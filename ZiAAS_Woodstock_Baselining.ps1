#requires -version 5.1
<#
ZiAAS Woodstock Baselining GitHub entrypoint.

Downloads the validated core script and component package from this repository,
decodes them into ProgramData, and starts the core script with the original
arguments. The core script handles product selection, cleanup, install order,
logging, reports, and component extraction.
#>

[CmdletBinding()]
param()

Set-StrictMode -Version 2.0
$ErrorActionPreference = "Stop"
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

$rawBase = "https://raw.githubusercontent.com/benflanagan-ziaas/ZiAAS/refs/heads/main"
$root = Join-Path $env:ProgramData "ZiAAS_Woodstock_Baselining"
$componentDir = Join-Path $root "components"
$corePath = Join-Path $root "ZiAAS_Woodstock_Baselining.core.ps1"
$coreB64Path = "$corePath.b64"
$packageB64Path = Join-Path $root "ZiAAS_Woodstock_Baselining.components.zip.b64"

function Save-ZiaasRawFile {
    param(
        [Parameter(Mandatory = $true)][string]$Url,
        [Parameter(Mandatory = $true)][string]$Path
    )

    $tmp = "$Path.tmp"
    if (Test-Path -LiteralPath $tmp) {
        Remove-Item -LiteralPath $tmp -Force
    }

    Invoke-WebRequest -Uri $Url -OutFile $tmp -UseBasicParsing -TimeoutSec 120
    Move-Item -LiteralPath $tmp -Destination $Path -Force
}

function Test-ZiaasArgumentPresent {
    param(
        [Parameter(Mandatory = $true)][string]$Name,
        [object[]]$ScriptArguments
    )

    foreach ($argument in @($ScriptArguments)) {
        if ([string]$argument -ieq "-$Name") {
            return $true
        }
    }

    return $false
}

if (-not (Test-Path -LiteralPath $root)) {
    New-Item -Path $root -ItemType Directory -Force | Out-Null
}
if (-not (Test-Path -LiteralPath $componentDir)) {
    New-Item -Path $componentDir -ItemType Directory -Force | Out-Null
}

Write-Host "Downloading ZiAAS Woodstock Baselining core..."
Save-ZiaasRawFile -Url "$rawBase/ZiAAS_Woodstock_Baselining.core.ps1.b64" -Path $coreB64Path
[System.IO.File]::WriteAllBytes($corePath, [Convert]::FromBase64String((Get-Content -LiteralPath $coreB64Path -Raw).Trim()))

Write-Host "Downloading ZiAAS Woodstock Baselining component package..."
Save-ZiaasRawFile -Url "$rawBase/ZiAAS_Woodstock_Baselining.components.zip.b64" -Path $packageB64Path

Write-Host "Starting ZiAAS Woodstock Baselining..."
$bootstrapArgs = @()
if (-not (Test-ZiaasArgumentPresent -Name "ComponentDirectory" -ScriptArguments $args)) {
    $bootstrapArgs += @("-ComponentDirectory", $componentDir)
}
if (-not (Test-ZiaasArgumentPresent -Name "ComponentPackageUrl" -ScriptArguments $args)) {
    $bootstrapArgs += @("-ComponentPackageUrl", "$rawBase/ZiAAS_Woodstock_Baselining.components.zip.b64")
}

& powershell.exe -NoProfile -ExecutionPolicy Bypass -File $corePath @bootstrapArgs @args
exit $LASTEXITCODE