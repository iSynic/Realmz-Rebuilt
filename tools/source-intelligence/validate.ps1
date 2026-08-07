[CmdletBinding()]
param()

$ErrorActionPreference = "Stop"
$generator = Join-Path (Split-Path -Parent $PSCommandPath) "generate.ps1"
& $generator -ValidateOnly
if ($LASTEXITCODE -ne 0) {
    throw "Source-intelligence validation failed."
}
