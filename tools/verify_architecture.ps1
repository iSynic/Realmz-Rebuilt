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

if ($violations.Count -gt 0) {
    $violations | ForEach-Object { Write-Error $_ }
    exit 1
}

Write-Host "Architecture boundaries verified across $($coreFiles.Count) core scripts."
