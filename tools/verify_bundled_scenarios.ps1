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
$sourceHash = ([BitConverter]::ToString($sourceHashBytes) -replace "-", "").ToLowerInvariant()
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
        $worldEntry = $archive.GetEntry("world.json")
        if ($null -eq $worldEntry) { throw "$($scenario.file) has no world.json." }
        $worldReader = [System.IO.StreamReader]::new($worldEntry.Open())
        try { $world = $worldReader.ReadToEnd() | ConvertFrom-Json }
        finally { $worldReader.Dispose() }
        $assetEntry = $archive.GetEntry("assets/index.json")
        if ($null -eq $assetEntry) { throw "$($scenario.file) has no assets/index.json." }
        $assetReader = [System.IO.StreamReader]::new($assetEntry.Open())
        try { $assetIndex = $assetReader.ReadToEnd() | ConvertFrom-Json }
        finally { $assetReader.Dispose() }
        $assetIds = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::Ordinal)
        $landCicnIds = [System.Collections.Generic.HashSet[int]]::new()
        $resourceKeys = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::Ordinal)
        foreach ($asset in @($assetIndex.assets)) {
            if (-not [string]::IsNullOrWhiteSpace([string]$asset.id)) { [void]$assetIds.Add([string]$asset.id) }
            if ($asset.resourceType -eq "cicn" -and $null -ne $asset.resourceId) { [void]$landCicnIds.Add([int]$asset.resourceId) }
            if (-not [string]::IsNullOrWhiteSpace([string]$asset.resourceType) -and $null -ne $asset.resourceId) {
                [void]$resourceKeys.Add("$($asset.resourceType):$([int]$asset.resourceId)")
            }
        }
        $scenarioEntry = $archive.GetEntry("scenario.json")
        if ($null -eq $scenarioEntry) { throw "$($scenario.file) has no scenario.json." }
        $scenarioReader = [System.IO.StreamReader]::new($scenarioEntry.Open())
        try { $scenarioDocument = $scenarioReader.ReadToEnd() | ConvertFrom-Json }
        finally { $scenarioReader.Dispose() }
        foreach ($program in @($scenarioDocument.programs)) {
            foreach ($instruction in @($program.instructions | Where-Object { $_.kind -eq "classicAction" -and $_.opcode -eq 62 })) {
                $resourceId = [int]$instruction.id
                if ($resourceId -eq 0) {
                    throw "$($scenario.file) program $($program.id) retains Castle's invalid scrolling-text resource ID 0."
                }
                if (-not $resourceKeys.Contains("TEXT:$resourceId")) {
                    throw "$($scenario.file) program $($program.id) has no exact scenario TEXT $resourceId asset for scrolling text."
                }
                if (-not $resourceKeys.Contains("styl:$resourceId")) {
                    throw "$($scenario.file) program $($program.id) has no same-ID Classic styl $resourceId asset for scrolling text."
                }
            }
        }
        foreach ($map in @($world.maps | Where-Object { $_.levelType -eq "land" })) {
            foreach ($cell in $map.cells) {
                $overlayId = [string]$cell[10]
                if (-not [string]::IsNullOrWhiteSpace($overlayId) -and (-not $assetIds.Contains($overlayId) -or [int]$cell[8] -gt 200)) {
                    throw "$($scenario.file) map $($map.id) has an unresolved or unseparated land overlay '$overlayId'."
                }
                if ([string]$cell[0] -match '^classic\.terrain\.(-?\d+)$') {
                    $terrainId = [int]$Matches[1]
                    if (($terrainId -lt 0 -or $terrainId -gt 200) -and $landCicnIds.Contains($terrainId) -and [string]::IsNullOrWhiteSpace($overlayId)) {
                        throw "$($scenario.file) map $($map.id) omits resolved land CICN $terrainId."
                    }
                }
            }
        }
        if ($scenario.campaignId -eq "scenario-city-of-bywater") {
            $contentEntry = $archive.GetEntry("content.json")
            if ($null -eq $contentEntry) { throw "City of Bywater has no compiled content document." }
            $contentReader = [System.IO.StreamReader]::new($contentEntry.Open())
            try { $contentDocument = $contentReader.ReadToEnd() | ConvertFrom-Json }
            finally { $contentReader.Dispose() }
            $ranthogTrigger = @($world.triggers | Where-Object { $_.id -eq "Data DD:0:39" })
            $ranthogReward = @($scenarioDocument.programs | Where-Object { $_.id -eq "xap:50" })
            $cryptDoorEncounter = @($contentDocument.complexEncounters | Where-Object { $_.id -eq 4 })
            $cryptDoorPrompt = @($contentDocument.messages | Where-Object { $_.id -eq 218 })
            $cobLandFive = @($world.maps | Where-Object { $_.id -eq "land:5" })
            $cobSecretCell = if ($cobLandFive.Count -eq 1) { $cobLandFive[0].cells[(10 * [int]$cobLandFive[0].width) + 61] } else { $null }
            if ($ranthogTrigger.Count -ne 1 -or $ranthogTrigger[0].active -ne $false -or $ranthogTrigger[0].chancePercent -ne -100 -or $ranthogTrigger[0].mapId -ne "land:0" -or $ranthogTrigger[0].coordinate.x -ne 39 -or $ranthogTrigger[0].coordinate.y -ne 56) {
                throw "City of Bywater must preserve dormant placed Action Point Data DD:0:39 at land:0 39,56."
            }
            if ($ranthogReward.Count -ne 1 -or (@($ranthogReward[0].instructions | ForEach-Object { $_.opcode }) -join ",") -ne "1,3,1,29,13,12,12") {
                throw "City of Bywater XAP 50 must retain the Ranthog reward, dormant-AP enable, and tree-tile mutation sequence."
            }
            if ($cryptDoorEncounter.Count -ne 1 -or $cryptDoorEncounter[0].promptMessageId -ne 218 -or (@($cryptDoorEncounter[0].texts[0], $cryptDoorEncounter[0].texts[1]) -join "|") -ne "Bang on the door.|Try and force the door." -or $cryptDoorPrompt.Count -ne 1) {
                throw "City of Bywater Complex Encounter 4 must retain prompt 218 and both authored door actions."
            }
            $secretFeatures = @()
            if ($null -ne $cobSecretCell) {
                $secretFeatures = @($cobSecretCell[7] | Where-Object { $_[1] -eq "secret" -and $_[2] -eq "hidden" })
            }
            if ($null -eq $cobSecretCell -or $cobSecretCell[0] -ne "classic.terrain.39" -or (([int]$cobSecretCell[2]) -band 1) -ne 0 -or -not (@($cobSecretCell[4]) -contains "Data DD:5:51") -or $secretFeatures.Count -ne 1) {
                throw "City of Bywater Land 5 cell 61,10 must retain solid terrain 39, hidden-secret state, and Action Point Data DD:5:51."
            }
        }
    } finally {
        $archive.Dispose()
    }
    if ($manifest.campaignId -ne $scenario.campaignId -or $manifest.name -ne $scenario.name -or $manifest.packageHash -ne $scenario.packageHash) {
        throw "$($scenario.file) manifest identity does not match provenance."
    }
    $expectedCompilerRevision = if ([string]::IsNullOrWhiteSpace([string]$scenario.compilerRevision)) { $catalog.compiler.revision } else { $scenario.compilerRevision }
    if ($manifest.compiler.commit -ne $expectedCompilerRevision) {
        throw "$($scenario.file) was not produced by its pinned Providence revision."
    }
}

Write-Host "Verified the 13-scenario bundle, scrolling-text resources, and designated City of Bywater source snapshot."
