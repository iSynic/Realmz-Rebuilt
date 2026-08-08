$ErrorActionPreference = "Stop"
$repoRoot = Split-Path -Parent $PSScriptRoot
$presetPath = Join-Path $repoRoot "export_presets.cfg"
$projectPath = Join-Path $repoRoot "project.godot"
$addonConfigPath = Join-Path $repoRoot "addons\godot_mcp\plugin.cfg"
$schemaPath = Join-Path $repoRoot "contracts\realmz2\realmz2-package.schema.json"
$schemaHashPath = Join-Path $repoRoot "contracts\realmz2\realmz2-package.schema.sha256"
$fixtureRoot = Join-Path $repoRoot "tests\fixtures\packages"
$fixtureManifestPath = Join-Path $fixtureRoot "fixture-provenance.json"

if (-not (Test-Path -LiteralPath $presetPath)) {
    throw "export_presets.cfg is required."
}

$preset = Get-Content -Raw -LiteralPath $presetPath
$presetSections = [regex]::Matches($preset, '(?ms)^\[preset\.\d+\]\s*(.*?)(?=^\[preset\.\d+(?:\.options)?\]|\z)')
$expectedPresets = [ordered]@{
    "Windows Desktop" = "Windows Desktop"
    "Linux" = "Linux"
    "macOS" = "macOS"
}
foreach ($expected in $expectedPresets.GetEnumerator()) {
    $section = $presetSections | Where-Object { $_.Groups[1].Value -match ('(?m)^name="' + [regex]::Escape($expected.Key) + '"$') } | Select-Object -First 1
    if ($null -eq $section) {
        throw "Missing release export preset $($expected.Key)."
    }
    $body = $section.Groups[1].Value
    if ($body -notmatch ('(?m)^platform="' + [regex]::Escape($expected.Value) + '"$') -or $body -notmatch '(?m)^script_export_mode=2$') {
        throw "Release preset $($expected.Key) must target $($expected.Value) with compiled script export."
    }
    foreach ($requiredExclusion in @("addons/godot_mcp/**", "tests/**", "tools/**", "docs/**", "contracts/**", "artifacts/**", ".references/**", ".github/**", ".mcp.json", "AGENTS.md", "README.md")) {
        if (-not $body.Contains($requiredExclusion)) {
            throw "Release preset $($expected.Key) must exclude $requiredExclusion"
        }
    }
}

$macOptions = [regex]::Match($preset, '(?ms)^\[preset\.2\.options\]\s*(.*?)(?=^\[preset\.\d+|\z)').Groups[1].Value
if ($macOptions -notmatch '(?m)^binary_format/architecture="universal"$' -or $macOptions -notmatch '(?m)^texture_format/etc2_astc=true$') {
    throw "The universal macOS release preset must enable ETC2/ASTC texture import."
}
$projectSettings = Get-Content -Raw -LiteralPath $projectPath
if ($projectSettings -notmatch '(?m)^textures/vram_compression/import_etc2_astc=true$') {
    throw "The project must import ETC2/ASTC textures for universal macOS export."
}

Write-Host "Windows, Linux, and macOS release export contracts verified."

if (-not (Test-Path -LiteralPath $addonConfigPath)) {
    throw "The vendored Godot MCP Pro addon is missing."
}
$addonConfig = Get-Content -Raw -LiteralPath $addonConfigPath
if ($addonConfig -notmatch 'version="1\.16\.0"') {
    throw "Godot MCP Pro must remain pinned to addon version 1.16.0."
}

Write-Host "Godot MCP Pro addon version verified."

if (-not (Test-Path -LiteralPath $schemaPath) -or -not (Test-Path -LiteralPath $schemaHashPath)) {
    throw "The mirrored Realmz 2.0 package schema and expected hash are required."
}
$expectedSchemaHash = (Get-Content -Raw -LiteralPath $schemaHashPath).Trim().ToLowerInvariant()
$actualSchemaHash = (Get-FileHash -LiteralPath $schemaPath -Algorithm SHA256).Hash.ToLowerInvariant()
if ($actualSchemaHash -ne $expectedSchemaHash) {
    throw "Realmz 2.0 schema mirror drift: expected $expectedSchemaHash, found $actualSchemaHash."
}
Write-Host "Realmz 2.0 schema mirror hash verified."

if (-not (Test-Path -LiteralPath $fixtureManifestPath)) {
    throw "The synthetic package fixture provenance record is required."
}
$fixtureManifest = Get-Content -Raw -LiteralPath $fixtureManifestPath | ConvertFrom-Json
foreach ($fixtureName in @("realmz2-synthetic-fixture.realmz2", "realmz2-synthetic-tampered.realmz2")) {
    if (-not (Test-Path -LiteralPath (Join-Path $fixtureRoot $fixtureName))) {
        throw "Missing synthetic package fixture $fixtureName."
    }
}
$packageHash = (Get-FileHash -LiteralPath (Join-Path $fixtureRoot "realmz2-synthetic-fixture.realmz2") -Algorithm SHA256).Hash.ToLowerInvariant()
$negativeHash = (Get-FileHash -LiteralPath (Join-Path $fixtureRoot "realmz2-synthetic-tampered.realmz2") -Algorithm SHA256).Hash.ToLowerInvariant()
if ($packageHash -ne $fixtureManifest.package_sha256 -or $negativeHash -ne $fixtureManifest.negative_fixture_sha256) {
    throw "Synthetic Realmz 2.0 fixture bytes do not match their provenance record."
}
if ($fixtureManifest.schema_sha256 -ne $expectedSchemaHash -or $fixtureManifest.commercial_payload -ne $false) {
    throw "Synthetic fixture provenance does not match the runtime schema/copyright contract."
}
Write-Host "Synthetic Realmz 2.0 fixture provenance verified."
