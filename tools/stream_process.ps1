function Invoke-StreamingProcess {
    param(
        [Parameter(Mandatory = $true)][string]$FilePath,
        [string[]]$ArgumentList = @(),
        [Parameter(Mandatory = $true)][string]$Label,
        [ValidateRange(0, 86400)][int]$TimeoutSeconds = 0,
        [ValidateRange(1, 300)][int]$HeartbeatSeconds = 10
    )

    $quotedArguments = @($ArgumentList | ForEach-Object {
        if ($_ -match '[\s"]') { '"' + $_.Replace('"', '\"') + '"' } else { $_ }
    })
    $stdoutPath = Join-Path ([System.IO.Path]::GetTempPath()) ("realmz-process-{0}.out" -f [guid]::NewGuid().ToString("N"))
    $stderrPath = Join-Path ([System.IO.Path]::GetTempPath()) ("realmz-process-{0}.err" -f [guid]::NewGuid().ToString("N"))
    $captured = [System.Collections.Generic.List[string]]::new()
    $stdoutCount = 0
    $stderrCount = 0
    $process = $null
    $startedAt = [DateTime]::UtcNow
    $nextHeartbeat = $startedAt.AddSeconds($HeartbeatSeconds)
    $timedOut = $false
    $terminationVerified = $true

    function Write-NewProcessOutput {
        param([string]$Path, [ref]$Count, [System.Collections.Generic.List[string]]$Capture)
        if (-not (Test-Path -LiteralPath $Path)) { return }
        $lines = @(Get-Content -LiteralPath $Path -ErrorAction SilentlyContinue)
        for ($index = $Count.Value; $index -lt $lines.Count; $index++) {
            $line = [string]$lines[$index]
            $Capture.Add($line)
            Write-Host $line
        }
        $Count.Value = $lines.Count
    }

    try {
        Write-Host "Starting $Label$(if ($TimeoutSeconds -gt 0) { " with a ${TimeoutSeconds}-second process budget" })..."
        $process = Start-Process -FilePath $FilePath -ArgumentList $quotedArguments -PassThru -NoNewWindow -RedirectStandardOutput $stdoutPath -RedirectStandardError $stderrPath
        while (-not $process.HasExited) {
            Write-NewProcessOutput -Path $stdoutPath -Count ([ref]$stdoutCount) -Capture $captured
            Write-NewProcessOutput -Path $stderrPath -Count ([ref]$stderrCount) -Capture $captured
            $now = [DateTime]::UtcNow
            if ($now -ge $nextHeartbeat) {
                Write-Host ("{0} still running ({1:n0}s elapsed)..." -f $Label, ($now - $startedAt).TotalSeconds)
                $nextHeartbeat = $now.AddSeconds($HeartbeatSeconds)
            }
            if ($TimeoutSeconds -gt 0 -and ($now - $startedAt).TotalSeconds -ge $TimeoutSeconds) {
                $timedOut = $true
                if ($env:OS -eq "Windows_NT") {
                    & taskkill.exe /PID $process.Id /T /F 2>$null | Out-Null
                    $terminationVerified = $LASTEXITCODE -eq 0
                } else {
                    try { $process.Kill($true) } catch { $process.Kill() }
                }
                try { $terminationVerified = $process.WaitForExit(5000) -and $terminationVerified } catch { $terminationVerified = $false }
                $process.Refresh()
                if (-not $process.HasExited) { $terminationVerified = $false }
                break
            }
            Start-Sleep -Milliseconds 250
            $process.Refresh()
        }
        Write-NewProcessOutput -Path $stdoutPath -Count ([ref]$stdoutCount) -Capture $captured
        Write-NewProcessOutput -Path $stderrPath -Count ([ref]$stderrCount) -Capture $captured
        $elapsedMilliseconds = [int]([DateTime]::UtcNow - $startedAt).TotalMilliseconds
        Write-Host "$Label completed in $elapsedMilliseconds ms."
        if ($timedOut) {
            $lastOutput = "<no process output>"
            for ($index = $captured.Count - 1; $index -ge 0; $index--) {
                if (-not [string]::IsNullOrWhiteSpace($captured[$index])) {
                    $lastOutput = $captured[$index]
                    break
                }
            }
            if (-not $terminationVerified) {
                throw "$Label exceeded the ${TimeoutSeconds}-second budget and process-tree termination could not be verified. Last output: $lastOutput"
            }
            throw "$Label exceeded the ${TimeoutSeconds}-second budget; its process tree was terminated. Last output: $lastOutput"
        }
        return [pscustomobject]@{
            ExitCode = $process.ExitCode
            Output = $captured.ToArray()
            ElapsedMilliseconds = $elapsedMilliseconds
        }
    } finally {
        if ($process -and -not $process.HasExited) {
            try { $process.Kill($true) } catch { try { $process.Kill() } catch { } }
        }
        Remove-Item -LiteralPath $stdoutPath, $stderrPath -Force -ErrorAction SilentlyContinue
    }
}
