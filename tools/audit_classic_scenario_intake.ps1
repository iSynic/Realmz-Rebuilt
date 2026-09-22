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
    [hashtable]$ScenarioSourceOverrides = @{},
    [string]$ProvidenceSlimmerPath = "",
    [string]$ApplicationPackagePath = "",
    [string]$ApplicationMediaCatalogPath = "",
    [string]$GodotPath = ""
)

$ErrorActionPreference = "Stop"
$repoRoot = Split-Path -Parent $PSScriptRoot
$ScenarioRoot = [IO.Path]::GetFullPath($ScenarioRoot)
$OutputRoot = [IO.Path]::GetFullPath($OutputRoot)
$requiredFiles = @($ProvidenceCliPath, $ProvidenceAdapterPath)
$requiredDirectories = @($ScenarioRoot, $ApplicationDataDirectory, $ApplicationLibraryRoot, $ReferenceCatalogRoot)
$slimEnabled = -not [string]::IsNullOrWhiteSpace($ProvidenceSlimmerPath)
if ($slimEnabled) {
    $requiredFiles += @($ProvidenceSlimmerPath, $ApplicationPackagePath, $ApplicationMediaCatalogPath)
} elseif (-not [string]::IsNullOrWhiteSpace($ApplicationPackagePath) -or -not [string]::IsNullOrWhiteSpace($ApplicationMediaCatalogPath)) {
    throw "Application package and media catalog require ProvidenceSlimmerPath."
}
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

function Request-CompleteValidation($Process, [ref]$RequestId) {
    $pages = @()
    $offset = 0
    $total = 0
    do {
        $page = Request-Adapter $Process $RequestId 'validation.list' @{
            offset = $offset
            limit = 128
        }
        $pages += $page
        $total = [int]$page.total
        $count = @($page.items).Count
        $next = $offset + $count
        if ($next -ge $total) { break }
        if (-not [bool]$page.truncated -or $count -eq 0) {
            throw "Providence validation.list returned an incomplete diagnostic page at offset $offset."
        }
        $offset = $next
    } while ($true)

    $items = @($pages | ForEach-Object { @($_.items) })
    $first = $pages[0]
    $groups = @($first.groups)
    $group_total = [int]$first.groupTotal
    $group_offset = $groups.Count
    while ($group_offset -lt $group_total) {
        $page = Request-Adapter $Process $RequestId 'validation.list' @{
            offset = 0
            limit = 1
            groupOffset = $group_offset
            groupLimit = 64
        }
        $page_groups = @($page.groups)
        if ($page_groups.Count -eq 0) {
            throw "Providence validation.list returned an incomplete diagnostic group page at offset $group_offset."
        }
        $groups += $page_groups
        $group_offset += $page_groups.Count
    }

    return [ordered]@{
        revision = $first.revision
        items = $items
        offset = 0
        limit = 128
        total = $total
        truncated = $false
        pages = $pages.Count
        groups = $groups
        groupOffset = 0
        groupLimit = 64
        groupTotal = $group_total
        groupsTruncated = $false
        unfilteredTotal = $first.unfilteredTotal
        matchedBeforeGroup = $first.matchedBeforeGroup
        unfilteredCounts = $first.unfilteredCounts
        categories = $first.categories
        complete = $items.Count -eq $total -and $groups.Count -eq $group_total
    }
}

