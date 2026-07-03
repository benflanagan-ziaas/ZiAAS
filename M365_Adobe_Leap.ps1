#requires -version 5.1
<#
Compatibility entrypoint for the previous ZiAAS Office/Adobe/LEAP raw URL.

The canonical script is now ZiAAS_Woodstock_Baselining.ps1. This wrapper keeps
older run commands alive by downloading the canonical entrypoint and forwarding
all supplied arguments.
#>

[CmdletBinding()]
param()

Set-StrictMode -Version 2.0
$ErrorActionPreference = "Stop"
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

$scriptUrl = "https://raw.githubusercontent.com/benflanagan-ziaas/ZiAAS/refs/heads/main/ZiAAS_Woodstock_Baselining.ps1"
$root = Join-Path $env:ProgramData "ZiAAS_Woodstock_Baselining"
$scriptPath = Join-Path $root "ZiAAS_Woodstock_Baselining.ps1"

if (-not (Test-Path -LiteralPath $root)) {
    New-Item -Path $root -ItemType Directory -Force | Out-Null
}

$tmp = "$scriptPath.tmp"
if (Test-Path -LiteralPath $tmp) {
    Remove-Item -LiteralPath $tmp -Force
}

Write-Host "Downloading ZiAAS Woodstock Baselining entrypoint..."
Invoke-WebRequest -Uri $scriptUrl -OutFile $tmp -UseBasicParsing -TimeoutSec 120
Move-Item -LiteralPath $tmp -Destination $scriptPath -Force

Write-Host "Starting ZiAAS Woodstock Baselining..."
& powershell.exe -NoProfile -ExecutionPolicy Bypass -File $scriptPath @args
exit $LASTEXITCODE