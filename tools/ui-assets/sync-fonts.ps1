param(
    [string]$RemakeRepository = "",
    [string]$PythonExecutable = "python"
)

$ErrorActionPreference = "Stop"

$toolRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
$repoRoot = Split-Path -Parent (Split-Path -Parent $toolRoot)
$destinationRoot = Join-Path $repoRoot "src/presentation/assets/fonts"
$stagingRoot = Join-Path ([IO.Path]::GetTempPath()) ("realmz2-fonts-" + [Guid]::NewGuid().ToString("N"))
$googleFontsCommit = "2d85e20401920891efb7cd6272d6339685df2820"
$castleCommit = "491816ad60037394f92c428e99c004494d3c28b3"
$remakeCommit = "86cf2bf391ef0c43ba31c1633ddd63b7e67e3d61"
$remakeFontSha256 = "597df5baae37e494f90f6e5b48714e723900ed99e6b29a1734d1e405b79ed2cf"
$remakeLicenseArchiveSha256 = "5ee3c5ede6fd1062d232f748c28dc33806d758f93bbb554f520b259ac4ad7a84"
$grenzeSha256 = "701b299d8dc002a2b4bea2ff0f1272c0e4081a2835914354804565c410d0c637"
$grenzeLicenseSha256 = "bca29af2c3c9e142d11f523f414902ab8fb9ab8ffa3c34c63b6b72aa4e7d6acc"
$modernizedGlyphSha256 = "1f0420531587dc657e5fc06ea8014440a42f3dc79f8ec6c0eb5b43b6f32827e9"
$modernizedBuilderSha256 = "4b4bd1bfd21c4fcf44c5aba7cb304495dd349b3ca0264b315b6fb97207fd3acd"
$modernizedRulesSha256 = "429ef0ab43d1fc91db4c055e6fccef8f790ac681e4f4086bf7e5a445a20b261c"
$modernizedVerifierSha256 = "d630209d14f51da9fec92f920037454516a37aed95ee7b3dcd410a5250ca4b95"
$fontToolsRequirementsSha256 = "c8f1eaefa5e6398ded5498c3025fd623e14956a3f558a82d0c50a4db60f87d80"
$modernizedFontSha256 = "79c7b7d54ad746db41b103ffc9f1bc3fabacb2cf2b594af080c0ac2c2fc7705d"
$modernizedGlyphPath = Join-Path $toolRoot "theldrow-modernized-glyphs.json"
$modernizedBuilderPath = Join-Path $toolRoot "build-theldrow-modernized.py"
$modernizedRulesPath = Join-Path $toolRoot "theldrow-modernized-rules.json"
$modernizedVerifierPath = Join-Path $toolRoot "verify-theldrow-modernized.py"
$fontToolsRequirementsPath = Join-Path $toolRoot "requirements-theldrow-fonts.txt"
$googleBase = "https://raw.githubusercontent.com/google/fonts/$googleFontsCommit/ofl"
$castleBase = "https://raw.githubusercontent.com/Realmz-Castle/realmz/$castleCommit"

if ([string]::IsNullOrWhiteSpace($RemakeRepository)) {
    $candidate = Join-Path $repoRoot ".references/remake-functional"
    if (Test-Path -LiteralPath $candidate) { $RemakeRepository = $candidate }
}
if ([string]::IsNullOrWhiteSpace($RemakeRepository)) {
    throw "Supply -RemakeRepository with a clean Realmz Remake checkout pinned at $remakeCommit"
}
$RemakeRepository = [IO.Path]::GetFullPath($RemakeRepository)
if (-not (Test-Path -LiteralPath $RemakeRepository -PathType Container)) {
    throw "Remake repository does not exist: $RemakeRepository"
}
$remakeHead = (& git -C $RemakeRepository rev-parse HEAD).Trim()
if ($LASTEXITCODE -ne 0 -or $remakeHead -ne $remakeCommit) {
    throw "Remake repository must be pinned at $remakeCommit; found $remakeHead"
}
$remakeStatus = @(& git -C $RemakeRepository status --porcelain)
if ($LASTEXITCODE -ne 0 -or $remakeStatus.Count -gt 0) {
    throw "Remake repository must be clean before font synchronization"
}

