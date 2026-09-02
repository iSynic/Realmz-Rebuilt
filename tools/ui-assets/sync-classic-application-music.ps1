param(
    [Parameter(Mandatory = $true)]
    [string]$CastleRepository,
    [Parameter(Mandatory = $true)]
    [string]$OpenMpt123Path,
    [Parameter(Mandatory = $true)]
    [string]$FfmpegPath
)

$ErrorActionPreference = "Stop"

function Get-SafeSlug([string]$Value) {
    return ($Value.ToLowerInvariant() -replace '[^a-z0-9]+', '-').Trim('-')
}

function Invoke-Checked([string]$Program, [string[]]$Arguments, [string]$Failure) {
    & $Program @Arguments
    if ($LASTEXITCODE -ne 0) {
        throw "$Failure (exit $LASTEXITCODE)"
    }
}

$toolRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
$repoRoot = Split-Path -Parent (Split-Path -Parent $toolRoot)
$catalogPath = Join-Path $toolRoot "application-music-catalog.json"
$catalog = Get-Content -Raw -LiteralPath $catalogPath | ConvertFrom-Json
$castleRoot = (Resolve-Path -LiteralPath $CastleRepository).Path
$openMpt = (Resolve-Path -LiteralPath $OpenMpt123Path).Path
$ffmpeg = (Resolve-Path -LiteralPath $FfmpegPath).Path

foreach ($commit in @($catalog.tracks | ForEach-Object { $_.source_commit } | Sort-Object -Unique)) {
    $resolved = (& git -C $castleRoot rev-parse "$commit^{commit}").Trim()
    if ($LASTEXITCODE -ne 0 -or $resolved -ne $commit) {
        throw "The requested Castle music source commit is unavailable: $commit"
    }
}

$openMptVersion = (& $openMpt --version 2>&1 | Out-String)
if ($LASTEXITCODE -ne 0 -or $openMptVersion -notmatch [regex]::Escape([string]$catalog.decoder.version)) {
    throw "openmpt123 $($catalog.decoder.version) is required"
}
$ffmpegVersion = (& $ffmpeg -version 2>&1 | Select-Object -First 1 | Out-String)
if ($LASTEXITCODE -ne 0 -or $ffmpegVersion -notmatch [regex]::Escape([string]$catalog.encoder.version)) {
    throw "FFmpeg $($catalog.encoder.version) is required"
}

$stagingRoot = Join-Path ([IO.Path]::GetTempPath()) ("realmz-application-music-" + [Guid]::NewGuid().ToString("N"))
$sourceRoot = Join-Path $stagingRoot "source"
$outputRoot = Join-Path $stagingRoot "output"
New-Item -ItemType Directory -Path $sourceRoot, $outputRoot | Out-Null

