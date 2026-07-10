#requires -version 5.1
[CmdletBinding()]
param([Parameter(Mandatory = $true)][string]$ConfigPath)

if (-not (Test-Path -LiteralPath $ConfigPath)) {
    Write-Host "Config file was not found: $ConfigPath"
    exit 90
}

$Script:ZiaasConfig = Get-Content -LiteralPath $ConfigPath -Raw | ConvertFrom-Json
$ComponentName = "LEAP-Install"
. "$PSScriptRoot\Common.ps1"

Invoke-ZiaasComponent -Name "LEAP install" -FailureExitCode 106 -ScriptBlock {
    Assert-LeapInstallerSourceAvailable
    $installerPath = Get-LeapInstallerPath
    Install-Leap -InstallerPath $installerPath
    Write-LeapInstallSummary
}