$downloads = @(
    @{ Uri = "$googleBase/alegreya/Alegreya%5Bwght%5D.ttf"; Target = "Alegreya-Variable.ttf"; Sha256 = "ba5564634b93a8f8ba57b48cd4f1ae7417d2b4656fbac779028679b00de3cf12" },
    @{ Uri = "$googleBase/alegreyasans/AlegreyaSans-Regular.ttf"; Target = "AlegreyaSans-Regular.ttf"; Sha256 = "8fab634196007afca839f1e5a6fb300976daff55d8528b590ef032f01b14ea10" },
    @{ Uri = "$googleBase/alegreyasans/AlegreyaSans-Bold.ttf"; Target = "AlegreyaSans-Bold.ttf"; Sha256 = "a3055a1893759bdbd7504bb22abc583769e7974c49353176eac0b03792c9fb8e" },
    @{ Uri = "$googleBase/alegreya/OFL.txt"; Target = "licenses/Alegreya-OFL.txt"; Sha256 = "f6f60d5d4cf4f4b1fc4e41353c897a2f5a16e6396c0cd8fa8bdfd2f4586a9a68" },
    @{ Uri = "$googleBase/alegreyasans/OFL.txt"; Target = "licenses/AlegreyaSans-OFL.txt"; Sha256 = "0677891e6a143f297350d260ad766ad33bfc18ed5fa4f213acf648d6b597ec1a" },
    @{ Uri = "$googleBase/grenzegotisch/GrenzeGotisch%5Bwght%5D.ttf"; Target = "source/GrenzeGotisch-Variable.ttf"; Sha256 = $grenzeSha256 },
    @{ Uri = "$googleBase/grenzegotisch/OFL.txt"; Target = "licenses/GrenzeGotisch-OFL.txt"; Sha256 = $grenzeLicenseSha256 },
    @{ Uri = "$castleBase/resources/Black%20Chancery.ttf"; Target = "BlackChancery-Realmz.ttf"; Sha256 = "1a3a41b4a7ab327002897275520c200028f0303f599e77c20b0e0e6a93b24357" },
    @{ Uri = "$castleBase/resources/ChicagoFLF.ttf"; Target = "ChicagoFLF.ttf"; Sha256 = "b442111f37639e27572d9df0c5190e7480e6a7b01ec768aea47a154efab8d50d" },
    @{ Uri = "$castleBase/vendored/Inter/InterVariable.ttf"; Target = "InterVariable-Castle.ttf"; Sha256 = "4989b125924991b90d05b2d16e0e388c48f7d5bb8b30539bbf9c755278d0ccaf" },
    @{ Uri = "$castleBase/vendored/Inter/LICENSE.txt"; Target = "licenses/Inter-OFL.txt"; Sha256 = "262481e844521b326f5ecd053e59b98c8b2da78c8ee1bdbb6e8174305e54935a" },
    @{ Uri = "$castleBase/base/Realmz/Data%20Files/The%20Family%20Jewels.rsrc"; Target = "source/The Family Jewels.rsrc"; Sha256 = "8dbae6c6a418c82250dca93937c5958dacea9874d654c62da4e4dafa184dc85c" }
)

