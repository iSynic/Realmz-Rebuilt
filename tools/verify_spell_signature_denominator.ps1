param(
    [switch]$Write,
    [string]$GodotPath = ""
)

$ErrorActionPreference = "Stop"
$repoRoot = Split-Path -Parent $PSScriptRoot

if ([string]::IsNullOrWhiteSpace($GodotPath)) {
    $GodotPath = Get-ChildItem "$env:LOCALAPPDATA\Microsoft\WinGet\Packages" -Recurse -Filter "Godot_v4.7.1-stable_win64_console.exe" -ErrorAction SilentlyContinue |
        Select-Object -First 1 -ExpandProperty FullName
    if (-not $GodotPath) {
        throw "Godot 4.7.1 console executable was not found. Pass -GodotPath explicitly."
    }
}

$arguments = @("--headless", "--path", $repoRoot, "--script", "res://tools/build_spell_signature_denominator.gd")
if ($Write) { $arguments += @("--", "--write") }
& $GodotPath @arguments
if ($LASTEXITCODE -ne 0) { throw "Spell signature denominator verification failed." }
