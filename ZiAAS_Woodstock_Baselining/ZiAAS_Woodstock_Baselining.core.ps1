#requires -version 5.1
<#
ZiAAS Woodstock Baselining orchestrator.

Runs Office, Adobe, and LEAP as separate component scripts with separate logs and exit codes.
The reinstall order is always Office, then Adobe, then LEAP, so add-ins bind correctly.
#>

[CmdletBinding()]
param(
    [Alias("Config")]
    [string]$DeploymentConfigPath,

    [string]$WorkingRoot = "$env:ProgramData\ZiAAS_Woodstock_Baselining",

    [ValidateSet("Prompt", "Office", "OfficeAndAdobe", "OfficeAndAdobeReader", "Adobe", "AdobeReader", "Leap", "OfficeAndLeap", "AdobeAndLeap", "AdobeReaderAndLeap", "OfficeAndAdobeAndLeap", "OfficeAndAdobeReaderAndLeap", "All")]
    [string]$InstallMode = "Prompt",

    [switch]$Simulation,
    [switch]$ForceCloseApps,
    [switch]$SkipOffice,
    [switch]$SkipAdobe,
    [switch]$DisableAdobeAutoUpdate,
    [switch]$KeepDownloads,
    [switch]$SkipLeapProfileCleanup,
    [switch]$Unattended,
    [switch]$ShowGuide,
    [switch]$NoLogo,

    [string]$OfficeDeploymentToolUrl = "https://download.microsoft.com/download/6c1eeb25-cf8b-41d9-8d0d-cc1dbc032140/officedeploymenttool_20026-20112.exe",
    [string]$OfficeScrubToolUrl = "https://aka.ms/SaRA_EnterpriseVersionFiles",

    [ValidateSet("Prompt", "Reader", "AcrobatPro")]
    [string]$AdobeProduct = "Prompt",

    [string]$AdobeReaderInstallerUrl = "https://ardownload2.adobe.com/pub/adobe/acrobat/win/AcrobatDC/2600121691/AcroRdrDCx642600121691_MUI.exe",
    [string]$AdobeAcrobatProInstallerPath,
    [string]$AdobeAcrobatProInstallerUrl,
    [string[]]$AdobeAcrobatProInstallArguments = @(),
    [string]$AdobeAcrobatProInstallArgumentLine,
    [switch]$AllowAcrobatProInstallerWithoutArguments,
    [switch]$AllowAcrobatProLanguageNotVerified,
    [string[]]$AdobeAcrobatProTrustedPublisherFragments = @("Adobe", "Adobe Inc."),
    [string]$AdobeCleanerToolUrl = "https://ardownload2.adobe.com/pub/adobe/acrobat/win/AcrobatDC/2100120135/x64/AdobeAcroCleaner_DC2021.exe",

    [string]$LeapInstallerPath,
    [string]$LeapInstallerUrl,
    [string]$LeapDownloadsPageUrl = "https://community.leap.co.uk/s/downloads",
    [string[]]$LeapInstallerSearchRoots = @(
        "$env:USERPROFILE\Downloads",
        "$env:PUBLIC\Downloads",
        "$env:SystemDrive\Installers",
        "$env:SystemDrive\Temp",
        "$env:ProgramData\ZiAAS_Woodstock_Baselining\Downloads"
    ),
    [switch]$AllowLocalLeapInstallerFallback,
    [string[]]$LeapInstallArguments = @(),
    [string[]]$LeapTrustedPublisherFragments = @("LEAP"),

    [int]$PostCleanupWaitSeconds = 60,
    [int]$PreLeapWaitSeconds = 60,

    [string]$ComponentDirectory,
    [string]$ComponentBaseUrl = "https://raw.githubusercontent.com/benflanagan-ziaas/ZiAAS/refs/heads/main/components",
    [string]$ComponentPackageUrl = "https://raw.githubusercontent.com/benflanagan-ziaas/ZiAAS/refs/heads/main/ZiAAS_Woodstock_Baselining.components.zip.b64",
    [switch]$NoComponentDownload,

    [ValidateRange(1, 10)]
    [int]$DownloadRetryCount = 3,

    [ValidateRange(0, 300)]
    [int]$DownloadRetryDelaySeconds = 5
)

Set-StrictMode -Version 2.0
$ErrorActionPreference = "Stop"
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

$Script:ZiAASRunGuide = @"
ZiAAS Woodstock Baselining - Running Guide
=========================================

