param(
    [Parameter(Mandatory = $true)]
    [string]$VectorFontPath,

    [Parameter(Mandatory = $true)]
    [string]$ClassicBmFontPath,

    [Parameter(Mandatory = $true)]
    [string]$OutputPath
)

$ErrorActionPreference = "Stop"

function Get-U16BE([byte[]]$Bytes, [int]$Offset) {
    if ($Offset -lt 0 -or $Offset + 2 -gt $Bytes.Length) { throw "16-bit read exceeds input at $Offset" }
    return ([int]$Bytes[$Offset] -shl 8) -bor [int]$Bytes[$Offset + 1]
}

function Get-U32BE([byte[]]$Bytes, [int]$Offset) {
    if ($Offset -lt 0 -or $Offset + 4 -gt $Bytes.Length) { throw "32-bit read exceeds input at $Offset" }
    return ([uint32]$Bytes[$Offset] -shl 24) -bor
        ([uint32]$Bytes[$Offset + 1] -shl 16) -bor
        ([uint32]$Bytes[$Offset + 2] -shl 8) -bor
        [uint32]$Bytes[$Offset + 3]
}

function Set-U16BE([byte[]]$Bytes, [int]$Offset, [uint16]$Value) {
    $Bytes[$Offset] = [byte](($Value -shr 8) -band 0xFF)
    $Bytes[$Offset + 1] = [byte]($Value -band 0xFF)
}

function Set-U32BE([byte[]]$Bytes, [int]$Offset, [uint32]$Value) {
    $Bytes[$Offset] = [byte](($Value -shr 24) -band 0xFF)
    $Bytes[$Offset + 1] = [byte](($Value -shr 16) -band 0xFF)
    $Bytes[$Offset + 2] = [byte](($Value -shr 8) -band 0xFF)
    $Bytes[$Offset + 3] = [byte]($Value -band 0xFF)
}

function Get-TableDirectory([byte[]]$Bytes) {
    $count = Get-U16BE $Bytes 4
    $result = @{}
    for ($index = 0; $index -lt $count; $index++) {
        $recordOffset = 12 + ($index * 16)
        $tag = [Text.Encoding]::ASCII.GetString($Bytes, $recordOffset, 4)
        $result[$tag] = [ordered]@{
            RecordOffset = $recordOffset
            Offset = [int](Get-U32BE $Bytes ($recordOffset + 8))
            Length = [int](Get-U32BE $Bytes ($recordOffset + 12))
        }
    }
    return $result
}

function Get-CmapSubtable([byte[]]$Bytes, [hashtable]$Tables) {
    $cmap = $Tables["cmap"]
    if ($null -eq $cmap) { throw "Vector font has no cmap table" }
    $count = Get-U16BE $Bytes ($cmap.Offset + 2)
    $candidates = @()
    for ($index = 0; $index -lt $count; $index++) {
        $recordOffset = $cmap.Offset + 4 + ($index * 8)
        $platform = Get-U16BE $Bytes $recordOffset
        $encoding = Get-U16BE $Bytes ($recordOffset + 2)
        $offset = $cmap.Offset + [int](Get-U32BE $Bytes ($recordOffset + 4))
        $format = Get-U16BE $Bytes $offset
        $priority = if ($format -eq 12 -and $platform -eq 3 -and $encoding -eq 10) { 0 } elseif ($format -eq 12 -and $platform -eq 0) { 1 } elseif ($format -eq 4 -and $platform -eq 3) { 2 } elseif ($format -eq 4 -and $platform -eq 0) { 3 } else { 99 }
        if ($priority -lt 99) { $candidates += [pscustomobject]@{ Priority = $priority; Format = $format; Offset = $offset } }
    }
    $selected = $candidates | Sort-Object Priority | Select-Object -First 1
    if ($null -eq $selected) { throw "Vector font has no supported Unicode cmap format" }
    return $selected
}

function Get-GlyphId([byte[]]$Bytes, [object]$Cmap, [int]$Codepoint) {
    if ($Cmap.Format -eq 12) {
        $groupCount = [int](Get-U32BE $Bytes ($Cmap.Offset + 12))
        for ($index = 0; $index -lt $groupCount; $index++) {
            $groupOffset = $Cmap.Offset + 16 + ($index * 12)
            $first = [int](Get-U32BE $Bytes $groupOffset)
            $last = [int](Get-U32BE $Bytes ($groupOffset + 4))
            if ($Codepoint -lt $first) { return 0 }
            if ($Codepoint -le $last) { return [int](Get-U32BE $Bytes ($groupOffset + 8)) + ($Codepoint - $first) }
        }
        return 0
    }

    $segmentCount = (Get-U16BE $Bytes ($Cmap.Offset + 6)) / 2
    $endCodesOffset = $Cmap.Offset + 14
    $startCodesOffset = $endCodesOffset + ($segmentCount * 2) + 2
    $deltasOffset = $startCodesOffset + ($segmentCount * 2)
    $rangeOffsetsOffset = $deltasOffset + ($segmentCount * 2)
    for ($index = 0; $index -lt $segmentCount; $index++) {
        $last = Get-U16BE $Bytes ($endCodesOffset + ($index * 2))
        if ($Codepoint -gt $last) { continue }
        $first = Get-U16BE $Bytes ($startCodesOffset + ($index * 2))
        if ($Codepoint -lt $first) { return 0 }
        $delta = Get-U16BE $Bytes ($deltasOffset + ($index * 2))
        $rangeOffsetAddress = $rangeOffsetsOffset + ($index * 2)
        $rangeOffset = Get-U16BE $Bytes $rangeOffsetAddress
        if ($rangeOffset -eq 0) { return ($Codepoint + $delta) -band 0xFFFF }
        $glyphAddress = $rangeOffsetAddress + $rangeOffset + (($Codepoint - $first) * 2)
        $glyph = Get-U16BE $Bytes $glyphAddress
        if ($glyph -eq 0) { return 0 }
        return ($glyph + $delta) -band 0xFFFF
    }
    return 0
}

