param(
    [Parameter(Mandatory = $true)]
    [string]$SourceRepository,
    [string]$CastleRepository = "",
    [string]$UiDonorRepository = "",
    [string]$PictDecoderPath = ""
)

$ErrorActionPreference = "Stop"
$toolRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
$repoRoot = Split-Path -Parent (Split-Path -Parent $toolRoot)
$catalogPath = Join-Path $toolRoot "catalog.json"
$catalog = Get-Content -Raw -LiteralPath $catalogPath | ConvertFrom-Json
$sourceRoot = (Resolve-Path -LiteralPath $SourceRepository).Path
$classicEntries = @($catalog.assets | Where-Object { $_.source_kind -in @("classic-cicn", "classic-pict", "classic-crsr") })
$classicPictEntries = @($classicEntries | Where-Object { $_.source_kind -eq "classic-pict" })
$uiDonorEntries = @($catalog.assets | Where-Object { $_.source_kind -eq "licensed-ui-donor" })
$castleRoot = ""
$uiDonorRoot = ""
$destinationRoot = Join-Path $repoRoot "src/presentation/assets/classic-controls"
$manifestPath = Join-Path $repoRoot "src/presentation/assets/classic-ui-assets.json"
$cicnExporterPath = Join-Path $toolRoot "export-classic-cicn.ps1"
$pictExporterPath = Join-Path $toolRoot "export-classic-pict.ps1"
$crsrExporterPath = Join-Path $toolRoot "export-classic-crsr.ps1"

$resolvedCommit = (& git -C $sourceRoot rev-parse "$($catalog.source_commit)^{commit}").Trim()
if ($LASTEXITCODE -ne 0 -or $resolvedCommit -ne $catalog.source_commit) {
    throw "The requested Remake source commit is unavailable: $($catalog.source_commit)"
}
if ($classicEntries.Count -gt 0) {
    if (-not $CastleRepository) {
        throw "CastleRepository is required for cataloged Classic resource-fork assets"
    }
    $castleRoot = (Resolve-Path -LiteralPath $CastleRepository).Path
    $castleCommits = @($classicEntries | ForEach-Object { $_.source_commit } | Sort-Object -Unique)
    if ($castleCommits.Count -ne 1) {
        throw "Classic resource-fork assets must share one Castle source commit"
    }
    $resolvedCastleCommit = (& git -C $castleRoot rev-parse "$($castleCommits[0])^{commit}").Trim()
    if ($LASTEXITCODE -ne 0 -or $resolvedCastleCommit -ne $castleCommits[0]) {
        throw "The requested Castle source commit is unavailable: $($castleCommits[0])"
    }
    if ($classicPictEntries.Count -gt 0 -and -not $PictDecoderPath) {
        throw "PictDecoderPath is required for cataloged Classic PICT assets"
    }
}
if ($uiDonorEntries.Count -gt 0) {
    if (-not $UiDonorRepository) {
        throw "UiDonorRepository is required for cataloged licensed UI donor assets"
    }
    $uiDonorRoot = (Resolve-Path -LiteralPath $UiDonorRepository).Path
    $uiDonorCommits = @($uiDonorEntries | ForEach-Object { $_.source_commit } | Sort-Object -Unique)
    foreach ($uiDonorCommit in $uiDonorCommits) {
        $resolvedUiDonorCommit = (& git -C $uiDonorRoot rev-parse "$uiDonorCommit`^{commit}").Trim()
        if ($LASTEXITCODE -ne 0 -or $resolvedUiDonorCommit -ne $uiDonorCommit) {
            throw "The requested licensed UI donor commit is unavailable: $uiDonorCommit"
        }
    }
}

$stagingRoot = Join-Path ([IO.Path]::GetTempPath()) ("realmz2-ui-assets-" + [Guid]::NewGuid().ToString("N"))
$archivePath = Join-Path $stagingRoot "source.zip"
$extractRoot = Join-Path $stagingRoot "source"
$castleArchivePath = Join-Path $stagingRoot "castle-source.zip"
$castleExtractRoot = Join-Path $stagingRoot "castle-source"
$uiDonorExtractRoot = Join-Path $stagingRoot "ui-donor-source"
$outputRoot = Join-Path $stagingRoot "output"
$sidecarRoot = Join-Path $stagingRoot "sidecars"
New-Item -ItemType Directory -Path $extractRoot, $castleExtractRoot, $uiDonorExtractRoot, $outputRoot, $sidecarRoot | Out-Null

