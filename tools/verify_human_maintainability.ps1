param()

$ErrorActionPreference = "Stop"
$repoRoot = Split-Path -Parent $PSScriptRoot
$configPath = Join-Path $PSScriptRoot "human-maintainability-budget.json"
$config = Get-Content -LiteralPath $configPath -Raw | ConvertFrom-Json
$failures = New-Object 'System.Collections.Generic.List[string]'

if ($config.schemaVersion -ne 1) {
    throw "Unsupported human-maintainability budget schema."
}

function Get-RelativePath {
    param([string]$Path)
    return $Path.Substring($repoRoot.Length + 1).Replace("\", "/")
}

function Convert-ToClassName {
    param([string]$Stem)
    $parts = @($Stem.Split('_') | Where-Object { $_.Length -gt 0 })
    return ($parts | ForEach-Object { $_.Substring(0, 1).ToUpperInvariant() + $_.Substring(1) }) -join ''
}

function Get-CodeSemicolonLineCount {
    param([string[]]$Lines)
    $count = 0
    $insideTripleQuotedString = $false
    foreach ($line in $Lines) {
        $quote = [char]0
        $escaped = $false
        $hasSemicolon = $false
        for ($index = 0; $index -lt $line.Length; $index++) {
            if ($insideTripleQuotedString) {
                if ($index + 2 -lt $line.Length -and $line.Substring($index, 3) -eq '"""') {
                    $insideTripleQuotedString = $false
                    $index += 2
                }
                continue
            }
            if ($quote -ne [char]0) {
                if ($escaped) {
                    $escaped = $false
                    continue
                }
                if ($line[$index] -eq '\') {
                    $escaped = $true
                    continue
                }
                if ($line[$index] -eq $quote) {
                    $quote = [char]0
                }
                continue
            }
            if ($index + 2 -lt $line.Length -and $line.Substring($index, 3) -eq '"""') {
                $insideTripleQuotedString = $true
                $index += 2
                continue
            }
            if ($line[$index] -eq '"' -or $line[$index] -eq "'") {
                $quote = $line[$index]
                continue
            }
            if ($line[$index] -eq '#') {
                break
            }
            if ($line[$index] -eq ';') {
                $hasSemicolon = $true
                break
            }
        }
        if ($hasSemicolon) {
            $count++
        }
    }
    return $count
}

$controlTypes = @(
    "Button", "CheckButton", "CheckBox", "ColorRect", "Control", "FlowContainer",
    "GridContainer", "HBoxContainer", "HFlowContainer", "HScrollBar", "HSeparator",
    "Label", "LineEdit", "MarginContainer", "MenuButton", "NinePatchRect", "OptionButton",
    "Panel", "PanelContainer", "ProgressBar", "RichTextLabel", "ScrollContainer", "SpinBox",
    "TabBar", "TabContainer", "TextureButton", "TextureRect", "Tree", "VBoxContainer",
    "VFlowContainer", "VScrollBar", "VSeparator"
)
$controlPattern = '\b(?:' + (($controlTypes | ForEach-Object { [regex]::Escape($_) }) -join '|') + ')\.new\s*\('
$productionFiles = @(Get-ChildItem (Join-Path $repoRoot "src") -Recurse -File -Filter "*.gd")
$statementSeparatorLines = 0
$runtimeControlConstructions = 0
$runtimeControlRecords = @{}
$missingPurposeHeaders = 0

foreach ($file in $productionFiles) {
    $relative = Get-RelativePath $file.FullName
    $content = [IO.File]::ReadAllText($file.FullName)
    $lines = @([IO.File]::ReadAllLines($file.FullName))
    if ($lines.Count -eq 0 -or -not $lines[0].StartsWith("## ")) {
        $missingPurposeHeaders++
    }
    $statementSeparatorLines += Get-CodeSemicolonLineCount $lines
    $functionName = "<file>"
    foreach ($line in $lines) {
        $functionMatch = [regex]::Match($line, '^\s*(?:static\s+)?func\s+([A-Za-z_][A-Za-z0-9_]*)\s*\(')
        if ($functionMatch.Success) {
            $functionName = $functionMatch.Groups[1].Value
        }
        $lineCount = [regex]::Matches($line, $controlPattern).Count
        if ($lineCount -eq 0) {
            continue
        }
        $runtimeControlConstructions += $lineCount
        $key = "$relative::$functionName"
        if (-not $runtimeControlRecords.ContainsKey($key)) {
            $runtimeControlRecords[$key] = [pscustomobject]@{
                Path = $relative
                Function = $functionName
                Count = 0
            }
        }
        $runtimeControlRecords[$key].Count += $lineCount
    }

    $classMatch = [regex]::Match($content, '(?m)^class_name\s+([A-Za-z_][A-Za-z0-9_]*)\s*$')
    if (-not $classMatch.Success) {
        continue
    }
    $actualClass = $classMatch.Groups[1].Value
    $expectedClass = Convert-ToClassName $file.BaseName
    $exception = @($config.classNameExceptions | Where-Object { $_.path -eq $relative -and $_.className -eq $actualClass }).Count -gt 0
    if (-not $exception -and $actualClass -ne $expectedClass) {
        $failures.Add("Class/file name mismatch: $relative declares $actualClass; expected $expectedClass.")
    }
}

if ($statementSeparatorLines -gt [int]$config.statementSeparatorLines.currentMaximum) {
    $failures.Add("Statement-separator debt grew: $statementSeparatorLines > $($config.statementSeparatorLines.currentMaximum).")
}
$classifiedControlConstructions = 0
$classifiedKeys = @{}
$allowedClassificationKinds = @("data-collection", "request-workspace", "algorithmic-surface", "conditional-chrome")
foreach ($classification in @($config.runtimeControlClassifications)) {
    $path = [string]$classification.path
    $kind = [string]$classification.kind
    $reason = [string]$classification.reason
    if ($allowedClassificationKinds -notcontains $kind) {
        $failures.Add("Unknown runtime Control classification kind '$kind' for $path.")
    }
    if ($reason.Trim().Length -lt 12) {
        $failures.Add("Runtime Control classification needs a useful reason: $path")
    }
    $classificationCount = 0
    foreach ($functionName in @($classification.functions)) {
        $key = "$path::$functionName"
        if ($classifiedKeys.ContainsKey($key)) {
            $failures.Add("Duplicate runtime Control classification: $key")
            continue
        }
        $classifiedKeys[$key] = $true
        if (-not $runtimeControlRecords.ContainsKey($key)) {
            $failures.Add("Stale runtime Control classification: $key")
            continue
        }
        $classificationCount += $runtimeControlRecords[$key].Count
    }
    $classifiedControlConstructions += $classificationCount
    if ($classificationCount -ne [int]$classification.currentMaximum) {
        $failures.Add("Runtime Control classification budget changed for ${path}: $classificationCount != $($classification.currentMaximum). Review the functions and update the exact budget.")
    }
}

$unclassifiedRecords = @($runtimeControlRecords.Values | Where-Object {
    -not $classifiedKeys.ContainsKey("$($_.Path)::$($_.Function)")
})
$unclassifiedControlConstructions = ($unclassifiedRecords | Measure-Object -Property Count -Sum).Sum
if ($null -eq $unclassifiedControlConstructions) {
    $unclassifiedControlConstructions = 0
}
if ($unclassifiedControlConstructions -gt [int]$config.runtimeControlConstructions.currentMaximum) {
    $details = ($unclassifiedRecords | Sort-Object -Property @{Expression = "Count"; Descending = $true}, Path, Function | Select-Object -First 12 | ForEach-Object {
        "$($_.Path)::$($_.Function)=$($_.Count)"
    }) -join ", "
    $failures.Add("Unclassified runtime Control construction debt grew: $unclassifiedControlConstructions > $($config.runtimeControlConstructions.currentMaximum). $details")
}
if ($missingPurposeHeaders -gt [int]$config.missingPurposeHeaders.currentMaximum) {
    $failures.Add("Production scripts without purpose headers grew: $missingPurposeHeaders > $($config.missingPurposeHeaders.currentMaximum).")
}

foreach ($relative in @($config.legacyRouteScenes)) {
    $path = Join-Path $repoRoot ([string]$relative)
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) {
        $failures.Add("Legacy route scene entry is stale; remove it after conversion: $relative")
        continue
    }
    $nodeCount = @([regex]::Matches([IO.File]::ReadAllText($path), '(?m)^\[node ')).Count
    if ($nodeCount -ne 1) {
        $failures.Add("Legacy route scene has been given real structure; remove it from the legacy list: $relative")
    }
}

