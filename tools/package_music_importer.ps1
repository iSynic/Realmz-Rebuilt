param(
    [Parameter(Mandatory = $true)]
    [ValidateSet("windows", "linux", "macos-universal")]
    [string]$Target,
    [Parameter(Mandatory = $true)]
    [string[]]$InputDirectory,
    [Parameter(Mandatory = $true)]
    [string]$OutputDirectory,
    [string]$LipoPath = "lipo"
)

$ErrorActionPreference = "Stop"
$binaryName = "realmz-music-importer" + $(if ($Target -eq "windows") { ".exe" } else { "" })
$inputs = @($InputDirectory | ForEach-Object { (Resolve-Path -LiteralPath $_).Path })
if ($Target -eq "macos-universal" -and $inputs.Count -ne 2) { throw "A universal macOS helper requires x64 and arm64 builds." }
if ($Target -ne "macos-universal" -and $inputs.Count -ne 1) { throw "$Target packaging requires exactly one build." }
$builds = @()
foreach ($directory in $inputs) {
    $manifestPath = Join-Path $directory "manifest.json"
    $manifest = Get-Content -Raw -LiteralPath $manifestPath | ConvertFrom-Json
    $binaryPath = Join-Path $directory $binaryName
    if (-not (Test-Path -LiteralPath $binaryPath -PathType Leaf)) { throw "Native music helper is missing: $binaryPath" }
    $identity = (& $binaryPath --version | ConvertFrom-Json)
    if ($LASTEXITCODE -ne 0 -or $identity.converter -cnotmatch '^realmz-music-1:[0-9a-f]{64}$' -or $identity.converter -cne [string]$manifest.converter) { throw "Music helper embedded identity does not match its build manifest: $directory" }
    if ([int]$manifest.formatVersion -ne 1 -or [string]::IsNullOrWhiteSpace([string]$manifest.dependencyBaseline)) { throw "Music helper build manifest is unsupported: $directory" }
    $licenseRoot = Join-Path $directory "licenses"
    $licenseFiles = @(Get-ChildItem -LiteralPath $licenseRoot -File -Recurse | Sort-Object { $_.FullName.Substring($licenseRoot.Length + 1).Replace('\', '/') })
    if ($licenseFiles.Count -eq 0) { throw "Music helper dependency licenses are missing: $directory" }
    $builds += [pscustomobject]@{ Directory = $directory; Manifest = $manifest; Binary = $binaryPath; Identity = [string]$identity.converter; LicenseRoot = $licenseRoot; LicenseFiles = $licenseFiles }
}
if (@($builds.Identity | Sort-Object -Unique).Count -ne 1 -or @($builds.Manifest.dependencyBaseline | Sort-Object -Unique).Count -ne 1) { throw "Music helper builds do not share source identity and dependency baseline." }
if ($Target -eq "macos-universal") {
    $expectedTargets = @("arm64-osx", "x64-osx")
    $actualTargetList = @($builds.Manifest.target | Sort-Object) -join "|"
    $expectedTargetList = @($expectedTargets | Sort-Object) -join "|"
    if ($actualTargetList -cne $expectedTargetList) { throw "Universal macOS packaging requires exactly arm64-osx and x64-osx builds." }
} else {
    $expectedBuildTarget = (@{ windows = "x64-windows-static"; linux = "x64-linux" })[$Target]
    if ($builds[0].Manifest.target -ne $expectedBuildTarget) {
        throw "Music helper build target does not match $Target packaging."
    }
}
$licenseSources = [System.Collections.Generic.Dictionary[string, object]]::new([StringComparer]::Ordinal)
foreach ($build in $builds) {
    foreach ($file in $build.LicenseFiles) {
        $relative = $file.FullName.Substring($build.LicenseRoot.Length + 1).Replace('\', '/')
        $hash = (Get-FileHash -LiteralPath $file.FullName -Algorithm SHA256).Hash
        if ($licenseSources.ContainsKey($relative)) {
            if ($licenseSources[$relative].Hash -cne $hash) { throw "Architecture builds contain different dependency license content: $relative" }
        } else {
            $licenseSources.Add($relative, [pscustomobject]@{ Path = $file.FullName; Hash = $hash })
        }
    }
}
$output = [IO.Path]::GetFullPath($OutputDirectory)
if (Test-Path -LiteralPath $output) { throw "Music importer package output already exists: $output" }
[IO.Directory]::CreateDirectory($output) | Out-Null
$licenses = Join-Path $output "licenses"
[IO.Directory]::CreateDirectory($licenses) | Out-Null
foreach ($relative in ($licenseSources.Keys | Sort-Object)) {
    $destination = Join-Path $licenses ($relative.Replace('/', [IO.Path]::DirectorySeparatorChar))
    [IO.Directory]::CreateDirectory((Split-Path -Parent $destination)) | Out-Null
    Copy-Item -LiteralPath $licenseSources[$relative].Path -Destination $destination
}
$binaryOutput = Join-Path $output $binaryName
if ($Target -eq "macos-universal") {
    & $LipoPath -create $builds[0].Binary $builds[1].Binary -output $binaryOutput
    if ($LASTEXITCODE -ne 0) { throw "Could not combine x64 and arm64 music helpers." }
    & $LipoPath $binaryOutput -verify_arch x86_64 arm64
    if ($LASTEXITCODE -ne 0) { throw "Combined music helper is missing a required macOS architecture." }
} else {
    Copy-Item -LiteralPath $builds[0].Binary -Destination $binaryOutput
}
if (-not $IsWindows -and $env:OS -ne "Windows_NT") { & chmod 755 $binaryOutput; if ($LASTEXITCODE -ne 0) { throw "Could not mark music helper executable." } }
$identity = (& $binaryOutput --version | ConvertFrom-Json)
if ($LASTEXITCODE -ne 0 -or [string]$identity.converter -cne $builds[0].Identity) { throw "Packaged music helper identity does not match its source builds." }
$files = [ordered]@{}
foreach ($file in Get-ChildItem -LiteralPath $output -File -Recurse | Sort-Object FullName) {
    $relative = $file.FullName.Substring($output.Length + 1).Replace('\', '/')
    $files[$relative] = (Get-FileHash -LiteralPath $file.FullName -Algorithm SHA256).Hash.ToLowerInvariant()
}
$result = [ordered]@{
    formatVersion = 1
    converter = $identity.converter
    dependencyBaseline = [string]$builds[0].Manifest.dependencyBaseline
    target = $Target
    files = $files
}
[IO.File]::WriteAllText((Join-Path $output "manifest.json"), ($result | ConvertTo-Json -Depth 6), [Text.UTF8Encoding]::new($false))
Write-Host "Packaged music importer: $($identity.converter) ($Target)"