Purpose
-------
Baselines a Windows client by removing and reinstalling selected products in a controlled order:
  1. LEAP remove and clean, if selected
  2. Adobe Reader/Acrobat remove and clean, if selected
  3. Office remove and clean, if selected
  4. Wait for post-cleanup settling
  5. Microsoft 365 Apps for enterprise install, if selected
  6. Adobe Reader/Acrobat install and enterprise policies, if selected
  7. Wait before LEAP
  8. LEAP install last, if selected

Why this order matters
----------------------
Office must be installed before Adobe so Adobe can lay down its Office/PDF add-ins.
LEAP must be installed last so LEAP can bind add-ins into the freshly installed Office and Adobe apps.

Common runs
-----------
Interactive operator run:
  powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\ZiAAS_Woodstock_Baselining.ps1

Full unattended Reader deployment:
  powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\ZiAAS_Woodstock_Baselining.ps1 -InstallMode All -AdobeProduct Reader -Unattended

Run from a JSON profile:
  powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\ZiAAS_Woodstock_Baselining.ps1 -Config .\config\office-adobe-leap-reader.json -Unattended

Simulation without machine changes:
  powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\ZiAAS_Woodstock_Baselining.ps1 -Simulation -InstallMode All -AdobeProduct Reader -WorkingRoot .\sandbox-test

Show this guide:
  powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\ZiAAS_Woodstock_Baselining.ps1 -ShowGuide

Key arguments
-------------
-Config / -DeploymentConfigPath
  Loads a JSON profile. Explicit command-line arguments override profile values.

-InstallMode
  Prompt, Office, OfficeAndAdobe, Adobe, Leap, OfficeAndLeap, AdobeAndLeap,
  OfficeAndAdobeAndLeap, All. Prompt shows the operator menu.

-AdobeProduct
  Reader or AcrobatPro. Reader uses the public 64-bit MUI installer with LANG_LIST=en_GB.
  AcrobatPro requires a licensed enterprise installer path or URL.

-Unattended
  Fails early if a prompt would be required. Use this for RMM/Intune scripts.

-Simulation
  Exercises the full flow, logging, component order, and exit handling without changing the machine.

-ForceCloseApps
  Allows the script to force-close blocking Office, Adobe, and LEAP apps. Use only when users have saved work.

-KeepDownloads
  Leaves installer/cache files under the working root for review or reuse.

-WorkingRoot
  Defaults to C:\ProgramData\ZiAAS_Woodstock_Baselining. Logs, state, reports, downloads, and backups live here.

-DisableAdobeAutoUpdate
  Adds Adobe updater policy/task disabling. Default keeps updater behaviour unless this is supplied.

-SkipLeapProfileCleanup
  Skips LEAP per-user profile cleanup. The script always preserves AppData\Roaming\LEAP Accounting.

-LeapInstallerUrl / -LeapInstallerPath
  Override LEAP installer discovery. By default, the script resolves the latest installer from the official LEAP downloads page.

-LeapInstallArguments
  Overrides the default LEAP InstallShield silent arguments: /s /SMS /v"/qn REBOOT=ReallySuppress".
  The default install step also closes known LEAP client/tray processes if the installer auto-launches them.

-AdobeAcrobatProInstallerPath / -AdobeAcrobatProInstallerUrl
  Required for Acrobat Pro real deployments.

-AdobeAcrobatProInstallArguments / -AdobeAcrobatProInstallArgumentLine
  Silent install arguments for the licensed Acrobat Pro package. Use ArgumentLine for one-line calls.
  Include LANG_LIST=en_GB where applicable.

-AllowAcrobatProLanguageNotVerified
  Bypasses the Acrobat Pro UK English proof check. Use only for a pre-configured Adobe enterprise package.

-ComponentDirectory
  Folder containing components\Common.ps1 and the six task scripts.

-ComponentBaseUrl
  Raw URL base used to download missing components. Defaults to the GitHub components folder.

-ComponentPackageUrl
  Zip package fallback used if individual component downloads are unavailable.

-NoComponentDownload
  Fails if a component is missing instead of downloading it.

-DownloadRetryCount / -DownloadRetryDelaySeconds
  Retries installer/component downloads before failing. Defaults to 3 attempts with 5 seconds between attempts.

Exit codes
----------
0     Success
1     Orchestrator failure
20    Operator cancelled
101   LEAP remove/clean failed
102   Adobe remove/clean failed
103   Office remove/clean failed
104   Office install failed
105   Adobe install/policy failed
106   LEAP install failed
3010  Reboot required

