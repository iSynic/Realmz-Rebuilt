param(
    [Parameter(Mandatory=$true)][string]$ProvidenceRoot,
    [Parameter(Mandatory=$true)][string]$ClassicScenariosRoot,
    [Parameter(Mandatory=$true)][string]$OriginalPackagesRoot,
    [Parameter(Mandatory=$true)][string]$OutputRoot
)
$ErrorActionPreference = 'Stop'
$repoRoot = Split-Path -Parent $PSScriptRoot
$bundleRoot = Join-Path $repoRoot 'src/storage/packages/bundled_campaigns'
$lock = Get-Content -Raw (Join-Path $bundleRoot 'shop-restoration.json') | ConvertFrom-Json
$catalog = Get-Content -Raw (Join-Path $bundleRoot 'castle-bundled-scenarios.provenance.json') | ConvertFrom-Json
if (Test-Path -LiteralPath $OutputRoot) { throw 'Choose a new, empty output root.' }
$OutputRoot = [IO.Path]::GetFullPath($OutputRoot)
[IO.Directory]::CreateDirectory($OutputRoot) | Out-Null
$sourceRoot = Join-Path $OutputRoot 'providence-source'
$snapshot = Join-Path $OutputRoot 'providence.zip'
& git -C $ProvidenceRoot archive $lock.compilerRevision --format=zip "--output=$snapshot"
if ($LASTEXITCODE -ne 0) { throw 'Pinned Providence source is unavailable.' }
Expand-Archive -LiteralPath $snapshot -DestinationPath $sourceRoot
$exampleRoot = Join-Path $sourceRoot 'crates/providence-application-library/examples'
[IO.Directory]::CreateDirectory($exampleRoot) | Out-Null
$helper = Join-Path $PSScriptRoot 'restore_bundled_shops.rs'
if ((Get-FileHash -LiteralPath $helper -Algorithm SHA256).Hash.ToLowerInvariant() -ne $lock.compilerToolSha256) { throw 'Repair helper hash mismatch.' }
Copy-Item -LiteralPath $helper -Destination (Join-Path $exampleRoot 'restore_bundled_shops.rs')
$targetRoot = Join-Path $OutputRoot 'target'
& cargo build --locked --release --manifest-path (Join-Path $sourceRoot 'Cargo.toml') --target-dir $targetRoot -p providence-application-library --example restore_bundled_shops
if ($LASTEXITCODE -ne 0) { throw 'Providence repair tool build failed.' }
$binary = Join-Path $targetRoot 'release/examples/restore_bundled_shops.exe'
foreach ($entry in $lock.transitions) {
    $scenario = @($catalog.scenarios | Where-Object campaignId -eq $entry.campaignId)[0]
    $plan = Join-Path $OutputRoot ($entry.campaignId + '.json')
    $entry | Add-Member -NotePropertyName applicationPackageHash -NotePropertyValue $lock.applicationPackageHash
    [IO.File]::WriteAllText($plan, ($entry | ConvertTo-Json -Depth 10), [Text.UTF8Encoding]::new($false))
    $output = Join-Path $OutputRoot $entry.file
    & $binary $plan (Join-Path $OriginalPackagesRoot $entry.file) (Join-Path (Join-Path $ClassicScenariosRoot $scenario.name) 'Data SD') (Join-Path $repoRoot 'src/storage/packages/application/realmz-classic-application-library.realmz2') $output (Join-Path $OutputRoot ($entry.campaignId + '-receipt.json'))
    if ($LASTEXITCODE -ne 0) { throw "Shop restoration failed: $($entry.campaignId)" }
    if ((Get-FileHash -LiteralPath $output -Algorithm SHA256).Hash.ToLowerInvariant() -ne $entry.newArchiveSha256) { throw 'Rebuilt archive differs from the accepted output.' }
}
Write-Host 'Reproduced all three shop-only corrections; originals and the playable bundle were not changed.'
