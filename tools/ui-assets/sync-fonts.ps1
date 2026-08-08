param()

$ErrorActionPreference = "Stop"
$toolRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
$repoRoot = Split-Path -Parent (Split-Path -Parent $toolRoot)
$destinationRoot = Join-Path $repoRoot "src/presentation/assets/fonts"
$stagingRoot = Join-Path ([IO.Path]::GetTempPath()) ("realmz2-fonts-" + [Guid]::NewGuid().ToString("N"))
$googleFontsCommit = "2d85e20401920891efb7cd6272d6339685df2820"
$baseUri = "https://raw.githubusercontent.com/google/fonts/$googleFontsCommit/ofl"
$files = @(
    @{ Id = "font.narrative.alegreya.variable"; Uri = "$baseUri/alegreya/Alegreya%5Bwght%5D.ttf"; Target = "Alegreya-Variable.ttf"; License = "OFL-1.1" },
    @{ Id = "font.ui.alegreya_sans.regular"; Uri = "$baseUri/alegreyasans/AlegreyaSans-Regular.ttf"; Target = "AlegreyaSans-Regular.ttf"; License = "OFL-1.1" },
    @{ Id = "font.ui.alegreya_sans.bold"; Uri = "$baseUri/alegreyasans/AlegreyaSans-Bold.ttf"; Target = "AlegreyaSans-Bold.ttf"; License = "OFL-1.1" },
    @{ Id = "license.alegreya"; Uri = "$baseUri/alegreya/OFL.txt"; Target = "licenses/Alegreya-OFL.txt"; License = "OFL-1.1" },
    @{ Id = "license.alegreya_sans"; Uri = "$baseUri/alegreyasans/OFL.txt"; Target = "licenses/AlegreyaSans-OFL.txt"; License = "OFL-1.1" }
)
New-Item -ItemType Directory -Path $stagingRoot | Out-Null

try {
    $records = @()
    foreach ($definition in $files) {
        $target = Join-Path $stagingRoot ($definition.Target -replace "/", [IO.Path]::DirectorySeparatorChar)
        New-Item -ItemType Directory -Path (Split-Path -Parent $target) -Force | Out-Null
        Invoke-WebRequest -UseBasicParsing -Headers @{ "User-Agent" = "Realmz2-asset-sync" } -Uri $definition.Uri -OutFile $target
        if ((Get-Item -LiteralPath $target).Length -eq 0) {
            throw "Downloaded font asset is empty: $($definition.Target)"
        }
        $records += [ordered]@{
            id = $definition.Id
            path = "res://src/presentation/assets/fonts/$($definition.Target)"
            source_repository = "google/fonts"
            source_commit = $googleFontsCommit
            sha256 = (Get-FileHash -Algorithm SHA256 -LiteralPath $target).Hash.ToLowerInvariant()
            license = $definition.License
        }
    }
    $manifest = [ordered]@{
        schema_version = 1
        source_repository = "google/fonts"
        source_commit = $googleFontsCommit
        runtime_network_dependency = $false
        assets = $records
    }
    [IO.File]::WriteAllText(
        (Join-Path $stagingRoot "font-assets.json"),
        (($manifest | ConvertTo-Json -Depth 5) + [Environment]::NewLine),
        [Text.UTF8Encoding]::new($false)
    )

    New-Item -ItemType Directory -Path $destinationRoot -Force | Out-Null
    Copy-Item -Path (Join-Path $stagingRoot "*") -Destination $destinationRoot -Recurse -Force
    Write-Host "Bundled Alegreya fonts and OFL licenses from google/fonts $googleFontsCommit."
}
finally {
    if (Test-Path -LiteralPath $stagingRoot) {
        Remove-Item -LiteralPath $stagingRoot -Recurse -Force
    }
}
