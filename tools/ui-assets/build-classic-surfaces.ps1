param(
    [Parameter(Mandatory = $true)]
    [string]$SourcePng,
    [Parameter(Mandatory = $true)]
    [string]$SpriteCookAssetId,
    [Parameter(Mandatory = $true)]
    [string]$SpriteCookLabel
)

$ErrorActionPreference = "Stop"
Add-Type -AssemblyName System.Drawing
$toolRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
$repoRoot = Split-Path -Parent (Split-Path -Parent $toolRoot)
$sourcePath = (Resolve-Path -LiteralPath $SourcePng).Path
$outputRoot = Join-Path $repoRoot "src/presentation/assets/ui"
$stagingRoot = Join-Path ([IO.Path]::GetTempPath()) ("realmz2-ui-surfaces-" + [Guid]::NewGuid().ToString("N"))
New-Item -ItemType Directory -Path $stagingRoot | Out-Null

function Save-Png([Drawing.Bitmap]$bitmap, [string]$path) {
    $bitmap.Save($path, [Drawing.Imaging.ImageFormat]::Png)
    $bytes = [IO.File]::ReadAllBytes($path)
    if ($bytes.Length -lt 24 -or [Text.Encoding]::ASCII.GetString($bytes, 1, 3) -ne "PNG") {
        throw "Generated surface is not a valid PNG: $path"
    }
}

try {
    $source = [Drawing.Bitmap]::new($sourcePath)
    try {
        $tile = [Drawing.Bitmap]::new(512, 512, [Drawing.Imaging.PixelFormat]::Format32bppArgb)
        $graphics = [Drawing.Graphics]::FromImage($tile)
        try {
            $graphics.InterpolationMode = [Drawing.Drawing2D.InterpolationMode]::HighQualityBicubic
            $graphics.PixelOffsetMode = [Drawing.Drawing2D.PixelOffsetMode]::HighQuality
            $graphics.DrawImage($source, [Drawing.Rectangle]::new(0, 0, 512, 512))
        }
        finally { $graphics.Dispose() }
        Save-Png $tile (Join-Path $stagingRoot "classic-charcoal-slate.png")

        foreach ($definition in @(
            @{ Name = "classic-raised-frame.png"; Top = [Drawing.Color]::FromArgb(190, 128, 138, 139); Bottom = [Drawing.Color]::FromArgb(220, 8, 11, 13) },
            @{ Name = "classic-inset-frame.png"; Top = [Drawing.Color]::FromArgb(225, 6, 8, 10); Bottom = [Drawing.Color]::FromArgb(180, 112, 121, 122) }
        )) {
            $frame = [Drawing.Bitmap]::new(64, 64, [Drawing.Imaging.PixelFormat]::Format32bppArgb)
            $frameGraphics = [Drawing.Graphics]::FromImage($frame)
            try {
                $frameGraphics.InterpolationMode = [Drawing.Drawing2D.InterpolationMode]::HighQualityBicubic
                $frameGraphics.DrawImage($tile, [Drawing.Rectangle]::new(0, 0, 64, 64))
                $topPen = [Drawing.Pen]::new($definition.Top, 3)
                $bottomPen = [Drawing.Pen]::new($definition.Bottom, 3)
                try {
                    $frameGraphics.DrawLine($topPen, 1, 1, 62, 1)
                    $frameGraphics.DrawLine($topPen, 1, 1, 1, 62)
                    $frameGraphics.DrawLine($bottomPen, 2, 62, 62, 62)
                    $frameGraphics.DrawLine($bottomPen, 62, 2, 62, 62)
                    $innerPen = [Drawing.Pen]::new([Drawing.Color]::FromArgb(170, 31, 38, 40), 1)
                    try { $frameGraphics.DrawRectangle($innerPen, 5, 5, 53, 53) }
                    finally { $innerPen.Dispose() }
                }
                finally { $topPen.Dispose(); $bottomPen.Dispose() }
            }
            finally { $frameGraphics.Dispose() }
            Save-Png $frame (Join-Path $stagingRoot $definition.Name)
            $frame.Dispose()
        }
        $tile.Dispose()
    }
    finally { $source.Dispose() }

    $records = @()
    foreach ($name in @("classic-charcoal-slate.png", "classic-raised-frame.png", "classic-inset-frame.png")) {
        $path = Join-Path $stagingRoot $name
        $bitmap = [Drawing.Bitmap]::new($path)
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
    $sourceHash = (Get-FileHash -Algorithm SHA256 -LiteralPath $sourcePath).Hash.ToLowerInvariant()
    $manifest = [ordered]@{
        schema_version = 2
        selected_asset = [ordered]@{
            asset_id = $SpriteCookAssetId
            label = $SpriteCookLabel
            source_sha256 = $sourceHash
            source_sha256_prefix = $sourceHash.Substring(0, 12)
            mode = "texture"
        }
        derivation = [ordered]@{
            generator = "tools/ui-assets/build-classic-surfaces.ps1"
            algorithm = "system-drawing-bicubic-512-plus-deterministic-64px-bevel-v1"
        }
        files = $records
    }
    $manifestPath = Join-Path $stagingRoot "spritecook-assets.json"
    [IO.File]::WriteAllText($manifestPath, (($manifest | ConvertTo-Json -Depth 6) + [Environment]::NewLine), [Text.UTF8Encoding]::new($false))

    New-Item -ItemType Directory -Path $outputRoot -Force | Out-Null
    foreach ($name in @("classic-charcoal-slate.png", "classic-raised-frame.png", "classic-inset-frame.png", "spritecook-assets.json")) {
        Copy-Item -LiteralPath (Join-Path $stagingRoot $name) -Destination (Join-Path $outputRoot $name) -Force
    }
    Write-Host "Built Classic slate surfaces from SpriteCook asset $SpriteCookAssetId."
}
finally {
    if (Test-Path -LiteralPath $stagingRoot) {
        Remove-Item -LiteralPath $stagingRoot -Recurse -Force
    }
}