$records = @(
    @{ Id = "font.narrative.alegreya.variable"; Target = "Alegreya-Variable.ttf"; Repository = "google/fonts"; Commit = $googleFontsCommit; License = "OFL-1.1" },
    @{ Id = "font.ui.alegreya_sans.regular"; Target = "AlegreyaSans-Regular.ttf"; Repository = "google/fonts"; Commit = $googleFontsCommit; License = "OFL-1.1" },
    @{ Id = "font.ui.alegreya_sans.bold"; Target = "AlegreyaSans-Bold.ttf"; Repository = "google/fonts"; Commit = $googleFontsCommit; License = "OFL-1.1" },
    @{ Id = "license.alegreya"; Target = "licenses/Alegreya-OFL.txt"; Repository = "google/fonts"; Commit = $googleFontsCommit; License = "OFL-1.1" },
    @{ Id = "license.alegreya_sans"; Target = "licenses/AlegreyaSans-OFL.txt"; Repository = "google/fonts"; Commit = $googleFontsCommit; License = "OFL-1.1" },
    @{ Id = "font.classic.black_chancery.regular"; Target = "BlackChancery-Realmz.ttf"; Repository = "Realmz-Castle/realmz"; Commit = $castleCommit; SourcePath = "resources/Black Chancery.ttf"; License = "Public-Domain"; Role = "character names, item statistics, movement, load, and compact status text" },
    @{ Id = "font.classic.chicago_flf.regular"; Target = "ChicagoFLF.ttf"; Repository = "Realmz-Castle/realmz"; Commit = $castleCommit; SourcePath = "resources/ChicagoFLF.ttf"; License = "Public-Domain"; Role = "Classic 3D-view help text" },
    @{ Id = "font.classic.geneva_substitute.inter"; Target = "InterVariable-Castle.ttf"; Repository = "Realmz-Castle/realmz"; Commit = $castleCommit; SourcePath = "vendored/Inter/InterVariable.ttf"; License = "OFL-1.1"; Role = "Castle's open substitute for Geneva utility and detail text" },
    @{ Id = "font.classic.theldrow.bitmap"; Target = "Theldrow-Classic.fnt"; Repository = "Realmz-Castle/realmz"; Commit = $castleCommit; SourcePath = "base/Realmz/Data Files/The Family Jewels.rsrc:FONT 1601"; License = "Realmz-Art-NonCommercial"; Role = "exact default Realmz interface, dialog, and narrative text metrics" },
    @{ Id = "font.classic.theldrow.atlas"; Target = "Theldrow-Classic.png"; Repository = "Realmz-Castle/realmz"; Commit = $castleCommit; SourcePath = "base/Realmz/Data Files/The Family Jewels.rsrc:FONT 1601"; License = "Realmz-Art-NonCommercial"; Role = "exact default Realmz bitmap glyph strike" },
    @{ Id = "font.classic.theldrow.vector"; Target = "Theldrow-Classic-Vector.ttf"; Repository = "iSynic/Realmz-Remake"; Commit = $remakeCommit; SourcePath = "src/Fonts/theldrowremake.ttf"; SourceSha256 = $remakeFontSha256; MetricRepository = "Realmz-Castle/realmz"; MetricCommit = $castleCommit; MetricPath = "base/Realmz/Data Files/The Family Jewels.rsrc:FONT 1601"; MetricSha256 = "cda33a0e5f352d7d38d8fdfcc64b71db10a23fcfd9d8c7a699fa1646ffcab553"; License = "CC0-1.0"; Role = "scalable Samuel Theldrow outlines with original FONT 1601 advance widths" },
    @{ Id = "font.classic.theldrow.rebuilt"; Target = "Theldrow-Rebuilt.ttf"; Repository = "Realmz-Rebuilt/Pencil-export"; Commit = $modernizedGlyphSha256; SourcePath = "tools/ui-assets/theldrow-modernized-glyphs.json"; SourceSha256 = $modernizedGlyphSha256; MetricRepository = "Realmz-Castle/realmz"; MetricCommit = $castleCommit; MetricPath = "base/Realmz/Data Files/The Family Jewels.rsrc:FONT 1601"; MetricSha256 = "cda33a0e5f352d7d38d8fdfcc64b71db10a23fcfd9d8c7a699fa1646ffcab553"; BaselineRepository = "iSynic/Realmz-Remake"; BaselineCommit = $remakeCommit; BaselinePath = "src/Fonts/theldrowremake.ttf"; BaselineSha256 = $remakeFontSha256; UtilityRepository = "google/fonts"; UtilityCommit = $googleFontsCommit; UtilityPath = "ofl/grenzegotisch/GrenzeGotisch[wght].ttf"; UtilitySha256 = $grenzeSha256; BuildToolPath = "tools/ui-assets/build-theldrow-modernized.py"; BuildToolSha256 = $modernizedBuilderSha256; StyleRulePath = "tools/ui-assets/theldrow-modernized-rules.json"; StyleRuleSha256 = $modernizedRulesSha256; VerifyToolPath = "tools/ui-assets/verify-theldrow-modernized.py"; VerifyToolSha256 = $modernizedVerifierSha256; License = "Realmz-Art-NonCommercial + CC0-1.0 + OFL-1.1"; Role = "runtime Classic body and narrative font: project-owner-approved Pen contours, strict production-sheet proportions and mixed-case optical weight, exact Castle advances, cap-height figures, and Grenze Gotisch utility glyphs" },
    @{ Id = "license.black_chancery"; Target = "licenses/BlackChancery-PUBLIC-DOMAIN.txt"; Repository = "Realmz-Castle/realmz"; Commit = $castleCommit; License = "Public-Domain" },
    @{ Id = "license.chicago_flf"; Target = "licenses/ChicagoFLF-PUBLIC-DOMAIN.txt"; Repository = "Realmz-Castle/realmz"; Commit = $castleCommit; License = "Public-Domain" },
    @{ Id = "license.inter"; Target = "licenses/Inter-OFL.txt"; Repository = "Realmz-Castle/realmz"; Commit = $castleCommit; SourcePath = "vendored/Inter/LICENSE.txt"; License = "OFL-1.1" },
    @{ Id = "license.grenze_gotisch"; Target = "licenses/GrenzeGotisch-OFL.txt"; Repository = "google/fonts"; Commit = $googleFontsCommit; SourcePath = "ofl/grenzegotisch/OFL.txt"; License = "OFL-1.1" },
    @{ Id = "license.theldrow_realmz"; Target = "licenses/Theldrow-REALMZ-NONCOMMERCIAL.txt"; Repository = "Realmz-Castle/realmz"; Commit = $castleCommit; SourcePath = "base/Realmz/Data Files/The Family Jewels.rsrc:FONT 1601"; License = "Realmz-Art-NonCommercial" },
    @{ Id = "license.theldrow_cc0"; Target = "licenses/Theldrow-CC0-LICENSE.txt"; Repository = "iSynic/Realmz-Remake"; Commit = $remakeCommit; SourcePath = "src/Fonts/theldrow.zip:license.txt"; License = "CC0-1.0" },
    @{ Id = "readme.theldrow_cc0"; Target = "licenses/Theldrow-CC0-README.txt"; Repository = "iSynic/Realmz-Remake"; Commit = $remakeCommit; SourcePath = "src/Fonts/theldrow.zip:readme.txt"; License = "CC0-1.0" }
)

