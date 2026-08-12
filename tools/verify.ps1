param(
    [string]$GodotPath = ""
)

$ErrorActionPreference = "Stop"
$repoRoot = Split-Path -Parent $PSScriptRoot
. "$PSScriptRoot\stream_process.ps1"

if ([string]::IsNullOrWhiteSpace($GodotPath)) {
    $candidate = Get-ChildItem "$env:LOCALAPPDATA\Microsoft\WinGet\Packages" -Recurse -Filter "Godot_v4.7.1-stable_win64_console.exe" -ErrorAction SilentlyContinue |
        Select-Object -First 1 -ExpandProperty FullName
    if (-not $candidate) {
        throw "Godot 4.7.1 console executable was not found. Pass -GodotPath explicitly."
    }
    $GodotPath = $candidate
}

$intelligenceGenerator = Join-Path $PSScriptRoot "source-intelligence\generate.ps1"
& $intelligenceGenerator
if ($LASTEXITCODE -ne 0) { throw "Source intelligence generation failed." }
if ($env:CI -eq "true") {
    $codemapStatus = @(git -C $repoRoot status --porcelain --untracked-files=all -- docs/codemap)
    if ($codemapStatus.Count -gt 0) {
        throw "Committed source-intelligence artifacts are stale. Regenerate and commit docs/codemap/."
    }
}

function Invoke-GodotGate {
    param(
        [string]$Label,
        [string[]]$GodotArguments,
        [switch]$RejectTeardownLeaks
    )

    $result = Invoke-StreamingProcess -FilePath $GodotPath -ArgumentList $GodotArguments -Label $Label
    $combined = $result.Output -join "`n"
    if ($result.ExitCode -ne 0) { throw "$Label failed with exit code $($result.ExitCode)." }
    if ($combined -match "SCRIPT ERROR:" -or $combined -match "Parse Error:") {
        throw "$Label emitted a GDScript error despite returning exit 0."
    }
    if ($RejectTeardownLeaks -and ($combined -match "ObjectDB instances were leaked at exit" -or $combined -match "resources still in use at exit")) {
        throw "$Label retained Godot objects or resources during process teardown."
    }
}

Invoke-GodotGate "Godot project import/script validation" @("--headless", "--path", $repoRoot, "--editor", "--quit")
Invoke-GodotGate "Main scene smoke launch" @("--headless", "--path", $repoRoot, "--quit-after", "5")
Invoke-GodotGate -Label "Headless test suite" -GodotArguments @("--headless", "--path", $repoRoot, "--script", "res://tests/test_runner.gd") -RejectTeardownLeaks

& "$PSScriptRoot\verify_architecture.ps1"
if ($LASTEXITCODE -ne 0) { throw "Architecture boundary verification failed." }

& "$PSScriptRoot\verify_export_contract.ps1"
if ($LASTEXITCODE -ne 0) { throw "Release export contract verification failed." }

& "$PSScriptRoot\verify_differential_evidence.ps1"
if ($LASTEXITCODE -ne 0) { throw "Differential evidence verification failed." }

& "$PSScriptRoot\verify_application_workflow_inventory.ps1" -Check
if ($LASTEXITCODE -ne 0) { throw "Application workflow inventory verification failed." }

git -C $repoRoot diff --check
if ($LASTEXITCODE -ne 0) { throw "git diff --check failed." }

Write-Host "Verification complete."
