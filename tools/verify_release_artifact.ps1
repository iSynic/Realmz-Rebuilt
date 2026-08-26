param(
    [Parameter(Mandatory = $true)]
    [ValidateSet("Windows Desktop", "Linux", "macOS")]
    [string]$Preset,
    [Parameter(Mandatory = $true)]
    [string]$Output,
    [Parameter(Mandatory = $true)]
    [string]$ExportLog
)

$ErrorActionPreference = "Stop"
$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path
$outputPath = (Resolve-Path -LiteralPath $Output).Path
$logPath = (Resolve-Path -LiteralPath $ExportLog).Path
$artifactDirectory = Split-Path -Parent $outputPath
$logText = Get-Content -Raw -LiteralPath $logPath
if ($logText -match '(?m)^(?:WARNING|ERROR|SCRIPT ERROR):') {
    throw "Release export emitted a warning or error: $($Matches[0])"
}
$forbidden = 'Storing File:\s+res://(?:addons/godot_mcp(?:/|\\)|tests(?:/|\\)|tools(?:/|\\)|docs(?:/|\\)|contracts(?:/|\\)|artifacts(?:/|\\)|\.references(?:/|\\)|\.github(?:/|\\)|\.mcp\.json|AGENTS\.md|README\.md)'
if ($logText -match $forbidden) {
    throw "Release export contains an excluded development resource: $($Matches[0])"
}
$packagePaths = @([regex]::Matches($logText, 'Storing File:\s+(res://[^\r\n]+\.realmz2)') | ForEach-Object { $_.Groups[1].Value } | Sort-Object -Unique)
if (($packagePaths -join '|') -ne 'res://src/infrastructure/characters/realmz-classic-character-library.realmz2') {
    throw "Release export contains an unexpected Realmz package set: $($packagePaths -join ', ')"
}

$artifact = Get-Item -LiteralPath $outputPath
$artifactHash = (Get-FileHash -LiteralPath $outputPath -Algorithm SHA256).Hash.ToLowerInvariant()
$pckName = ""
$pckBytes = 0L
$pckHash = ""
if ($Preset -eq "macOS") {
    Add-Type -AssemblyName System.IO.Compression.FileSystem
    $archive = [System.IO.Compression.ZipFile]::OpenRead($outputPath)
    try {
        $entries = @($archive.Entries | Where-Object { $_.FullName.EndsWith(".pck", [System.StringComparison]::OrdinalIgnoreCase) })
        if ($entries.Count -ne 1) { throw "macOS release archive must contain exactly one PCK." }
        $entry = $entries[0]
        $pckName = $entry.FullName
        $pckBytes = $entry.Length
        $stream = $entry.Open()
        $sha = [System.Security.Cryptography.SHA256]::Create()
        try { $pckHash = [Convert]::ToHexString($sha.ComputeHash($stream)).ToLowerInvariant() }
        finally { $sha.Dispose(); $stream.Dispose() }
    } finally {
        $archive.Dispose()
    }
} else {
    $pckPath = [System.IO.Path]::ChangeExtension($outputPath, ".pck")
    if (-not (Test-Path -LiteralPath $pckPath -PathType Leaf)) { throw "$Preset release is missing its adjacent PCK." }
    $pck = Get-Item -LiteralPath $pckPath
    $pckName = $pck.Name
    $pckBytes = $pck.Length
    $pckHash = (Get-FileHash -LiteralPath $pckPath -Algorithm SHA256).Hash.ToLowerInvariant()
}
if ($artifact.Length -le 0 -or $pckBytes -le 0) { throw "$Preset release contains an empty artifact or PCK." }

$fixturePath = Join-Path $repoRoot "tests\fixtures\packages\realmz2-synthetic-fixture.realmz2"
$manifest = [ordered]@{
    formatVersion = 1
    commit = (& git -C $repoRoot rev-parse HEAD).Trim()
    preset = $Preset
    artifact = [ordered]@{ file = $artifact.Name; bytes = $artifact.Length; sha256 = $artifactHash }
    pck = [ordered]@{ file = $pckName; bytes = $pckBytes; sha256 = $pckHash }
    certificationPackage = [ordered]@{
        file = "realmz2-synthetic-fixture.realmz2"
        sha256 = (Get-FileHash -LiteralPath $fixturePath -Algorithm SHA256).Hash.ToLowerInvariant()
        commercialPayload = $false
    }
}
$manifestPath = Join-Path $artifactDirectory "release-manifest.json"
[System.IO.File]::WriteAllText($manifestPath, (($manifest | ConvertTo-Json -Depth 5) + "`n"), [System.Text.UTF8Encoding]::new($false))
Write-Host "$Preset release artifact verified: artifact=$artifactHash pck=$pckHash manifest=$manifestPath"
