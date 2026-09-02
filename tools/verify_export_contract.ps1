$ErrorActionPreference = "Stop"
$repoRoot = Split-Path -Parent $PSScriptRoot
$presetPath = Join-Path $repoRoot "export_presets.cfg"
$projectPath = Join-Path $repoRoot "project.godot"
$addonConfigPath = Join-Path $repoRoot "addons\godot_mcp\plugin.cfg"
$schemaPath = Join-Path $repoRoot "contracts\realmz2\realmz2-package.schema.json"
$schemaHashPath = Join-Path $repoRoot "contracts\realmz2\realmz2-package.schema.sha256"
$featureSchemaPath = Join-Path $repoRoot "contracts\realmz2\realmz2-feature-report.schema.json"
$featureSchemaHashPath = Join-Path $repoRoot "contracts\realmz2\realmz2-feature-report.schema.sha256"
$fixtureRoot = Join-Path $repoRoot "tests\fixtures\packages"
$fixtureManifestPath = Join-Path $fixtureRoot "fixture-provenance.json"
$noticePath = Join-Path $repoRoot "THIRD_PARTY_NOTICES.txt"
$ciPath = Join-Path $repoRoot ".github\workflows\ci.yml"
$releaseWorkflowPath = Join-Path $repoRoot ".github\workflows\release.yml"

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
    foreach ($requiredExclusion in @("addons/godot_mcp/**", "tests/**", "tools/**", "docs/**", "contracts/**", "artifacts/**", ".references/**", ".github/**", ".mcp.json", "**/AGENTS.md", "README.md", "CONTRIBUTING.md")) {
        if (-not $body.Contains($requiredExclusion)) {
            throw "Release preset $($expected.Key) must exclude $requiredExclusion"
        }
    }
    foreach ($requiredBundledFile in @("LICENSE", "THIRD_PARTY_NOTICES.txt", "src/presentation/assets/classic-application-media.json", "src/presentation/assets/classic-media/**", "src/infrastructure/characters/realmz-classic-starter-characters.json")) {
        if ($body -notmatch ('(?m)^include_filter="[^"]*' + [regex]::Escape($requiredBundledFile) + '[^"]*"$')) {
            throw "Release preset $($expected.Key) must include $requiredBundledFile"
        }
    }
}

if (-not (Test-Path -LiteralPath $noticePath -PathType Leaf)) {
    throw "The release must carry THIRD_PARTY_NOTICES.txt."
}
$notice = Get-Content -Raw -LiteralPath $noticePath
foreach ($requiredNotice in @("Realmz copyright 1994 by Tim Phillips", "CC-BY-NC-SA", "491816ad60037394f92c428e99c004494d3c28b3", "linearly rendered to 48000 Hz", "Castle's playback algorithm")) {
    if (-not $notice.Contains($requiredNotice)) {
        throw "THIRD_PARTY_NOTICES.txt is missing required integrated-media provenance: $requiredNotice"
    }
}
foreach ($starterNotice in @("Classic Realmz 7.1.2 starter characters", "Kevlar: 6a5124c03e41977002d93fcfbc52d206c84e4b0b1948a84bcaf41052aa5b41a2", "Vormale: 440e0b9cb675f7cc68553ab3414b830bb8d1889518e095ba4e16d00805f957f5", "GPL")) {
    if (-not $notice.Contains($starterNotice)) { throw "THIRD_PARTY_NOTICES.txt is missing release-license/starter provenance: $starterNotice" }
}

