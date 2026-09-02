param(
    [string[]]$ReportPath = @(),
    [string[]]$BaselineReportPath = @(),
    [string]$CandidateMetadataPath = "",
    [string]$ApplicationInventoryPath = "",
    [string]$OutputPath = "",
    [switch]$SelfTest
)

$ErrorActionPreference = "Stop"
$repoRoot = Split-Path -Parent $PSScriptRoot
$featureSchemaPath = Join-Path $repoRoot "contracts\realmz2\realmz2-feature-report.schema.json"
$featureSchemaHashPath = Join-Path $repoRoot "contracts\realmz2\realmz2-feature-report.schema.sha256"
$packageSchemaHashPath = Join-Path $repoRoot "contracts\realmz2\realmz2-package.schema.sha256"
$shaPattern = '^[0-9a-f]{64}$'

function Assert-Condition {
    param([bool]$Condition, [string]$Message)
    if (-not $Condition) { throw $Message }
}

function Assert-Hash {
    param($Value, [string]$Context)
    Assert-Condition ($Value -is [string] -and $Value -cmatch $shaPattern) "$Context must be a lowercase SHA-256 value."
}

function Assert-NoPrivateContent {
    param($Value, [string]$Context = "report")
    if ($null -eq $Value) { return }
    if ($Value -is [string]) {
        Assert-Condition ($Value -notmatch '(?i)([a-z]:\\|file://|res://|user://)') "$Context contains a local or runtime path."
        return
    }
    if ($Value -is [System.Collections.IEnumerable] -and $Value -isnot [System.Management.Automation.PSCustomObject]) {
        $index = 0
        foreach ($entry in $Value) {
            Assert-NoPrivateContent $entry "$Context[$index]"
            $index++
        }
        return
    }
    if ($Value -is [System.Management.Automation.PSCustomObject]) {
        $forbiddenKeys = @("name", "description", "text", "coordinate", "coordinates", "localPath", "sourcePath", "recordId", "ownerId")
        foreach ($property in $Value.PSObject.Properties) {
            Assert-Condition ($forbiddenKeys -cnotcontains $property.Name) "$Context contains forbidden scenario-content field '$($property.Name)'."
            Assert-NoPrivateContent $property.Value "$Context.$($property.Name)"
        }
    }
}

function Assert-UniqueHashes {
    param([object[]]$Records, [string]$Field, [string]$Context)
    $seen = @{}
    foreach ($record in @($Records)) {
        $value = $record.$Field
        Assert-Hash $value "$Context.$Field"
        Assert-Condition (-not $seen.ContainsKey($value)) "$Context contains duplicate $Field '$value'."
        $seen[$value] = $true
    }
}

function Sum-Count {
    param([object[]]$Records)
    $sum = 0L
    foreach ($record in @($Records)) {
        Assert-Condition ($record.count -is [int] -or $record.count -is [long]) "Feature report count must be an integer."
        Assert-Condition ([long]$record.count -ge 0) "Feature report count must not be negative."
        $sum += [long]$record.count
    }
    return $sum
}

