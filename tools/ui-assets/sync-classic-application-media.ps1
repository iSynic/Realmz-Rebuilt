param(
    [Parameter(Mandatory = $true)]
    [string]$CastleRepository,
    [string]$PictDecoderPath = "",
    [string]$ResourceDasmPath = "",
    [switch]$SoundOnly,
    [switch]$CicnOnly,
    [switch]$PictOnly
)

$ErrorActionPreference = "Stop"
Add-Type -AssemblyName System.Drawing

if (@($SoundOnly, $CicnOnly, $PictOnly).Where({ [bool]$_ }).Count -gt 1) {
    throw "SoundOnly, CicnOnly, and PictOnly are mutually exclusive"
}

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

function Get-ResourceEntries([byte[]]$ForkBytes, [string]$ResourceType) {
    if ($ForkBytes.Length -lt 32) {
        throw "Resource fork is too short"
    }
    $dataOffset = [int](Get-U32 $ForkBytes 0)
    $mapOffset = [int](Get-U32 $ForkBytes 4)
    $typeListOffset = $mapOffset + (Get-U16 $ForkBytes ($mapOffset + 24))
    $rawTypeCount = Get-U16 $ForkBytes $typeListOffset
    if ($rawTypeCount -eq 0xffff) {
        return @()
    }
    $entries = @()
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
            $resourceId = Get-I16 $ForkBytes $referenceOffset
            $relativeOffset = ([int]$ForkBytes[$referenceOffset + 5] -shl 16) -bor ([int]$ForkBytes[$referenceOffset + 6] -shl 8) -bor [int]$ForkBytes[$referenceOffset + 7]
            $lengthOffset = $dataOffset + $relativeOffset
            $length = [int](Get-U32 $ForkBytes $lengthOffset)
            if ($lengthOffset + 4 + $length -gt $ForkBytes.Length) {
                throw "Resource $ResourceType $resourceId is truncated"
            }
            $resource = [byte[]]::new($length)
            [Array]::Copy($ForkBytes, $lengthOffset + 4, $resource, 0, $length)
            $entries += [pscustomobject]@{ Id = $resourceId; Bytes = $resource }
        }
    }
    return $entries
}

if (-not ("CastleSoundRenderer" -as [type])) {
    Add-Type -TypeDefinition @'
using System;
using System.Text;

public static class CastleSoundRenderer {
    public const int OutputSampleRate = 48000;

    public static byte[] Render(byte[] sourceSamples, uint sourceRate) {
        if (sourceSamples == null || sourceSamples.Length == 0 || sourceRate == 0) {
            throw new ArgumentException("Classic sampled sound requires samples and a positive rate");
        }

        double expansionFactor = (double)OutputSampleRate / sourceRate;
        int frameCount = checked((int)(
            Math.Ceiling((sourceSamples.LongLength + 1) * expansionFactor) -
            Math.Ceiling(2 * expansionFactor)));
        byte[] output = new byte[checked(44 + frameCount * 2)];
        WriteAscii(output, 0, "RIFF");
        WriteU32(output, 4, (uint)(output.Length - 8));
        WriteAscii(output, 8, "WAVEfmt ");
        WriteU32(output, 16, 16);
        WriteU16(output, 20, 1);
        WriteU16(output, 22, 1);
        WriteU32(output, 24, OutputSampleRate);
        WriteU32(output, 28, OutputSampleRate * 2);
        WriteU16(output, 32, 2);
        WriteU16(output, 34, 16);
        WriteAscii(output, 36, "data");
        WriteU32(output, 40, (uint)(frameCount * 2));

        int outputOffset = 44;
        float previous = (sourceSamples[0] - 0x80) / (float)0x80;
        for (int sourceIndex = 1; sourceIndex < sourceSamples.Length; sourceIndex++) {
            float current = (sourceSamples[sourceIndex] - 0x80) / (float)0x80;
            long inputSampleIndex = sourceIndex + 1L;
            int framesToWrite = checked((int)(
                Math.Ceiling((inputSampleIndex + 1) * expansionFactor) -
                Math.Ceiling(inputSampleIndex * expansionFactor)));
            for (int frame = 0; frame < framesToWrite; frame++) {
                float progress = (float)frame / framesToWrite;
                float interpolated = previous * (1.0f - progress) + current * progress;
                long scaled = (long)(interpolated * 0x7FFF);
                short sample = (short)Math.Max(short.MinValue, Math.Min(short.MaxValue, scaled));
                WriteU16(output, outputOffset, unchecked((ushort)sample));
                outputOffset += 2;
            }
            previous = current;
        }
        if (outputOffset != output.Length) {
            throw new InvalidOperationException("Castle sound rendering length drifted");
        }
        return output;
    }

    private static void WriteAscii(byte[] output, int offset, string value) {
        Encoding.ASCII.GetBytes(value, 0, value.Length, output, offset);
    }

    private static void WriteU16(byte[] output, int offset, ushort value) {
        output[offset] = (byte)value;
        output[offset + 1] = (byte)(value >> 8);
    }

    private static void WriteU32(byte[] output, int offset, uint value) {
        output[offset] = (byte)value;
        output[offset + 1] = (byte)(value >> 8);
        output[offset + 2] = (byte)(value >> 16);
        output[offset + 3] = (byte)(value >> 24);
    }
}
'@
}

