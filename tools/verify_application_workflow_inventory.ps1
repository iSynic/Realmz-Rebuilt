param(
    [switch]$Check,
    [switch]$Write,
    [string]$CastleRoot = "",
    [string]$RemakeRoot = "",
    [string]$ProvidenceRoot = ""
)

$ErrorActionPreference = "Stop"

$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path
$inventoryPath = Join-Path $repoRoot "tests\fixtures\oracle\classic-application-workflow-inventory.json"
$ledgerPath = Join-Path $repoRoot "tests\fixtures\oracle\classic-functional-differential.json"
$referencesPath = Join-Path $repoRoot "docs\references.lock.json"
$reportPath = Join-Path $repoRoot "docs\classic-application-workflow-status.md"

if ($Check -and $Write) {
    throw "Choose either -Check or -Write."
}
if (-not $Check -and -not $Write) {
    $Check = $true
}

function Assert-Condition([bool]$Condition, [string]$Message) {
    if (-not $Condition) {
        throw "Application workflow inventory validation failed: $Message"
    }
}

function Get-Property([object]$Value, [string]$Name) {
    if ($null -eq $Value) { return $null }
    return $Value.PSObject.Properties[$Name]
}

function Assert-RelativePath([string]$Path, [string]$Label) {
    Assert-Condition (-not [string]::IsNullOrWhiteSpace($Path)) "$Label has no path."
    Assert-Condition (-not [System.IO.Path]::IsPathRooted($Path)) "$Label contains an absolute path: $Path"
    Assert-Condition (-not (@($Path -split '[\\/]') -contains '..')) "$Label escapes its repository: $Path"
}

function Assert-SourceReference([object]$Source, [string]$Label, [string]$Root = "") {
    Assert-Condition ($null -ne $Source) "$Label is missing."
    $path = [string]$Source.path
    $symbol = [string]$Source.symbol
    Assert-RelativePath $path $Label
    Assert-Condition (-not [string]::IsNullOrWhiteSpace($symbol)) "$Label has no symbol."
    if ([string]::IsNullOrWhiteSpace($Root)) { return }
    $fullPath = Join-Path $Root $path
    Assert-Condition (Test-Path -LiteralPath $fullPath -PathType Leaf) "$Label path does not exist: $path"
    Assert-Condition ([bool](Select-String -LiteralPath $fullPath -SimpleMatch $symbol -Quiet)) "$Label symbol was not found: $path :: $symbol"
}

function Assert-ReferenceRoot([string]$Root, [string]$ExpectedCommit, [string]$Label) {
    if ([string]::IsNullOrWhiteSpace($Root)) {
        Write-Host "Application workflow inventory: $Label external symbol validation skipped (no root supplied)."
        return
    }
    Assert-Condition (Test-Path -LiteralPath $Root -PathType Container) "$Label root does not exist: $Root"
    $actualCommit = (& git -C $Root rev-parse HEAD).Trim()
    Assert-Condition ($LASTEXITCODE -eq 0) "$Label root is not a Git worktree: $Root"
    Assert-Condition ($actualCommit -eq $ExpectedCommit) "$Label root is at $actualCommit, expected $ExpectedCommit."
    $status = (& git -C $Root status --porcelain --untracked-files=no)
    Assert-Condition ($LASTEXITCODE -eq 0) "$Label worktree status could not be read."
    Assert-Condition ([string]::IsNullOrWhiteSpace(($status -join "`n"))) "$Label worktree has tracked changes."
}

function Get-DerivedState([object]$Workflow) {
    $requiredContentMissing = $Workflow.providence.status -eq "missing"
    $simulationMissing = $Workflow.simulation.status -eq "absent"
    $presentationMissing = $Workflow.presentation.status -eq "absent"
    if ($requiredContentMissing -or $simulationMissing -or $presentationMissing) {
        return "missing"
    }

    $variantIncomplete = @($Workflow.variants | Where-Object { $_.status -in @("missing", "unresolved") }).Count -gt 0
    $axisIncomplete = $Workflow.providence.status -eq "partial" -or
        $Workflow.simulation.status -eq "partial" -or
        $Workflow.persistence.status -in @("absent", "partial") -or
        $Workflow.presentation.status -eq "fixture-shell" -or
        $Workflow.castle.oracle -eq "required"
    $hasBlocker = @($Workflow.gaps | Where-Object { $_.severity -eq "blocker" }).Count -gt 0
    if ($variantIncomplete -or $axisIncomplete -or $hasBlocker) {
        return "partial"
    }

    $functional = $Workflow.providence.status -in @("not-required", "complete") -and
        $Workflow.simulation.status -in @("not-applicable", "complete") -and
        $Workflow.persistence.status -in @("not-applicable", "verified") -and
        $Workflow.presentation.status -in @("functional", "accepted")
    if (-not $functional) { return "partial" }

    $ordinaryEvidence = @($Workflow.liveEvidence | Where-Object { $_ -in @("aogm-ordinary", "other-ordinary", "cross-platform") }).Count -gt 0
    if ($Workflow.presentation.status -eq "accepted" -and $ordinaryEvidence) {
        return "certified"
    }
    return "functional"
}

function Get-EnumNames([string]$Path, [string]$EnumName) {
    $text = Get-Content -LiteralPath $Path -Raw
    $match = [regex]::Match($text, "enum\s+$EnumName\s*\{(?<body>[\s\S]*?)\}")
    Assert-Condition $match.Success "Could not find enum $EnumName in $Path."
    return @($match.Groups["body"].Value -split ',' | ForEach-Object {
        ($_ -replace '#.*$', '').Trim()
    } | Where-Object { $_ -match '^[A-Z][A-Z0-9_]*$' })
}