function Assert-FeatureReport {
    param($Report, [string]$Context)
    $featureSchemaHash = (Get-Content -Raw -LiteralPath $featureSchemaHashPath).Trim().ToLowerInvariant()
    $packageSchemaHash = (Get-Content -Raw -LiteralPath $packageSchemaHashPath).Trim().ToLowerInvariant()
    Assert-Condition ($Report.kind -ceq "realmz2.feature-report") "$Context has an unsupported kind."
    Assert-Condition ($Report.formatVersion -eq 2) "$Context has an unsupported feature-report format version."
    Assert-Condition ($Report.schemaHash -ceq $featureSchemaHash) "$Context does not match the mirrored feature-report schema."
    Assert-Condition ($Report.package.format -ceq "realmz2" -and $Report.package.formatVersion -eq 2 -and $Report.package.schemaVersion -eq 3) "$Context targets an unsupported package contract."
    Assert-Condition ($Report.package.schemaHash -ceq $packageSchemaHash) "$Context does not match the mirrored package schema."
    Assert-Hash $Report.package.packageHash "$Context packageHash"
    Assert-Hash $Report.package.campaignIdentityHash "$Context campaignIdentityHash"
    Assert-NoPrivateContent $Report $Context

    $opcodeIdentities = @($Report.opcodes.identities)
    $opcodeVariants = @($Report.opcodes.variants)
    Assert-Condition ($Report.opcodes.identityCount -eq $opcodeIdentities.Count) "$Context opcode identity count is inconsistent."
    Assert-Condition ($Report.opcodes.variantCount -eq $opcodeVariants.Count) "$Context opcode variant count is inconsistent."
    Assert-Condition ($Report.opcodes.occurrences -eq (Sum-Count $opcodeIdentities)) "$Context opcode occurrence/identity counts disagree."
    Assert-Condition ($Report.opcodes.occurrences -eq (Sum-Count $opcodeVariants)) "$Context opcode occurrence/variant counts disagree."
    $seenOpcodes = @{}
    foreach ($identity in $opcodeIdentities) {
        Assert-Condition ($identity.opcode -is [int] -or $identity.opcode -is [long]) "$Context contains a non-integer opcode."
        Assert-Condition (-not $seenOpcodes.ContainsKey([string]$identity.opcode)) "$Context contains duplicate opcode identity $($identity.opcode)."
        $seenOpcodes[[string]$identity.opcode] = $true
    }
    Assert-UniqueHashes $opcodeVariants "signatureHash" "$Context opcode variants"
    foreach ($variant in $opcodeVariants) { Assert-Hash $variant.parameterHash "$Context opcode parameterHash" }

    $spellSignatures = @($Report.spells.behaviorSignatures)
    Assert-Condition ($Report.spells.definitions -eq ($Report.spells.applicationDefinitions + $Report.spells.scenarioDefinitions)) "$Context spell definition ownership counts disagree."
    Assert-Condition ($Report.spells.behaviorSignatureCount -eq $spellSignatures.Count) "$Context spell signature count is inconsistent."
    Assert-Condition ($Report.spells.definitions -eq (Sum-Count $spellSignatures)) "$Context spell definition/signature counts disagree."
    Assert-UniqueHashes $spellSignatures "signatureHash" "$Context spell signatures"

    foreach ($section in @(
        @($Report.interactions.signatures),
        @($Report.combat.battleShapeSignatures),
        @($Report.combat.monsterBehaviorSignatures),
        @($Report.rewards.signatures),
        @($Report.world.mapSignatures),
        @($Report.shops.signatures)
    )) {
        Assert-UniqueHashes $section "signatureHash" "$Context signature section"
    }
    Assert-UniqueHashes @($Report.combat.macroSignatures) "identityHash" "$Context combat macro signatures"

    $diagnostics = @($Report.compiler.diagnostics)
    $lossDiagnostics = @($Report.compiler.compilerLossDiagnostics)
    Assert-Condition ($Report.compiler.diagnosticCount -eq (Sum-Count $diagnostics)) "$Context compiler diagnostic count is inconsistent."
    Assert-Condition ($Report.compiler.unresolvedCompilerLossCount -eq (Sum-Count $lossDiagnostics)) "$Context compiler-loss count is inconsistent."
}

function Read-FeatureReport {
    param([string]$Path)
    $resolved = (Resolve-Path -LiteralPath $Path).Path
    $report = Get-Content -Raw -LiteralPath $resolved | ConvertFrom-Json
    Assert-FeatureReport $report $resolved
    return [pscustomobject]@{
        Path = $resolved
        Hash = (Get-FileHash -LiteralPath $resolved -Algorithm SHA256).Hash.ToLowerInvariant()
        Report = $report
    }
}

