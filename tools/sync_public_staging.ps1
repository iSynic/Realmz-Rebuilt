param(
    [Parameter(Mandatory = $true)]
    [string]$Destination
)

$ErrorActionPreference = "Stop"
$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path
$manifestPath = Join-Path $PSScriptRoot "public-source-manifest.json"
$manifest = Get-Content -Raw -LiteralPath $manifestPath | ConvertFrom-Json
$destinationPath = [System.IO.Path]::GetFullPath($Destination)

& git -C $repoRoot diff --quiet --ignore-submodules --
if ($LASTEXITCODE -ne 0) { throw "Public staging synchronization requires a clean source working tree." }
& git -C $repoRoot diff --cached --quiet --ignore-submodules --
if ($LASTEXITCODE -ne 0) { throw "Public staging synchronization requires a clean source index." }

if ($destinationPath.StartsWith($repoRoot + [System.IO.Path]::DirectorySeparatorChar, [System.StringComparison]::OrdinalIgnoreCase)) {
    throw "Public staging must be outside the source repository."
}
if (-not (Test-Path -LiteralPath (Join-Path $destinationPath ".git"))) {
    throw "Public staging destination must be an existing Git checkout: $destinationPath"
}
$destinationStatus = @(& git -C $destinationPath status --porcelain=v1 --untracked-files=all)
if ($LASTEXITCODE -ne 0 -or $destinationStatus.Count -ne 0) {
    throw "Public staging destination must be completely clean before synchronization."
}
$destinationBranch = (& git -C $destinationPath branch --show-current).Trim()
if ([string]::IsNullOrWhiteSpace($destinationBranch) -or $destinationBranch -in @("main", "master")) {
    throw "Public staging synchronization requires a named review branch, not main, master, or detached HEAD."
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
    return @($manifest.includeRoots) -contains $segments[0]
}

$desiredPaths = @(& git -C $repoRoot ls-files --cached | Where-Object { Test-ManifestPath $_ } | Sort-Object -Unique)
if ($LASTEXITCODE -ne 0 -or $desiredPaths.Count -eq 0) { throw "Could not enumerate public source files." }
$desiredSet = New-Object 'System.Collections.Generic.HashSet[string]' ([System.StringComparer]::OrdinalIgnoreCase)
foreach ($relativePath in $desiredPaths) { [void]$desiredSet.Add($relativePath.Replace('\', '/')) }

$removed = 0
foreach ($relativePath in @(& git -C $destinationPath ls-files)) {
    $normalized = $relativePath.Replace('\', '/')
    if ($desiredSet.Contains($normalized)) { continue }
    $targetPath = [System.IO.Path]::GetFullPath((Join-Path $destinationPath $relativePath))
    if (-not $targetPath.StartsWith($destinationPath + [System.IO.Path]::DirectorySeparatorChar, [System.StringComparison]::OrdinalIgnoreCase)) {
        throw "Refusing to remove a staging file outside the destination: $relativePath"
    }
    if (Test-Path -LiteralPath $targetPath -PathType Leaf) { [System.IO.File]::Delete($targetPath) }
    $removed += 1
}

$copied = 0
foreach ($relativePath in $desiredPaths) {
    $sourcePath = Join-Path $repoRoot $relativePath
    if (-not (Test-Path -LiteralPath $sourcePath -PathType Leaf)) { throw "Public source file is missing: $relativePath" }
    $targetPath = Join-Path $destinationPath $relativePath
    $targetParent = Split-Path -Parent $targetPath
    if (-not (Test-Path -LiteralPath $targetParent)) { New-Item -ItemType Directory -Force -Path $targetParent | Out-Null }
    Copy-Item -LiteralPath $sourcePath -Destination $targetPath -Force
    $copied += 1
}

$attributesPath = Join-Path $destinationPath ".gitattributes"
$attributes = Get-Content -Raw -LiteralPath $attributesPath
if ($attributes.Contains("*.realmz2 binary")) {
    $attributes = $attributes.Replace("*.realmz2 binary", "*.realmz2 filter=lfs diff=lfs merge=lfs -text")
    [System.IO.File]::WriteAllText($attributesPath, $attributes, [System.Text.UTF8Encoding]::new($false))
}
if (-not $attributes.Contains("*.realmz2 filter=lfs diff=lfs merge=lfs -text")) {
    throw "Public staging does not preserve the Realmz package LFS boundary."
}
foreach ($required in @("LICENSE", "README.md", "project.godot", "src", "tests", "tools", ".github")) {
    if (-not (Test-Path -LiteralPath (Join-Path $destinationPath $required))) { throw "Public staging omitted required root: $required" }
}

Write-Host "Public staging synchronized from explicit manifest: copied=$copied removed=$removed branch=$destinationBranch destination=$destinationPath"