function Request-CompleteReadiness($Process, [ref]$RequestId) {
    $pages = @()
    $offset = 0
    $total = 0
    do {
        $page = Request-Adapter $Process $RequestId 'project.inspect-rebuilt-readiness' @{
            offset = $offset
            limit = 200
        }
        $pages += $page
        $total = [int]$page.blockerCount
        $count = @($page.blockers).Count
        $next = $offset + $count
        if ($next -ge $total) { break }
        if (-not [bool]$page.truncated -or $count -eq 0) {
            throw "Providence readiness returned an incomplete blocker page at offset $offset."
        }
        $offset = $next
    } while ($true)

    $first = $pages[0]
    $blockers = @($pages | ForEach-Object { @($_.blockers) })
    $problems = @($first.problems)
    $problemCount = [int]$first.problemCount
    $problemPage = $first
    $problemPages = 1
    if ([int]$problemPage.problemOffset -ne 0) {
        throw "Providence readiness did not start its problem projection at offset zero."
    }
    while ([bool]$problemPage.problemsTruncated) {
        $nextProblemOffset = $problems.Count
        $problemPage = Request-Adapter $Process $RequestId 'project.inspect-rebuilt-readiness' @{
            offset = 0
            limit = 1
            problemOffset = $nextProblemOffset
            problemLimit = 200
        }
        if ([int]$problemPage.problemOffset -ne $nextProblemOffset) {
            throw "Providence readiness changed problem-page identity while paging."
        }
        $problemItems = @($problemPage.problems)
        if ($problemItems.Count -eq 0) {
            throw "Providence readiness returned an incomplete problem page."
        }
        $problems += $problemItems
        $problemPages++
        if ($problems.Count -gt $problemCount) {
            throw "Providence readiness returned more runtime problems than its denominator."
        }
    }
    $problems_complete = $problems.Count -eq $problemCount
    return [ordered]@{
        revision = $first.revision
        target = $first.target
        status = $first.status
        blockerCount = $total
        groupCount = $first.groupCount
        groups = @($first.groups)
        blockers = $blockers
        problemCount = $problemCount
        problems = $problems
        problemOffset = 0
        problemLimit = 200
        problemPages = $problemPages
        problemsTruncated = -not $problems_complete
        offset = 0
        limit = 200
        truncated = $false
        pages = $pages.Count
        complete = $blockers.Count -eq $total -and $problems_complete
        incompleteReason = if ($problems_complete) { $null } else { "Providence readiness returned an incomplete runtime problem projection." }
    }
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
    return "scenario-$($slug.Trim('-'))"
}

if ([string]::IsNullOrWhiteSpace($GodotPath)) {
    $GodotPath = Get-ChildItem "$env:LOCALAPPDATA\Microsoft\WinGet\Packages" -Recurse -Filter "Godot_v4.7.1-stable_win64_console.exe" -ErrorAction SilentlyContinue |
        Select-Object -First 1 -ExpandProperty FullName
}
$runtimeCommit = (& git -C $repoRoot rev-parse HEAD).Trim()
$adapterHash = (Get-FileHash -LiteralPath $ProvidenceAdapterPath -Algorithm SHA256).Hash.ToLowerInvariant()
$compilerIdentity = [ordered]@{
    cli = [ordered]@{
        path=[IO.Path]::GetFullPath($ProvidenceCliPath)
        bytes=(Get-Item -LiteralPath $ProvidenceCliPath).Length
        sha256=(Get-FileHash -LiteralPath $ProvidenceCliPath -Algorithm SHA256).Hash.ToLowerInvariant()
    }
    adapter = [ordered]@{
        path=[IO.Path]::GetFullPath($ProvidenceAdapterPath)
        bytes=(Get-Item -LiteralPath $ProvidenceAdapterPath).Length
        sha256=$adapterHash
    }
}
if ($slimEnabled) {
    $compilerIdentity.slimmer = [ordered]@{
        path=[IO.Path]::GetFullPath($ProvidenceSlimmerPath)
        bytes=(Get-Item -LiteralPath $ProvidenceSlimmerPath).Length
        sha256=(Get-FileHash -LiteralPath $ProvidenceSlimmerPath -Algorithm SHA256).Hash.ToLowerInvariant()
    }
    $compilerIdentity.applicationPackageSha256 = (Get-FileHash -LiteralPath $ApplicationPackagePath -Algorithm SHA256).Hash.ToLowerInvariant()
    $compilerIdentity.applicationMediaCatalogSha256 = (Get-FileHash -LiteralPath $ApplicationMediaCatalogPath -Algorithm SHA256).Hash.ToLowerInvariant()
}
$applicationDataIdentity = Get-TreeIdentity $ApplicationDataDirectory
$applicationLibraryIdentity = Get-TreeIdentity $ApplicationLibraryRoot
$referenceCatalogIdentity = Get-TreeIdentity $ReferenceCatalogRoot
$bundledCatalog = Get-Content -LiteralPath (Join-Path $repoRoot 'src/storage/packages/bundled_campaigns/castle-bundled-scenarios.provenance.json') -Raw | ConvertFrom-Json
$results = @()

