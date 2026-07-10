#requires -version 5.1
[CmdletBinding()]
param([Parameter(Mandatory = $true)][string]$ConfigPath)

if (-not (Test-Path -LiteralPath $ConfigPath)) {
    Write-Host "Config file was not found: $ConfigPath"
    exit 90
}

$Script:ZiaasConfig = Get-Content -LiteralPath $ConfigPath -Raw | ConvertFrom-Json
$ComponentName = "LEAP-RemoveClean"
. "$PSScriptRoot\Common.ps1"

Invoke-ZiaasComponent -Name "LEAP uninstall and cleanup" -FailureExitCode 101 -ScriptBlock {
    Uninstall-Leap
    Remove-StaleLeapUserProfileRemnants
    Remove-StaleLeapMachineRemnants
    Write-LeapResidualCleanupSummary
}
