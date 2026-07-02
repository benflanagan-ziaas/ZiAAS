#requires -version 5.1
<#
    ZiAAS Woodstock Baselining fixed entrypoint.

    This preserves the existing public filename and URL used by the current batch file.

    It downloads the last full source script from repository history, applies defensive
    hotfixes locally, then runs the patched copy in the same elevated PowerShell session.

    Current hotfixes:
      - ConvertTo-SafeFileName tolerates blank filename/header values.
      - Office ODT Remove All is best-effort. If ODT removal returns a non-success code,
        Microsoft OfficeScrubScenario still runs instead of stopping immediately.
      - Adobe AcroCleaner is best-effort only when a post-check proves Reader/Acrobat
        uninstall entries are already gone. If Adobe remains, the deployment still fails.
#>

Set-StrictMode -Version 2.0
$ErrorActionPreference = "Stop"
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

$sourceUrl = "https://raw.githubusercontent.com/benflanagan-ziaas/ZiAAS/117e08f1968308f1c20d72a2c7167174195db0dd/ZiAAS_Woodstock_Baselining.ps1"
$root = Join-Path $env:ProgramData "ZiAAS_Woodstock_Baselining"
$downloadedScript = Join-Path $root "ZiAAS_Woodstock_Baselining.source.ps1"
$patchedScript = Join-Path $root "ZiAAS_Woodstock_Baselining.patched.ps1"

New-Item -Path $root -ItemType Directory -Force | Out-Null
Write-Host "Downloading ZiAAS Woodstock Baselining source script..."
Invoke-WebRequest -Uri $sourceUrl -OutFile $downloadedScript -UseBasicParsing

$scriptText = Get-Content -LiteralPath $downloadedScript -Raw

$scriptText = $scriptText.Replace(
    '[Parameter(Mandatory = $true)]' + "`r`n" + '        [Alias("Name")]' + "`r`n" + '        [string]$FileName',
    '[Parameter(Mandatory = $false)]' + "`r`n" + '        [Alias("Name")]' + "`r`n" + '        [string]$FileName'
)
$scriptText = $scriptText.Replace(
    '[Parameter(Mandatory = $true)][string]$FileName',
    '[Parameter(Mandatory = $false)][AllowEmptyString()][string]$FileName'
)
$scriptText = $scriptText.Replace(
    '[Parameter(Mandatory = $true)][string]$Name',
    '[Parameter(Mandatory = $true)][AllowEmptyString()][string]$Name'
)

$officeUninstallReplacement = @'
function Invoke-OfficeUninstallAndCleanup {
    param([Parameter(Mandatory = $true)]$Assets)

    Stop-OfficeBlockingApps

    try {
        Invoke-ProcessChecked `
            -FilePath $Assets.Setup `
            -ArgumentList @("/configure", $Assets.RemoveConfig) `
            -Description "Office Click-to-Run removal" `
            -WorkingDirectory $Script:OfficeDir
    }
    catch {
        Write-Log "Office Click-to-Run removal returned a non-success result. Continuing to Microsoft Office scrub cleanup because ODT Remove All can fail when Office is already absent or partially removed." "WARN"
        Write-Log "Office Click-to-Run removal detail: $($_.Exception.Message)" "WARN"
    }

    Invoke-OfficeScrubCleanup
}
'@

$officePattern = '(?s)function Invoke-OfficeUninstallAndCleanup \{.*?\r?\n\}\r?\n\r?\nfunction Invoke-OfficeInstall'
if ($scriptText -notmatch $officePattern) {
    throw "Could not find Invoke-OfficeUninstallAndCleanup function block to patch. Source script may have changed."
}
$scriptText = [regex]::Replace($scriptText, $officePattern, ($officeUninstallReplacement + "`r`nfunction Invoke-OfficeInstall"), 1)

$acroCleanerReplacement = @'
function Invoke-AdobeCleanerCleanup {
    $cleanerExe = Get-AdobeCleanerPath

    foreach ($productId in @(1, 0)) {
        $productName = if ($productId -eq 1) { "Reader" } else { "Acrobat" }

        try {
            Invoke-ProcessChecked `
                -FilePath $cleanerExe `
                -ArgumentList @("/silent", "/product=$productId", "/cleanlevel=1", "/scanforothers=1") `
                -SuccessExitCodes @(0, 3010) `
                -Description "Adobe AcroCleaner cleanup for $productName"
        }
        catch {
            $remaining = @(Get-AdobeReaderAndAcrobatEntries)

            if ($remaining.Count -eq 0) {
                Write-Log "Adobe AcroCleaner cleanup for $productName failed or found nothing useful to clean after standard Adobe uninstall, but no Adobe Reader/Acrobat uninstall entries remain. Continuing with reinstall flow." "WARN"
                if (-not $Simulation) {
                    $Script:RebootRequired = $true
                }
                break
            }

            foreach ($entry in $remaining) {
                Write-Log "Adobe Reader/Acrobat still present after AcroCleaner failure: $($entry.DisplayName) $($entry.DisplayVersion)" "ERROR"
            }

            throw
        }
    }

    if (-not $Simulation) {
        $Script:RebootRequired = $true
    }
    Write-Log "Adobe recommends restarting after AcroCleaner. Continuing because this deployment flow reinstalls before LEAP, but a reboot should be scheduled afterward." "WARN"
}
'@

$acroPattern = '(?s)function Invoke-AdobeCleanerCleanup \{.*?\r?\n\}\r?\n\r?\nfunction Get-AdobeReaderInstallerPath'
if ($scriptText -notmatch $acroPattern) {
    throw "Could not find Invoke-AdobeCleanerCleanup function block to patch. Source script may have changed."
}
$scriptText = [regex]::Replace($scriptText, $acroPattern, ($acroCleanerReplacement + "`r`nfunction Get-AdobeReaderInstallerPath"), 1)

Set-Content -LiteralPath $patchedScript -Value $scriptText -Encoding UTF8
Write-Host "Running patched ZiAAS Woodstock Baselining script..."
& $patchedScript @args
exit $LASTEXITCODE