try {
    $sourcePaths = @($catalog.assets | Where-Object { $_.source_kind -notin @("classic-cicn", "classic-pict", "classic-crsr", "licensed-ui-donor") } | ForEach-Object { $_.source_path } | Sort-Object -Unique)
    & git -C $sourceRoot archive --format=zip --output=$archivePath $catalog.source_commit -- @sourcePaths
    if ($LASTEXITCODE -ne 0) {
        throw "git archive failed"
    }
    Expand-Archive -LiteralPath $archivePath -DestinationPath $extractRoot
    if ($classicEntries.Count -gt 0) {
        $castleSourcePaths = @($classicEntries | ForEach-Object { $_.source_path } | Sort-Object -Unique)
        $castleCommit = $classicEntries[0].source_commit
        & git -C $castleRoot archive --format=zip --output=$castleArchivePath $castleCommit -- @castleSourcePaths
        if ($LASTEXITCODE -ne 0) {
            throw "Castle git archive failed"
        }
        Expand-Archive -LiteralPath $castleArchivePath -DestinationPath $castleExtractRoot
    }
    foreach ($uiDonorCommit in @($uiDonorEntries | ForEach-Object { $_.source_commit } | Sort-Object -Unique)) {
        $commitRoot = Join-Path $uiDonorExtractRoot $uiDonorCommit
        $commitArchivePath = Join-Path $stagingRoot ("ui-donor-" + $uiDonorCommit + ".zip")
        $uiDonorPaths = @($uiDonorEntries | Where-Object { $_.source_commit -eq $uiDonorCommit } | ForEach-Object { $_.source_path } | Sort-Object -Unique)
        & git -C $uiDonorRoot archive --format=zip --output=$commitArchivePath $uiDonorCommit -- @uiDonorPaths
        if ($LASTEXITCODE -ne 0) {
            throw "Licensed UI donor git archive failed"
        }
        New-Item -ItemType Directory -Path $commitRoot | Out-Null
        Expand-Archive -LiteralPath $commitArchivePath -DestinationPath $commitRoot
    }

    $records = @()
    foreach ($entry in $catalog.assets) {
        $isClassicCicn = $entry.source_kind -eq "classic-cicn"
        $isClassicPict = $entry.source_kind -eq "classic-pict"
        $isClassicCrsr = $entry.source_kind -eq "classic-crsr"
        $isLicensedUiDonor = $entry.source_kind -eq "licensed-ui-donor"
        $entryExtractRoot = if ($isClassicCicn -or $isClassicPict -or $isClassicCrsr) {
            $castleExtractRoot
        }
        elseif ($isLicensedUiDonor) {
            Join-Path $uiDonorExtractRoot $entry.source_commit
        }
        else {
            $extractRoot
        }
        $sourcePath = Join-Path $entryExtractRoot ($entry.source_path -replace "/", [IO.Path]::DirectorySeparatorChar)
        if (-not (Test-Path -LiteralPath $sourcePath -PathType Leaf)) {
            throw "Catalog source is missing from the recorded commit: $($entry.source_path)"
        }
        if ($entry.PSObject.Properties.Name -contains "source_file_sha256") {
            $sourceSha256 = (Get-FileHash -Algorithm SHA256 -LiteralPath $sourcePath).Hash.ToLowerInvariant()
            if ($sourceSha256 -ne $entry.source_file_sha256) {
                throw "Catalog source hash mismatch: $($entry.source_path)"
            }
        }
        $targetPath = Join-Path $outputRoot ($entry.target_path -replace "/", [IO.Path]::DirectorySeparatorChar)
        New-Item -ItemType Directory -Path (Split-Path -Parent $targetPath) -Force | Out-Null
        if ($isClassicCicn) {
            & $cicnExporterPath -ResourceForkPath $sourcePath -ResourceId $entry.resource_id -OutputPath $targetPath
        }
        elseif ($isClassicPict) {
            $pictArguments = @{
                ResourceForkPath = $sourcePath
                ResourceId = $entry.resource_id
                PictDecoderPath = $PictDecoderPath
                OutputPath = $targetPath
            }
            if ($entry.PSObject.Properties.Name -contains "crop_width") {
                $pictArguments["CropX"] = $entry.crop_x
                $pictArguments["CropY"] = $entry.crop_y
                $pictArguments["CropWidth"] = $entry.crop_width
                $pictArguments["CropHeight"] = $entry.crop_height
            }
            & $pictExporterPath @pictArguments
        }
        elseif ($isClassicCrsr) {
            & $crsrExporterPath -ResourceForkPath $sourcePath -ResourceId $entry.resource_id -ExpectedHotspotX $entry.hotspot_x -ExpectedHotspotY $entry.hotspot_y -OutputPath $targetPath
        }
        else {
            [IO.File]::WriteAllBytes($targetPath, [IO.File]::ReadAllBytes($sourcePath))
        }
        $bytes = [IO.File]::ReadAllBytes($targetPath)
        if ($bytes.Length -lt 24 -or [Text.Encoding]::ASCII.GetString($bytes, 1, 3) -ne "PNG") {
            throw "Only validated PNG controls may be imported: $($entry.source_path)"
        }
        $width = [Net.IPAddress]::NetworkToHostOrder([BitConverter]::ToInt32($bytes, 16))
        $height = [Net.IPAddress]::NetworkToHostOrder([BitConverter]::ToInt32($bytes, 20))
        if ($width -le 0 -or $height -le 0) {
            throw "Invalid PNG dimensions: $($entry.source_path)"
        }
        $sha256 = (Get-FileHash -Algorithm SHA256 -LiteralPath $targetPath).Hash.ToLowerInvariant()
        if ($entry.PSObject.Properties.Name -contains "sha256" -and $sha256 -ne $entry.sha256) {
            throw "Catalog output hash mismatch: $($entry.target_path)"
        }
        $classification = if ($entry.PSObject.Properties.Name -contains "classification") { $entry.classification } else { "tracked-remake-bitmap" }
        $evidenceStatus = if ($entry.PSObject.Properties.Name -contains "evidence_status") { $entry.evidence_status } else { "remake-scene-use" }
        $evidenceNote = if ($entry.PSObject.Properties.Name -contains "evidence_note") { $entry.evidence_note } else { "Semantic use is proven by the tracked Remake scene; direct extraction from a Classic resource fork is not claimed." }
        $evidence = [ordered]@{
            status = $evidenceStatus
            path = if ($entry.PSObject.Properties.Name -contains "evidence_path") { $entry.evidence_path } else { $catalog.contexts.($entry.context) }
            note = $evidenceNote
        }
        if ($entry.PSObject.Properties.Name -contains "evidence_repository") {
            $evidence["repository"] = $entry.evidence_repository
        }
        if ($entry.PSObject.Properties.Name -contains "evidence_commit") {
            $evidence["commit"] = $entry.evidence_commit
        }
        $record = [ordered]@{
            id = $entry.id
            path = "res://src/presentation/assets/classic-controls/$($entry.target_path)"
            source_repository = if ($entry.PSObject.Properties.Name -contains "source_repository") { $entry.source_repository } else { $catalog.source_repository }
            source_commit = if ($entry.PSObject.Properties.Name -contains "source_commit") { $entry.source_commit } else { $catalog.source_commit }
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
        if ($isClassicCrsr) {
            $record["cursor_hotspot"] = @($entry.hotspot_x, $entry.hotspot_y)
        }
        if ($isClassicCicn -or $isClassicPict -or $isClassicCrsr) {
            $record["source_file_sha256"] = $entry.source_file_sha256
            $record["source_resource_type"] = $entry.resource_type
            $record["source_resource_id"] = $entry.resource_id
        }
        if ($isClassicPict -and $entry.PSObject.Properties.Name -contains "crop_width") {
            $record["source_rectangle"] = @($entry.crop_x, $entry.crop_y, $entry.crop_width, $entry.crop_height)
        }
        if ($entry.PSObject.Properties.Name -contains "license") {
            $record["license"] = $entry.license
        }
        if ($entry.PSObject.Properties.Name -contains "license_note") {
            $record["license_note"] = $entry.license_note
        }
        $records += $record
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
