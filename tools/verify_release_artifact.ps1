param(
    [Parameter(Mandatory = $true)]
    [ValidateSet("Windows Desktop", "Linux", "macOS")]
    [string]$Preset,
    [Parameter(Mandatory = $true)]
    [string]$Output,
    [Parameter(Mandatory = $true)]
    [string]$ExportLog,
    [Parameter(Mandatory = $true)]
    [string]$ImporterRoot,
    [switch]$LocalTestBuild
)

$ErrorActionPreference = "Stop"
$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path
$catalogPath = Join-Path $repoRoot "src\storage\packages\bundled_campaigns\castle-bundled-scenarios.provenance.json"
$iconRoot = Join-Path $repoRoot "src\ui\shared\assets\ui\application-icon"
$iconManifest = Get-Content -Raw -LiteralPath (Join-Path $iconRoot "application-icon.json") | ConvertFrom-Json
$catalog = Get-Content -Raw -LiteralPath $catalogPath | ConvertFrom-Json
& (Join-Path $PSScriptRoot "verify_bundled_scenarios.ps1")
$outputPath = (Resolve-Path -LiteralPath $Output).Path
$logPath = (Resolve-Path -LiteralPath $ExportLog).Path
$artifactDirectory = Split-Path -Parent $outputPath
$importerRootPath = (Resolve-Path -LiteralPath $ImporterRoot).Path
if ($Preset -ne "macOS") {
    $expectedImporterRoot = [IO.Path]::GetFullPath((Join-Path $artifactDirectory "importer"))
    if (-not [IO.Path]::GetFullPath($importerRootPath).Equals($expectedImporterRoot, [StringComparison]::OrdinalIgnoreCase)) { throw "Windows/Linux importer must be packaged beside the native executable." }
}
$logText = Get-Content -Raw -LiteralPath $logPath
$ansiPattern = [regex]::Escape(([char]27).ToString()) + '\[[0-9;?]*[ -/]*[@-~]'
$plainLogText = [regex]::Replace($logText, $ansiPattern, "")
if ($plainLogText -match '(?m)^(?:WARNING|ERROR|SCRIPT ERROR):') {
    throw "Release export emitted a warning or error: $($Matches[0])"
}
$forbidden = 'Storing File:\s+res://(?:addons/(?:godot_mcp|realmz_builder)(?:/|\\)|tests(?:/|\\)|tools(?:/|\\)|docs(?:/|\\)|contracts(?:/|\\)|artifacts(?:/|\\)|\.references(?:/|\\)|\.github(?:/|\\)|\.mcp\.json|(?:[^\r\n]+/)?AGENTS\.md|README\.md|CONTRIBUTING\.md)'
if ($plainLogText -match $forbidden) {
    throw "Release export contains an excluded development resource: $($Matches[0])"
}
$packagePaths = @([regex]::Matches($plainLogText, 'Storing File:\s+(res://[^\r\n]+\.realmz2)') | ForEach-Object { $_.Groups[1].Value } | Sort-Object -Unique)
$expectedPackagePaths = @('res://src/storage/packages/application/realmz-classic-application-library.realmz2')
$expectedPackagePaths += @($catalog.scenarios | ForEach-Object { "res://src/storage/packages/bundled_campaigns/$($_.file)" })
$expectedPackagePaths = @($expectedPackagePaths | Sort-Object)
if (($packagePaths -join '|') -ne ($expectedPackagePaths -join '|')) {
    throw "Release export contains an unexpected Realmz package set: $($packagePaths -join ', ')"
}
foreach ($requiredRuntimeFile in @('res://LICENSE', 'res://THIRD_PARTY_NOTICES.txt', 'res://src/storage/characters/realmz-classic-starter-characters.json')) {
    if ($plainLogText -notmatch ('Storing File:\s+' + [regex]::Escape($requiredRuntimeFile) + '(?:\r?\n|$)')) {
        throw "Release export is missing required runtime/license file: $requiredRuntimeFile"
    }
}

