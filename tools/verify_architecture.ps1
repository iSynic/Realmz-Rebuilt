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
    if ($normalized -match '^src/core(?:/|$)') { return 'core' }
    if ($normalized -match '^src/scenario(?:/|$)') { return 'scenario' }
    if ($normalized -match '^src/infrastructure(?:/|$)') { return 'infrastructure' }
    if ($normalized -match '^src/presentation(?:/|$)') { return 'presentation' }
    if ($normalized -match '^src/app(?:/|$)') { return 'app' }
    if ($normalized -match '^src/session(?:/|$)') { return 'session' }
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

$coreFiles = Get-ChildItem (Join-Path $repoRoot "src\core") -Recurse -Filter "*.gd" -ErrorAction SilentlyContinue
$forbiddenPatterns = @(
    @{ Pattern = '\bextends\s+(Node|Control|Node2D|Node3D)\b'; Reason = "simulation classes must not extend Godot nodes" },
    @{ Pattern = '\b(RandomNumberGenerator|randf|randi|randfn|randomize)\b'; Reason = "simulation randomness must go through RealmzRng" },
    @{ Pattern = '\b(Time|FileAccess|DirAccess|ResourceLoader|AudioServer)\b'; Reason = "simulation must not access host time, files, resources, or audio" },
    @{ Pattern = '\b(get_tree|get_node|Engine\.get_)\b'; Reason = "simulation must not access the scene tree or engine singleton" }
)