function Read-CandidateMetadata {
    param([string]$Path)
    $metadata = @{}
    if ([string]::IsNullOrWhiteSpace($Path)) { return $metadata }
    $resolved = (Resolve-Path -LiteralPath $Path).Path
    $document = Get-Content -Raw -LiteralPath $resolved | ConvertFrom-Json
    Assert-Condition ($document.formatVersion -eq 1) "$resolved has an unsupported candidate-metadata format version."
    Assert-NoPrivateContent $document $resolved
    foreach ($candidate in @($document.candidates)) {
        Assert-Hash $candidate.campaignIdentityHash "$resolved campaignIdentityHash"
        Assert-Condition ($candidate.playerPriority -is [int] -or $candidate.playerPriority -is [long]) "$resolved playerPriority must be an integer."
        Assert-Condition ([long]$candidate.playerPriority -ge 0) "$resolved playerPriority must not be negative."
        Assert-Condition ($candidate.reliableCompletionRoute -is [bool]) "$resolved reliableCompletionRoute must be boolean."
        Assert-Condition (-not $metadata.ContainsKey($candidate.campaignIdentityHash)) "$resolved contains duplicate campaign metadata."
        $metadata[$candidate.campaignIdentityHash] = $candidate
    }
    return $metadata
}

function Read-ApplicationInventory {
    param([string]$Path)
    if ([string]::IsNullOrWhiteSpace($Path)) { return $null }
    $resolved = (Resolve-Path -LiteralPath $Path).Path
    $inventory = Get-Content -Raw -LiteralPath $resolved | ConvertFrom-Json
    Assert-Condition ($inventory.formatVersion -eq 2) "$resolved has an unsupported gameplay-parity inventory version."
    Assert-Condition ($inventory.featureReportContract.schemaHash -ceq $expectedFeatureSchemaHash) "$resolved does not target the mirrored feature-report schema."
    Assert-Condition ($inventory.spellSummary.totalDefinitions -eq @($inventory.spells).Count) "$resolved has inconsistent spell-definition counts."
    Assert-Condition ($inventory.spellSummary.behaviorSignatures -eq @($inventory.spellSignatures).Count) "$resolved has inconsistent spell-signature counts."
    return $inventory
}

function Get-Sha256Prefix {
    param([string]$Text, [int]$Length)
    $algorithm = [System.Security.Cryptography.SHA256]::Create()
    try {
        $bytes = [System.Text.Encoding]::UTF8.GetBytes($Text)
        return ([System.BitConverter]::ToString($algorithm.ComputeHash($bytes))).Replace("-", "").ToLowerInvariant().Substring(0, $Length)
    } finally {
        $algorithm.Dispose()
    }
}

function Get-ApplicationBehaviorSignatureId {
    param($Behavior)
    $normalized = [ordered]@{
        canRotate = $Behavior.canRotate
        cannot = $Behavior.cannot
        cost = $Behavior.cost
        damage = [ordered]@{
            maximum = $Behavior.damageMax
            minimum = $Behavior.damageMin
            powerMaximum = $Behavior.powerDamageMax
            powerMinimum = $Behavior.powerDamageMin
            type = $Behavior.damageType
        }
        duration = [ordered]@{
            maximum = $Behavior.durationMax
            minimum = $Behavior.durationMin
            powerMaximum = $Behavior.powerDurationMax
            powerMinimum = $Behavior.powerDurationMin
        }
        fixedTargetCount = $Behavior.fixedTargetCount
        inCamp = $Behavior.inCamp
        inCombat = $Behavior.inCombat
        queueIcon = $Behavior.queueIcon
        range = [ordered]@{ maximum = $Behavior.rangeMax; minimum = $Behavior.rangeMin }
        resistanceAdjust = $Behavior.resistanceAdjust
        saveAdjust = $Behavior.saveAdjust
        saveBonus = $Behavior.saveBonus
        size = $Behavior.size
        special = $Behavior.special
        spellClass = $Behavior.spellClass
        targetType = $Behavior.targetType
        toHitBonus = $Behavior.toHitBonus
    }
    return Get-Sha256Prefix ($normalized | ConvertTo-Json -Compress -Depth 8) 16
}

