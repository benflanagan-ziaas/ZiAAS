#requires -version 5.1
[CmdletBinding()]
param([Parameter(Mandatory = $true)][string]$ConfigPath)

if (-not (Test-Path -LiteralPath $ConfigPath)) {
    Write-Host "Config file was not found: $ConfigPath"
    exit 90
}

$Script:ZiaasConfig = Get-Content -LiteralPath $ConfigPath -Raw | ConvertFrom-Json
$ComponentName = "Adobe-Install"
. "$PSScriptRoot\Common.ps1"

Invoke-ZiaasComponent -Name "Adobe Reader/Acrobat install and policy configuration" -FailureExitCode 105 -ScriptBlock {
    $adobeSelection = Resolve-AdobeProductSelection -InstallAdobe $true
    Assert-AdobeInstallerSourceAvailable -AdobeSelection $adobeSelection
    Write-Log "Selected Adobe product: $($adobeSelection.Label)"
    Write-Log "Pre-staging $($adobeSelection.Label) installer after cleanup and before fresh Adobe install."
    $installerPath = Get-AdobeSelectedInstallerPath -AdobeSelection $adobeSelection
    Install-AdobeProduct -AdobeSelection $adobeSelection -InstallerPath $installerPath
    Set-AdobeEnterprisePolicies -AdobeSelection $adobeSelection
    Test-AdobeEnterprisePolicies -AdobeSelection $adobeSelection
    Write-AdobeInstallSummary -AdobeSelection $adobeSelection
}
