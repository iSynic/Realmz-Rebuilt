param(
    [Parameter(Mandatory)][ValidateSet("windows", "linux", "macos")][string]$ExpectedPlatform,
    [Parameter(Mandatory)][string]$Target,
    [Parameter(Mandatory)][string]$ExecutablePath
)

$ErrorActionPreference = "Stop"

function Assert-Condition([bool]$Condition, [string]$Message) {
    if (-not $Condition) { throw $Message }
}

function Read-BigEndianUInt32([byte[]]$Bytes, [int]$Offset) {
    return ([uint32]$Bytes[$Offset] -shl 24) -bor ([uint32]$Bytes[$Offset + 1] -shl 16) -bor ([uint32]$Bytes[$Offset + 2] -shl 8) -bor [uint32]$Bytes[$Offset + 3]
}

function Read-LittleEndianUInt32([byte[]]$Bytes, [int]$Offset) {
    return ([uint32]$Bytes[$Offset + 3] -shl 24) -bor ([uint32]$Bytes[$Offset + 2] -shl 16) -bor ([uint32]$Bytes[$Offset + 1] -shl 8) -bor [uint32]$Bytes[$Offset]
}

function Read-UInt64([byte[]]$Bytes, [int]$Offset, [bool]$LittleEndian) {
    if ($LittleEndian) {
        $low = Read-LittleEndianUInt32 $Bytes $Offset
        $high = Read-LittleEndianUInt32 $Bytes ($Offset + 4)
    } else {
        $high = Read-BigEndianUInt32 $Bytes $Offset
        $low = Read-BigEndianUInt32 $Bytes ($Offset + 4)
    }
    return ([uint64]$high -shl 32) -bor [uint64]$low
}

function Read-ExactBytes([IO.FileStream]$Stream, [long]$Offset, [int]$Count) {
    $bytes = New-Object byte[] $Count
    $Stream.Seek($Offset, [IO.SeekOrigin]::Begin) | Out-Null
    $read = $Stream.Read($bytes, 0, $Count)
    Assert-Condition ($read -eq $Count) "Universal Mach-O binary contains a truncated architecture slice."
    return ,$bytes
}

switch ($ExpectedPlatform) {
    "windows" {
        Assert-Condition ($Target -match '^x86_64-.*-windows(?:-|$)') "Windows scenario importer target '$Target' must be x86_64 Windows."
    }
    "linux" {
        Assert-Condition ($Target -match '^x86_64-unknown-linux(?:-|$)') "Linux scenario importer target '$Target' must be x86_64 Linux."
    }
    "macos" {
        Assert-Condition ($Target -match '^(?:x86_64|aarch64)-apple-darwin$') "macOS scenario importer target '$Target' must be a supported native Darwin build identity."
        Assert-Condition (Test-Path -LiteralPath $ExecutablePath -PathType Leaf) "macOS scenario importer executable is missing."
        $stream = [IO.File]::OpenRead($ExecutablePath)
        try {
            $fileLength = $stream.Length
            $header = New-Object byte[] 8
            $read = $stream.Read($header, 0, $header.Length)
        } finally {
            $stream.Dispose()
        }
        Assert-Condition ($read -eq 8) "macOS scenario importer executable is too short for a universal Mach-O header."
        $magic = [BitConverter]::ToString($header[0..3]).Replace('-', '')
        $littleEndian = $false
        $entryBytes = 20
        if ($magic -eq 'CAFEBABE') {
            $littleEndian = $false
        } elseif ($magic -eq 'BEBAFECA') {
            $littleEndian = $true
        } elseif ($magic -eq 'CAFEBABF') {
            $littleEndian = $false
            $entryBytes = 32
        } elseif ($magic -eq 'BFBAFECA') {
            $littleEndian = $true
            $entryBytes = 32
        } else {
            throw "macOS scenario importer must be a universal Mach-O binary; got magic $magic."
        }
        $readUInt32 = if ($littleEndian) { { param([byte[]]$Bytes, [int]$Offset) Read-LittleEndianUInt32 $Bytes $Offset } } else { { param([byte[]]$Bytes, [int]$Offset) Read-BigEndianUInt32 $Bytes $Offset } }
        $architectureCount = & $readUInt32 $header 4
        Assert-Condition ($architectureCount -gt 0 -and $architectureCount -le 64) "macOS scenario importer has an invalid universal architecture count."
        $requiredBytes = 8L + ([long]$architectureCount * $entryBytes)
        Assert-Condition ($fileLength -ge $requiredBytes) "macOS scenario importer has a truncated universal Mach-O architecture table."
        $table = New-Object byte[] ([int]$requiredBytes)
        $stream = [IO.File]::OpenRead($ExecutablePath)
        try { $read = $stream.Read($table, 0, $table.Length) } finally { $stream.Dispose() }
        Assert-Condition ($read -eq $table.Length) "Could not read the complete universal Mach-O architecture table."
        $slices = @()
        for ($index = 0; $index -lt $architectureCount; $index++) {
            $entryOffset = 8 + ($index * $entryBytes)
            $cpuType = [uint32](& $readUInt32 $table $entryOffset)
            if ($entryBytes -eq 20) {
                $sliceOffset = [uint64](& $readUInt32 $table ($entryOffset + 8))
                $sliceBytes = [uint64](& $readUInt32 $table ($entryOffset + 12))
            } else {
                $sliceOffset = Read-UInt64 $table ($entryOffset + 8) $littleEndian
                $sliceBytes = Read-UInt64 $table ($entryOffset + 16) $littleEndian
            }
            Assert-Condition ($sliceOffset -ge $requiredBytes -and $sliceOffset -le [uint64]$fileLength -and $sliceBytes -ge 32 -and $sliceBytes -le ([uint64]$fileLength - $sliceOffset)) "macOS scenario importer contains an out-of-bounds or truncated architecture slice."
            $slices += [ordered]@{ cpuType = $cpuType; offset = $sliceOffset; bytes = $sliceBytes }
        }
        $orderedSlices = @($slices | Sort-Object { [uint64]$_.offset })
        for ($index = 1; $index -lt $orderedSlices.Count; $index++) {
            $previousEnd = [uint64]$orderedSlices[$index - 1].offset + [uint64]$orderedSlices[$index - 1].bytes
            Assert-Condition ($previousEnd -le [uint64]$orderedSlices[$index].offset) "macOS scenario importer has overlapping universal architecture slices."
        }
        $stream = [IO.File]::OpenRead($ExecutablePath)
        try {
            foreach ($requiredCpu in @([uint32]16777223, [uint32]16777228)) {
                $matches = @($slices | Where-Object { [uint32]$_.cpuType -eq $requiredCpu })
                Assert-Condition ($matches.Count -eq 1) "macOS scenario importer must contain exactly one x86_64 and one arm64 slice."
                $slice = $matches[0]
                $sliceHeader = Read-ExactBytes $stream ([long]$slice.offset) 8
                $sliceMagic = [BitConverter]::ToString($sliceHeader[0..3]).Replace('-', '')
                Assert-Condition ($sliceMagic -eq 'CFFAEDFE') "macOS scenario importer architecture slice is not a little-endian 64-bit Mach-O image."
                $sliceCpu = Read-LittleEndianUInt32 $sliceHeader 4
                Assert-Condition ([uint32]$sliceCpu -eq $requiredCpu) "macOS scenario importer Mach-O slice header does not match its universal architecture entry."
            }
        } finally {
            $stream.Dispose()
        }
    }
}

Write-Output "Scenario importer target and executable match $ExpectedPlatform requirements."