function Get-InteractionKinds([string]$Path) {
    $text = Get-Content -LiteralPath $Path -Raw
    return @([regex]::Matches($text, '(?m)^const\s+([A-Z][A-Z0-9_]+):\s*StringName\s*=') | ForEach-Object { $_.Groups[1].Value })
}

function Get-UiRoutes([string]$Path) {
    $text = Get-Content -LiteralPath $Path -Raw
    $match = [regex]::Match($text, 'const\s+ROUTES:[\s\S]*?\n\]')
    Assert-Condition $match.Success "Could not find ROUTES in $Path."
    return @([regex]::Matches($match.Value, '"id":\s*&"([a-z-]+)"') | ForEach-Object { $_.Groups[1].Value } | Sort-Object -Unique)
}

function Add-CountTable([System.Text.StringBuilder]$Builder, [object[]]$Workflows, [string]$Axis, [string[]]$Values) {
    [void]$Builder.AppendLine("| $Axis | Count |")
    [void]$Builder.AppendLine("| --- | ---: |")
    foreach ($value in $Values) {
        $count = @($Workflows | Where-Object { [string]($_.$Axis.status) -eq $value }).Count
        [void]$Builder.AppendLine("| $value | $count |")
    }
    [void]$Builder.AppendLine()
}

function Get-StateCounts([object[]]$Workflows, [hashtable]$States) {
    $counts = [ordered]@{}
    foreach ($state in @("missing", "partial", "functional", "certified")) {
        $counts[$state] = @($Workflows | Where-Object { $States[[string]$_.id] -eq $state }).Count
    }
    return $counts
}

