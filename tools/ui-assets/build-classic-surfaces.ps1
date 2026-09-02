param(
    [string]$SourcePng = "",
    [string]$SpriteCookAssetId = "",
    [string]$SpriteCookLabel = "",
    [switch]$RebuildFromCommittedSurface
)

$ErrorActionPreference = "Stop"
Add-Type -AssemblyName System.Drawing
$toolRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
$repoRoot = Split-Path -Parent (Split-Path -Parent $toolRoot)
$outputRoot = Join-Path $repoRoot "src/presentation/assets/ui"
$committedSurfacePath = Join-Path $outputRoot "classic-charcoal-slate.png"
$committedManifestPath = Join-Path $outputRoot "spritecook-assets.json"
$stagingRoot = Join-Path ([IO.Path]::GetTempPath()) ("realmz2-ui-surfaces-" + [Guid]::NewGuid().ToString("N"))
New-Item -ItemType Directory -Path $stagingRoot | Out-Null
$decorativeAssets = @()
$imagegenAssets = @()
$statusAssets = @()
$commandAssets = @()
if (Test-Path -LiteralPath $committedManifestPath) {
    $committedManifest = Get-Content -Raw -LiteralPath $committedManifestPath | ConvertFrom-Json
    if ($null -ne $committedManifest.decorative_assets) {
        $decorativeAssets = @($committedManifest.decorative_assets)
    }
    if ($null -ne $committedManifest.imagegen_assets) {
        $imagegenAssets = @($committedManifest.imagegen_assets)
    }
    if ($null -ne $committedManifest.status_assets) {
        $statusAssets = @($committedManifest.status_assets)
    }
    if ($null -ne $committedManifest.command_assets) {
        $commandAssets = @($committedManifest.command_assets)
    }
}

function Save-Png([Drawing.Bitmap]$bitmap, [string]$path) {
    $bitmap.Save($path, [Drawing.Imaging.ImageFormat]::Png)
    $bytes = [IO.File]::ReadAllBytes($path)
    if ($bytes.Length -lt 24 -or [Text.Encoding]::ASCII.GetString($bytes, 1, 3) -ne "PNG") {
        throw "Generated surface is not a valid PNG: $path"
    }
}

function New-SeamlessTile([Drawing.Bitmap]$source, [int]$blendWidth = 64) {
    if ($source.Width -lt $blendWidth * 2 -or $source.Height -lt $blendWidth * 2) {
        throw "The selected surface is too small for a $blendWidth-pixel edge feather."
    }
    $horizontal = [Drawing.Bitmap]$source.Clone()
    for ($y = 0; $y -lt $source.Height; $y++) {
        for ($offset = 0; $offset -lt $blendWidth; $offset++) {
            $opposite = $source.Width - 1 - $offset
            $weight = 0.25 * (1.0 + [Math]::Cos([Math]::PI * $offset / $blendWidth))
            $left = $source.GetPixel($offset, $y)
            $right = $source.GetPixel($opposite, $y)
            $horizontal.SetPixel($offset, $y, [Drawing.Color]::FromArgb(
                [int][Math]::Round($left.A * (1.0 - $weight) + $right.A * $weight),
                [int][Math]::Round($left.R * (1.0 - $weight) + $right.R * $weight),
                [int][Math]::Round($left.G * (1.0 - $weight) + $right.G * $weight),
                [int][Math]::Round($left.B * (1.0 - $weight) + $right.B * $weight)
            ))
            $horizontal.SetPixel($opposite, $y, [Drawing.Color]::FromArgb(
                [int][Math]::Round($right.A * (1.0 - $weight) + $left.A * $weight),
                [int][Math]::Round($right.R * (1.0 - $weight) + $left.R * $weight),
                [int][Math]::Round($right.G * (1.0 - $weight) + $left.G * $weight),
                [int][Math]::Round($right.B * (1.0 - $weight) + $left.B * $weight)
            ))
        }
    }
    $result = [Drawing.Bitmap]$horizontal.Clone()
    try {
        for ($x = 0; $x -lt $horizontal.Width; $x++) {
            for ($offset = 0; $offset -lt $blendWidth; $offset++) {
                $opposite = $horizontal.Height - 1 - $offset
                $weight = 0.25 * (1.0 + [Math]::Cos([Math]::PI * $offset / $blendWidth))
                $top = $horizontal.GetPixel($x, $offset)
                $bottom = $horizontal.GetPixel($x, $opposite)
                $result.SetPixel($x, $offset, [Drawing.Color]::FromArgb(
                    [int][Math]::Round($top.A * (1.0 - $weight) + $bottom.A * $weight),
                    [int][Math]::Round($top.R * (1.0 - $weight) + $bottom.R * $weight),
                    [int][Math]::Round($top.G * (1.0 - $weight) + $bottom.G * $weight),
                    [int][Math]::Round($top.B * (1.0 - $weight) + $bottom.B * $weight)
                ))
                $result.SetPixel($x, $opposite, [Drawing.Color]::FromArgb(
                    [int][Math]::Round($bottom.A * (1.0 - $weight) + $top.A * $weight),
                    [int][Math]::Round($bottom.R * (1.0 - $weight) + $top.R * $weight),
                    [int][Math]::Round($bottom.G * (1.0 - $weight) + $top.G * $weight),
                    [int][Math]::Round($bottom.B * (1.0 - $weight) + $top.B * $weight)
                ))
            }
        }
    }
    finally { $horizontal.Dispose() }
    return $result
}

