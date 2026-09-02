$ErrorActionPreference = "Stop"

function Assert-Condition([bool]$Condition, [string]$Message) {
    if (-not $Condition) {
        throw "Classic application music validation failed: $Message"
    }
}

$toolRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
$repoRoot = Split-Path -Parent (Split-Path -Parent $toolRoot)
$sourceCatalog = Get-Content -Raw -LiteralPath (Join-Path $toolRoot "application-music-catalog.json") | ConvertFrom-Json
$manifestPath = Join-Path $repoRoot "src/presentation/assets/classic-application-music.json"
Assert-Condition (Test-Path -LiteralPath $manifestPath -PathType Leaf) "runtime manifest is missing"
$manifest = Get-Content -Raw -LiteralPath $manifestPath | ConvertFrom-Json
Assert-Condition ($manifest.schema_version -eq 1) "manifest schema is unsupported"
Assert-Condition ($manifest.ownership -eq "classic-application") "ownership is not application-scoped"
Assert-Condition ($manifest.slot_count -eq 20) "Classic slot count changed"
Assert-Condition ($manifest.lookup -eq "playlist-id") "lookup contract changed"
Assert-Condition ($manifest.decoder.name -eq $sourceCatalog.decoder.name -and $manifest.decoder.version -eq $sourceCatalog.decoder.version -and $manifest.decoder.license -eq "BSD-3-Clause") "OpenMPT provenance drifted"
Assert-Condition ($manifest.decoder.sample_rate -eq 48000 -and $manifest.decoder.channels -eq 2 -and $manifest.decoder.sample_format -eq "float32") "OpenMPT render contract drifted"
Assert-Condition ($manifest.encoder.name -eq $sourceCatalog.encoder.name -and $manifest.encoder.version -eq $sourceCatalog.encoder.version -and $manifest.encoder.quality -eq $sourceCatalog.encoder.quality) "Vorbis encoder provenance drifted"
Assert-Condition (@($manifest.tracks).Count -eq @($sourceCatalog.tracks).Count) "track count changed"

$seen = @{}
foreach ($record in @($manifest.tracks)) {
    $playlistId = [int]$record.playlist_id
    Assert-Condition ($playlistId -ge 1 -and $playlistId -le 11) "invalid stock playlist $playlistId"
    Assert-Condition (-not $seen.ContainsKey($playlistId)) "duplicate playlist $playlistId"
    $seen[$playlistId] = $true
    $source = @($sourceCatalog.tracks | Where-Object { [int]$_.playlist_id -eq $playlistId })
    Assert-Condition ($source.Count -eq 1) "playlist $playlistId is absent from the source catalog"
    Assert-Condition ($record.context -eq $source[0].context -and $record.title -eq $source[0].title) "playlist $playlistId identity drifted"
    Assert-Condition ($record.source_repository -eq $sourceCatalog.source_repository -and $record.source_commit -eq $source[0].source_commit -and $record.source_sha256 -eq $source[0].source_sha256 -and $record.source_bytes -eq $source[0].source_bytes) "playlist $playlistId source provenance drifted"
    Assert-Condition ($record.duration_ms -eq $source[0].duration_ms) "playlist $playlistId duration drifted"
    Assert-Condition ($record.mime_type -eq "audio/ogg" -and $record.classification -eq "classic-application-music") "playlist $playlistId runtime classification drifted"
    Assert-Condition ([string]$record.path -match '^res://src/presentation/assets/classic-media/music/playlist-[0-9]{2}-[a-z0-9-]+\.ogg$') "playlist $playlistId path is invalid"
    $relative = ([string]$record.path).Substring("res://".Length) -replace '/', [IO.Path]::DirectorySeparatorChar
    $fullPath = Join-Path $repoRoot $relative
    Assert-Condition (Test-Path -LiteralPath $fullPath -PathType Leaf) "playlist $playlistId file is missing"
    $bytes = [IO.File]::ReadAllBytes($fullPath)
    Assert-Condition ($bytes.Length -eq [int64]$record.bytes) "playlist $playlistId byte count drifted"
    Assert-Condition ((Get-FileHash -Algorithm SHA256 -LiteralPath $fullPath).Hash.ToLowerInvariant() -eq $record.sha256) "playlist $playlistId output hash drifted"
    Assert-Condition ($bytes.Length -ge 4 -and [Text.Encoding]::ASCII.GetString($bytes, 0, 4) -eq "OggS") "playlist $playlistId is not an Ogg stream"
}

foreach ($playlistId in 1..11) {
    Assert-Condition ($seen.ContainsKey($playlistId)) "stock playlist $playlistId is missing"
}
$outdoor = @($manifest.tracks | Where-Object { [int]$_.playlist_id -eq 1 })[0]
Assert-Condition ($outdoor.legacy_source_commit -eq $sourceCatalog.tracks[0].legacy_source_commit -and $outdoor.legacy_source_sha256 -eq $sourceCatalog.tracks[0].legacy_source_sha256 -and -not [string]::IsNullOrWhiteSpace([string]$outdoor.replacement_reason)) "Outdoor MADG replacement evidence drifted"
$musicRoot = Join-Path $repoRoot "src/presentation/assets/classic-media/music"
$committedNames = @($manifest.tracks | ForEach-Object { [IO.Path]::GetFileName([string]$_.path) } | Sort-Object)
$diskNames = @(Get-ChildItem -LiteralPath $musicRoot -File -Filter "playlist-*.ogg" | Select-Object -ExpandProperty Name | Sort-Object)
Assert-Condition (($committedNames -join "`n") -eq ($diskNames -join "`n")) "stock music directory contains missing or untracked playlist files"

Write-Host "Classic application music validation passed: $($seen.Count) stock tracks, 20 playlist slots."
