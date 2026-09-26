param(
    [Parameter(Mandatory)][string]$Url,
    [Parameter(Mandatory)][ValidatePattern('^[0-9a-fA-F]{64}$')][string]$ExpectedSha256,
    [Parameter(Mandatory)][string]$DestinationRoot,
    [Parameter(Mandatory)][string]$ExpectedPlatform
)

$ErrorActionPreference = "Stop"
$ExpectedSha256 = $ExpectedSha256.ToLowerInvariant()
try { $uri = [Uri]$Url } catch { throw "Scenario importer URL is not a valid absolute URL." }
if ($uri.Scheme -ne "https" -or $uri.AbsolutePath -notmatch "/releases/download/[^/]+/[^/]+$") {
    throw "Scenario importer URL must identify a versioned HTTPS release asset (not a mutable latest URL)."
}
if ($ExpectedPlatform -notin @("windows", "linux", "macos")) { throw "ExpectedPlatform must be windows, linux, or macos." }

$DestinationRoot = [IO.Path]::GetFullPath($DestinationRoot)
if (Test-Path -LiteralPath $DestinationRoot) {
    if (-not (Test-Path -LiteralPath $DestinationRoot -PathType Container) -or @(Get-ChildItem -LiteralPath $DestinationRoot -Force).Count -ne 0) {
        throw "Importer destination must be new or empty; existing output is preserved."
    }
}
$parent = Split-Path -Parent $DestinationRoot
[IO.Directory]::CreateDirectory($parent) | Out-Null
$stage = Join-Path $parent (".scenario-importer-download-" + [Guid]::NewGuid().ToString("N"))
$archivePath = Join-Path $stage "artifact.zip"
$extractRoot = Join-Path $stage "extract"

function Assert-Condition([bool]$Condition, [string]$Message) {
    if (-not $Condition) { throw $Message }
}

function Get-Sha256([string]$Path) {
    return (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash.ToLowerInvariant()
}

try {
    [IO.Directory]::CreateDirectory($stage) | Out-Null
    Invoke-WebRequest -Uri $uri -OutFile $archivePath
    Assert-Condition ((Get-Sha256 $archivePath) -ceq $ExpectedSha256) "Downloaded scenario importer release asset SHA-256 does not match the configured pin."
    Add-Type -AssemblyName System.IO.Compression.FileSystem
    $archive = [IO.Compression.ZipFile]::OpenRead($archivePath)
    try {
        foreach ($entry in $archive.Entries) {
            $name = $entry.FullName.Replace('\', '/')
            Assert-Condition (-not $name.StartsWith('/') -and -not $name.Contains(':') -and -not @($name.Split('/')).Contains('..')) "Scenario importer archive contains an unsafe path: $name"
            $unixMode = ($entry.ExternalAttributes -shr 16) -band 0xF000
            Assert-Condition ($unixMode -eq 0 -or $unixMode -eq 0x8000 -or $unixMode -eq 0x4000) "Scenario importer archive contains a link or special file: $name"
        }
        [IO.Directory]::CreateDirectory($extractRoot) | Out-Null
        [IO.Compression.ZipFile]::ExtractToDirectory($archivePath, $extractRoot)
    } finally {
        $archive.Dispose()
    }

    $manifestPath = Join-Path $extractRoot "build-manifest.json"
    Assert-Condition (Test-Path -LiteralPath $manifestPath -PathType Leaf) "Versioned scenario importer is missing build-manifest.json."
    $manifest = Get-Content -LiteralPath $manifestPath -Raw | ConvertFrom-Json
    Assert-Condition ($manifest.kind -ceq "realmz-rebuilt.scenario-importer-build" -and [int]$manifest.formatVersion -eq 1) "Versioned scenario importer manifest kind or version is unsupported."
    Assert-Condition ($manifest.buildIdentity.profile -ceq "release" -and -not [bool]$manifest.buildIdentity.sourceDirty) "Versioned scenario importer must report a clean release-profile source build."
    $target = [string]$manifest.buildIdentity.target
    $binaryName = [string]$manifest.executable.path
    $expectedBinary = "providence-native-adapter" + $(if ($ExpectedPlatform -eq "windows") { ".exe" } else { "" })
    Assert-Condition ($binaryName -ceq $expectedBinary) "Scenario importer executable name does not match its target platform."

    $expectedFiles = @(".gdignore", "build-manifest.json", $binaryName)
    $binaryPath = Join-Path $extractRoot $binaryName
    Assert-Condition (Test-Path -LiteralPath $binaryPath -PathType Leaf) "Scenario importer executable is missing."
    Assert-Condition ((Get-Item -LiteralPath $binaryPath).Length -eq [long]$manifest.executable.bytes -and (Get-Sha256 $binaryPath) -ceq [string]$manifest.executable.sha256) "Scenario importer executable does not match its build manifest."
    & (Join-Path $PSScriptRoot "verify_scenario_importer_platform.ps1") -ExpectedPlatform $ExpectedPlatform -Target $target -ExecutablePath $binaryPath
    foreach ($record in $manifest.supportFiles) {
        $relative = [string]$record.path
        Assert-Condition (-not [string]::IsNullOrWhiteSpace($relative) -and -not [IO.Path]::IsPathRooted($relative) -and -not $relative.Contains('\') -and -not @($relative.Split('/')).Contains('..')) "Scenario importer support manifest contains an unsafe path."
        $path = Join-Path (Join-Path $extractRoot "support") ($relative.Replace('/', [IO.Path]::DirectorySeparatorChar))
        Assert-Condition (Test-Path -LiteralPath $path -PathType Leaf) "Scenario importer support file is missing: $relative"
        Assert-Condition ((Get-Item -LiteralPath $path).Length -eq [long]$record.bytes -and (Get-Sha256 $path) -ceq [string]$record.sha256) "Scenario importer support file failed its manifest check: $relative"
        $expectedFiles += "support/$relative"
    }
    $actualFiles = @(Get-ChildItem -LiteralPath $extractRoot -File -Recurse -Force | ForEach-Object {
        [IO.Path]::GetFullPath($_.FullName).Substring(([IO.Path]::GetFullPath($extractRoot).TrimEnd('\', '/') + [IO.Path]::DirectorySeparatorChar).Length).Replace('\', '/')
    })
    $differences = @(Compare-Object ($expectedFiles | Sort-Object) ($actualFiles | Sort-Object))
    Assert-Condition ($differences.Count -eq 0) "Scenario importer release archive contains unexpected or missing files."

    if (Test-Path -LiteralPath $DestinationRoot) { [IO.Directory]::Delete($DestinationRoot, $false) }
    [IO.Directory]::Move($extractRoot, $DestinationRoot)
    if ($ExpectedPlatform -ne "windows") {
        & chmod 755 (Join-Path $DestinationRoot $binaryName)
        Assert-Condition ($LASTEXITCODE -eq 0) "Could not mark the installed scenario importer executable."
    }
} catch {
    if ((Test-Path -LiteralPath $DestinationRoot -PathType Container) -and @(Get-ChildItem -LiteralPath $DestinationRoot -Force).Count -eq 0) {
        [IO.Directory]::Delete($DestinationRoot, $false)
    }
    throw
} finally {
    if (Test-Path -LiteralPath $stage -PathType Container) { [IO.Directory]::Delete($stage, $true) }
}

Write-Output "Verified scenario importer $($manifest.buildIdentity.commit) ($target) installed at $DestinationRoot"
