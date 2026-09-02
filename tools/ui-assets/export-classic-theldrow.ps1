param(
    [Parameter(Mandatory = $true)]
    [string]$ResourceForkPath,

    [Parameter(Mandatory = $true)]
    [string]$DestinationRoot
)

$ErrorActionPreference = "Stop"
Add-Type -AssemblyName System.Drawing

function Get-U16BE([byte[]]$Bytes, [int]$Offset) {
    if ($Offset -lt 0 -or $Offset + 2 -gt $Bytes.Length) { throw "16-bit read exceeds input at $Offset" }
    return ([int]$Bytes[$Offset] -shl 8) -bor [int]$Bytes[$Offset + 1]
}

function Get-I16BE([byte[]]$Bytes, [int]$Offset) {
    $value = Get-U16BE $Bytes $Offset
    if ($value -ge 0x8000) { return $value - 0x10000 }
    return $value
}

function Get-U32BE([byte[]]$Bytes, [int]$Offset) {
    if ($Offset -lt 0 -or $Offset + 4 -gt $Bytes.Length) { throw "32-bit read exceeds input at $Offset" }
    return ([uint32]$Bytes[$Offset] -shl 24) -bor
        ([uint32]$Bytes[$Offset + 1] -shl 16) -bor
        ([uint32]$Bytes[$Offset + 2] -shl 8) -bor
        [uint32]$Bytes[$Offset + 3]
}

function Get-ClassicResource([byte[]]$Bytes, [string]$ResourceType, [int]$ResourceId) {
    if ($Bytes.Length -lt 32) { throw "Classic resource fork is truncated" }
    $dataOffset = [int](Get-U32BE $Bytes 0)
    $mapOffset = [int](Get-U32BE $Bytes 4)
    if ($mapOffset + 28 -gt $Bytes.Length) { throw "Classic resource map is truncated" }
    $typeListOffset = $mapOffset + (Get-U16BE $Bytes ($mapOffset + 24))
    $rawTypeCount = Get-U16BE $Bytes $typeListOffset
    if ($rawTypeCount -eq 0xFFFF) { throw "Classic resource fork contains no resources" }

    for ($typeIndex = 0; $typeIndex -le $rawTypeCount; $typeIndex++) {
        $typeOffset = $typeListOffset + 2 + ($typeIndex * 8)
        $typeName = [Text.Encoding]::ASCII.GetString($Bytes, $typeOffset, 4)
        if ($typeName -ne $ResourceType) { continue }
        $rawResourceCount = Get-U16BE $Bytes ($typeOffset + 4)
        $referenceListOffset = $typeListOffset + (Get-U16BE $Bytes ($typeOffset + 6))
        for ($referenceIndex = 0; $referenceIndex -le $rawResourceCount; $referenceIndex++) {
            $referenceOffset = $referenceListOffset + ($referenceIndex * 12)
            if ((Get-I16BE $Bytes $referenceOffset) -ne $ResourceId) { continue }
            $relativeDataOffset = ([int]$Bytes[$referenceOffset + 5] -shl 16) -bor
                ([int]$Bytes[$referenceOffset + 6] -shl 8) -bor
                [int]$Bytes[$referenceOffset + 7]
            $lengthOffset = $dataOffset + $relativeDataOffset
            $length = [int](Get-U32BE $Bytes $lengthOffset)
            if ($lengthOffset + 4 + $length -gt $Bytes.Length) { throw "Classic resource payload is truncated" }
            $result = [byte[]]::new($length)
            [Array]::Copy($Bytes, $lengthOffset + 4, $result, 0, $length)
            return $result
        }
    }
    throw "Classic resource $ResourceType $ResourceId was not found"
}

function Get-UnicodeCodepoint([Text.Encoding]$MacRoman, [int]$ClassicCode) {
    $text = $MacRoman.GetString([byte[]]@([byte]$ClassicCode))
    if ([string]::IsNullOrEmpty($text)) { return $null }
    return [char]::ConvertToUtf32($text, 0)
}

$resourceFork = [IO.File]::ReadAllBytes((Resolve-Path -LiteralPath $ResourceForkPath))
$fontData = Get-ClassicResource $resourceFork "FONT" 1601
if ($fontData.Length -ne 2942) { throw "Theldrow FONT 1601 has unexpected length $($fontData.Length)" }

$typeFlags = Get-U16BE $fontData 0
$firstCharacter = Get-U16BE $fontData 2
$lastCharacter = Get-U16BE $fontData 4
$maximumWidth = Get-U16BE $fontData 6
$maximumKerning = Get-I16BE $fontData 8
$rectangleWidth = Get-U16BE $fontData 12
$rectangleHeight = Get-U16BE $fontData 14
$maximumAscent = Get-I16BE $fontData 18
$maximumDescent = Get-I16BE $fontData 20
$leading = Get-I16BE $fontData 22
$bitmapRowWords = Get-U16BE $fontData 24
if (($typeFlags -band 0x000C) -ne 0) { throw "Only the original monochrome Theldrow strike is supported" }
if ($firstCharacter -ne 0 -or $lastCharacter -ne 216 -or $rectangleHeight -ne 15 -or $bitmapRowWords -ne 68) {
    throw "Theldrow FONT 1601 metrics do not match the pinned Castle resource"
}