function Get-CapabilityAudit {
    param($Report, $Inventory, [string]$Context)
    if ($null -eq $Inventory) { return $null }

    Assert-Condition ($Report.spells.applicationDefinitions -eq $Inventory.spellSummary.totalDefinitions) "$Context application spell-definition count does not match the pinned runtime inventory."
    $reportedSignatureIds = @(
        $Report.spells.behaviorSignatures |
            Where-Object { @($_.origins) -ccontains "application" } |
            ForEach-Object { Get-ApplicationBehaviorSignatureId $_.behavior } |
            Sort-Object -Unique
    )
    $inventorySignatureIds = @($Inventory.spellSignatures.signatureId | Sort-Object -Unique)
    $missingSignatures = @($inventorySignatureIds | Where-Object { $_ -cnotin $reportedSignatureIds })
    $unexpectedSignatures = @($reportedSignatureIds | Where-Object { $_ -cnotin $inventorySignatureIds })
    Assert-Condition ($missingSignatures.Count -eq 0 -and $unexpectedSignatures.Count -eq 0) "$Context application spell signatures do not match the pinned runtime inventory."

    $opcodeDispositions = @{}
    foreach ($opcode in @($Inventory.opcodes)) { $opcodeDispositions[[string]$opcode.opcode] = [string]$opcode.disposition }
    $nonExecutableOpcodes = @(
        $Report.opcodes.identities |
            Where-Object { $opcodeDispositions[[string]$_.opcode] -cne "executable" } |
            ForEach-Object { [long]$_.opcode } |
            Sort-Object -Unique
    )
    Assert-Condition ($nonExecutableOpcodes.Count -eq 0) "$Context contains opcode identities without executable runtime dispositions."

    return [pscustomobject][ordered]@{
        applicationDefinitions = [long]$Report.spells.applicationDefinitions
        applicationSignatureCount = $reportedSignatureIds.Count
        inventorySignatureCount = $inventorySignatureIds.Count
        missingApplicationSignatures = 0
        unexpectedApplicationSignatures = 0
        opcodeIdentityCount = [long]$Report.opcodes.identityCount
        opcodeVariantCount = [long]$Report.opcodes.variantCount
        nonExecutableOpcodes = @()
    }
}

function Add-Hashes {
    param([System.Collections.Generic.HashSet[string]]$Target, [object[]]$Records, [string]$Field)
    foreach ($record in @($Records)) { [void]$Target.Add([string]$record.$Field) }
}

function Get-FeatureSets {
    param($Report)
    $sets = [ordered]@{}
    foreach ($key in @("opcodeVariants", "spellSignatures", "interactionSignatures", "combatMacros", "battleShapes", "monsterSignatures", "rewardSignatures", "mapSignatures", "shopSignatures")) {
        $sets[$key] = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::Ordinal)
    }
    Add-Hashes $sets.opcodeVariants @($Report.opcodes.variants) "signatureHash"
    Add-Hashes $sets.spellSignatures @($Report.spells.behaviorSignatures) "signatureHash"
    Add-Hashes $sets.interactionSignatures @($Report.interactions.signatures) "signatureHash"
    Add-Hashes $sets.combatMacros @($Report.combat.macroSignatures) "identityHash"
    Add-Hashes $sets.battleShapes @($Report.combat.battleShapeSignatures) "signatureHash"
    Add-Hashes $sets.monsterSignatures @($Report.combat.monsterBehaviorSignatures) "signatureHash"
    Add-Hashes $sets.rewardSignatures @($Report.rewards.signatures) "signatureHash"
    Add-Hashes $sets.mapSignatures @($Report.world.mapSignatures) "signatureHash"
    Add-Hashes $sets.shopSignatures @($Report.shops.signatures) "signatureHash"
    return $sets
}

function Merge-FeatureSets {
    param([object[]]$Reports)
    $merged = Get-FeatureSets ([pscustomobject]@{
        opcodes = @{ variants = @() }; spells = @{ behaviorSignatures = @() }; interactions = @{ signatures = @() }
        combat = @{ macroSignatures = @(); battleShapeSignatures = @(); monsterBehaviorSignatures = @() }
        rewards = @{ signatures = @() }; world = @{ mapSignatures = @() }; shops = @{ signatures = @() }
    })
    foreach ($report in $Reports) {
        $sets = Get-FeatureSets $report
        foreach ($key in $merged.Keys) { $merged[$key].UnionWith($sets[$key]) }
    }
    return $merged
}