function Convert-SndToWav([byte[]]$Snd, [int]$ResourceId) {
    if ($Snd.Length -lt 2) {
        throw "snd $ResourceId is too short"
    }
    $format = Get-U16 $Snd 0
    $headerOffset = -1
    if ($format -eq 1) {
        if ($Snd.Length -lt 22) {
            throw "format-1 snd $ResourceId is truncated"
        }
        $commandCount = Get-U16 $Snd 10
        $cursor = 12
        for ($index = 0; $index -lt $commandCount; $index++) {
            if ($cursor + 8 -gt $Snd.Length) {
                break
            }
            $command = Get-U16 $Snd $cursor
            if (($command -band 0x7fff) -eq 0x51 -and ($command -band 0x8000) -ne 0) {
                $headerOffset = [int](Get-U32 $Snd ($cursor + 4))
                break
            }
            $cursor += 8
        }
    }
    elseif ($format -eq 2) {
        if ($Snd.Length -lt 36) {
            throw "format-2 snd $ResourceId is truncated"
        }
        $commandCount = Get-U16 $Snd 4
        $command = Get-U16 $Snd 6
        $commandKind = $command -band 0x7fff
        $commandParameter = [int](Get-U32 $Snd 10)
        if ($commandCount -gt 0 -and $commandKind -eq 0x50 -and ($command -band 0x8000) -ne 0 -and $commandParameter -ge 14) {
            $headerOffset = $commandParameter
        }
        elseif ($commandCount -gt 0 -and $commandKind -eq 0x51) {
            $headerOffset = 14
        }
    }
    else {
        throw "snd $ResourceId uses unsupported format $format"
    }
    if ($headerOffset -lt 0 -or $headerOffset + 22 -gt $Snd.Length) {
        throw "snd $ResourceId has no supported sampled-sound header"
    }
    $sampleLength = [int](Get-U32 $Snd ($headerOffset + 4))
    $sourceRate = [uint32]((Get-U32 $Snd ($headerOffset + 8)) -shr 16)
    if ($sourceRate -lt 1) {
        $sourceRate = 1
    }
    $sampleStart = $headerOffset + 22
    if ($sampleStart + $sampleLength -gt $Snd.Length) {
        throw "snd $ResourceId sample data is truncated"
    }
    $sourceSamples = [byte[]]::new($sampleLength)
    [Array]::Copy($Snd, $sampleStart, $sourceSamples, 0, $sampleLength)
    $playbackRate = [CastleSoundRenderer]::OutputSampleRate
    return [pscustomobject]@{
        Bytes = [CastleSoundRenderer]::Render($sourceSamples, $sourceRate)
        SourceRate = $sourceRate
        PlaybackRate = $playbackRate
        Samples = $sourceSamples.Length
    }
}

$toolRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
$repoRoot = Split-Path -Parent (Split-Path -Parent $toolRoot)
$catalogPath = Join-Path $toolRoot "application-media-catalog.json"
$cicnExporterPath = Join-Path $toolRoot "export-classic-cicn.ps1"
$pictExporterPath = Join-Path $toolRoot "export-classic-pict.ps1"
$catalog = Get-Content -Raw -LiteralPath $catalogPath | ConvertFrom-Json
$castleRoot = (Resolve-Path -LiteralPath $CastleRepository).Path
$resolvedCommit = (& git -C $castleRoot rev-parse "$($catalog.source_commit)^{commit}").Trim()
if ($LASTEXITCODE -ne 0 -or $resolvedCommit -ne $catalog.source_commit) {
    throw "The requested Castle source commit is unavailable: $($catalog.source_commit)"
}

$stagingRoot = Join-Path ([IO.Path]::GetTempPath()) ("realmz-application-media-" + [Guid]::NewGuid().ToString("N"))
$archivePath = Join-Path $stagingRoot "castle-source.zip"
$extractRoot = Join-Path $stagingRoot "source"
$outputRoot = Join-Path $stagingRoot "output"
$sidecarRoot = Join-Path $stagingRoot "sidecars"
$destinationRoot = Join-Path $repoRoot "src/presentation/assets/classic-media"
$manifestPath = Join-Path $repoRoot "src/presentation/assets/classic-application-media.json"
$existingManifest = if ($SoundOnly -or $CicnOnly -or $PictOnly) { Get-Content -Raw -LiteralPath $manifestPath | ConvertFrom-Json } else { $null }
$activeResourceSets = @($catalog.resource_sets | Where-Object {
    if ($SoundOnly) { return $_.resource_type -eq "snd " }
    if ($CicnOnly) { return $_.resource_type -eq "cicn" }
    if ($PictOnly) { return $_.resource_type -eq "PICT" }
    return $true
})
New-Item -ItemType Directory -Path $extractRoot, $outputRoot, $sidecarRoot | Out-Null

