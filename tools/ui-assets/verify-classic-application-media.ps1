$ErrorActionPreference = "Stop"
Add-Type -AssemblyName System.Drawing

$toolRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
$repoRoot = Split-Path -Parent (Split-Path -Parent $toolRoot)
$manifestPath = Join-Path $repoRoot "src/presentation/assets/classic-application-media.json"
if (-not (Test-Path -LiteralPath $manifestPath -PathType Leaf)) {
    throw "Classic application media manifest is missing"
}
$manifest = Get-Content -Raw -LiteralPath $manifestPath | ConvertFrom-Json
if ($manifest.schema_version -ne 1 -or $manifest.lookup -ne "scenario-first-application-fallback") {
    throw "Classic application media manifest contract is unsupported"
}
if ($manifest.source_commit -ne "491816ad60037394f92c428e99c004494d3c28b3" -or $manifest.license -ne "CC-BY-NC-SA-4.0" -or [string]::IsNullOrWhiteSpace($manifest.copyright) -or [string]::IsNullOrWhiteSpace($manifest.modification)) {
    throw "Classic application media provenance or license metadata is incomplete"
}
$ids = @{}
$keys = @{}
foreach ($asset in $manifest.assets) {
    if ($ids.ContainsKey($asset.id)) {
        throw "Duplicate application media asset ID: $($asset.id)"
    }
    $ids[$asset.id] = $true
    $key = "$($asset.resource_type):$($asset.resource_id)"
    if ($keys.ContainsKey($key)) {
        throw "Duplicate application media resource key: $key"
    }
    $keys[$key] = $true
    if (-not $asset.path.StartsWith("res://")) {
        throw "Application media path is not project-relative: $($asset.path)"
    }
    $relativePath = $asset.path.Substring("res://".Length) -replace "/", [IO.Path]::DirectorySeparatorChar
    $path = Join-Path $repoRoot $relativePath
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) {
        throw "Application media file is missing: $($asset.path)"
    }
    if ((Get-Item -LiteralPath $path).Length -ne $asset.bytes) {
        throw "Application media byte count does not match: $($asset.id)"
    }
    $sha256 = (Get-FileHash -Algorithm SHA256 -LiteralPath $path).Hash.ToLowerInvariant()
    if ($sha256 -ne $asset.sha256) {
        throw "Application media hash does not match: $($asset.id)"
    }
	if ($asset.mime_type -eq "image/png" -and ($asset.width -lt 1 -or $asset.height -lt 1)) {
		throw "Application image media has invalid dimensions: $($asset.id)"
	}
}
$soundCount = @($manifest.assets | Where-Object { $_.resource_type -eq "snd " }).Count
$combatIconCount = @($manifest.assets | Where-Object { $_.path -like "*/combat-icons/*" }).Count
$itemIconCount = @($manifest.assets | Where-Object { $_.path -like "*/item-icons/*" }).Count
if ($soundCount -ne 142 -or $combatIconCount -ne 145 -or $itemIconCount -ne 270) {
    throw "Expected 142 built-in sounds, 145 source-backed combat icons, and 270 shared or stock-supply item icons; found $soundCount sounds, $combatIconCount combat icons, and $itemIconCount item icons"
}
foreach ($requiredSupplyIcon in @(142, 601, 602, 603, 604, 605, 607, 608, 2011, 2013)) {
    if (-not $keys.ContainsKey("cicn:$requiredSupplyIcon")) {
        throw "Required application-owned stock supply icon is missing: cicn:$requiredSupplyIcon"
    }
}

