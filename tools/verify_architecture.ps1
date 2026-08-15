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
    # Resolve both paths first, then remove the
    # repository-root prefix without allowing a sibling path such as
    # C:\repo-other to pass as a child of C:\repo.
    $resolvedRoot = [IO.Path]::GetFullPath($RootPath).TrimEnd('\')
    $resolvedTarget = [IO.Path]::GetFullPath($TargetPath)
    if ($resolvedTarget.Equals($resolvedRoot, [StringComparison]::OrdinalIgnoreCase)) {
        return ''
    }
    $rootPrefix = $resolvedRoot + '\'
    if (-not $resolvedTarget.StartsWith($rootPrefix, [StringComparison]::OrdinalIgnoreCase)) {
        throw "Target path '$TargetPath' is outside repository root '$RootPath'."
    }
    return $resolvedTarget.Substring($rootPrefix.Length).Replace('/', '\')
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
    infrastructure = @('presentation', 'app')
    presentation = @('infrastructure')
}
$dependencyRoots = @(
    (Join-Path $repoRoot "src\core"),
    (Join-Path $repoRoot "src\scenario"),
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
            $isWireSerializer = ($relativePath -eq "src\core\session\interaction_request.gd" -and $line -match '"payload": body\.to_data\(\)') -or
                ($relativePath -eq "src\scenario\runtime\scenario_runtime_continuation.gd" -and $line -match 'continuation_data\s*:=\s*body\.to_data\(\)')
            $isDetachedEvent = $relativePath -eq "src\scenario\runtime\operations\classic_battle_reward_operations.gd" -and $line -match 'DomainEvent\.new\(&"reward_wealth_transferred", body\.to_data\(\)\)'
            if (-not $isWireSerializer -and -not $isDetachedEvent) {
                $violations += "$($file.FullName):$lineNumber interaction request bodies must remain typed outside codecs and detached event serialization"
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