function New-StatusReport([object]$Inventory) {
    $builder = [System.Text.StringBuilder]::new()
    $workflows = @($Inventory.workflows)
    $classic = @($workflows | Where-Object { $_.scope -eq "classic" })
    $hostWorkflows = @($workflows | Where-Object { $_.scope -eq "host" })
    $states = @{}
    foreach ($workflow in $workflows) { $states[[string]$workflow.id] = Get-DerivedState $workflow }

    [void]$builder.AppendLine("# Classic Application Workflow Status")
    [void]$builder.AppendLine()
    [void]$builder.AppendLine("Generated deterministically from ``tests/fixtures/oracle/classic-application-workflow-inventory.json``. Castle application completeness and modern host completeness are deliberately reported as separate denominators.")
    [void]$builder.AppendLine()
    [void]$builder.AppendLine("## Denominators")
    [void]$builder.AppendLine()
    [void]$builder.AppendLine("| Scope | Total | Missing | Partial | Functional | Certified |")
    [void]$builder.AppendLine("| --- | ---: | ---: | ---: | ---: | ---: |")
    foreach ($scope in @("classic", "host")) {
        $rows = @($workflows | Where-Object { $_.scope -eq $scope })
        $counts = @{}
        foreach ($state in @("missing", "partial", "functional", "certified")) {
            $counts[$state] = @($rows | Where-Object { $states[[string]$_.id] -eq $state }).Count
        }
        [void]$builder.AppendLine("| $scope | $($rows.Count) | $($counts.missing) | $($counts.partial) | $($counts.functional) | $($counts.certified) |")
    }
    [void]$builder.AppendLine()
    [void]$builder.AppendLine("Delivery state is derived. Missing means required content, simulation, or presentation is absent. Partial includes partial axes, shell-only presentation, unverified persistence, unresolved variants, oracle-required ambiguity, or blockers. Functional requires complete content/simulation, verified or inapplicable persistence, functional presentation, accounted variants, and no blocker. Certified additionally requires accepted presentation and ordinary-play or cross-platform evidence.")
    [void]$builder.AppendLine()

    $pause = $Inventory.maintenancePause
    if ($null -ne $pause -and $pause.status -eq "active") {
        [void]$builder.AppendLine("## Maintenance pause")
        [void]$builder.AppendLine()
        [void]$builder.AppendLine("Parity work is temporarily paused by **$($pause.id)** from baseline ``$($pause.baselineCommit)``. $($pause.reason)")
        [void]$builder.AppendLine()
        [void]$builder.AppendLine("The workflow denominator, delivery states, and current parity batch remain unchanged. After the maintenance exit gate passes, work resumes at ``$($pause.resumeBatchId)``.")
        [void]$builder.AppendLine()
        [void]$builder.AppendLine("Exit gate:")
        [void]$builder.AppendLine()
        foreach ($gate in @($pause.exitGate)) { [void]$builder.AppendLine("- ``$gate``") }
        [void]$builder.AppendLine()
    }

    $batch = $Inventory.currentBatch
    [void]$builder.AppendLine("## Current parity-convergence batch")
    [void]$builder.AppendLine()
    [void]$builder.AppendLine("**$($batch.name)** (``$($batch.id)``)")
    [void]$builder.AppendLine()
    [void]$builder.AppendLine($batch.selectionRationale)
    [void]$builder.AppendLine()
    [void]$builder.AppendLine("Planning target: **$($Inventory.convergencePolicy.effortTargets.ordinaryPlayAndPresentationPercent)%** ordinary-play acceptance and presentation, **$($Inventory.convergencePolicy.effortTargets.missingAndPartialImplementationPercent)%** missing or partial workflow implementation, and **$($Inventory.convergencePolicy.effortTargets.targetedArchaeologyPercent)%** discrepancy-triggered archaeology. These percentages guide batch selection; they are not inferred from commits or test counts.")
    [void]$builder.AppendLine()
    [void]$builder.AppendLine("| Workflow | Mode | Priority | Expected evidence | Owned gaps |")
    [void]$builder.AppendLine("| --- | --- | --- | --- | --- |")
    foreach ($target in @($batch.targets)) {
        $ownedGaps = @($target.gapIds) -join ", "
        $expectedEvidence = if ([string]::IsNullOrWhiteSpace([string]$target.expectedEvidence)) { "-" } else { [string]$target.expectedEvidence }
        [void]$builder.AppendLine("| ``$($target.workflowId)`` | $($target.mode) | $($target.priority) | $expectedEvidence | $ownedGaps |")
    }
    [void]$builder.AppendLine()
    [void]$builder.AppendLine("### Batch count delta")
    [void]$builder.AppendLine()
    [void]$builder.AppendLine("| Scope | State | Baseline | Current | Delta |")
    [void]$builder.AppendLine("| --- | --- | ---: | ---: | ---: |")
    foreach ($scope in @("classic", "host")) {
        $rows = @($workflows | Where-Object { $_.scope -eq $scope })
        $currentCounts = Get-StateCounts $rows $states
        foreach ($state in @("missing", "partial", "functional", "certified")) {
            $baseline = [int]$batch.baselineCounts.$scope.$state
            $current = [int]$currentCounts[$state]
            $delta = $current - $baseline
            $deltaText = if ($delta -gt 0) { "+$delta" } else { [string]$delta }
            [void]$builder.AppendLine("| $scope | $state | $baseline | $current | $deltaText |")
        }
    }
    [void]$builder.AppendLine()

    [void]$builder.AppendLine("## Classic domain heatmap")
    [void]$builder.AppendLine()
    [void]$builder.AppendLine("| Domain | Total | Missing | Partial | Functional | Certified |")
    [void]$builder.AppendLine("| --- | ---: | ---: | ---: | ---: | ---: |")
    foreach ($domain in @($Inventory.domains | Where-Object { $_.scope -eq "classic" })) {
        $rows = @($classic | Where-Object { $_.domain -eq $domain.id })
        $counts = @{}
        foreach ($state in @("missing", "partial", "functional", "certified")) {
            $counts[$state] = @($rows | Where-Object { $states[[string]$_.id] -eq $state }).Count
        }
        [void]$builder.AppendLine("| $($domain.name) | $($rows.Count) | $($counts.missing) | $($counts.partial) | $($counts.functional) | $($counts.certified) |")
    }
    [void]$builder.AppendLine()

    [void]$builder.AppendLine("## Completion axes")
    [void]$builder.AppendLine()
    [void]$builder.AppendLine("### Classic")
    [void]$builder.AppendLine()
    [void]$builder.AppendLine("| Castle oracle | Count |")
    [void]$builder.AppendLine("| --- | ---: |")
    foreach ($value in @("not-required", "required", "completed")) {
        [void]$builder.AppendLine("| $value | $(@($classic | Where-Object { $_.castle.oracle -eq $value }).Count) |")
    }
    [void]$builder.AppendLine()
    [void]$builder.AppendLine("| Remake | Count |")
    [void]$builder.AppendLine("| --- | ---: |")
    foreach ($value in @("absent", "partial", "implemented", "divergent", "not-applicable")) {
        [void]$builder.AppendLine("| $value | $(@($classic | Where-Object { $_.remake.status -eq $value }).Count) |")
    }
    [void]$builder.AppendLine()
    Add-CountTable $builder $classic "providence" @("not-required", "missing", "partial", "complete")
    Add-CountTable $builder $classic "simulation" @("not-applicable", "absent", "partial", "complete")
    Add-CountTable $builder $classic "persistence" @("not-applicable", "absent", "partial", "verified")
    Add-CountTable $builder $classic "presentation" @("absent", "fixture-shell", "functional", "accepted")
    [void]$builder.AppendLine("### Host")
    [void]$builder.AppendLine()
    Add-CountTable $builder $hostWorkflows "providence" @("not-required", "missing", "partial", "complete")
    Add-CountTable $builder $hostWorkflows "simulation" @("not-applicable", "absent", "partial", "complete")
    Add-CountTable $builder $hostWorkflows "persistence" @("not-applicable", "absent", "partial", "verified")
    Add-CountTable $builder $hostWorkflows "presentation" @("absent", "fixture-shell", "functional", "accepted")
    [void]$builder.AppendLine("### Live evidence labels")
    [void]$builder.AppendLine()
    [void]$builder.AppendLine("| Label | Classic | Host |")
    [void]$builder.AppendLine("| --- | ---: | ---: |")
    foreach ($value in @("synthetic", "route-harness", "aogm-ordinary", "other-ordinary", "cross-platform")) {
        $classicLive = @($classic | Where-Object { @($_.liveEvidence) -contains $value }).Count
        $hostLive = @($hostWorkflows | Where-Object { @($_.liveEvidence) -contains $value }).Count
        [void]$builder.AppendLine("| $value | $classicLive | $hostLive |")
    }
    [void]$builder.AppendLine()

    $allGaps = @()
    foreach ($workflow in $workflows) {
        foreach ($gap in @($workflow.gaps)) {
            $allGaps += [pscustomobject]@{ Workflow = $workflow; Gap = $gap }
        }
    }
    $blockers = @($allGaps | Where-Object { $_.Gap.severity -eq "blocker" })
    $majors = @($allGaps | Where-Object { $_.Gap.severity -eq "major" })
    [void]$builder.AppendLine("## Release blockers and major gaps")
    [void]$builder.AppendLine()
    [void]$builder.AppendLine("Blockers: **$($blockers.Count)**. Major gaps: **$($majors.Count)**.")
    [void]$builder.AppendLine()
    foreach ($entry in @($blockers + $majors | Sort-Object @{Expression={$_.Gap.severity}}, @{Expression={$_.Workflow.id}}, @{Expression={$_.Gap.id}})) {
        [void]$builder.AppendLine("- **$($entry.Gap.severity)** ``$($entry.Workflow.id)`` - $($entry.Gap.summary) Next: $($entry.Gap.nextAction)")
    }
    if (($blockers.Count + $majors.Count) -eq 0) { [void]$builder.AppendLine("- None.") }
    [void]$builder.AppendLine()

    $oracleRequired = @($workflows | Where-Object { $_.castle.oracle -eq "required" })
    [void]$builder.AppendLine("## Oracle-required unknowns")
    [void]$builder.AppendLine()
    foreach ($workflow in $oracleRequired | Sort-Object id) {
        [void]$builder.AppendLine("- ``$($workflow.id)`` - $($workflow.name)")
    }
    if ($oracleRequired.Count -eq 0) { [void]$builder.AppendLine("- None.") }
    [void]$builder.AppendLine()

    [void]$builder.AppendLine("## Prioritized remaining-work queues")
    [void]$builder.AppendLine()
    foreach ($queue in @("aogm", "other-campaign", "parity", "polish")) {
        [void]$builder.AppendLine("### $queue")
        [void]$builder.AppendLine()
        $queueRows = @($allGaps | Where-Object { $_.Gap.queue -eq $queue } | Sort-Object @{Expression={$_.Gap.severity}}, @{Expression={$_.Workflow.id}}, @{Expression={$_.Gap.id}})
        foreach ($entry in $queueRows) {
            [void]$builder.AppendLine("- ``$($entry.Workflow.id)`` - $($entry.Gap.summary)")
        }
        if ($queueRows.Count -eq 0) { [void]$builder.AppendLine("- None.") }
        [void]$builder.AppendLine()
    }

    [void]$builder.AppendLine("## Coverage caveats")
    [void]$builder.AppendLine()
    [void]$builder.AppendLine("- Synthetic evidence proves a controlled fixture, not an ordinary campaign workflow.")
    [void]$builder.AppendLine("- Route-harness evidence proves an automated route and may bypass ordinary navigation or presentation.")
    [void]$builder.AppendLine("- AOGM and other ordinary-play labels certify only the listed workflow variants actually observed.")
    [void]$builder.AppendLine("- Cross-platform certification requires the same Safe package and workflow to pass on every release platform.")
    [void]$builder.AppendLine("- Differential cases provide behavioral depth. This inventory supplies the fixed application denominator.")
    [void]$builder.AppendLine("- Gaps not selected by the current batch remain explicitly deferred; their presence alone does not authorize archaeology.")
    return $builder.ToString().Replace("`r`n", "`n")
}

