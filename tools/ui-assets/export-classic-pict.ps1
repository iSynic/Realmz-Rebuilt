param(
    [Parameter(Mandatory = $true)]
    [string]$ResourceForkPath,
    [Parameter(Mandatory = $true)]
    [int]$ResourceId,
    [Parameter(Mandatory = $true)]
    [string]$PictDecoderPath,
    [Parameter(Mandatory = $true)]
    [string]$OutputPath,
    [int]$CropX = 0,
    [int]$CropY = 0,
    [int]$CropWidth = 0,
    [int]$CropHeight = 0
)

$ErrorActionPreference = "Stop"
Add-Type -AssemblyName System.Drawing

function Get-U16([byte[]]$Bytes, [int]$Offset) {
    return ([int]$Bytes[$Offset] -shl 8) -bor [int]$Bytes[$Offset + 1]
}

function Get-I16([byte[]]$Bytes, [int]$Offset) {
    $value = Get-U16 $Bytes $Offset
    if ($value -ge 0x8000) { return $value - 0x10000 }
    return $value
}

function Get-U32([byte[]]$Bytes, [int]$Offset) {
    return ([uint32]$Bytes[$Offset] -shl 24) -bor ([uint32]$Bytes[$Offset + 1] -shl 16) -bor ([uint32]$Bytes[$Offset + 2] -shl 8) -bor [uint32]$Bytes[$Offset + 3]
}

function Get-ResourceBytes([byte[]]$ForkBytes, [string]$ResourceType, [int]$WantedId) {
    $dataOffset = [int](Get-U32 $ForkBytes 0)
    $mapOffset = [int](Get-U32 $ForkBytes 4)
    $typeListOffset = $mapOffset + (Get-U16 $ForkBytes ($mapOffset + 24))
    $rawTypeCount = Get-U16 $ForkBytes $typeListOffset
    for ($typeIndex = 0; $typeIndex -le $rawTypeCount; $typeIndex++) {
        $typeOffset = $typeListOffset + 2 + $typeIndex * 8
        if ([Text.Encoding]::ASCII.GetString($ForkBytes, $typeOffset, 4) -ne $ResourceType) { continue }
        $rawResourceCount = Get-U16 $ForkBytes ($typeOffset + 4)
        $referenceListOffset = $typeListOffset + (Get-U16 $ForkBytes ($typeOffset + 6))
        for ($referenceIndex = 0; $referenceIndex -le $rawResourceCount; $referenceIndex++) {
            $referenceOffset = $referenceListOffset + $referenceIndex * 12
            if ((Get-I16 $ForkBytes $referenceOffset) -ne $WantedId) { continue }
            $relativeOffset = ([int]$ForkBytes[$referenceOffset + 5] -shl 16) -bor ([int]$ForkBytes[$referenceOffset + 6] -shl 8) -bor [int]$ForkBytes[$referenceOffset + 7]
            $lengthOffset = $dataOffset + $relativeOffset
            $length = [int](Get-U32 $ForkBytes $lengthOffset)
            $resource = [byte[]]::new($length)
            [Array]::Copy($ForkBytes, $lengthOffset + 4, $resource, 0, $length)
            return $resource
        }
    }
    throw "Resource $ResourceType $WantedId was not found"
}

$decoder = (Resolve-Path -LiteralPath $PictDecoderPath).Path
$forkBytes = [IO.File]::ReadAllBytes((Resolve-Path -LiteralPath $ResourceForkPath).Path)
$rawPath = Join-Path ([IO.Path]::GetTempPath()) ("realmz2-pict-" + [Guid]::NewGuid().ToString("N") + ".pict")
$decodedPath = if ($CropWidth -gt 0 -or $CropHeight -gt 0) {
    Join-Path ([IO.Path]::GetTempPath()) ("realmz2-pict-" + [Guid]::NewGuid().ToString("N") + ".png")
}
else {
    $OutputPath
}
try {
    [IO.File]::WriteAllBytes($rawPath, (Get-ResourceBytes $forkBytes "PICT" $ResourceId))
    $parent = Split-Path -Parent $OutputPath
    if ($parent) { New-Item -ItemType Directory -Path $parent -Force | Out-Null }
    & $decoder $rawPath $decodedPath
    if ($LASTEXITCODE -ne 0 -or -not (Test-Path -LiteralPath $decodedPath -PathType Leaf)) {
        throw "PICT decoder failed for PICT $ResourceId"
    }
    if ($decodedPath -ne $OutputPath) {
        if ($CropX -lt 0 -or $CropY -lt 0 -or $CropWidth -le 0 -or $CropHeight -le 0) {
            throw "PICT crop rectangle is invalid for PICT $ResourceId"
        }
        $source = [Drawing.Bitmap]::new($decodedPath)
        try {
            $bounds = [Drawing.Rectangle]::new(0, 0, $source.Width, $source.Height)
            $cropBounds = [Drawing.Rectangle]::new($CropX, $CropY, $CropWidth, $CropHeight)
            if (-not $bounds.Contains($cropBounds)) {
                throw "PICT crop rectangle exceeds decoded PICT $ResourceId bounds"
            }
            $crop = $source.Clone($cropBounds, $source.PixelFormat)
            try {
                $crop.Save($OutputPath, [Drawing.Imaging.ImageFormat]::Png)
            }
            finally {
                $crop.Dispose()
            }
        }
        finally {
            $source.Dispose()
        }
    }
}
finally {
    if (Test-Path -LiteralPath $rawPath) { Remove-Item -LiteralPath $rawPath -Force }
    if ($decodedPath -ne $OutputPath -and (Test-Path -LiteralPath $decodedPath)) { Remove-Item -LiteralPath $decodedPath -Force }
}