Outputs
-------
Logs:     <WorkingRoot>\Logs
Reports:  <WorkingRoot>\Reports
State:    <WorkingRoot>\RunState
Backups:  <WorkingRoot>\Backups
"@

if ($ShowGuide) {
    Write-Host $Script:ZiAASRunGuide
    exit 0
}

$Script:OriginalBoundParameters = @{}
foreach ($key in $PSBoundParameters.Keys) {
    $Script:OriginalBoundParameters[$key] = $true
}

function Import-ZiaasDeploymentConfig {
    param([Parameter(Mandatory = $true)][string]$Path)

    if (-not (Test-Path -LiteralPath $Path)) {
        throw "Config file was not found: $Path"
    }

    $config = Get-Content -LiteralPath $Path -Raw | ConvertFrom-Json
    $allowedNames = @(
        "WorkingRoot", "InstallMode", "Simulation", "ForceCloseApps", "SkipOffice", "SkipAdobe",
        "DisableAdobeAutoUpdate", "KeepDownloads", "SkipLeapProfileCleanup", "Unattended", "NoLogo",
        "OfficeDeploymentToolUrl", "OfficeScrubToolUrl", "AdobeProduct", "AdobeReaderInstallerUrl",
        "AdobeAcrobatProInstallerPath", "AdobeAcrobatProInstallerUrl", "AdobeAcrobatProInstallArguments",
        "AdobeAcrobatProInstallArgumentLine",
        "AllowAcrobatProInstallerWithoutArguments", "AllowAcrobatProLanguageNotVerified",
        "AdobeAcrobatProTrustedPublisherFragments", "AdobeCleanerToolUrl", "LeapInstallerPath",
        "LeapInstallerUrl", "LeapDownloadsPageUrl", "LeapInstallerSearchRoots",
        "AllowLocalLeapInstallerFallback", "LeapInstallArguments", "LeapTrustedPublisherFragments",
        "PostCleanupWaitSeconds", "PreLeapWaitSeconds", "ComponentDirectory", "ComponentBaseUrl", "ComponentPackageUrl",
        "NoComponentDownload", "DownloadRetryCount", "DownloadRetryDelaySeconds"
    )

    foreach ($name in $allowedNames) {
        $property = $config.PSObject.Properties[$name]
        if ($null -eq $property) {
            continue
        }

        if ($Script:OriginalBoundParameters.ContainsKey($name)) {
            continue
        }

        Set-Variable -Name $name -Value $property.Value -Scope Script
    }
}

if (-not [string]::IsNullOrWhiteSpace($DeploymentConfigPath)) {
    Import-ZiaasDeploymentConfig -Path $DeploymentConfigPath
}

if ([string]::IsNullOrWhiteSpace($ComponentDirectory)) {
    $ComponentDirectory = Join-Path $PSScriptRoot "components"
}

$requiredComponentFiles = @(
    "Common.ps1",
    "LEAP.RemoveClean.ps1",
    "Adobe.RemoveClean.ps1",
    "Office.RemoveClean.ps1",
    "Office.Install.ps1",
    "Adobe.Install.ps1",
    "LEAP.Install.ps1"
)

function Invoke-ZiaasWebDownloadWithRetry {
    param(
        [Parameter(Mandatory = $true)][string]$Uri,
        [Parameter(Mandatory = $true)][string]$OutFile,
        [Parameter(Mandatory = $true)][string]$Description
    )

    $attemptLimit = [Math]::Max(1, $DownloadRetryCount)
    $lastError = $null
    for ($attempt = 1; $attempt -le $attemptLimit; $attempt++) {
        try {
            if ($attempt -gt 1) {
                Write-Host "Retrying $Description download ($attempt of $attemptLimit)..."
            }
            Invoke-WebRequest -Uri $Uri -OutFile $OutFile -UseBasicParsing -TimeoutSec 120
            return
        }
        catch {
            $lastError = $_.Exception.Message
            if ($attempt -ge $attemptLimit) {
                break
            }
            Write-Host "$Description download attempt $attempt failed. Retrying in $DownloadRetryDelaySeconds seconds..."
            if ($DownloadRetryDelaySeconds -gt 0) {
                Start-Sleep -Seconds $DownloadRetryDelaySeconds
            }
        }
    }

    throw "$Description download failed after $attemptLimit attempt(s). Last error: $lastError"
}

function Test-ZiaasRequiredComponentsPresent {
    foreach ($fileName in $requiredComponentFiles) {
        if (-not (Test-Path -LiteralPath (Join-Path $ComponentDirectory $fileName))) {
            return $false
        }
    }

    return $true
}

