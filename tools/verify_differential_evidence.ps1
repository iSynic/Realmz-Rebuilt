param(
    [string]$RemakeRoot = "",
    [string]$CastleRoot = "",
    [string]$ProvidenceRoot = ""
)

$ErrorActionPreference = "Stop"

$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path
$ledgerPath = Join-Path $repoRoot "tests\fixtures\oracle\classic-functional-differential.json"
$referencesPath = Join-Path $repoRoot "docs\references.lock.json"

function Assert-Condition([bool]$Condition, [string]$Message) {
    if (-not $Condition) {
        throw "Differential evidence validation failed: $Message"
    }
}

function Assert-SourceReference([object]$Source, [string]$Label, [string]$Root = "") {
    $path = [string]$Source.path
    $symbol = [string]$Source.symbol
    Assert-Condition (-not [string]::IsNullOrWhiteSpace($path)) "$Label has no path."
    Assert-Condition (-not [string]::IsNullOrWhiteSpace($symbol)) "$Label has no symbol."
    Assert-Condition (-not [System.IO.Path]::IsPathRooted($path)) "$Label contains an absolute path: $path"
    $segments = @($path -split '[\\/]')
    Assert-Condition (-not ($segments -contains '..')) "$Label escapes its repository: $path"

    if ([string]::IsNullOrWhiteSpace($Root)) {
        return
    }

    $fullPath = Join-Path $Root $path
    Assert-Condition (Test-Path -LiteralPath $fullPath -PathType Leaf) "$Label path does not exist: $path"
    Assert-Condition ([bool](Select-String -LiteralPath $fullPath -SimpleMatch $symbol -Quiet)) "$Label symbol was not found: $path :: $symbol"
}

function Assert-ReferenceRoot([string]$Root, [string]$ExpectedCommit, [string]$Label) {
    if ([string]::IsNullOrWhiteSpace($Root)) {
        Write-Host "Differential evidence: $Label external symbol validation skipped (no root supplied)."
        return
    }

    Assert-Condition (Test-Path -LiteralPath $Root -PathType Container) "$Label root does not exist: $Root"
    $actualCommit = (& git -C $Root rev-parse HEAD).Trim()
    Assert-Condition ($LASTEXITCODE -eq 0) "$Label root is not a Git worktree: $Root"
    Assert-Condition ($actualCommit -eq $ExpectedCommit) "$Label root is at $actualCommit, expected $ExpectedCommit."
    $trackedStatus = (& git -C $Root status --porcelain --untracked-files=no)
    Assert-Condition ($LASTEXITCODE -eq 0) "$Label worktree status could not be read."
    Assert-Condition ([string]::IsNullOrWhiteSpace(($trackedStatus -join "`n"))) "$Label worktree has tracked changes."
}

Assert-Condition (Test-Path -LiteralPath $ledgerPath -PathType Leaf) "Ledger is missing."
Assert-Condition (Test-Path -LiteralPath $referencesPath -PathType Leaf) "Reference lock is missing."

$ledger = Get-Content -LiteralPath $ledgerPath -Raw | ConvertFrom-Json
$referenceLock = Get-Content -LiteralPath $referencesPath -Raw | ConvertFrom-Json
$lockedById = @{}
foreach ($reference in $referenceLock.references) {
    $lockedById[[string]$reference.id] = [string]$reference.commit
}

Assert-Condition ($ledger.formatVersion -eq 1) "Unsupported ledger formatVersion."
Assert-Condition ($ledger.references.castle -eq $lockedById["realmz-castle-oracle"]) "Castle commit differs from references.lock.json."
Assert-Condition ($ledger.references.remakeFunctional -eq $lockedById["realmz-remake-functional-reference"]) "Functional Remake commit differs from references.lock.json."
Assert-Condition ($ledger.references.remakeVm -eq $lockedById["realmz-remake-vm-reference"]) "VM Remake commit differs from references.lock.json."
Assert-Condition ($ledger.references.providence -eq $lockedById["providence-compiler-base"]) "Providence commit differs from references.lock.json."

Assert-ReferenceRoot $RemakeRoot $ledger.references.remakeFunctional "Remake functional reference"
Assert-ReferenceRoot $CastleRoot $ledger.references.castle "Castle reference"
Assert-ReferenceRoot $ProvidenceRoot $ledger.references.providence "Providence reference"