$fontManifestPath = Join-Path $repoRoot "src/presentation/assets/fonts/font-assets.json"
if (-not (Test-Path -LiteralPath $fontManifestPath -PathType Leaf)) {
    throw "Font asset manifest is missing"
}
$fontManifest = Get-Content -Raw -LiteralPath $fontManifestPath | ConvertFrom-Json
if ($fontManifest.schema_version -ne 3 -or $fontManifest.runtime_network_dependency -ne $false) {
    throw "Font asset manifest contract is unsupported"
}
$fontIds = @{}
foreach ($fontAsset in $fontManifest.assets) {
    if ($fontIds.ContainsKey($fontAsset.id)) { throw "Duplicate font asset ID: $($fontAsset.id)" }
    $fontIds[$fontAsset.id] = $true
    if (-not $fontAsset.path.StartsWith("res://") -or [string]::IsNullOrWhiteSpace($fontAsset.source_repository) -or [string]::IsNullOrWhiteSpace($fontAsset.source_commit) -or [string]::IsNullOrWhiteSpace($fontAsset.license)) {
        throw "Font asset provenance is incomplete: $($fontAsset.id)"
    }
    if ($null -ne $fontAsset.metric_source_repository -and ([string]::IsNullOrWhiteSpace($fontAsset.metric_source_repository) -or [string]::IsNullOrWhiteSpace($fontAsset.metric_source_commit) -or [string]::IsNullOrWhiteSpace($fontAsset.metric_source_path) -or [string]::IsNullOrWhiteSpace($fontAsset.metric_source_sha256))) {
        throw "Font metric-source provenance is incomplete: $($fontAsset.id)"
    }
    if ($null -ne $fontAsset.baseline_source_repository -and ([string]::IsNullOrWhiteSpace($fontAsset.baseline_source_repository) -or [string]::IsNullOrWhiteSpace($fontAsset.baseline_source_commit) -or [string]::IsNullOrWhiteSpace($fontAsset.baseline_source_path) -or [string]::IsNullOrWhiteSpace($fontAsset.baseline_source_sha256))) {
        throw "Font baseline-source provenance is incomplete: $($fontAsset.id)"
    }
    if ($null -ne $fontAsset.utility_source_repository -and ([string]::IsNullOrWhiteSpace($fontAsset.utility_source_repository) -or [string]::IsNullOrWhiteSpace($fontAsset.utility_source_commit) -or [string]::IsNullOrWhiteSpace($fontAsset.utility_source_path) -or [string]::IsNullOrWhiteSpace($fontAsset.utility_source_sha256))) {
        throw "Font utility-source provenance is incomplete: $($fontAsset.id)"
    }
    if ($null -ne $fontAsset.build_tool_path) {
        $buildToolPath = Join-Path $repoRoot ($fontAsset.build_tool_path -replace "/", [IO.Path]::DirectorySeparatorChar)
        if (-not (Test-Path -LiteralPath $buildToolPath -PathType Leaf) -or [string]::IsNullOrWhiteSpace($fontAsset.build_tool_sha256)) {
            throw "Font build-tool provenance is incomplete: $($fontAsset.id)"
        }
        if ((Get-FileHash -Algorithm SHA256 -LiteralPath $buildToolPath).Hash.ToLowerInvariant() -ne $fontAsset.build_tool_sha256) {
            throw "Font build-tool hash does not match: $($fontAsset.id)"
        }
    }
    $relativePath = $fontAsset.path.Substring("res://".Length) -replace "/", [IO.Path]::DirectorySeparatorChar
    $path = Join-Path $repoRoot $relativePath
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { throw "Font asset file is missing: $($fontAsset.path)" }
    $sha256 = (Get-FileHash -Algorithm SHA256 -LiteralPath $path).Hash.ToLowerInvariant()
    if ($sha256 -ne $fontAsset.sha256) { throw "Font asset hash does not match: $($fontAsset.id)" }
    if ($fontAsset.id -eq "font.classic.theldrow.rebuilt") {
        $glyphSourcePath = Join-Path $repoRoot ($fontAsset.source_path -replace "/", [IO.Path]::DirectorySeparatorChar)
        if (-not (Test-Path -LiteralPath $glyphSourcePath -PathType Leaf) -or [string]::IsNullOrWhiteSpace($fontAsset.source_sha256)) {
            throw "Modernized Theldrow Pencil geometry provenance is incomplete"
        }
        if ((Get-FileHash -Algorithm SHA256 -LiteralPath $glyphSourcePath).Hash.ToLowerInvariant() -ne $fontAsset.source_sha256) {
            throw "Modernized Theldrow Pencil geometry hash does not match"
        }
    }
}
foreach ($requiredFont in @("font.classic.black_chancery.regular", "font.classic.chicago_flf.regular", "font.classic.geneva_substitute.inter", "font.classic.theldrow.bitmap", "font.classic.theldrow.atlas", "font.classic.theldrow.vector", "font.classic.theldrow.rebuilt", "license.grenze_gotisch")) {
    if (-not $fontIds.ContainsKey($requiredFont)) { throw "Required Classic font asset is missing: $requiredFont" }
}

