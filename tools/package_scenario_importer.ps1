param(
    [Parameter(Mandatory)][string]$ImporterRoot,
    [Parameter(Mandatory)][string]$OutputPath
)

$ErrorActionPreference = "Stop"
$ImporterRoot = (Resolve-Path -LiteralPath $ImporterRoot).Path
$OutputPath = [IO.Path]::GetFullPath($OutputPath)
if ([IO.Path]::GetExtension($OutputPath) -ine ".zip") { throw "Scenario importer package output must be a .zip archive." }
if (Test-Path -LiteralPath $OutputPath) { throw "Scenario importer archive already exists; versioned outputs are immutable." }
$importerPrefix = [IO.Path]::GetFullPath($ImporterRoot).TrimEnd('\', '/') + [IO.Path]::DirectorySeparatorChar
if ($OutputPath.StartsWith($importerPrefix, [StringComparison]::OrdinalIgnoreCase)) { throw "Scenario importer ZIP output must be outside its source directory." }
$manifestPath = Join-Path $ImporterRoot "build-manifest.json"
if (-not (Test-Path -LiteralPath $manifestPath -PathType Leaf)) { throw "Importer build-manifest.json is missing." }
$manifest = Get-Content -LiteralPath $manifestPath -Raw | ConvertFrom-Json
if ($manifest.kind -cne "realmz-rebuilt.scenario-importer-build" -or [int]$manifest.formatVersion -ne 1) { throw "Importer manifest kind or version is unsupported." }
$expectedFiles = @(".gdignore", "build-manifest.json", [string]$manifest.executable.path)
$executablePath = Join-Path $ImporterRoot ([string]$manifest.executable.path)
if (-not (Test-Path -LiteralPath $executablePath -PathType Leaf)) { throw "Importer executable is missing." }
if ((Get-Item -LiteralPath $executablePath).Length -ne [long]$manifest.executable.bytes -or (Get-FileHash -LiteralPath $executablePath -Algorithm SHA256).Hash.ToLowerInvariant() -cne [string]$manifest.executable.sha256) { throw "Importer executable does not match its manifest." }
foreach ($support in $manifest.supportFiles) {
    $relative = [string]$support.path
    if ([string]::IsNullOrWhiteSpace($relative) -or [IO.Path]::IsPathRooted($relative) -or $relative.Contains('\') -or $relative.Contains(':') -or @($relative.Split('/')).Contains('..')) { throw "Importer manifest contains an unsafe support path." }
    $path = Join-Path (Join-Path $ImporterRoot "support") ($relative.Replace('/', [IO.Path]::DirectorySeparatorChar))
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { throw "Importer support file is missing: $relative" }
    if ((Get-Item -LiteralPath $path).Length -ne [long]$support.bytes -or (Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash.ToLowerInvariant() -cne [string]$support.sha256) { throw "Importer support file failed its manifest check: $relative" }
    $expectedFiles += "support/$relative"
}
foreach ($entry in Get-ChildItem -LiteralPath $ImporterRoot -Recurse -Force) {
    if (($entry.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) { throw "Importer package source may not contain reparse points: $($entry.FullName)" }
}
$actualFiles = @(Get-ChildItem -LiteralPath $ImporterRoot -File -Recurse -Force | ForEach-Object { [IO.Path]::GetFullPath($_.FullName).Substring($importerPrefix.Length).Replace('\', '/') })
if (@(Compare-Object ($expectedFiles | Sort-Object) ($actualFiles | Sort-Object)).Count -ne 0) { throw "Importer directory contains unexpected or missing files." }

[IO.Directory]::CreateDirectory((Split-Path -Parent $OutputPath)) | Out-Null
Add-Type -AssemblyName System.IO.Compression.FileSystem
[IO.Compression.ZipFile]::CreateFromDirectory($ImporterRoot, $OutputPath, [IO.Compression.CompressionLevel]::Optimal, $false)
$hash = (Get-FileHash -LiteralPath $OutputPath -Algorithm SHA256).Hash.ToLowerInvariant()
Write-Output ([ordered]@{ path = $OutputPath; bytes = (Get-Item -LiteralPath $OutputPath).Length; sha256 = $hash; buildIdentity = $manifest.buildIdentity } | ConvertTo-Json -Depth 8)
