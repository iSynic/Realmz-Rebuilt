$ErrorActionPreference = "Stop"
$repoRoot = Split-Path -Parent $PSScriptRoot
$violations = @()

function Remove-GdscriptLineComment {
    param([string]$Line)

    # Architecture checks inspect executable syntax only.  In particular, do
    # not let examples in comments or a '#' inside a quoted string become a
    # false dependency edge.
    $builder = [Text.StringBuilder]::new()
    $inString = $false
    $escaped = $false
    foreach ($character in $Line.ToCharArray()) {
        if ($escaped) {
            [void]$builder.Append($character)
            $escaped = $false
            continue
        }
        if ($character -eq '\' -and $inString) {
            [void]$builder.Append($character)
            $escaped = $true
            continue
        }
        if ($character -eq '"') {
            $inString = -not $inString
            [void]$builder.Append($character)
            continue
        }
        if ($character -eq '#' -and -not $inString) {
            break
        }
        [void]$builder.Append($character)
    }
    return $builder.ToString()
}

function Get-SanitizedGdscriptLines {
    param([string]$Content)

    # Replace comments and quoted strings with spaces while preserving line
    # numbers and executable identifiers.  The architecture scan must not
    # interpret a dependency-looking example in documentation or a literal
    # string as a class reference.  Triple-quoted strings are handled as well
    # because GDScript permits multiline string literals.
    $lines = [Collections.Generic.List[string]]::new()
    $builder = [Text.StringBuilder]::new()
    $inString = $false
    $tripleString = $false
    $quote = [char]0
    $escaped = $false
    $inLineComment = $false
    $index = 0
    while ($index -lt $Content.Length) {
        $character = $Content[$index]
        if ($character -eq "`r") {
            $index++
            continue
        }
        if ($character -eq "`n") {
            [void]$lines.Add($builder.ToString())
            [void]$builder.Clear()
            $inLineComment = $false
            $escaped = $false
            $index++
            continue
        }
        if ($inLineComment) {
            [void]$builder.Append(' ')
            $index++
            continue
        }
        if ($inString) {
            if ($tripleString -and $index + 2 -lt $Content.Length -and $Content[$index] -eq $quote -and $Content[$index + 1] -eq $quote -and $Content[$index + 2] -eq $quote) {
                [void]$builder.Append('   ')
                $index += 3
                $inString = $false
                $tripleString = $false
                $quote = [char]0
                $escaped = $false
                continue
            }
            if (-not $tripleString -and $character -eq $quote) {
                [void]$builder.Append(' ')
                $index++
                $inString = $false
                $quote = [char]0
                $escaped = $false
                continue
            }
            [void]$builder.Append(' ')
            if ($escaped) {
                $escaped = $false
            } elseif ($character -eq '\') {
                $escaped = $true
            }
            $index++
            continue
        }
        if ($character -eq '#') {
            [void]$builder.Append(' ')
            $inLineComment = $true
            $index++
            continue
        }
        if (($character -eq '"' -or $character -eq "'") -and $index + 2 -lt $Content.Length -and $Content[$index + 1] -eq $character -and $Content[$index + 2] -eq $character) {
            [void]$builder.Append('   ')
            $index += 3
            $inString = $true
            $tripleString = $true
            $quote = $character
            $escaped = $false
            continue
        }
        if ($character -eq '"' -or $character -eq "'") {
            [void]$builder.Append(' ')
            $index++
            $inString = $true
            $tripleString = $false
            $quote = $character
            $escaped = $false
            continue
        }
        [void]$builder.Append($character)
        $index++
    }
    if ($builder.Length -gt 0 -or $Content.EndsWith("`n")) {
        [void]$lines.Add($builder.ToString())
    }
    return [string[]]$lines.ToArray()
}