foreach ($name in @($ScenarioName | Select-Object -Unique)) {
    $source = Join-Path $ScenarioRoot $name
    $bundledEntry = @($bundledCatalog.scenarios | Where-Object name -EQ $name)
    $sourceOverride = if ($bundledEntry.Count -eq 1) { $bundledEntry[0].sourceOverride } else { $null }
    if ($ScenarioSourceOverrides.ContainsKey($name)) {
        $source = $ScenarioSourceOverrides[$name]
    }
    $slug = Get-Slug $name
    $project = Join-Path $OutputRoot "projects\$slug"
    $package = Join-Path $OutputRoot "packages\$slug.realmz2"
    $entry = [ordered]@{
        name=$name
        sourcePath=[IO.Path]::GetFullPath($source)
        sourceIdentity=$null
        designatedSnapshotSha256=if ($sourceOverride) { $sourceOverride.snapshotSha256 } else { $null }
        sourceCatalogVerified=if ($sourceOverride) { $false } else { $null }
        status="pending"
        stages=[ordered]@{
            monsterCatalog="not-run"
            import="not-run"
            diagnostics="not-run"
            readiness="not-run"
            compilation="not-run"
            finalization="not-run"
            packageValidation="not-run"
            startup="not-run"
        }
        import=$null
        monsterCatalog=$null
        diagnostics=$null
        readiness=$null
        package=$null
        finalPackage=$null
        projectPath=[IO.Path]::GetFullPath($project)
        packagePath=[IO.Path]::GetFullPath($package)
        runtimeProbe=$null
        failure=$null
    }
    if (-not (Test-Path -LiteralPath $source -PathType Container)) {
        $entry.status = "source-missing"
        $entry.failure = "Scenario directory is missing."
        $results += $entry
        continue
    }
    $entry.sourceIdentity = Get-TreeIdentity $source
    if ($sourceOverride) {
        $sourceCatalogPath = Join-Path $repoRoot "src/storage/packages/bundled_campaigns/$($sourceOverride.catalog)"
        $sourceCatalog = Get-Content -LiteralPath $sourceCatalogPath -Raw | ConvertFrom-Json
        $expectedFiles = @($sourceCatalog.files)
        $actualFiles = @($entry.sourceIdentity.files)
        $actualByPath = @{}
        foreach ($actualFile in $actualFiles) { $actualByPath[[string]$actualFile['path']] = $actualFile }
        $matchingFiles = $actualFiles.Count -eq $expectedFiles.Count
        $mismatchDetail = "count $($actualFiles.Count)/$($expectedFiles.Count)"
        if ($matchingFiles) {
            foreach ($expectedFile in $expectedFiles) {
                $actualFile = $actualByPath[[string]$expectedFile.file]
                if ($null -eq $actualFile -or
                    [long]$expectedFile.bytes -ne [long]$actualFile['bytes'] -or
                    $expectedFile.sha256 -ne $actualFile['sha256']) {
                    $matchingFiles = $false
                    $mismatchDetail = "file $($expectedFile.file)"
                    break
                }
            }
        }
        if (-not $matchingFiles -or $sourceCatalog.snapshot.fileCount -ne $entry.sourceIdentity.fileCount -or
            $sourceCatalog.snapshot.bytes -ne $entry.sourceIdentity.byteCount -or
            $sourceCatalog.snapshot.sha256 -ne $sourceOverride.snapshotSha256) {
            $entry.status = "source-identity-mismatch"
            $entry.failure = "Designated source files do not match the bundled provenance catalog: $mismatchDetail."
            $results += $entry
            continue
        }
        $entry.sourceCatalogVerified = $true
    }
    $monsterInputs = @('Data MD', 'Data MD1', 'Data MD-1', 'Data DES', 'Data ED3') |
        ForEach-Object { Join-Path $source $_ }
    $missingMonsterInputs = @($monsterInputs | Where-Object { -not (Test-Path -LiteralPath $_ -PathType Leaf) })
    if ($missingMonsterInputs.Count -gt 0) {
        $entry.stages.monsterCatalog = "unsupported"
        $entry.monsterCatalog = [ordered]@{ complete=$false; reason="Missing native Monster catalog input(s): $($missingMonsterInputs -join ', ')" }
    } else {
        $monsterOutput = (& $ProvidenceCliPath inspect-monster-catalog @monsterInputs 2>&1 | Out-String).Trim()
        try {
            $monsterReport = $monsterOutput | ConvertFrom-Json -ErrorAction Stop
            $entry.monsterCatalog = $monsterReport
            $entry.stages.monsterCatalog = if ($monsterReport.projectionComplete -eq $true) { "passed" } else { "incomplete" }
        } catch {
            $entry.stages.monsterCatalog = "incomplete"
            $entry.monsterCatalog = [ordered]@{ complete=$false; reason=$monsterOutput }
        }
    }
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
        $entry.stages.import = "passed"
        $entry.diagnostics = Request-CompleteValidation $adapter ([ref]$requestId)
        if ($entry.diagnostics.complete) { $entry.stages.diagnostics = "passed" } else { $entry.stages.diagnostics = "incomplete" }
        $readiness = Request-CompleteReadiness $adapter ([ref]$requestId)
        $entry.readiness = $readiness
        if ($readiness.complete) { $entry.stages.readiness = "passed" } else { $entry.stages.readiness = "incomplete" }
        if ($readiness.status -ne 'ready') {
            $entry.status = "readiness-blocked"
            $entry.failure = "Providence Rebuilt readiness is incomplete."
        } else {
            [IO.Directory]::CreateDirectory((Split-Path -Parent $package)) | Out-Null
            $inspection = Request-Adapter $adapter ([ref]$requestId) 'project.inspect-rebuilt-package' @{compilerCommit=$ProvidenceCommit; minimumEngineVersion='0.1.0'; limit=200}
            $compiled = Request-Adapter $adapter ([ref]$requestId) 'project.compile-rebuilt-package' @{path=$package; compilerCommit=$ProvidenceCommit; minimumEngineVersion='0.1.0'; expectedRevision=$import.revision}
            $entry.stages.compilation = "passed"
            $entry.package = [ordered]@{
                archiveBytes=(Get-Item -LiteralPath $package).Length
                archiveSha256=(Get-FileHash -LiteralPath $package -Algorithm SHA256).Hash.ToLowerInvariant()
                inspection=$inspection
                compilation=$compiled
            }
            $entry.stages.packageValidation = "pending"
            $entry.status = "compiled"
        }
    } catch {
        if ($entry.stages.import -eq "not-run") {
            $entry.stages.import = "failed"
        } elseif ($entry.stages.diagnostics -eq "not-run") {
            $entry.stages.diagnostics = "failed"
        } elseif ($entry.stages.readiness -eq "not-run") {
            $entry.stages.readiness = "failed"
        } elseif ($entry.stages.compilation -eq "not-run") {
            $entry.stages.compilation = "failed"
        } else {
            $entry.stages.packageValidation = "failed"
        }
        if ($entry.status -eq "pending") { $entry.status = "intake-failed" }
        $entry.failure = $_.Exception.Message
    } finally {
        $adapterError = Stop-Adapter $adapter
        if ($adapterError -and -not $entry.failure) { $entry.failure = $adapterError.Trim() }
    }
    $probePackage = $package
    if ($entry.status -eq 'compiled' -and $slimEnabled) {
        try {
            $slimInput = Join-Path $OutputRoot "slim-input\$slug"
            $slimOutput = Join-Path $OutputRoot "final-packages\$slug"
            [IO.Directory]::CreateDirectory($slimInput) | Out-Null
            [IO.Directory]::CreateDirectory($slimOutput) | Out-Null
            Copy-Item -LiteralPath $package -Destination $slimInput
            $ownershipRoot = $ScenarioRoot
            if ([IO.Path]::GetFullPath($source) -ne [IO.Path]::GetFullPath((Join-Path $ScenarioRoot $name))) {
                $ownershipRoot = Join-Path $OutputRoot "ownership-sources\$slug"
                $ownershipScenario = Join-Path $ownershipRoot $name
                [IO.Directory]::CreateDirectory($ownershipScenario) | Out-Null
                foreach ($sourceFile in Get-ChildItem -LiteralPath $source -Force) {
                    Copy-Item -LiteralPath $sourceFile.FullName -Destination $ownershipScenario -Recurse
                }
            }
            $slimLock = Join-Path $slimOutput 'scenario-library.lock.json'
            $slimOutputText = (& $ProvidenceSlimmerPath slim-scenarios --application-package $ApplicationPackagePath --application-media-catalog $ApplicationMediaCatalogPath --classic-application-data $ApplicationDataDirectory --classic-scenarios-root $ownershipRoot --input-dir $slimInput --output-dir $slimOutput --lock $slimLock --commit $ProvidenceCommit 2>&1 | Out-String).Trim()
            if ($LASTEXITCODE -ne 0) { throw "Providence scenario finalization failed: $slimOutputText" }
            $lock = Get-Content -LiteralPath $slimLock -Raw | ConvertFrom-Json
            if ($lock.scenarios.Count -ne 1 -or $lock.scenarios[0].campaignId -ne $slug) {
                throw "Providence scenario finalization returned a different campaign identity."
            }
            $probePackage = Join-Path $slimOutput "$slug.realmz2"
            $entry.finalPackage = [ordered]@{
                path=[IO.Path]::GetFullPath($probePackage)
                archiveBytes=(Get-Item -LiteralPath $probePackage).Length
                archiveSha256=(Get-FileHash -LiteralPath $probePackage -Algorithm SHA256).Hash.ToLowerInvariant()
                packageHash=$lock.scenarios[0].packageHash
                contentId=$lock.scenarios[0].contentId
                ownershipSource=$lock.scenarios[0].ownershipSource
                removed=$lock.scenarios[0].removed
                retained=$lock.scenarios[0].retained
            }
            $entry.stages.finalization = "passed"
            $entry.status = "finalized"
        } catch {
            $entry.stages.finalization = "failed"
            $entry.status = "finalization-blocked"
            $entry.failure = $_.Exception.Message
        }
    } elseif ($entry.status -eq 'compiled') {
        $entry.stages.finalization = "unsupported"
    }
    if ($entry.status -in @('compiled', 'finalized') -and $GodotPath) {
        $probeOutput = (& $GodotPath --headless --path $repoRoot --script res://tools/package_probe.gd -- $probePackage 2>&1 | Out-String).Trim()
        $entry.runtimeProbe = [ordered]@{ exitCode=$LASTEXITCODE; output=$probeOutput }
        $packageAccepted = $probeOutput -match '(?m)^PACKAGE_VALIDATED\b'
        if ($packageAccepted) { $entry.stages.packageValidation = "passed" } else { $entry.stages.packageValidation = "failed" }
        if ($LASTEXITCODE -eq 0) { $entry.stages.startup = "passed" } else { $entry.stages.startup = "failed" }
        if ($LASTEXITCODE -eq 0) {
            $entry.status = if ($slimEnabled) { "loadable" } else { "intermediate-loadable" }
        } elseif ($packageAccepted) {
            $entry.status = "startup-blocked"
            $entry.failure = "Rebuilt package was accepted but session startup or view construction failed."
        } else {
            $entry.status = "package-validation-blocked"
            $entry.failure = "Rebuilt package probe rejected the compiled archive before startup."
        }
    } elseif ($entry.status -in @('compiled', 'finalized')) {
        $entry.stages.packageValidation = "unsupported"
        $entry.stages.startup = "unsupported"
        $entry.status = if ($slimEnabled) { "finalized" } else { "compiled" }
        $entry.failure = "Godot package startup probe was not configured."
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
    compiler=$compilerIdentity
    applicationDataIdentity=[ordered]@{ root=[IO.Path]::GetFullPath($ApplicationDataDirectory); fileCount=$applicationDataIdentity.fileCount; byteCount=$applicationDataIdentity.byteCount; treeSha256=$applicationDataIdentity.treeSha256 }
    applicationLibraryIdentity=[ordered]@{ root=[IO.Path]::GetFullPath($ApplicationLibraryRoot); fileCount=$applicationLibraryIdentity.fileCount; byteCount=$applicationLibraryIdentity.byteCount; treeSha256=$applicationLibraryIdentity.treeSha256 }
    referenceCatalogIdentity=[ordered]@{ root=[IO.Path]::GetFullPath($ReferenceCatalogRoot); fileCount=$referenceCatalogIdentity.fileCount; byteCount=$referenceCatalogIdentity.byteCount; treeSha256=$referenceCatalogIdentity.treeSha256 }
    scenarioCount=$results.Count
    results=$results
}
$reportPath = Join-Path $OutputRoot 'intake-report.json'
[IO.File]::WriteAllText($reportPath, ($report | ConvertTo-Json -Depth 40), [Text.UTF8Encoding]::new($false))
Write-Host "Classic scenario intake report: $reportPath"