function Install-ZiaasComponentPackage {
    if ([string]::IsNullOrWhiteSpace($ComponentPackageUrl)) {
        throw "Required component scripts are missing and no component package URL was supplied."
    }

    $packageParent = Split-Path -Parent $ComponentDirectory
    $packagePath = Join-Path $packageParent "ZiAAS_Woodstock_Baselining.components.package"
    $zipPath = Join-Path $packageParent "ZiAAS_Woodstock_Baselining.components.zip"
    foreach ($path in @($packagePath, $zipPath)) {
        if (Test-Path -LiteralPath $path) {
            Remove-Item -LiteralPath $path -Force
        }
    }

    Write-Host "Downloading ZiAAS component package..."
    Invoke-ZiaasWebDownloadWithRetry -Uri $ComponentPackageUrl -OutFile $packagePath -Description "Component package"

    $packageBytes = [System.IO.File]::ReadAllBytes($packagePath)
    if (($packageBytes.Length -ge 2) -and ($packageBytes[0] -eq 0x50) -and ($packageBytes[1] -eq 0x4B)) {
        Move-Item -LiteralPath $packagePath -Destination $zipPath -Force
    }
    else {
        $base64Package = (Get-Content -LiteralPath $packagePath -Raw).Trim()
        [System.IO.File]::WriteAllBytes($zipPath, [Convert]::FromBase64String($base64Package))
    }

    Expand-Archive -LiteralPath $zipPath -DestinationPath $ComponentDirectory -Force

    if (-not (Test-ZiaasRequiredComponentsPresent)) {
        throw "Component package was downloaded and extracted, but one or more required component scripts are still missing."
    }
}

function Ensure-ZiaasComponents {
    if (-not (Test-Path -LiteralPath $ComponentDirectory)) {
        New-Item -Path $ComponentDirectory -ItemType Directory -Force | Out-Null
    }

    if (Test-ZiaasRequiredComponentsPresent) {
        return
    }

    if ($NoComponentDownload) {
        $missing = @($requiredComponentFiles | Where-Object { -not (Test-Path -LiteralPath (Join-Path $ComponentDirectory $_)) })
        throw "Required component script(s) missing and -NoComponentDownload was supplied: $($missing -join ', ')"
    }

    $individualDownloadFailed = $false
    foreach ($fileName in $requiredComponentFiles) {
        $path = Join-Path $ComponentDirectory $fileName
        if (Test-Path -LiteralPath $path) {
            continue
        }

        if ([string]::IsNullOrWhiteSpace($ComponentBaseUrl)) {
            $individualDownloadFailed = $true
            break
        }

        $url = ($ComponentBaseUrl.TrimEnd('/') + '/' + $fileName)
        Write-Host "Downloading component $fileName..."
        try {
            Invoke-ZiaasWebDownloadWithRetry -Uri $url -OutFile $path -Description "Component $fileName"
        }
        catch {
            Write-Host "Component file download failed: $($_.Exception.Message)"
            $individualDownloadFailed = $true
            break
        }
    }

    if (Test-ZiaasRequiredComponentsPresent) {
        return
    }

    if ($individualDownloadFailed) {
        Write-Host "Falling back to the component package download..."
    }

    Install-ZiaasComponentPackage
}

Ensure-ZiaasComponents
$ComponentName = "ZiAAS_Woodstock_Baselining-Orchestrator"
. (Join-Path $ComponentDirectory "Common.ps1")

$Script:ComponentResults = @()
$Script:SelectedLabel = $null
$Script:SelectedAdobeLabel = $null
$Script:ConfigPath = $null
$Script:ReportsDir = Join-Path $Script:Root "Reports"

function Write-ZiaasUiLine {
    param(
        [string]$Text = "",
        [ConsoleColor]$Color = [ConsoleColor]::Gray
    )

    Write-Host $Text -ForegroundColor $Color
}

function Write-ZiaasBanner {
    if ($NoLogo) {
        return
    }

    Write-Host ""
    Write-ZiaasUiLine "============================================================" Cyan
    Write-ZiaasUiLine " ZiAAS Woodstock Baselining" Cyan
    Write-ZiaasUiLine " Office, Adobe, and LEAP enterprise deployment orchestrator" DarkCyan
    Write-ZiaasUiLine "============================================================" Cyan
    Write-ZiaasUiLine " Use -ShowGuide for arguments, examples, exit codes, and outputs." DarkGray
    Write-Host ""
}

