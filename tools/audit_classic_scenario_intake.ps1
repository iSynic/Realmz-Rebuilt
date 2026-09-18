param(
    [Parameter(Mandatory)][string]$ScenarioRoot,
    [Parameter(Mandatory)][string[]]$ScenarioName,
    [Parameter(Mandatory)][string]$ProvidenceCliPath,
    [Parameter(Mandatory)][string]$ProvidenceAdapterPath,
    [Parameter(Mandatory)][string]$ProvidenceCommit,
    [Parameter(Mandatory)][string]$ApplicationDataDirectory,
    [Parameter(Mandatory)][string]$ApplicationLibraryRoot,
    [Parameter(Mandatory)][string]$ReferenceCatalogRoot,
    [Parameter(Mandatory)][string]$OutputRoot,
    [string]$GodotPath = ""
)

$ErrorActionPreference = "Stop"
$repoRoot = Split-Path -Parent $PSScriptRoot
$ScenarioRoot = [IO.Path]::GetFullPath($ScenarioRoot)
$OutputRoot = [IO.Path]::GetFullPath($OutputRoot)
$requiredFiles = @($ProvidenceCliPath, $ProvidenceAdapterPath)
$requiredDirectories = @($ScenarioRoot, $ApplicationDataDirectory, $ApplicationLibraryRoot, $ReferenceCatalogRoot)
foreach ($path in $requiredFiles) {
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { throw "Missing required file: $path" }
}
foreach ($path in $requiredDirectories) {
    if (-not (Test-Path -LiteralPath $path -PathType Container)) { throw "Missing required directory: $path" }
}
if (Test-Path -LiteralPath $OutputRoot) { throw "Choose a new output root; intake evidence is never overwritten." }
[IO.Directory]::CreateDirectory($OutputRoot) | Out-Null