$legacySet = @{}
foreach ($relative in @($config.legacyRouteScenes)) {
    $legacySet[[string]$relative] = $true
}
$markerSet = @{}
foreach ($relative in @($config.routeMarkerScenes)) {
    $path = Join-Path $repoRoot ([string]$relative)
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) {
        $failures.Add("Route-marker scene is missing: $relative")
        continue
    }
    $content = [IO.File]::ReadAllText($path)
    $nodeCount = @([regex]::Matches($content, '(?m)^\[node ')).Count
    if ($nodeCount -ne 1 -or $content -notmatch 'route_id = &"(?:combat|exploration)"') {
        $failures.Add("Route-marker scene must remain a one-node combat or exploration route token: $relative")
    }
    $markerSet[[string]$relative] = $true
}
foreach ($scene in @(Get-ChildItem (Join-Path $repoRoot "src") -Recurse -File -Filter "*_screen.tscn")) {
    $relative = Get-RelativePath $scene.FullName
    $nodeCount = @([regex]::Matches([IO.File]::ReadAllText($scene.FullName), '(?m)^\[node ')).Count
    if ($nodeCount -eq 1 -and -not $legacySet.ContainsKey($relative) -and -not $markerSet.ContainsKey($relative)) {
        $failures.Add("New one-node route scene is not allowed: $relative")
    }
}

Write-Host "Human-maintainability budget: semicolon-lines=$statementSeparatorLines/$($config.statementSeparatorLines.currentMaximum), runtime-controls=$runtimeControlConstructions raw ($classifiedControlConstructions classified, $unclassifiedControlConstructions unclassified/$($config.runtimeControlConstructions.currentMaximum)), missing-purpose-headers=$missingPurposeHeaders/$($config.missingPurposeHeaders.currentMaximum), legacy-route-scenes=$($config.legacyRouteScenes.Count), spatial-route-markers=$($config.routeMarkerScenes.Count)."
if ($failures.Count -gt 0) {
    foreach ($failure in $failures) {
        Write-Error $failure
    }
    exit 1
}

Write-Host "Human-maintainability verification passed."
exit 0