function Get-ZiaasPlannedSteps {
    param(
        [Parameter(Mandatory = $true)]$Selection,
        [object]$AdobeSelection
    )

    $steps = New-Object System.Collections.Generic.List[string]
    if ($Selection.InstallLeap) { $steps.Add("LEAP remove and clean") }
    if ($Selection.InstallAdobe) { $steps.Add("Adobe Reader/Acrobat remove and clean") }
    if ($Selection.InstallOffice) { $steps.Add("Office remove and clean") }
    if ($Selection.InstallOffice -or $Selection.InstallAdobe) { $steps.Add("Wait $PostCleanupWaitSeconds seconds") }
    if ($Selection.InstallOffice) { $steps.Add("Install Microsoft 365 Apps for enterprise x64 en-GB Semi-Annual Enterprise") }
    if ($Selection.InstallAdobe) {
        $adobeLabel = if ($AdobeSelection) { $AdobeSelection.Label } else { "selected Adobe product" }
        $steps.Add("Install $adobeLabel and apply Adobe policies")
    }
    if ($Selection.InstallLeap -and ($Selection.InstallOffice -or $Selection.InstallAdobe)) { $steps.Add("Wait $PreLeapWaitSeconds seconds before LEAP") }
    if ($Selection.InstallLeap) { $steps.Add("Install LEAP last") }
    return @($steps)
}

function Write-ZiaasPreflightSummary {
    param(
        [Parameter(Mandatory = $true)]$Selection,
        [object]$AdobeSelection
    )

    Write-Host ""
    Write-ZiaasUiLine "Preflight summary" Yellow
    Write-ZiaasUiLine "-----------------" Yellow
    Write-ZiaasUiLine ("Mode:          {0}" -f $Selection.Label)
    Write-ZiaasUiLine ("Office:        {0}" -f ($(if ($Selection.InstallOffice) { "Microsoft 365 Apps for enterprise, x64, en-GB, Semi-Annual Enterprise" } else { "Skipped" })))
    Write-ZiaasUiLine ("Adobe:         {0}" -f ($(if ($Selection.InstallAdobe) { $AdobeSelection.Label } else { "Skipped" })))
    Write-ZiaasUiLine ("LEAP:          {0}" -f ($(if ($Selection.InstallLeap) { "Remove first, install last" } else { "Skipped" })))
    Write-ZiaasUiLine ("Simulation:    {0}" -f ([bool]$Simulation))
    Write-ZiaasUiLine ("Working root:  {0}" -f $Script:Root)
    Write-ZiaasUiLine ("Logs:          {0}" -f $Script:LogDir)
    Write-ZiaasUiLine ("Reports:       {0}" -f $Script:ReportsDir)
    Write-ZiaasUiLine ("Components:    {0}" -f $ComponentDirectory)
    Write-ZiaasUiLine ""
    Write-ZiaasUiLine "Planned sequence:" Yellow
    $index = 1
    foreach ($step in Get-ZiaasPlannedSteps -Selection $Selection -AdobeSelection $AdobeSelection) {
        Write-ZiaasUiLine ("  {0}. {1}" -f $index, $step)
        $index++
    }
    Write-Host ""
}

function Confirm-ZiaasInteractiveRun {
    param([Parameter(Mandatory = $true)]$Selection)

    if ($Unattended) {
        return
    }

    if ($InstallMode -ne "Prompt") {
        return
    }

    do {
        $answer = Read-Host "Proceed with $($Selection.Label)? Enter Y to continue or N to cancel"
    } until ($answer -match "^(?i:y|yes|n|no)$")

    if ($answer -match "^(?i:n|no)$") {
        throw "Operator cancelled before deployment started."
    }
}