function Count-NewFeatures {
    param([System.Collections.Generic.HashSet[string]]$Candidate, [System.Collections.Generic.HashSet[string]]$Baseline)
    $copy = [System.Collections.Generic.HashSet[string]]::new($Candidate, [System.StringComparer]::Ordinal)
    $copy.ExceptWith($Baseline)
    return $copy.Count
}

function Rank-FeatureReports {
    param([object[]]$Candidates, [object[]]$Baselines, [hashtable]$CandidateMetadata = @{}, $ApplicationInventory = $null)
    $baselineSets = Merge-FeatureSets $Baselines
    $weights = [ordered]@{
        opcodeVariants = 10; spellSignatures = 8; interactionSignatures = 7; combatMacros = 8
        battleShapes = 6; monsterSignatures = 6; rewardSignatures = 4; mapSignatures = 3; shopSignatures = 3
    }
    $ranked = foreach ($candidate in $Candidates) {
        $sets = Get-FeatureSets $candidate.Report
        $gain = [ordered]@{}
        $score = 0
        foreach ($key in $weights.Keys) {
            $gain[$key] = Count-NewFeatures $sets[$key] $baselineSets[$key]
            $score += $gain[$key] * $weights[$key]
        }
        $riskGain = $gain.opcodeVariants + $gain.interactionSignatures + $gain.combatMacros + $gain.battleShapes
        $metadata = $CandidateMetadata[[string]$candidate.Report.package.campaignIdentityHash]
        $playerPriority = if ($null -eq $metadata) { 0 } else { [long]$metadata.playerPriority }
        $reliableCompletionRoute = if ($null -eq $metadata) { $false } else { [bool]$metadata.reliableCompletionRoute }
        [pscustomobject][ordered]@{
            campaignIdentityHash = $candidate.Report.package.campaignIdentityHash
            packageHash = $candidate.Report.package.packageHash
            featureReportHash = $candidate.Hash
            coverageScore = $score
            highRiskBoundaryGain = $riskGain
            compilerLossDiagnostics = [long]$candidate.Report.compiler.unresolvedCompilerLossCount
            playerPriority = $playerPriority
            reliableCompletionRoute = $reliableCompletionRoute
            capabilityAudit = Get-CapabilityAudit $candidate.Report $ApplicationInventory $candidate.Path
            newFeatures = [pscustomobject]$gain
        }
    }
    return @($ranked | Sort-Object @{Expression="coverageScore";Descending=$true}, @{Expression="highRiskBoundaryGain";Descending=$true}, @{Expression="compilerLossDiagnostics";Descending=$true}, @{Expression="playerPriority";Descending=$true}, @{Expression="reliableCompletionRoute";Descending=$true}, @{Expression="campaignIdentityHash";Descending=$false})
}

