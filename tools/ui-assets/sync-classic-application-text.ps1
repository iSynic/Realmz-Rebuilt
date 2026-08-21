param(
    [Parameter(Mandatory = $true)]
    [string]$CastleRepository
)

$ErrorActionPreference = "Stop"
$sourceCommit = "491816ad60037394f92c428e99c004494d3c28b3"
$sourcePath = "base/Realmz/Data Files/The Family Jewels.rsrc"
$sourceSha256 = "8dbae6c6a418c82250dca93937c5958dacea9874d654c62da4e4dafa184dc85c"
$destination = Join-Path (Split-Path -Parent (Split-Path -Parent $PSScriptRoot)) "src/infrastructure/packages/classic-application-spell-descriptions.json"

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

function Get-MacRomanEncoding {
    try {
        return [Text.Encoding]::GetEncoding(10000)
    }
    catch {
        [void][Reflection.Assembly]::Load("System.Text.Encoding.CodePages")
        $providerType = [Type]::GetType("System.Text.CodePagesEncodingProvider, System.Text.Encoding.CodePages", $true)
        $provider = $providerType.GetProperty("Instance", [Reflection.BindingFlags]"Public,Static").GetValue($null)
        $register = [Text.Encoding].GetMethod("RegisterProvider", [Reflection.BindingFlags]"Public,Static")
        [void]$register.Invoke($null, @($provider))
        return [Text.Encoding]::GetEncoding(10000)
    }
}

function ConvertTo-JsonString([string]$Value) {
    $builder = [Text.StringBuilder]::new($Value.Length + 2)
    [void]$builder.Append('"')
    foreach ($character in $Value.ToCharArray()) {
        switch ([int]$character) {
            8 { [void]$builder.Append('\b'); continue }
            9 { [void]$builder.Append('\t'); continue }
            10 { [void]$builder.Append('\n'); continue }
            12 { [void]$builder.Append('\f'); continue }
            13 { [void]$builder.Append('\r'); continue }
            34 { [void]$builder.Append('\"'); continue }
            92 { [void]$builder.Append('\\'); continue }
        }
        if ([int]$character -lt 32) {
            [void]$builder.AppendFormat('\u{0:x4}', [int]$character)
        }
        else {
            [void]$builder.Append($character)
        }
    }
    [void]$builder.Append('"')
    return $builder.ToString()
}

function Get-StringLists([byte[]]$ForkBytes) {
    $macRoman = Get-MacRomanEncoding
    $dataOffset = [int](Get-U32 $ForkBytes 0)
    $mapOffset = [int](Get-U32 $ForkBytes 4)
    $typeListOffset = $mapOffset + (Get-U16 $ForkBytes ($mapOffset + 24))
    $rawTypeCount = Get-U16 $ForkBytes $typeListOffset
    $result = @{}
    for ($typeIndex = 0; $typeIndex -le $rawTypeCount; $typeIndex++) {
        $typeOffset = $typeListOffset + 2 + $typeIndex * 8
        if ([Text.Encoding]::ASCII.GetString($ForkBytes, $typeOffset, 4) -ne "STR#") { continue }
        $rawResourceCount = Get-U16 $ForkBytes ($typeOffset + 4)
        $referenceListOffset = $typeListOffset + (Get-U16 $ForkBytes ($typeOffset + 6))
        for ($referenceIndex = 0; $referenceIndex -le $rawResourceCount; $referenceIndex++) {
            $referenceOffset = $referenceListOffset + $referenceIndex * 12
            $resourceId = Get-I16 $ForkBytes $referenceOffset
            if ($resourceId -gt -1000 -or $resourceId -lt -3006) { continue }
            $absoluteId = [Math]::Abs($resourceId)
            $class = [Math]::Floor($absoluteId / 1000)
            $levelIndex = $absoluteId % 1000
            if ($class -lt 1 -or $class -gt 3 -or $levelIndex -lt 0 -or $levelIndex -gt 6) { continue }
            $relativeOffset = ([int]$ForkBytes[$referenceOffset + 5] -shl 16) -bor ([int]$ForkBytes[$referenceOffset + 6] -shl 8) -bor [int]$ForkBytes[$referenceOffset + 7]
            $lengthOffset = $dataOffset + $relativeOffset
            $length = [int](Get-U32 $ForkBytes $lengthOffset)
            $cursor = $lengthOffset + 4
            $limit = $cursor + $length
            $count = Get-U16 $ForkBytes $cursor
            $cursor += 2
            if ($count -lt 1 -or $count -gt 15) { throw "Classic spell description STR# $resourceId contains an invalid $count entries." }
            for ($slot = 0; $slot -lt $count; $slot++) {
                if ($cursor -ge $limit) { throw "Classic spell description STR# $resourceId is truncated." }
                $textLength = [int]$ForkBytes[$cursor]
                $cursor += 1
                if ($cursor + $textLength -gt $limit) { throw "Classic spell description STR# $resourceId is truncated." }
                $classicId = $class * 1000 + ($levelIndex + 1) * 100 + $slot + 1
                $result[[string]$classicId] = $macRoman.GetString($ForkBytes, $cursor, $textLength)
                $cursor += $textLength
            }
        }
    }
    return $result
}

$castleRoot = (Resolve-Path -LiteralPath $CastleRepository).Path
$resolvedCommit = (& git -C $castleRoot rev-parse "HEAD^{commit}").Trim()
if ($LASTEXITCODE -ne 0 -or $resolvedCommit -ne $sourceCommit) { throw "Castle reference must be pinned at $sourceCommit." }
$resolvedSource = Join-Path $castleRoot $sourcePath
$actualSha256 = (Get-FileHash -Algorithm SHA256 -LiteralPath $resolvedSource).Hash.ToLowerInvariant()
if ($actualSha256 -ne $sourceSha256) { throw "The Family Jewels resource hash does not match the pinned application library." }
$descriptions = Get-StringLists ([IO.File]::ReadAllBytes($resolvedSource))
if ($descriptions.Count -ne 252) { throw "Expected 252 stock player-spell descriptions; found $($descriptions.Count)." }
$json = [Text.StringBuilder]::new()
[void]$json.Append('{"schemaVersion":1,"sourceCommit":')
[void]$json.Append((ConvertTo-JsonString $sourceCommit))
[void]$json.Append(',"sourcePath":')
[void]$json.Append((ConvertTo-JsonString $sourcePath))
[void]$json.Append(',"sourceFileSha256":')
[void]$json.Append((ConvertTo-JsonString $sourceSha256))
[void]$json.Append(',"descriptions":{')
$first = $true
foreach ($key in ($descriptions.Keys | Sort-Object {[int]$_})) {
    if (-not $first) { [void]$json.Append(',') }
    $first = $false
    [void]$json.Append((ConvertTo-JsonString $key))
    [void]$json.Append(':')
    [void]$json.Append((ConvertTo-JsonString $descriptions[$key]))
}
[void]$json.Append("}}`n")
[IO.File]::WriteAllText($destination, $json.ToString(), [Text.UTF8Encoding]::new($false))
Write-Output "Wrote $($descriptions.Count) Classic application spell descriptions to $destination"