function Write-ZiaasSummaryReport {
    param(
        [Parameter(Mandatory = $true)][string]$Status,
        [Parameter(Mandatory = $true)][int]$ExitCode,
        [string]$FailureMessage
    )

    if (-not (Test-Path -LiteralPath $Script:ReportsDir)) {
        New-Item -Path $Script:ReportsDir -ItemType Directory -Force | Out-Null
    }

    $elapsed = New-TimeSpan -Start $Script:StartTime -End (Get-Date)
    $summary = [ordered]@{
        App = "ZiAAS Woodstock Baselining"
        Status = $Status
        ExitCode = $ExitCode
        RebootRequired = [bool]$Script:RebootRequired
        Started = $Script:StartTime.ToString("s")
        Finished = (Get-Date).ToString("s")
        Elapsed = ("{0:g}" -f $elapsed)
        Selection = $Script:SelectedLabel
        AdobeProduct = $Script:SelectedAdobeLabel
        WorkingRoot = $Script:Root
        LogFile = $Script:LogFile
        DeploymentConfigPath = $DeploymentConfigPath
        ConfigPath = $Script:ConfigPath
        ComponentDirectory = $ComponentDirectory
        DownloadRetryCount = $DownloadRetryCount
        DownloadRetryDelaySeconds = $DownloadRetryDelaySeconds
        FailureMessage = $FailureMessage
        Components = @($Script:ComponentResults)
    }

    $jsonPath = Join-Path $Script:ReportsDir "summary-$Script:RunStamp.json"
    $textPath = Join-Path $Script:ReportsDir "summary-$Script:RunStamp.txt"
    $summary | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $jsonPath -Encoding UTF8

    $lines = New-Object System.Collections.Generic.List[string]
    $lines.Add("ZiAAS Woodstock Baselining Summary")
    $lines.Add("==================================")
    $lines.Add("Status: $Status")
    $lines.Add("Exit code: $ExitCode")
    $lines.Add("Reboot required: $($Script:RebootRequired)")
    $lines.Add("Selection: $($Script:SelectedLabel)")
    $lines.Add("Adobe: $($Script:SelectedAdobeLabel)")
    $lines.Add("Elapsed: $($summary.Elapsed)")
    if ($FailureMessage) { $lines.Add("Failure: $FailureMessage") }
    $lines.Add("")
    $lines.Add("Components:")
    foreach ($component in @($Script:ComponentResults)) {
        $lines.Add(("  - {0}: {1} (exit {2})" -f $component.Description, $component.Status, $component.ExitCode))
    }
    $lines.Add("")
    $lines.Add("Logs: $Script:LogDir")
    $lines.Add("JSON report: $jsonPath")
    $lines | Set-Content -LiteralPath $textPath -Encoding UTF8

    Write-Log "Wrote summary report: $textPath"
    Write-Log "Wrote JSON report: $jsonPath"

    Write-Host ""
    Write-ZiaasUiLine "Run summary" Yellow
    Write-ZiaasUiLine "-----------" Yellow
    Write-ZiaasUiLine ("Status:          {0}" -f $Status)
    Write-ZiaasUiLine ("Exit code:       {0}" -f $ExitCode)
    Write-ZiaasUiLine ("Reboot required: {0}" -f $Script:RebootRequired)
    Write-ZiaasUiLine ("Text report:     {0}" -f $textPath)
    Write-ZiaasUiLine ("JSON report:     {0}" -f $jsonPath)
    Write-Host ""
}

function New-ZiaasRunConfig {
    param(
        [Parameter(Mandatory = $true)]$Selection,
        [object]$AdobeSelection
    )

    $resolvedAdobeProduct = if ($AdobeSelection) { $AdobeSelection.Product } else { $AdobeProduct }

    [ordered]@{
        WorkingRoot = $WorkingRoot
        DeploymentConfigPath = $DeploymentConfigPath
        InstallMode = $InstallMode
        InstallModeParameterWasUsed = $PSBoundParameters.ContainsKey("InstallMode")
        SkipOfficeParameterWasUsed = $PSBoundParameters.ContainsKey("SkipOffice")
        SkipAdobeParameterWasUsed = $PSBoundParameters.ContainsKey("SkipAdobe")
        Simulation = [bool]$Simulation
        ForceCloseApps = [bool]$ForceCloseApps
        SkipOffice = [bool]$SkipOffice
        SkipAdobe = [bool]$SkipAdobe
        DisableAdobeAutoUpdate = [bool]$DisableAdobeAutoUpdate
        KeepDownloads = [bool]$KeepDownloads
        SkipLeapProfileCleanup = [bool]$SkipLeapProfileCleanup
        Unattended = [bool]$Unattended
        OfficeDeploymentToolUrl = $OfficeDeploymentToolUrl
        OfficeScrubToolUrl = $OfficeScrubToolUrl
        AdobeProduct = $resolvedAdobeProduct
        AdobeReaderInstallerUrl = $AdobeReaderInstallerUrl
        AdobeAcrobatProInstallerPath = $AdobeAcrobatProInstallerPath
        AdobeAcrobatProInstallerUrl = $AdobeAcrobatProInstallerUrl
        AdobeAcrobatProInstallArguments = @($AdobeAcrobatProInstallArguments)
        AdobeAcrobatProInstallArgumentLine = $AdobeAcrobatProInstallArgumentLine
        AllowAcrobatProInstallerWithoutArguments = [bool]$AllowAcrobatProInstallerWithoutArguments
        AllowAcrobatProLanguageNotVerified = [bool]$AllowAcrobatProLanguageNotVerified
        AdobeAcrobatProTrustedPublisherFragments = @($AdobeAcrobatProTrustedPublisherFragments)
        AdobeCleanerToolUrl = $AdobeCleanerToolUrl
        LeapInstallerPath = $LeapInstallerPath
        LeapInstallerUrl = $LeapInstallerUrl
        LeapDownloadsPageUrl = $LeapDownloadsPageUrl
        LeapInstallerSearchRoots = @($LeapInstallerSearchRoots)
        AllowLocalLeapInstallerFallback = [bool]$AllowLocalLeapInstallerFallback
        LeapInstallArguments = @($LeapInstallArguments)
        LeapTrustedPublisherFragments = @($LeapTrustedPublisherFragments)
        PostCleanupWaitSeconds = $PostCleanupWaitSeconds
        PreLeapWaitSeconds = $PreLeapWaitSeconds
        DownloadRetryCount = $DownloadRetryCount
        DownloadRetryDelaySeconds = $DownloadRetryDelaySeconds
        RunStamp = $Script:RunStamp
        InstallOffice = [bool]$Selection.InstallOffice
        InstallAdobe = [bool]$Selection.InstallAdobe
        InstallLeap = [bool]$Selection.InstallLeap
        SelectionLabel = $Selection.Label
    }
}

