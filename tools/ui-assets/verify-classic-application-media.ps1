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
$combatIconCount = @($manifest.assets | Where-Object { $_.resource_type -eq "cicn" }).Count
if ($soundCount -ne 142 -or $combatIconCount -ne 145) {
    throw "Expected 142 built-in sounds and 145 source-backed combat icons; found $soundCount sounds and $combatIconCount icons"
}

$chromeManifestPath = Join-Path $repoRoot "src/presentation/assets/ui/spritecook-assets.json"
if (-not (Test-Path -LiteralPath $chromeManifestPath -PathType Leaf)) {
    throw "SpriteCook chrome manifest is missing"
}
$chromeManifest = Get-Content -Raw -LiteralPath $chromeManifestPath | ConvertFrom-Json
if ($chromeManifest.schema_version -ne 5 -or [string]::IsNullOrWhiteSpace($chromeManifest.selected_asset.asset_id)) {
    throw "SpriteCook chrome manifest contract is unsupported"
}
$chromeFiles = @($chromeManifest.files)
foreach ($decorativeAsset in @($chromeManifest.decorative_assets)) {
    if ([string]::IsNullOrWhiteSpace($decorativeAsset.asset_id) -or [string]::IsNullOrWhiteSpace($decorativeAsset.source_sha256) -or [string]::IsNullOrWhiteSpace($decorativeAsset.derivation)) {
        throw "SpriteCook decorative asset provenance is incomplete"
    }
    $chromeFiles += $decorativeAsset.file
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
Write-Host "Classic application media verified: $($manifest.assets.Count) assets; generated chrome verified: $($chromeFiles.Count) files."
exit 0
