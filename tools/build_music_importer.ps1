param(
    [string]$Triplet = "",
    [string]$OutputDirectory = "",
    [string]$CMakePath = "cmake"
)

$ErrorActionPreference = "Stop"
$repoRoot = Split-Path -Parent $PSScriptRoot
$source = Join-Path $PSScriptRoot "music_importer"
$manifest = Get-Content (Join-Path $source "vcpkg.json") -Raw | ConvertFrom-Json
$pin = $manifest.'builtin-baseline'
$windowsHost = [Environment]::OSVersion.Platform -eq [PlatformID]::Win32NT
if (-not $Triplet) {
    $Triplet = if ($windowsHost) { "x64-windows-static" } elseif ((uname) -eq "Darwin") { "arm64-osx" } else { "x64-linux" }
}
if ($Triplet -notin @("x64-windows-static", "x64-linux", "x64-osx", "arm64-osx")) { throw "Unsupported music importer triplet: $Triplet" }
if (-not $OutputDirectory) { $OutputDirectory = Join-Path $repoRoot "music-importer" }
$OutputDirectory = [IO.Path]::GetFullPath($OutputDirectory)
$buildRoot = Join-Path $repoRoot "build/music-importer"
$vcpkg = Join-Path $buildRoot "vcpkg"
$build = Join-Path $buildRoot $Triplet
New-Item -ItemType Directory -Force -Path $buildRoot | Out-Null
[IO.File]::WriteAllText((Join-Path $buildRoot ".gdignore"), "", [Text.UTF8Encoding]::new($false))
if (-not (Test-Path (Join-Path $vcpkg ".git"))) {
    & git init $vcpkg
    if ($LASTEXITCODE) { throw "Could not initialize the dependency checkout." }
    & git -C $vcpkg remote add origin https://github.com/microsoft/vcpkg.git
    & git -C $vcpkg fetch --depth 1 origin $pin
    if ($LASTEXITCODE) { throw "Could not fetch the pinned dependency baseline." }
    & git -C $vcpkg checkout --detach $pin
    if ($LASTEXITCODE) { throw "Could not check out the pinned dependency baseline." }
}
if ((& git -C $vcpkg rev-parse HEAD).Trim() -ne $pin) { throw "Dependency checkout does not match the pinned baseline." }
if ((& git -C $vcpkg status --porcelain --untracked-files=no)) { throw "Dependency checkout has local modifications." }
$bootstrap = Join-Path $vcpkg $(if ($windowsHost) { "bootstrap-vcpkg.bat" } else { "bootstrap-vcpkg.sh" })
if (-not (Test-Path (Join-Path $vcpkg $(if ($windowsHost) { "vcpkg.exe" } else { "vcpkg" })))) {
    if ($windowsHost) { & $bootstrap -disableMetrics } else { & bash $bootstrap -disableMetrics }
    if ($LASTEXITCODE) { throw "Dependency bootstrap failed." }
}
$hashInput = (@("CMakeLists.txt", "vcpkg.json", "audio_import.h", "audio_import.cpp", "main.cpp") | ForEach-Object {
    "$_=$((Get-FileHash (Join-Path $source $_) -Algorithm SHA256).Hash.ToLowerInvariant())"
}) -join "`n"
$sha = [Security.Cryptography.SHA256]::Create()
try { $sourceId = ([BitConverter]::ToString($sha.ComputeHash([Text.Encoding]::UTF8.GetBytes($hashInput)))).Replace("-", "").ToLowerInvariant() } finally { $sha.Dispose() }
$arguments = @("-S", $source, "-B", $build, "-DCMAKE_TOOLCHAIN_FILE=$vcpkg/scripts/buildsystems/vcpkg.cmake", "-DVCPKG_TARGET_TRIPLET=$Triplet", "-DMUSIC_SOURCE_ID=$sourceId", "-DCMAKE_BUILD_TYPE=Release")
if ($windowsHost) {
    $vswhere = Join-Path ${env:ProgramFiles(x86)} "Microsoft Visual Studio/Installer/vswhere.exe"
    $visualStudio = (& $vswhere -latest -products '*' -version '[17,18)' -requires Microsoft.VisualStudio.Component.VC.Tools.x86.x64 -property installationPath)
    if (-not $visualStudio) { throw "Visual Studio 2022 C++ build tools are required." }
    $env:VCPKG_VISUAL_STUDIO_PATH = $visualStudio.Trim()
    $arguments += @("-G", "Visual Studio 17 2022", "-A", "x64", "-DCMAKE_GENERATOR_INSTANCE=$($visualStudio.Trim())", "-DCMAKE_MSVC_RUNTIME_LIBRARY=MultiThreaded")
}
if ($Triplet -eq "x64-osx") { $arguments += "-DCMAKE_OSX_ARCHITECTURES=x86_64" }
if ($Triplet -eq "arm64-osx") { $arguments += "-DCMAKE_OSX_ARCHITECTURES=arm64" }
& $CMakePath @arguments
if ($LASTEXITCODE) { throw "Music importer configuration failed." }
& $CMakePath --build $build --config Release --parallel 4
if ($LASTEXITCODE) { throw "Music importer build failed." }
& $CMakePath --install $build --config Release --prefix $OutputDirectory
if ($LASTEXITCODE) { throw "Music importer installation failed." }
$executable = Join-Path $OutputDirectory $(if ($windowsHost) { "realmz-music-importer.exe" } else { "realmz-music-importer" })
$identity = (& $executable --version) | ConvertFrom-Json
if ($LASTEXITCODE -or $identity.converter -ne "realmz-music-1:$sourceId") { throw "Music importer embedded identity mismatch." }
$licenses = Join-Path $OutputDirectory "licenses"
New-Item -ItemType Directory -Force -Path $licenses | Out-Null
Get-ChildItem (Join-Path $build "vcpkg_installed/$Triplet/share") -Directory | ForEach-Object {
    $copyright = Join-Path $_.FullName "copyright"
    if (Test-Path $copyright) { Copy-Item -LiteralPath $copyright -Destination (Join-Path $licenses ($_.Name + ".txt")) -Force }
}
$files = [ordered]@{}
Get-ChildItem $OutputDirectory -Recurse -File | Where-Object { $_.Name -notin @("manifest.json", ".gdignore") } | Sort-Object FullName | ForEach-Object {
    $relative = $_.FullName.Substring($OutputDirectory.Length + 1).Replace('\', '/')
    $files[$relative] = (Get-FileHash -LiteralPath $_.FullName -Algorithm SHA256).Hash.ToLowerInvariant()
}
$result = [ordered]@{formatVersion = 1; converter = $identity.converter; dependencyBaseline = $pin; target = $Triplet; files = $files}
[IO.File]::WriteAllText((Join-Path $OutputDirectory "manifest.json"), ($result | ConvertTo-Json -Depth 6), [Text.UTF8Encoding]::new($false))
[IO.File]::WriteAllText((Join-Path $OutputDirectory ".gdignore"), "", [Text.UTF8Encoding]::new($false))
Write-Host "Music importer built: $($identity.converter) ($Triplet)"
