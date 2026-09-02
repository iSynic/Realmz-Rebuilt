param(
    [string[]]$Suite = @(),
    [string[]]$Case = @(),
    [ValidateRange(1, 3600)]
    [int]$TimeoutSeconds = 120,
    [string]$GodotPath = "",
    [string]$CastleRoot = "",
    [string]$RemakeRoot = "",
    [string]$ProvidenceRoot = ""
)

$ErrorActionPreference = "Stop"
$repoRoot = Split-Path -Parent $PSScriptRoot

if ([string]::IsNullOrWhiteSpace($GodotPath)) {
    $candidate = Get-ChildItem "$env:LOCALAPPDATA\Microsoft\WinGet\Packages" -Recurse -Filter "Godot_v4.7.1-stable_win64_console.exe" -ErrorAction SilentlyContinue |
        Select-Object -First 1 -ExpandProperty FullName
    if (-not $candidate) {
        throw "Godot 4.7.1 console executable was not found. Pass -GodotPath explicitly."
    }
    $GodotPath = $candidate
}

$suiteFragments = @($Suite | ForEach-Object { $_.Trim() } | Where-Object { -not [string]::IsNullOrWhiteSpace($_) } | Select-Object -Unique)
$caseFragments = @($Case | ForEach-Object { $_.Trim() } | Where-Object { -not [string]::IsNullOrWhiteSpace($_) } | Select-Object -Unique)
if ($suiteFragments.Count -eq 0 -and $caseFragments.Count -eq 0) {
    throw "At least one non-empty -Suite or -Case fragment is required."
}
if ($suiteFragments.Count -eq 0 -and $caseFragments.Count -gt 0) {
    throw "Named case filters require at least one -Suite fragment."
}

& "$PSScriptRoot\run_tests.ps1" -Suite $suiteFragments -Case $caseFragments -TimeoutSeconds $TimeoutSeconds -GodotPath $GodotPath

& "$PSScriptRoot\ui-assets\verify-classic-application-media.ps1"
if ($LASTEXITCODE -ne 0) { throw "Classic application media verification failed." }

$changedPaths = @(
    git -C $repoRoot status --porcelain=v1 --untracked-files=all |
        ForEach-Object {
            if ($_.Length -lt 4) { return }
            $path = $_.Substring(3)
            if ($path.Contains(" -> ")) { $path = $path.Split(" -> ")[-1] }
            $path.Trim('"') -replace '\\', '/'
        } |
        Where-Object { -not [string]::IsNullOrWhiteSpace($_) } |
        Select-Object -Unique
)

if (@($changedPaths | Where-Object { $_ -eq "src" -or $_.StartsWith("src/") -or $_ -eq "project.godot" }).Count -gt 0) {
    & "$PSScriptRoot\verify_architecture.ps1"
    if ($LASTEXITCODE -ne 0) { throw "Architecture boundary verification failed." }
} else {
    Write-Host "Architecture boundary verification skipped: no product source changed."
}

& "$PSScriptRoot\verify_hotspot_test_budget.ps1"
if ($LASTEXITCODE -ne 0) { throw "Hotspot and test-budget verification failed." }

$referenceArguments = @{}
if (-not [string]::IsNullOrWhiteSpace($CastleRoot)) { $referenceArguments.CastleRoot = $CastleRoot }
if (-not [string]::IsNullOrWhiteSpace($RemakeRoot)) { $referenceArguments.RemakeRoot = $RemakeRoot }
if (-not [string]::IsNullOrWhiteSpace($ProvidenceRoot)) { $referenceArguments.ProvidenceRoot = $ProvidenceRoot }

& "$PSScriptRoot\verify_differential_evidence.ps1" @referenceArguments
if ($LASTEXITCODE -ne 0) { throw "Differential evidence verification failed." }

& "$PSScriptRoot\verify_application_workflow_inventory.ps1" -Check @referenceArguments
if ($LASTEXITCODE -ne 0) { throw "Application workflow inventory verification failed." }

& "$PSScriptRoot\verify_gameplay_parity_inventory.ps1" -GodotPath $GodotPath
if ($LASTEXITCODE -ne 0) { throw "Gameplay parity inventory verification failed." }

& "$PSScriptRoot\analyze_gameplay_feature_reports.ps1" -SelfTest

git -C $repoRoot diff --check
if ($LASTEXITCODE -ne 0) { throw "git diff --check failed." }

$addedTrackedLines = @(git -C $repoRoot diff --no-ext-diff --unified=0 HEAD -- . | Where-Object { $_ -match '^\+(?!\+\+)' } | ForEach-Object { $_.Substring(1) })
$localPathPattern = '(?i)([a-z]:[\\/](users|documents|realmz|godot)|/(users|home)/[^/\s]+/)'
foreach ($line in $addedTrackedLines) {
    if ($line -match $localPathPattern) {
        throw "Changed text contains a machine-local absolute path: $line"
    }
}

foreach ($path in $changedPaths) {
    $extension = [System.IO.Path]::GetExtension($path).ToLowerInvariant()
    if ($extension -eq ".r2save") {
        throw "Save artifact must not enter a workflow commit: $path"
    }
    $isAllowedRealmz2 = $path.StartsWith("tests/fixtures/packages/") -or
        $path -eq "src/infrastructure/characters/realmz-classic-character-library.realmz2" -or
        $path.StartsWith("src/infrastructure/campaigns/")
    if ($extension -eq ".realmz2" -and -not $isAllowedRealmz2) {
        throw "Package outside the synthetic, application-library, or Castle-distributed bundle boundary must not enter a workflow commit: $path"
    }
    $fullPath = Join-Path $repoRoot $path
    $trackedMatches = @(git -C $repoRoot ls-files -- $path)
    if ($trackedMatches.Count -gt 0 -or -not (Test-Path -LiteralPath $fullPath -PathType Leaf)) {
        continue
    }
    try {
        $untrackedText = Get-Content -LiteralPath $fullPath -Raw -ErrorAction Stop
    } catch {
        continue
    }
    if ($untrackedText -match $localPathPattern) {
        throw "Untracked text contains a machine-local absolute path: $path"
    }
}

Write-Host "Workflow verification complete: $($suiteFragments.Count) suite filter(s), $($caseFragments.Count) case filter(s), $($changedPaths.Count) changed path(s)."
exit 0
