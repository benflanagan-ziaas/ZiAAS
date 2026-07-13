#requires -version 5.1
[CmdletBinding()]
param([Parameter(Mandatory = $true)][string]$ConfigPath)

if (-not (Test-Path -LiteralPath $ConfigPath)) {
    Write-Host "Config file was not found: $ConfigPath"
    exit 90
}

$Script:ZiaasConfig = Get-Content -LiteralPath $ConfigPath -Raw | ConvertFrom-Json
$ComponentName = "Office-Install"
. "$PSScriptRoot\Common.ps1"

Invoke-ZiaasComponent -Name "Microsoft 365 Apps install" -FailureExitCode 104 -ScriptBlock {
    $assets = Get-OfficeDeploymentAssets
    Invoke-OfficeInstall -Assets $assets
}
