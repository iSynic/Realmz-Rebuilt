param(
    [Parameter(Mandatory = $true)]
    [string]$SourceOgvPath,

    [Parameter(Mandatory = $true)]
    [string]$SourceSoundtrackPath,

    [string]$ExpectedSha256 = "2b30c6bca4a8d6ba6ee524c28630c4706944f327b5d8d304ce0253050fb53f40",

    [string]$ExpectedSoundtrackSha256 = "c64e2792eba92284896084c3d48af9d595fdd98cda5e7a3d90931b2a9a21f0e5"
)

$ErrorActionPreference = "Stop"

$toolRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
$repoRoot = Split-Path -Parent (Split-Path -Parent $toolRoot)
$destinationRoot = Join-Path $repoRoot "src/presentation/assets/ui/intro"
$stagingRoot = Join-Path ([IO.Path]::GetTempPath()) ("rebuilt-intro-" + [Guid]::NewGuid().ToString("N"))
$sourcePath = (Resolve-Path -LiteralPath $SourceOgvPath).Path
$sourceHash = (Get-FileHash -Algorithm SHA256 -LiteralPath $sourcePath).Hash.ToLowerInvariant()
if ($sourceHash -ne $ExpectedSha256.ToLowerInvariant()) {
    throw "Realmz Rebuilt intro OGV hash does not match the approved source"
}
if ((Get-Item -LiteralPath $sourcePath).Length -ne 1097782) {
    throw "Realmz Rebuilt intro OGV byte length changed"
}
$soundtrackSourcePath = (Resolve-Path -LiteralPath $SourceSoundtrackPath).Path
$soundtrackSourceHash = (Get-FileHash -Algorithm SHA256 -LiteralPath $soundtrackSourcePath).Hash.ToLowerInvariant()
if ($soundtrackSourceHash -ne $ExpectedSoundtrackSha256.ToLowerInvariant()) {
    throw "Realmz Rebuilt intro soundtrack MP3 hash does not match the approved source"
}
if ((Get-Item -LiteralPath $soundtrackSourcePath).Length -ne 721197) {
    throw "Realmz Rebuilt intro soundtrack MP3 byte length changed"
}

$resolvedDestination = [IO.Path]::GetFullPath($destinationRoot)
$resolvedRepo = [IO.Path]::GetFullPath($repoRoot).TrimEnd([IO.Path]::DirectorySeparatorChar) + [IO.Path]::DirectorySeparatorChar
if (-not $resolvedDestination.StartsWith($resolvedRepo, [StringComparison]::OrdinalIgnoreCase)) {
    throw "Intro destination escapes the repository: $resolvedDestination"
}

try {
    New-Item -ItemType Directory -Path $stagingRoot | Out-Null
    $assetName = "rebuilt-intro.ogv"
    $soundtrackAssetName = "rebuilt-intro-soundtrack.mp3"
    Copy-Item -LiteralPath $sourcePath -Destination (Join-Path $stagingRoot $assetName)
    Copy-Item -LiteralPath $soundtrackSourcePath -Destination (Join-Path $stagingRoot $soundtrackAssetName)
    foreach ($retainedAssetName in @($assetName, $soundtrackAssetName)) {
        foreach ($sidecarSuffix in @(".uid", ".import")) {
            $sidecarName = "$retainedAssetName$sidecarSuffix"
            $existingSidecarPath = Join-Path $resolvedDestination $sidecarName
            if (Test-Path -LiteralPath $existingSidecarPath -PathType Leaf) {
                Copy-Item -LiteralPath $existingSidecarPath -Destination (Join-Path $stagingRoot $sidecarName)
            }
        }
    }
    $manifest = [ordered]@{
        schema_version = 3
        source_role = "Realmz Rebuilt intro video supplied by the project owner"
        source_sha256 = $sourceHash
        license = "Project-Owner-Supplied"
        path = "res://src/presentation/assets/ui/intro/$assetName"
        bytes = 1097782
        width = 832
        height = 480
        frames_per_second = 24
        duration_ms = 5167
        video_codec = "theora"
        audio_codec = "vorbis"
        audio_sample_rate = 48000
        audio_channels = 2
        loop = $true
        playback_audio = $false
        soundtrack = [ordered]@{
            source_role = "Realmz Rebuilt intro soundtrack supplied by the project owner"
            source_sha256 = $soundtrackSourceHash
            license = "Project-Owner-Supplied"
            path = "res://src/presentation/assets/ui/intro/$soundtrackAssetName"
            bytes = 721197
            duration_ms = 30000
            codec = "mp3"
            bit_rate = 192000
            sample_rate = 48000
            channels = 2
            loop = $true
            click_toggle = $true
            independent_from_video = $true
        }
    }
    [IO.File]::WriteAllText((Join-Path $stagingRoot "intro-video.json"), (($manifest | ConvertTo-Json -Depth 4) + [Environment]::NewLine), [Text.UTF8Encoding]::new($false))

    if (Test-Path -LiteralPath $resolvedDestination) {
        Remove-Item -LiteralPath $resolvedDestination -Recurse -Force
    }
    Move-Item -LiteralPath $stagingRoot -Destination $resolvedDestination
    Write-Host "Imported the silent-playback 832x480 Realmz Rebuilt OGV and its independent looping 30-second MP3 soundtrack."
}
finally {
    if (Test-Path -LiteralPath $stagingRoot) { Remove-Item -LiteralPath $stagingRoot -Recurse -Force }
}
