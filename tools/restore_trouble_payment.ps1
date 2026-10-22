param(
    [Parameter(Mandatory=$true)][string]$ProvidenceRoot,
    [Parameter(Mandatory=$true)][string]$NativeDataED3,
    [Parameter(Mandatory=$true)][string]$OriginalPackage,
    [Parameter(Mandatory=$true)][string]$OutputRoot
)
$ErrorActionPreference = 'Stop'
$repoRoot = Split-Path -Parent $PSScriptRoot
$bundleRoot = Join-Path $repoRoot 'src/storage/packages/bundled_campaigns'
$receipt = Get-Content -Raw (Join-Path $bundleRoot 'trouble-payment-restoration.json') | ConvertFrom-Json
if (Test-Path -LiteralPath $OutputRoot) { throw 'Choose a new output root; existing evidence is preserved.' }
$OutputRoot = [IO.Path]::GetFullPath($OutputRoot)
[IO.Directory]::CreateDirectory($OutputRoot) | Out-Null
$sourceRoot = Join-Path $OutputRoot 'providence-source'
$snapshot = Join-Path $OutputRoot 'providence.zip'
& git -C $ProvidenceRoot archive $receipt.compilerRevision --format=zip "--output=$snapshot"
if ($LASTEXITCODE -ne 0) { throw 'Pinned Providence source is unavailable.' }
Expand-Archive -LiteralPath $snapshot -DestinationPath $sourceRoot
$exampleRoot = Join-Path $sourceRoot 'crates/providence-application-library/examples'
[IO.Directory]::CreateDirectory($exampleRoot) | Out-Null
$helper = Join-Path $PSScriptRoot 'restore_trouble_payment.rs'
if ((Get-FileHash -LiteralPath $helper -Algorithm SHA256).Hash.ToLowerInvariant() -ne $receipt.compilerToolSha256) { throw 'Restoration helper hash mismatch.' }
Copy-Item -LiteralPath $helper -Destination (Join-Path $exampleRoot 'restore_trouble_payment.rs')
$targetRoot = Join-Path $OutputRoot 'target'
& cargo build --locked --release --manifest-path (Join-Path $sourceRoot 'Cargo.toml') --target-dir $targetRoot -p providence-application-library --example restore_trouble_payment
if ($LASTEXITCODE -ne 0) { throw 'Providence restoration build failed.' }
$binary = Join-Path $targetRoot 'release/examples/restore_trouble_payment.exe'
$output = Join-Path $OutputRoot $receipt.file
& $binary $OriginalPackage $NativeDataED3 $output (Join-Path $OutputRoot 'receipt.json')
if ($LASTEXITCODE -ne 0) { throw 'Payment program restoration failed.' }
if ((Get-FileHash -LiteralPath $output -Algorithm SHA256).Hash.ToLowerInvariant() -ne $receipt.archiveSha256) { throw 'Rebuilt archive differs from the accepted output.' }
Write-Host 'Reproduced the exact native payment restoration; originals and the playable bundle were not changed.'
