$ErrorActionPreference = "Stop"
$repoRoot = Split-Path -Parent $PSScriptRoot
$violations = @()

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

Write-Host "Architecture boundaries and typed request protocol verified across core, scenario, and presentation scripts."