Assert-Condition (Test-Path -LiteralPath $inventoryPath -PathType Leaf) "Inventory is missing."
Assert-Condition (Test-Path -LiteralPath $ledgerPath -PathType Leaf) "Differential ledger is missing."
Assert-Condition (Test-Path -LiteralPath $referencesPath -PathType Leaf) "Reference lock is missing."

$inventory = Get-Content -LiteralPath $inventoryPath -Raw | ConvertFrom-Json
$ledger = Get-Content -LiteralPath $ledgerPath -Raw | ConvertFrom-Json
$referenceLock = Get-Content -LiteralPath $referencesPath -Raw | ConvertFrom-Json
$lockedById = @{}
foreach ($reference in $referenceLock.references) { $lockedById[[string]$reference.id] = [string]$reference.commit }

Assert-Condition ($inventory.formatVersion -eq 2) "Unsupported formatVersion."
Assert-Condition ($inventory.references.castle -eq $lockedById["realmz-castle-oracle"]) "Castle commit differs from references.lock.json."
Assert-Condition ($inventory.references.remakeFunctional -eq $lockedById["realmz-remake-functional-reference"]) "Remake commit differs from references.lock.json."
Assert-Condition ($inventory.references.remakeVm -eq $lockedById["realmz-remake-vm-reference"]) "Remake VM commit differs from references.lock.json."
Assert-Condition ($inventory.references.providence -eq $lockedById["providence-compiler-base"]) "Providence commit differs from references.lock.json."
Assert-Condition ($inventory.references.realmz2 -eq "cff7174399212c1256c52fc6b10d4a766af4174e") "Realmz 2.0 baseline differs from the approved audit base."
$pause = $inventory.maintenancePause
if ($null -ne $pause) {
    Assert-Condition ([string]$pause.id -in @("rebuilt-architecture-hardening", "rebuilt-hotspot-test-performance")) "Maintenance pause has an unexpected ID."
    Assert-Condition ([string]$pause.status -in @("active", "complete")) "Maintenance pause has an invalid status."
    Assert-Condition ([string]$pause.baselineCommit -match '^[0-9a-f]{40}$') "Maintenance pause has no full baseline commit."
    Assert-Condition ([string]$pause.resumeBatchId -eq [string]$inventory.currentBatch.id) "Maintenance pause does not preserve the scheduled parity batch."
    Assert-Condition (-not [string]::IsNullOrWhiteSpace([string]$pause.reason)) "Maintenance pause has no reason."
    $maintenanceExitGate = @($pause.exitGate | ForEach-Object { [string]$_ })
    Assert-Condition ($maintenanceExitGate.Count -eq 6) "Maintenance pause must declare the six approved exit-gate records."
    Assert-Condition (($maintenanceExitGate | Sort-Object -Unique).Count -eq $maintenanceExitGate.Count) "Maintenance pause repeats an exit-gate record."
}

Assert-ReferenceRoot $CastleRoot $inventory.references.castle "Castle reference"
Assert-ReferenceRoot $RemakeRoot $inventory.references.remakeFunctional "Remake functional reference"
Assert-ReferenceRoot $ProvidenceRoot $inventory.references.providence "Providence reference"

