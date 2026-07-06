#requires -version 5.1
[CmdletBinding()]
param([Parameter(Mandatory = $true)][string]$ConfigPath)

if (-not (Test-Path -LiteralPath $ConfigPath)) {
    Write-Host "Config file was not found: $ConfigPath"
    exit 90
}

$Script:ZiaasConfig = Get-Content -LiteralPath $ConfigPath -Raw | ConvertFrom-Json
$ComponentName = "Adobe-RemoveClean"
. "$PSScriptRoot\Common.ps1"

Invoke-ZiaasComponent -Name "Adobe Reader/Acrobat uninstall and cleanup" -FailureExitCode 102 -ScriptBlock {
    Uninstall-AdobeReaderAndAcrobat
    Remove-StaleAdobeMachineRemnants
    Invoke-AdobeCleanerCleanup
}