foreach ($file in $coreFiles) {
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
    core = @('scenario', 'session', 'infrastructure', 'presentation', 'app')
    scenario = @('infrastructure', 'presentation', 'app', 'session')
    session = @('infrastructure', 'presentation', 'app')
    infrastructure = @('presentation', 'app')
    presentation = @('infrastructure')
}
$dependencyRoots = @(
    (Join-Path $repoRoot "src\core"),
    (Join-Path $repoRoot "src\scenario"),
    (Join-Path $repoRoot "src\session"),
    (Join-Path $repoRoot "src\infrastructure"),
    (Join-Path $repoRoot "src\presentation"),
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
$gameSessionPath = Join-Path $repoRoot "src\session\game_session.gd"
if (Test-Path -LiteralPath $gameSessionPath) {
    $gameSessionContent = [IO.File]::ReadAllText($gameSessionPath)
    if ($gameSessionContent -notmatch '\bSessionRestoreValidator\.validate\s*\(') {
        $violations += "src/session/game_session.gd GameSession.restore must delegate candidate validation to SessionRestoreValidator"
    }
    $lineNumber = 0
    foreach ($line in Get-SanitizedGdscriptLines -Content $gameSessionContent) {
        $lineNumber++
        if ($line -match '^\s*(?:static\s+)?func\s+_(?:valid_|party_.*_is_valid|shop_state_is_valid|location_notes_are_valid|journal_messages_are_valid|acquired_player_maps_are_valid)') {
            $violations += "src/session/game_session.gd:$lineNumber GameSession must not own restore-validation helpers"
        }
    }
}

# Session continuation coordinators operate on one explicit operation context
# and return an internal typed outcome. They may not regain a private owner
# backchannel or construct the public SessionStep boundary themselves.
$sessionCoordinatorRoot = Join-Path $repoRoot "src\session\coordinators"
foreach ($file in Get-ChildItem $sessionCoordinatorRoot -Filter "session_*_coordinator.gd" -ErrorAction SilentlyContinue) {
    $relativePath = Get-RepositoryRelativePath -RootPath $repoRoot -TargetPath $file.FullName
    $lineNumber = 0
    foreach ($line in Get-SanitizedGdscriptLines -Content ([IO.File]::ReadAllText($file.FullName))) {
        $lineNumber++
        if ($line -match '\b(?:WeakRef|GameSession|SessionStep)\b' -or $line -match '\bfunc\s+_session\s*\(') {
            $violations += "$($relativePath):$lineNumber session coordinators must use the explicit operation context and SessionCoordinatorResult"
        }
    }
}
$coordinatorContextPath = Join-Path $sessionCoordinatorRoot "session_coordinator_context.gd"
if (Test-Path -LiteralPath $coordinatorContextPath) {
    $contextContent = [IO.File]::ReadAllText($coordinatorContextPath)
    if ($contextContent -match '(?m)^var\s+view_revision\b') {
        $violations += "src/session/coordinators/session_coordinator_context.gd request identity must use named revision capabilities instead of a writable revision field"
    }
}

# Party setup is a composed presentation workspace. Inspection, assembly, and
# creation may share explicit setup state, but they may not inherit behavior
# from one another or turn the public facade back into the old behavior chain.
$partySetupControllerPaths = @(
    "src\presentation\controllers\party_setup_inspection_controller.gd",
    "src\presentation\controllers\party_setup_assembly_controller.gd",
    "src\presentation\controllers\party_setup_character_creation_controller.gd",
    "src\presentation\controllers\campaign_party_setup_controller.gd"
)
foreach ($relativePath in $partySetupControllerPaths) {
    $path = Join-Path $repoRoot $relativePath
    if (-not (Test-Path -LiteralPath $path)) {
        continue
    }
    $content = [IO.File]::ReadAllText($path)
    if ($content -match 'extends\s+"res://src/presentation/controllers/(?:campaign_party_setup_state|party_setup_inspection_controller|party_setup_assembly_controller|party_setup_character_creation_controller)\.gd"') {
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

# PackageRepository is an infrastructure coordinator.  Domain construction is
# owned by its package collaborators, so keep this check tied to explicit core
# class names and function declarations rather than banning generic words such
# as "construct" in comments or diagnostics.
$packageRepositoryPath = Join-Path $repoRoot "src\infrastructure\packages\package_repository.gd"
if (Test-Path -LiteralPath $packageRepositoryPath) {
    $coreClassNames = @{}
    foreach ($coreFile in Get-ChildItem (Join-Path $repoRoot "src\core") -Recurse -Filter "*.gd" -ErrorAction SilentlyContinue) {
        foreach ($line in Get-Content -LiteralPath $coreFile.FullName) {
            $code = Remove-GdscriptLineComment $line
            if ($code -match '^\s*class_name\s+([A-Za-z_][A-Za-z0-9_]*)') {
                $coreClassNames[$Matches[1]] = $true
            }
        }
    }
    $lineNumber = 0
    foreach ($line in Get-Content -LiteralPath $packageRepositoryPath) {
        $lineNumber++
        $code = Remove-GdscriptLineComment $line
        if ($code -match '^\s*func\s+_construct_[A-Za-z0-9_]*\s*\(') {
            $violations += "src/infrastructure/packages/package_repository.gd:$lineNumber PackageRepository must not own domain construction functions"
        }
        foreach ($coreClassName in $coreClassNames.Keys) {
            if ($code -match "\b$([regex]::Escape($coreClassName))\s*\.\s*new\s*\(") {
                $violations += "src/infrastructure/packages/package_repository.gd:$lineNumber PackageRepository must not directly construct core domain type $coreClassName"
            }
        }
    }
}

# App-facing prepared package values expose the core media abstraction, never
# an infrastructure decoder/catalog implementation. Presentation routing has a
# similarly narrow responsibility: it may mount workspaces and navigate among
# them, while route-local controllers and rendering belong to the workspace
# presenter mounted beneath the scene's explicit hosts.
$preparedPackagePath = Join-Path $repoRoot "src\app\view\prepared_package.gd"
if (Test-Path -LiteralPath $preparedPackagePath) {
    $preparedPackageContent = [IO.File]::ReadAllText($preparedPackagePath)
    if ($preparedPackageContent -match '\bPackageMediaCatalog\b') {
        $violations += "src/app/view/prepared_package.gd app view models must expose MediaSource instead of the infrastructure PackageMediaCatalog"
    }
}

$classicRouterPath = Join-Path $repoRoot "src\presentation\classic_screen_router.gd"
if (Test-Path -LiteralPath $classicRouterPath) {
    $routerLines = Get-SanitizedGdscriptLines -Content ([IO.File]::ReadAllText($classicRouterPath))
    $routeControllerPattern = '\b(?:Character|Inventory|Services|MapsJournal|Spells|System)WorkspaceController\b'
    for ($index = 0; $index -lt $routerLines.Count; $index++) {
        $code = $routerLines[$index]
        $lineNumber = $index + 1
        if ($code -match $routeControllerPattern) {
            $violations += "src/presentation/classic_screen_router.gd:$lineNumber ClassicScreenRouter must not construct or call route-domain workspace controllers"
        }
        if ($code -match '^\s*func\s+_render_(?:characters|vault|inventory|spells|services|journal|system)\s*\(') {
            $violations += "src/presentation/classic_screen_router.gd:$lineNumber ClassicScreenRouter must not render route-domain content"
        }
        if ($code -match '\bsetup_controller\.attach\s*\(\s*self\s*\)') {
            $violations += "src/presentation/classic_screen_router.gd:$lineNumber setup overlays must attach to the shell-owned OverlayHost, not the router"
        }
    }
}

$classicShellScenePath = Join-Path $repoRoot "src\presentation\classic_application_shell.tscn"
if (Test-Path -LiteralPath $classicShellScenePath) {
    $classicShellScene = [IO.File]::ReadAllText($classicShellScenePath)
    foreach ($requiredHost in @('WorkspaceHost', 'OverlayHost')) {
        if ($classicShellScene -notmatch ('\[node\s+name="' + [regex]::Escape($requiredHost) + '"\s+type="Control"\s+parent="ScreenRouter"\]')) {
            $violations += "src/presentation/classic_application_shell.tscn must provide ScreenRouter/$requiredHost as an explicit scene-owned presentation host"
        }
    }
}

# Typed request bodies may become dictionaries only at their wire serializer or
# when a detached domain event is deliberately published. Live core, scenario,
# and presentation behavior must consume the typed request variants directly.
$protocolRoots = @("src\core", "src\scenario", "src\presentation")
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
            $isWireSerializer = ($relativePath -eq "src/core/session/interaction_request.gd" -and $line -match '"payload": body\.to_data\(\)') -or
                ($relativePath -eq "src/scenario/runtime/scenario_runtime_continuation.gd" -and $line -match 'continuation_data\s*:=\s*body\.to_data\(\)')
            $isDetachedEvent = $relativePath -eq "src/scenario/runtime/operations/classic_battle_reward_operations.gd" -and $line -match 'DomainEvent\.new\(&"reward_wealth_transferred", body\.to_data\(\)\)'
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
foreach ($protocolRoot in @("src\presentation", "src\app")) {
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

# VM execution provenance is a closed typed protocol.  Dictionaries exist only
# at ScenarioExecutionContext.to_data/from_data; frames, directives, handlers,
# and runtime calls must not reopen that boundary with an arbitrary context.
$scenarioRoot = Join-Path $repoRoot "src\scenario"
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