function Get-SourceLayer {
    param([string]$RelativePath)

    $normalized = $RelativePath.Replace('\', '/')
    if ($normalized -match '^src/game(?:/|$)') { return 'game' }
    if ($normalized -match '^src/scenarios(?:/|$)') { return 'scenarios' }
    if ($normalized -match '^src/storage(?:/|$)') { return 'storage' }
    if ($normalized -match '^src/ui(?:/|$)') { return 'ui' }
    if ($normalized -match '^src/app(?:/|$)') { return 'app' }
    if ($normalized -match '^src/playthrough(?:/|$)') { return 'playthrough' }
    return $null
}

function Get-RepositoryRelativePath {
    param(
        [string]$RootPath,
        [string]$TargetPath
    )

    # Windows PowerShell 5.1 does not expose the newer .NET relative-path API.
    # Resolve both paths first, then remove the platform-native repository-root
    # prefix without allowing a sibling path such as repo-other to pass as a
    # child of repo. Return one slash-normalized representation on every host.
    $directorySeparators = [char[]]@([IO.Path]::DirectorySeparatorChar, [IO.Path]::AltDirectorySeparatorChar)
    $resolvedRoot = [IO.Path]::GetFullPath($RootPath).TrimEnd($directorySeparators)
    $resolvedTarget = [IO.Path]::GetFullPath($TargetPath)
    $pathComparison = if ([IO.Path]::DirectorySeparatorChar -eq '\') { [StringComparison]::OrdinalIgnoreCase } else { [StringComparison]::Ordinal }
    if ($resolvedTarget.Equals($resolvedRoot, $pathComparison)) {
        return ''
    }
    $rootPrefix = $resolvedRoot + [IO.Path]::DirectorySeparatorChar
    if (-not $resolvedTarget.StartsWith($rootPrefix, $pathComparison)) {
        throw "Target path '$TargetPath' is outside repository root '$RootPath'."
    }
    return $resolvedTarget.Substring($rootPrefix.Length).Replace('\', '/')
}

function Get-ClassNameSymbolTable {
    param([string]$RootPath)

    $symbols = @{}
    foreach ($file in Get-ChildItem (Join-Path $RootPath "src") -Recurse -Filter "*.gd" -ErrorAction SilentlyContinue) {
        $relativePath = Get-RepositoryRelativePath -RootPath $RootPath -TargetPath $file.FullName
        $sourceLayer = Get-SourceLayer $relativePath
        if (-not $sourceLayer) {
            continue
        }
        $lines = Get-SanitizedGdscriptLines -Content ([IO.File]::ReadAllText($file.FullName))
        for ($index = 0; $index -lt $lines.Count; $index++) {
            $match = [regex]::Match($lines[$index], '^\s*class_name\s+([A-Za-z_][A-Za-z0-9_]*)')
            if (-not $match.Success) {
                continue
            }
            $name = $match.Groups[1].Value
            $entry = [pscustomobject]@{
                Name = $name
                RelativePath = $relativePath
                LineNumber = $index + 1
                SourceLayer = $sourceLayer
            }
            if ($symbols.ContainsKey($name)) {
                $symbols[$name] = @($symbols[$name]) + $entry
            } else {
                $symbols[$name] = @($entry)
            }
        }
    }
    return $symbols
}

function Get-SourceDependencyEdges {
    param(
        [string]$FilePath,
        [string]$RelativePath,
        [hashtable]$ClassNameSymbols,
        [string]$ClassNameReferencePattern
    )

    $rawLines = [IO.File]::ReadAllLines($FilePath)
    $lines = Get-SanitizedGdscriptLines -Content ([IO.File]::ReadAllText($FilePath))
    $sourceLayer = Get-SourceLayer $RelativePath
    $lineNumber = 0
    foreach ($code in $lines) {
        $lineNumber++
        $importCode = Remove-GdscriptLineComment $rawLines[$lineNumber - 1]
        foreach ($match in [regex]::Matches($importCode, '\b(preload|load)\s*\(\s*"(res://src/[^"]+)"')) {
            $targetPath = $match.Groups[2].Value.Substring(6).Replace('/', '\')
            $targetLayer = Get-SourceLayer $targetPath
            if ($targetLayer) {
                [pscustomobject]@{
                    RelativePath = $RelativePath
                    LineNumber = $lineNumber
                    TargetPath = $targetPath
                    TargetLayer = $targetLayer
                    Symbol = $match.Groups[1].Value
                    EdgeType = 'path'
                }
            }
        }
        if ([string]::IsNullOrEmpty($ClassNameReferencePattern)) {
            continue
        }
        foreach ($match in [regex]::Matches($code, $ClassNameReferencePattern, [Text.RegularExpressions.RegexOptions]::CultureInvariant)) {
            $symbolName = $match.Value
            $declarations = @($ClassNameSymbols[$symbolName])
            # GDScript requires global class names to be unique.  If a broken
            # checkout contains an ambiguous declaration, do not guess which
            # target the reference resolves to and create a false violation.
            if ($declarations.Count -ne 1) {
                continue
            }
            $target = $declarations[0]
            if ($target.SourceLayer -eq $sourceLayer) {
                continue
            }
            [pscustomobject]@{
                RelativePath = $RelativePath
                LineNumber = $lineNumber
                TargetPath = $target.RelativePath
                TargetLayer = $target.SourceLayer
                Symbol = $symbolName
                EdgeType = 'class_name'
            }
        }
    }
}

$gameFiles = Get-ChildItem (Join-Path $repoRoot "src\game") -Recurse -Filter "*.gd" -ErrorAction SilentlyContinue
$forbiddenPatterns = @(
    @{ Pattern = '\bextends\s+(Node|Control|Node2D|Node3D)\b'; Reason = "simulation classes must not extend Godot nodes" },
    @{ Pattern = '\b(RandomNumberGenerator|randf|randi|randfn|randomize)\b'; Reason = "simulation randomness must go through RealmzRng" },
    @{ Pattern = '\b(Time|FileAccess|DirAccess|ResourceLoader|AudioServer)\b'; Reason = "simulation must not access host time, files, resources, or audio" },
    @{ Pattern = '\b(get_tree|get_node|Engine\.get_)\b'; Reason = "simulation must not access the scene tree or engine singleton" }
)

foreach ($file in $gameFiles) {
    $content = Get-Content -Raw $file.FullName
    foreach ($rule in $forbiddenPatterns) {
        if ($content -match $rule.Pattern) {
            $violations += "$($file.FullName): $($rule.Reason)"
        }
    }
}

# Explicit resource imports and globally registered class_name references are
# the stable, source-level dependency edges in this GDScript project.  Same-
# layer references are allowed.  Cross-layer rules are intentionally narrow:
# they enforce the settled ownership matrix without banning legitimate
# collaborators or relying on line counts.
$dependencyRules = @{
    game = @('scenarios', 'playthrough', 'storage', 'ui', 'app')
    scenarios = @('storage', 'ui', 'app', 'playthrough')
    playthrough = @('storage', 'ui', 'app')
    storage = @('ui', 'app')
    ui = @('storage')
}
$dependencyRoots = @(
    (Join-Path $repoRoot "src\game"),
    (Join-Path $repoRoot "src\scenarios"),
    (Join-Path $repoRoot "src\playthrough"),
    (Join-Path $repoRoot "src\storage"),
    (Join-Path $repoRoot "src\ui"),
    (Join-Path $repoRoot "src\app")
)
$classNameSymbols = Get-ClassNameSymbolTable -RootPath $repoRoot
$uniqueClassNameSymbols = @{}
foreach ($symbolName in $classNameSymbols.Keys) {
    if (@($classNameSymbols[$symbolName]).Count -eq 1) {
        $uniqueClassNameSymbols[$symbolName] = $classNameSymbols[$symbolName]
    }
}

# GameSession owns public dispatch and the final all-or-nothing restore commit;
# construction and validation of a detached restore candidate belong to the
# typed validator. This guards responsibility rather than imposing a line cap.
$gameSessionPath = Join-Path $repoRoot "src\playthrough\session\game_session.gd"
if (Test-Path -LiteralPath $gameSessionPath) {
    $gameSessionContent = [IO.File]::ReadAllText($gameSessionPath)
    if ($gameSessionContent -notmatch '\bSessionRestoreValidator\.validate\s*\(') {
        $violations += "src/playthrough/session/game_session.gd GameSession.restore must delegate candidate validation to SessionRestoreValidator"
    }
    $lineNumber = 0
    foreach ($line in Get-SanitizedGdscriptLines -Content $gameSessionContent) {
        $lineNumber++
        if ($line -match '^\s*(?:static\s+)?func\s+_(?:valid_|party_.*_is_valid|shop_state_is_valid|location_notes_are_valid|journal_messages_are_valid|acquired_player_maps_are_valid)') {
            $violations += "src/playthrough/session/game_session.gd:$lineNumber GameSession must not own restore-validation helpers"
        }
    }
}

# Session continuation coordinators operate on one explicit operation context
# and return an internal typed outcome. They may not regain a private owner
# backchannel or construct the public SessionStep boundary themselves.
$sessionCoordinatorRoot = Join-Path $repoRoot "src\playthrough\coordinators"
foreach ($file in Get-ChildItem $sessionCoordinatorRoot -Filter "session_*_coordinator.gd" -ErrorAction SilentlyContinue) {
    $relativePath = Get-RepositoryRelativePath -RootPath $repoRoot -TargetPath $file.FullName
    $lineNumber = 0
    foreach ($line in Get-SanitizedGdscriptLines -Content ([IO.File]::ReadAllText($file.FullName))) {
        $lineNumber++
        if ($line -match '\b(?:WeakRef|GameSession|SessionStep)\b' -or $line -match '\bfunc\s+_session\s*\(') {
            $violations += "$($relativePath):$lineNumber session coordinators must use the explicit operation context and SessionCoordinatorResult"
        }
        if ($line -match '\b_context\.(?:completed|waiting|failed|rejected|closed)\s*\(') {
            $violations += "$($relativePath):$lineNumber session coordinators must construct outcomes through SessionCoordinatorResult"
        }
    }
}
$coordinatorContextPath = Join-Path $repoRoot "src\playthrough\session\session_context.gd"
if (Test-Path -LiteralPath $coordinatorContextPath) {
    $contextContent = [IO.File]::ReadAllText($coordinatorContextPath)
    if ($contextContent -match '(?m)^var\s+view_revision\b') {
        $violations += "src/playthrough/session/session_context.gd request identity must use named revision capabilities instead of a writable revision field"
    }
    if ($contextContent -match '(?m)^(?:static\s+)?func\s+(?:completed|waiting|failed|rejected|closed)\s*\(') {
        $violations += "src/playthrough/session/session_context.gd SessionCoordinatorResult must own the coordinator outcome vocabulary"
    }
}

# Carried-item ownership and wearable equipment are separate rule concepts.
# Production callers address EquipmentRules directly instead of rebuilding an
# InventoryRules forwarding facade around equipment admission or projection.
$inventoryRulesPath = Join-Path $repoRoot "src\game\inventory\inventory_rules.gd"
$equipmentRulesPath = Join-Path $repoRoot "src\game\inventory\equipment_rules.gd"
$equipmentMethodPattern = '(?:combat_equipment|has_equipped_scroll_case|classic_equip_probe|classic_unequip_probe|equip_classic|unequip_classic|can_equip|equip)'
if (-not (Test-Path -LiteralPath $equipmentRulesPath)) {
    $violations += "src/game/inventory/equipment_rules.gd must own wearable equipment rules"
}
if (Test-Path -LiteralPath $inventoryRulesPath) {
    $inventoryRulesContent = [IO.File]::ReadAllText($inventoryRulesPath)
    if ($inventoryRulesContent -match ('(?m)^(?:static\s+)?func\s+' + $equipmentMethodPattern + '\s*\(')) {
        $violations += "src/game/inventory/inventory_rules.gd must not forward or re-own wearable equipment rules"
    }
}
foreach ($rootPath in @("src\game", "src\playthrough", "src\scenarios", "src\storage", "src\ui", "src\app")) {
    foreach ($file in Get-ChildItem (Join-Path $repoRoot $rootPath) -Recurse -Filter "*.gd" -ErrorAction SilentlyContinue) {
        $relativePath = Get-RepositoryRelativePath -RootPath $repoRoot -TargetPath $file.FullName
        $lineNumber = 0
        foreach ($line in Get-SanitizedGdscriptLines -Content ([IO.File]::ReadAllText($file.FullName))) {
            $lineNumber++
            if ($line -match ('\.inventory\.' + $equipmentMethodPattern + '\s*\(')) {
                $violations += "$($relativePath):$lineNumber production callers must address EquipmentRules for wearable equipment behavior"
            }
        }
    }
}

# WorldState is a save aggregate, not a broad forwarding API. Physical map
# changes, encounter triggers, and exploration memory have direct state owners.
$worldStatePath = Join-Path $repoRoot "src\game\world\world_state.gd"
$worldCollaboratorPaths = @(
    "src\game\world\world_topology_state.gd",
    "src\game\world\world_trigger_state.gd",
    "src\game\world\world_exploration_state.gd",
    "src\game\world\classic_land_tile_rules.gd"
)
foreach ($relativePath in $worldCollaboratorPaths) {
    if (-not (Test-Path -LiteralPath (Join-Path $repoRoot $relativePath))) {
        $violations += "$($relativePath -replace '\\','/') must own its named world-state responsibility"
    }
}
$worldAggregateMethodPattern = '(?:terrain_for|replace_terrain|has_terrain_override|classic_tile_for|set_boat_present|boat_presence_state|boat_presence_overrides|open_door|door_is_open|discover_secret|secret_is_discovered|topology_revision|set_map_darkness|map_is_dark|set_map_landlook|map_landlook|map_landlook_for|disable_trigger|trigger_is_disabled|set_trigger_chance|trigger_chance|trigger_chance_is_overridden|set_random_region|random_region|random_region_ids_at|has_random_region_at|random_region_bounds_revision|exploration_revision|acquire_map|has_map|acquired_map_ids|upsert_location_note|remove_location_note|location_note_at|location_notes|location_notes_for_kind|next_location_note_ordinal|mark_visited|was_visited|visited_coordinates|mark_seen|mark_seen_many|was_seen|seen_coordinates)'
if (Test-Path -LiteralPath $worldStatePath) {
    $worldStateContent = [IO.File]::ReadAllText($worldStatePath)
    if ($worldStateContent -match ('(?m)^(?:static\s+)?func\s+' + $worldAggregateMethodPattern + '\s*\(')) {
        $violations += "src/game/world/world_state.gd must not forward or re-own topology, trigger, or exploration behavior"
    }
}
foreach ($rootPath in @("src\game", "src\playthrough", "src\scenarios", "src\storage", "src\ui", "src\app")) {
    foreach ($file in Get-ChildItem (Join-Path $repoRoot $rootPath) -Recurse -Filter "*.gd" -ErrorAction SilentlyContinue) {
        $relativePath = Get-RepositoryRelativePath -RootPath $repoRoot -TargetPath $file.FullName
        $lineNumber = 0
        foreach ($line in Get-SanitizedGdscriptLines -Content ([IO.File]::ReadAllText($file.FullName))) {
            $lineNumber++
            if ($line -match ('\.world\.' + $worldAggregateMethodPattern + '\s*\(')) {
                $violations += "$($relativePath):$lineNumber production callers must address the direct WorldState collaborator"
            }
            if ($line -match '\bWorldState\.(?:normalized_classic_land_tile|classic_special_land_overlay)\s*\(') {
                $violations += "$($relativePath):$lineNumber ClassicLandTileRules must own Classic land tile decoding"
            }
        }
    }
}

# Party setup is a composed presentation workspace. Inspection, assembly, and
# creation may share explicit setup state, but they may not inherit behavior
# from one another or turn the public facade back into the old behavior chain.
$partySetupControllerPaths = @(
    "src\ui\setup\party_setup_inspection_controller.gd",
    "src\ui\setup\party_setup_assembly_controller.gd",
    "src\ui\setup\party_setup_character_creation_controller.gd",
    "src\ui\setup\campaign_party_setup_controller.gd"
)
foreach ($relativePath in $partySetupControllerPaths) {
    $path = Join-Path $repoRoot $relativePath
    if (-not (Test-Path -LiteralPath $path)) {
        continue
    }
    $content = [IO.File]::ReadAllText($path)
    if ($content -match 'extends\s+"res://src/ui/setup/(?:campaign_party_setup_state|party_setup_inspection_controller|party_setup_assembly_controller|party_setup_character_creation_controller)\.gd"') {
        $violations += "$($relativePath -replace '\\','/') party setup controllers must compose responsibility collaborators instead of inheriting their behavior"
    }
}
$classNameReferencePattern = ''
if ($uniqueClassNameSymbols.Count -gt 0) {
    $escapedNames = @($uniqueClassNameSymbols.Keys | Sort-Object { $_.Length } -Descending | ForEach-Object { [regex]::Escape($_) })
    $classNameReferencePattern = '(?<![A-Za-z0-9_])(?:' + ($escapedNames -join '|') + ')(?![A-Za-z0-9_])'
}
foreach ($rootPath in $dependencyRoots) {
    if (-not (Test-Path -LiteralPath $rootPath)) {
        continue
    }
    foreach ($file in Get-ChildItem -LiteralPath $rootPath -Recurse -Filter "*.gd") {
        $relativePath = Get-RepositoryRelativePath -RootPath $repoRoot -TargetPath $file.FullName
        $sourceLayer = Get-SourceLayer $relativePath
        if (-not $sourceLayer -or -not $dependencyRules.ContainsKey($sourceLayer)) {
            continue
        }
        foreach ($edge in Get-SourceDependencyEdges -FilePath $file.FullName -RelativePath $relativePath -ClassNameSymbols $uniqueClassNameSymbols -ClassNameReferencePattern $classNameReferencePattern) {
            if ($dependencyRules[$sourceLayer] -contains $edge.TargetLayer) {
                if ($edge.EdgeType -eq 'class_name') {
                    $violations += "$($edge.RelativePath):$($edge.LineNumber) $sourceLayer may not reference globally registered symbol $($edge.Symbol) from $($edge.TargetLayer) ($($edge.TargetPath))"
                } else {
                    $violations += "$($edge.RelativePath):$($edge.LineNumber) $sourceLayer may not use $($edge.Symbol) to import $($edge.TargetLayer) ($($edge.TargetPath))"
                }
            }
        }
    }
}

# PackageRepository is an storage coordinator.  Domain construction is
# owned by its package collaborators, so keep this check tied to explicit game
# class names and function declarations rather than banning generic words such
# as "construct" in comments or diagnostics.
$packageRepositoryPath = Join-Path $repoRoot "src\storage\packages\package_repository.gd"
if (Test-Path -LiteralPath $packageRepositoryPath) {
    $gameClassNames = @{}
    foreach ($gameFile in Get-ChildItem (Join-Path $repoRoot "src\game") -Recurse -Filter "*.gd" -ErrorAction SilentlyContinue) {
        foreach ($line in Get-Content -LiteralPath $gameFile.FullName) {
            $code = Remove-GdscriptLineComment $line
            if ($code -match '^\s*class_name\s+([A-Za-z_][A-Za-z0-9_]*)') {
                $gameClassNames[$Matches[1]] = $true
            }
        }
    }
    $lineNumber = 0
    foreach ($line in Get-Content -LiteralPath $packageRepositoryPath) {
        $lineNumber++
        $code = Remove-GdscriptLineComment $line
        if ($code -match '^\s*func\s+_construct_[A-Za-z0-9_]*\s*\(') {
            $violations += "src/storage/packages/package_repository.gd:$lineNumber PackageRepository must not own domain construction functions"
        }
        foreach ($gameClassName in $gameClassNames.Keys) {
            if ($code -match "\b$([regex]::Escape($gameClassName))\s*\.\s*new\s*\(") {
                $violations += "src/storage/packages/package_repository.gd:$lineNumber PackageRepository must not directly construct game domain type $gameClassName"
            }
        }
    }
}

# App-facing prepared package values expose the game media abstraction, never
# an storage decoder/catalog implementation. Presentation routing has a
# similarly narrow responsibility: it may mount workspaces and navigate among
# them, while route-local controllers and rendering belong to the workspace
# presenter mounted beneath the scene's explicit hosts.
$preparedPackagePath = Join-Path $repoRoot "src\app\startup\prepared_package.gd"
if (Test-Path -LiteralPath $preparedPackagePath) {
    $preparedPackageContent = [IO.File]::ReadAllText($preparedPackagePath)
    if ($preparedPackageContent -match '\bPackageMediaCatalog\b') {
        $violations += "src/app/startup/prepared_package.gd app view models must expose MediaSource instead of the storage PackageMediaCatalog"
    }
}

$screenNavigatorPath = Join-Path $repoRoot "src\ui\shell\screen_navigator.gd"
if (Test-Path -LiteralPath $screenNavigatorPath) {
    $navigatorLines = Get-SanitizedGdscriptLines -Content ([IO.File]::ReadAllText($screenNavigatorPath))
    $routeControllerPattern = '\b(?:Character|Inventory|Services|MapsJournal|Spells|System)ScreenController\b'
    for ($index = 0; $index -lt $navigatorLines.Count; $index++) {
        $code = $navigatorLines[$index]
        $lineNumber = $index + 1
        if ($code -match $routeControllerPattern) {
            $violations += "src/ui/shell/screen_navigator.gd:$lineNumber ScreenNavigator must not construct or call route-domain workspace controllers"
        }
        if ($code -match '^\s*func\s+_render_(?:characters|vault|inventory|spells|services|journal|system)\s*\(') {
            $violations += "src/ui/shell/screen_navigator.gd:$lineNumber ScreenNavigator must not render route-domain content"
        }
        if ($code -match '\bsetup_controller\.attach\s*\(\s*self\s*\)') {
            $violations += "src/ui/shell/screen_navigator.gd:$lineNumber setup overlays must attach to the shell-owned OverlayHost, not the router"
        }
    }
}

$gameShellScenePath = Join-Path $repoRoot "src\ui\shell\game_shell.tscn"
$screenNavigatorScenePath = Join-Path $repoRoot "src\ui\shell\screen_navigator.tscn"
if (Test-Path -LiteralPath $gameShellScenePath) {
    $gameShellScene = [IO.File]::ReadAllText($gameShellScenePath)
    if ($gameShellScene -notmatch '\[ext_resource\s+type="PackedScene"\s+path="res://src/ui/shell/screen_navigator\.tscn"') {
        $violations += "src/ui/shell/game_shell.tscn must instance the authored src/ui/shell/screen_navigator.tscn presentation host"
    }
}
if (Test-Path -LiteralPath $screenNavigatorScenePath) {
    $screenNavigatorScene = [IO.File]::ReadAllText($screenNavigatorScenePath)
    foreach ($requiredHost in @('WorkspaceHost', 'OverlayHost')) {
        if ($screenNavigatorScene -notmatch ('\[node\s+name="' + [regex]::Escape($requiredHost) + '"\s+type="Control"\s+parent="\."\]')) {
            $violations += "src/ui/shell/screen_navigator.tscn must provide $requiredHost as an explicit scene-owned presentation host"
        }
    }
} else {
    $violations += "src/ui/shell/screen_navigator.tscn must own the navigation presentation hosts"
}

# Typed request bodies may become dictionaries only at their wire serializer or
# when a detached domain event is deliberately published. Live game, scenario,
# and presentation behavior must consume the typed request variants directly.
$protocolRoots = @("src\game", "src\scenarios", "src\ui")
foreach ($protocolRoot in $protocolRoots) {
    $rootPath = Join-Path $repoRoot $protocolRoot
    foreach ($file in Get-ChildItem $rootPath -Recurse -Filter "*.gd" -ErrorAction SilentlyContinue) {
        $relativePath = Get-RepositoryRelativePath -RootPath $repoRoot -TargetPath $file.FullName
        $lineNumber = 0
        foreach ($line in Get-Content $file.FullName) {
            $lineNumber++
            if ($line -notmatch '\bbody\.to_data\(\)') {
                continue
            }
            $isWireSerializer = ($relativePath -eq "src/game/shared/interactions/interaction_request.gd" -and $line -match '"payload": body\.to_data\(\)') -or
                ($relativePath -eq "src/scenarios/runtime/scenario_runtime_continuation.gd" -and $line -match 'continuation_data\s*:=\s*body\.to_data\(\)')
            $isDetachedEvent = $relativePath -eq "src/scenarios/classic/operations/classic_battle_reward_operations.gd" -and $line -match 'DomainEvent\.new\(&"reward_wealth_transferred", body\.to_data\(\)\)'
            if (-not $isWireSerializer -and -not $isDetachedEvent) {
                $violations += "$($file.FullName):$lineNumber interaction request bodies must remain typed outside codecs and detached event serialization"
            }
        }
    }
}

# Player interactions cross presentation and application boundaries as typed
# bodies or explicit presentation-only signals.  These retired identifiers
# represent the old dictionary command bus; reintroducing any of them would
# silently reopen an unvalidated live protocol even though dictionary-backed
# widget configuration and detached DomainEvent payloads remain legitimate.
$retiredLiveProtocolPatterns = @(
    @{ Pattern = '\bsignal\s+payload_submitted\b'; Reason = "interaction components must emit typed response bodies" },
    @{ Pattern = '\bsignal\s+presentation_action_requested\b'; Reason = "presentation-only commands require explicit typed signals" },
    @{ Pattern = '\bsignal\s+tactical_action_requested\b'; Reason = "battlefield actions must emit InteractionResponse.CombatBody" },
    @{ Pattern = '\bsubmit_active_payload\s*\('; Reason = "InteractionPresenter accepts typed response bodies" },
    @{ Pattern = '\bcombat_payload_with_preferences\s*\('; Reason = "combat preferences apply to InteractionResponse.CombatBody" },
    @{ Pattern = '\bcommitted_payload\s*\('; Reason = "combat targeting commits a typed CombatBody" },
    @{ Pattern = '\bselection_data\s*\('; Reason = "combat targeting state must remain typed" }
)
foreach ($protocolRoot in @("src\ui", "src\app")) {
    $rootPath = Join-Path $repoRoot $protocolRoot
    foreach ($file in Get-ChildItem $rootPath -Recurse -Filter "*.gd" -ErrorAction SilentlyContinue) {
        $relativePath = Get-RepositoryRelativePath -RootPath $repoRoot -TargetPath $file.FullName
        $lineNumber = 0
        foreach ($line in Get-SanitizedGdscriptLines -Content ([IO.File]::ReadAllText($file.FullName))) {
            $lineNumber++
            foreach ($rule in $retiredLiveProtocolPatterns) {
                if ($line -match $rule.Pattern) {
                    $violations += "$($relativePath):$lineNumber $($rule.Reason)"
                }
            }
        }
    }
}

# VM execution provenance is a closed typed protocol. Dictionaries exist only
# inside ScenarioExecutionContextCodec; frames, directives, handlers, and
# runtime calls must not reopen that boundary with an arbitrary context.
$scenarioRoot = Join-Path $repoRoot "src\scenarios"
foreach ($file in Get-ChildItem $scenarioRoot -Recurse -Filter "*.gd" -ErrorAction SilentlyContinue) {
    $relativePath = Get-RepositoryRelativePath -RootPath $repoRoot -TargetPath $file.FullName
    $lineNumber = 0
    foreach ($line in Get-SanitizedGdscriptLines -Content ([IO.File]::ReadAllText($file.FullName))) {
        $lineNumber++
        if ($line -match '\b_?context\s*:\s*Dictionary\b') {
            $violations += "$($relativePath):$lineNumber scenario execution context must use ScenarioExecutionContext outside its strict wire codec"
        }
    }
}

if ($violations.Count -gt 0) {
    $violations | ForEach-Object { Write-Error $_ }
    exit 1
}

Write-Host "Architecture dependency matrix, coordinator boundaries, and typed request/execution protocols verified."