try {
    $records = @()
    foreach ($track in @($catalog.tracks | Sort-Object playlist_id)) {
    $playlistId = [int]$track.playlist_id
    $slug = Get-SafeSlug ([string]$track.context)
    $archivePath = Join-Path $stagingRoot ("source-{0:D2}.zip" -f $playlistId)
    $extractRoot = Join-Path $sourceRoot ("{0:D2}" -f $playlistId)
    $sourcePath = "base/Realmz/Realmz Music/$($track.filename)"
    Invoke-Checked "git" @("-C", $castleRoot, "archive", "--format=zip", "--output=$archivePath", [string]$track.source_commit, "--", $sourcePath) "Castle music archive failed for playlist $playlistId"
    Expand-Archive -LiteralPath $archivePath -DestinationPath $extractRoot
    $modulePath = Join-Path $extractRoot ($sourcePath -replace '/', [IO.Path]::DirectorySeparatorChar)
    $sourceHash = (Get-FileHash -Algorithm SHA256 -LiteralPath $modulePath).Hash.ToLowerInvariant()
    $sourceBytes = (Get-Item -LiteralPath $modulePath).Length
    if ($sourceHash -ne [string]$track.source_sha256 -or $sourceBytes -ne [long]$track.source_bytes) {
        throw "Catalog source mismatch for playlist $playlistId"
    }

    $wavPath = Join-Path $stagingRoot ("playlist-{0:D2}.wav" -f $playlistId)
    $fileName = "playlist-{0:D2}-{1}.ogg" -f $playlistId, $slug
    $oggPath = Join-Path $outputRoot $fileName
    Invoke-Checked $openMpt @("--batch", "--quiet", "--samplerate", [string]$catalog.decoder.sample_rate, "--channels", [string]$catalog.decoder.channels, "--float", "--force", "--output", $wavPath, "--", $modulePath) "OpenMPT render failed for playlist $playlistId"
    Invoke-Checked $ffmpeg @("-hide_banner", "-loglevel", "error", "-y", "-i", $wavPath, "-map_metadata", "-1", "-c:a", "libvorbis", "-q:a", [string]$catalog.encoder.quality, $oggPath) "Vorbis encode failed for playlist $playlistId"
    $oggBytes = [IO.File]::ReadAllBytes($oggPath)
    if ($oggBytes.Length -lt 4 -or [Text.Encoding]::ASCII.GetString($oggBytes, 0, 4) -ne "OggS") {
        throw "Generated music is not an Ogg stream for playlist $playlistId"
    }
    $records += [ordered]@{
        playlist_id = $playlistId
        context = [string]$track.context
        title = [string]$track.title
        path = "res://src/presentation/assets/classic-media/music/$fileName"
        mime_type = "audio/ogg"
        bytes = $oggBytes.Length
        sha256 = (Get-FileHash -Algorithm SHA256 -LiteralPath $oggPath).Hash.ToLowerInvariant()
        duration_ms = [int]$track.duration_ms
        source_repository = [string]$catalog.source_repository
        source_commit = [string]$track.source_commit
        source_path = $sourcePath
        source_bytes = $sourceBytes
        source_sha256 = $sourceHash
        classification = "classic-application-music"
    }
    if ($null -ne $track.legacy_source_commit) {
        $records[-1]["legacy_source_commit"] = [string]$track.legacy_source_commit
        $records[-1]["legacy_source_sha256"] = [string]$track.legacy_source_sha256
        $records[-1]["replacement_reason"] = "Pinned Castle Outdoor Music is a legacy MADG module unsupported by OpenMPT; the exact later Castle MOD replacement preserves the stock title."
    }
    }

    $manifest = [ordered]@{
    schema_version = 1
    ownership = "classic-application"
    slot_count = 20
    lookup = "playlist-id"
    decoder = $catalog.decoder
    encoder = $catalog.encoder
    tracks = $records
    }
    $manifestJson = $manifest | ConvertTo-Json -Depth 12
    $stagedManifest = Join-Path $stagingRoot "classic-application-music.json"
    Set-Content -LiteralPath $stagedManifest -Value $manifestJson -Encoding utf8

    $destinationRoot = Join-Path $repoRoot "src/presentation/assets/classic-media/music"
    $manifestPath = Join-Path $repoRoot "src/presentation/assets/classic-application-music.json"
    New-Item -ItemType Directory -Path $destinationRoot -Force | Out-Null
    foreach ($existing in @(Get-ChildItem -LiteralPath $destinationRoot -File -Filter "playlist-*.ogg")) {
        if ($existing.Name -notin @($records | ForEach-Object { [IO.Path]::GetFileName([string]$_.path) })) {
            Remove-Item -LiteralPath $existing.FullName -Force
        }
    }
    Copy-Item -Path (Join-Path $outputRoot "*.ogg") -Destination $destinationRoot -Force
    Copy-Item -LiteralPath $stagedManifest -Destination $manifestPath -Force
    Write-Host "Generated $($records.Count) Classic application music tracks through OpenMPT."
}
finally {
    $expectedPrefix = Join-Path ([IO.Path]::GetTempPath()) "realmz-application-music-"
    if ($stagingRoot.StartsWith($expectedPrefix, [StringComparison]::OrdinalIgnoreCase) -and (Test-Path -LiteralPath $stagingRoot -PathType Container)) {
        Remove-Item -LiteralPath $stagingRoot -Recurse -Force
    }
}
