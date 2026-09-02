param(
    [Parameter(Mandatory = $true)]
    [string]$ResourceForkPath,
    [Parameter(Mandatory = $true)]
    [int]$ResourceId,
    [Parameter(Mandatory = $true)]
    [int]$ExpectedHotspotX,
    [Parameter(Mandatory = $true)]
    [int]$ExpectedHotspotY,
    [Parameter(Mandatory = $true)]
    [string]$OutputPath
)

$ErrorActionPreference = "Stop"

function Get-U16([byte[]]$Bytes, [int]$Offset) {
    return ([int]$Bytes[$Offset] -shl 8) -bor [int]$Bytes[$Offset + 1]
}

function Get-I16([byte[]]$Bytes, [int]$Offset) {
    $value = Get-U16 $Bytes $Offset
    if ($value -ge 0x8000) {
        return $value - 0x10000
    }
    return $value
}

function Get-U32([byte[]]$Bytes, [int]$Offset) {
    return ([uint32]$Bytes[$Offset] -shl 24) -bor ([uint32]$Bytes[$Offset + 1] -shl 16) -bor ([uint32]$Bytes[$Offset + 2] -shl 8) -bor [uint32]$Bytes[$Offset + 3]
}

function Get-ResourceBytes([byte[]]$ForkBytes, [string]$ResourceType, [int]$WantedId) {
    if ($ForkBytes.Length -lt 32) {
        throw "Resource fork is too short"
    }
    $dataOffset = [int](Get-U32 $ForkBytes 0)
    $mapOffset = [int](Get-U32 $ForkBytes 4)
    $typeListOffset = $mapOffset + (Get-U16 $ForkBytes ($mapOffset + 24))
    $rawTypeCount = Get-U16 $ForkBytes $typeListOffset
    if ($rawTypeCount -eq 0xffff) {
        throw "Resource fork has no resource types"
    }
    for ($typeIndex = 0; $typeIndex -le $rawTypeCount; $typeIndex++) {
        $typeOffset = $typeListOffset + 2 + $typeIndex * 8
        $type = [Text.Encoding]::ASCII.GetString($ForkBytes, $typeOffset, 4)
        if ($type -ne $ResourceType) {
            continue
        }
        $rawResourceCount = Get-U16 $ForkBytes ($typeOffset + 4)
        $referenceListOffset = $typeListOffset + (Get-U16 $ForkBytes ($typeOffset + 6))
        for ($referenceIndex = 0; $referenceIndex -le $rawResourceCount; $referenceIndex++) {
            $referenceOffset = $referenceListOffset + $referenceIndex * 12
            if ((Get-I16 $ForkBytes $referenceOffset) -ne $WantedId) {
                continue
            }
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

function Export-CrsrPng([byte[]]$Crsr, [string]$Destination, [int]$WantedHotspotX, [int]$WantedHotspotY) {
    if ($Crsr.Length -lt 96 -or ((Get-U16 $Crsr 0) -band 0xfffe) -ne 0x8000) {
        throw "Unsupported crsr resource header"
    }
    $pixelMapOffset = [int](Get-U32 $Crsr 2) + 4
    $pixelDataOffset = [int](Get-U32 $Crsr 6)
    $hotspotY = Get-U16 $Crsr 84
    $hotspotX = Get-U16 $Crsr 86
    if ($hotspotX -ne $WantedHotspotX -or $hotspotY -ne $WantedHotspotY) {
        throw "crsr hotspot mismatch: expected $WantedHotspotX,$WantedHotspotY; got $hotspotX,$hotspotY"
    }

    $rowBytes = (Get-U16 $Crsr $pixelMapOffset) -band 0x3fff
    $top = Get-I16 $Crsr ($pixelMapOffset + 2)
    $left = Get-I16 $Crsr ($pixelMapOffset + 4)
    $height = (Get-I16 $Crsr ($pixelMapOffset + 6)) - $top
    $width = (Get-I16 $Crsr ($pixelMapOffset + 8)) - $left
    $pixelSize = Get-U16 $Crsr ($pixelMapOffset + 28)
    $colorTableOffset = [int](Get-U32 $Crsr ($pixelMapOffset + 38))
    if ($width -le 0 -or $height -le 0 -or $width -gt 256 -or $height -gt 256 -or $pixelSize -notin @(1, 2, 4, 8)) {
        throw "Unsupported crsr geometry"
    }
    if ($pixelDataOffset + $rowBytes * $height -gt $Crsr.Length -or $colorTableOffset + 8 -gt $Crsr.Length) {
        throw "crsr resource is truncated"
    }

    $colorTableFlags = Get-U16 $Crsr ($colorTableOffset + 4)
    $colorCount = (Get-I16 $Crsr ($colorTableOffset + 6)) + 1
    if ($colorCount -lt 1 -or $colorTableOffset + 8 + $colorCount * 8 -gt $Crsr.Length) {
        throw "crsr color table is invalid"
    }
    $colors = @{}
    $orderedColors = @()
    for ($index = 0; $index -lt $colorCount; $index++) {
        $offset = $colorTableOffset + 8 + $index * 8
        $colorNumber = Get-U16 $Crsr $offset
        $color = @(
            [Math]::Floor((Get-U16 $Crsr ($offset + 2)) / 257.0),
            [Math]::Floor((Get-U16 $Crsr ($offset + 4)) / 257.0),
            [Math]::Floor((Get-U16 $Crsr ($offset + 6)) / 257.0)
        )
        $colors[$colorNumber] = $color
        $orderedColors += ,$color
    }

    Add-Type -AssemblyName System.Drawing
    $bitmap = [Drawing.Bitmap]::new($width, $height, [Drawing.Imaging.PixelFormat]::Format32bppArgb)
    try {
        for ($y = 0; $y -lt $height; $y++) {
            for ($x = 0; $x -lt $width; $x++) {
                $pixelByte = $Crsr[$pixelDataOffset + $y * $rowBytes + [Math]::Floor($x * $pixelSize / 8)]
                $shift = 8 - $pixelSize - (($x * $pixelSize) % 8)
                $colorIndex = ($pixelByte -shr $shift) -band ((1 -shl $pixelSize) - 1)
                $rgb = if (($colorTableFlags -band 0x8000) -ne 0) { $orderedColors[$colorIndex] } else { $colors[$colorIndex] }
                if ($null -eq $rgb) {
                    $rgb = @(0, 0, 0)
                }
                $maskByte = $Crsr[52 + $y * 2 + [Math]::Floor($x / 8)]
                $alpha = if ((($maskByte -shr (7 - ($x % 8))) -band 1) -eq 1) { 255 } else { 0 }
                $bitmap.SetPixel($x, $y, [Drawing.Color]::FromArgb($alpha, $rgb[0], $rgb[1], $rgb[2]))
            }
        }
        $parent = Split-Path -Parent $Destination
        if ($parent) {
            New-Item -ItemType Directory -Path $parent -Force | Out-Null
        }
        $bitmap.Save($Destination, [Drawing.Imaging.ImageFormat]::Png)
    }
    finally {
        $bitmap.Dispose()
    }
}

$resolvedResourceFork = (Resolve-Path -LiteralPath $ResourceForkPath).Path
$forkBytes = [IO.File]::ReadAllBytes($resolvedResourceFork)
$crsrBytes = Get-ResourceBytes $forkBytes "crsr" $ResourceId
Export-CrsrPng $crsrBytes $OutputPath $ExpectedHotspotX $ExpectedHotspotY
