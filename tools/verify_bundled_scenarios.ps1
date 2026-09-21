$ErrorActionPreference = "Stop"
$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path
$campaignRoot = Join-Path $repoRoot "src\storage\packages\bundled_campaigns"
$catalogPath = Join-Path $campaignRoot "castle-bundled-scenarios.provenance.json"
$citySourcePath = Join-Path $campaignRoot "city-of-bywater.source.json"
$applicationRoot = Join-Path $repoRoot "src\storage\packages\application"
$applicationLock = Get-Content -Raw -LiteralPath (Join-Path $applicationRoot "application-library.lock.json") | ConvertFrom-Json
$catalog = Get-Content -Raw -LiteralPath $catalogPath | ConvertFrom-Json
$nativeOwnership = Get-Content -Raw -LiteralPath (Join-Path $PSScriptRoot "fixtures/classic-monster-cicn-ownership.json") | ConvertFrom-Json
$nativeByCampaign = @{}
if ($nativeOwnership.formatVersion -ne 1 -or @($nativeOwnership.entries).Count -ne 13) {
    throw "Native scenario CICN ownership inventory must cover the exact bundled corpus."
}
foreach ($entry in @($nativeOwnership.entries)) {
    if ($nativeByCampaign.ContainsKey([string]$entry.campaignId) -or [string]$entry.scenarioResourceForkSha256 -notmatch '^[0-9a-f]{64}$') {
        throw "Native scenario CICN ownership inventory has a duplicate or unpinned resource fork."
    }
    $nativeByCampaign[[string]$entry.campaignId] = $entry
}

