param(
    [string]$GodotPath = "",
    [switch]$Update,
    [string]$Report = ""
)

# Ratchets GDScript unsafe-typing warnings per file. Godot cannot raise warning
# levels per directory, so a temporary override.cfg promotes the unsafe_* family
# to errors for one complete compilation pass; every reported site is counted
# against the exact per-file ceilings in unsafe-warning-budget.json.

$ErrorActionPreference = "Stop"
$repoRoot = Split-Path -Parent $PSScriptRoot
$budgetPath = Join-Path $PSScriptRoot "unsafe-warning-budget.json"
$overridePath = Join-Path $repoRoot "override.cfg"
$budget = Get-Content -Raw -LiteralPath $budgetPath | ConvertFrom-Json

if ([string]::IsNullOrWhiteSpace($GodotPath)) {
    $GodotPath = Get-ChildItem "$env:LOCALAPPDATA\Microsoft\WinGet\Packages" -Recurse -Filter "Godot_v4.7.1-stable_win64_console.exe" -ErrorAction SilentlyContinue |
        Select-Object -First 1 -ExpandProperty FullName
    if (-not $GodotPath) { throw "Godot 4.7.1 console executable was not found. Pass -GodotPath explicitly." }
}
if (Test-Path -LiteralPath $overridePath) { throw "override.cfg already exists; refusing to replace a local project override." }

$settings = @("[debug]") + @($budget.warnings | ForEach-Object { "gdscript/warnings/$_=2" })
[System.IO.File]::WriteAllText($overridePath, ($settings -join "`n") + "`n", [System.Text.UTF8Encoding]::new($false))
try {
    $engineLog = Join-Path ([IO.Path]::GetTempPath()) ("realmz-warnings-" + [Guid]::NewGuid().ToString("N") + ".log")
    $output = @(& $GodotPath --headless --log-file $engineLog --path $repoRoot --script "res://tools/verify_script_compilation.gd" 2>&1 | ForEach-Object { "$_" })
} finally {
    Remove-Item -LiteralPath $overridePath -Force
}
if (-not ($output -match '^Compiled \d+ project scripts\.$')) { throw "Unsafe-warning compilation pass did not complete." }

# Each promoted warning prints its message, then a backtrace line naming res://path.gd:line.
$sites = @{}
for ($index = 0; $index -lt $output.Count; $index++) {
    if ($output[$index] -notmatch 'Parse Error: (.+) \(Warning treated as error\.\)') { continue }
    $message = $Matches[1]
    for ($next = $index + 1; $next -lt [Math]::Min($index + 4, $output.Count); $next++) {
        if ($output[$next] -match 'res://([^:)]+\.gd):(\d+)') {
            $sites["$($Matches[1])|$($Matches[2])|$message"] = $Matches[1]
            break
        }
    }
}
$measured = @{}
foreach ($path in $sites.Values) { $measured[$path] = 1 + [int]$measured[$path] }
$total = [int](($measured.Values | Measure-Object -Sum).Sum)

if (-not [string]::IsNullOrWhiteSpace($Report)) {
    $sites.Keys | Where-Object { $_.StartsWith($Report) } | Sort-Object { $_.Split("|")[0] }, { [int]$_.Split("|")[1] } | ForEach-Object {
        $parts = $_.Split("|", 3)
        Write-Host "$($parts[0]):$($parts[1]): $($parts[2])"
    }
    return
}

if ($Update) {
    $files = [ordered]@{}
    foreach ($path in ($measured.Keys | Sort-Object)) { $files[$path] = $measured[$path] }
    $updated = [ordered]@{
        schemaVersion = 1
        warnings = @($budget.warnings)
        zeroPrefixes = @($budget.zeroPrefixes)
        total = $total
        files = $files
    }
    [System.IO.File]::WriteAllText($budgetPath, ($updated | ConvertTo-Json -Depth 4) + "`n", [System.Text.UTF8Encoding]::new($false))
    Write-Host "Unsafe-warning budget rewritten: $total sites in $($measured.Count) files."
    return
}

$failures = @()
foreach ($path in $measured.Keys) {
    $ceiling = if ($null -ne $budget.files.$path) { [int]$budget.files.$path } else { 0 }
    if ($measured[$path] -gt $ceiling) { $failures += "$path has $($measured[$path]) unsafe-typing sites; its ceiling is $ceiling." }
    foreach ($prefix in @($budget.zeroPrefixes)) {
        if ($path.StartsWith($prefix) -and $measured[$path] -gt 0) { $failures += "$path is under zero-locked $prefix and has $($measured[$path]) unsafe-typing sites." }
    }
}
if ($failures.Count -gt 0) { throw ("Unsafe-warning ratchet failed:`n" + ($failures -join "`n")) }
Write-Host "Unsafe-warning ratchet: $total sites in $($measured.Count) files (budget $($budget.total)); zero-locked: $(@($budget.zeroPrefixes) -join ', ')."