foreach ($localInput in @(
    @{ Path = $modernizedGlyphPath; Sha256 = $modernizedGlyphSha256; Name = "Pencil glyph geometry" },
    @{ Path = $modernizedBuilderPath; Sha256 = $modernizedBuilderSha256; Name = "modernized Theldrow builder" },
    @{ Path = $modernizedRulesPath; Sha256 = $modernizedRulesSha256; Name = "modernized Theldrow production rules" },
    @{ Path = $modernizedVerifierPath; Sha256 = $modernizedVerifierSha256; Name = "modernized Theldrow verifier" },
    @{ Path = $fontToolsRequirementsPath; Sha256 = $fontToolsRequirementsSha256; Name = "pinned fontTools requirements" }
)) {
    if (-not (Test-Path -LiteralPath $localInput.Path -PathType Leaf)) {
        throw "$($localInput.Name) is missing: $($localInput.Path)"
    }
    $actual = (Get-FileHash -Algorithm SHA256 -LiteralPath $localInput.Path).Hash.ToLowerInvariant()
    if ($actual -ne $localInput.Sha256) {
        throw "$($localInput.Name) hash does not match the reviewed input"
    }
}
if (-not (Test-Path -LiteralPath $fontToolsRequirementsPath -PathType Leaf)) {
    throw "Pinned fontTools requirements are missing: $fontToolsRequirementsPath"
}