if ($catalog.formatVersion -ne 3 -or $catalog.source.license -ne "CC-BY-NC-SA-4.0" -or $catalog.source.defaultForScenariosWithoutOverride -ne $true) {
    throw "Bundled scenario provenance header is invalid."
}
if ($catalog.compiler.packageSchemaVersion -ne 3 -or $catalog.acceptedApplicationLibrary.packageHash -ne $applicationLock.packageHash -or $catalog.acceptedApplicationLibrary.archiveSha256 -ne $applicationLock.archiveSha256 -or $catalog.acceptedApplicationLibrary.compilerRevision -ne $applicationLock.compilerCommit) {
    throw "Bundled scenario provenance does not name the accepted application library."
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
$applicationAssetIds = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::Ordinal)
$applicationAssetsByResourceKey = @{}
$applicationArchive = [System.IO.Compression.ZipFile]::OpenRead((Join-Path $applicationRoot "realmz-classic-application-library.realmz2"))
try {
    $applicationAssetEntry = $applicationArchive.GetEntry("assets/index.json")
    if ($null -eq $applicationAssetEntry) { throw "The application library has no assets/index.json." }
    $applicationAssetReader = [System.IO.StreamReader]::new($applicationAssetEntry.Open())
    try { $applicationAssetIndex = $applicationAssetReader.ReadToEnd() | ConvertFrom-Json }
    finally { $applicationAssetReader.Dispose() }
    $sharedBattleAtlas = @($applicationAssetIndex.assets | Where-Object { $_.resourceType -ceq "PICT" -and $_.resourceId -eq 302 })
    if ($sharedBattleAtlas.Count -ne 1 -or $sharedBattleAtlas[0].kind -ne "tileset" -or $sharedBattleAtlas[0].width -ne 640 -or $sharedBattleAtlas[0].height -ne 640 -or $sharedBattleAtlas[0].tileWidth -ne 32 -or $sharedBattleAtlas[0].tileHeight -ne 32 -or $sharedBattleAtlas[0].columns -ne 20 -or $sharedBattleAtlas[0].rows -ne 20) {
        throw "The application library must own one complete exact PICT:302 atlas."
    }
    foreach ($asset in @($applicationAssetIndex.assets)) {
        if (-not [string]::IsNullOrWhiteSpace([string]$asset.id)) { [void]$applicationAssetIds.Add([string]$asset.id) }
        if (-not [string]::IsNullOrWhiteSpace([string]$asset.resourceType) -and $null -ne $asset.resourceId) {
            $resourceKey = "$($asset.resourceType.ToLowerInvariant()):$([int]$asset.resourceId)"
            $applicationAssetsByResourceKey[$resourceKey] = $asset
        }
    }
} finally {
    $applicationArchive.Dispose()
}
$scenarioArchiveBytes = [long]0
$sourceArchiveBytes = [long]0
$refreshedScenarioMedia = 0
$addedScenarioMediaDescriptors = 0
$preservedUnrefreshableScenarioMedia = 0
$rewrittenScenarioMediaReferences = 0
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
    if ($scenario.sourceArchive.archiveSha256 -notmatch '^[0-9a-f]{64}$' -or [long]$scenario.sourceArchive.bytes -le 0 -or $scenario.classicScenarioResourcesSha256 -notmatch '^[0-9a-f]{64}$') {
        throw "$($scenario.file) source or resource provenance is incomplete."
    }
    if ($scenario.campaignId -ne "scenario-war-in-the-sword-lands") {
        $migration = $scenario.mediaOwnershipMigration
        if ($null -eq $migration -or $migration.operation -ne "slim-scenarios" -or $migration.compilerRevision -notmatch '^[0-9a-f]{40}$' -or $migration.applicationPackageHash -ne $applicationLock.packageHash -or $migration.applicationMediaCatalogSha256 -ne $applicationLock.catalogs.'media.json'.sha256 -or $migration.sourcePackageHash -notmatch '^[0-9a-f]{64}$' -or $migration.sourceArchiveSha256 -notmatch '^[0-9a-f]{64}$' -or [long]$migration.sourceArchiveBytes -le 0 -or $migration.removedResourceKey -cne "PICT:302" -or $migration.removedMediaDescriptors -ne 1 -or $migration.removedMediaPayloads -ne 1 -or $migration.rewrittenAssetReferences -ne 0) {
            throw "$($scenario.file) has invalid shared-atlas ownership migration provenance."
        }
    }
    $refresh = $scenario.scenarioMediaMigration
    if ($null -eq $refresh -or $refresh.operation -ne "refresh-scenario-media" -or $refresh.compilerRevision -ne $scenario.compilerRevision -or $refresh.sourceCompilerRevision -notmatch '^[0-9a-f]{40}$' -or $refresh.sourcePackageHash -notmatch '^[0-9a-f]{64}$' -or $refresh.sourceArchiveSha256 -notmatch '^[0-9a-f]{64}$' -or [long]$refresh.sourceArchiveBytes -le 0 -or $refresh.applicationPackageHash -ne $applicationLock.packageHash -or $refresh.applicationMediaCatalogSha256 -ne $applicationLock.catalogs.'media.json'.sha256 -or $refresh.classicScenarioResourcesSha256 -ne $scenario.classicScenarioResourcesSha256 -or [int]$refresh.refreshedScenarioMedia -lt 0 -or [int]$refresh.addedScenarioMediaDescriptors -lt 0 -or [int]$refresh.preservedUnrefreshableScenarioMedia -lt 0 -or $refresh.removedMediaDescriptors -ne 0 -or [int]$refresh.removedMediaPayloads -lt 0 -or [int]$refresh.removedMediaPayloads -gt [int]$refresh.refreshedScenarioMedia -or [int]$refresh.rewrittenAssetReferences -lt 0) {
        throw "$($scenario.file) has invalid scenario-media refresh provenance."
    }
    $refreshedScenarioMedia += [int]$refresh.refreshedScenarioMedia
    $addedScenarioMediaDescriptors += [int]$refresh.addedScenarioMediaDescriptors
    $preservedUnrefreshableScenarioMedia += [int]$refresh.preservedUnrefreshableScenarioMedia
    $rewrittenScenarioMediaReferences += [int]$refresh.rewrittenAssetReferences
    $scenarioArchiveBytes += [long]$scenario.bytes
    $sourceArchiveBytes += [long]$scenario.sourceArchive.bytes
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
        foreach ($playerMap in @($world.playerMaps)) {
            if ([string]::IsNullOrWhiteSpace([string]$playerMap.name) -or [string]$playerMap.name -match '^Map \d+$') {
                throw "$($scenario.file) player-map record $($playerMap.classicId) lost its authored STR# Map Names title."
            }
        }
        $assetEntry = $archive.GetEntry("assets/index.json")
        if ($null -eq $assetEntry) { throw "$($scenario.file) has no assets/index.json." }
        $assetReader = [System.IO.StreamReader]::new($assetEntry.Open())
        try { $assetIndex = $assetReader.ReadToEnd() | ConvertFrom-Json }
        finally { $assetReader.Dispose() }
        $assetIds = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::Ordinal)
        $assetPaths = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::Ordinal)
        $landCicnIds = [System.Collections.Generic.HashSet[int]]::new()
        $resourceKeys = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::Ordinal)
        $assetsByResourceKey = @{}
        foreach ($asset in @($assetIndex.assets)) {
            if (-not [string]::IsNullOrWhiteSpace([string]$asset.id)) { [void]$assetIds.Add([string]$asset.id) }
            if (-not [string]::IsNullOrWhiteSpace([string]$asset.path)) { [void]$assetPaths.Add([string]$asset.path) }
            if ($asset.resourceType -eq "cicn" -and $null -ne $asset.resourceId) { [void]$landCicnIds.Add([int]$asset.resourceId) }
            if (-not [string]::IsNullOrWhiteSpace([string]$asset.resourceType) -and $null -ne $asset.resourceId) {
                $resourceKey = "$($asset.resourceType):$([int]$asset.resourceId)"
                [void]$resourceKeys.Add($resourceKey)
                $assetsByResourceKey[$resourceKey] = $asset
            }
        }
        $scenarioEntry = $archive.GetEntry("scenario.json")
        if ($null -eq $scenarioEntry) { throw "$($scenario.file) has no scenario.json." }
        $scenarioReader = [System.IO.StreamReader]::new($scenarioEntry.Open())
        try { $scenarioDocument = $scenarioReader.ReadToEnd() | ConvertFrom-Json }
        finally { $scenarioReader.Dispose() }
        $contentEntry = $archive.GetEntry("content.json")
        if ($null -eq $contentEntry) { throw "$($scenario.file) has no content.json." }
        $contentReader = [System.IO.StreamReader]::new($contentEntry.Open())
        try { $contentDocument = $contentReader.ReadToEnd() | ConvertFrom-Json }
        finally { $contentReader.Dispose() }
        if (-not $nativeByCampaign.ContainsKey([string]$scenario.campaignId)) {
            throw "$($scenario.file) has no pinned native CICN ownership inventory."
        }
        $nativeEntry = $nativeByCampaign[[string]$scenario.campaignId]
        if ($nativeEntry.classicScenarioResourcesSha256 -ne $scenario.classicScenarioResourcesSha256) {
            throw "$($scenario.file) native CICN inventory does not name the accepted source resources."
        }
        $nativeCicnIds = [System.Collections.Generic.HashSet[int]]::new()
        foreach ($nativeId in @($nativeEntry.nativeScenarioCicnIds)) {
            if ([int]$nativeId -lt -32768 -or [int]$nativeId -gt 32767 -or -not $nativeCicnIds.Add([int]$nativeId)) {
                throw "$($scenario.file) native CICN inventory has a duplicate or invalid resource ID."
            }
        }
        foreach ($asset in @($assetIndex.assets | Where-Object { $_.resourceType -ceq "cicn" })) {
            if (-not $nativeCicnIds.Contains([int]$asset.resourceId)) {
                throw "$($scenario.file) scenario CICN $($asset.resourceId) has no pinned native owner."
            }
        }

        # Every emitted monster icon uses Castle's paired-facing identity: the
        # right-facing CICN is base + 308. Resolve scenario-owned media first,
        # then the pinned application inventory, and reject an incomplete pair
        # before a package can enter the bundled corpus.
        foreach ($monster in @($contentDocument.monsters)) {
            if ($null -eq $monster.iconId -or [int]$monster.iconId -le 0) { continue }
            $baseId = [int]$monster.iconId
            $rightId = $baseId + 308
            foreach ($resourceId in @($baseId, $rightId)) {
                $nativeScenarioOwner = $nativeCicnIds.Contains($resourceId)
                $compiledScenarioOwner = $assetsByResourceKey.ContainsKey("cicn:$resourceId")
                if ($nativeScenarioOwner -ne $compiledScenarioOwner) {
                    throw "$($scenario.file) monster $($monster.id) CICN $resourceId resolves from the wrong owner."
                }
            }
            $baseKey = "cicn:$baseId"
            $rightKey = "cicn:$rightId"
            $baseAsset = if ($assetsByResourceKey.ContainsKey($baseKey)) { $assetsByResourceKey[$baseKey] } else { $applicationAssetsByResourceKey[$baseKey] }
            $rightAsset = if ($assetsByResourceKey.ContainsKey($rightKey)) { $assetsByResourceKey[$rightKey] } else { $applicationAssetsByResourceKey[$rightKey] }
            if ($null -eq $baseAsset -or $null -eq $rightAsset) {
                throw "$($scenario.file) monster $($monster.id) is missing its effective CICN pair $baseId/$rightId."
            }
            foreach ($pairedAsset in @($baseAsset, $rightAsset)) {
                if ([string]$pairedAsset.resourceType -cne "cicn" -or [string]$pairedAsset.sha256 -notmatch '^[0-9a-f]{64}$') {
                    throw "$($scenario.file) monster CICN $($pairedAsset.resourceId) has invalid native inventory metadata."
                }
            }
        }
        if ($scenario.campaignId -eq "scenario-half-truth") {
            $battle103 = @($contentDocument.battles | Where-Object { [int]$_.classicId -eq 103 })
            if ($battle103.Count -ne 1 -or @($battle103[0].monsterSlots).Count -ne 6 -or @($battle103[0].monsterSlots | Where-Object { $_.monsterId -notin @("classic.monster.104", "classic.monster.105") }).Count -ne 0) {
                throw "$($scenario.file) Battle 103 no longer uses its six Runic Heavy Horse/Slaine slots."
            }
            $battle103Monsters = @($contentDocument.monsters | Where-Object { $_.id -in @("classic.monster.104", "classic.monster.105") })
            if ($battle103Monsters.Count -ne 2 -or @($battle103Monsters | Where-Object { [int]$_.iconId -ne 442 }).Count -ne 0) {
                throw "$($scenario.file) Battle 103 monster definitions no longer share CICN 442."
            }
            $battleBase = $assetsByResourceKey["cicn:442"]
            $battleRight = $assetsByResourceKey["cicn:750"]
            if ($null -eq $battleBase -or $battleBase.id -ne "scenario-cicn-442" -or $battleBase.sha256 -cne "d94bc5719e06d3440540e0eb32bb83733e3b0ae6933a3b1867b293e40c74e3d8") {
                throw "$($scenario.file) Battle 103 CICN 442 is not the pinned scenario-owned blue rider."
            }
            if ($null -eq $battleRight -or $battleRight.id -ne "realmz-monster-icon-750" -or $battleRight.sha256 -cne "e30f83389294988df0347da79c9c66b9fe1953b02947cdfd3b777936345e51c4") {
                throw "$($scenario.file) Battle 103 CICN 750 is not the pinned scenario-owned blue rider."
            }
        }
        if (@($assetIndex.assets | Where-Object { $_.kind -eq "battle-tileset" -or $_.id -eq "classic-battle-tiles-302" -or ($_.resourceType -ceq "PICT" -and $_.resourceId -eq 302) }).Count -ne 0) {
            throw "$($scenario.file) duplicates the application-owned PICT:302 resource."
        }
        if (@($contentDocument.battles).Count -gt 0 -and -not (@($manifest.capabilities) -contains "realmz.presentation.battle-atlas-v1")) {
            throw "$($scenario.file) retains battles without the shared-atlas capability."
        }
        if (@($contentDocument.items).Count -ne [int]$scenario.retainedScenarioContent.items -or @($contentDocument.spells).Count -ne [int]$scenario.retainedScenarioContent.spells -or @($contentDocument.races).Count -ne [int]$scenario.retainedScenarioContent.races -or @($contentDocument.castes).Count -ne [int]$scenario.retainedScenarioContent.castes) {
            throw "$($scenario.file) definition inventory does not match its scenario-ownership lock."
        }
        if (@($assetIndex.assets).Count -ne [int]$scenario.retainedScenarioContent.mediaDescriptors -or $assetPaths.Count -ne [int]$scenario.retainedScenarioContent.mediaPayloads) {
            throw "$($scenario.file) media inventory does not match its scenario-ownership lock."
        }
        if (@($contentDocument.races).Count -ne 0 -or ($scenario.campaignId -ne "scenario-city-of-bywater" -and @($contentDocument.castes).Count -ne 0)) {
            throw "$($scenario.file) duplicates application-owned Race or Caste definitions."
        }
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
                $textAsset = $assetsByResourceKey["TEXT:$resourceId"]
                $styleAsset = $assetsByResourceKey["styl:$resourceId"]
                $textEntry = $archive.GetEntry([string]$textAsset.path)
                $styleEntry = $archive.GetEntry([string]$styleAsset.path)
                if ($null -eq $textEntry -or $null -eq $styleEntry) {
                    throw "$($scenario.file) scrolling-text resource $resourceId has a missing payload."
                }
                $textReader = [System.IO.StreamReader]::new($textEntry.Open(), [System.Text.UTF8Encoding]::new($false, $true))
                try { $scrollingText = $textReader.ReadToEnd() }
                finally { $textReader.Dispose() }
                $styleStream = $styleEntry.Open()
                $styleMemory = [System.IO.MemoryStream]::new()
                try {
                    $styleStream.CopyTo($styleMemory)
                    $styleBytes = $styleMemory.ToArray()
                } finally {
                    $styleStream.Dispose()
                    $styleMemory.Dispose()
                }
                if ($styleBytes.Length -lt 2) {
                    throw "$($scenario.file) scrolling-text styl $resourceId is truncated."
                }
                $styleCount = ([int]$styleBytes[0] -shl 8) -bor [int]$styleBytes[1]
                if ($styleCount -eq 0 -or $styleBytes.Length -lt 2 + ($styleCount * 20)) {
                    throw "$($scenario.file) scrolling-text styl $resourceId has an invalid 20-byte run table."
                }
                $styleStarts = @()
                for ($styleIndex = 0; $styleIndex -lt $styleCount; $styleIndex += 1) {
                    $styleOffset = 2 + ($styleIndex * 20)
                    $styleStart = ([int64]$styleBytes[$styleOffset] -shl 24) -bor ([int64]$styleBytes[$styleOffset + 1] -shl 16) -bor ([int64]$styleBytes[$styleOffset + 2] -shl 8) -bor [int64]$styleBytes[$styleOffset + 3]
                    if ($styleStart -lt 0 -or $styleStart -gt $scrollingText.Length) {
                        throw "$($scenario.file) scrolling-text styl $resourceId has run $styleIndex outside its offset-preserving TEXT payload."
                    }
                    $styleStarts += $styleStart
                }
                if ($scenario.campaignId -eq "scenario-city-of-bywater" -and $resourceId -eq -200) {
                    if (-not $scrollingText.StartsWith("`n`n`n`n<<< Click & Drag") -or $styleStarts.Count -lt 2 -or $styleStarts[1] -ne 89) {
                        throw "City of Bywater TEXT/styl -200 must preserve its four authored leading returns and raw style offset 89."
                    }
                }
            }
        }
        foreach ($map in @($world.maps | Where-Object { $_.levelType -eq "land" })) {
            foreach ($cell in $map.cells) {
                $overlayId = [string]$cell[10]
                if (-not [string]::IsNullOrWhiteSpace($overlayId) -and ((-not $assetIds.Contains($overlayId) -and -not $applicationAssetIds.Contains($overlayId)) -or [int]$cell[8] -gt 200)) {
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
            $ranthogTrigger = @($world.triggers | Where-Object { $_.id -eq "Data DD:0:39" })
            $ranthogReward = @($scenarioDocument.programs | Where-Object { $_.id -eq "xap:50" })
            $cryptDoorEncounter = @($contentDocument.complexEncounters | Where-Object { $_.id -eq 4 })
            $cryptDoorPrompt = @($contentDocument.messages | Where-Object { $_.id -eq 218 })
            $cobLandFive = @($world.maps | Where-Object { $_.id -eq "land:5" })
            $cobSecretEntranceMap = @($world.playerMaps | Where-Object { $_.classicId -eq 1 -and $_.name -eq "Secret Castle Entrance" })
            $cobLedgerMap = @($world.playerMaps | Where-Object { $_.classicId -eq 11 -and $_.name -eq "Ledger" })
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
            if ($cobSecretEntranceMap.Count -ne 1 -or $cobLedgerMap.Count -ne 1) {
                throw "City of Bywater must retain the authored names for player-map records 1 and 11."
            }
            $secretFeatures = @()
            if ($null -ne $cobSecretCell) {
                $secretFeatures = @($cobSecretCell[7] | Where-Object { $_[1] -eq "secret" -and $_[2] -eq "hidden" })
            }
            if ($null -eq $cobSecretCell -or $cobSecretCell[0] -ne "classic.terrain.39" -or (([int]$cobSecretCell[2]) -band 1) -ne 0 -or -not (@($cobSecretCell[4]) -contains "Data DD:5:51") -or $secretFeatures.Count -ne 1) {
                throw "City of Bywater Land 5 cell 61,10 must retain solid terrain 39, hidden-secret state, and Action Point Data DD:5:51."
            }
        }
        if ($scenario.campaignId -eq "scenario-prelude-to-pestilence") {
            $correctionPath = Join-Path $campaignRoot "prelude-to-pestilence.corrections.json"
            if (-not (Test-Path -LiteralPath $correctionPath)) {
                throw "$($scenario.file) is missing its source-backed correction catalog."
            }
            $correction = Get-Content -Raw -LiteralPath $correctionPath | ConvertFrom-Json
            $expectedCorrection = @($correction.corrections | Where-Object { $_.id -ceq "prelude-river-riter-unpaid-branch" })
            $xap97 = @($scenarioDocument.programs | Where-Object { $_.id -ceq "xap:97" })
            if ($scenario.correctionsCatalog -cne "prelude-to-pestilence.corrections.json" -or $correction.formatVersion -ne 1 -or $correction.campaignId -cne $scenario.campaignId -or $correction.sourceRevision -cne "491816ad60037394f92c428e99c004494d3c28b3" -or $correction.sourceFiles[0].file -cne "Data ED3" -or $correction.sourceFiles[0].sha256 -cne "d519b69ee4dee10b4a44f14a25e57076cc1c7d7e5f172de76c9575a320ca7892" -or $expectedCorrection.Count -ne 1 -or $xap97.Count -ne 1 -or $xap97[0].ownerId -cne "Data ED3:macro:97" -or @($xap97[0].instructions).Count -ne 2 -or [int]$xap97[0].instructions[0].opcode -ne 1 -or [int]$xap97[0].instructions[0].id -ne -248 -or [int]$xap97[0].instructions[1].opcode -ne 24) {
                throw "$($scenario.file) does not retain the source-backed XAP 97 payment-refusal correction."
            }
            if ($correction.packageAfter.packageHash -cne $scenario.packageHash -or $correction.packageAfter.archiveSha256 -cne $scenario.archiveSha256 -or [long]$correction.packageAfter.bytes -ne [long]$scenario.bytes) {
                throw "$($scenario.file) correction catalog does not match the current package identity."
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

if ($refreshedScenarioMedia -ne 515 -or $addedScenarioMediaDescriptors -ne 515 -or $preservedUnrefreshableScenarioMedia -ne 1 -or $rewrittenScenarioMediaReferences -ne 2) {
    throw "Bundled scenario media refresh totals do not match the pinned corpus migration."
}

$applicationArchiveBytes = [long](Get-Item -LiteralPath (Join-Path $applicationRoot "realmz-classic-application-library.realmz2")).Length
if ($scenarioArchiveBytes -ge $sourceArchiveBytes -or ($scenarioArchiveBytes + $applicationArchiveBytes) -ge $sourceArchiveBytes) {
    throw "The separated application-plus-scenario library did not reduce the previous bundled archive footprint."
}

Write-Host "Verified the lean 13-scenario bundle, 515 restored scenario CICN descriptors, application ownership, authored player-map names, scrolling-text resources, and designated City of Bywater source snapshot."