$artifact = Get-Item -LiteralPath $outputPath
$artifactHash = (Get-FileHash -LiteralPath $outputPath -Algorithm SHA256).Hash.ToLowerInvariant()
$pckName = ""
$pckBytes = 0L
$pckHash = ""
$nativeIcon = [ordered]@{}
if ($Preset -eq "macOS") {
    Add-Type -AssemblyName System.IO.Compression.FileSystem
    $archive = [System.IO.Compression.ZipFile]::OpenRead($outputPath)
    try {
        $entries = @($archive.Entries | Where-Object { $_.FullName.EndsWith(".pck", [System.StringComparison]::OrdinalIgnoreCase) })
        if ($entries.Count -ne 1) { throw "macOS release archive must contain exactly one PCK." }
        $entry = $entries[0]
        $pckName = $entry.FullName
        $pckBytes = $entry.Length
        $stream = $entry.Open()
        $sha = [System.Security.Cryptography.SHA256]::Create()
        try { $pckHash = [Convert]::ToHexString($sha.ComputeHash($stream)).ToLowerInvariant() }
        finally { $sha.Dispose(); $stream.Dispose() }
        $iconEntries = @($archive.Entries | Where-Object { $_.FullName.EndsWith("/Contents/Resources/icon.icns", [System.StringComparison]::OrdinalIgnoreCase) })
        if ($iconEntries.Count -ne 1) { throw "macOS release archive must contain exactly one application icon." }
        $iconEntry = $iconEntries[0]
        $stream = $iconEntry.Open()
        $sha = [System.Security.Cryptography.SHA256]::Create()
        try { $iconHash = [Convert]::ToHexString($sha.ComputeHash($stream)).ToLowerInvariant() }
        finally { $sha.Dispose(); $stream.Dispose() }
        $expectedIconHash = ($iconManifest.files | Where-Object { $_.path -eq "realmz-icon.icns" } | Select-Object -First 1).sha256
        if ($iconHash -ne $expectedIconHash) { throw "macOS release does not preserve the reviewed ICNS application icon." }
        $nativeIcon = [ordered]@{ file = $iconEntry.FullName; bytes = $iconEntry.Length; sha256 = $iconHash }
    } finally {
        $archive.Dispose()
    }
} else {
    $pckPath = [System.IO.Path]::ChangeExtension($outputPath, ".pck")
    if (-not (Test-Path -LiteralPath $pckPath -PathType Leaf)) { throw "$Preset release is missing its adjacent PCK." }
    $pck = Get-Item -LiteralPath $pckPath
    $pckName = $pck.Name
    $pckBytes = $pck.Length
    $pckHash = (Get-FileHash -LiteralPath $pckPath -Algorithm SHA256).Hash.ToLowerInvariant()
    if ($Preset -eq "Windows Desktop") {
        Add-Type -AssemblyName System.Drawing
        $exportedIcon = [System.Drawing.Icon]::ExtractAssociatedIcon($outputPath)
        $expectedBitmap = [System.Drawing.Bitmap]::new((Join-Path $iconRoot "realmz-icon-32.png"))
        $exportedBitmap = $exportedIcon.ToBitmap()
        try {
            if ($exportedBitmap.Width -ne 32 -or $exportedBitmap.Height -ne 32) { throw "Windows release application icon is not the reviewed 32px member." }
            for ($y = 0; $y -lt 32; $y++) {
                for ($x = 0; $x -lt 32; $x++) {
                    if ($exportedBitmap.GetPixel($x, $y).ToArgb() -ne $expectedBitmap.GetPixel($x, $y).ToArgb()) { throw "Windows release application icon pixels differ at ($x,$y)." }
                }
            }
        } finally {
            $exportedBitmap.Dispose()
            $expectedBitmap.Dispose()
            $exportedIcon.Dispose()
        }
        $nativeIcon = [ordered]@{ file = $artifact.Name; verifiedPixelSize = 32; sourceSha256 = ($iconManifest.files | Where-Object { $_.path -eq "realmz-icon-32.png" } | Select-Object -First 1).sha256 }
    }
}
if ($artifact.Length -le 0 -or $pckBytes -le 0) { throw "$Preset release contains an empty artifact or PCK." }

