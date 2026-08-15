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

function Get-SourceDependencyEdges {
    param(
        [string]$FilePath,
        [string]$RelativePath
    )

    $lineNumber = 0
    foreach ($line in Get-Content -LiteralPath $FilePath) {
        $lineNumber++
        $code = Remove-GdscriptLineComment $line
        foreach ($match in [regex]::Matches($code, '\b(?:preload|load)\s*\(\s*"(res://src/[^"]+)"')) {
            $targetPath = $match.Groups[1].Value.Substring(6).Replace('/', '\')
            $targetLayer = Get-SourceLayer $targetPath
            if ($targetLayer) {
                [pscustomobject]@{
                    RelativePath = $RelativePath
                    LineNumber = $lineNumber
                    TargetPath = $targetPath
                    TargetLayer = $targetLayer
                }
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

# Explicit resource imports are the stable, source-level dependency edges in
# this GDScript project.  Same-layer imports are allowed.  Cross-layer rules
# are intentionally narrow: they enforce the settled ownership matrix without
# banning legitimate collaborators or relying on line counts.
$dependencyRules = @{
    core = @('scenario', 'infrastructure', 'presentation', 'app')
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
foreach ($rootPath in $dependencyRoots) {
    if (-not (Test-Path -LiteralPath $rootPath)) {
        continue
    }
    foreach ($file in Get-ChildItem -LiteralPath $rootPath -Recurse -Filter "*.gd") {
        $relativePath = [IO.Path]::GetRelativePath($repoRoot, $file.FullName)
        $sourceLayer = Get-SourceLayer $relativePath
        if (-not $sourceLayer -or -not $dependencyRules.ContainsKey($sourceLayer)) {
            continue
        }
        foreach ($edge in Get-SourceDependencyEdges -FilePath $file.FullName -RelativePath $relativePath) {
            if ($dependencyRules[$sourceLayer] -contains $edge.TargetLayer) {
                $violations += "$($edge.RelativePath):$($edge.LineNumber) $sourceLayer may not import $($edge.TargetLayer) ($($edge.TargetPath))"
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
        $relativePath = [IO.Path]::GetRelativePath($repoRoot, $file.FullName)
        $lineNumber = 0
        foreach ($line in Get-Content $file.FullName) {
            $lineNumber++
            if ($line -notmatch '\bbody\.to_data\(\)') {
                continue
            }
            $isWireSerializer = $relativePath -eq "src\core\session\interaction_request.gd" -and $line -match '"payload": body\.to_data\(\)'
            $isDetachedEvent = $relativePath -eq "src\scenario\runtime\realmz_runtime_api.gd" -and $line -match 'DomainEvent\.new\(&"reward_wealth_transferred", body\.to_data\(\)\)'
            if (-not $isWireSerializer -and -not $isDetachedEvent) {
                $violations += "$($file.FullName):$lineNumber interaction request bodies must remain typed outside codecs and detached event serialization"
            }
        }
    }
}

if ($violations.Count -gt 0) {
    $violations | ForEach-Object { Write-Error $_ }
    exit 1
}

Write-Host "Architecture dependency matrix, PackageRepository coordinator boundary, and typed request protocol verified."