$allowedScopes = @("classic", "host")
$allowedRemake = @("absent", "partial", "implemented", "divergent", "not-applicable")
$allowedProvidence = @("not-required", "missing", "partial", "complete")
$allowedSimulation = @("not-applicable", "absent", "partial", "complete")
$allowedPersistence = @("not-applicable", "absent", "partial", "verified")
$allowedPresentation = @("absent", "fixture-shell", "functional", "accepted")
$allowedOracle = @("not-required", "required", "completed")
$allowedVariant = @("implemented", "missing", "unresolved", "not-applicable")
$allowedLive = @("synthetic", "route-harness", "aogm-ordinary", "other-ordinary", "cross-platform")
$allowedReachability = @("known-reachable", "observed", "not-observed", "unknown")
$allowedGapCategory = @("source", "compiler", "simulation", "persistence", "presentation", "test", "live-proof")
$allowedSeverity = @("blocker", "major", "minor")
$allowedQueue = @("aogm", "other-campaign", "parity", "polish")
$allowedIntentClassification = @("implemented", "presentation-owned", "intentionally-rejected", "redundant-dead", "missing")
$allowedBatchModes = @("certification", "implementation", "archaeology")
$requiredPriorityOrder = @("aogm-certification", "classic-missing", "aogm-major-partial", "war-prerequisite", "broader-parity", "rare-or-unreachable")
$allowedArchaeologyTriggers = @("observed-discrepancy", "reachable-blocker", "high-risk-boundary", "providence-data-loss", "source-ambiguity-for-target-campaign")

$scopeIds = @{}
foreach ($scope in $inventory.scopes) {
    Assert-Condition ($allowedScopes -contains [string]$scope.id) "Invalid scope ID: $($scope.id)"
    Assert-Condition (-not $scopeIds.ContainsKey([string]$scope.id)) "Duplicate scope ID: $($scope.id)"
    $scopeIds[[string]$scope.id] = $true
}
Assert-Condition ($scopeIds.Count -eq 2) "Inventory must declare exactly Classic and host scopes."

$domainIds = @{}
foreach ($domain in $inventory.domains) {
    $id = [string]$domain.id
    Assert-Condition ($id -match '^[a-z][a-z0-9-]*(\.[a-z0-9-]+)+$') "Invalid domain ID: $id"
    Assert-Condition (-not $domainIds.ContainsKey($id)) "Duplicate domain ID: $id"
    Assert-Condition ($scopeIds.ContainsKey([string]$domain.scope)) "$id has invalid scope."
    $domainIds[$id] = $domain
}
foreach ($domain in $inventory.domains) {
    if (-not [string]::IsNullOrWhiteSpace([string]$domain.parent)) {
        Assert-Condition ($domainIds.ContainsKey([string]$domain.parent)) "$($domain.id) has an unknown parent."
        Assert-Condition ([string]$domain.parent -ne [string]$domain.id) "$($domain.id) is its own parent."
    }
}
foreach ($domain in $inventory.domains) {
    $seenParents = @{}
    $cursor = $domain
    while (-not [string]::IsNullOrWhiteSpace([string]$cursor.parent)) {
        Assert-Condition (-not $seenParents.ContainsKey([string]$cursor.id)) "$($domain.id) participates in a domain-parent cycle."
        $seenParents[[string]$cursor.id] = $true
        $cursor = $domainIds[[string]$cursor.parent]
    }
}

