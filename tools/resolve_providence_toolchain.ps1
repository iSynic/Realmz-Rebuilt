param(
    [string]$LockPath = "",
    [string]$LocalConfigPath = ""
)

$ErrorActionPreference = "Stop"
$repoRoot = Split-Path -Parent $PSScriptRoot
if ([string]::IsNullOrWhiteSpace($LockPath)) {
    $LockPath = Join-Path $PSScriptRoot "providence-toolchain.lock.json"
}
if ([string]::IsNullOrWhiteSpace($LocalConfigPath)) {
    $LocalConfigPath = Join-Path $PSScriptRoot "providence-toolchain.local.json"
}

function Assert-Condition([bool]$Condition, [string]$Message) {
    if (-not $Condition) { throw $Message }
}

function Get-Sha256([string]$Path) {
    return (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash.ToLowerInvariant()
}

function Get-TreeIdentity([string]$Root) {
    $resolvedRoot = [IO.Path]::GetFullPath($Root).TrimEnd('\', '/')
    $rootPrefix = $resolvedRoot + [IO.Path]::DirectorySeparatorChar
    $entries = @()
    [long]$byteCount = 0
    foreach ($file in Get-ChildItem -LiteralPath $Root -File -Recurse | Sort-Object FullName) {
        $resolvedFile = [IO.Path]::GetFullPath($file.FullName)
        Assert-Condition ($resolvedFile.StartsWith($rootPrefix, [StringComparison]::OrdinalIgnoreCase)) "Tree identity escaped its declared root: $resolvedFile"
        $relative = $resolvedFile.Substring($rootPrefix.Length).Replace('\', '/')
        $hash = Get-Sha256 $file.FullName
        $byteCount += $file.Length
        $entries += "$relative`t$($file.Length)`t$hash"
    }
    $identityBytes = [Text.Encoding]::UTF8.GetBytes(($entries -join "`n"))
    $sha = [Security.Cryptography.SHA256]::Create()
    try {
        $treeHash = ([BitConverter]::ToString($sha.ComputeHash($identityBytes))).Replace('-', '').ToLowerInvariant()
    } finally {
        $sha.Dispose()
    }
    return [ordered]@{
        fileCount = $entries.Count
        byteCount = $byteCount
        treeSha256 = $treeHash
    }
}

function Assert-FileIdentity([string]$Label, [string]$Path, $Expected) {
    Assert-Condition (Test-Path -LiteralPath $Path -PathType Leaf) "$Label is missing: $Path"
    $file = Get-Item -LiteralPath $Path
    Assert-Condition ([long]$file.Length -eq [long]$Expected.bytes) "$Label byte count does not match the Providence toolchain lock."
    Assert-Condition ((Get-Sha256 $Path) -ceq [string]$Expected.sha256) "$Label hash does not match the Providence toolchain lock."
}

function Assert-TreeIdentity([string]$Label, [string]$Path, $Expected) {
    Assert-Condition (Test-Path -LiteralPath $Path -PathType Container) "$Label is missing: $Path"
    $actual = Get-TreeIdentity $Path
    Assert-Condition ([int]$actual.fileCount -eq [int]$Expected.fileCount) "$Label file count does not match the Providence toolchain lock."
    Assert-Condition ([long]$actual.byteCount -eq [long]$Expected.byteCount) "$Label byte count does not match the Providence toolchain lock."
    Assert-Condition ($actual.treeSha256 -ceq [string]$Expected.treeSha256) "$Label tree hash does not match the Providence toolchain lock."
    return $actual
}

Assert-Condition (Test-Path -LiteralPath $LockPath -PathType Leaf) "Providence toolchain lock is missing: $LockPath"
Assert-Condition (Test-Path -LiteralPath $LocalConfigPath -PathType Leaf) "Providence local toolchain configuration is missing: $LocalConfigPath"
$lock = Get-Content -LiteralPath $LockPath -Raw | ConvertFrom-Json
$local = Get-Content -LiteralPath $LocalConfigPath -Raw | ConvertFrom-Json
Assert-Condition ($lock.kind -ceq "realmz-rebuilt.providence-toolchain-lock") "Providence toolchain lock kind is unsupported."
Assert-Condition ([int]$lock.formatVersion -eq 1) "Providence toolchain lock format is unsupported."
Assert-Condition ($local.kind -ceq "realmz-rebuilt.providence-toolchain-local") "Providence local toolchain configuration kind is unsupported."
Assert-Condition ([int]$local.formatVersion -eq 1) "Providence local toolchain configuration format is unsupported."

$toolchainDirectory = [IO.Path]::GetFullPath((Join-Path ([string]$local.toolchainRoot) ([string]$lock.compiler.directoryName)))
$binaryPaths = [ordered]@{}
foreach ($property in $lock.compiler.binaries.PSObject.Properties) {
    $name = $property.Name
    $expected = $property.Value
    $path = Join-Path $toolchainDirectory ([string]$expected.file)
    Assert-FileIdentity "Providence $name executable" $path $expected
    $identityText = (& $path build-identity 2>&1 | Out-String).Trim()
    Assert-Condition ($LASTEXITCODE -eq 0) "Providence $name build-identity failed: $identityText"
    try {
        $identity = $identityText | ConvertFrom-Json -ErrorAction Stop
    } catch {
        throw "Providence $name build-identity did not return JSON."
    }
    foreach ($field in @('commit', 'sourceTree', 'schemaSha256', 'cargoLockSha256', 'rustcVersion', 'cargoVersion', 'target', 'profile')) {
        Assert-Condition ([string]$identity.$field -ceq [string]$lock.compiler.$field) "Providence $name embedded $field does not match the toolchain lock."
    }
    Assert-Condition ([bool]$identity.sourceDirty -eq [bool]$lock.compiler.sourceDirty) "Providence $name embedded dirty state does not match the toolchain lock."
    Assert-Condition ([string]$identity.tool -ceq [string]$expected.tool) "Providence $name executable reports the wrong tool identity."
    $binaryPaths[$name] = [IO.Path]::GetFullPath($path)
}

$applicationPackagePath = [IO.Path]::GetFullPath((Join-Path $repoRoot ([string]$lock.application.package.path)))
$applicationMediaCatalogPath = [IO.Path]::GetFullPath([string]$local.applicationMediaCatalogPath)
$applicationDataDirectory = [IO.Path]::GetFullPath([string]$local.applicationDataDirectory)
$applicationLibraryRoot = [IO.Path]::GetFullPath([string]$local.applicationLibraryRoot)
$referenceCatalogRoot = [IO.Path]::GetFullPath([string]$local.referenceCatalogRoot)
Assert-FileIdentity "application package" $applicationPackagePath $lock.application.package
Assert-FileIdentity "application media catalog" $applicationMediaCatalogPath $lock.application.mediaCatalog
$applicationDataIdentity = Assert-TreeIdentity "Classic application data" $applicationDataDirectory $lock.application.nativeData
$applicationLibraryIdentity = Assert-TreeIdentity "Providence application reference library" $applicationLibraryRoot $lock.application.referenceLibrary
$referenceCatalogIdentity = Assert-TreeIdentity "Providence reference catalog" $referenceCatalogRoot $lock.application.referenceCatalog

Add-Type -AssemblyName System.IO.Compression.FileSystem
$archive = [IO.Compression.ZipFile]::OpenRead($applicationPackagePath)
try {
    $entry = $archive.GetEntry('manifest.json')
    Assert-Condition ($null -ne $entry) "Application package is missing manifest.json."
    $reader = [IO.StreamReader]::new($entry.Open())
    try {
        $manifest = $reader.ReadToEnd() | ConvertFrom-Json
    } finally {
        $reader.Dispose()
    }
} finally {
    $archive.Dispose()
}
Assert-Condition ($manifest.campaignId -ceq [string]$lock.application.package.campaignId) "Application package campaign identity does not match the toolchain lock."
Assert-Condition ($manifest.packageHash -ceq [string]$lock.application.package.packageHash) "Application package semantic hash does not match the toolchain lock."
Assert-Condition ($manifest.contentId -ceq [string]$lock.application.package.contentId) "Application package content identity does not match the toolchain lock."

[ordered]@{
    lockPath = [IO.Path]::GetFullPath($LockPath)
    lockSha256 = Get-Sha256 $LockPath
    compilerCommit = [string]$lock.compiler.commit
    cliPath = $binaryPaths.cli
    adapterPath = $binaryPaths.adapter
    slimmerPath = $binaryPaths.slimmer
    applicationPackagePath = $applicationPackagePath
    applicationMediaCatalogPath = $applicationMediaCatalogPath
    applicationDataDirectory = $applicationDataDirectory
    applicationLibraryRoot = $applicationLibraryRoot
    referenceCatalogRoot = $referenceCatalogRoot
    applicationDataIdentity = $applicationDataIdentity
    applicationLibraryIdentity = $applicationLibraryIdentity
    referenceCatalogIdentity = $referenceCatalogIdentity
} | ConvertTo-Json -Depth 8 -Compress