function New-SyntheticReport {
    param([string]$CampaignHash, [string[]]$OpcodeHashes, [string[]]$SpellHashes)
    $featureSchemaHash = (Get-Content -Raw -LiteralPath $featureSchemaHashPath).Trim().ToLowerInvariant()
    $packageSchemaHash = (Get-Content -Raw -LiteralPath $packageSchemaHashPath).Trim().ToLowerInvariant()
    $opcodeVariants = @($OpcodeHashes | ForEach-Object { [pscustomobject]@{ signatureHash=$_; opcode=1; rawOpcodeClass="positive"; gosub=$false; operandShape="positive"; extraCodeShape=@(); parameterHash=("e" * 64); ownerKinds=@("trigger"); count=1 } })
    $behavior = [pscustomobject]@{
        canRotate=$false; cannot=$false; cost=1; damageMax=0; damageMin=0; damageType=0
        durationMax=0; durationMin=0; fixedTargetCount=1; inCamp=$true; inCombat=$true
        powerDamageMax=0; powerDamageMin=0; powerDurationMax=0; powerDurationMin=0
        queueIcon=0; rangeMax=1; rangeMin=0; resistanceAdjust=0; saveAdjust=0; saveBonus=0; size=0
        special=0; spellClass=1; targetType=1; toHitBonus=0
    }
    $spellSignatures = @($SpellHashes | ForEach-Object { [pscustomobject]@{ signatureHash=$_; count=1; origins=@("application"); behavior=$behavior } })
    return [pscustomobject]@{
        kind="realmz2.feature-report"; formatVersion=2; schemaHash=$featureSchemaHash
        package=[pscustomobject]@{ format="realmz2"; formatVersion=2; schemaVersion=3; schemaHash=$packageSchemaHash; packageHash=("f" * 64); campaignIdentityHash=$CampaignHash }
        opcodes=[pscustomobject]@{ occurrences=$opcodeVariants.Count; identityCount=([int]($opcodeVariants.Count -gt 0)); variantCount=$opcodeVariants.Count; identities=@($(if ($opcodeVariants.Count -gt 0) { [pscustomobject]@{opcode=1;count=$opcodeVariants.Count;variantCount=$opcodeVariants.Count} })); variants=$opcodeVariants }
        spells=[pscustomobject]@{ definitions=$spellSignatures.Count; applicationDefinitions=$spellSignatures.Count; scenarioDefinitions=0; behaviorSignatureCount=$spellSignatures.Count; behaviorSignatures=$spellSignatures }
        interactions=[pscustomobject]@{ signatures=@() }; combat=[pscustomobject]@{ macroSignatures=@(); battleShapeSignatures=@(); monsterBehaviorSignatures=@() }
        rewards=[pscustomobject]@{ signatures=@() }; world=[pscustomobject]@{ mapSignatures=@() }; shops=[pscustomobject]@{ signatures=@() }; allies=[pscustomobject]@{}
        compiler=[pscustomobject]@{ projectSchemaVersion=1; diagnosticCount=0; diagnostics=@(); compilerLossDiagnostics=@(); unresolvedCompilerLossCount=0 }
    }
}

if (-not (Test-Path -LiteralPath $featureSchemaPath) -or -not (Test-Path -LiteralPath $featureSchemaHashPath)) {
    throw "The mirrored gameplay feature-report schema is required."
}
$expectedFeatureSchemaHash = (Get-Content -Raw -LiteralPath $featureSchemaHashPath).Trim().ToLowerInvariant()
$actualFeatureSchemaHash = (Get-FileHash -LiteralPath $featureSchemaPath -Algorithm SHA256).Hash.ToLowerInvariant()
Assert-Condition ($actualFeatureSchemaHash -ceq $expectedFeatureSchemaHash) "Gameplay feature-report schema mirror drift: expected $expectedFeatureSchemaHash, found $actualFeatureSchemaHash."

