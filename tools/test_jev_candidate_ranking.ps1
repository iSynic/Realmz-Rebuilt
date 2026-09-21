param(
    [string]$OutputRoot = ""
)

$ErrorActionPreference = "Stop"
$toolRoot = $PSScriptRoot
$scriptPath = Join-Path $toolRoot "rank_scenario_audit_candidates.ps1"
$candidatePath = Join-Path $toolRoot "fixtures/jev-ranking-candidates.json"
$mockPath = Join-Path $toolRoot "fixtures/jev-ranking-mock-responses.json"
if ([string]::IsNullOrWhiteSpace($OutputRoot)) {
    $OutputRoot = Join-Path ([IO.Path]::GetTempPath()) ("realmz-jev-test-" + [guid]::NewGuid().ToString("N"))
}
[IO.Directory]::CreateDirectory($OutputRoot) | Out-Null
$reportPath = Join-Path $OutputRoot "report.json"

& $scriptPath -CandidatesPath $candidatePath -OutputPath $reportPath -MockResponsePath $mockPath
$report = Get-Content -LiteralPath $reportPath -Raw | ConvertFrom-Json
if ($report.mode -ne "mock") { throw "Expected mock Jev mode." }
if ($report.results.Count -ne 2) { throw "Expected two candidate results." }
$openResult = @($report.results | Where-Object { $_.candidateId -eq "open-a" })[0]
if ($openResult.model -ne "jev-1.13.0") { throw "The returned Jev model identity was not retained." }
if ($openResult.choice -ne "session-fixture") { throw "The mocked Choice answer was not retained." }
if ($openResult.requestHash.Length -ne 64) { throw "The request hash was not retained." }
if (@($report.results | Where-Object { $_.candidateId -eq "control-b" }).Count -ne 1) { throw "The control candidate was not evaluated." }
if ($report.estimatedCostUsd -le 0) { throw "Mock usage did not contribute to the cost receipt." }

$malformedPath = Join-Path $OutputRoot "malformed.json"
@{
    responses = @{
        "open-a" = @{ model = "jev-1.13.0"; answers = @{}; usage = @{ input_tokens = 1; output_tokens = 1 } }
        "control-b" = @{ model = "jev-1.13.0"; answers = @{}; usage = @{ input_tokens = 1; output_tokens = 1 } }
    }
} | ConvertTo-Json -Depth 20 | Set-Content -LiteralPath $malformedPath -Encoding utf8
$malformedReportPath = Join-Path $OutputRoot "malformed-report.json"
& $scriptPath -CandidatesPath $candidatePath -OutputPath $malformedReportPath -MockResponsePath $malformedPath
$malformedReport = Get-Content -LiteralPath $malformedReportPath -Raw | ConvertFrom-Json
if ($malformedReport.results[0].error.kind -ne "malformed_response") { throw "Malformed Jev output was not rejected." }

$missingCredentialReportPath = Join-Path $OutputRoot "missing-credential-report.json"
& $scriptPath -CandidatesPath $candidatePath -OutputPath $missingCredentialReportPath -ApiKeyVariable "REALMZ_TEST_TYPESAFE_KEY_DOES_NOT_EXIST"
$missingCredentialReport = Get-Content -LiteralPath $missingCredentialReportPath -Raw | ConvertFrom-Json
if ($missingCredentialReport.results[0].error.kind -ne "credentials_unavailable") { throw "Unavailable credentials did not leave a deterministic report." }

$serviceFailureReportPath = Join-Path $OutputRoot "service-failure-report.json"
& $scriptPath -CandidatesPath $candidatePath -OutputPath $serviceFailureReportPath -Endpoint "http://127.0.0.1:1/v1/systemone"
$serviceFailureReport = Get-Content -LiteralPath $serviceFailureReportPath -Raw | ConvertFrom-Json
if ($serviceFailureReport.results[0].error.kind -ne "service_failure") { throw "Unavailable Jev service did not leave a deterministic report." }

$dryReportPath = Join-Path $OutputRoot "dry-report.json"
& $scriptPath -CandidatesPath $candidatePath -OutputPath $dryReportPath -DryRun
$dryReport = Get-Content -LiteralPath $dryReportPath -Raw | ConvertFrom-Json
if ($dryReport.mode -ne "dry-run" -or $dryReport.results[0].dryRun -ne $true) { throw "Dry-run deterministic fallback was not retained." }

$tooManyPath = Join-Path $OutputRoot "too-many.json"
@{ candidates = @(1..41 | ForEach-Object { @{ candidateId = "candidate-$_"; tier = 3; control = $false } }) } | ConvertTo-Json -Depth 20 | Set-Content -LiteralPath $tooManyPath -Encoding utf8
$limitFailed = $false
try {
    & $scriptPath -CandidatesPath $tooManyPath -OutputPath (Join-Path $OutputRoot "too-many-report.json") -DryRun
} catch {
    $limitFailed = $_.Exception.Message -like "*more than 40 candidates*"
}
if (-not $limitFailed) { throw "The Jev candidate limit was not enforced." }

Write-Host "Jev ranking mock tests passed: $reportPath"
