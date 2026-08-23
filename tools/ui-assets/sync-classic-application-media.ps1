param(
    [Parameter(Mandatory = $true)]
    [string]$CastleRepository
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

function Add-LittleEndian([Collections.Generic.List[byte]]$Output, [uint32]$Value, [int]$Width) {
    for ($index = 0; $index -lt $Width; $index++) {
        $Output.Add([byte](($Value -shr (8 * $index)) -band 0xff))
    }
}

function New-Wav([byte[]]$Samples, [uint32]$SampleRate) {
    $output = [Collections.Generic.List[byte]]::new()
    $paddedLength = $Samples.Length + ($Samples.Length -band 1)
    $output.AddRange([Text.Encoding]::ASCII.GetBytes("RIFF"))
    Add-LittleEndian $output ([uint32](36 + $paddedLength)) 4
    $output.AddRange([Text.Encoding]::ASCII.GetBytes("WAVEfmt "))
    Add-LittleEndian $output 16 4
    Add-LittleEndian $output 1 2
    Add-LittleEndian $output 1 2
    Add-LittleEndian $output $SampleRate 4
    Add-LittleEndian $output $SampleRate 4
    Add-LittleEndian $output 1 2
    Add-LittleEndian $output 8 2
    $output.AddRange([Text.Encoding]::ASCII.GetBytes("data"))
    Add-LittleEndian $output ([uint32]$Samples.Length) 4
    $output.AddRange($Samples)
    if (($Samples.Length -band 1) -ne 0) {
        $output.Add(0)
    }
    return ,$output.ToArray()
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
    $playbackRate = $sourceRate
    $playbackSamples = $sourceSamples
    if ($sourceRate -lt 8000) {
        $playbackRate = 8000
        $outputLength = [Math]::Max(1, [int](($sourceSamples.Length * 8000L) / $sourceRate))
        $playbackSamples = [byte[]]::new($outputLength)
        for ($index = 0; $index -lt $outputLength; $index++) {
            $sourceIndex = [Math]::Min($sourceSamples.Length - 1, [int](($index * [long]$sourceRate) / 8000L))
            $playbackSamples[$index] = if ($sourceSamples.Length -gt 0) { $sourceSamples[$sourceIndex] } else { 128 }
        }
    }
    return [pscustomobject]@{
        Bytes = New-Wav $playbackSamples $playbackRate
        SourceRate = $sourceRate
        PlaybackRate = $playbackRate
        Samples = $sourceSamples.Length
    }
}

$toolRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
$repoRoot = Split-Path -Parent (Split-Path -Parent $toolRoot)
$catalogPath = Join-Path $toolRoot "application-media-catalog.json"
$cicnExporterPath = Join-Path $toolRoot "export-classic-cicn.ps1"
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
New-Item -ItemType Directory -Path $extractRoot, $outputRoot, $sidecarRoot | Out-Null

try {
    $sourcePaths = @($catalog.resource_sets | ForEach-Object { $_.source_path } | Sort-Object -Unique)
    & git -C $castleRoot archive --format=zip --output=$archivePath $catalog.source_commit -- @sourcePaths
    if ($LASTEXITCODE -ne 0) {
        throw "Castle git archive failed"
    }
    Expand-Archive -LiteralPath $archivePath -DestinationPath $extractRoot

    $records = @()
    foreach ($set in $catalog.resource_sets) {
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
            if ($set.resource_type -eq "snd ") {
                $decoded = Convert-SndToWav $entry.Bytes $entry.Id
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
                        path = $set.evidence_path
                        note = $set.evidence_note
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
    $ownedDirectories = @($catalog.resource_sets | ForEach-Object { $_.target_directory } | Sort-Object -Unique)
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
