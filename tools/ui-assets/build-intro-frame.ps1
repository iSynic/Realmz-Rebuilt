param(
    [Parameter(Mandatory = $true)]
    [string]$SourcePng,

    [string]$ExpectedSourceSha256 = "2bd8594faccb531aa1c0a9d013e2136ccbfe6017d8f6d3ce00fb327327ae4878"
)

$ErrorActionPreference = "Stop"
Add-Type -AssemblyName System.Drawing

$toolRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
$repoRoot = Split-Path -Parent (Split-Path -Parent $toolRoot)
$outputPath = Join-Path $repoRoot "src/presentation/assets/ui/classic-intro-frame.png"
$sourcePath = (Resolve-Path -LiteralPath $SourcePng).Path
$sourceHash = (Get-FileHash -Algorithm SHA256 -LiteralPath $sourcePath).Hash.ToLowerInvariant()
if ($sourceHash -ne $ExpectedSourceSha256.ToLowerInvariant()) {
    throw "Intro-frame source hash does not match the approved SpriteCook asset"
}

$stagingPath = Join-Path ([IO.Path]::GetTempPath()) ("realmz-intro-frame-" + [Guid]::NewGuid().ToString("N") + ".png")
$source = [Drawing.Bitmap]::new([string]$sourcePath)
try {
    if ($source.Width -ne 1024 -or $source.Height -ne 1024) {
        throw "Intro-frame source must be 1024x1024"
    }

    $working = [Drawing.Bitmap]$source.Clone()
    try {
        # SpriteCook supplied an alpha exterior but an opaque neutral center.
        # Clear only the measured opening, leaving the inner gold fillet intact.
        for ($y = 181; $y -le 841; $y++) {
            for ($x = 181; $x -le 841; $x++) {
                $working.SetPixel($x, $y, [Drawing.Color]::Transparent)
            }
        }

        $output = [Drawing.Bitmap]::new(512, 512, [Drawing.Imaging.PixelFormat]::Format32bppArgb)
        try {
            $graphics = [Drawing.Graphics]::FromImage($output)
            try {
                $graphics.Clear([Drawing.Color]::Transparent)
                $graphics.CompositingMode = [Drawing.Drawing2D.CompositingMode]::SourceCopy
                $graphics.CompositingQuality = [Drawing.Drawing2D.CompositingQuality]::HighQuality
                $graphics.InterpolationMode = [Drawing.Drawing2D.InterpolationMode]::HighQualityBicubic
                $graphics.PixelOffsetMode = [Drawing.Drawing2D.PixelOffsetMode]::HighQuality
                $graphics.DrawImage(
                    $working,
                    [Drawing.Rectangle]::new(0, 0, 512, 512),
                    [Drawing.Rectangle]::new(88, 88, 848, 848),
                    [Drawing.GraphicsUnit]::Pixel
                )
            }
            finally { $graphics.Dispose() }

            if ($output.GetPixel(256, 256).A -ne 0 -or $output.GetPixel(8, 256).A -eq 0) {
                throw "Derived intro frame does not preserve the expected transparent opening and visible rail"
            }
            $output.Save($stagingPath, [Drawing.Imaging.ImageFormat]::Png)
        }
        finally { $output.Dispose() }
    }
    finally { $working.Dispose() }

    New-Item -ItemType Directory -Force -Path (Split-Path -Parent $outputPath) | Out-Null
    Copy-Item -LiteralPath $stagingPath -Destination $outputPath -Force
    $outputHash = (Get-FileHash -Algorithm SHA256 -LiteralPath $outputPath).Hash.ToLowerInvariant()
    Write-Host "Built 512x512 intro frame from SpriteCook asset source."
    Write-Host "Source SHA-256: $sourceHash"
    Write-Host "Output SHA-256: $outputHash"
}
finally {
    $source.Dispose()
    if (Test-Path -LiteralPath $stagingPath) {
        Remove-Item -LiteralPath $stagingPath -Force
    }
}
