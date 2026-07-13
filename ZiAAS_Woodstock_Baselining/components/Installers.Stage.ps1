#requires -version 5.1
[CmdletBinding()]
param([Parameter(Mandatory = $true)][string]$ConfigPath)

if (-not (Test-Path -LiteralPath $ConfigPath)) {
    Write-Host "Config file was not found: $ConfigPath"
    exit 90
}

$Script:ZiaasConfig = Get-Content -LiteralPath $ConfigPath -Raw | ConvertFrom-Json
$ComponentName = "Installer-Staging"
. "$PSScriptRoot\Common.ps1"

Invoke-ZiaasComponent -Name "Pre-cleanup installer staging and verification" -FailureExitCode 100 -ScriptBlock {
    $stagedFiles = New-Object System.Collections.Generic.List[string]
    $officePayloadPath = ""

    if (Resolve-ZiaasConfigBool -Name "InstallOffice" -Default $false) {
        Write-Log "Staging Microsoft deployment, scrub, and Office installation assets before cleanup."
        $assets = Get-OfficeDeploymentAssets
        Invoke-ProcessChecked `
            -FilePath $assets.Setup `
            -ArgumentList @("/download", $assets.InstallConfig) `
            -Description "Microsoft 365 Apps pre-cleanup payload staging" `
            -WorkingDirectory $Script:OfficeDir `
            -TimeoutSeconds 5400
        $officePayloadPath = Join-Path $Script:OfficeDir "Office\Data"
        if ((-not $Simulation) -and (-not (Test-Path -LiteralPath $officePayloadPath -PathType Container))) {
            throw "Office payload staging did not create the expected Office data folder: $officePayloadPath"
        }
        $scrubTool = Get-OfficeScrubToolPath
        $stagedFiles.Add($assets.Setup)
        $stagedFiles.Add($scrubTool)
    }

    if (Resolve-ZiaasConfigBool -Name "InstallAdobe" -Default $false) {
        $adobeSelection = Resolve-AdobeProductSelection -InstallAdobe $true
        Assert-AdobeInstallerSourceAvailable -AdobeSelection $adobeSelection
        Write-Log "Staging and signature-checking $($adobeSelection.Label) installer before cleanup."
        $stagedFiles.Add((Get-AdobeSelectedInstallerPath -AdobeSelection $adobeSelection))
        $stagedFiles.Add((Get-AdobeCleanerPath))
    }

    if (Resolve-ZiaasConfigBool -Name "InstallLeap" -Default $false) {
        Assert-LeapInstallerSourceAvailable
        Write-Log "Staging and signature-checking the latest LEAP Desktop installer before cleanup."
        $stagedFiles.Add((Get-LeapInstallerPath))
    }

    foreach ($download in @(Get-ChildItem -LiteralPath $Script:DownloadDir -File -ErrorAction SilentlyContinue)) {
        $stagedFiles.Add($download.FullName)
    }

    Write-ZiaasStagingManifest -Files @($stagedFiles) -OfficePayloadPath $officePayloadPath | Out-Null
    Write-Log "All selected reinstall media passed the pre-cleanup staging gate."
}
