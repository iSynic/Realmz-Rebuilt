$ErrorActionPreference = "Stop"
$repoRoot = Split-Path -Parent $PSScriptRoot
$presetPath = Join-Path $repoRoot "export_presets.cfg"
$addonConfigPath = Join-Path $repoRoot "addons\godot_mcp\plugin.cfg"

if (-not (Test-Path -LiteralPath $presetPath)) {
    throw "export_presets.cfg is required."
}

$preset = Get-Content -Raw -LiteralPath $presetPath
foreach ($requiredExclusion in @("addons/godot_mcp/**", "tests/**", "artifacts/**", ".references/**")) {
    if (-not $preset.Contains($requiredExclusion)) {
        throw "Release exports must exclude $requiredExclusion"
    }
}

Write-Host "Release export exclusions verified."

if (-not (Test-Path -LiteralPath $addonConfigPath)) {
    throw "The vendored Godot MCP Pro addon is missing."
}
$addonConfig = Get-Content -Raw -LiteralPath $addonConfigPath
if ($addonConfig -notmatch 'version="1\.16\.0"') {
    throw "Godot MCP Pro must remain pinned to addon version 1.16.0."
}

Write-Host "Godot MCP Pro addon version verified."