$introManifestPath = Join-Path $repoRoot "src/presentation/assets/ui/intro/intro-video.json"
if (-not (Test-Path -LiteralPath $introManifestPath -PathType Leaf)) { throw "Realmz Rebuilt intro video manifest is missing" }
$introManifest = Get-Content -Raw -LiteralPath $introManifestPath | ConvertFrom-Json
if ($introManifest.schema_version -ne 2 -or $introManifest.source_sha256 -ne "f78a04d978b0de0b306598a201e5cccaa7e930b947b1bfab59d81437b4c8cf75" -or $introManifest.license -ne "Project-Owner-Supplied" -or $introManifest.path -ne "res://src/presentation/assets/ui/intro/rebuilt-intro.ogv" -or $introManifest.bytes -ne 1110117 -or $introManifest.width -ne 832 -or $introManifest.height -ne 480 -or $introManifest.frames_per_second -ne 24 -or $introManifest.duration_ms -ne 5167 -or $introManifest.video_codec -ne "theora" -or $introManifest.audio_codec -ne "vorbis" -or $introManifest.audio_sample_rate -ne 32000 -or $introManifest.audio_channels -ne 2 -or -not $introManifest.loop) {
    throw "Realmz Rebuilt intro video provenance or media contract is invalid"
}
$introVideoPath = Join-Path $repoRoot ($introManifest.path.Substring("res://".Length) -replace "/", [IO.Path]::DirectorySeparatorChar)
if (-not (Test-Path -LiteralPath $introVideoPath -PathType Leaf)) { throw "Realmz Rebuilt intro video is missing" }
if ((Get-Item -LiteralPath $introVideoPath).Length -ne $introManifest.bytes) { throw "Realmz Rebuilt intro video byte length does not match" }
if ((Get-FileHash -Algorithm SHA256 -LiteralPath $introVideoPath).Hash.ToLowerInvariant() -ne $introManifest.source_sha256) { throw "Realmz Rebuilt intro video hash does not match" }

$chromeManifestPath = Join-Path $repoRoot "src/presentation/assets/ui/spritecook-assets.json"
if (-not (Test-Path -LiteralPath $chromeManifestPath -PathType Leaf)) {
    throw "SpriteCook chrome manifest is missing"
}
$chromeManifest = Get-Content -Raw -LiteralPath $chromeManifestPath | ConvertFrom-Json
if ($chromeManifest.schema_version -ne 7 -or [string]::IsNullOrWhiteSpace($chromeManifest.selected_asset.asset_id)) {
    throw "SpriteCook chrome manifest contract is unsupported"
}
$chromeFiles = @($chromeManifest.files)
foreach ($decorativeAsset in @($chromeManifest.decorative_assets)) {
    if ([string]::IsNullOrWhiteSpace($decorativeAsset.asset_id) -or [string]::IsNullOrWhiteSpace($decorativeAsset.source_sha256) -or [string]::IsNullOrWhiteSpace($decorativeAsset.derivation)) {
        throw "SpriteCook decorative asset provenance is incomplete"
    }
    $chromeFiles += $decorativeAsset.file
}
foreach ($statusAsset in @($chromeManifest.status_assets)) {
    if ([string]::IsNullOrWhiteSpace($statusAsset.asset_id) -or [string]::IsNullOrWhiteSpace($statusAsset.generation_job_id) -or [string]::IsNullOrWhiteSpace($statusAsset.source_sha256) -or [string]::IsNullOrWhiteSpace($statusAsset.derivation)) {
        throw "SpriteCook status asset provenance is incomplete"
    }
    $chromeFiles += $statusAsset.file
}
foreach ($commandAsset in @($chromeManifest.command_assets)) {
    if ([string]::IsNullOrWhiteSpace($commandAsset.asset_id) -or [string]::IsNullOrWhiteSpace($commandAsset.generation_job_id) -or [string]::IsNullOrWhiteSpace($commandAsset.source_sha256) -or [string]::IsNullOrWhiteSpace($commandAsset.derivation)) {
        throw "SpriteCook command asset provenance is incomplete"
    }
    $chromeFiles += $commandAsset.file
}
foreach ($file in $chromeFiles) {
    if (-not $file.path.StartsWith("res://")) {
        throw "Generated chrome path is not project-relative: $($file.path)"
    }
    $relativePath = $file.path.Substring("res://".Length) -replace "/", [IO.Path]::DirectorySeparatorChar
    $path = Join-Path $repoRoot $relativePath
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) {
        throw "Generated chrome file is missing: $($file.path)"
    }
    $sha256 = (Get-FileHash -Algorithm SHA256 -LiteralPath $path).Hash.ToLowerInvariant()
    if ($sha256 -ne $file.sha256) {
        throw "Generated chrome hash does not match: $($file.path)"
    }
    $bitmap = [Drawing.Bitmap]::new([string]$path)
    try {
        if ($bitmap.Width -ne $file.width -or $bitmap.Height -ne $file.height) {
            throw "Generated chrome dimensions do not match: $($file.path)"
        }
    }
    finally { $bitmap.Dispose() }
}
Write-Host "Classic application media verified: $($manifest.assets.Count) assets; fonts verified: $($fontManifest.assets.Count) assets; intro video verified: $($introManifest.width)x$($introManifest.height); generated chrome verified: $($chromeFiles.Count) files."
exit 0
