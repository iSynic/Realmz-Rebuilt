param(
    [Parameter(Mandatory = $true)]
    [string]$SourcePackage,
    [Parameter(Mandatory = $true)]
    [string]$DestinationPackage
)

$ErrorActionPreference = "Stop"
Add-Type -AssemblyName System.IO.Compression

$sourcePath = (Resolve-Path -LiteralPath $SourcePackage).Path
$destinationPath = [System.IO.Path]::GetFullPath($DestinationPackage)
$destinationDirectory = [System.IO.Path]::GetDirectoryName($destinationPath)
[System.IO.Directory]::CreateDirectory($destinationDirectory) | Out-Null
if ([System.IO.File]::Exists($destinationPath)) {
    [System.IO.File]::Delete($destinationPath)
}

$sourceStream = [System.IO.File]::OpenRead($sourcePath)
$destinationStream = [System.IO.File]::Open($destinationPath, [System.IO.FileMode]::CreateNew)
try {
    $sourceArchive = [System.IO.Compression.ZipArchive]::new($sourceStream, [System.IO.Compression.ZipArchiveMode]::Read, $false)
    $destinationArchive = [System.IO.Compression.ZipArchive]::new($destinationStream, [System.IO.Compression.ZipArchiveMode]::Create, $true)
    try {
        foreach ($sourceEntry in ($sourceArchive.Entries | Sort-Object FullName)) {
            $input = $sourceEntry.Open()
            $buffer = [System.IO.MemoryStream]::new()
            try {
                $input.CopyTo($buffer)
                [byte[]]$bytes = $buffer.ToArray()
            }
            finally {
                $buffer.Dispose()
                $input.Dispose()
            }
            if ($sourceEntry.FullName -eq "content.json") {
                $utf8 = [System.Text.UTF8Encoding]::new($false)
                $text = $utf8.GetString($bytes)
                if (-not $text.Contains("Fixture Wand")) {
                    throw "The positive fixture does not contain the expected synthetic mutation target."
                }
                $bytes = $utf8.GetBytes($text.Replace("Fixture Wand", "Fixture Band"))
            }
            $destinationEntry = $destinationArchive.CreateEntry($sourceEntry.FullName, [System.IO.Compression.CompressionLevel]::Optimal)
            $destinationEntry.LastWriteTime = $sourceEntry.LastWriteTime
            $output = $destinationEntry.Open()
            try {
                $output.Write($bytes, 0, $bytes.Length)
            }
            finally {
                $output.Dispose()
            }
        }
    }
    finally {
        $destinationArchive.Dispose()
        $sourceArchive.Dispose()
    }
}
finally {
    $destinationStream.Dispose()
    $sourceStream.Dispose()
}

Write-Host "Created valid-ZIP stale-hash fixture at $destinationPath"
