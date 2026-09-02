param(
    [Parameter(Mandatory = $true)]
    [string]$SourcePng,
    [int]$TargetWidth = 48,
    [int]$TargetHeight = 468
)

$ErrorActionPreference = "Stop"
Add-Type -AssemblyName System.Drawing
$toolRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
$repoRoot = Split-Path -Parent (Split-Path -Parent $toolRoot)
$outputPath = Join-Path $repoRoot "src/presentation/assets/ui/classic-exploration-rail.png"
$sourcePath = (Resolve-Path -LiteralPath $SourcePng).Path
$stagingPath = Join-Path ([IO.Path]::GetTempPath()) ("realmz2-exploration-rail-" + [Guid]::NewGuid().ToString("N") + ".png")

if ($TargetWidth -lt 1 -or $TargetHeight -lt 1) {
    throw "Target dimensions must be positive."
}

$source = [Drawing.Bitmap]::new([string]$sourcePath)
try {
    $minimumX = $source.Width
    $minimumY = $source.Height
    $maximumX = -1
    $maximumY = -1
    for ($y = 0; $y -lt $source.Height; $y++) {
        for ($x = 0; $x -lt $source.Width; $x++) {
            if ($source.GetPixel($x, $y).A -eq 0) {
                continue
            }
            $minimumX = [Math]::Min($minimumX, $x)
            $minimumY = [Math]::Min($minimumY, $y)
            $maximumX = [Math]::Max($maximumX, $x)
            $maximumY = [Math]::Max($maximumY, $y)
        }
    }
    if ($maximumX -lt $minimumX -or $maximumY -lt $minimumY) {
        throw "The selected rail has no visible pixels."
    }

    $sourceRect = [Drawing.Rectangle]::new(
        $minimumX,
        $minimumY,
        $maximumX - $minimumX + 1,
        $maximumY - $minimumY + 1
    )
    $output = [Drawing.Bitmap]::new($TargetWidth, $TargetHeight, [Drawing.Imaging.PixelFormat]::Format32bppArgb)
    $graphics = [Drawing.Graphics]::FromImage($output)
    try {
        $graphics.Clear([Drawing.Color]::Transparent)
        $graphics.CompositingMode = [Drawing.Drawing2D.CompositingMode]::SourceCopy
        $graphics.CompositingQuality = [Drawing.Drawing2D.CompositingQuality]::HighQuality
        $graphics.InterpolationMode = [Drawing.Drawing2D.InterpolationMode]::HighQualityBicubic
        $graphics.PixelOffsetMode = [Drawing.Drawing2D.PixelOffsetMode]::HighQuality
        $graphics.DrawImage(
            $source,
            [Drawing.Rectangle]::new(0, 0, $TargetWidth, $TargetHeight),
            $sourceRect,
            [Drawing.GraphicsUnit]::Pixel
        )
    }
    finally { $graphics.Dispose() }
    try { $output.Save($stagingPath, [Drawing.Imaging.ImageFormat]::Png) }
    finally { $output.Dispose() }

    New-Item -ItemType Directory -Path (Split-Path -Parent $outputPath) -Force | Out-Null
    Copy-Item -LiteralPath $stagingPath -Destination $outputPath -Force
    $sourceHash = (Get-FileHash -Algorithm SHA256 -LiteralPath $sourcePath).Hash.ToLowerInvariant()
    $outputHash = (Get-FileHash -Algorithm SHA256 -LiteralPath $outputPath).Hash.ToLowerInvariant()
    Write-Host "Built exploration rail from crop $($sourceRect.X),$($sourceRect.Y),$($sourceRect.Width),$($sourceRect.Height)."
    Write-Host "Source SHA-256: $sourceHash"
    Write-Host "Output SHA-256: $outputHash"
}
finally {
    $source.Dispose()
    if (Test-Path -LiteralPath $stagingPath) {
        Remove-Item -LiteralPath $stagingPath -Force
    }
}
