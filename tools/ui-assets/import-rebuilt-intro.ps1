param(
    [Parameter(Mandatory = $true)]
    [string]$SourceOgvPath,

    [string]$ExpectedSha256 = "f78a04d978b0de0b306598a201e5cccaa7e930b947b1bfab59d81437b4c8cf75"
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
if ((Get-Item -LiteralPath $sourcePath).Length -ne 1110117) {
    throw "Realmz Rebuilt intro OGV byte length changed"
}

$resolvedDestination = [IO.Path]::GetFullPath($destinationRoot)
$resolvedRepo = [IO.Path]::GetFullPath($repoRoot).TrimEnd([IO.Path]::DirectorySeparatorChar) + [IO.Path]::DirectorySeparatorChar
if (-not $resolvedDestination.StartsWith($resolvedRepo, [StringComparison]::OrdinalIgnoreCase)) {
    throw "Intro destination escapes the repository: $resolvedDestination"
}

try {
    New-Item -ItemType Directory -Path $stagingRoot | Out-Null
    $assetName = "rebuilt-intro.ogv"
    Copy-Item -LiteralPath $sourcePath -Destination (Join-Path $stagingRoot $assetName)
    $uidName = "$assetName.uid"
    $existingUidPath = Join-Path $resolvedDestination $uidName
    if (Test-Path -LiteralPath $existingUidPath -PathType Leaf) {
        Copy-Item -LiteralPath $existingUidPath -Destination (Join-Path $stagingRoot $uidName)
    }
    $manifest = [ordered]@{
        schema_version = 2
        source_role = "Realmz Rebuilt intro video supplied by the project owner"
        source_sha256 = $sourceHash
        license = "Project-Owner-Supplied"
        path = "res://src/presentation/assets/ui/intro/$assetName"
        bytes = 1110117
        width = 832
        height = 480
        frames_per_second = 24
        duration_ms = 5167
        video_codec = "theora"
        audio_codec = "vorbis"
        audio_sample_rate = 32000
        audio_channels = 2
        loop = $true
    }
    [IO.File]::WriteAllText((Join-Path $stagingRoot "intro-video.json"), (($manifest | ConvertTo-Json -Depth 4) + [Environment]::NewLine), [Text.UTF8Encoding]::new($false))

    if (Test-Path -LiteralPath $resolvedDestination) {
        Remove-Item -LiteralPath $resolvedDestination -Recurse -Force
    }
    Move-Item -LiteralPath $stagingRoot -Destination $resolvedDestination
    Write-Host "Imported the 832x480, 24-fps Realmz Rebuilt OGV intro with stereo audio."
}
finally {
    if (Test-Path -LiteralPath $stagingRoot) { Remove-Item -LiteralPath $stagingRoot -Recurse -Force }
}
