param(
    [Parameter(Mandatory = $true)]
    [ValidateNotNullOrEmpty()]
    [string[]]$Suite,
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
if ($suiteFragments.Count -eq 0) {
    throw "At least one non-empty -Suite path fragment is required."
}

$testArguments = @("--headless", "--path", $repoRoot, "--script", "res://tests/test_runner.gd", "--")
foreach ($fragment in $suiteFragments) {
    $testArguments += @("--suite", $fragment)
}

$previousErrorAction = $ErrorActionPreference
$ErrorActionPreference = "Continue"
try {
    $testOutput = & $GodotPath @testArguments 2>&1
    $testExitCode = $LASTEXITCODE
} finally {
    $ErrorActionPreference = $previousErrorAction
}
$testOutput | ForEach-Object { Write-Host $_ }
$combinedOutput = $testOutput -join "`n"
if ($testExitCode -ne 0) {
    throw "Focused Godot suites failed with exit code $testExitCode."
}
if ($combinedOutput -match "SCRIPT ERROR:" -or $combinedOutput -match "Parse Error:") {
    throw "Focused Godot suites emitted a GDScript error despite returning exit 0."
}
if ($combinedOutput -match "ObjectDB instances were leaked at exit" -or $combinedOutput -match "resources still in use at exit") {
    throw "Focused Godot suites retained objects or resources during process teardown."
}

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

$referenceArguments = @{}
if (-not [string]::IsNullOrWhiteSpace($CastleRoot)) { $referenceArguments.CastleRoot = $CastleRoot }
if (-not [string]::IsNullOrWhiteSpace($RemakeRoot)) { $referenceArguments.RemakeRoot = $RemakeRoot }
if (-not [string]::IsNullOrWhiteSpace($ProvidenceRoot)) { $referenceArguments.ProvidenceRoot = $ProvidenceRoot }

& "$PSScriptRoot\verify_differential_evidence.ps1" @referenceArguments
if ($LASTEXITCODE -ne 0) { throw "Differential evidence verification failed." }

& "$PSScriptRoot\verify_application_workflow_inventory.ps1" -Check @referenceArguments
if ($LASTEXITCODE -ne 0) { throw "Application workflow inventory verification failed." }

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
    if ($extension -eq ".realmz2" -and -not $path.StartsWith("tests/fixtures/packages/")) {
        throw "Campaign package outside the synthetic fixture boundary must not enter a workflow commit: $path"
    }
    $fullPath = Join-Path $repoRoot $path
    if ((git -C $repoRoot ls-files --error-unmatch -- $path 2>$null) -or -not (Test-Path -LiteralPath $fullPath -PathType Leaf)) {
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

Write-Host "Workflow verification complete: $($suiteFragments.Count) requested suite filter(s), $($changedPaths.Count) changed path(s)."
exit 0
