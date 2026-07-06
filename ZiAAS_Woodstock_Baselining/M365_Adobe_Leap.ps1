#requires -version 5.1
<#
Compatibility entrypoint for the previous ZiAAS Office/Adobe/LEAP raw URL.

The canonical script is now ZiAAS_Woodstock_Baselining.ps1. This wrapper keeps
older run commands alive by downloading the canonical entrypoint and forwarding
all supplied arguments.
#>

[CmdletBinding()]
param(
    [Parameter(ValueFromRemainingArguments = $true)]
    [object[]]$ForwardedArguments
)

Set-StrictMode -Version 2.0
$ErrorActionPreference = "Stop"
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

$defaultRawBase = "https://raw.githubusercontent.com/benflanagan-ziaas/ZiAAS/refs/heads/main/ZiAAS_Woodstock_Baselining"
$rawBase = if ([string]::IsNullOrWhiteSpace($env:ZIAAS_WOODSTOCK_RAW_BASE)) { $defaultRawBase } else { $env:ZIAAS_WOODSTOCK_RAW_BASE.TrimEnd("/") }
$scriptUrl = "$rawBase/ZiAAS_Woodstock_Baselining.ps1"
$root = if ([string]::IsNullOrWhiteSpace($env:ZIAAS_WOODSTOCK_BOOTSTRAP_ROOT)) {
    Join-Path $env:ProgramData "ZiAAS_Woodstock_Baselining"
}
else {
    $env:ZIAAS_WOODSTOCK_BOOTSTRAP_ROOT
}
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
& powershell.exe -NoProfile -ExecutionPolicy Bypass -File $scriptPath @ForwardedArguments
exit $LASTEXITCODE