New-Item -ItemType Directory -Path $stagingRoot | Out-Null
try {
    $remakeArchivePath = Join-Path $stagingRoot "remake-font-source.zip"
    & git -C $RemakeRepository archive --format=zip --output=$remakeArchivePath $remakeCommit -- "src/Fonts/theldrowremake.ttf" "src/Fonts/theldrow.zip"
    if ($LASTEXITCODE -ne 0) { throw "Failed to archive pinned Remake font sources" }
    $remakeExtractRoot = Join-Path $stagingRoot "remake-source"
    Expand-Archive -LiteralPath $remakeArchivePath -DestinationPath $remakeExtractRoot
    $remakeFontPath = Join-Path $remakeExtractRoot "src/Fonts/theldrowremake.ttf"
    $remakeLicenseArchivePath = Join-Path $remakeExtractRoot "src/Fonts/theldrow.zip"
    if ((Get-FileHash -Algorithm SHA256 -LiteralPath $remakeFontPath).Hash.ToLowerInvariant() -ne $remakeFontSha256) {
        throw "Pinned Remake Theldrow source hash does not match"
    }
    if ((Get-FileHash -Algorithm SHA256 -LiteralPath $remakeLicenseArchivePath).Hash.ToLowerInvariant() -ne $remakeLicenseArchiveSha256) {
        throw "Pinned Remake Theldrow license archive hash does not match"
    }

    foreach ($definition in $downloads) {
        $target = Join-Path $stagingRoot ($definition.Target -replace "/", [IO.Path]::DirectorySeparatorChar)
        New-Item -ItemType Directory -Path (Split-Path -Parent $target) -Force | Out-Null
        Invoke-WebRequest -UseBasicParsing -Headers @{ "User-Agent" = "Realmz2-asset-sync" } -Uri $definition.Uri -OutFile $target
        $actual = (Get-FileHash -Algorithm SHA256 -LiteralPath $target).Hash.ToLowerInvariant()
        if ($actual -ne $definition.Sha256) { throw "Downloaded font asset hash does not match: $($definition.Target)" }
    }

    & (Join-Path $toolRoot "export-classic-theldrow.ps1") `
        -ResourceForkPath (Join-Path $stagingRoot "source/The Family Jewels.rsrc") `
        -DestinationRoot $stagingRoot
    & (Join-Path $toolRoot "remetric-classic-theldrow.ps1") `
        -VectorFontPath $remakeFontPath `
        -ClassicBmFontPath (Join-Path $stagingRoot "Theldrow-Classic.fnt") `
        -OutputPath (Join-Path $stagingRoot "Theldrow-Classic-Vector.ttf")

    $pythonDependencyRoot = Join-Path $stagingRoot "python-dependencies"
    & $PythonExecutable -m pip install --disable-pip-version-check --require-hashes --no-deps --target $pythonDependencyRoot -r $fontToolsRequirementsPath
    if ($LASTEXITCODE -ne 0) { throw "Failed to install the pinned fontTools build dependency" }
    $previousPythonPath = $env:PYTHONPATH
    try {
        $env:PYTHONPATH = $pythonDependencyRoot
        & $PythonExecutable $modernizedBuilderPath `
            --glyphs $modernizedGlyphPath `
            --rules $modernizedRulesPath `
            --metrics (Join-Path $stagingRoot "Theldrow-Classic.fnt") `
            --baseline (Join-Path $stagingRoot "Theldrow-Classic-Vector.ttf") `
            --utility (Join-Path $stagingRoot "source/GrenzeGotisch-Variable.ttf") `
            --output (Join-Path $stagingRoot "Theldrow-Rebuilt.ttf")
        if ($LASTEXITCODE -ne 0) { throw "Failed to build the modernized Theldrow font" }
        & $PythonExecutable $modernizedVerifierPath `
            --font (Join-Path $stagingRoot "Theldrow-Rebuilt.ttf") `
            --metrics (Join-Path $stagingRoot "Theldrow-Classic.fnt") `
            --rules $modernizedRulesPath
        if ($LASTEXITCODE -ne 0) { throw "Modernized Theldrow failed strict production-rule verification" }
    }
    finally {
        $env:PYTHONPATH = $previousPythonPath
    }
    $actualModernizedHash = (Get-FileHash -Algorithm SHA256 -LiteralPath (Join-Path $stagingRoot "Theldrow-Rebuilt.ttf")).Hash.ToLowerInvariant()
    if ($actualModernizedHash -ne $modernizedFontSha256) {
        throw "Modernized Theldrow output hash does not match: $actualModernizedHash"
    }
    Remove-Item -LiteralPath $pythonDependencyRoot -Recurse -Force

    $remakeLicenseRoot = Join-Path $stagingRoot "remake-license"
    Expand-Archive -LiteralPath $remakeLicenseArchivePath -DestinationPath $remakeLicenseRoot
    Copy-Item -LiteralPath (Join-Path $remakeLicenseRoot "license.txt") -Destination (Join-Path $stagingRoot "licenses/Theldrow-CC0-LICENSE.txt")
    Copy-Item -LiteralPath (Join-Path $remakeLicenseRoot "readme.txt") -Destination (Join-Path $stagingRoot "licenses/Theldrow-CC0-README.txt")
    Remove-Item -LiteralPath (Join-Path $stagingRoot "source") -Recurse -Force
    Remove-Item -LiteralPath $remakeArchivePath, $remakeExtractRoot, $remakeLicenseRoot -Recurse -Force

    foreach ($notice in @("BlackChancery-PUBLIC-DOMAIN.txt", "ChicagoFLF-PUBLIC-DOMAIN.txt", "Theldrow-REALMZ-NONCOMMERCIAL.txt")) {
        $source = Join-Path $destinationRoot "licenses/$notice"
        if (-not (Test-Path -LiteralPath $source -PathType Leaf)) { throw "Committed font notice is missing: $notice" }
        Copy-Item -LiteralPath $source -Destination (Join-Path $stagingRoot "licenses/$notice")
    }

    $manifestRecords = @()
    foreach ($definition in $records) {
        $target = Join-Path $stagingRoot ($definition.Target -replace "/", [IO.Path]::DirectorySeparatorChar)
        if (-not (Test-Path -LiteralPath $target -PathType Leaf)) { throw "Staged font asset is missing: $($definition.Target)" }
        $record = [ordered]@{
            id = $definition.Id
            path = "res://src/presentation/assets/fonts/$($definition.Target)"
            source_repository = $definition.Repository
            source_commit = $definition.Commit
        }
        if ($definition.SourcePath) { $record.source_path = $definition.SourcePath }
        if ($definition.SourceSha256) { $record.source_sha256 = $definition.SourceSha256 }
        if ($definition.MetricRepository) {
            $record.metric_source_repository = $definition.MetricRepository
            $record.metric_source_commit = $definition.MetricCommit
            $record.metric_source_path = $definition.MetricPath
            $record.metric_source_sha256 = $definition.MetricSha256
        }
        if ($definition.BaselineRepository) {
            $record.baseline_source_repository = $definition.BaselineRepository
            $record.baseline_source_commit = $definition.BaselineCommit
            $record.baseline_source_path = $definition.BaselinePath
            $record.baseline_source_sha256 = $definition.BaselineSha256
        }
        if ($definition.UtilityRepository) {
            $record.utility_source_repository = $definition.UtilityRepository
            $record.utility_source_commit = $definition.UtilityCommit
            $record.utility_source_path = $definition.UtilityPath
            $record.utility_source_sha256 = $definition.UtilitySha256
        }
        if ($definition.BuildToolPath) {
            $record.build_tool_path = $definition.BuildToolPath
            $record.build_tool_sha256 = $definition.BuildToolSha256
        }
        if ($definition.StyleRulePath) {
            $record.style_rule_path = $definition.StyleRulePath
            $record.style_rule_sha256 = $definition.StyleRuleSha256
        }
        if ($definition.VerifyToolPath) {
            $record.verify_tool_path = $definition.VerifyToolPath
            $record.verify_tool_sha256 = $definition.VerifyToolSha256
        }
        $record.sha256 = (Get-FileHash -Algorithm SHA256 -LiteralPath $target).Hash.ToLowerInvariant()
        $record.license = $definition.License
        if ($definition.Role) { $record.role = $definition.Role }
        $manifestRecords += $record
    }
    $manifest = [ordered]@{ schema_version = 3; runtime_network_dependency = $false; assets = $manifestRecords }
    $manifestJson = ($manifest | ConvertTo-Json -Depth 8) -replace "`r`n", "`n"
    [IO.File]::WriteAllText((Join-Path $stagingRoot "font-assets.json"), ($manifestJson.TrimEnd() + "`n"), [Text.UTF8Encoding]::new($false))

    New-Item -ItemType Directory -Path $destinationRoot -Force | Out-Null
    Copy-Item -Path (Join-Path $stagingRoot "*") -Destination $destinationRoot -Recurse -Force
    foreach ($obsoleteTarget in @(
        "Theldrow-CC0.ttf"
    )) {
        $obsoletePath = Join-Path $destinationRoot $obsoleteTarget
        if (Test-Path -LiteralPath $obsoletePath -PathType Leaf) { Remove-Item -LiteralPath $obsoletePath -Force }
    }
    Write-Host "Bundled readable fonts and source-backed Classic typography assets, including the strict Pen-modernized Theldrow with original Castle advances, from pinned sources."
}
finally {
    if (Test-Path -LiteralPath $stagingRoot) { Remove-Item -LiteralPath $stagingRoot -Recurse -Force }
}
