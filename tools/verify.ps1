param(
    [string]$GodotPath = "",
    # Retained predecessor archives stay outside Git. When supplied, the root
    # holds half-truth/, shop/, marker/ and payment/ input directories.
    [string]$UpdateSaveOriginals = ""
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
Invoke-GodotGate "Complete script compilation" @("--headless", "--path", $repoRoot, "--script", "res://tools/verify_script_compilation.gd")
Invoke-GodotGate "Main scene smoke launch" @("--headless", "--path", $repoRoot, "--quit-after", "5")
Invoke-GodotGate -Label "Headless test suite" -GodotArguments @("--headless", "--path", $repoRoot, "--script", "res://tests/test_runner.gd") -RejectTeardownLeaks
Invoke-GodotGate "Providence-Rebuilt package alignment" @("--headless", "--path", $repoRoot, "--script", "res://tools/providence_alignment_probe.gd")
Invoke-GodotGate "Bundled party-setup catalogs" @("--headless", "--path", $repoRoot, "--script", "res://tools/generate_setup_catalogs.gd", "--", "--check")

$iconInput = Join-Path ([IO.Path]::GetTempPath()) ("realmz-map-icons-" + [Guid]::NewGuid().ToString("N") + ".json")
$iconResult = $iconInput + ".result.json"
$iconArguments = @((Join-Path $PSScriptRoot "map_icon_inventory.py"), "--output", $iconInput)
foreach ($archive in (Get-ChildItem -LiteralPath (Join-Path $repoRoot "src/storage/packages/bundled_campaigns") -File -Filter "*.realmz2" | Sort-Object Name)) {
    $iconArguments += @("--package", $archive.FullName)
}
& python @iconArguments
if ($LASTEXITCODE -ne 0) { throw "Native map-icon inventory failed; inputs: $iconInput" }
Invoke-GodotGate "Native map-icon projection" @("--headless", "--path", $repoRoot, "--script", "res://tools/map_icon_projection_probe.gd", "--", $iconInput, $iconResult)
Remove-Item -LiteralPath $iconInput, $iconResult

if ([string]::IsNullOrWhiteSpace($UpdateSaveOriginals)) {
    Write-Host "Update Save probes not run: pass -UpdateSaveOriginals <retained-archive-root> to exercise Half Truth media, marker and Trouble payment updates."
} else {
    $originals = (Resolve-Path -LiteralPath $UpdateSaveOriginals).Path
    $updateScratch = Join-Path ([IO.Path]::GetTempPath()) ("realmz-update-save-" + [Guid]::NewGuid().ToString("N"))
    Invoke-GodotGate "Half Truth media Update Save probe" @("--headless", "--path", $repoRoot, "--script", "res://tools/half_truth_media_probe.gd", "--", "--package-path=$(Join-Path $originals 'half-truth\scenario-half-truth.realmz2')", "--package-hash=a96fbff24e4204ce49bb60556c27cab6091d0f8f8a26d6b6b0c4c543ecc06562")
    Invoke-GodotGate "Pre-marker stock Update Save probe" @("--headless", "--path", $repoRoot, "--script", "res://tools/marker_save_update_probe.gd", "--", (Join-Path $originals "marker"), (Join-Path $updateScratch "marker"))
    Invoke-GodotGate "Trouble XAP 330 Update Save probe" @("--headless", "--path", $repoRoot, "--script", "res://tools/marker_save_update_probe.gd", "--", (Join-Path $originals "payment"), (Join-Path $updateScratch "payment"), "payment")
    Remove-Item -LiteralPath $updateScratch -Recurse -Force
}

& "$PSScriptRoot\ui-assets\verify-classic-application-media.ps1"
if ($LASTEXITCODE -ne 0) { throw "Classic application media verification failed." }

& "$PSScriptRoot\ui-assets\verify-classic-application-music.ps1"
if ($LASTEXITCODE -ne 0) { throw "Classic application music verification failed." }

& "$PSScriptRoot\verify_architecture.ps1"
if ($LASTEXITCODE -ne 0) { throw "Architecture boundary verification failed." }

& "$PSScriptRoot\verify_hotspot_test_budget.ps1"
if ($LASTEXITCODE -ne 0) { throw "Hotspot and test-budget verification failed." }

& "$PSScriptRoot\verify_human_maintainability.ps1"
if ($LASTEXITCODE -ne 0) { throw "Human-maintainability verification failed." }

& "$PSScriptRoot\verify_architecture_overhaul.ps1"
if ($LASTEXITCODE -ne 0) { throw "Architecture-overhaul verification failed." }

& "$PSScriptRoot\verify_export_contract.ps1"
if ($LASTEXITCODE -ne 0) { throw "Release export contract verification failed." }

& "$PSScriptRoot\verify_bundled_scenarios.ps1"
if ($LASTEXITCODE -ne 0) { throw "Bundled scenario verification failed." }

& "$PSScriptRoot\verify_differential_evidence.ps1"
if ($LASTEXITCODE -ne 0) { throw "Differential evidence verification failed." }

& "$PSScriptRoot\verify_application_workflow_inventory.ps1" -Check
if ($LASTEXITCODE -ne 0) { throw "Application workflow inventory verification failed." }

& "$PSScriptRoot\verify_gameplay_parity_inventory.ps1" -GodotPath $GodotPath
if ($LASTEXITCODE -ne 0) { throw "Gameplay parity inventory verification failed." }

git -C $repoRoot diff --check
if ($LASTEXITCODE -ne 0) { throw "git diff --check failed." }

Write-Host "Verification complete."