$macOptions = [regex]::Match($preset, '(?ms)^\[preset\.2\.options\]\s*(.*?)(?=^\[preset\.\d+|\z)').Groups[1].Value
if ($macOptions -notmatch '(?m)^binary_format/architecture="universal"$' -or $macOptions -notmatch '(?m)^texture_format/etc2_astc=true$') {
    throw "The universal macOS release preset must enable ETC2/ASTC texture import."
}
$projectSettings = Get-Content -Raw -LiteralPath $projectPath
if ($projectSettings -notmatch '(?m)^config/features=PackedStringArray\("4\.7", "Mobile"\)$' -or $projectSettings -notmatch '(?m)^renderer/rendering_method="mobile"$') {
    throw "Native releases must default to Godot's Mobile RenderingDevice path; Compatibility remains an explicit launch override."
}
if ($projectSettings -notmatch '(?m)^textures/vram_compression/import_etc2_astc=true$') {
    throw "The project must import ETC2/ASTC textures for universal macOS export."
}
if ($projectSettings -notmatch '(?m)^config/version="\d+(?:\.\d+)*"$') {
    throw "The cross-platform release version must use the numeric format required by macOS export."
}
if ($projectSettings -match '(?m)^\s*[^;\r\n]*addons/godot_mcp/.*_service\.gd') {
    throw "Release project settings must not retain development-only MCP runtime autoloads."
}

if (-not (Test-Path -LiteralPath $ciPath -PathType Leaf)) {
    throw "The native release CI matrix is missing."
}
$ci = Get-Content -Raw -LiteralPath $ciPath
foreach ($artifactPath in @("dist/windows", "dist/linux", "dist/macos")) {
    if (-not $ci.Contains("artifactPath: $artifactPath")) { throw "Release CI does not upload the complete $artifactPath directory." }
}
foreach ($requiredStep in @("verify_release_artifact.ps1", "Launch exported Windows runtime", "Launch exported Linux runtime", "Launch exported macOS runtime", 'path: ${{ matrix.artifactPath }}')) {
    if (-not $ci.Contains($requiredStep)) { throw "Release CI is missing required artifact/native-smoke contract: $requiredStep" }
}
foreach ($requiredCiContract in @("lfs: true", "fetch-depth: 1", "verify_public_source.ps1", "Realmz Rebuilt.exe", "Realmz Rebuilt.x86_64", "Realmz Rebuilt.zip", "realmz-rebuilt-windows-x86_64", "realmz-rebuilt-linux-x86_64", "realmz-rebuilt-macos-universal")) {
    if (-not $ci.Contains($requiredCiContract)) { throw "Release CI is missing required public-release contract: $requiredCiContract" }
}
if (-not (Test-Path -LiteralPath $releaseWorkflowPath -PathType Leaf)) { throw "The tag draft-prerelease workflow is missing." }
$releaseWorkflow = Get-Content -Raw -LiteralPath $releaseWorkflowPath
foreach ($requiredReleaseContract in @('tags:', '"v*"', "draft: true", "prerelease: true", "SHA256SUMS", "realmz-rebuilt-windows-x86_64.zip", "realmz-rebuilt-linux-x86_64.tar.gz", "realmz-rebuilt-macos-universal.zip")) {
    if (-not $releaseWorkflow.Contains($requiredReleaseContract)) { throw "Tag workflow is missing required draft-prerelease contract: $requiredReleaseContract" }
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

if (-not (Test-Path -LiteralPath $featureSchemaPath) -or -not (Test-Path -LiteralPath $featureSchemaHashPath)) {
    throw "The mirrored Realmz 2.0 feature-report schema and expected hash are required."
}
$expectedFeatureSchemaHash = (Get-Content -Raw -LiteralPath $featureSchemaHashPath).Trim().ToLowerInvariant()
$actualFeatureSchemaHash = (Get-FileHash -LiteralPath $featureSchemaPath -Algorithm SHA256).Hash.ToLowerInvariant()
if ($actualFeatureSchemaHash -ne $expectedFeatureSchemaHash) {
    throw "Realmz 2.0 feature-report schema mirror drift: expected $expectedFeatureSchemaHash, found $actualFeatureSchemaHash."
}
Write-Host "Realmz 2.0 feature-report schema mirror hash verified."

& "$PSScriptRoot\analyze_gameplay_feature_reports.ps1" -SelfTest

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
