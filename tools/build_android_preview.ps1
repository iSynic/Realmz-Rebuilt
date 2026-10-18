param(
    [Parameter(Mandatory = $true)][string]$GodotExe,
    [Parameter(Mandatory = $true)][string]$TemplateRoot,
    [Parameter(Mandatory = $true)][string]$AndroidSdk,
    [Parameter(Mandatory = $true)][string]$JavaHome,
    [Parameter(Mandatory = $true)][string]$OutputDirectory
)
$ErrorActionPreference = 'Stop'
$repoRoot = Split-Path -Parent $PSScriptRoot
foreach ($variable in @('GODOT_ANDROID_KEYSTORE_RELEASE_PATH', 'GODOT_ANDROID_KEYSTORE_RELEASE_USER', 'GODOT_ANDROID_KEYSTORE_RELEASE_PASSWORD')) {
    if (-not [Environment]::GetEnvironmentVariable($variable)) { throw "Missing signing environment variable: $variable" }
}
foreach ($path in @($GodotExe, "$TemplateRoot/android_release.apk", "$AndroidSdk/platform-tools/adb.exe", "$AndroidSdk/build-tools/35.0.1/apksigner.bat", "$JavaHome/bin/java.exe")) {
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { throw "Missing Android build input: $path" }
}
if (Test-Path -LiteralPath $OutputDirectory) { throw 'Choose a new output directory; previous APKs and evidence are never replaced.' }
$null = New-Item -ItemType Directory -Path $OutputDirectory
$outputRoot = (Resolve-Path -LiteralPath $OutputDirectory).Path
$engineRoot = Join-Path $outputRoot 'engine'
$null = New-Item -ItemType Directory -Path $engineRoot
# Self-contained editor settings leave the developer's ordinary Godot configuration alone.
$engineSource = $GodotExe
if ($GodotExe.EndsWith('_console.exe')) {
    $engineSource = $GodotExe.Replace('_console.exe', '.exe')
}
Copy-Item -LiteralPath $engineSource -Destination "$engineRoot/Godot.exe"
[IO.File]::WriteAllText("$engineRoot/_sc_", '')
$editorData = "$engineRoot/editor_data"
$templateDestination = "$editorData/export_templates/4.7.1.stable"
$null = New-Item -ItemType Directory -Path $templateDestination -Force
foreach ($name in @('android_release.apk', 'android_debug.apk', 'version.txt')) {
    Copy-Item -LiteralPath (Join-Path $TemplateRoot $name) -Destination $templateDestination
}
$sdkValue = $AndroidSdk.Replace('\', '/')
$javaValue = $JavaHome.Replace('\', '/')
if ($sdkValue.Contains('"') -or $javaValue.Contains('"')) { throw 'SDK paths cannot contain quotes.' }
$settings = @"
[gd_resource type="EditorSettings" format=3]

[resource]
export/android/android_sdk_path = "$sdkValue"
export/android/java_sdk_path = "$javaValue"
"@
[IO.File]::WriteAllText("$editorData/editor_settings-4.7.tres", $settings)
$oldJava = $env:JAVA_HOME
$env:JAVA_HOME = $JavaHome
try {
    $engine = "$engineRoot/Godot.exe"
    $apk = "$outputRoot/Realmz-Rebuilt-preview.apk"
    . "$PSScriptRoot/stream_process.ps1"
    $result = Invoke-StreamingProcess -FilePath $engine -ArgumentList @('--headless', '--path', $repoRoot, '--export-release', 'Android Tablet Preview', $apk) -Label 'Android export' -TimeoutSeconds 1200 6> "$outputRoot/export.log"
    if ($result.ExitCode -ne 0 -or -not (Test-Path -LiteralPath $apk)) { throw "Android export failed; see $outputRoot/export.log" }
    & python "$PSScriptRoot/prepare_android_apk.py" $apk "$outputRoot/unaligned.apk"
    if ($LASTEXITCODE -ne 0) { throw 'Android archive preparation failed.' }
    & "$AndroidSdk/build-tools/35.0.1/zipalign.exe" -P 16 -f 4 "$outputRoot/unaligned.apk" "$outputRoot/aligned.apk"
    if ($LASTEXITCODE -ne 0) { throw 'Android ZIP alignment failed.' }
    & "$AndroidSdk/build-tools/35.0.1/apksigner.bat" sign --ks $env:GODOT_ANDROID_KEYSTORE_RELEASE_PATH --ks-key-alias $env:GODOT_ANDROID_KEYSTORE_RELEASE_USER --ks-pass env:GODOT_ANDROID_KEYSTORE_RELEASE_PASSWORD --key-pass env:GODOT_ANDROID_KEYSTORE_RELEASE_PASSWORD --out $apk "$outputRoot/aligned.apk"
    if ($LASTEXITCODE -ne 0) { throw 'Android final signing failed.' }
    & "$AndroidSdk/build-tools/35.0.1/zipalign.exe" -c -P 16 4 $apk *> "$outputRoot/alignment.txt"
    if ($LASTEXITCODE -ne 0) { throw 'Android alignment verification failed.' }
    & "$AndroidSdk/build-tools/35.0.1/apksigner.bat" verify --verbose --print-certs $apk *> "$outputRoot/signature.txt"
    if ($LASTEXITCODE -ne 0) { throw 'Android signature verification failed.' }
    & "$AndroidSdk/build-tools/35.0.1/aapt.exe" dump xmltree $apk AndroidManifest.xml *> "$outputRoot/manifest.txt"
    if ($LASTEXITCODE -ne 0) { throw 'Android manifest inspection failed.' }
    & python "$PSScriptRoot/verify_android_preview.py" $outputRoot
    if ($LASTEXITCODE -ne 0) { throw 'Android package verification failed.' }
    $sourceFiles = @(& git -C $repoRoot ls-files --cached --others --exclude-standard)
    $sourceHashes = [ordered]@{}
    foreach ($relative in $sourceFiles) {
        $sourcePath = Join-Path $repoRoot $relative
        if (Test-Path -LiteralPath $sourcePath -PathType Leaf) {
            $sourceHashes[$relative] = (Get-FileHash -LiteralPath $sourcePath).Hash.ToLowerInvariant()
        }
    }
    [IO.File]::WriteAllText("$outputRoot/source-hashes.json", ($sourceHashes | ConvertTo-Json -Depth 3))
    $receipt = [ordered]@{
        sourceCommit = (& git -C $repoRoot rev-parse HEAD).Trim()
        sourceStatus = @(& git -C $repoRoot status --porcelain)
        godot = (& $engine --version | Out-String).Trim()
        godotSha256 = (Get-FileHash -LiteralPath $engineSource).Hash.ToLowerInvariant()
        templateSha256 = (Get-FileHash -LiteralPath "$TemplateRoot/android_release.apk").Hash.ToLowerInvariant()
        java = (& "$JavaHome/bin/java.exe" --version | Out-String).Trim()
        javaSha256 = (Get-FileHash -LiteralPath "$JavaHome/bin/java.exe").Hash.ToLowerInvariant()
        sourceHashesSha256 = (Get-FileHash -LiteralPath "$outputRoot/source-hashes.json").Hash.ToLowerInvariant()
        buildTools = (Get-Content -LiteralPath "$AndroidSdk/build-tools/35.0.1/source.properties" | Out-String).Trim()
        apkSha256 = (Get-FileHash -LiteralPath $apk).Hash.ToLowerInvariant()
        apkBytes = (Get-Item -LiteralPath $apk).Length
        localPreview = $true
    }
    [IO.File]::WriteAllText("$outputRoot/build-receipt.json", ($receipt | ConvertTo-Json -Depth 5))
    Write-Host "Verified signed Android preview: $apk"
} finally {
    $env:JAVA_HOME = $oldJava
}