try {
    $sourcePaths = @($activeResourceSets | ForEach-Object { $_.source_path } | Sort-Object -Unique)
    & git -C $castleRoot archive --format=zip --output=$archivePath $catalog.source_commit -- @sourcePaths
    if ($LASTEXITCODE -ne 0) {
        throw "Castle git archive failed"
    }
    Expand-Archive -LiteralPath $archivePath -DestinationPath $extractRoot

    $records = @()
    foreach ($set in $activeResourceSets) {
        $sourcePath = Join-Path $extractRoot ($set.source_path -replace "/", [IO.Path]::DirectorySeparatorChar)
        $sourceSha256 = (Get-FileHash -Algorithm SHA256 -LiteralPath $sourcePath).Hash.ToLowerInvariant()
        if ($sourceSha256 -ne $set.source_file_sha256) {
            throw "Catalog source hash mismatch: $($set.source_path)"
        }
        $forkBytes = [IO.File]::ReadAllBytes($sourcePath)
        $availableEntries = @(Get-ResourceEntries $forkBytes $set.resource_type)
        $expectedIds = @($set.resource_ids | ForEach-Object { [int]$_ })
        foreach ($range in @($set.resource_ranges)) {
			if ($null -eq $range) {
				continue
			}
            $expectedIds += @(([int]$range.start)..([int]$range.end))
        }
        $expectedIds = @($expectedIds | Sort-Object -Unique)
        $availableIds = @($availableEntries | ForEach-Object { $_.Id } | Sort-Object -Unique)
        $missingIds = @($expectedIds | Where-Object { $_ -notin $availableIds })
        if ($missingIds.Count -gt 0) {
            throw "Catalog resource IDs are missing from $($set.source_path) $($set.resource_type): $($missingIds -join ',')"
        }
        $entries = @($availableEntries | Where-Object { $_.Id -in $expectedIds })
        foreach ($entry in $entries | Sort-Object Id) {
            if ($set.resource_type -eq "PICT") {
                if ([string]::IsNullOrWhiteSpace($PictDecoderPath)) {
                    throw "PictDecoderPath is required for cataloged Classic PICT assets"
                }
                $isDarknessMask = $set.target_directory -eq "darkness-masks"
                $landlook = $entry.Id - 300
                $darknessLevel = $entry.Id - 350
                $landlookMetadata = if ($isDarknessMask) { $null } else { @{
                        0 = @("Plains", 156)
                        3 = @("Subterranean", 155)
                        4 = @("Castle", 111)
                        5 = @("Desert", 191)
                        9 = @("Swamp", 155)
                        10 = @("Snow", 155)
                    }[$landlook] }
                if (-not $isDarknessMask -and $null -eq $landlookMetadata) {
                    throw "Unsupported stock landlook PICT: $($entry.Id)"
                }
                $relativePath = if ($isDarknessMask) { "$($set.target_directory)/darkness-mask-$darknessLevel.png" } else { "$($set.target_directory)/landlook-$landlook.png" }
                $targetPath = Join-Path $outputRoot ($relativePath -replace "/", [IO.Path]::DirectorySeparatorChar)
                & $pictExporterPath -ResourceForkPath $sourcePath -ResourceId $entry.Id -PictDecoderPath $PictDecoderPath -OutputPath $targetPath
                if ($LASTEXITCODE -ne 0) {
                    throw "Classic PICT export failed for resource $($entry.Id)"
                }
                $pngBytes = [IO.File]::ReadAllBytes($targetPath)
                if ($pngBytes.Length -lt 24) {
                    throw "Decoded Classic PICT PNG is truncated: $($entry.Id)"
                }
                $width = [int](Get-U32 $pngBytes 16)
                $height = [int](Get-U32 $pngBytes 20)
                $expectedWidth = if ($isDarknessMask) { 320 } else { 640 }
                if ($width -ne $expectedWidth -or $height -ne 320) {
                    throw "Decoded Classic PICT $($entry.Id) is ${width}x${height}; expected ${expectedWidth}x320"
                }
                $record = [ordered]@{
                    id = if ($isDarknessMask) { "classic-darkness-mask-$darknessLevel" } else { "landlook-$landlook" }
                    label = if ($isDarknessMask) { "Classic darkness mask $darknessLevel" } else { $landlookMetadata[0] }
                    kind = if ($isDarknessMask) { "picture" } else { "tileset" }
                    mime_type = "image/png"
                    resource_type = $set.resource_type
                    resource_id = $entry.Id
                    path = "res://src/presentation/assets/classic-media/$relativePath"
                    bytes = $pngBytes.Length
                    sha256 = (Get-FileHash -Algorithm SHA256 -LiteralPath $targetPath).Hash.ToLowerInvariant()
                    width = $width
                    height = $height
                    source_repository = $catalog.source_repository
                    source_commit = $catalog.source_commit
                    source_path = $set.source_path
                    source_file_sha256 = $set.source_file_sha256
                    source_resource_sha256 = (Get-FileHash -InputStream ([IO.MemoryStream]::new($entry.Bytes)) -Algorithm SHA256).Hash.ToLowerInvariant()
                    classification = $set.classification
                    classic_evidence = [ordered]@{
                        status = "source-control-flow"
                        path = $set.evidence_path
                        note = $set.evidence_note
                    }
                }
                if (-not $isDarknessMask) {
                    $record["tile_width"] = 32
                    $record["tile_height"] = 32
                    $record["columns"] = 20
                    $record["rows"] = 10
                    $record["landlook"] = $landlook
                    $record["base_tile"] = $landlookMetadata[1]
                }
                $records += $record
                continue
            }
            if ($set.resource_type -eq "ppat") {
                if ([string]::IsNullOrWhiteSpace($ResourceDasmPath) -or -not (Test-Path -LiteralPath $ResourceDasmPath -PathType Leaf)) {
                    throw "ResourceDasmPath is required for cataloged Classic ppat assets"
                }
                $decodeRoot = Join-Path $stagingRoot "ppat-$($entry.Id)"
                $rawPath = Join-Path $decodeRoot "ppat-$($entry.Id).bin"
                New-Item -ItemType Directory -Path $decodeRoot -Force | Out-Null
                [IO.File]::WriteAllBytes($rawPath, $entry.Bytes)
                & $ResourceDasmPath "--decode-single-resource=ppat:$($entry.Id)" $rawPath
                if ($LASTEXITCODE -ne 0) {
                    throw "Classic ppat export failed for resource $($entry.Id)"
                }
                $decodedBitmapPath = "$rawPath`_ppat_$($entry.Id).bmp"
                if (-not (Test-Path -LiteralPath $decodedBitmapPath -PathType Leaf)) {
                    throw "Classic ppat export did not produce its primary bitmap for resource $($entry.Id)"
                }
                $relativePath = "$($set.target_directory)/ppat-$($entry.Id).png"
                $targetPath = Join-Path $outputRoot ($relativePath -replace "/", [IO.Path]::DirectorySeparatorChar)
                New-Item -ItemType Directory -Path (Split-Path -Parent $targetPath) -Force | Out-Null
                $bitmap = [Drawing.Bitmap]::new($decodedBitmapPath)
                try {
                    $width = $bitmap.Width
                    $height = $bitmap.Height
                    $bitmap.Save($targetPath, [Drawing.Imaging.ImageFormat]::Png)
                }
                finally {
                    $bitmap.Dispose()
                }
                if ($entry.Id -ne 129 -or $width -ne 64 -or $height -ne 64) {
                    throw "Decoded Classic ppat $($entry.Id) is ${width}x${height}; expected ppat 129 at 64x64"
                }
                $pngBytes = [IO.File]::ReadAllBytes($targetPath)
                $records += [ordered]@{
                    id = "realmz-application-ppat-$($entry.Id)"
                    label = "Classic scrolling text background"
                    kind = "pattern"
                    mime_type = "image/png"
                    resource_type = $set.resource_type
                    resource_id = $entry.Id
                    path = "res://src/presentation/assets/classic-media/$relativePath"
                    bytes = $pngBytes.Length
                    sha256 = (Get-FileHash -Algorithm SHA256 -LiteralPath $targetPath).Hash.ToLowerInvariant()
                    width = $width
                    height = $height
                    source_repository = $catalog.source_repository
                    source_commit = $catalog.source_commit
                    source_path = $set.source_path
                    source_file_sha256 = $set.source_file_sha256
                    source_resource_sha256 = (Get-FileHash -InputStream ([IO.MemoryStream]::new($entry.Bytes)) -Algorithm SHA256).Hash.ToLowerInvariant()
                    classification = $set.classification
                    classic_evidence = [ordered]@{
                        status = "source-control-flow"
                        path = $set.evidence_path
                        note = $set.evidence_note
                    }
                }
                continue
            }
            if ($set.resource_type -eq "snd ") {
                $decoded = Convert-SndToWav $entry.Bytes $entry.Id
                $evidencePath = $set.evidence_path
                $evidenceNote = $set.evidence_note
                if ($entry.Id -eq 624) {
                    $evidencePath = "src/realmz_orig/showlogo.c:16-60"
                    $evidenceNote = "Castle plays exact application sound 624 on both transitions around its timed launch logo."
                } elseif ($entry.Id -eq 20) {
                    $evidencePath = "src/realmz_orig/main.c:897-1009"
                    $evidenceNote = "Castle plays exact application sound 20 after the timed launch logo as its main application window becomes available."
                }
                $relativePath = "$($set.target_directory)/snd-$($entry.Id).wav"
                $targetPath = Join-Path $outputRoot ($relativePath -replace "/", [IO.Path]::DirectorySeparatorChar)
                New-Item -ItemType Directory -Path (Split-Path -Parent $targetPath) -Force | Out-Null
                [IO.File]::WriteAllBytes($targetPath, $decoded.Bytes)
                $records += [ordered]@{
                    id = "realmz-application-snd-$($entry.Id)"
                    label = "Realmz sound $($entry.Id)"
                    kind = "sound"
                    mime_type = "audio/wav"
                    resource_type = $set.resource_type
                    resource_id = $entry.Id
                    path = "res://src/presentation/assets/classic-media/$relativePath"
                    bytes = $decoded.Bytes.Length
                    sha256 = (Get-FileHash -Algorithm SHA256 -LiteralPath $targetPath).Hash.ToLowerInvariant()
                    sample_rate = $decoded.PlaybackRate
                    source_sample_rate = $decoded.SourceRate
                    samples = $decoded.Samples
                    duration_ms = if ($decoded.SourceRate -gt 0) { [Math]::Floor($decoded.Samples * 1000.0 / $decoded.SourceRate) } else { 0 }
                    channels = 1
                    source_repository = $catalog.source_repository
                    source_commit = $catalog.source_commit
                    source_path = $set.source_path
                    source_file_sha256 = $set.source_file_sha256
                    source_resource_sha256 = (Get-FileHash -InputStream ([IO.MemoryStream]::new($entry.Bytes)) -Algorithm SHA256).Hash.ToLowerInvariant()
                    classification = $set.classification
                    classic_evidence = [ordered]@{
                        status = "source-control-flow"
                        path = $evidencePath
                        note = $evidenceNote
                    }
                }
                continue
            }
            if ($set.resource_type -eq "cicn") {
                $relativePath = "$($set.target_directory)/cicn-$($entry.Id).png"
                $targetPath = Join-Path $outputRoot ($relativePath -replace "/", [IO.Path]::DirectorySeparatorChar)
                & $cicnExporterPath -ResourceForkPath $sourcePath -ResourceId $entry.Id -OutputPath $targetPath
                if ($LASTEXITCODE -ne 0) {
                    throw "Classic cicn export failed for resource $($entry.Id)"
                }
                $pngBytes = [IO.File]::ReadAllBytes($targetPath)
                if ($pngBytes.Length -lt 24) {
                    throw "Decoded cicn PNG is truncated: $($entry.Id)"
                }
                $width = [int](Get-U32 $pngBytes 16)
                $height = [int](Get-U32 $pngBytes 20)
                $records += [ordered]@{
                    id = "realmz-application-cicn-$($entry.Id)"
                    label = "Realmz color icon $($entry.Id)"
                    kind = "icon"
                    mime_type = "image/png"
                    resource_type = $set.resource_type
                    resource_id = $entry.Id
                    path = "res://src/presentation/assets/classic-media/$relativePath"
                    bytes = $pngBytes.Length
                    sha256 = (Get-FileHash -Algorithm SHA256 -LiteralPath $targetPath).Hash.ToLowerInvariant()
                    width = $width
                    height = $height
                    source_repository = $catalog.source_repository
                    source_commit = $catalog.source_commit
                    source_path = $set.source_path
                    source_file_sha256 = $set.source_file_sha256
                    source_resource_sha256 = (Get-FileHash -InputStream ([IO.MemoryStream]::new($entry.Bytes)) -Algorithm SHA256).Hash.ToLowerInvariant()
                    classification = $set.classification
                    classic_evidence = [ordered]@{
                        status = "source-control-flow"
                        path = $set.evidence_path
                        note = $set.evidence_note
                    }
                }
                continue
            }
            throw "Unsupported application resource type: $($set.resource_type)"
        }
    }

    if ($SoundOnly) {
        $generatedSounds = @{}
        foreach ($record in $records) {
            $generatedSounds[$record.id] = $record
        }
        $records = @($existingManifest.assets | ForEach-Object {
            if ($_.resource_type -eq "snd ") {
                if (-not $generatedSounds.ContainsKey($_.id)) {
                    throw "Existing sound is absent from regenerated media: $($_.id)"
                }
                $generatedSounds[$_.id]
            } else {
                $_
            }
        })
        if (@($generatedSounds.Keys).Count -ne @($existingManifest.assets | Where-Object resource_type -eq "snd ").Count) {
            throw "Regenerated sound count does not match the committed manifest"
        }
    }
    elseif ($CicnOnly) {
        $generatedCicns = @{}
        foreach ($record in $records) {
            $generatedCicns[$record.id] = $record
        }
        $existingCicnIds = @{}
        $mergedRecords = @($existingManifest.assets | ForEach-Object {
            if ($_.resource_type -ne "cicn") {
                return $_
            }
            if (-not $generatedCicns.ContainsKey($_.id)) {
                throw "Existing cicn is absent from regenerated media: $($_.id)"
            }
            $existingCicnIds[$_.id] = $true
            return $generatedCicns[$_.id]
        })
        $newRecords = @($records | Where-Object { -not $existingCicnIds.ContainsKey($_.id) })
        $records = @($mergedRecords) + @($newRecords)
    }
    elseif ($PictOnly) {
        $generatedPicts = @{}
        foreach ($record in $records) {
            $generatedPicts[$record.id] = $record
        }
        $existingPictIds = @{}
        $mergedRecords = @($existingManifest.assets | ForEach-Object {
            if ($_.resource_type -ne "PICT") {
                return $_
            }
            if ($generatedPicts.ContainsKey($_.id)) {
                $existingPictIds[$_.id] = $true
                return $generatedPicts[$_.id]
            }
            return $_
        })
        $newRecords = @($records | Where-Object { -not $existingPictIds.ContainsKey($_.id) })
        $records = @($mergedRecords) + @($newRecords)
    }

    $manifest = [ordered]@{
        schema_version = 1
        source_repository = $catalog.source_repository
        source_commit = $catalog.source_commit
        copyright = $catalog.copyright
        license = $catalog.license
        license_url = $catalog.license_url
        modification = $catalog.modification
        generated_by = "tools/ui-assets/sync-classic-application-media.ps1"
        lookup = "scenario-first-application-fallback"
        assets = $records
    }
    $manifestText = ($manifest | ConvertTo-Json -Depth 8) + [Environment]::NewLine
    $stagedManifest = Join-Path $stagingRoot "classic-application-media.json"
    [IO.File]::WriteAllText($stagedManifest, $manifestText, [Text.UTF8Encoding]::new($false))

    New-Item -ItemType Directory -Path $destinationRoot -Force | Out-Null
    $resolvedDestinationRoot = [IO.Path]::GetFullPath($destinationRoot).TrimEnd([IO.Path]::DirectorySeparatorChar) + [IO.Path]::DirectorySeparatorChar
    $ownedDirectories = @($activeResourceSets | ForEach-Object { $_.target_directory } | Sort-Object -Unique)
    foreach ($ownedDirectory in $ownedDirectories) {
        $destinationDirectory = [IO.Path]::GetFullPath((Join-Path $destinationRoot $ownedDirectory))
        if (-not $destinationDirectory.StartsWith($resolvedDestinationRoot, [StringComparison]::OrdinalIgnoreCase)) {
            throw "Catalog target directory escapes the Classic media root: $ownedDirectory"
        }
        if (Test-Path -LiteralPath $destinationDirectory) {
            foreach ($sidecar in Get-ChildItem -LiteralPath $destinationDirectory -Recurse -File -Filter "*.import") {
                $relativePath = [IO.Path]::GetRelativePath($destinationRoot, $sidecar.FullName)
                $stagedSidecar = Join-Path $sidecarRoot $relativePath
                New-Item -ItemType Directory -Path (Split-Path -Parent $stagedSidecar) -Force | Out-Null
                Copy-Item -LiteralPath $sidecar.FullName -Destination $stagedSidecar
            }
            Remove-Item -LiteralPath $destinationDirectory -Recurse -Force
        }
        $stagedDirectory = Join-Path $outputRoot $ownedDirectory
        if (Test-Path -LiteralPath $stagedDirectory) {
            Copy-Item -LiteralPath $stagedDirectory -Destination $destinationRoot -Recurse -Force
        }
    }
    foreach ($sidecar in Get-ChildItem -LiteralPath $sidecarRoot -Recurse -File -Filter "*.import") {
        $relativePath = [IO.Path]::GetRelativePath($sidecarRoot, $sidecar.FullName)
        $sourceAssetRelativePath = $relativePath.Substring(0, $relativePath.Length - ".import".Length)
        if (Test-Path -LiteralPath (Join-Path $destinationRoot $sourceAssetRelativePath) -PathType Leaf) {
            $destinationSidecar = Join-Path $destinationRoot $relativePath
            New-Item -ItemType Directory -Path (Split-Path -Parent $destinationSidecar) -Force | Out-Null
            Copy-Item -LiteralPath $sidecar.FullName -Destination $destinationSidecar
        }
    }
    Copy-Item -LiteralPath $stagedManifest -Destination $manifestPath -Force
    Write-Host "Imported $($records.Count) exact-commit Classic application media assets."
}
finally {
    if (Test-Path -LiteralPath $stagingRoot) {
        Remove-Item -LiteralPath $stagingRoot -Recurse -Force
    }
}
