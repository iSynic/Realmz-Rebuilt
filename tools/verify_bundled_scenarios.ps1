$ErrorActionPreference = "Stop"
$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path
$campaignRoot = Join-Path $repoRoot "src\infrastructure\campaigns"
$catalogPath = Join-Path $campaignRoot "castle-bundled-scenarios.provenance.json"
$citySourcePath = Join-Path $campaignRoot "city-of-bywater.source.json"
$catalog = Get-Content -Raw -LiteralPath $catalogPath | ConvertFrom-Json

if ($catalog.formatVersion -ne 1 -or $catalog.source.license -ne "CC-BY-NC-SA-4.0" -or $catalog.source.defaultForScenariosWithoutOverride -ne $true) {
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

$city = @($catalog.scenarios | Where-Object { $_.campaignId -eq "scenario-city-of-bywater" })
if ($city.Count -ne 1 -or $city[0].sourceOverride.kind -ne "project-owner-designated-snapshot" -or $city[0].sourceOverride.catalog -ne "city-of-bywater.source.json") {
    throw "City of Bywater must name its project-owner-designated source catalog."
}
$unexpectedOverrides = @($catalog.scenarios | Where-Object { $_.campaignId -ne "scenario-city-of-bywater" -and $null -ne $_.sourceOverride })
if ($unexpectedOverrides.Count -ne 0) {
    throw "Only City of Bywater may override the default pinned Castle source."
}

$citySource = Get-Content -Raw -LiteralPath $citySourcePath | ConvertFrom-Json
$cityFiles = @($citySource.files)
if ($citySource.formatVersion -ne 1 -or $citySource.campaignId -ne "scenario-city-of-bywater" -or $citySource.authority -ne "project-owner-designated" -or $citySource.upstreamStatus -ne "pending-castle-adoption") {
    throw "City of Bywater source provenance header is invalid."
}
if ($citySource.snapshot.algorithm -ne "sha256-utf8-file-null-bytes-null-sha256-lines-v1" -or $cityFiles.Count -ne [int]$citySource.snapshot.fileCount) {
    throw "City of Bywater source snapshot shape is invalid."
}
$sourceNames = @($cityFiles | ForEach-Object { $_.file })
if (($sourceNames | Sort-Object -Unique).Count -ne $sourceNames.Count) {
    throw "City of Bywater source snapshot contains duplicate file identities."
}
$sourceBytes = [long]0
$sourceLines = [System.Text.StringBuilder]::new()
foreach ($sourceFile in $cityFiles) {
    if ($sourceFile.file -notmatch '^[^/\\:]+$' -or $sourceFile.bytes -lt 0 -or $sourceFile.sha256 -notmatch '^[0-9a-f]{64}$') {
        throw "City of Bywater source snapshot contains an invalid file identity."
    }
    $sourceBytes += [long]$sourceFile.bytes
    [void]$sourceLines.Append($sourceFile.file).Append([char]0).Append([long]$sourceFile.bytes).Append([char]0).Append($sourceFile.sha256).Append("`n")
}
$sourceHashAlgorithm = [System.Security.Cryptography.SHA256]::Create()
try {
    $sourceHashBytes = $sourceHashAlgorithm.ComputeHash([System.Text.UTF8Encoding]::new($false).GetBytes($sourceLines.ToString()))
} finally {
    $sourceHashAlgorithm.Dispose()
}
$sourceHash = [Convert]::ToHexString($sourceHashBytes).ToLowerInvariant()
if ($sourceBytes -ne [long]$citySource.snapshot.bytes -or $sourceHash -ne $citySource.snapshot.sha256 -or $sourceHash -ne $city[0].sourceOverride.snapshotSha256) {
    throw "City of Bywater source snapshot identity does not match its provenance catalogs."
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
        if ($scenario.campaignId -eq "scenario-city-of-bywater") {
            $worldEntry = $archive.GetEntry("world.json")
            $scenarioEntry = $archive.GetEntry("scenario.json")
            if ($null -eq $worldEntry -or $null -eq $scenarioEntry) { throw "City of Bywater has no compiled world or scenario document." }
            $worldReader = [System.IO.StreamReader]::new($worldEntry.Open())
            try { $world = $worldReader.ReadToEnd() | ConvertFrom-Json }
            finally { $worldReader.Dispose() }
            $scenarioReader = [System.IO.StreamReader]::new($scenarioEntry.Open())
            try { $scenarioDocument = $scenarioReader.ReadToEnd() | ConvertFrom-Json }
            finally { $scenarioReader.Dispose() }
            $ranthogTrigger = @($world.triggers | Where-Object { $_.id -eq "Data DD:0:39" })
            $ranthogReward = @($scenarioDocument.programs | Where-Object { $_.id -eq "xap:50" })
            if ($ranthogTrigger.Count -ne 1 -or $ranthogTrigger[0].active -ne $false -or $ranthogTrigger[0].chancePercent -ne -100 -or $ranthogTrigger[0].mapId -ne "land:0" -or $ranthogTrigger[0].coordinate.x -ne 39 -or $ranthogTrigger[0].coordinate.y -ne 56) {
                throw "City of Bywater must preserve dormant placed Action Point Data DD:0:39 at land:0 39,56."
            }
            if ($ranthogReward.Count -ne 1 -or (@($ranthogReward[0].instructions | ForEach-Object { $_.opcode }) -join ",") -ne "1,3,1,29,13,12,12") {
                throw "City of Bywater XAP 50 must retain the Ranthog reward, dormant-AP enable, and tree-tile mutation sequence."
            }
        }
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

Write-Host "Verified the 13-scenario bundle and designated City of Bywater source snapshot."
