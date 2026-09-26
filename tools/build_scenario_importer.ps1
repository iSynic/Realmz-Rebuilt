<#
.SYNOPSIS
Builds the Providence native scenario importer and assembles its local support directory.

.DESCRIPTION
Builds providence-native-adapter from the supplied Providence checkout and records its actual
embedded identity and source changes. Release builds additionally require a clean checkout and
an accepted release identity. Packages only importer support files beneath OutputRoot. The
existing Rebuilt application package is never copied here; the runtime supplies it per job.

.EXAMPLE
./tools/build_scenario_importer.ps1 -ProvidenceSource C:/src/providence-current-compiler `
  -ApplicationDataDirectory C:/Realmz/'Data Files' `
  -ApplicationLibraryRoot C:/providence/application-library `
  -ApplicationMediaCatalogPath C:/providence/application-library/media.json
#>
param(
    [Parameter(Mandatory)][string]$ProvidenceSource,
    [Parameter(Mandatory)][string]$ApplicationDataDirectory,
    [Parameter(Mandatory)][string]$ApplicationLibraryRoot,
    [Parameter(Mandatory)][string]$ApplicationMediaCatalogPath,
    [string]$OutputRoot = "",
    [string]$ToolchainLockPath = "",
    [switch]$Release,
    [string]$ReleaseIdentityPath = ""
)

$ErrorActionPreference = "Stop"
$repoRoot = Split-Path -Parent $PSScriptRoot
if ([string]::IsNullOrWhiteSpace($OutputRoot)) {
    $OutputRoot = Join-Path $repoRoot "importer"
}
$OutputRoot = [IO.Path]::GetFullPath($OutputRoot)
$ProvidenceSource = [IO.Path]::GetFullPath($ProvidenceSource)
$ApplicationDataDirectory = [IO.Path]::GetFullPath($ApplicationDataDirectory)
$ApplicationLibraryRoot = [IO.Path]::GetFullPath($ApplicationLibraryRoot)
$ApplicationMediaCatalogPath = [IO.Path]::GetFullPath($ApplicationMediaCatalogPath)

function Assert-Condition([bool]$Condition, [string]$Message) {
    if (-not $Condition) { throw $Message }
}

function Get-Sha256([string]$Path) {
    return (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash.ToLowerInvariant()
}

function Get-ManifestFiles([string]$Root) {
    $resolvedRoot = [IO.Path]::GetFullPath($Root).TrimEnd('\', '/')
    $prefix = $resolvedRoot + [IO.Path]::DirectorySeparatorChar
    $files = @()
    foreach ($entry in Get-ChildItem -LiteralPath $Root -Recurse -Force) {
        Assert-Condition (($entry.Attributes -band [IO.FileAttributes]::ReparsePoint) -eq 0) "Support inputs may not contain reparse points: $($entry.FullName)"
    }
    foreach ($file in Get-ChildItem -LiteralPath $Root -File -Recurse -Force | Sort-Object FullName) {
        Assert-Condition (($file.Attributes -band [IO.FileAttributes]::ReparsePoint) -eq 0) "Support inputs may not contain reparse points: $($file.FullName)"
        $resolvedFile = [IO.Path]::GetFullPath($file.FullName)
        Assert-Condition ($resolvedFile.StartsWith($prefix, [StringComparison]::OrdinalIgnoreCase)) "A support file escaped its source root: $resolvedFile"
        $relativePath = $resolvedFile.Substring($prefix.Length).Replace('\', '/')
        $files += [ordered]@{
            path = $relativePath
            bytes = [long]$file.Length
            sha256 = Get-Sha256 $file.FullName
        }
    }
    return $files
}

function Get-TreeIdentity([string]$Root) {
    $rootFiles = @(Get-ManifestFiles $Root)
    [long]$byteCount = 0
    $identityLines = @()
    foreach ($file in $rootFiles) {
        $byteCount += [long]$file.bytes
        $identityLines += "$($file.path)`t$($file.bytes)`t$($file.sha256)"
    }
    $identityBytes = [Text.Encoding]::UTF8.GetBytes(($identityLines -join "`n"))
    $sha = [Security.Cryptography.SHA256]::Create()
    try {
        $treeHash = ([BitConverter]::ToString($sha.ComputeHash($identityBytes))).Replace('-', '').ToLowerInvariant()
    } finally {
        $sha.Dispose()
    }
    return [ordered]@{
        fileCount = $rootFiles.Count
        byteCount = $byteCount
        treeSha256 = $treeHash
    }
}

