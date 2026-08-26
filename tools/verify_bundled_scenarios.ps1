$ErrorActionPreference = "Stop"
$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path
$campaignRoot = Join-Path $repoRoot "src\infrastructure\campaigns"
$catalogPath = Join-Path $campaignRoot "castle-bundled-scenarios.provenance.json"
$catalog = Get-Content -Raw -LiteralPath $catalogPath | ConvertFrom-Json

if ($catalog.formatVersion -ne 1 -or $catalog.source.license -ne "CC-BY-NC-SA-4.0") {
    throw "Bundled scenario provenance header is invalid."
}
if (@($catalog.scenarios).Count -ne 13) {
    throw "Bundled scenario catalog must contain exactly 13 Castle-distributed scenarios."
}
$expectedCampaignIds = @(
    "scenario-assault-on-giant-mountain",
    "scenario-castle-in-the-clouds",
    "scenario-city-of-bywater",
    "scenario-destroy-the-necronomicon",
    "scenario-grilochs-revenge",
    "scenario-half-truth",
    "scenario-mithril-vault",
    "scenario-prelude-to-pestilence",
    "scenario-trouble-in-the-sword-lands",
    "scenario-twin-sands-of-time",
    "scenario-war-in-the-sword-lands",
    "scenario-white-dragon",
    "scenario-wrath-of-the-mind-lords"
)
$catalogCampaignIds = @($catalog.scenarios | ForEach-Object { $_.campaignId } | Sort-Object)
if (($catalogCampaignIds -join "|") -ne (($expectedCampaignIds | Sort-Object) -join "|")) {
    throw "Bundled scenario catalog does not name the exact Castle-distributed campaign set."
}

$expectedFiles = @($catalog.scenarios | ForEach-Object { $_.file } | Sort-Object)
$actualFiles = @(Get-ChildItem -LiteralPath $campaignRoot -Filter "*.realmz2" -File | ForEach-Object { $_.Name } | Sort-Object)
if (($expectedFiles -join "|") -ne ($actualFiles -join "|")) {
    throw "Bundled scenario archive set does not match the provenance catalog."
}

Add-Type -AssemblyName System.IO.Compression.FileSystem
foreach ($scenario in $catalog.scenarios) {
    $packagePath = Join-Path $campaignRoot $scenario.file
    $package = Get-Item -LiteralPath $packagePath
    if ($package.Length -ne [long]$scenario.bytes) {
        throw "$($scenario.file) byte count does not match provenance."
    }
    $archiveHash = (Get-FileHash -LiteralPath $packagePath -Algorithm SHA256).Hash.ToLowerInvariant()
    if ($archiveHash -ne $scenario.archiveSha256) {
        throw "$($scenario.file) archive SHA-256 does not match provenance."
    }
    $archive = [System.IO.Compression.ZipFile]::OpenRead($packagePath)
    try {
        $entry = $archive.GetEntry("manifest.json")
        if ($null -eq $entry) { throw "$($scenario.file) has no manifest.json." }
        $reader = [System.IO.StreamReader]::new($entry.Open())
        try { $manifest = $reader.ReadToEnd() | ConvertFrom-Json }
        finally { $reader.Dispose() }
    } finally {
        $archive.Dispose()
    }
    if ($manifest.campaignId -ne $scenario.campaignId -or $manifest.name -ne $scenario.name -or $manifest.packageHash -ne $scenario.packageHash) {
        throw "$($scenario.file) manifest identity does not match provenance."
    }
    if ($manifest.compiler.commit -ne $catalog.compiler.revision) {
        throw "$($scenario.file) was not produced by the pinned Providence revision."
    }
}

Write-Host "Verified 13 Castle-distributed bundled scenarios."
