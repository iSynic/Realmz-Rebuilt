param(
    [string]$GodotPath = ""
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

& $GodotPath --headless --path $repoRoot --editor --quit
if ($LASTEXITCODE -ne 0) { throw "Godot project import/script validation failed." }

& $GodotPath --headless --path $repoRoot --quit-after 5
if ($LASTEXITCODE -ne 0) { throw "Main scene smoke launch failed." }

& $GodotPath --headless --path $repoRoot --script res://tests/test_runner.gd
if ($LASTEXITCODE -ne 0) { throw "Headless test suite failed." }

& "$PSScriptRoot\verify_architecture.ps1"
if ($LASTEXITCODE -ne 0) { throw "Architecture boundary verification failed." }

& "$PSScriptRoot\verify_export_contract.ps1"
if ($LASTEXITCODE -ne 0) { throw "Release export contract verification failed." }

git -C $repoRoot diff --check
if ($LASTEXITCODE -ne 0) { throw "git diff --check failed." }

Write-Host "Verification complete."
