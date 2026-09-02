param()

$ErrorActionPreference = "Stop"
$repoRoot = Split-Path -Parent $PSScriptRoot
$configPath = Join-Path $PSScriptRoot "hotspot-test-budget.json"

function Get-SubstantiveLines {
    param([string]$Path)
    return @(
        Get-Content -LiteralPath $Path |
            Where-Object {
                $trimmed = $_.Trim()
                -not [string]::IsNullOrWhiteSpace($trimmed) -and -not $trimmed.StartsWith("#")
            }
    ).Count
}

function Get-RelativePath {
    param([string]$Path)
    return $Path.Substring($repoRoot.Length + 1).Replace("\", "/")
}

function Get-FunctionMeasurements {
    param([string]$Path)
    $lines = @(Get-Content -LiteralPath $Path)
    $functions = @()
    for ($index = 0; $index -lt $lines.Count; $index++) {
        if ($lines[$index] -notmatch '^(\s*)(?:static\s+)?func\s+([A-Za-z0-9_]+)') { continue }
        $functions += [pscustomobject]@{
            Index = $index
            Indent = $Matches[1].Length
            Name = $Matches[2]
        }
    }
    $measurements = @()
    for ($functionIndex = 0; $functionIndex -lt $functions.Count; $functionIndex++) {
        $function = $functions[$functionIndex]
        $end = $lines.Count
        for ($candidateIndex = $functionIndex + 1; $candidateIndex -lt $functions.Count; $candidateIndex++) {
            if ($functions[$candidateIndex].Indent -le $function.Indent) {
                $end = $functions[$candidateIndex].Index
                break
            }
        }
        $count = 0
        for ($lineIndex = $function.Index; $lineIndex -lt $end; $lineIndex++) {
            $trimmed = $lines[$lineIndex].Trim()
            if (-not [string]::IsNullOrWhiteSpace($trimmed) -and -not $trimmed.StartsWith("#")) {
                $count++
            }
        }
        $measurements += [pscustomobject]@{
            Name = $function.Name
            Line = $function.Index + 1
            Lines = $count
        }
    }
    return $measurements
}

function Test-GrandfatherEntries {
    param(
        [object[]]$Entries,
        [string]$Label,
        [System.Collections.Generic.List[string]]$Failures
    )
    foreach ($entry in @($Entries)) {
        if ($null -eq $entry.path -or $null -eq $entry.sha256 -or $null -eq $entry.maximumLines) {
            $Failures.Add("$Label grandfather entry is missing path, sha256, or maximumLines.")
            continue
        }
        $path = Join-Path $repoRoot ([string]$entry.path)
        if (-not (Test-Path -LiteralPath $path -PathType Leaf)) {
            $Failures.Add("$Label grandfather path does not exist: $($entry.path)")
            continue
        }
        $hash = (Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash.ToLowerInvariant()
        if ($hash -ne ([string]$entry.sha256).ToLowerInvariant()) {
            $Failures.Add("$Label grandfather hash changed and may not grow: $($entry.path)")
        }
        $lines = Get-SubstantiveLines $path
        if ($lines -gt [int]$entry.maximumLines) {
            $Failures.Add("$Label grandfather exceeds its no-growth ceiling: $($entry.path) has $lines lines.")
        }
    }
}

if (-not (Test-Path -LiteralPath $configPath -PathType Leaf)) {
    throw "Hotspot/test-budget configuration is missing: $configPath"
}
$config = Get-Content -LiteralPath $configPath -Raw | ConvertFrom-Json
if ($config.schemaVersion -ne 1 -or $config.substantiveLineAlgorithm -ne "trimmed-nonblank-noncomment-v1") {
    throw "Unsupported hotspot/test-budget configuration."
}

$failures = New-Object 'System.Collections.Generic.List[string]'
$productionFiles = @(Get-ChildItem (Join-Path $repoRoot "src") -Recurse -File -Filter "*.gd")
$testFiles = @(Get-ChildItem (Join-Path $repoRoot "tests") -Recurse -File -Filter "*.gd")
$productionLines = 0
$testLines = 0

foreach ($file in $productionFiles) {
    $relative = Get-RelativePath $file.FullName
    $lines = Get-SubstantiveLines $file.FullName
    $productionLines += $lines
    $grandfathered = @($config.productionGrandfather | Where-Object { $_.path -eq $relative }).Count -gt 0
    if (-not $grandfathered -and $lines -gt [int]$config.limits.productionFileLines) {
        $failures.Add("Production hotspot exceeds $($config.limits.productionFileLines) lines: $relative has $lines.")
    }
    foreach ($function in @(Get-FunctionMeasurements $file.FullName)) {
        if ($function.Lines -gt [int]$config.limits.functionLines) {
            $failures.Add("Function hotspot exceeds $($config.limits.functionLines) lines: ${relative}:$($function.Line) $($function.Name) has $($function.Lines).")
        }
    }
}

foreach ($file in $testFiles) {
    $relative = Get-RelativePath $file.FullName
    $lines = Get-SubstantiveLines $file.FullName
    $testLines += $lines
    $grandfathered = @($config.testSuiteGrandfather | Where-Object { $_.path -eq $relative }).Count -gt 0
    if (-not $grandfathered -and $lines -gt [int]$config.limits.testSuiteLines) {
        $failures.Add("Test suite exceeds $($config.limits.testSuiteLines) lines: $relative has $lines.")
    }
    $lineNumber = 0
    foreach ($line in @(Get-Content -LiteralPath $file.FullName)) {
        $lineNumber++
        if ($line -match '\._[A-Za-z][A-Za-z0-9_]*\s*\(') {
            $failures.Add("Test calls a private product-style method: ${relative}:$lineNumber")
        }
    }
}

Test-GrandfatherEntries @($config.productionGrandfather) "Production" $failures
Test-GrandfatherEntries @($config.testSuiteGrandfather) "Test suite" $failures

if ($testLines -gt [int]$config.limits.currentTestLines) {
    $failures.Add("Test budget exceeds the current ratchet: $testLines > $($config.limits.currentTestLines).")
}
if ($testLines -gt [int]$config.limits.finalTestLines) {
    $failures.Add("Test budget exceeds the final ceiling: $testLines > $($config.limits.finalTestLines).")
}
$ratio = if ($productionLines -eq 0) { 100.0 } else { 100.0 * $testLines / $productionLines }
if ($ratio -gt [double]$config.limits.testToProductionPercent) {
    $failures.Add("Test/production ratio exceeds $($config.limits.testToProductionPercent)%: $([math]::Round($ratio, 2))%.")
}

Write-Host "Hotspot/test budget: production=$productionLines, tests=$testLines, ratio=$([math]::Round($ratio, 2))%, largest-file=$($config.limits.productionFileLines), largest-function=$($config.limits.functionLines), largest-suite=$($config.limits.testSuiteLines)."
if ($failures.Count -gt 0) {
    foreach ($failure in $failures) { Write-Error $failure }
    exit 1
}
Write-Host "Hotspot and test-budget verification passed."
exit 0