function Invoke-ZiaasComponentScript {
    param(
        [Parameter(Mandatory = $true)][string]$FileName,
        [Parameter(Mandatory = $true)][string]$Description,
        [Parameter(Mandatory = $true)][string]$ConfigPath
    )

    $componentPath = Join-Path $ComponentDirectory $FileName
    if (-not (Test-Path -LiteralPath $componentPath)) {
        throw "Component script was not found: $componentPath"
    }

    Write-Log "Starting component: $Description"
    & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $componentPath -ConfigPath $ConfigPath
    $exitCode = $LASTEXITCODE
    Write-Log "Component finished with exit code ${exitCode}: $Description"

    $componentLogName = ([System.IO.Path]::GetFileNameWithoutExtension($FileName) -replace "\.", "-")
    $componentLogPath = Join-Path $Script:LogDir "$componentLogName-$Script:RunStamp.log"

    if ($exitCode -eq 0) {
        $Script:ComponentResults += [pscustomobject]@{
            File = $FileName
            Description = $Description
            Status = "Success"
            ExitCode = $exitCode
            LogFile = $componentLogPath
        }
        return
    }

    if ($exitCode -eq 3010) {
        $Script:RebootRequired = $true
        Write-Log "Component requested a reboot; continuing so the selected deployment sequence can finish." "WARN"
        $Script:ComponentResults += [pscustomobject]@{
            File = $FileName
            Description = $Description
            Status = "RebootRequired"
            ExitCode = $exitCode
            LogFile = $componentLogPath
        }
        return
    }

    $Script:ComponentResults += [pscustomobject]@{
        File = $FileName
        Description = $Description
        Status = "Failed"
        ExitCode = $exitCode
        LogFile = $componentLogPath
    }

    throw "Component failed with exit code ${exitCode}: $Description"
}

