param(
    [Parameter(Mandatory = $true)]
    [string]$SourceGifPath,

    [string]$ExpectedSha256 = "43dd46139afab9f63f08b782781d476c91cf3a7bc21b7b8ae69b7ea47ac7f3fb"
)

$ErrorActionPreference = "Stop"
Add-Type -AssemblyName System.Drawing

$toolRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
$repoRoot = Split-Path -Parent (Split-Path -Parent $toolRoot)
$destinationRoot = Join-Path $repoRoot "src/presentation/assets/ui/intro"
$stagingRoot = Join-Path ([IO.Path]::GetTempPath()) ("realmz-intro-" + [Guid]::NewGuid().ToString("N"))
$sourcePath = (Resolve-Path -LiteralPath $SourceGifPath).Path
$sourceHash = (Get-FileHash -Algorithm SHA256 -LiteralPath $sourcePath).Hash.ToLowerInvariant()
if ($sourceHash -ne $ExpectedSha256.ToLowerInvariant()) {
    throw "Realmz intro GIF hash does not match the approved source"
}

$resolvedDestination = [IO.Path]::GetFullPath($destinationRoot)
$resolvedRepo = [IO.Path]::GetFullPath($repoRoot).TrimEnd([IO.Path]::DirectorySeparatorChar) + [IO.Path]::DirectorySeparatorChar
if (-not $resolvedDestination.StartsWith($resolvedRepo, [StringComparison]::OrdinalIgnoreCase)) {
    throw "Intro destination escapes the repository: $resolvedDestination"
}

$image = [Drawing.Image]::FromFile($sourcePath)
try {
    $dimension = [Drawing.Imaging.FrameDimension]::new($image.FrameDimensionsList[0])
    $sourceFrameCount = $image.GetFrameCount($dimension)
    if ($image.Width -ne 640 -or $image.Height -ne 608 -or $sourceFrameCount -ne 124) {
        throw "Realmz intro GIF shape changed; expected 640x608 and 124 frames"
    }
    $delayProperty = $image.GetPropertyItem(0x5100)
    $delayValues = @()
    for ($index = 0; $index -lt $sourceFrameCount; $index++) {
        $delayValues += [Math]::Max(10, [BitConverter]::ToInt32($delayProperty.Value, $index * 4) * 10)
    }

    New-Item -ItemType Directory -Path $stagingRoot | Out-Null
    $outputWidth = 320
    $outputHeight = 304
    $sampleStride = 4
    $records = @()
    for ($sourceIndex = 0; $sourceIndex -lt $sourceFrameCount; $sourceIndex += $sampleStride) {
        [void]$image.SelectActiveFrame($dimension, $sourceIndex)
        $bitmap = [Drawing.Bitmap]::new($outputWidth, $outputHeight, [Drawing.Imaging.PixelFormat]::Format32bppArgb)
        try {
            $graphics = [Drawing.Graphics]::FromImage($bitmap)
            try {
                $graphics.CompositingMode = [Drawing.Drawing2D.CompositingMode]::SourceCopy
                $graphics.InterpolationMode = [Drawing.Drawing2D.InterpolationMode]::NearestNeighbor
                $graphics.PixelOffsetMode = [Drawing.Drawing2D.PixelOffsetMode]::Half
                $graphics.SmoothingMode = [Drawing.Drawing2D.SmoothingMode]::None
                $graphics.DrawImage($image, [Drawing.Rectangle]::new(0, 0, $outputWidth, $outputHeight), 0, 0, $image.Width, $image.Height, [Drawing.GraphicsUnit]::Pixel)
            }
            finally { $graphics.Dispose() }
            $outputIndex = [int]($sourceIndex / $sampleStride)
            $filename = "realmz-intro-{0:D2}.png" -f $outputIndex
            $outputPath = Join-Path $stagingRoot $filename
            $bitmap.Save($outputPath, [Drawing.Imaging.ImageFormat]::Png)
            $duration = 0
            for ($delayIndex = $sourceIndex; $delayIndex -lt [Math]::Min($sourceIndex + $sampleStride, $sourceFrameCount); $delayIndex++) {
                $duration += $delayValues[$delayIndex]
            }
            $records += [ordered]@{
                path = "res://src/presentation/assets/ui/intro/$filename"
                duration_ms = $duration
                width = $outputWidth
                height = $outputHeight
                sha256 = (Get-FileHash -Algorithm SHA256 -LiteralPath $outputPath).Hash.ToLowerInvariant()
            }
        }
        finally { $bitmap.Dispose() }
    }

    $manifest = [ordered]@{
        schema_version = 1
        source_role = "licensed Realmz intro animation supplied by the project owner"
        source_sha256 = $sourceHash
        license = "Realmz-Art-NonCommercial"
        source_width = $image.Width
        source_height = $image.Height
        source_frames = $sourceFrameCount
        sample_stride = $sampleStride
        frames = $records
    }
    [IO.File]::WriteAllText((Join-Path $stagingRoot "intro-animation.json"), (($manifest | ConvertTo-Json -Depth 6) + [Environment]::NewLine), [Text.UTF8Encoding]::new($false))

    if (Test-Path -LiteralPath $resolvedDestination) {
        Remove-Item -LiteralPath $resolvedDestination -Recurse -Force
    }
    Move-Item -LiteralPath $stagingRoot -Destination $resolvedDestination
    Write-Host "Imported $($records.Count) Realmz intro frames at ${outputWidth}x${outputHeight}; preserved $([Math]::Round(($delayValues | Measure-Object -Sum).Sum / 1000.0, 2)) seconds of loop timing."
}
finally {
    $image.Dispose()
    if (Test-Path -LiteralPath $stagingRoot) { Remove-Item -LiteralPath $stagingRoot -Recurse -Force }
}
