param(
    [Parameter(Mandatory = $true)]
    [string]$ManifestPath,
    [string]$GodotPath = ""
)

$ErrorActionPreference = "Stop"
$repoRoot = Split-Path -Parent $PSScriptRoot
if (-not (Test-Path -LiteralPath $ManifestPath)) {
    throw "Corpus manifest does not exist: $ManifestPath"
}
if ([string]::IsNullOrWhiteSpace($GodotPath)) {
    $godotCommand = Get-Command Godot_v4.7.1-stable_win64_console.exe -ErrorAction SilentlyContinue
    if ($null -eq $godotCommand) {
        $godotCommand = Get-Command godot -ErrorAction Stop
    }
    $GodotPath = $godotCommand.Source
}

$manifest = Get-Content -Raw -LiteralPath $ManifestPath | ConvertFrom-Json
if ($manifest.schemaVersion -ne 1 -or $null -eq $manifest.campaigns -or $manifest.campaigns.Count -eq 0) {
    throw "Corpus manifest must use schemaVersion 1 and declare at least one campaign."
}

$failures = @()
foreach ($campaign in $manifest.campaigns) {
    foreach ($field in @("id", "package", "route", "report")) {
        if ([string]::IsNullOrWhiteSpace($campaign.$field)) {
            throw "Corpus entry is missing $field."
        }
    }
    foreach ($inputPath in @($campaign.package, $campaign.route)) {
        if (-not (Test-Path -LiteralPath $inputPath)) {
            throw "Corpus input does not exist: $inputPath"
        }
    }
    $reportDirectory = Split-Path -Parent $campaign.report
    if (-not [string]::IsNullOrWhiteSpace($reportDirectory)) {
        New-Item -ItemType Directory -Force -Path $reportDirectory | Out-Null
    }
    Write-Host "CERTIFY $($campaign.id)"
    & $GodotPath --headless --path $repoRoot --script res://tools/route_acceptance.gd -- $campaign.package $campaign.route $campaign.report
    if ($LASTEXITCODE -ne 0) {
        $failures += $campaign.id
    }
}

if ($failures.Count -gt 0) {
    throw "Campaign route certification failed: $($failures -join ', ')"
}
Write-Host "Corpus route certification passed for $($manifest.campaigns.Count) campaign(s)."