try {
    $selectedAsset = $null
    $basePath = Join-Path $stagingRoot "classic-charcoal-slate.png"
    if ($RebuildFromCommittedSurface) {
        if (-not [string]::IsNullOrWhiteSpace($SourcePng) -or -not [string]::IsNullOrWhiteSpace($SpriteCookAssetId) -or -not [string]::IsNullOrWhiteSpace($SpriteCookLabel)) {
            throw "RebuildFromCommittedSurface cannot be combined with source-import arguments."
        }
        if (-not (Test-Path -LiteralPath $committedSurfacePath) -or -not (Test-Path -LiteralPath $committedManifestPath)) {
            throw "The committed selected surface and manifest are required for an offline rebuild."
        }
        $existingManifest = Get-Content -Raw -LiteralPath $committedManifestPath | ConvertFrom-Json
        $selectedAsset = [ordered]@{
            asset_id = [string]$existingManifest.selected_asset.asset_id
            label = [string]$existingManifest.selected_asset.label
            source_sha256 = [string]$existingManifest.selected_asset.source_sha256
            source_sha256_prefix = [string]$existingManifest.selected_asset.source_sha256_prefix
            mode = [string]$existingManifest.selected_asset.mode
        }
        Copy-Item -LiteralPath $committedSurfacePath -Destination $basePath
    }
    else {
        if ([string]::IsNullOrWhiteSpace($SourcePng) -or [string]::IsNullOrWhiteSpace($SpriteCookAssetId) -or [string]::IsNullOrWhiteSpace($SpriteCookLabel)) {
            throw "SourcePng, SpriteCookAssetId, and SpriteCookLabel are required when importing a selected SpriteCook surface."
        }
        $sourcePath = (Resolve-Path -LiteralPath $SourcePng).Path
        $source = [Drawing.Bitmap]::new([string]$sourcePath)
        try {
            $base = [Drawing.Bitmap]::new(512, 512, [Drawing.Imaging.PixelFormat]::Format32bppArgb)
            $graphics = [Drawing.Graphics]::FromImage($base)
            try {
                $graphics.InterpolationMode = [Drawing.Drawing2D.InterpolationMode]::HighQualityBicubic
                $graphics.PixelOffsetMode = [Drawing.Drawing2D.PixelOffsetMode]::HighQuality
                $graphics.DrawImage($source, [Drawing.Rectangle]::new(0, 0, 512, 512))
            }
            finally { $graphics.Dispose() }
            Save-Png $base $basePath
            $base.Dispose()
        }
        finally { $source.Dispose() }
        $sourceHash = (Get-FileHash -Algorithm SHA256 -LiteralPath $sourcePath).Hash.ToLowerInvariant()
        $selectedAsset = [ordered]@{
            asset_id = $SpriteCookAssetId
            label = $SpriteCookLabel
            source_sha256 = $sourceHash
            source_sha256_prefix = $sourceHash.Substring(0, 12)
            mode = "texture"
        }
    }

    $baseSurface = [Drawing.Bitmap]::new([string]$basePath)
    try {
        $seamlessTile = New-SeamlessTile $baseSurface
        try {
            Save-Png $seamlessTile (Join-Path $stagingRoot "classic-charcoal-slate-tile.png")
            foreach ($definition in @(
                @{ Name = "classic-raised-frame.png"; Top = [Drawing.Color]::FromArgb(190, 128, 138, 139); Bottom = [Drawing.Color]::FromArgb(220, 8, 11, 13) },
                @{ Name = "classic-inset-frame.png"; Top = [Drawing.Color]::FromArgb(225, 6, 8, 10); Bottom = [Drawing.Color]::FromArgb(180, 112, 121, 122) }
            )) {
                $frame = [Drawing.Bitmap]::new($seamlessTile.Width + 16, $seamlessTile.Height + 16, [Drawing.Imaging.PixelFormat]::Format32bppArgb)
                $frameGraphics = [Drawing.Graphics]::FromImage($frame)
                try {
                    $frameGraphics.Clear([Drawing.Color]::FromArgb(255, 24, 27, 28))
                    $tileBrush = [Drawing.TextureBrush]::new($seamlessTile, [Drawing.Drawing2D.WrapMode]::Tile)
                    try { $frameGraphics.FillRectangle($tileBrush, 0, 0, $frame.Width, $frame.Height) }
                    finally { $tileBrush.Dispose() }
                    $topPen = [Drawing.Pen]::new($definition.Top, 3)
                    $bottomPen = [Drawing.Pen]::new($definition.Bottom, 3)
                    try {
                        $maximum = $frame.Width - 2
                        $frameGraphics.DrawLine($topPen, 1, 1, $maximum, 1)
                        $frameGraphics.DrawLine($topPen, 1, 1, 1, $maximum)
                        $frameGraphics.DrawLine($bottomPen, 2, $maximum, $maximum, $maximum)
                        $frameGraphics.DrawLine($bottomPen, $maximum, 2, $maximum, $maximum)
                        $innerPen = [Drawing.Pen]::new([Drawing.Color]::FromArgb(170, 31, 38, 40), 1)
                        try { $frameGraphics.DrawRectangle($innerPen, 5, 5, $frame.Width - 11, $frame.Height - 11) }
                        finally { $innerPen.Dispose() }
                    }
                    finally {
                        $topPen.Dispose()
                        $bottomPen.Dispose()
                    }
                }
                finally { $frameGraphics.Dispose() }
                Save-Png $frame (Join-Path $stagingRoot $definition.Name)
                $frame.Dispose()
            }
        }
        finally { $seamlessTile.Dispose() }
    }
    finally { $baseSurface.Dispose() }

    $surfaceNames = @(
        "classic-charcoal-slate.png",
        "classic-charcoal-slate-tile.png",
        "classic-raised-frame.png",
        "classic-inset-frame.png"
    )
    $records = @()
    foreach ($name in $surfaceNames) {
        $path = Join-Path $stagingRoot $name
        $bitmap = [Drawing.Bitmap]::new([string]$path)
        try {
            $records += [ordered]@{
                path = "res://src/presentation/assets/ui/$name"
                width = $bitmap.Width
                height = $bitmap.Height
                sha256 = (Get-FileHash -Algorithm SHA256 -LiteralPath $path).Hash.ToLowerInvariant()
            }
        }
        finally { $bitmap.Dispose() }
    }
    $manifest = [ordered]@{
        schema_version = 8
        selected_asset = $selectedAsset
        decorative_assets = $decorativeAssets
        imagegen_assets = $imagegenAssets
        status_assets = $statusAssets
        command_assets = $commandAssets
        derivation = [ordered]@{
            generator = "tools/ui-assets/build-classic-surfaces.ps1"
            algorithm = "system-drawing-bicubic-512-plus-cosine-feathered-512-tile-and-opaque-528px-bevel-v3"
            seamless_strategy = "64px-cosine-opposite-edge-feather"
        }
        files = $records
    }
    $manifestPath = Join-Path $stagingRoot "spritecook-assets.json"
    [IO.File]::WriteAllText($manifestPath, (($manifest | ConvertTo-Json -Depth 6) + [Environment]::NewLine), [Text.UTF8Encoding]::new($false))

    New-Item -ItemType Directory -Path $outputRoot -Force | Out-Null
    foreach ($name in $surfaceNames + @("spritecook-assets.json")) {
        Copy-Item -LiteralPath (Join-Path $stagingRoot $name) -Destination (Join-Path $outputRoot $name) -Force
    }
    Write-Host "Built Classic slate surfaces from SpriteCook asset $($selectedAsset.asset_id)."
}
finally {
    if (Test-Path -LiteralPath $stagingRoot) {
        Remove-Item -LiteralPath $stagingRoot -Recurse -Force
    }
}
