param(
    [string[]]$Suite = @(),
    [string[]]$Case = @(),
    [ValidateRange(1, 3600)]
    [int]$TimeoutSeconds = 120,
    [string]$GodotPath = ""
)

$ErrorActionPreference = "Stop"
$repoRoot = Split-Path -Parent $PSScriptRoot
. "$PSScriptRoot\stream_process.ps1"

if ($Suite.Count -eq 0 -and $Case.Count -eq 0) {
    throw "Focused tests require at least one -Suite or -Case filter. Use tools/verify.ps1 for the complete suite."
}
if ($Suite.Count -eq 0 -and $Case.Count -gt 0) {
    throw "Named case filters require at least one -Suite filter so unrelated suites are never instantiated."
}

if ([string]::IsNullOrWhiteSpace($GodotPath)) {
    $GodotPath = Get-ChildItem "$env:LOCALAPPDATA\Microsoft\WinGet\Packages" -Recurse -Filter "Godot_v4.7.1-stable_win64_console.exe" -ErrorAction SilentlyContinue |
        Select-Object -First 1 -ExpandProperty FullName
    if (-not $GodotPath) {
        throw "Godot 4.7.1 console executable was not found. Pass -GodotPath explicitly."
    }
}

$arguments = [System.Collections.Generic.List[string]]::new()
@("--headless", "--path", $repoRoot, "--script", "res://tests/test_runner.gd", "--") | ForEach-Object { $arguments.Add($_) }
@($Suite | ForEach-Object { $_.Trim() } | Where-Object { $_ } | Select-Object -Unique) | ForEach-Object {
    $arguments.Add("--suite")
    $arguments.Add($_)
}
@($Case | ForEach-Object { $_.Trim() } | Where-Object { $_ } | Select-Object -Unique) | ForEach-Object {
    $arguments.Add("--case")
    $arguments.Add($_)
}
$result = Invoke-StreamingProcess -FilePath $GodotPath -ArgumentList $arguments.ToArray() -Label "Focused Godot tests" -TimeoutSeconds $TimeoutSeconds
$combinedOutput = $result.Output -join "`n"
if ($result.ExitCode -ne 0) {
    throw "Focused Godot tests failed with exit code $($result.ExitCode)."
}
if ($combinedOutput -match "SCRIPT ERROR:" -or $combinedOutput -match "Parse Error:") {
    throw "Focused Godot tests emitted a GDScript error despite returning exit 0."
}
if ($combinedOutput -match "ObjectDB instances were leaked at exit" -or $combinedOutput -match "resources still in use at exit") {
    throw "Focused Godot tests retained objects or resources during process teardown."
}