try {
    Initialize-DeploymentFolders
    Write-ZiaasBanner
    Write-Log "ZiAAS Woodstock Baselining orchestration started."
    Write-Log "Log file: $Script:LogFile"
    Write-Log "Working root: $Script:Root"
    Write-Log "Component directory: $ComponentDirectory"
    Assert-AdminAndPlatform

    if ($Unattended -and $InstallMode -eq "Prompt") {
        throw "Unattended mode requires an explicit -InstallMode value."
    }

    $selection = Resolve-InstallSelection
    $installOffice = [bool]$selection.InstallOffice
    $installAdobe = [bool]$selection.InstallAdobe
    $installLeap = [bool]$selection.InstallLeap
    $Script:SelectedLabel = $selection.Label
    Write-Log "Selected deployment mode: $($selection.Label)"

    if ($Unattended -and $installAdobe -and $AdobeProduct -eq "Prompt") {
        throw "Unattended mode requires -AdobeProduct Reader or -AdobeProduct AcrobatPro when Adobe is selected."
    }

    $adobeSelection = Resolve-AdobeProductSelection -InstallAdobe $installAdobe
    if ($installAdobe) {
        $Script:SelectedAdobeLabel = $adobeSelection.Label
        Write-Log "Selected Adobe product: $($adobeSelection.Label)"
        Assert-AdobeInstallerSourceAvailable -AdobeSelection $adobeSelection
    }
    else {
        $Script:SelectedAdobeLabel = "Skipped"
    }

    if ($installLeap) {
        Assert-LeapInstallerSourceAvailable
    }

    Write-ZiaasPreflightSummary -Selection $selection -AdobeSelection $adobeSelection
    Confirm-ZiaasInteractiveRun -Selection $selection

    $runStateDir = Join-Path $Script:Root "RunState"
    if (-not (Test-Path -LiteralPath $runStateDir)) {
        New-Item -Path $runStateDir -ItemType Directory -Force | Out-Null
    }

    $configPath = Join-Path $runStateDir "ZiAAS-Woodstock-Baselining-$Script:RunStamp.json"
    $config = New-ZiaasRunConfig -Selection $selection -AdobeSelection $adobeSelection
    $config | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $configPath -Encoding UTF8
    $Script:ConfigPath = $configPath
    Write-Log "Wrote run configuration: $configPath"

    if ($installLeap) {
        Invoke-ZiaasComponentScript -FileName "LEAP.RemoveClean.ps1" -Description "LEAP uninstall and cleanup" -ConfigPath $configPath
    }
    else {
        Write-Log "Skipping LEAP uninstall/cleanup for selected deployment mode." "WARN"
    }

    if ($installAdobe) {
        Invoke-ZiaasComponentScript -FileName "Adobe.RemoveClean.ps1" -Description "Adobe Reader/Acrobat uninstall and cleanup" -ConfigPath $configPath
    }
    else {
        Write-Log "Skipping Adobe uninstall/cleanup for selected deployment mode." "WARN"
    }

    if ($installOffice) {
        Invoke-ZiaasComponentScript -FileName "Office.RemoveClean.ps1" -Description "Office uninstall and cleanup" -ConfigPath $configPath
    }
    else {
        Write-Log "Skipping Office uninstall/cleanup for selected deployment mode." "WARN"
    }

    if ($installOffice -or $installAdobe) {
        Invoke-DeploymentPause -Seconds $PostCleanupWaitSeconds -Reason "post-cleanup settling before fresh installs"
    }

    if ($installOffice) {
        Invoke-ZiaasComponentScript -FileName "Office.Install.ps1" -Description "Microsoft 365 Apps install" -ConfigPath $configPath
    }

    if ($installAdobe) {
        Invoke-ZiaasComponentScript -FileName "Adobe.Install.ps1" -Description "Adobe Reader/Acrobat install and policy configuration" -ConfigPath $configPath
    }

    if ($installLeap -and ($installOffice -or $installAdobe)) {
        Invoke-DeploymentPause -Seconds $PreLeapWaitSeconds -Reason "Office/Adobe installation completion before LEAP add-in install"
    }

    if ($installLeap) {
        Invoke-ZiaasComponentScript -FileName "LEAP.Install.ps1" -Description "LEAP install" -ConfigPath $configPath
    }
    else {
        Write-Log "Skipping LEAP install for selected deployment mode." "WARN"
    }

    Remove-WorkingDownloadsIfRequested

    $elapsed = New-TimeSpan -Start $Script:StartTime -End (Get-Date)
    Write-Log ("ZiAAS Woodstock Baselining orchestration completed in {0:g}." -f $elapsed) "SUCCESS"
    if ($Script:RebootRequired) {
        Write-Log "A reboot is required to finish one or more changes." "WARN"
        Write-ZiaasSummaryReport -Status "RebootRequired" -ExitCode 3010
        exit 3010
    }

    Write-ZiaasSummaryReport -Status "Success" -ExitCode 0
    exit 0
}
catch {
    $failureMessage = $_.Exception.Message
    $exitCode = if ($failureMessage -like "Operator cancelled*") { 20 } else { 1 }
    try {
        Write-Log $failureMessage "ERROR"
        Write-Log "ZiAAS Woodstock Baselining orchestration failed. See component logs in $Script:LogDir." "ERROR"
        Write-ZiaasSummaryReport -Status "Failed" -ExitCode $exitCode -FailureMessage $failureMessage
    }
    catch {
        Write-Host "ZiAAS Woodstock Baselining orchestration failed before logging was available. $failureMessage"
    }
    exit $exitCode
}
