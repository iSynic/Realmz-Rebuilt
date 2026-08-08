param(
    [Parameter(Mandatory = $true)]
    [string]$SourceRepository
)

$ErrorActionPreference = "Stop"
$toolRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
$repoRoot = Split-Path -Parent (Split-Path -Parent $toolRoot)
$catalogPath = Join-Path $toolRoot "catalog.json"
$catalog = Get-Content -Raw -LiteralPath $catalogPath | ConvertFrom-Json
$sourceRoot = (Resolve-Path -LiteralPath $SourceRepository).Path
$destinationRoot = Join-Path $repoRoot "src/presentation/assets/classic-controls"
$manifestPath = Join-Path $repoRoot "src/presentation/assets/classic-ui-assets.json"

$resolvedCommit = (& git -C $sourceRoot rev-parse "$($catalog.source_commit)^{commit}").Trim()
if ($LASTEXITCODE -ne 0 -or $resolvedCommit -ne $catalog.source_commit) {
    throw "The requested Remake source commit is unavailable: $($catalog.source_commit)"
}

$stagingRoot = Join-Path ([IO.Path]::GetTempPath()) ("realmz2-ui-assets-" + [Guid]::NewGuid().ToString("N"))
$archivePath = Join-Path $stagingRoot "source.zip"
$extractRoot = Join-Path $stagingRoot "source"
$outputRoot = Join-Path $stagingRoot "output"
$sidecarRoot = Join-Path $stagingRoot "sidecars"
New-Item -ItemType Directory -Path $extractRoot, $outputRoot, $sidecarRoot | Out-Null

try {
    $sourcePaths = @($catalog.assets | ForEach-Object { $_.source_path } | Sort-Object -Unique)
    & git -C $sourceRoot archive --format=zip --output=$archivePath $catalog.source_commit -- @sourcePaths
    if ($LASTEXITCODE -ne 0) {
        throw "git archive failed"
    }
    Expand-Archive -LiteralPath $archivePath -DestinationPath $extractRoot

    $records = @()
    foreach ($entry in $catalog.assets) {
        $sourcePath = Join-Path $extractRoot ($entry.source_path -replace "/", [IO.Path]::DirectorySeparatorChar)
        if (-not (Test-Path -LiteralPath $sourcePath -PathType Leaf)) {
            throw "Catalog source is missing from the recorded commit: $($entry.source_path)"
        }
        $bytes = [IO.File]::ReadAllBytes($sourcePath)
        if ($bytes.Length -lt 24 -or [Text.Encoding]::ASCII.GetString($bytes, 1, 3) -ne "PNG") {
            throw "Only validated PNG controls may be imported: $($entry.source_path)"
        }
        $width = [Net.IPAddress]::NetworkToHostOrder([BitConverter]::ToInt32($bytes, 16))
        $height = [Net.IPAddress]::NetworkToHostOrder([BitConverter]::ToInt32($bytes, 20))
        if ($width -le 0 -or $height -le 0) {
            throw "Invalid PNG dimensions: $($entry.source_path)"
        }
        $targetPath = Join-Path $outputRoot ($entry.target_path -replace "/", [IO.Path]::DirectorySeparatorChar)
        New-Item -ItemType Directory -Path (Split-Path -Parent $targetPath) -Force | Out-Null
        [IO.File]::WriteAllBytes($targetPath, $bytes)
        $sha256 = (Get-FileHash -Algorithm SHA256 -LiteralPath $targetPath).Hash.ToLowerInvariant()
        $classification = if ($entry.PSObject.Properties.Name -contains "classification") { $entry.classification } else { "tracked-remake-bitmap" }
        $evidenceStatus = if ($entry.PSObject.Properties.Name -contains "evidence_status") { $entry.evidence_status } else { "remake-scene-use" }
        $evidenceNote = if ($entry.PSObject.Properties.Name -contains "evidence_note") { $entry.evidence_note } else { "Semantic use is proven by the tracked Remake scene; direct extraction from a Classic resource fork is not claimed." }
        $evidence = [ordered]@{
            status = $evidenceStatus
            path = $catalog.contexts.($entry.context)
            note = $evidenceNote
        }
        if ($entry.PSObject.Properties.Name -contains "evidence_repository") {
            $evidence["repository"] = $entry.evidence_repository
        }
        if ($entry.PSObject.Properties.Name -contains "evidence_commit") {
            $evidence["commit"] = $entry.evidence_commit
        }
        $records += [ordered]@{
            id = $entry.id
            path = "res://src/presentation/assets/classic-controls/$($entry.target_path)"
            source_repository = $catalog.source_repository
            source_commit = $catalog.source_commit
            source_path = $entry.source_path
            native_width = $width
            native_height = $height
            sha256 = $sha256
            classification = $classification
            classic_evidence = $evidence
            rendering = [ordered]@{
                filter = "nearest"
                allowed_scales = @(1, 2)
                source_pixels_modified = $false
            }
        }
    }

    $manifest = [ordered]@{
        schema_version = 1
        source_repository = $catalog.source_repository
        source_commit = $catalog.source_commit
        generated_by = "tools/ui-assets/sync-classic-ui-assets.ps1"
        assets = $records
    }
    $manifestText = ($manifest | ConvertTo-Json -Depth 8) + [Environment]::NewLine
    $stagedManifest = Join-Path $stagingRoot "classic-ui-assets.json"
    [IO.File]::WriteAllText($stagedManifest, $manifestText, [Text.UTF8Encoding]::new($false))
    $parsed = Get-Content -Raw -LiteralPath $stagedManifest | ConvertFrom-Json
    if ($parsed.assets.Count -ne $catalog.assets.Count) {
        throw "Generated asset manifest failed validation"
    }

    if (Test-Path -LiteralPath $destinationRoot) {
        foreach ($sidecar in Get-ChildItem -LiteralPath $destinationRoot -Recurse -File -Filter "*.import") {
            $relativePath = [IO.Path]::GetRelativePath($destinationRoot, $sidecar.FullName)
            $stagedSidecar = Join-Path $sidecarRoot $relativePath
            New-Item -ItemType Directory -Path (Split-Path -Parent $stagedSidecar) -Force | Out-Null
            Copy-Item -LiteralPath $sidecar.FullName -Destination $stagedSidecar
        }
        Remove-Item -LiteralPath $destinationRoot -Recurse -Force
    }
    New-Item -ItemType Directory -Path $destinationRoot | Out-Null
    Copy-Item -Path (Join-Path $outputRoot "*") -Destination $destinationRoot -Recurse -Force
    foreach ($sidecar in Get-ChildItem -LiteralPath $sidecarRoot -Recurse -File -Filter "*.import") {
        $relativePath = [IO.Path]::GetRelativePath($sidecarRoot, $sidecar.FullName)
        $sourceAssetRelativePath = $relativePath.Substring(0, $relativePath.Length - ".import".Length)
        if (-not (Test-Path -LiteralPath (Join-Path $destinationRoot $sourceAssetRelativePath) -PathType Leaf)) {
            continue
        }
        $destinationSidecar = Join-Path $destinationRoot $relativePath
        New-Item -ItemType Directory -Path (Split-Path -Parent $destinationSidecar) -Force | Out-Null
        Copy-Item -LiteralPath $sidecar.FullName -Destination $destinationSidecar
    }
    Copy-Item -LiteralPath $stagedManifest -Destination $manifestPath -Force
    Write-Host "Imported $($records.Count) exact-commit Classic UI assets."
}
finally {
    if (Test-Path -LiteralPath $stagingRoot) {
        Remove-Item -LiteralPath $stagingRoot -Recurse -Force
    }
}