$bitmapOffset = 26
$bitmapRowBytes = $bitmapRowWords * 2
$bitmapLength = $bitmapRowBytes * $rectangleHeight
$glyphCountWithMissing = ($lastCharacter + 2) - $firstCharacter
$locationTableOffset = $bitmapOffset + $bitmapLength
$widthTableOffset = $locationTableOffset + (($glyphCountWithMissing + 1) * 2)
if ($widthTableOffset + ($glyphCountWithMissing * 2) -gt $fontData.Length) { throw "Theldrow metric tables are truncated" }

$locations = [int[]]::new($glyphCountWithMissing + 1)
for ($index = 0; $index -lt $locations.Length; $index++) {
    $locations[$index] = Get-U16BE $fontData ($locationTableOffset + ($index * 2))
}

$destination = [IO.Path]::GetFullPath($DestinationRoot)
[IO.Directory]::CreateDirectory($destination) | Out-Null
$atlasPath = Join-Path $destination "Theldrow-Classic.png"
$descriptorPath = Join-Path $destination "Theldrow-Classic.fnt"
$atlasWidth = $bitmapRowWords * 16
$atlas = [Drawing.Bitmap]::new($atlasWidth, $rectangleHeight, [Drawing.Imaging.PixelFormat]::Format32bppArgb)
try {
    $transparent = [Drawing.Color]::FromArgb(0, 255, 255, 255)
    $opaque = [Drawing.Color]::FromArgb(255, 255, 255, 255)
    for ($y = 0; $y -lt $rectangleHeight; $y++) {
        for ($x = 0; $x -lt $atlasWidth; $x++) {
            $byteOffset = $bitmapOffset + ($y * $bitmapRowBytes) + [int][Math]::Floor($x / 8)
            $mask = 1 -shl (7 - ($x % 8))
            $atlas.SetPixel($x, $y, $(if (($fontData[$byteOffset] -band $mask) -ne 0) { $opaque } else { $transparent }))
        }
    }
    $atlas.Save($atlasPath, [Drawing.Imaging.ImageFormat]::Png)
}
finally {
    $atlas.Dispose()
}

$macRoman = [Text.Encoding]::GetEncoding(10000)
$characters = [Collections.Generic.List[string]]::new()
$seenCodepoints = [Collections.Generic.HashSet[int]]::new()
for ($index = 0; $index -lt ($glyphCountWithMissing - 1); $index++) {
    $classicCode = $firstCharacter + $index
    $unicodeCodepoint = Get-UnicodeCodepoint $macRoman $classicCode
    if ($null -eq $unicodeCodepoint -or $unicodeCodepoint -lt 32 -or -not $seenCodepoints.Add($unicodeCodepoint)) { continue }
    $glyphStart = $locations[$index]
    $glyphWidth = $locations[$index + 1] - $glyphStart
    $drawingOffset = [int]$fontData[$widthTableOffset + ($index * 2)]
    if ($drawingOffset -ge 128) { $drawingOffset -= 256 }
    $advance = [int]$fontData[$widthTableOffset + ($index * 2) + 1]
    if ($drawingOffset -eq -1 -and $advance -eq 255) { continue }
    $characters.Add("char id=$unicodeCodepoint x=$glyphStart y=0 width=$glyphWidth height=$rectangleHeight xoffset=$drawingOffset yoffset=0 xadvance=$advance page=0 chnl=15")
}

$lines = [Collections.Generic.List[string]]::new()
$lines.Add("info face=`"Theldrow Classic`" size=$rectangleHeight bold=0 italic=0 charset=`"MacRoman`" unicode=1 stretchH=100 smooth=0 aa=0 padding=0,0,0,0 spacing=0,0 outline=0")
$lines.Add("common lineHeight=$($rectangleHeight + $leading) base=$maximumAscent scaleW=$atlasWidth scaleH=$rectangleHeight pages=1 packed=0 alphaChnl=0 redChnl=4 greenChnl=4 blueChnl=4")
$lines.Add("page id=0 file=`"Theldrow-Classic.png`"")
$lines.Add("chars count=$($characters.Count)")
$lines.AddRange($characters)
[IO.File]::WriteAllText($descriptorPath, (($lines -join "`n") + "`n"), [Text.UTF8Encoding]::new($false))

$sha = [Security.Cryptography.SHA256]::Create()
try { $payloadHash = ([BitConverter]::ToString($sha.ComputeHash($fontData))).Replace("-", "").ToLowerInvariant() } finally { $sha.Dispose() }
Write-Host "Exported exact Theldrow FONT 1601: $($characters.Count) Unicode glyphs; ${atlasWidth}x${rectangleHeight}; ascent $maximumAscent; descent $maximumDescent; leading $leading; max width $maximumWidth; max kerning $maximumKerning; payload SHA-256 $payloadHash."