$workflowIds = @{}
$differentialToWorkflows = @{}
$gapIds = @{}
foreach ($workflow in $inventory.workflows) {
    $id = [string]$workflow.id
    Assert-Condition ($id -match '^(classic|host)\.[a-z][a-z0-9-]*(\.[a-z0-9-]+)+$') "Invalid workflow ID: $id"
    Assert-Condition (-not $workflowIds.ContainsKey($id)) "Duplicate workflow ID: $id"
    Assert-Condition ($allowedScopes -contains [string]$workflow.scope) "$id has invalid scope."
    Assert-Condition ($domainIds.ContainsKey([string]$workflow.domain)) "$id has unknown domain."
    Assert-Condition ($domainIds[[string]$workflow.domain].scope -eq $workflow.scope) "$id domain belongs to another scope."
    foreach ($field in @("name", "trigger", "interactionSequence", "committedOutcome")) {
        Assert-Condition (-not [string]::IsNullOrWhiteSpace([string]$workflow.$field)) "$id has no $field."
    }
    Assert-Condition (@($workflow.variants).Count -gt 0) "$id has no variants."
    $variantIds = @{}
    foreach ($variant in $workflow.variants) {
        Assert-Condition (-not [string]::IsNullOrWhiteSpace([string]$variant.id)) "$id has a variant without an ID."
        Assert-Condition (-not $variantIds.ContainsKey([string]$variant.id)) "$id has duplicate variant $($variant.id)."
        $variantIds[[string]$variant.id] = $true
        Assert-Condition ($allowedVariant -contains [string]$variant.status) "$id has an invalid variant status."
    }
    Assert-Condition ($allowedOracle -contains [string]$workflow.castle.oracle) "$id has invalid oracle status."
    if ($workflow.scope -eq "classic") {
        Assert-Condition (@($workflow.castle.sources).Count -gt 0) "$id has no Castle source evidence."
    }
    foreach ($source in $workflow.castle.sources) { Assert-SourceReference $source "$id Castle source" $CastleRoot }
    Assert-Condition ($allowedRemake -contains [string]$workflow.remake.status) "$id has invalid Remake status."
    foreach ($source in @($workflow.remake.sources)) { Assert-SourceReference $source "$id Remake source" $RemakeRoot }
    foreach ($source in @($workflow.remake.tests)) { Assert-SourceReference $source "$id Remake test" $RemakeRoot }
    Assert-Condition ($allowedProvidence -contains [string]$workflow.providence.status) "$id has invalid Providence status."
    foreach ($source in @($workflow.providence.sources)) { Assert-SourceReference $source "$id Providence source" $ProvidenceRoot }
    if ($workflow.providence.status -eq "complete") { Assert-Condition (@($workflow.providence.sources).Count -gt 0) "$id marks Providence complete without evidence." }
    Assert-Condition ($allowedSimulation -contains [string]$workflow.simulation.status) "$id has invalid simulation status."
    foreach ($source in @($workflow.simulation.owners)) { Assert-SourceReference $source "$id simulation owner" $repoRoot }
    Assert-Condition ($allowedPersistence -contains [string]$workflow.persistence.status) "$id has invalid persistence status."
    Assert-Condition ($allowedPresentation -contains [string]$workflow.presentation.status) "$id has invalid presentation status."
    foreach ($source in @($workflow.presentation.owners)) { Assert-SourceReference $source "$id presentation owner" $repoRoot }
    foreach ($source in @($workflow.tests)) { Assert-SourceReference $source "$id test" $repoRoot }
    if ($workflow.simulation.status -eq "complete") {
        Assert-Condition (@($workflow.simulation.owners).Count -gt 0) "$id marks simulation complete without an owner."
        Assert-Condition (@($workflow.tests).Count -gt 0) "$id marks simulation complete without a test."
    }
    if ($workflow.persistence.status -eq "verified") { Assert-Condition (@($workflow.tests).Count -gt 0) "$id marks persistence verified without a test." }
    if ($workflow.presentation.status -in @("functional", "accepted")) {
        Assert-Condition (@($workflow.presentation.owners).Count -gt 0) "$id marks presentation functional without an owner."
        Assert-Condition (@($workflow.tests).Count -gt 0) "$id marks presentation functional without a test."
    }
    foreach ($label in @($workflow.liveEvidence)) { Assert-Condition ($allowedLive -contains [string]$label) "$id has invalid live evidence: $label" }
    foreach ($campaign in @("aogm", "war", "classic")) { Assert-Condition ($allowedReachability -contains [string]$workflow.reachability.$campaign) "$id has invalid $campaign reachability." }
    foreach ($gap in @($workflow.gaps)) {
        Assert-Condition ([string]$gap.id -match '^GAP-[A-Z0-9]+-[0-9]{3}$') "$id has an invalid gap ID."
        Assert-Condition (-not $gapIds.ContainsKey([string]$gap.id)) "Duplicate gap ID: $($gap.id)"
        $gapIds[[string]$gap.id] = $true
        Assert-Condition ($allowedGapCategory -contains [string]$gap.category) "$id has an invalid gap category."
        Assert-Condition ($allowedSeverity -contains [string]$gap.severity) "$id has invalid gap severity."
        Assert-Condition ($allowedQueue -contains [string]$gap.queue) "$id has invalid gap queue."
        Assert-Condition (-not [string]::IsNullOrWhiteSpace([string]$gap.evidence)) "$id gap has no evidence."
        Assert-Condition (-not [string]::IsNullOrWhiteSpace([string]$gap.nextAction)) "$id gap has no next action."
    }
    if ((Get-DerivedState $workflow) -eq "certified") {
        Assert-Condition (@($workflow.gaps | Where-Object { $_.severity -eq "blocker" }).Count -eq 0) "$id is certified with a blocker."
    }
    foreach ($caseId in @($workflow.differentialCaseIds)) {
        if (-not $differentialToWorkflows.ContainsKey([string]$caseId)) { $differentialToWorkflows[[string]$caseId] = @() }
        $differentialToWorkflows[[string]$caseId] += $id
    }
    $workflowIds[$id] = $workflow
}

$policy = $inventory.convergencePolicy
Assert-Condition ($null -ne $policy) "Parity convergence policy is missing."
Assert-Condition ([int]$policy.effortTargets.ordinaryPlayAndPresentationPercent -eq 60) "Ordinary-play and presentation effort target must remain 60 percent."
Assert-Condition ([int]$policy.effortTargets.missingAndPartialImplementationPercent -eq 25) "Missing and partial implementation effort target must remain 25 percent."
Assert-Condition ([int]$policy.effortTargets.targetedArchaeologyPercent -eq 15) "Targeted archaeology effort target must remain 15 percent."
Assert-Condition (((@($policy.priorityOrder) | ForEach-Object { [string]$_ }) -join '|') -eq ($requiredPriorityOrder -join '|')) "Parity convergence priority order differs from the approved policy."
$policyTriggers = @($policy.archaeologyTriggers | ForEach-Object { [string]$_ } | Sort-Object -Unique)
Assert-Condition (($policyTriggers -join '|') -eq (($allowedArchaeologyTriggers | Sort-Object) -join '|')) "Parity convergence archaeology triggers differ from the approved policy."