function Get-TreeIdentity([string]$Root) {
    $entries = @()
    [long]$byteCount = 0
    foreach ($file in Get-ChildItem -LiteralPath $Root -File -Recurse | Sort-Object FullName) {
        $relative = [IO.Path]::GetRelativePath($Root, $file.FullName).Replace('\', '/')
        $hash = (Get-FileHash -LiteralPath $file.FullName -Algorithm SHA256).Hash.ToLowerInvariant()
        $byteCount += $file.Length
        $entries += [ordered]@{ path=$relative; bytes=$file.Length; sha256=$hash }
    }
    $identityText = ($entries | ForEach-Object { "$($_.path)`t$($_.bytes)`t$($_.sha256)" }) -join "`n"
    $identityBytes = [Text.Encoding]::UTF8.GetBytes($identityText)
    return [ordered]@{
        fileCount=$entries.Count
        byteCount=$byteCount
        treeSha256=[Convert]::ToHexString([Security.Cryptography.SHA256]::HashData($identityBytes)).ToLowerInvariant()
        files=$entries
    }
}

function Start-Adapter([string]$ProjectRoot) {
    $start = [Diagnostics.ProcessStartInfo]::new()
    $start.FileName = $ProvidenceAdapterPath
    $start.UseShellExecute = $false
    $start.CreateNoWindow = $true
    $start.RedirectStandardInput = $true
    $start.RedirectStandardOutput = $true
    $start.RedirectStandardError = $true
    foreach ($argument in @('serve-project', $ProjectRoot, '--application-library-root', $ApplicationLibraryRoot, '--reference-catalog-root', $ReferenceCatalogRoot)) {
        $start.ArgumentList.Add($argument)
    }
    return [Diagnostics.Process]::Start($start)
}

function Request-Adapter($Process, [ref]$RequestId, [string]$Method, [hashtable]$Parameters = @{}) {
    $RequestId.Value++
    $request = @{id=$RequestId.Value; method=$Method; params=$Parameters} | ConvertTo-Json -Depth 30 -Compress
    $Process.StandardInput.WriteLine($request)
    $Process.StandardInput.Flush()
    $pending = $Process.StandardOutput.ReadLineAsync()
    if (-not $pending.Wait(240000)) { throw "Adapter timed out during $Method" }
    if ($null -eq $pending.Result) { throw "Adapter closed during $Method" }
    $response = $pending.Result | ConvertFrom-Json -AsHashtable
    if ($response.id -ne $RequestId.Value) { throw "Adapter response identity changed during $Method" }
    if (-not $response.ok) { throw "$Method`: $($response.error)" }
    return $response.result
}

function Stop-Adapter($Process) {
    if ($null -eq $Process) { return "" }
    $Process.StandardInput.Close()
    if (-not $Process.WaitForExit(10000)) { $Process.Kill($true) }
    $stderr = $Process.StandardError.ReadToEnd()
    $Process.Dispose()
    return $stderr
}

function Get-Slug([string]$Name) {
    $slug = $Name.ToLowerInvariant() -replace '[^a-z0-9]+', '-'
    return $slug.Trim('-')
}

if ([string]::IsNullOrWhiteSpace($GodotPath)) {
    $GodotPath = Get-ChildItem "$env:LOCALAPPDATA\Microsoft\WinGet\Packages" -Recurse -Filter "Godot_v4.7.1-stable_win64_console.exe" -ErrorAction SilentlyContinue |
        Select-Object -First 1 -ExpandProperty FullName
}
$runtimeCommit = (& git -C $repoRoot rev-parse HEAD).Trim()
$adapterHash = (Get-FileHash -LiteralPath $ProvidenceAdapterPath -Algorithm SHA256).Hash.ToLowerInvariant()
$results = @()

foreach ($name in @($ScenarioName | Select-Object -Unique)) {
    $source = Join-Path $ScenarioRoot $name
    $slug = Get-Slug $name
    $project = Join-Path $OutputRoot "projects\$slug"
    $package = Join-Path $OutputRoot "packages\$slug.realmz2"
    $entry = [ordered]@{
        name=$name
        sourceIdentity=$null
        status="conversion-blocked"
        import=$null
        readiness=$null
        package=$null
        runtimeProbe=$null
        failure=$null
    }
    if (-not (Test-Path -LiteralPath $source -PathType Container)) {
        $entry.failure = "Scenario directory is missing."
        $results += $entry
        continue
    }
    $entry.sourceIdentity = Get-TreeIdentity $source
    $adapter = $null
    try {
        [IO.Directory]::CreateDirectory((Split-Path -Parent $project)) | Out-Null
        $newOutput = (& $ProvidenceCliPath project-new $slug $project 2>&1 | Out-String).Trim()
        if ($LASTEXITCODE -ne 0) { throw "Providence project creation failed: $newOutput" }
        $adapter = Start-Adapter $project
        $requestId = 0
        $description = Request-Adapter $adapter ([ref]$requestId) 'session.describe'
        $import = Request-Adapter $adapter ([ref]$requestId) 'project.import-classic-scenario' @{
            expectedRevision=$description.revision
            directory=$source
            applicationDataDirectory=$ApplicationDataDirectory
        }
        $entry.import = $import
        $readiness = Request-Adapter $adapter ([ref]$requestId) 'project.inspect-rebuilt-readiness' @{limit=200}
        $entry.readiness = $readiness
        if ($readiness.status -ne 'ready') {
            $entry.failure = "Providence Rebuilt readiness is incomplete."
        } else {
            [IO.Directory]::CreateDirectory((Split-Path -Parent $package)) | Out-Null
            $inspection = Request-Adapter $adapter ([ref]$requestId) 'project.inspect-rebuilt-package' @{compilerCommit=$ProvidenceCommit; minimumEngineVersion='0.1.0'; limit=200}
            $compiled = Request-Adapter $adapter ([ref]$requestId) 'project.compile-rebuilt-package' @{path=$package; compilerCommit=$ProvidenceCommit; minimumEngineVersion='0.1.0'; expectedRevision=$import.revision}
            $entry.package = [ordered]@{
                archiveBytes=(Get-Item -LiteralPath $package).Length
                archiveSha256=(Get-FileHash -LiteralPath $package -Algorithm SHA256).Hash.ToLowerInvariant()
                inspection=$inspection
                compilation=$compiled
            }
            $entry.status = "loadable"
        }
    } catch {
        $entry.failure = $_.Exception.Message
    } finally {
        $adapterError = Stop-Adapter $adapter
        if ($adapterError -and -not $entry.failure) { $entry.failure = $adapterError.Trim() }
    }
    if ($entry.status -eq 'loadable' -and $GodotPath) {
        $probeOutput = (& $GodotPath --headless --path $repoRoot --script res://tools/package_probe.gd -- $package 2>&1 | Out-String).Trim()
        $entry.runtimeProbe = [ordered]@{ exitCode=$LASTEXITCODE; output=$probeOutput }
        if ($LASTEXITCODE -ne 0) {
            $entry.status = "conversion-blocked"
            $entry.failure = "Rebuilt package probe rejected the compiled archive."
        }
    }
    $results += $entry
    Write-Host "$name`: $($entry.status)"
}

$report = [ordered]@{
    kind="realmz-rebuilt.classic-scenario-intake"
    formatVersion=1
    generatedAt=(Get-Date).ToUniversalTime().ToString('o')
    runtimeCommit=$runtimeCommit
    providenceCommit=$ProvidenceCommit
    providenceAdapterSha256=$adapterHash
    scenarioCount=$results.Count
    results=$results
}
$reportPath = Join-Path $OutputRoot 'intake-report.json'
[IO.File]::WriteAllText($reportPath, ($report | ConvertTo-Json -Depth 40), [Text.UTF8Encoding]::new($false))
Write-Host "Classic scenario intake report: $reportPath"
