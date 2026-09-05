param()

$ErrorActionPreference = "Stop"
$repoRoot = Split-Path -Parent $PSScriptRoot
$budget = Get-Content -LiteralPath (Join-Path $PSScriptRoot "architecture-overhaul-budget.json") -Raw | ConvertFrom-Json
$manifestPath = Join-Path $repoRoot ([string]$budget.manifestPath)
$failures = New-Object 'System.Collections.Generic.List[string]'

if ($budget.schemaVersion -ne 1) {
    throw "Unsupported architecture-overhaul budget schema."
}
if (-not (Test-Path -LiteralPath $manifestPath -PathType Leaf)) {
    throw "System manifest is missing: $manifestPath"
}

function Get-RelativePath {
    param([string]$Path)
    return $Path.Substring($repoRoot.Length + 1).Replace("\", "/")
}

function Get-SubstantiveLineCount {
    param([string[]]$Lines)
    return @($Lines | Where-Object {
        $trimmed = $_.Trim()
        -not [string]::IsNullOrWhiteSpace($trimmed) -and -not $trimmed.StartsWith("#")
    }).Count
}

function Get-FunctionMeasurements {
    param([string[]]$Lines)
    $functions = @()
    for ($index = 0; $index -lt $Lines.Count; $index++) {
        if ($Lines[$index] -notmatch '^(\s*)(?:static\s+)?func\s+([A-Za-z0-9_]+)') { continue }
        $functions += [pscustomobject]@{
            Index = $index
            Indent = $Matches[1].Length
            Name = $Matches[2]
        }
    }
    $measurements = @()
    for ($functionIndex = 0; $functionIndex -lt $functions.Count; $functionIndex++) {
        $function = $functions[$functionIndex]
        $end = $Lines.Count
        for ($candidateIndex = $functionIndex + 1; $candidateIndex -lt $functions.Count; $candidateIndex++) {
            if ($functions[$candidateIndex].Indent -le $function.Indent) {
                $end = $functions[$candidateIndex].Index
                break
            }
        }
        $body = @()
        if ($end -gt $function.Index) {
            $body = @($Lines[$function.Index..($end - 1)])
        }
        $measurements += [pscustomobject]@{
            Name = $function.Name
            Indent = $function.Indent
            Lines = Get-SubstantiveLineCount $body
        }
    }
    return $measurements
}

function Add-MigrationCeilingFailure {
    param(
        [string]$Name,
        [int]$Actual
    )
    $ceiling = [int]$budget.migrationCeilings.$Name
    $target = [int]$budget.finalTargets.$Name
    if ($target -gt $ceiling) {
        $failures.Add("Architecture target exceeds its migration ceiling: $Name target=$target ceiling=$ceiling")
    }
    if ($Actual -gt $ceiling) {
        $failures.Add("Architecture migration debt grew: $Name=$Actual ceiling=$ceiling target=$target")
    }
}

$productionFiles = @(Get-ChildItem (Join-Path $repoRoot "src") -Recurse -File -Filter "*.gd")
$oversizedFiles = 0
$oversizedFunctions = 0
$oversizedClasses = 0
$crossObjectPrivateCalls = 0
$genericPreloadAliases = 0

foreach ($file in $productionFiles) {
    $lines = @([IO.File]::ReadAllLines($file.FullName))
    if ((Get-SubstantiveLineCount $lines) -gt [int]$budget.limits.productionFileLines) {
        $oversizedFiles++
    }
    $measurements = @(Get-FunctionMeasurements $lines)
    $oversizedFunctions += @($measurements | Where-Object {
        $_.Lines -gt [int]$budget.limits.functionLines
    }).Count
    $topLevelMethods = @($measurements | Where-Object { $_.Indent -eq 0 })
    $publicMethods = @($topLevelMethods | Where-Object { -not $_.Name.StartsWith("_") })
    if ($topLevelMethods.Count -gt [int]$budget.limits.methodsPerClass -or
        $publicMethods.Count -gt [int]$budget.limits.publicMethodsPerClass) {
        $oversizedClasses++
    }
    $content = [IO.File]::ReadAllText($file.FullName)
    foreach ($match in [regex]::Matches($content, '\b([A-Za-z_][A-Za-z0-9_]*)\._[A-Za-z][A-Za-z0-9_]*\s*\(')) {
        if ($match.Groups[1].Value -ne "self") {
            $crossObjectPrivateCalls++
        }
    }
    $genericPreloadAliases += [regex]::Matches(
        $content,
        '(?m)^const\s+[A-Za-z_][A-Za-z0-9_]*(?:Type|Script)\s*(?::=|=)\s*preload\('
    ).Count
}

$manifest = Get-Content -LiteralPath $manifestPath -Raw | ConvertFrom-Json
if ($manifest.schemaVersion -ne 1) {
    $failures.Add("Unsupported system-manifest schema.")
}
$expectedBoundaries = @("app", "game", "playthrough", "scenarios", "storage", "ui")
$actualBoundaries = @($manifest.boundaries | ForEach-Object { [string]$_ } | Sort-Object)
if (($actualBoundaries -join ',') -ne (($expectedBoundaries | Sort-Object) -join ',')) {
    $failures.Add("System manifest must name exactly the six public architecture boundaries.")
}

$expectedLayoutRoots = @($expectedBoundaries | ForEach-Object { "src/$_" } | Sort-Object)
$actualLayoutRoots = @($manifest.sourceLayout | ForEach-Object { [string]$_.root } | Sort-Object)
if (($actualLayoutRoots -join ',') -ne ($expectedLayoutRoots -join ',')) {
    $failures.Add("System manifest sourceLayout must name each public source boundary exactly once.")
}
$missingFeatureDirectories = 0
$unexpectedFeatureDirectories = 0
$misplacedRootProductionFiles = 0
foreach ($layout in @($manifest.sourceLayout)) {
    $relativeRoot = [string]$layout.root
    $rootPath = Join-Path $repoRoot $relativeRoot
    if (-not (Test-Path -LiteralPath $rootPath -PathType Container)) {
        $failures.Add("Source-layout root is missing: $relativeRoot")
        continue
    }
    $features = @($layout.featureDirectories | ForEach-Object { [string]$_ })
    if ($features.Count -eq 0 -or @($features | Sort-Object -Unique).Count -ne $features.Count) {
        $failures.Add("Source-layout root '$relativeRoot' must name unique feature directories.")
        continue
    }
    $existingDirectories = @(Get-ChildItem -LiteralPath $rootPath -Directory | ForEach-Object { $_.Name })
    $missingFeatureDirectories += @($features | Where-Object { $existingDirectories -notcontains $_ }).Count
    $unexpectedFeatureDirectories += @($existingDirectories | Where-Object { $features -notcontains $_ }).Count
    foreach ($feature in $features) {
        $featureReadme = Join-Path (Join-Path $rootPath $feature) "README.md"
        if (-not (Test-Path -LiteralPath $featureReadme -PathType Leaf)) {
            $failures.Add("Source feature '$relativeRoot/$feature' is missing its public README.md.")
        }
    }
    $misplacedRootProductionFiles += @(Get-ChildItem -LiteralPath $rootPath -File | Where-Object {
        $_.Extension -in @(".gd", ".tscn", ".tres", ".gdshader")
    }).Count
}

$systemIds = @{}
foreach ($system in @($manifest.systems)) {
    $id = [string]$system.id
    if ([string]::IsNullOrWhiteSpace($id) -or $systemIds.ContainsKey($id)) {
        $failures.Add("System manifest contains a blank or duplicate system id: '$id'")
        continue
    }
    $systemIds[$id] = $true
    if ($expectedBoundaries -notcontains [string]$system.boundary) {
        $failures.Add("System '$id' has an unknown boundary: $($system.boundary)")
    }
    $ownedPaths = @([string]$system.guide) + @($system.entryPoints) + @($system.tests) + @($system.performanceProbes)
    foreach ($relative in $ownedPaths) {
        if ([string]::IsNullOrWhiteSpace([string]$relative)) {
            $failures.Add("System '$id' contains a blank owned path.")
            continue
        }
        if (-not (Test-Path -LiteralPath (Join-Path $repoRoot ([string]$relative)))) {
            $failures.Add("System '$id' references a missing path: $relative")
        }
    }
    if (@($system.entryPoints).Count -eq 0 -or @($system.publicInterfaces).Count -eq 0 -or @($system.tests).Count -eq 0) {
        $failures.Add("System '$id' must name an entry point, public interface, and owning test.")
    }
}

$previewPaths = @{}
$previewRegistryPath = Join-Path $repoRoot ([string]$budget.previewRegistryPath)
if (Test-Path -LiteralPath $previewRegistryPath -PathType Leaf) {
    $previewRegistry = Get-Content -LiteralPath $previewRegistryPath -Raw | ConvertFrom-Json
    $requiredProfiles = @("Wide", "Compact", "Empty", "Long Content", "Unavailable", "Error")
    foreach ($profile in $requiredProfiles) {
        if (@($previewRegistry.profiles) -notcontains $profile) {
            $failures.Add("Realmz Builder preview registry is missing the '$profile' profile.")
        }
    }
    $registeredPreviewIds = @{}
    foreach ($preview in @($previewRegistry.scenes)) {
        $previewId = [string]$preview.id
        $previewScene = [string]$preview.scene
        if ([string]::IsNullOrWhiteSpace($previewId) -or $registeredPreviewIds.ContainsKey($previewId)) {
            $failures.Add("Realmz Builder contains a blank or duplicate scene id: '$previewId'")
            continue
        }
        $registeredPreviewIds[$previewId] = $true
        foreach ($property in @("scene", "guide", "controller", "view")) {
            $relative = [string]$preview.$property
            if ([string]::IsNullOrWhiteSpace($relative) -or -not (Test-Path -LiteralPath (Join-Path $repoRoot $relative) -PathType Leaf)) {
                $failures.Add("Realmz Builder '$previewId' references a missing $property path: $relative")
            }
        }
        if (@($preview.tests).Count -eq 0) {
            $failures.Add("Realmz Builder '$previewId' must name at least one owning test.")
        }
        foreach ($test in @($preview.tests)) {
            if (-not (Test-Path -LiteralPath (Join-Path $repoRoot ([string]$test)) -PathType Leaf)) {
                $failures.Add("Realmz Builder '$previewId' references a missing test: $test")
            }
        }
        if ($preview.productionBinding -eq $true) {
            $previewPaths[$previewScene] = $true
        }
    }
}
$builderPluginPath = Join-Path $repoRoot "addons\realmz_builder\plugin.cfg"
$builderScriptPath = Join-Path $repoRoot "addons\realmz_builder\realmz_builder_plugin.gd"
if (-not (Test-Path -LiteralPath $builderPluginPath -PathType Leaf) -or -not (Test-Path -LiteralPath $builderScriptPath -PathType Leaf)) {
    $failures.Add("The Realmz Builder editor plugin and its scene-preview registry are required.")
}
$projectSettings = Get-Content -LiteralPath (Join-Path $repoRoot "project.godot") -Raw
if (-not $projectSettings.Contains('res://addons/realmz_builder/plugin.cfg')) {
    $failures.Add("Realmz Builder must be enabled for contributors in project.godot.")
}
$surfaceIds = @{}
$surfacesWithoutScene = 0
$surfacesWithoutPreview = 0
foreach ($surface in @($manifest.majorUiSurfaces)) {
    $id = [string]$surface.id
    if ([string]::IsNullOrWhiteSpace($id) -or $surfaceIds.ContainsKey($id)) {
        $failures.Add("System manifest contains a blank or duplicate major UI surface id: '$id'")
        continue
    }
    $surfaceIds[$id] = $true
    $scene = [string]$surface.scene
    if ([string]::IsNullOrWhiteSpace($scene)) {
        $surfacesWithoutScene++
        $surfacesWithoutPreview++
        continue
    }
    if (-not (Test-Path -LiteralPath (Join-Path $repoRoot $scene) -PathType Leaf)) {
        $failures.Add("Major UI surface '$id' references a missing scene: $scene")
    }
    if (-not $previewPaths.ContainsKey($scene)) {
        $surfacesWithoutPreview++
    }
}

$shellModeMarkerScenes = 0
foreach ($sceneName in @("exploration_screen.tscn", "combat_screen.tscn")) {
    foreach ($file in Get-ChildItem -LiteralPath (Join-Path $repoRoot "src/ui") -Recurse -File -Filter $sceneName) {
        $nodeCount = [regex]::Matches([IO.File]::ReadAllText($file.FullName), '(?m)^\[node ').Count
        if ($nodeCount -eq 1) { $shellModeMarkerScenes++ }
    }
}

Add-MigrationCeilingFailure "oversizedProductionFiles" $oversizedFiles
Add-MigrationCeilingFailure "oversizedFunctions" $oversizedFunctions
Add-MigrationCeilingFailure "oversizedTopLevelClasses" $oversizedClasses
Add-MigrationCeilingFailure "crossObjectPrivateCalls" $crossObjectPrivateCalls
Add-MigrationCeilingFailure "genericPreloadAliases" $genericPreloadAliases
Add-MigrationCeilingFailure "majorSurfacesWithoutScene" $surfacesWithoutScene
Add-MigrationCeilingFailure "majorSurfacesWithoutPreview" $surfacesWithoutPreview
Add-MigrationCeilingFailure "shellModeMarkerScenes" $shellModeMarkerScenes
Add-MigrationCeilingFailure "missingFeatureDirectories" $missingFeatureDirectories
Add-MigrationCeilingFailure "unexpectedFeatureDirectories" $unexpectedFeatureDirectories
Add-MigrationCeilingFailure "misplacedRootProductionFiles" $misplacedRootProductionFiles

Write-Host "Architecture overhaul: files=$oversizedFiles/$($budget.migrationCeilings.oversizedProductionFiles)->0, functions=$oversizedFunctions/$($budget.migrationCeilings.oversizedFunctions)->0, classes=$oversizedClasses/$($budget.migrationCeilings.oversizedTopLevelClasses)->0, cross-private=$crossObjectPrivateCalls/$($budget.migrationCeilings.crossObjectPrivateCalls)->0, generic-aliases=$genericPreloadAliases/$($budget.migrationCeilings.genericPreloadAliases)->0, missing-scenes=$surfacesWithoutScene/$($budget.migrationCeilings.majorSurfacesWithoutScene)->0, missing-previews=$surfacesWithoutPreview/$($budget.migrationCeilings.majorSurfacesWithoutPreview)->0, shell-markers=$shellModeMarkerScenes/$($budget.migrationCeilings.shellModeMarkerScenes)->0, missing-feature-dirs=$missingFeatureDirectories/$($budget.migrationCeilings.missingFeatureDirectories)->0, unexpected-feature-dirs=$unexpectedFeatureDirectories/$($budget.migrationCeilings.unexpectedFeatureDirectories)->0, misplaced-root-files=$misplacedRootProductionFiles/$($budget.migrationCeilings.misplacedRootProductionFiles)->0."
if ($failures.Count -gt 0) {
    foreach ($failure in $failures) { Write-Error $failure }
    exit 1
}
Write-Host "Architecture overhaul manifest and migration ceilings verified."
exit 0