$batch = $inventory.currentBatch
Assert-Condition ($null -ne $batch) "Current parity-convergence batch is missing."
Assert-Condition ([string]$batch.id -match '^[a-z][a-z0-9-]+$') "Current batch has an invalid ID."
Assert-Condition (-not [string]::IsNullOrWhiteSpace([string]$batch.name)) "Current batch has no name."
Assert-Condition ([string]$batch.baselineCommit -match '^[0-9a-f]{40}$') "Current batch has no full baseline commit."
$historyCount = [int]((& git -C $repoRoot rev-list --count HEAD).Trim())
Assert-Condition ($LASTEXITCODE -eq 0) "Repository history could not be inspected."
$isSingleCommitCheckout = $historyCount -eq 1
if ($isSingleCommitCheckout) {
    Write-Host "Application workflow inventory: private batch-baseline ancestry validation skipped in sanitized one-root public history."
} else {
    $null = & git -C $repoRoot cat-file -e "$($batch.baselineCommit)^{commit}" 2>$null
    Assert-Condition ($LASTEXITCODE -eq 0) "Current batch baseline commit does not exist locally."
    $null = & git -C $repoRoot merge-base --is-ancestor $batch.baselineCommit HEAD 2>$null
    Assert-Condition ($LASTEXITCODE -eq 0) "Current batch baseline commit is not an ancestor of HEAD."
}
Assert-Condition (-not [string]::IsNullOrWhiteSpace([string]$batch.selectionRationale)) "Current batch has no selection rationale."
$batchTargets = @($batch.targets)
Assert-Condition ($batchTargets.Count -ge 3 -and $batchTargets.Count -le 5) "Current batch must contain 3 to 5 workflows."
Assert-Condition (@($batchTargets | Where-Object { $_.mode -eq 'certification' }).Count -gt 0) "Current batch must contain at least one ordinary-play certification target."
$batchWorkflowIds = @{}
foreach ($target in $batchTargets) {
    $workflowId = [string]$target.workflowId
    Assert-Condition ($workflowIds.ContainsKey($workflowId)) "Current batch references unknown workflow $workflowId."
    Assert-Condition (-not $batchWorkflowIds.ContainsKey($workflowId)) "Current batch repeats workflow $workflowId."
    $batchWorkflowIds[$workflowId] = $true
    Assert-Condition ($allowedBatchModes -contains [string]$target.mode) "$workflowId has invalid batch mode."
    Assert-Condition ($requiredPriorityOrder -contains [string]$target.priority) "$workflowId has invalid convergence priority."
    $targetTriggers = @($target.archaeologyTriggers | ForEach-Object { [string]$_ } | Sort-Object -Unique)
    foreach ($trigger in $targetTriggers) { Assert-Condition ($allowedArchaeologyTriggers -contains $trigger) "$workflowId has invalid archaeology trigger $trigger." }
    if ($target.mode -eq "archaeology") {
        Assert-Condition ($targetTriggers.Count -gt 0) "$workflowId schedules archaeology without an approved trigger."
    } else {
        Assert-Condition ($targetTriggers.Count -eq 0) "$workflowId declares archaeology triggers outside an archaeology target."
    }
    $workflow = $workflowIds[$workflowId]
    $derivedState = Get-DerivedState $workflow
    if ($target.mode -eq "certification") {
        Assert-Condition ($derivedState -in @("functional", "certified")) "$workflowId is not ready for a certification target."
        Assert-Condition ([string]$target.expectedEvidence -in @("aogm-ordinary", "other-ordinary")) "$workflowId certification target has no ordinary-play evidence goal."
    } else {
        Assert-Condition ([string]::IsNullOrWhiteSpace([string]$target.expectedEvidence)) "$workflowId declares ordinary-play evidence outside a certification target."
    }
    if ($target.mode -eq "implementation") {
        Assert-Condition ($derivedState -in @("missing", "partial")) "$workflowId is already functional and cannot be scheduled as implementation."
    }
    if ($derivedState -in @("functional", "certified") -and $target.mode -eq "archaeology") {
        Assert-Condition ($targetTriggers.Count -gt 0) "$workflowId cannot deepen a functional workflow without an approved archaeology trigger."
    }
    if ($target.priority -eq "aogm-certification") {
        Assert-Condition ($workflow.scope -eq "classic" -and $workflow.reachability.aogm -in @("known-reachable", "observed")) "$workflowId is not an evidenced AOGM certification candidate."
    }
    foreach ($gapId in @($target.gapIds)) {
        Assert-Condition (@($workflow.gaps | ForEach-Object { [string]$_.id }) -contains [string]$gapId) "$workflowId batch target references gap $gapId owned by another workflow."
    }
}
foreach ($scope in @("classic", "host")) {
    $scopeTotal = @($inventory.workflows | Where-Object { $_.scope -eq $scope }).Count
    $baselineTotal = 0
    foreach ($state in @("missing", "partial", "functional", "certified")) {
        $value = [int]$batch.baselineCounts.$scope.$state
        Assert-Condition ($value -ge 0) "Current batch has a negative $scope $state baseline."
        $baselineTotal += $value
    }
    Assert-Condition ($baselineTotal -eq $scopeTotal) "Current batch $scope baseline does not match the fixed denominator."
}

function Assert-WorkflowLinks([object]$Record, [string]$Label) {
    $links = @($Record.workflowIds)
    Assert-Condition ($links.Count -gt 0) "$Label has no workflow mapping."
    foreach ($workflowId in $links) { Assert-Condition ($workflowIds.ContainsKey([string]$workflowId)) "$Label maps unknown workflow $workflowId." }
}

$exclusionIds = @{}
foreach ($exclusion in $inventory.exclusions) {
    $id = [string]$exclusion.id
    Assert-Condition ($id -match '^exclude\.[a-z][a-z0-9-]*(\.[a-z0-9-]+)*$') "Invalid exclusion ID: $id"
    Assert-Condition (-not $exclusionIds.ContainsKey($id)) "Duplicate exclusion ID: $id"
    Assert-SourceReference $exclusion.evidence "$id evidence" $CastleRoot
    $exclusionIds[$id] = $true
}

$entrypointIds = @{}
foreach ($entrypoint in $inventory.castleEntrypoints) {
    $id = [string]$entrypoint.id
    Assert-Condition (-not $entrypointIds.ContainsKey($id)) "Duplicate Castle entrypoint ID: $id"
    Assert-SourceReference $entrypoint.source "$id source" $CastleRoot
    $hasWorkflows = @($entrypoint.workflowIds).Count -gt 0
    $hasExclusion = -not [string]::IsNullOrWhiteSpace([string]$entrypoint.exclusionId)
    Assert-Condition ($hasWorkflows -xor $hasExclusion) "$id must map to workflows or exactly one exclusion."
    if ($hasWorkflows) { Assert-WorkflowLinks $entrypoint $id }
    if ($hasExclusion) { Assert-Condition ($exclusionIds.ContainsKey([string]$entrypoint.exclusionId)) "$id maps unknown exclusion." }
    $entrypointIds[$id] = $true
}
Assert-Condition (@($inventory.castleEntrypoints).Count -gt 0) "No Castle entrypoints were audited."

