param([string]$GodotPath = "")

$ErrorActionPreference = "Stop"
$repoRoot = Split-Path -Parent $PSScriptRoot
if ([string]::IsNullOrWhiteSpace($GodotPath)) {
    $command = Get-Command "Godot_v4.7.1-stable_win64_console.exe" -ErrorAction SilentlyContinue
    if (-not $command) { throw "Godot 4.7.1 was not found. Pass -GodotPath explicitly." }
    $GodotPath = $command.Source
}

$registry = Get-Content -LiteralPath (Join-Path $repoRoot "addons/realmz_builder/scene_previews.json") -Raw | ConvertFrom-Json
$logRoot = Join-Path ([IO.Path]::GetTempPath()) ("realmz-editor-authoring-" + [Guid]::NewGuid().ToString("N"))
New-Item -ItemType Directory -Path $logRoot | Out-Null

foreach ($scene in $registry.scenes) {
    $id = [string]$scene.id
    $editorLog = Join-Path $logRoot "$id-editor.log"
    & $GodotPath --headless --editor --path $repoRoot --script res://tools/verify_editor_authoring.gd -- --editor-cycle "--only=$id" *> $editorLog
    $editorOutput = Get-Content -LiteralPath $editorLog -Raw
    $editorMarker = "EDITOR_CYCLES=1 FAILURES=0"
    $editorMarkerAt = $editorOutput.IndexOf($editorMarker, [StringComparison]::Ordinal)
    $editorBeforeReceipt = if ($editorMarkerAt -ge 0) { $editorOutput.Substring(0, $editorMarkerAt) } else { $editorOutput }
    $editorAfterReceipt = if ($editorMarkerAt -ge 0) { $editorOutput.Substring($editorMarkerAt + $editorMarker.Length) } else { "" }
    $unexpectedShutdownErrors = @($editorAfterReceipt -split "`r?`n" | Where-Object { $_ -match '^ERROR:' -and $_ -notmatch '^ERROR: [0-9]+ RID allocations of type ' -and $_ -notmatch '^ERROR: [0-9]+ resources still in use at exit ' })
    if ($LASTEXITCODE -ne 0 -or $editorMarkerAt -lt 0 -or $editorBeforeReceipt -match '(?m)^(ERROR:|SCRIPT ERROR:)|AUTHORING_FAILURE:|Parse Error:' -or $unexpectedShutdownErrors.Count -gt 0) {
        throw "Editor authoring cycle failed for $id. See $editorLog"
    }

    $runtimeLog = Join-Path $logRoot "$id-runtime.log"
    & $GodotPath --headless --path $repoRoot --script res://tools/verify_editor_authoring.gd -- --runtime-cycle *> $runtimeLog
    $runtimeOutput = Get-Content -LiteralPath $runtimeLog -Raw
    if ($LASTEXITCODE -ne 0 -or $runtimeOutput -notmatch "RUNTIME_CYCLES=1 FAILURES=0" -or $runtimeOutput -match '(?m)^(ERROR:|SCRIPT ERROR:)|AUTHORING_FAILURE:|Parse Error:') {
        throw "Production binding of the editor-saved scene failed for $id. See $runtimeLog"
    }
    Write-Output "PASS $id"
}

Write-Output "Editor edit/save/reopen and runtime binding passed for $($registry.scenes.Count) registered surfaces. Logs: $logRoot"
