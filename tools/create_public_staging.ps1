param(
    [Parameter(Mandatory = $true)]
    [string]$Destination
)

$ErrorActionPreference = "Stop"
$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path
$manifestPath = Join-Path $PSScriptRoot "public-source-manifest.json"
$manifest = Get-Content -Raw -LiteralPath $manifestPath | ConvertFrom-Json
$destinationPath = [System.IO.Path]::GetFullPath($Destination)

if ($destinationPath.StartsWith($repoRoot + [System.IO.Path]::DirectorySeparatorChar, [System.StringComparison]::OrdinalIgnoreCase)) {
    throw "Public staging must be outside the source repository."
}
if (Test-Path -LiteralPath $destinationPath) {
    if (@(Get-ChildItem -Force -LiteralPath $destinationPath).Count -ne 0) {
        throw "Public staging destination must not exist or must be empty: $destinationPath"
    }
} else {
    New-Item -ItemType Directory -Path $destinationPath | Out-Null
}

function Test-ManifestPath {
    param([string]$RelativePath)

    $normalized = $RelativePath.Replace('\', '/')
    $segments = $normalized.Split('/')
    if (@($manifest.excludeNames) -contains $segments[-1]) { return $false }
    if (@($manifest.excludePaths) -contains $normalized) { return $false }
    foreach ($prefix in @($manifest.excludePrefixes)) {
        if ($normalized.StartsWith([string]$prefix, [System.StringComparison]::OrdinalIgnoreCase)) { return $false }
    }
    $root = $segments[0]
    return @($manifest.includeRoots) -contains $root
}

$candidates = @(& git -C $repoRoot ls-files --cached --others --exclude-standard)
if ($LASTEXITCODE -ne 0) { throw "Could not enumerate source files." }
$copied = 0
foreach ($relativePath in $candidates | Sort-Object -Unique) {
    if (-not (Test-ManifestPath $relativePath)) { continue }
    $sourcePath = Join-Path $repoRoot $relativePath
    if (-not (Test-Path -LiteralPath $sourcePath -PathType Leaf)) { continue }
    $targetPath = Join-Path $destinationPath $relativePath
    $targetParent = Split-Path -Parent $targetPath
    if (-not (Test-Path -LiteralPath $targetParent)) {
        New-Item -ItemType Directory -Force -Path $targetParent | Out-Null
    }
    Copy-Item -LiteralPath $sourcePath -Destination $targetPath
    $copied += 1
}

foreach ($required in @("LICENSE", "README.md", "project.godot", "src", "tests", "tools", ".github")) {
    if (-not (Test-Path -LiteralPath (Join-Path $destinationPath $required))) {
        throw "Public staging omitted required root: $required"
    }
}
$attributesPath = Join-Path $destinationPath ".gitattributes"
$attributes = Get-Content -Raw -LiteralPath $attributesPath
if (-not $attributes.Contains("*.realmz2 binary")) { throw "Public staging could not locate the package attribute boundary." }
$attributes = $attributes.Replace("*.realmz2 binary", "*.realmz2 filter=lfs diff=lfs merge=lfs -text")
[System.IO.File]::WriteAllText($attributesPath, $attributes, [System.Text.UTF8Encoding]::new($false))
Write-Host "Public staging populated from explicit manifest: files=$copied destination=$destinationPath"
