$ErrorActionPreference = "Stop"
$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot "..\..")).Path
$iconRoot = Join-Path $repoRoot "src\ui\shared\assets\ui\application-icon"
$manifestPath = Join-Path $iconRoot "application-icon.json"
$projectPath = Join-Path $repoRoot "project.godot"
$presetPath = Join-Path $repoRoot "export_presets.cfg"

function Get-BigEndianUInt32 {
    param([byte[]]$Bytes, [int]$Offset)
    return ([uint32]$Bytes[$Offset] -shl 24) -bor
        ([uint32]$Bytes[$Offset + 1] -shl 16) -bor
        ([uint32]$Bytes[$Offset + 2] -shl 8) -bor
        [uint32]$Bytes[$Offset + 3]
}

function Get-ByteHash {
    param([byte[]]$Bytes)
    $sha = [System.Security.Cryptography.SHA256]::Create()
    try {
        return ([BitConverter]::ToString($sha.ComputeHash($Bytes))).Replace("-", "").ToLowerInvariant()
    } finally {
        $sha.Dispose()
    }
}

if (-not (Test-Path -LiteralPath $manifestPath -PathType Leaf)) { throw "Application icon manifest is missing." }
$manifest = Get-Content -Raw -LiteralPath $manifestPath | ConvertFrom-Json
if ($manifest.formatVersion -ne 1 -or $manifest.identity.creatorCode -ne "RLMZ" -or $manifest.identity.fileReferenceType -ne "APPL" -or $manifest.identity.bundleResourceId -ne 128 -or $manifest.identity.localIconId -ne 0 -or $manifest.identity.iconResourceId -ne 128) {
    throw "Application icon identity no longer matches Castle's BNDL 128 mapping."
}
if ($manifest.source.revision -ne "491816ad60037394f92c428e99c004494d3c28b3" -or $manifest.source.path -ne "resources/realmz.rsrc" -or $manifest.source.sha256 -ne "5bc76d986eb0f31589ef58120f4b9ad40234f228448bb75c09eb40e59c97bc9f" -or $manifest.source.license -ne "CC BY-NC-SA 4.0") {
    throw "Application icon source provenance drifted."
}
if ((@($manifest.derivation.nativeSizes) -join ",") -ne "16,32" -or (@($manifest.derivation.scaledSizes) -join ",") -ne "48,64,128,256,512,1024" -or $manifest.derivation.scaledFrom -ne 32 -or $manifest.derivation.resampling -ne "nearest-neighbor") {
    throw "Application icon family must retain native 16/32 pixels and nearest-neighbor scaling from the detailed 32px source."
}