if ($SelfTest) {
    $baseline = New-SyntheticReport ("a" * 64) @(("1" * 64)) @(("2" * 64))
    $low = New-SyntheticReport ("b" * 64) @(("1" * 64)) @(("3" * 64))
    $high = New-SyntheticReport ("c" * 64) @(("4" * 64), ("5" * 64)) @(("6" * 64))
    foreach ($entry in @($baseline, $low, $high)) { Assert-FeatureReport $entry "synthetic feature report" }
    $ranked = Rank-FeatureReports @(
        [pscustomobject]@{ Report=$low; Hash=("7" * 64) },
        [pscustomobject]@{ Report=$high; Hash=("8" * 64) }
    ) @($baseline)
    Assert-Condition ($ranked.Count -eq 2 -and $ranked[0].campaignIdentityHash -ceq ("c" * 64)) "Coverage-gain ranking self-test failed."
    $priorityFirst = Rank-FeatureReports @(
        [pscustomobject]@{ Report=(New-SyntheticReport ("d" * 64) @(("9" * 64)) @()); Hash=("a" * 64) },
        [pscustomobject]@{ Report=(New-SyntheticReport ("e" * 64) @(("9" * 64)) @()); Hash=("b" * 64) }
    ) @() @{
        ("d" * 64) = [pscustomobject]@{ playerPriority=2; reliableCompletionRoute=$false }
        ("e" * 64) = [pscustomobject]@{ playerPriority=1; reliableCompletionRoute=$true }
    }
    Assert-Condition ($priorityFirst[0].campaignIdentityHash -ceq ("d" * 64)) "Player-priority tie-break self-test failed."
    $routeFirst = Rank-FeatureReports @(
        [pscustomobject]@{ Report=(New-SyntheticReport ("d" * 64) @(("9" * 64)) @()); Hash=("a" * 64) },
        [pscustomobject]@{ Report=(New-SyntheticReport ("e" * 64) @(("9" * 64)) @()); Hash=("b" * 64) }
    ) @() @{
        ("d" * 64) = [pscustomobject]@{ playerPriority=1; reliableCompletionRoute=$false }
        ("e" * 64) = [pscustomobject]@{ playerPriority=1; reliableCompletionRoute=$true }
    }
    Assert-Condition ($routeFirst[0].campaignIdentityHash -ceq ("e" * 64)) "Reliable-route tie-break self-test failed."

    $capabilityReport = New-SyntheticReport ("f" * 64) @(("a" * 64)) @(("b" * 64))
    $capabilitySignatureId = Get-ApplicationBehaviorSignatureId $capabilityReport.spells.behaviorSignatures[0].behavior
    $alternateQueueBehavior = $capabilityReport.spells.behaviorSignatures[0].behavior.PSObject.Copy()
    $alternateQueueBehavior.queueIcon = 1
    Assert-Condition ((Get-ApplicationBehaviorSignatureId $alternateQueueBehavior) -cne $capabilitySignatureId) "Queue-icon spell mechanics must affect application capability signatures."
    $capabilityInventory = [pscustomobject]@{
        spellSummary = [pscustomobject]@{ totalDefinitions=1; behaviorSignatures=1 }
        spellSignatures = @([pscustomobject]@{ signatureId=$capabilitySignatureId })
        opcodes = @([pscustomobject]@{ opcode=1; disposition="executable" })
    }
    $capabilityAudit = Get-CapabilityAudit $capabilityReport $capabilityInventory "synthetic capability report"
    Assert-Condition ($capabilityAudit.applicationSignatureCount -eq 1 -and $capabilityAudit.opcodeIdentityCount -eq 1) "Capability-audit self-test failed."

    $capabilityInventory.opcodes[0].disposition = "unsupported-pending"
    $rejectedNonExecutableOpcode = $false
    try {
        [void](Get-CapabilityAudit $capabilityReport $capabilityInventory "synthetic non-executable opcode report")
    } catch {
        $rejectedNonExecutableOpcode = $_.Exception.Message -like "*without executable runtime dispositions*"
    }
    Assert-Condition $rejectedNonExecutableOpcode "Non-executable opcode rejection self-test failed."
    Write-Host "Gameplay feature-report validation and coverage ranking self-test passed."
}

if ($ReportPath.Count -gt 0) {
    $candidates = @($ReportPath | ForEach-Object { Read-FeatureReport $_ })
    $baselines = @($BaselineReportPath | ForEach-Object { (Read-FeatureReport $_).Report })
    $candidateMetadata = Read-CandidateMetadata $CandidateMetadataPath
    $applicationInventory = Read-ApplicationInventory $ApplicationInventoryPath
    $ranking = Rank-FeatureReports $candidates $baselines $candidateMetadata $applicationInventory
    $result = [ordered]@{
        formatVersion = 1
        featureReportSchemaHash = $expectedFeatureSchemaHash
        baselineReportCount = $baselines.Count
        candidateReportCount = $candidates.Count
        ranking = $ranking
    }
    $json = $result | ConvertTo-Json -Depth 12
    if ([string]::IsNullOrWhiteSpace($OutputPath)) {
        $json
    } else {
        $parent = Split-Path -Parent $OutputPath
        if (-not [string]::IsNullOrWhiteSpace($parent)) { [void](New-Item -ItemType Directory -Force -Path $parent) }
        [System.IO.File]::WriteAllText($OutputPath, $json + [Environment]::NewLine, [System.Text.UTF8Encoding]::new($false))
        Write-Host "Gameplay feature ranking written to $OutputPath"
    }
} elseif (-not $SelfTest) {
    throw "Pass at least one -ReportPath or use -SelfTest."
}
