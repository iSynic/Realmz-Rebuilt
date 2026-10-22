param(
    [Parameter(Mandatory = $true)][string]$GodotPath,
    [Parameter(Mandatory = $true)][string]$NativeReceiptPath,
    [Parameter(Mandatory = $true)][string]$ClockInputsPath,
    [Parameter(Mandatory = $true)][string]$OutputRoot,
    [string]$BywaterArchivePath = "",
    [string]$BywaterCheckpointPath = ""
)

$ErrorActionPreference = "Stop"
$repoRoot = Split-Path -Parent $PSScriptRoot
. "$PSScriptRoot/stream_process.ps1"
foreach ($path in @($GodotPath, $NativeReceiptPath, $ClockInputsPath)) {
    if (-not [System.IO.Path]::IsPathRooted($path) -or -not (Test-Path -LiteralPath $path -PathType Leaf)) {
        throw "An existing absolute input file is required: $path"
    }
}
if (-not [System.IO.Path]::IsPathRooted($OutputRoot) -or (Test-Path -LiteralPath $OutputRoot)) {
    throw "OutputRoot must be a fresh absolute directory."
}
if ([string]::IsNullOrEmpty($BywaterArchivePath) -ne [string]::IsNullOrEmpty($BywaterCheckpointPath)) {
    throw "Supply both Bywater archive and checkpoint, or neither."
}
foreach ($path in @($BywaterArchivePath, $BywaterCheckpointPath)) {
    if ($path -and (-not [System.IO.Path]::IsPathRooted($path) -or -not (Test-Path -LiteralPath $path -PathType Leaf))) {
        throw "An existing absolute fixture input is required: $path"
    }
}
$null = New-Item -ItemType Directory -Path $OutputRoot

function Invoke-CompatibilityProbe {
    param([string]$Name, [string]$Script, [string[]]$Inputs)
    $result = Invoke-StreamingProcess -FilePath $GodotPath -Label $Name -TimeoutSeconds 300 -ArgumentList (@("--headless", "--path", $repoRoot, "--script", $Script, "--") + $Inputs)
    $combined = $result.Output -join "`n"
    [System.IO.File]::WriteAllText((Join-Path $OutputRoot "$Name.log"), $combined, [System.Text.UTF8Encoding]::new($false))
    if ($result.ExitCode -ne 0 -or $combined -match '(?m)(SCRIPT ERROR:|Parse Error:|^ERROR:|ObjectDB instances were leaked|resources still in use at exit)') {
        throw "$Name failed or emitted an engine error or teardown leak."
    }
}

$clockOutput = Join-Path $OutputRoot "clock-and-combat.json"
Invoke-CompatibilityProbe "clock-and-combat" "res://tools/clock_combat_compatibility_probe.gd" @($NativeReceiptPath, $ClockInputsPath, $clockOutput)
$clock = Get-Content -LiteralPath $clockOutput -Raw | ConvertFrom-Json
if ($clock.format -ne 'realmz.clock-combat-compatibility/1' -or @($clock.failures).Count -ne 0 -or @($clock.clockCases).Count -ne 89 -or @($clock.fixtures.checks).Count -ne 95 -or @($clock.fixtures.timers.checks).Count -ne 42 -or @($clock.fixtures.timers.failures).Count -ne 0) {
    throw "Clock/combat evidence is incomplete or has failed checks."
}
if ($BywaterArchivePath) {
    $sessionRoot = Join-Path $OutputRoot "session"
    Invoke-CompatibilityProbe "session" "res://tools/clock_combat_session_probe.gd" @($BywaterArchivePath, $BywaterCheckpointPath, $sessionRoot)
    $session = Get-Content -LiteralPath (Join-Path $sessionRoot "result.json") -Raw | ConvertFrom-Json
    if ($session.format -ne 'realmz.clock-combat-session/1' -or @($session.failures).Count -ne 0 -or @($session.checks).Count -ne 59) {
        throw "Session evidence is incomplete or has failed checks."
    }
}
$receipt = [ordered]@{
    format = 'realmz.clock-combat-verification/1'
    sourceRevision = (& git -C $repoRoot rev-parse HEAD)
    sourceStatus = @(& git -C $repoRoot status --porcelain)
    godotSha256 = (Get-FileHash -LiteralPath $GodotPath -Algorithm SHA256).Hash.ToLowerInvariant()
    nativeReceiptSha256 = (Get-FileHash -LiteralPath $NativeReceiptPath -Algorithm SHA256).Hash.ToLowerInvariant()
    clockInputsSha256 = (Get-FileHash -LiteralPath $ClockInputsPath -Algorithm SHA256).Hash.ToLowerInvariant()
    clockOutputSha256 = (Get-FileHash -LiteralPath $clockOutput -Algorithm SHA256).Hash.ToLowerInvariant()
    sessionIncluded = [bool]$BywaterArchivePath
}
[System.IO.File]::WriteAllText((Join-Path $OutputRoot "verification.json"), ($receipt | ConvertTo-Json -Depth 6), [System.Text.UTF8Encoding]::new($false))
Write-Host "Clock/combat compatibility verification passed. Evidence: $OutputRoot"