$pngSignature = [byte[]](0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a)
foreach ($file in @($manifest.files)) {
    $path = Join-Path $iconRoot $file.path
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { throw "Missing application icon asset $($file.path)." }
    $item = Get-Item -LiteralPath $path
    $hash = (Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash.ToLowerInvariant()
    if ($item.Length -ne [long]$file.bytes -or $hash -ne $file.sha256) { throw "Application icon asset bytes drifted: $($file.path)." }
    if ($file.PSObject.Properties.Name -contains "width") {
        $bytes = [System.IO.File]::ReadAllBytes($path)
        if (($bytes[0..7] -join ",") -ne ($pngSignature -join ",")) { throw "$($file.path) is not a PNG." }
        $width = Get-BigEndianUInt32 $bytes 16
        $height = Get-BigEndianUInt32 $bytes 20
        if ($width -ne [uint32]$file.width -or $height -ne [uint32]$file.height) { throw "$($file.path) dimensions drifted." }
    }
}

$icoBytes = [System.IO.File]::ReadAllBytes((Join-Path $iconRoot "realmz-icon.ico"))
if ([BitConverter]::ToUInt16($icoBytes, 0) -ne 0 -or [BitConverter]::ToUInt16($icoBytes, 2) -ne 1 -or [BitConverter]::ToUInt16($icoBytes, 4) -ne 6) { throw "Windows icon container header is invalid." }
$icoSizes = @(16, 32, 48, 64, 128, 256)
for ($index = 0; $index -lt $icoSizes.Count; $index++) {
    $entry = 6 + 16 * $index
    $encodedSize = if ($icoSizes[$index] -eq 256) { 0 } else { $icoSizes[$index] }
    if ($icoBytes[$entry] -ne $encodedSize -or $icoBytes[$entry + 1] -ne $encodedSize -or [BitConverter]::ToUInt16($icoBytes, $entry + 4) -ne 1 -or [BitConverter]::ToUInt16($icoBytes, $entry + 6) -ne 32) { throw "Windows icon entry $index does not describe the required $($icoSizes[$index])px image." }
    $length = [BitConverter]::ToUInt32($icoBytes, $entry + 8)
    $offset = [BitConverter]::ToUInt32($icoBytes, $entry + 12)
    if ([long]$offset + [long]$length -gt $icoBytes.Length) { throw "Windows icon entry $index exceeds the container." }
    $payload = [byte[]]::new($length)
    [Array]::Copy($icoBytes, $offset, $payload, 0, $length)
    $expected = $manifest.files | Where-Object { $_.path -eq "realmz-icon-$($icoSizes[$index]).png" } | Select-Object -First 1
    if ((Get-ByteHash $payload) -ne $expected.sha256) { throw "Windows icon entry $($icoSizes[$index])px does not preserve the reviewed PNG." }
}

$icnsBytes = [System.IO.File]::ReadAllBytes((Join-Path $iconRoot "realmz-icon.icns"))
if ([Text.Encoding]::ASCII.GetString($icnsBytes, 0, 4) -ne "icns" -or (Get-BigEndianUInt32 $icnsBytes 4) -ne $icnsBytes.Length) { throw "macOS icon container header is invalid." }
$icnsSizes = [ordered]@{ "icp4" = 16; "icp5" = 32; "icp6" = 64; "ic07" = 128; "ic08" = 256; "ic09" = 512; "ic10" = 1024 }
$cursor = 8
foreach ($entry in $icnsSizes.GetEnumerator()) {
    if ([Text.Encoding]::ASCII.GetString($icnsBytes, $cursor, 4) -ne $entry.Key) { throw "macOS icon is missing ordered chunk $($entry.Key)." }
    $length = Get-BigEndianUInt32 $icnsBytes ($cursor + 4)
    if ($length -lt 8 -or [long]$cursor + [long]$length -gt $icnsBytes.Length) { throw "macOS icon chunk $($entry.Key) is invalid." }
    $payload = [byte[]]::new($length - 8)
    [Array]::Copy($icnsBytes, $cursor + 8, $payload, 0, $length - 8)
    $expected = $manifest.files | Where-Object { $_.path -eq "realmz-icon-$($entry.Value).png" } | Select-Object -First 1
    if ((Get-ByteHash $payload) -ne $expected.sha256) { throw "macOS icon chunk $($entry.Value)px does not preserve the reviewed PNG." }
    $cursor += $length
}
if ($cursor -ne $icnsBytes.Length) { throw "macOS icon contains unexpected trailing chunks." }

$project = Get-Content -Raw -LiteralPath $projectPath
foreach ($setting in @(
    'config/icon="res://src/ui/shared/assets/ui/application-icon/realmz-icon-256.png"',
    'config/windows_native_icon="res://src/ui/shared/assets/ui/application-icon/realmz-icon.ico"',
    'config/macos_native_icon="res://src/ui/shared/assets/ui/application-icon/realmz-icon.icns"'
)) {
    if (-not $project.Contains($setting)) { throw "Godot project icon setting is missing: $setting" }
}
$presets = Get-Content -Raw -LiteralPath $presetPath
$windowsOptions = [regex]::Match($presets, '(?ms)^\[preset\.0\.options\]\s*(.*?)(?=^\[preset\.\d+|\z)').Groups[1].Value
$macOptions = [regex]::Match($presets, '(?ms)^\[preset\.2\.options\]\s*(.*?)(?=^\[preset\.\d+|\z)').Groups[1].Value
if (-not $windowsOptions.Contains('application/icon="res://src/ui/shared/assets/ui/application-icon/realmz-icon.ico"') -or -not $windowsOptions.Contains("application/modify_resources=true")) { throw "Windows export must embed the reviewed multi-size icon." }
if (-not $macOptions.Contains('application/icon="res://src/ui/shared/assets/ui/application-icon/realmz-icon.icns"')) { throw "macOS export must embed the reviewed multi-size icon." }

Write-Host "Realmz project, Windows, and macOS application icon contracts verified."