$expectedIntents = Get-EnumNames (Join-Path $repoRoot "src\core\session\player_intent.gd") "Kind"
$mappedIntents = @($inventory.boundaryCoverage.intents | ForEach-Object { [string]$_.id })
Assert-Condition ((($expectedIntents | Sort-Object) -join '|') -eq (($mappedIntents | Sort-Object) -join '|')) "Intent coverage differs from PlayerIntent.Kind."
foreach ($record in $inventory.boundaryCoverage.intents) {
    Assert-Condition ($allowedIntentClassification -contains [string]$record.classification) "Intent $($record.id) has invalid classification."
    if (@($record.workflowIds).Count -gt 0) { Assert-WorkflowLinks $record "intent $($record.id)" }
    else { Assert-Condition ($exclusionIds.ContainsKey([string]$record.exclusionId)) "Intent $($record.id) has neither workflow nor valid exclusion." }
    Assert-SourceReference $record.evidence "intent $($record.id) evidence" $repoRoot
}

$expectedInteractions = Get-InteractionKinds (Join-Path $repoRoot "src\core\session\interaction_request.gd")
$mappedInteractions = @($inventory.boundaryCoverage.interactions | ForEach-Object { [string]$_.id })
Assert-Condition ((($expectedInteractions | Sort-Object) -join '|') -eq (($mappedInteractions | Sort-Object) -join '|')) "Interaction coverage differs from InteractionRequest constants."
foreach ($record in $inventory.boundaryCoverage.interactions) { Assert-WorkflowLinks $record "interaction $($record.id)"; Assert-SourceReference $record.evidence "interaction $($record.id) evidence" $repoRoot }

$expectedRoutes = Get-UiRoutes (Join-Path $repoRoot "src\presentation\ui_route_catalog.gd")
$mappedRoutes = @($inventory.boundaryCoverage.routes | ForEach-Object { [string]$_.id })
Assert-Condition ((($expectedRoutes | Sort-Object) -join '|') -eq (($mappedRoutes | Sort-Object) -join '|')) "UI route coverage differs from UiRouteCatalog."
foreach ($record in $inventory.boundaryCoverage.routes) { Assert-WorkflowLinks $record "route $($record.id)"; Assert-SourceReference $record.evidence "route $($record.id) evidence" $repoRoot }

$requiredOpcodes = @(1, 2, 3, 4, 5, 6, 10, 11, 26, 27, 29, 30, 31, 32, 36, 48, 49, 56, 62, 65, 107)
$mappedOpcodes = @($inventory.boundaryCoverage.applicationTransitionOpcodes | ForEach-Object { [int]$_.id })
Assert-Condition ((($requiredOpcodes | Sort-Object) -join '|') -eq (($mappedOpcodes | Sort-Object) -join '|')) "Application-transition opcode coverage is incomplete."
foreach ($record in $inventory.boundaryCoverage.applicationTransitionOpcodes) { Assert-WorkflowLinks $record "opcode $($record.id)"; Assert-SourceReference $record.evidence "opcode $($record.id) evidence" $repoRoot }

$ledgerIds = @{}
foreach ($case in $ledger.cases) {
    $caseId = [string]$case.id
    Assert-Condition (-not $ledgerIds.ContainsKey($caseId)) "Duplicate differential case ID: $caseId"
    Assert-Condition (@($case.workflowIds).Count -gt 0) "$caseId has no workflowIds."
    foreach ($workflowId in @($case.workflowIds)) {
        Assert-Condition ($workflowIds.ContainsKey([string]$workflowId)) "$caseId maps unknown workflow $workflowId."
        Assert-Condition (@($workflowIds[[string]$workflowId].differentialCaseIds) -contains $caseId) "$caseId is not linked back from $workflowId."
    }
    $reverse = @($differentialToWorkflows[$caseId] | Sort-Object -Unique)
    $forward = @($case.workflowIds | ForEach-Object { [string]$_ } | Sort-Object -Unique)
    Assert-Condition (($reverse -join '|') -eq ($forward -join '|')) "$caseId workflow links are not exactly bidirectional."
    $ledgerIds[$caseId] = $true
}
foreach ($caseId in $differentialToWorkflows.Keys) { Assert-Condition ($ledgerIds.ContainsKey($caseId)) "Inventory references unknown differential case $caseId." }

$inventoryText = Get-Content -LiteralPath $inventoryPath -Raw
foreach ($text in @($inventoryText, (New-StatusReport $inventory))) {
    Assert-Condition ($text -notmatch '(?i)[A-Z]:\\') "Artifact contains an absolute Windows path."
    Assert-Condition ($text -notmatch '(?i)(\.realmz2|\.r2save|\.png|\.jpg|\.jpeg)') "Artifact contains a package, save, or screenshot path."
}

$report = New-StatusReport $inventory
if ($Write) {
    [System.IO.File]::WriteAllText($reportPath, $report, [System.Text.UTF8Encoding]::new($false))
    Write-Host "Wrote deterministic application workflow report: $reportPath"
} else {
    Assert-Condition (Test-Path -LiteralPath $reportPath -PathType Leaf) "Generated report is missing. Run with -Write."
    $actualReport = (Get-Content -LiteralPath $reportPath -Raw).Replace("`r`n", "`n")
    Assert-Condition ($actualReport -eq $report) "Generated Markdown is stale. Run with -Write."
}

$classicCount = @($inventory.workflows | Where-Object { $_.scope -eq "classic" }).Count
$hostCount = @($inventory.workflows | Where-Object { $_.scope -eq "host" }).Count
$blockerCount = @($inventory.workflows | ForEach-Object { $_.gaps } | Where-Object { $_.severity -eq "blocker" }).Count
Write-Host "Application workflow inventory validation passed: $classicCount Classic workflows, $hostCount host workflows, $blockerCount blockers, $($ledger.cases.Count) differential links."
