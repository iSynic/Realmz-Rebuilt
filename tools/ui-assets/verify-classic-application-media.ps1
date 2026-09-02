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
	if ($asset.resource_type -eq "snd ") {
		$importPath = "$path.import"
		$importSettings = if (Test-Path -LiteralPath $importPath -PathType Leaf) { Get-Content -Raw -LiteralPath $importPath } else { "" }
		if ($importSettings -notmatch '(?m)^compress/mode=0$' -or $importSettings -notmatch '(?m)^force/mono=true$') {
			throw "Classic application sound must use lossless PCM import: $($asset.id)"
		}
		if ($asset.sample_rate -ne 48000 -or $asset.channels -ne 1) {
			throw "Classic application sound must retain Castle's 48 kHz mono waveform: $($asset.id)"
		}
	}
	if ($asset.mime_type -eq "image/png" -and ($asset.width -lt 1 -or $asset.height -lt 1)) {
		throw "Application image media has invalid dimensions: $($asset.id)"
	}
}
$soundCount = @($manifest.assets | Where-Object { $_.resource_type -eq "snd " }).Count
$combatIconCount = @($manifest.assets | Where-Object { $_.path -like "*/combat-icons/*" }).Count
$itemIconCount = @($manifest.assets | Where-Object { $_.path -like "*/item-icons/*" }).Count
$effectIconCount = @($manifest.assets | Where-Object { $_.path -like "*/effect-icons/*" }).Count
$landTilesetCount = @($manifest.assets | Where-Object { $_.kind -eq "tileset" }).Count
$darknessMaskCount = @($manifest.assets | Where-Object { $_.id -like "classic-darkness-mask-*" }).Count
if ($soundCount -ne 142 -or $combatIconCount -ne 145 -or $itemIconCount -ne 274 -or $effectIconCount -ne 64 -or $landTilesetCount -ne 6 -or $darknessMaskCount -ne 7) {
	throw "Expected 142 built-in sounds, 145 source-backed combat icons, 274 shared, stock-supply, or Money Changing item icons, 64 animated effect icons, 6 stock land tilesets, and 7 darkness masks; found $soundCount sounds, $combatIconCount combat icons, $itemIconCount item icons, $effectIconCount effect icons, $landTilesetCount land tilesets, and $darknessMaskCount darkness masks"
}
foreach ($effectResourceId in 14000..14063) {
    if (-not $keys.ContainsKey("cicn:$effectResourceId")) {
        throw "Required application-owned party effect icon is missing: cicn:$effectResourceId"
    }
}
foreach ($landlook in @(0, 3, 4, 5, 9, 10)) {
    $tileset = @($manifest.assets | Where-Object { $_.id -eq "landlook-$landlook" })
    if ($tileset.Count -ne 1 -or $tileset[0].resource_type -ne "PICT" -or $tileset[0].resource_id -ne 300 + $landlook -or $tileset[0].width -ne 640 -or $tileset[0].height -ne 320 -or $tileset[0].tile_width -ne 32 -or $tileset[0].tile_height -ne 32 -or $tileset[0].columns -ne 20 -or $tileset[0].rows -ne 10 -or $tileset[0].landlook -ne $landlook) {
        throw "Stock application landlook contract is invalid: $landlook"
    }
}
foreach ($darknessLevel in 0..6) {
    $mask = @($manifest.assets | Where-Object { $_.id -eq "classic-darkness-mask-$darknessLevel" })
	if ($mask.Count -ne 1 -or $mask[0].resource_type -ne "PICT" -or $mask[0].resource_id -ne (350 + $darknessLevel) -or $mask[0].width -ne 320 -or $mask[0].height -ne 320) {
        throw "Stock application darkness mask contract is invalid: $darknessLevel"
    }
}
$scrollingPattern = @($manifest.assets | Where-Object { $_.resource_type -eq "ppat" -and $_.resource_id -eq 129 })
if ($scrollingPattern.Count -ne 1 -or $scrollingPattern[0].id -ne "realmz-application-ppat-129" -or $scrollingPattern[0].kind -ne "pattern" -or $scrollingPattern[0].width -ne 64 -or $scrollingPattern[0].height -ne 64) {
    throw "Classic scrolling-text ppat 129 contract is invalid"
}
foreach ($requiredSupplyIcon in @(142, 601, 602, 603, 604, 605, 607, 608, 2011, 2013, 6195)) {
    if (-not $keys.ContainsKey("cicn:$requiredSupplyIcon")) {
        throw "Required application-owned stock supply icon is missing: cicn:$requiredSupplyIcon"
    }
}
foreach ($requiredWealthIcon in @(2002, 2011, 2012, 2014)) {
    if (-not $keys.ContainsKey("cicn:$requiredWealthIcon")) {
        throw "Required application-owned Money Changing icon is missing: cicn:$requiredWealthIcon"
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
if ($introManifest.schema_version -ne 4 -or $introManifest.source_sha256 -ne "2b30c6bca4a8d6ba6ee524c28630c4706944f327b5d8d304ce0253050fb53f40" -or $introManifest.license -ne "Project-Owner-Supplied" -or $introManifest.path -ne "res://src/presentation/assets/ui/intro/rebuilt-intro.ogv" -or $introManifest.bytes -ne 1097782 -or $introManifest.width -ne 832 -or $introManifest.height -ne 480 -or $introManifest.frames_per_second -ne 24 -or $introManifest.duration_ms -ne 5167 -or $introManifest.video_codec -ne "theora" -or $introManifest.audio_codec -ne "vorbis" -or $introManifest.audio_sample_rate -ne 48000 -or $introManifest.audio_channels -ne 2 -or -not $introManifest.loop -or $introManifest.playback_audio -ne $false) {
    throw "Realmz Rebuilt intro video provenance or media contract is invalid"
}
$launchSplash = $introManifest.launch_splash
if ($null -eq $launchSplash -or $launchSplash.source_role -ne "Realmz Rebuilt launch splash supplied by the project owner" -or $launchSplash.source_name -ne "Rebuilt Splash.jpg" -or $launchSplash.source_sha256 -ne "de81e79e6cf5e92bac396f5c4aa90b6be21c3b16b33cb450879b08a9e655497a" -or $launchSplash.license -ne "Project-Owner-Supplied" -or $launchSplash.path -ne "res://src/presentation/assets/ui/intro/rebuilt-launch-splash.jpg" -or $launchSplash.bytes -ne 219118 -or $launchSplash.width -ne 1024 -or $launchSplash.height -ne 1024 -or $launchSplash.format -ne "jpeg" -or $launchSplash.minimum_duration_ms -ne 3000 -or $launchSplash.scaling -ne "keep-aspect-centered") {
    throw "Realmz Rebuilt launch splash provenance or presentation contract is invalid"
}
$launchSplashPath = Join-Path $repoRoot ($launchSplash.path.Substring("res://".Length) -replace "/", [IO.Path]::DirectorySeparatorChar)
if (-not (Test-Path -LiteralPath $launchSplashPath -PathType Leaf) -or (Get-Item -LiteralPath $launchSplashPath).Length -ne $launchSplash.bytes -or (Get-FileHash -Algorithm SHA256 -LiteralPath $launchSplashPath).Hash.ToLowerInvariant() -ne $launchSplash.source_sha256) {
    throw "Realmz Rebuilt launch splash bytes do not match the project-owner-supplied asset"
}
$projectSettings = Get-Content -Raw -LiteralPath (Join-Path $repoRoot "project.godot")
if ($projectSettings -notmatch 'boot_splash/bg_color=Color\(0, 0, 0, 1\)' -or $projectSettings -notmatch 'boot_splash/show_image=false' -or $projectSettings -match 'boot_splash/image=') {
    throw "Godot boot must remain black until the ready runtime reveals the Rebuilt card and its first cue together"
}
$launchBitmap = [Drawing.Bitmap]::new([string]$launchSplashPath)
try {
    if ($launchBitmap.Width -ne $launchSplash.width -or $launchBitmap.Height -ne $launchSplash.height) { throw "Realmz Rebuilt launch splash dimensions do not match" }
} finally { $launchBitmap.Dispose() }
$introVideoPath = Join-Path $repoRoot ($introManifest.path.Substring("res://".Length) -replace "/", [IO.Path]::DirectorySeparatorChar)
if (-not (Test-Path -LiteralPath $introVideoPath -PathType Leaf)) { throw "Realmz Rebuilt intro video is missing" }
if ((Get-Item -LiteralPath $introVideoPath).Length -ne $introManifest.bytes) { throw "Realmz Rebuilt intro video byte length does not match" }
if ((Get-FileHash -Algorithm SHA256 -LiteralPath $introVideoPath).Hash.ToLowerInvariant() -ne $introManifest.source_sha256) { throw "Realmz Rebuilt intro video hash does not match" }
$introSoundtrack = $introManifest.soundtrack
if ($null -eq $introSoundtrack -or $introSoundtrack.source_sha256 -ne "c64e2792eba92284896084c3d48af9d595fdd98cda5e7a3d90931b2a9a21f0e5" -or $introSoundtrack.license -ne "Project-Owner-Supplied" -or $introSoundtrack.path -ne "res://src/presentation/assets/ui/intro/rebuilt-intro-soundtrack.mp3" -or $introSoundtrack.bytes -ne 721197 -or $introSoundtrack.duration_ms -ne 30000 -or $introSoundtrack.codec -ne "mp3" -or $introSoundtrack.bit_rate -ne 192000 -or $introSoundtrack.sample_rate -ne 48000 -or $introSoundtrack.channels -ne 2 -or -not $introSoundtrack.loop -or -not $introSoundtrack.click_toggle -or -not $introSoundtrack.independent_from_video) {
    throw "Realmz Rebuilt intro soundtrack provenance or playback contract is invalid"
}
$introSoundtrackPath = Join-Path $repoRoot ($introSoundtrack.path.Substring("res://".Length) -replace "/", [IO.Path]::DirectorySeparatorChar)
if (-not (Test-Path -LiteralPath $introSoundtrackPath -PathType Leaf)) { throw "Realmz Rebuilt intro soundtrack is missing" }
if ((Get-Item -LiteralPath $introSoundtrackPath).Length -ne $introSoundtrack.bytes) { throw "Realmz Rebuilt intro soundtrack byte length does not match" }
if ((Get-FileHash -Algorithm SHA256 -LiteralPath $introSoundtrackPath).Hash.ToLowerInvariant() -ne $introSoundtrack.source_sha256) { throw "Realmz Rebuilt intro soundtrack hash does not match" }
$introSoundtrackImportPath = "$introSoundtrackPath.import"
if (-not (Test-Path -LiteralPath $introSoundtrackImportPath -PathType Leaf)) { throw "Realmz Rebuilt intro soundtrack import contract is missing" }
$introSoundtrackImport = Get-Content -Raw -LiteralPath $introSoundtrackImportPath
if ($introSoundtrackImport -notmatch 'importer="mp3"' -or $introSoundtrackImport -notmatch '(?m)^loop=true\r?$') { throw "Realmz Rebuilt intro soundtrack import contract does not enable MP3 looping" }

$chromeManifestPath = Join-Path $repoRoot "src/presentation/assets/ui/spritecook-assets.json"
if (-not (Test-Path -LiteralPath $chromeManifestPath -PathType Leaf)) {
    throw "SpriteCook chrome manifest is missing"
}
$chromeManifest = Get-Content -Raw -LiteralPath $chromeManifestPath | ConvertFrom-Json
if ($chromeManifest.schema_version -ne 8 -or [string]::IsNullOrWhiteSpace($chromeManifest.selected_asset.asset_id)) {
    throw "SpriteCook chrome manifest contract is unsupported"
}
$chromeFiles = @($chromeManifest.files)
foreach ($decorativeAsset in @($chromeManifest.decorative_assets)) {
    if ([string]::IsNullOrWhiteSpace($decorativeAsset.asset_id) -or [string]::IsNullOrWhiteSpace($decorativeAsset.source_sha256) -or [string]::IsNullOrWhiteSpace($decorativeAsset.derivation)) {
        throw "SpriteCook decorative asset provenance is incomplete"
    }
    $chromeFiles += $decorativeAsset.file
}
foreach ($imagegenAsset in @($chromeManifest.imagegen_assets)) {
    if ([string]::IsNullOrWhiteSpace($imagegenAsset.asset_id) -or $imagegenAsset.provider -ne "openai-imagegen" -or [string]::IsNullOrWhiteSpace($imagegenAsset.generation_job_id) -or [string]::IsNullOrWhiteSpace($imagegenAsset.source_sha256) -or [string]::IsNullOrWhiteSpace($imagegenAsset.derivation)) {
        throw "ImageGen decorative asset provenance is incomplete"
    }
    $chromeFiles += $imagegenAsset.file
}
foreach ($statusAsset in @($chromeManifest.status_assets)) {
    if ([string]::IsNullOrWhiteSpace($statusAsset.asset_id) -or [string]::IsNullOrWhiteSpace($statusAsset.generation_job_id) -or [string]::IsNullOrWhiteSpace($statusAsset.source_sha256) -or [string]::IsNullOrWhiteSpace($statusAsset.derivation)) {
        throw "SpriteCook status asset provenance is incomplete"
    }
    $chromeFiles += $statusAsset.file
}
foreach ($commandAsset in @($chromeManifest.command_assets)) {
    $hasBaseProvenance = -not [string]::IsNullOrWhiteSpace($commandAsset.asset_id) -and -not [string]::IsNullOrWhiteSpace($commandAsset.source_sha256) -and -not [string]::IsNullOrWhiteSpace($commandAsset.derivation)
    $hasProviderProvenance = if ($commandAsset.provider -eq "project-owner") {
        $commandAsset.license -eq "Project-Owner-Supplied"
    } else {
        -not [string]::IsNullOrWhiteSpace($commandAsset.generation_job_id)
    }
    if (-not $hasBaseProvenance -or -not $hasProviderProvenance) {
        throw "Command asset provenance is incomplete"
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
Write-Host "Classic application media verified: $($manifest.assets.Count) assets; fonts verified: $($fontManifest.assets.Count) assets; intro media verified: $($launchSplash.width)x$($launchSplash.height) launch + $($introManifest.width)x$($introManifest.height) video + $($introSoundtrack.duration_ms)ms soundtrack; generated chrome verified: $($chromeFiles.Count) files."
exit 0