function Get-TableChecksum([byte[]]$Bytes, [int]$Offset, [int]$Length) {
    [uint64]$sum = 0
    $paddedLength = ($Length + 3) -band -4
    for ($index = 0; $index -lt $paddedLength; $index += 4) {
        [uint32]$word = 0
        for ($part = 0; $part -lt 4; $part++) {
            $sourceIndex = $Offset + $index + $part
            $value = if ($index + $part -lt $Length) { [uint32]$Bytes[$sourceIndex] } else { [uint32]0 }
            $word = $word -bor ($value -shl (24 - ($part * 8)))
        }
        $sum = ($sum + $word) -band 0xFFFFFFFFL
    }
    return [uint32]$sum
}

$bytes = [IO.File]::ReadAllBytes((Resolve-Path -LiteralPath $VectorFontPath))
$tables = Get-TableDirectory $bytes
foreach ($requiredTable in @("cmap", "head", "hhea", "hmtx", "maxp")) {
    if (-not $tables.ContainsKey($requiredTable)) { throw "Vector font is missing $requiredTable" }
}
$unitsPerEm = Get-U16BE $bytes ($tables["head"].Offset + 18)
$glyphCount = Get-U16BE $bytes ($tables["maxp"].Offset + 4)
$metricCount = Get-U16BE $bytes ($tables["hhea"].Offset + 34)
if ($unitsPerEm -le 0 -or $metricCount -ne $glyphCount) { throw "Vector font must contain one horizontal metric per glyph" }

$classicLines = Get-Content -LiteralPath $ClassicBmFontPath
$info = $classicLines | Where-Object { $_ -like "info *" } | Select-Object -First 1
if ($info -notmatch '(?:^| )size=(\d+)') { throw "Classic BMFont has no source size" }
$classicSize = [int]$Matches[1]
$classicAdvances = @{}
foreach ($line in $classicLines) {
    if ($line -match '^char id=(\d+).* xadvance=(-?\d+) ') {
        $classicAdvances[[int]$Matches[1]] = [int]$Matches[2]
    }
}
if ($classicAdvances.Count -lt 100) { throw "Classic BMFont metric set is incomplete" }

$cmap = Get-CmapSubtable $bytes $tables
$updatedGlyphs = [Collections.Generic.HashSet[int]]::new()
$sampleRecords = [Collections.Generic.List[string]]::new()
foreach ($entry in $classicAdvances.GetEnumerator()) {
    $glyphId = Get-GlyphId $bytes $cmap ([int]$entry.Key)
    if ($glyphId -le 0 -or $glyphId -ge $glyphCount -or -not $updatedGlyphs.Add($glyphId)) { continue }
    $metricOffset = $tables["hmtx"].Offset + ($glyphId * 4)
    $oldAdvance = Get-U16BE $bytes $metricOffset
    $newAdvance = [Math]::Clamp([int][Math]::Round(([double]$entry.Value * $unitsPerEm) / $classicSize), 1, 65535)
    Set-U16BE $bytes $metricOffset ([uint16]$newAdvance)
    if ([int]$entry.Key -in @(32, 65, 73, 77, 87, 97, 105, 109, 119)) {
        $sampleRecords.Add("U+$(([int]$entry.Key).ToString('X4')):$oldAdvance->$newAdvance")
    }
}
if ($updatedGlyphs.Count -lt 100) { throw "Too few Samuel glyphs map to original Theldrow metrics: $($updatedGlyphs.Count)" }

$headOffset = $tables["head"].Offset
Set-U32BE $bytes ($headOffset + 8) 0
$hmtxChecksum = Get-TableChecksum $bytes $tables["hmtx"].Offset $tables["hmtx"].Length
Set-U32BE $bytes ($tables["hmtx"].RecordOffset + 4) $hmtxChecksum
$wholeChecksum = Get-TableChecksum $bytes 0 $bytes.Length
$adjustment = [uint32](([uint64]2981146554 - [uint64]$wholeChecksum) -band 0xFFFFFFFFL)
Set-U32BE $bytes ($headOffset + 8) $adjustment

$destination = [IO.Path]::GetFullPath($OutputPath)
[IO.Directory]::CreateDirectory((Split-Path -Parent $destination)) | Out-Null
[IO.File]::WriteAllBytes($destination, $bytes)
Write-Host "Remetricked Samuel Theldrow with $($updatedGlyphs.Count) original FONT 1601 advances at $unitsPerEm units/em ($($sampleRecords -join ', '))."