function Copy-SupportTree([string]$SourceRoot, [string]$DestinationRoot) {
    [IO.Directory]::CreateDirectory($DestinationRoot) | Out-Null
    $resolvedSourceRoot = [IO.Path]::GetFullPath($SourceRoot).TrimEnd('\', '/')
    $sourcePrefix = $resolvedSourceRoot + [IO.Path]::DirectorySeparatorChar
    foreach ($file in Get-ChildItem -LiteralPath $SourceRoot -File -Recurse -Force | Sort-Object FullName) {
        Assert-Condition (($file.Attributes -band [IO.FileAttributes]::ReparsePoint) -eq 0) "Support inputs may not contain reparse points: $($file.FullName)"
        $resolvedFile = [IO.Path]::GetFullPath($file.FullName)
        Assert-Condition ($resolvedFile.StartsWith($sourcePrefix, [StringComparison]::OrdinalIgnoreCase)) "A support file escaped its source root: $resolvedFile"
        $relative = $resolvedFile.Substring($sourcePrefix.Length)
        $target = Join-Path $DestinationRoot $relative
        $targetParent = Split-Path -Parent $target
        [IO.Directory]::CreateDirectory($targetParent) | Out-Null
        Copy-Item -LiteralPath $file.FullName -Destination $target
    }
}

function Write-Utf8Json([string]$Path, $Value) {
    $json = ConvertTo-Json -InputObject $Value -Depth 16
    [IO.File]::WriteAllText($Path, $json + "`n", [Text.UTF8Encoding]::new($false))
}

function Get-SourceChanges([string]$Root) {
    $lines = @(& git -C $Root status --porcelain --untracked-files=all)
    Assert-Condition ($LASTEXITCODE -eq 0) "Could not inspect Providence source changes."
    $changes = @()
    foreach ($line in $lines) {
        if ([string]::IsNullOrWhiteSpace($line)) { continue }
        $state = $line.Substring(0, 2).Trim()
        $relative = $line.Substring(3).Trim()
        if ($relative.Contains(" -> ")) { $relative = $relative.Substring($relative.LastIndexOf(" -> ", [StringComparison]::Ordinal) + 4) }
        $relative = $relative.Trim('"').Replace('\', '/')
        $candidate = Join-Path $Root $relative
        $entry = [ordered]@{ path = $relative; state = $state; bytes = $null; sha256 = $null }
        if (Test-Path -LiteralPath $candidate -PathType Leaf) {
            $file = Get-Item -LiteralPath $candidate
            $entry.bytes = [long]$file.Length
            $entry.sha256 = Get-Sha256 $candidate
        }
        $changes += $entry
    }
    return $changes
}

if (Test-Path -LiteralPath $OutputRoot) {
    Assert-Condition (Test-Path -LiteralPath $OutputRoot -PathType Container) "OutputRoot exists but is not a directory."
    Assert-Condition (@(Get-ChildItem -LiteralPath $OutputRoot -Force).Count -eq 0) "OutputRoot must be new or empty; existing non-empty output is preserved."
}
Assert-Condition (Test-Path -LiteralPath $ProvidenceSource -PathType Container) "Providence source directory is missing."
Assert-Condition (Test-Path -LiteralPath (Join-Path $ProvidenceSource "Cargo.toml") -PathType Leaf) "ProvidenceSource must name the Cargo workspace root."

$toolchainLockPath = if ([string]::IsNullOrWhiteSpace($ToolchainLockPath)) { Join-Path $PSScriptRoot "providence-toolchain.lock.json" } else { [IO.Path]::GetFullPath($ToolchainLockPath) }
$lock = Get-Content -LiteralPath $toolchainLockPath -Raw | ConvertFrom-Json
$gitRoot = (& git -C $ProvidenceSource rev-parse --show-toplevel 2>$null | Out-String).Trim()
Assert-Condition ($LASTEXITCODE -eq 0) "ProvidenceSource is not inside a Git checkout."
$resolvedGitRoot = [IO.Path]::GetFullPath($gitRoot).TrimEnd('\', '/')
Assert-Condition ([IO.Path]::GetFullPath($ProvidenceSource).TrimEnd('\', '/').Equals($resolvedGitRoot, [StringComparison]::OrdinalIgnoreCase)) "ProvidenceSource must name its Git checkout root."
$sourceCommit = (& git -C $ProvidenceSource rev-parse HEAD 2>$null | Out-String).Trim()
$sourceTree = (& git -C $ProvidenceSource rev-parse 'HEAD^{tree}' 2>$null | Out-String).Trim()
Assert-Condition ($LASTEXITCODE -eq 0) "Could not read the Providence source identity."

$referenceMediaManifest = Join-Path $ApplicationLibraryRoot "classic-application-media.json"
$referenceBlobs = Join-Path $ApplicationLibraryRoot "blobs"
Assert-Condition (Test-Path -LiteralPath $ApplicationDataDirectory -PathType Container) "Application data directory is missing."
Assert-Condition (Test-Path -LiteralPath $referenceMediaManifest -PathType Leaf) "Application reference library is missing classic-application-media.json."
Assert-Condition (Test-Path -LiteralPath $referenceBlobs -PathType Container) "Application reference library is missing its blobs directory."
Assert-Condition (Test-Path -LiteralPath $ApplicationMediaCatalogPath -PathType Leaf) "Accepted slimming media catalog is missing."
$applicationDataIdentity = Get-TreeIdentity $ApplicationDataDirectory
Assert-Condition ([int]$applicationDataIdentity.fileCount -eq [int]$lock.application.nativeData.fileCount -and [long]$applicationDataIdentity.byteCount -eq [long]$lock.application.nativeData.byteCount -and [string]$applicationDataIdentity.treeSha256 -ceq [string]$lock.application.nativeData.treeSha256) "Application data does not match the accepted support-data identity in the toolchain lock."
$acceptedLibraryIdentity = Get-TreeIdentity $ApplicationLibraryRoot
Assert-Condition ([int]$acceptedLibraryIdentity.fileCount -eq [int]$lock.application.referenceLibrary.fileCount -and [long]$acceptedLibraryIdentity.byteCount -eq [long]$lock.application.referenceLibrary.byteCount -and [string]$acceptedLibraryIdentity.treeSha256 -ceq [string]$lock.application.referenceLibrary.treeSha256) "Application reference library does not match the accepted support-data identity in the toolchain lock."
Assert-Condition ((Get-Item -LiteralPath $ApplicationMediaCatalogPath).Length -eq [long]$lock.application.mediaCatalog.bytes -and (Get-Sha256 $ApplicationMediaCatalogPath) -ceq [string]$lock.application.mediaCatalog.sha256) "Application media catalog does not match the accepted support-data identity in the toolchain lock."

$stageRoot = Join-Path (Split-Path -Parent $OutputRoot) (".scenario-importer-stage-" + [Guid]::NewGuid().ToString("N"))
$stageResolved = [IO.Path]::GetFullPath($stageRoot)
$stageParent = [IO.Path]::GetFullPath((Split-Path -Parent $OutputRoot)).TrimEnd('\', '/') + [IO.Path]::DirectorySeparatorChar
Assert-Condition ($stageResolved.StartsWith($stageParent, [StringComparison]::OrdinalIgnoreCase)) "Importer staging path is outside its output parent."

try {
    $cargo = Get-Command cargo -ErrorAction Stop
    $rustc = Get-Command rustc -ErrorAction Stop
    $rustcVersion = (& $rustc.Source -vV | Out-String)
    Assert-Condition ($LASTEXITCODE -eq 0) "Could not inspect the active Rust host target."
    $hostTargetMatch = [regex]::Match($rustcVersion, '(?m)^host:\s*(\S+)\s*$')
    Assert-Condition ($hostTargetMatch.Success) "rustc -vV did not report its host target."
    $hostTarget = $hostTargetMatch.Groups[1].Value
    $cargoArguments = @("build", "--manifest-path", (Join-Path $ProvidenceSource "Cargo.toml"), "-p", "providence-native-adapter", "--release", "--target", $hostTarget)
    Push-Location $ProvidenceSource
    try {
        & $cargo.Source @cargoArguments
        Assert-Condition ($LASTEXITCODE -eq 0) "Cargo failed to build providence-native-adapter."
    } finally {
        Pop-Location
    }

    $cargoTargetRoot = if ([string]::IsNullOrWhiteSpace($env:CARGO_TARGET_DIR)) { Join-Path $ProvidenceSource "target" } elseif ([IO.Path]::IsPathRooted($env:CARGO_TARGET_DIR)) { [IO.Path]::GetFullPath($env:CARGO_TARGET_DIR) } else { [IO.Path]::GetFullPath((Join-Path $ProvidenceSource $env:CARGO_TARGET_DIR)) }
    $adapterBinaryName = if ($hostTarget -match "windows") { "providence-native-adapter.exe" } else { "providence-native-adapter" }
    $builtAdapterPath = Join-Path $cargoTargetRoot ($hostTarget + [IO.Path]::DirectorySeparatorChar + "release" + [IO.Path]::DirectorySeparatorChar + $adapterBinaryName)
    Assert-Condition (Test-Path -LiteralPath $builtAdapterPath -PathType Leaf) "Cargo build succeeded but the native adapter output was not found: $builtAdapterPath"

    $identityText = (& $builtAdapterPath build-identity 2>&1 | Out-String).Trim()
    Assert-Condition ($LASTEXITCODE -eq 0) "The built native adapter could not report its build identity."
    try { $buildIdentity = $identityText | ConvertFrom-Json -ErrorAction Stop } catch { throw "The native adapter build identity is not valid JSON." }
    Assert-Condition ([string]$buildIdentity.commit -ceq $sourceCommit -and [string]$buildIdentity.sourceTree -ceq $sourceTree) "The native adapter embedded source identity does not match ProvidenceSource."
    Assert-Condition ([string]$buildIdentity.tool -ceq "providence-native-adapter") "The built executable reports the wrong tool identity."
    Assert-Condition ([string]$buildIdentity.target -ceq $hostTarget -and [string]$buildIdentity.profile -ceq "release") "The native adapter must use this runner's Rust host target and release profile."
    $sourceChanges = @(Get-SourceChanges $ProvidenceSource)
    if ($Release) {
        Assert-Condition ($sourceChanges.Count -eq 0 -and -not [bool]$buildIdentity.sourceDirty) "A release importer requires a clean Providence source tree."
        Assert-Condition (-not [string]::IsNullOrWhiteSpace($ReleaseIdentityPath) -and (Test-Path -LiteralPath $ReleaseIdentityPath -PathType Leaf)) "-Release requires an accepted ReleaseIdentityPath."
        $releaseRecord = Get-Content -LiteralPath $ReleaseIdentityPath -Raw | ConvertFrom-Json
        $acceptedIdentity = $releaseRecord
        if ($null -ne $releaseRecord.buildIdentity) { $acceptedIdentity = $releaseRecord.buildIdentity }
        foreach ($field in @("kind", "formatVersion", "tool", "version", "commit", "sourceTree", "sourceDirty", "schemaSha256", "cargoLockSha256", "rustcVersion", "cargoVersion", "target", "profile")) {
            Assert-Condition ([string]$buildIdentity.$field -ceq [string]$acceptedIdentity.$field) "The built native adapter $field does not match the accepted release identity."
        }
    }

    [IO.Directory]::CreateDirectory($stageRoot) | Out-Null
    Copy-SupportTree $ApplicationDataDirectory (Join-Path $stageRoot "support/application-data")
    Copy-SupportTree $ApplicationLibraryRoot (Join-Path $stageRoot "support/reference-library")
    Copy-Item -LiteralPath $ApplicationMediaCatalogPath -Destination (Join-Path $stageRoot "support/media.json")
    Copy-Item -LiteralPath $builtAdapterPath -Destination (Join-Path $stageRoot $adapterBinaryName)
    if ($hostTarget -notmatch "windows") {
        & chmod 755 (Join-Path $stageRoot $adapterBinaryName)
        Assert-Condition ($LASTEXITCODE -eq 0) "Could not mark the native adapter executable."
    }
    [IO.File]::WriteAllText((Join-Path $stageRoot ".gdignore"), "", [Text.UTF8Encoding]::new($false))

    $referenceLibraryIdentity = Get-TreeIdentity (Join-Path $stageRoot "support/reference-library")
    Assert-Condition ([int]$referenceLibraryIdentity.fileCount -eq [int]$lock.application.referenceLibrary.fileCount -and [long]$referenceLibraryIdentity.byteCount -eq [long]$lock.application.referenceLibrary.byteCount -and [string]$referenceLibraryIdentity.treeSha256 -ceq [string]$lock.application.referenceLibrary.treeSha256) "Copied reference library does not match the accepted Providence toolchain identity."
    $applicationMediaPath = Join-Path $stageRoot "support/media.json"
    Assert-Condition ((Get-Item -LiteralPath $applicationMediaPath).Length -eq [long]$lock.application.mediaCatalog.bytes -and (Get-Sha256 $applicationMediaPath) -ceq [string]$lock.application.mediaCatalog.sha256) "Copied application media catalog does not match the accepted toolchain lock."

    $supportFiles = @(Get-ManifestFiles (Join-Path $stageRoot "support"))
    $binaryPath = Join-Path $stageRoot $adapterBinaryName
    $binaryMode = if ($hostTarget -match "windows") { "windows-executable" } else { "0755" }
    $expectedRelativePaths = @(".gdignore", $adapterBinaryName) + @($supportFiles | ForEach-Object { "support/" + $_.path })
    $actualRelativePaths = @(
        Get-ChildItem -LiteralPath $stageRoot -File -Recurse -Force | ForEach-Object {
            $relativeRoot = [IO.Path]::GetFullPath($stageRoot).TrimEnd('\', '/') + [IO.Path]::DirectorySeparatorChar
            ([IO.Path]::GetFullPath($_.FullName).Substring($relativeRoot.Length)).Replace('\', '/')
        }
    )
    Assert-Condition (@(Compare-Object ($expectedRelativePaths | Sort-Object) ($actualRelativePaths | Sort-Object)).Count -eq 0) "Staged importer contains unexpected or missing files."
    $buildManifest = [ordered]@{
        kind = "realmz-rebuilt.scenario-importer-build"
        formatVersion = 1
        executable = [ordered]@{
            path = $adapterBinaryName
            bytes = [long](Get-Item -LiteralPath $binaryPath).Length
            sha256 = Get-Sha256 $binaryPath
            mode = $binaryMode
        }
        buildIdentity = $buildIdentity
        sourceChanges = $sourceChanges
        supportFiles = $supportFiles
    }
    Write-Utf8Json (Join-Path $stageRoot "build-manifest.json") $buildManifest
    $expectedRelativePaths += "build-manifest.json"
    $actualRelativePaths = @(
        Get-ChildItem -LiteralPath $stageRoot -File -Recurse -Force | ForEach-Object {
            $relativeRoot = [IO.Path]::GetFullPath($stageRoot).TrimEnd('\', '/') + [IO.Path]::DirectorySeparatorChar
            ([IO.Path]::GetFullPath($_.FullName).Substring($relativeRoot.Length)).Replace('\', '/')
        }
    )
    Assert-Condition (@(Compare-Object ($expectedRelativePaths | Sort-Object) ($actualRelativePaths | Sort-Object)).Count -eq 0) "Final importer output contains unexpected or missing files."

    $outputParent = Split-Path -Parent $OutputRoot
    [IO.Directory]::CreateDirectory($outputParent) | Out-Null
    if (Test-Path -LiteralPath $OutputRoot) {
        Assert-Condition (Test-Path -LiteralPath $OutputRoot -PathType Container) "OutputRoot exists but is not a directory."
        Assert-Condition (@(Get-ChildItem -LiteralPath $OutputRoot -Force).Count -eq 0) "OutputRoot must be new or empty; existing non-empty output is preserved."
        [IO.Directory]::Delete($OutputRoot, $false)
    }
    [IO.Directory]::Move($stageRoot, $OutputRoot)
} catch {
    if (Test-Path -LiteralPath $stageRoot -PathType Container) {
        $cleanupResolved = [IO.Path]::GetFullPath($stageRoot)
        if ($cleanupResolved.StartsWith($stageParent, [StringComparison]::OrdinalIgnoreCase)) {
            [IO.Directory]::Delete($cleanupResolved, $true)
        }
    }
    throw
}

Write-Output "Scenario importer packaged at $OutputRoot"
