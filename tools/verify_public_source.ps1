param(
    [string]$Root = ""
)

$ErrorActionPreference = "Stop"
if ([string]::IsNullOrWhiteSpace($Root)) { $Root = Join-Path $PSScriptRoot ".." }
$repoRoot = (Resolve-Path $Root).Path

foreach ($required in @("LICENSE", "README.md", "CONTRIBUTING.md", "THIRD_PARTY_NOTICES.txt", "project.godot", ".gitattributes", ".github/workflows/ci.yml", ".github/workflows/release.yml")) {
    if (-not (Test-Path -LiteralPath (Join-Path $repoRoot $required) -PathType Leaf)) {
        throw "Public source is missing $required"
    }
}

$tracked = @(& git -C $repoRoot ls-files)
if ($LASTEXITCODE -ne 0 -or $tracked.Count -eq 0) { throw "Public source must be a Git working tree with tracked files." }
$forbiddenNames = @("AGENTS.md", ".mcp.json")
foreach ($path in $tracked) {
    $normalized = $path.Replace('\', '/')
    if ($forbiddenNames -contains ($normalized.Split('/')[-1])) { throw "Forbidden internal file is tracked: $normalized" }
    foreach ($prefix in @(".godot/", ".references/", ".ua/", ".understand/", "artifacts/", "dist/", "docs/codemap/", "release-evidence/", "test-results/")) {
        if ($normalized.StartsWith($prefix, [System.StringComparison]::OrdinalIgnoreCase)) { throw "Forbidden generated/internal path is tracked: $normalized" }
    }
    if ($normalized -in @("docs/development.md", "docs/roadmap.md")) { throw "Internal process document is tracked: $normalized" }
}

$textExtensions = @(".cfg", ".gd", ".gitattributes", ".gitignore", ".json", ".md", ".ps1", ".py", ".txt", ".yml", ".yaml")
$contentPatterns = [ordered]@{
    "machine-local Windows path" = '(?i)[A-Z]:\\Users\\[^\\\s]+'
    "machine-local macOS path" = '(?i)/Users/[^/\s]+'
    "source-intelligence metadata" = '(?i)knowledgeGraph|Understand Anything|docs/codemap|(?:^|/)\.ua(?:/|$)|(?:^|/)\.understand(?:/|$)'
    "internal process contract" = '(?i)\bDOX\b|AGENTS\.md'
}
foreach ($path in $tracked) {
    $fullPath = Join-Path $repoRoot $path
    if (-not (Test-Path -LiteralPath $fullPath -PathType Leaf)) { continue }
    if ($path -in @(".gitignore", "export_presets.cfg", "tools/verify_export_contract.ps1", "tools/verify_release_artifact.ps1", "tools/verify_public_source.ps1", "tools/public-source-manifest.json", "tools/create_public_staging.ps1")) { continue }
    $extension = [System.IO.Path]::GetExtension($path).ToLowerInvariant()
    if ($textExtensions -notcontains $extension -and -not ($path -in @(".gitattributes", ".gitignore"))) { continue }
    $text = Get-Content -Raw -LiteralPath $fullPath
    foreach ($entry in $contentPatterns.GetEnumerator()) {
        if ($text -match $entry.Value) { throw "Public source contains $($entry.Key) in $path" }
    }
}

$realmzPackages = @($tracked | Where-Object { $_.EndsWith('.realmz2', [System.StringComparison]::OrdinalIgnoreCase) })
if ($realmzPackages.Count -ne 16) { throw "Public source must track exactly 13 scenarios, one character library, and two synthetic fixtures; found $($realmzPackages.Count)." }
Add-Type -AssemblyName System.IO.Compression.FileSystem
foreach ($relativePath in $realmzPackages) {
    $fullPath = Join-Path $repoRoot $relativePath
    $prefix = [System.IO.File]::ReadAllBytes($fullPath)[0..3]
    $prefixText = [System.Text.Encoding]::ASCII.GetString($prefix)
    if (-not $prefixText.StartsWith('PK')) { throw "$relativePath is not materialized ZIP data; run git lfs pull." }
    $archive = [System.IO.Compression.ZipFile]::OpenRead($fullPath)
    try {
        if ($archive.Entries.Count -eq 0) { throw "$relativePath is an empty ZIP package." }
    } finally { $archive.Dispose() }
    $attribute = (& git -C $repoRoot check-attr filter -- $relativePath).Trim()
    if ($attribute -notmatch ': filter: lfs$') { throw "$relativePath is not governed by Git LFS." }
}

$largeBlobs = @(& git -C $repoRoot ls-tree -r -l HEAD | ForEach-Object {
    if ($_ -match '^\d+\s+blob\s+[0-9a-f]+\s+(\d+)\s+(.+)$' -and [long]$Matches[1] -gt 10MB) { $Matches[2] }
})
if ($largeBlobs.Count -gt 0) { throw "Oversized non-LFS Git blobs found: $($largeBlobs -join ', ')" }

& git -C $repoRoot lfs fsck
if ($LASTEXITCODE -ne 0) { throw "git lfs fsck failed." }
Write-Host "Public source, exclusions, ZIP packages, and Git LFS objects verified."