$importerBuildManifestPath = Join-Path $importerRootPath "build-manifest.json"
if (-not (Test-Path -LiteralPath $importerBuildManifestPath -PathType Leaf)) { throw "The exported runtime is missing its verified adjacent scenario importer." }
$importerManifest = Get-Content -Raw -LiteralPath $importerBuildManifestPath | ConvertFrom-Json
if ($importerManifest.kind -cne "realmz-rebuilt.scenario-importer-build" -or [int]$importerManifest.formatVersion -ne 1) { throw "Scenario importer build manifest kind or version is unsupported." }
if ($importerManifest.buildIdentity.profile -cne "release") { throw "Artifacts require a release-profile Providence build identity." }
if ([bool]$importerManifest.buildIdentity.sourceDirty -and -not $LocalTestBuild) { throw "Release artifacts require a clean Providence build identity; use -LocalTestBuild only for an unpublished local test export." }
$importerTarget = [string]$importerManifest.buildIdentity.target
$expectedImporterPlatform = switch ($Preset) {
    "Windows Desktop" { "windows" }
    "Linux" { "linux" }
    "macOS" { "macos" }
}
$expectedImporterBinary = "providence-native-adapter" + $(if ($Preset -eq "Windows Desktop") { ".exe" } else { "" })
$importerBinaryPath = Join-Path $importerRootPath $expectedImporterBinary
if ([string]$importerManifest.executable.path -cne $expectedImporterBinary -or -not (Test-Path -LiteralPath $importerBinaryPath -PathType Leaf)) { throw "Scenario importer executable does not match its native target." }
if ((Get-Item -LiteralPath $importerBinaryPath).Length -ne [long]$importerManifest.executable.bytes -or (Get-FileHash -LiteralPath $importerBinaryPath -Algorithm SHA256).Hash.ToLowerInvariant() -cne [string]$importerManifest.executable.sha256) { throw "Scenario importer executable does not match its build manifest." }
& (Join-Path $PSScriptRoot "verify_scenario_importer_platform.ps1") -ExpectedPlatform $expectedImporterPlatform -Target $importerTarget -ExecutablePath $importerBinaryPath
$expectedImporterFiles = @(".gdignore", "build-manifest.json", $expectedImporterBinary)
foreach ($supportFile in $importerManifest.supportFiles) {
    $relative = [string]$supportFile.path
    if ([string]::IsNullOrWhiteSpace($relative) -or [IO.Path]::IsPathRooted($relative) -or $relative.Contains('\') -or @($relative.Split('/')).Contains('..')) { throw "Scenario importer manifest contains an unsafe support path." }
    $path = Join-Path (Join-Path $importerRootPath "support") ($relative.Replace('/', [IO.Path]::DirectorySeparatorChar))
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { throw "Scenario importer support file is missing: $relative" }
    $support = Get-Item -LiteralPath $path
    if ($support.Length -ne [long]$supportFile.bytes -or (Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash.ToLowerInvariant() -cne [string]$supportFile.sha256) { throw "Scenario importer support file failed its manifest check: $relative" }
    $expectedImporterFiles += "support/$relative"
}
$importerPrefix = $importerRootPath.TrimEnd('\', '/') + [IO.Path]::DirectorySeparatorChar
$actualImporterFiles = @(Get-ChildItem -LiteralPath $importerRootPath -File -Recurse -Force | ForEach-Object { [IO.Path]::GetFullPath($_.FullName).Substring($importerPrefix.Length).Replace('\', '/') })
if (@(Compare-Object ($expectedImporterFiles | Sort-Object) ($actualImporterFiles | Sort-Object)).Count -ne 0) { throw "Scenario importer directory contains unexpected or missing files." }
if ($Preset -eq "macOS") {
    $archive = [System.IO.Compression.ZipFile]::OpenRead($outputPath)
    try {
        $importerManifestEntries = @($archive.Entries | Where-Object { $_.FullName -match '(^|/)Realmz Rebuilt\.app/Contents/MacOS/importer/build-manifest\.json$' })
        if ($importerManifestEntries.Count -ne 1) { throw "macOS release archive must contain one importer inside Contents/MacOS." }
        $appImporterPrefix = $importerManifestEntries[0].FullName.Substring(0, $importerManifestEntries[0].FullName.Length - "build-manifest.json".Length)
        foreach ($relative in $expectedImporterFiles) {
            if (@($archive.Entries | Where-Object { $_.FullName -ceq ($appImporterPrefix + $relative) }).Count -ne 1) { throw "macOS release archive is missing importer file $relative inside Contents/MacOS/importer." }
        }
    } finally {
        $archive.Dispose()
    }
}

$manifest = [ordered]@{
    formatVersion = 1
    commit = (& git -C $repoRoot rev-parse HEAD).Trim()
    localTestBuild = [bool]$LocalTestBuild
    preset = $Preset
    artifact = [ordered]@{ file = $artifact.Name; bytes = $artifact.Length; sha256 = $artifactHash }
    pck = [ordered]@{ file = $pckName; bytes = $pckBytes; sha256 = $pckHash }
    nativeIcon = $nativeIcon
    bundledScenarioCatalog = [ordered]@{
        sourceRevision = $catalog.source.revision
        compilerRevision = $catalog.compiler.revision
        license = $catalog.source.license
        scenarios = @($catalog.scenarios | ForEach-Object {
            [ordered]@{
                campaignId = $_.campaignId
                file = $_.file
                packageHash = $_.packageHash
                archiveSha256 = $_.archiveSha256
                bytes = [long]$_.bytes
            }
        })
    }
    starterCharacterCatalog = [ordered]@{
        file = "src/storage/characters/realmz-classic-starter-characters.json"
        sha256 = (Get-FileHash -LiteralPath (Join-Path $repoRoot "src\storage\characters\realmz-classic-starter-characters.json") -Algorithm SHA256).Hash.ToLowerInvariant()
        recordCount = 6
    }
    scenarioImporter = [ordered]@{
        executable = $importerManifest.executable
        buildIdentity = $importerManifest.buildIdentity
        supportFiles = $importerManifest.supportFiles
    }
}
if ($LocalTestBuild) {
    $changedPaths = @(& git -C $repoRoot -c core.quotepath=false diff --name-only HEAD --)
    $changedPaths += @(& git -C $repoRoot -c core.quotepath=false ls-files --others --exclude-standard)
    $manifest.sourceDirty = $changedPaths.Count -gt 0
    $manifest.sourceChanges = @($changedPaths | Sort-Object -Unique | ForEach-Object {
        $relative = $_
        $path = Join-Path $repoRoot $relative
        if (Test-Path -LiteralPath $path -PathType Leaf) {
            [ordered]@{ path = $relative; sha256 = (Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash.ToLowerInvariant() }
        } else {
            [ordered]@{ path = $relative; deleted = $true }
        }
    })
}
$manifestPath = Join-Path $artifactDirectory "release-manifest.json"
[System.IO.File]::WriteAllText($manifestPath, (($manifest | ConvertTo-Json -Depth 7) + "`n"), [System.Text.UTF8Encoding]::new($false))
Write-Host "$Preset release artifact verified: artifact=$artifactHash pck=$pckHash manifest=$manifestPath"
