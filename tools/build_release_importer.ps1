param(
    [Parameter(Mandatory)][string]$Target,
    [Parameter(Mandatory)][string]$WorkRoot,
    [Parameter(Mandatory)][string]$OutputRoot
)

$ErrorActionPreference = 'Stop'
$inputs = Get-Content -Raw (Join-Path $PSScriptRoot 'scenario-importer-inputs.json') | ConvertFrom-Json
$WorkRoot = [IO.Path]::GetFullPath($WorkRoot)
$OutputRoot = [IO.Path]::GetFullPath($OutputRoot)
foreach ($path in @($WorkRoot, $OutputRoot)) {
    if (Test-Path -LiteralPath $path) { throw "Build output must not exist: $path" }
    [IO.Directory]::CreateDirectory($path) | Out-Null
}
function Get-Hash([string]$Path) { return (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash.ToLowerInvariant() }
function Get-PinnedInput($Record, [string]$Destination) {
    Invoke-WebRequest -Uri $Record.url -OutFile $Destination
    if ((Get-Hash $Destination) -cne $Record.sha256) { throw 'Converter input archive failed its SHA-256 check.' }
}
$bundle = Join-Path $WorkRoot 'source.bundle'
$support = Join-Path $WorkRoot 'support.zip'
Get-PinnedInput $inputs.source $bundle
Get-PinnedInput $inputs.support $support
$sourceRoot = Join-Path $WorkRoot 'source'
git -c core.autocrlf=false clone --quiet $bundle $sourceRoot
if ($LASTEXITCODE -ne 0) { throw 'Could not clone pinned converter source.' }
$acceptedSource = $inputs.source
if ($null -ne $inputs.sourceUpdate) {
    $update = $inputs.sourceUpdate
    $updateFile = [string]$update.file
    if ([string]::IsNullOrWhiteSpace($updateFile) -or $updateFile -in @('.', '..') -or $updateFile -match '[/\\:]' -or $update.baseCommit -cne $inputs.source.commit) { throw 'Converter source update must name a local bundle for the pinned base commit.' }
    $updatePath = Join-Path $PSScriptRoot $updateFile
    if ((Get-Hash $updatePath) -cne $update.sha256) { throw 'Converter source update failed its SHA-256 check.' }
    git -C $sourceRoot bundle verify $updatePath
    if ($LASTEXITCODE -ne 0) { throw 'Converter source update prerequisites are unavailable.' }
    git -C $sourceRoot fetch --quiet $updatePath $update.commit
    if ($LASTEXITCODE -ne 0) { throw 'Could not fetch the pinned converter source update.' }
    git -C $sourceRoot merge-base --is-ancestor $inputs.source.commit $update.commit
    if ($LASTEXITCODE -ne 0) { throw 'Converter source update is not a successor of the pinned base.' }
    $acceptedSource = $update
}
git -C $sourceRoot checkout --quiet --detach $acceptedSource.commit
if ($LASTEXITCODE -ne 0) { throw 'Pinned converter source commit is absent.' }
$tree = (& git -C $sourceRoot rev-parse 'HEAD^{tree}').Trim()
if ($tree -cne $acceptedSource.tree) { throw 'Converter source tree differs from the pin.' }
Add-Type -AssemblyName System.IO.Compression.FileSystem
$archive = [IO.Compression.ZipFile]::OpenRead($support)
try {
    foreach ($entry in $archive.Entries) {
        if ($entry.FullName -match '\\|:|^/' -or @($entry.FullName.Split('/')).Contains('..')) { throw 'Unsafe support archive path.' }
        $mode = ($entry.ExternalAttributes -shr 16) -band 0xF000
        if ($mode -notin @(0, 0x8000, 0x4000)) { throw 'Support archive contains a link or special file.' }
    }
    [IO.Compression.ZipFile]::ExtractToDirectory($support, $OutputRoot)
} finally { $archive.Dispose() }
[IO.File]::WriteAllText((Join-Path $OutputRoot '.gdignore'), '', [Text.UTF8Encoding]::new($false))
Push-Location $sourceRoot
try {
    if ([string]::IsNullOrWhiteSpace($inputs.rustToolchain)) { throw 'Converter Rust toolchain pin is missing.' }
    rustup toolchain install $inputs.rustToolchain --profile minimal
    if ($LASTEXITCODE -ne 0) { throw 'Pinned Rust toolchain installation failed.' }
    rustup override set $inputs.rustToolchain
    if ($LASTEXITCODE -ne 0) { throw 'Pinned Rust toolchain selection failed.' }
    rustup target add $Target
    if ($LASTEXITCODE -ne 0) { throw 'Rust target installation failed.' }
    cargo build --locked --release -p providence-native-adapter --target $Target
    if ($LASTEXITCODE -ne 0) { throw 'Converter compilation failed.' }
} finally { Pop-Location }
$binaryName = 'providence-native-adapter' + $(if ($Target -match 'windows') { '.exe' } else { '' })
$binary = Join-Path $sourceRoot "target/$Target/release/$binaryName"
$identity = (& $binary build-identity | Out-String) | ConvertFrom-Json
if ($LASTEXITCODE -ne 0) { throw 'Converter build identity could not be read.' }
foreach ($field in @('commit', 'schemaSha256', 'cargoLockSha256')) {
    if ($identity.$field -cne $acceptedSource.$field) { throw "Converter $field differs from the accepted input." }
}
if ($identity.sourceTree -cne $acceptedSource.tree -or $identity.sourceDirty -or $identity.target -cne $Target -or $identity.profile -cne 'release') { throw 'Converter did not report the pinned clean native release identity.' }
if (-not $identity.rustcVersion.StartsWith("rustc $($inputs.rustToolchain) ") -or -not $identity.cargoVersion.StartsWith("cargo $($inputs.rustToolchain) ")) { throw 'Converter did not report the pinned Rust toolchain.' }
if (@(& git -C $sourceRoot status --porcelain --untracked-files=all).Count -ne 0) { throw 'Converter build modified its source checkout.' }
Copy-Item -LiteralPath $binary -Destination (Join-Path $OutputRoot $binaryName)
$manifest = Get-Content -Raw (Join-Path $OutputRoot 'build-manifest.json') | ConvertFrom-Json
$manifest.buildIdentity = $identity
$manifest.sourceChanges = @()
$manifest.executable.path = $binaryName
$manifest.executable.bytes = (Get-Item -LiteralPath $binary).Length
$manifest.executable.sha256 = Get-Hash $binary
$manifest.executable.mode = if ($Target -match 'windows') { 'windows-executable' } else { '0755' }
[IO.File]::WriteAllText((Join-Path $OutputRoot 'build-manifest.json'), ($manifest | ConvertTo-Json -Depth 16) + "`n", [Text.UTF8Encoding]::new($false))
Write-Host "Built clean converter $($identity.commit) for $Target"
