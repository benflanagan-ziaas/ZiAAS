#requires -version 5.1
<#
    Downloads the current ZiAAS_Woodstock_Baselining.ps1 from GitHub, applies the current
    defensive hotfixes locally, then runs the patched copy.

    Purpose:
      - Keep client-side invocation GitHub-based.
      - Avoid overwriting the live production script with a partial file replacement.
      - Treat Adobe AcroCleaner as best-effort only when a post-check proves Reader/Acrobat
        uninstall entries are already gone.

    Usage from elevated PowerShell:
      powershell.exe -ExecutionPolicy Bypass -File .\ZiAAS_Woodstock_Baselining_FixedRunner.ps1

    Any arguments supplied to this runner are passed to the patched baselining script, for example:
      powershell.exe -ExecutionPolicy Bypass -File .\ZiAAS_Woodstock_Baselining_FixedRunner.ps1 -InstallMode All -AdobeProduct Reader
#>

Set-StrictMode -Version 2.0
$ErrorActionPreference = "Stop"
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

$sourceUrl = "https://raw.githubusercontent.com/benflanagan-ziaas/ZiAAS/refs/heads/main/ZiAAS_Woodstock_Baselining.ps1"
$root = Join-Path $env:ProgramData "ZiAAS_Woodstock_Baselining"
$downloadedScript = Join-Path $root "ZiAAS_Woodstock_Baselining.source.ps1"
$patchedScript = Join-Path $root "ZiAAS_Woodstock_Baselining.patched.ps1"

New-Item -Path $root -ItemType Directory -Force | Out-Null
Write-Host "Downloading source script from GitHub..."
Invoke-WebRequest -Uri $sourceUrl -OutFile $downloadedScript -UseBasicParsing

$scriptText = Get-Content -LiteralPath $downloadedScript -Raw

# Hotfix 1: the later ConvertTo-SafeFileName implementation should tolerate blank values.
# Some remote download headers can return a blank filename before the script falls back correctly.
$scriptText = $scriptText.Replace(
    '[Parameter(Mandatory = $true)]' + "`r`n" + '        [Alias("Name")]' + "`r`n" + '        [string]$FileName',
    '[Parameter(Mandatory = $false)]' + "`r`n" + '        [Alias("Name")]' + "`r`n" + '        [string]$FileName'
)

# Hotfix 2: AcroCleaner is best-effort. If it crashes/fails after the standard Adobe MSI uninstall,
# continue only when a registry post-check proves no Adobe Reader/Acrobat uninstall entries remain.
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

$pattern = '(?s)function Invoke-AdobeCleanerCleanup \{.*?\r?\n\}\r?\n\r?\nfunction Get-AdobeReaderInstallerPath'
if ($scriptText -notmatch $pattern) {
    throw "Could not find Invoke-AdobeCleanerCleanup function block to patch. Source script may have changed."
}

$scriptText = [regex]::Replace($scriptText, $pattern, ($acroCleanerReplacement + "`r`nfunction Get-AdobeReaderInstallerPath"), 1)

Set-Content -LiteralPath $patchedScript -Value $scriptText -Encoding UTF8
Write-Host "Running patched baselining script..."
& powershell.exe -NoProfile -ExecutionPolicy Bypass -File $patchedScript @args
exit $LASTEXITCODE