$allowedEvidence = @("source-control-flow", "castle-runtime")
$allowedDecisions = @("aligned", "compiler-defect", "runtime-defect", "presentation-defect", "intentional-correction", "unresolved")
$allowedAvailability = @("implemented", "disabled")
$caseIds = @{}

foreach ($case in $ledger.cases) {
    $caseId = [string]$case.id
    Assert-Condition ($caseId -match '^[a-z][a-z0-9-]*(\.[a-z0-9-]+)+$') "Invalid case ID: $caseId"
    Assert-Condition (-not $caseIds.ContainsKey($caseId)) "Duplicate case ID: $caseId"
    $caseIds[$caseId] = $true
    Assert-Condition (-not [string]::IsNullOrWhiteSpace([string]$case.domain)) "$caseId has no domain."
    Assert-Condition (-not [string]::IsNullOrWhiteSpace([string]$case.claim)) "$caseId has no behavior claim."
    Assert-Condition ($allowedDecisions -contains [string]$case.decision) "$caseId has an invalid decision."
    Assert-Condition ($allowedAvailability -contains [string]$case.availability) "$caseId has an invalid availability."
    if ($case.decision -eq "unresolved") {
        Assert-Condition ($case.availability -eq "disabled") "$caseId is unresolved but not disabled."
    }
    if ($case.decision -eq "intentional-correction") {
        $decision = $case.fidelityDecision
        Assert-Condition ($null -ne $decision) "$caseId has no fidelityDecision record."
        Assert-Condition ([string]$decision.id -match '^FD-[A-Z0-9]+-[0-9]{3}$') "$caseId has an invalid fidelity decision ID."
        $fixturePath = [string]$decision.fixturePath
        $fixtureHash = [string]$decision.fixtureSha256
        Assert-Condition (-not [System.IO.Path]::IsPathRooted($fixturePath)) "$caseId has an absolute fidelity fixture path."
        Assert-Condition ($fixtureHash -match '^[0-9a-f]{64}$') "$caseId has an invalid fidelity fixture hash."
        $fixtureFullPath = Join-Path $repoRoot $fixturePath
        Assert-Condition (Test-Path -LiteralPath $fixtureFullPath -PathType Leaf) "$caseId fidelity fixture does not exist."
        $actualFixtureHash = (Get-FileHash -LiteralPath $fixtureFullPath -Algorithm SHA256).Hash.ToLowerInvariant()
        Assert-Condition ($actualFixtureHash -eq $fixtureHash) "$caseId fidelity fixture hash is stale."
    }

    Assert-Condition ($case.remake.commit -eq $ledger.references.remakeFunctional) "$caseId has the wrong Remake commit."
    Assert-Condition ($case.castle.commit -eq $ledger.references.castle) "$caseId has the wrong Castle commit."
    Assert-Condition ($case.providence.commit -eq $ledger.references.providence) "$caseId has the wrong Providence commit."
    Assert-Condition ($allowedEvidence -contains [string]$case.castle.evidence) "$caseId has an invalid Castle evidence label."

    foreach ($source in $case.remake.sources) { Assert-SourceReference $source "$caseId Remake source" $RemakeRoot }
    foreach ($source in $case.remake.tests) { Assert-SourceReference $source "$caseId Remake test" $RemakeRoot }
    foreach ($source in $case.castle.controlFlow) { Assert-SourceReference $source "$caseId Castle source" $CastleRoot }
    foreach ($source in $case.providence.sources) { Assert-SourceReference $source "$caseId Providence source" $ProvidenceRoot }

    Assert-SourceReference $case.realmz2.owner "$caseId Realmz 2 owner" $repoRoot
    Assert-Condition (@($case.realmz2.expectedTrace).Count -gt 0) "$caseId has no expected Realmz 2 trace."
    if ($case.decision -ne "unresolved") {
        Assert-Condition (@($case.realmz2.tests).Count -gt 0) "$caseId has no Realmz 2 regression tests."
    }
    foreach ($source in $case.realmz2.tests) { Assert-SourceReference $source "$caseId Realmz 2 test" $repoRoot }
}

Write-Host "Differential evidence validation passed: $($ledger.cases.Count) cases."
