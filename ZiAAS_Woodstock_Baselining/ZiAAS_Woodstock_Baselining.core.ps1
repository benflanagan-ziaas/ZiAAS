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
    [string]$BrandPackPath,

    [ValidateSet("Prompt", "Office", "OfficeAndAdobe", "OfficeAndAdobeReader", "Adobe", "AdobeReader", "Leap", "OfficeAndLeap", "AdobeAndLeap", "AdobeReaderAndLeap", "OfficeAndAdobeAndLeap", "OfficeAndAdobeReaderAndLeap", "All")]
    [string]$InstallMode = "Prompt",

    [switch]$Simulation,
    [ValidateSet(0, 200, 300)]
    [int]$SimulationAcrobatProEntitlementLevel = 300,
    [switch]$ForceCloseApps,
    [switch]$SkipOffice,
    [switch]$SkipAdobe,
    [switch]$DisableAdobeAutoUpdate,
    [switch]$KeepDownloads,
    [switch]$SkipLeapProfileCleanup,
    [switch]$Unattended,
    [switch]$ShowGuide,
    [switch]$NoLogo,
    [switch]$PreflightOnly,
    [switch]$ResumeLastRun,
    [switch]$CreateSupportBundle,
    [switch]$NoColor,
    [switch]$Quiet,

    [ValidateSet("Debug", "Info", "Warn")]
    [string]$LogLevel = "Info",

    [string]$OfficeDeploymentToolUrl = "https://download.microsoft.com/download/6c1eeb25-cf8b-41d9-8d0d-cc1dbc032140/officedeploymenttool_20026-20112.exe",
    [string]$OfficeScrubToolUrl = "https://aka.ms/SaRA_EnterpriseVersionFiles",
    [ValidateSet("O365ProPlusRetail", "O365ProPlusEEANoTeamsRetail")]
    [string]$OfficeProductId = "O365ProPlusRetail",

    [ValidateSet("Prompt", "Reader", "AcrobatPro")]
    [string]$AdobeProduct = "Prompt",

    [string]$AdobeReaderInstallerUrl = "https://ardownload2.adobe.com/pub/adobe/acrobat/win/AcrobatDC/2600121691/AcroRdrDCx642600121691_MUI.exe",
    [string]$AdobeAcrobatProInstallerPath,
    [string]$AdobeAcrobatProInstallerUrl,
    [string[]]$AdobeAcrobatProInstallArguments = @(),
    [string]$AdobeAcrobatProInstallArgumentLine,
    [switch]$AllowAcrobatProInstallerWithoutArguments,
    [switch]$AllowAcrobatProLanguageNotVerified,
    [switch]$AllowAcrobatProEntitlementNotVerified,
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
    [string]$ComponentBaseUrl = "https://raw.githubusercontent.com/benflanagan-ziaas/ZiAAS/refs/heads/main/ZiAAS_Woodstock_Baselining/components",
    [string]$ComponentPackageUrl = "https://raw.githubusercontent.com/benflanagan-ziaas/ZiAAS/refs/heads/main/ZiAAS_Woodstock_Baselining/ZiAAS_Woodstock_Baselining.components.zip.b64",
    [switch]$NoComponentDownload,
    [switch]$UseCachedInstallers,
    [string]$ManifestUrl,
    [string]$ExpectedManifestHash,
    [string]$ExpectedComponentPackageHash,

    [ValidateRange(1, 10)]
    [int]$DownloadRetryCount = 3,

    [ValidateRange(0, 300)]
    [int]$DownloadRetryDelaySeconds = 5
)

Set-StrictMode -Version 2.0
$ErrorActionPreference = "Stop"
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
Import-Module Microsoft.PowerShell.Utility -ErrorAction SilentlyContinue

$Script:ZiAASRunGuide = @"
ZiAAS Woodstock Baselining - Running Guide
=========================================

Purpose
-------
Baselines a Windows client by removing and reinstalling selected products in a controlled order:
  1. Download, signature-check, hash, and stage all selected reinstall media
  2. LEAP remove and clean, if selected
  3. Adobe Reader/Acrobat remove and clean, if selected
  4. Office remove and clean, if selected
  5. Wait for post-cleanup settling
  6. Microsoft 365 Apps for enterprise install, if selected
  7. Adobe Reader/Acrobat install and enterprise policies, if selected
  8. Wait before LEAP
  9. LEAP install last, if selected

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

Preflight only, no cleanup or install:
  powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\ZiAAS_Woodstock_Baselining.ps1 -PreflightOnly -InstallMode All -AdobeProduct Reader

Resume from the last safe failed boundary:
  powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\ZiAAS_Woodstock_Baselining.ps1 -ResumeLastRun

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
  Adobe maps International English en_GB to its en_US English resource transform. Reader mode is enforced by machine policy.
  AcrobatPro requires a licensed enterprise installer path or URL before the run starts.
  Do not rely on an already-installed Acrobat Pro copy; Adobe cleanup removes existing Reader/Acrobat first.

-OfficeProductId
  Allowed enterprise product IDs are O365ProPlusRetail (default) and O365ProPlusEEANoTeamsRetail.
  Consumer product IDs are rejected.

-AllowAcrobatProEntitlementNotVerified
  Explicitly allows a Pro deployment when the current Windows user cannot yet expose Adobe entitlement level 300.
  The default is fail-closed because a unified Reader install can otherwise be mistaken for Acrobat Pro.

-Unattended
  Fails early if a prompt would be required. Use this for RMM/Intune scripts.

-PreflightOnly
  Validates prerequisites, selected sequence, installer endpoints, disk space, and blocking apps without cleanup or installation.
  A real run then downloads and verifies every selected installer before the first uninstall begins.

-ResumeLastRun
  Loads the latest failed run state and skips component steps already recorded as complete after preflight passes.

-Simulation
  Exercises the full flow, logging, component order, and exit handling without changing the machine.

-NoColor / -Quiet / -LogLevel
  Controls console output for RMM logs. Full log files are still written under the working root.

-CreateSupportBundle
  Creates a sanitized zip containing logs, reports, run state, manifest, and machine summary.

-ForceCloseApps
  Allows the script to force-close blocking Office, Adobe, and LEAP apps. Use only when users have saved work.

-KeepDownloads
  Leaves installer/cache files under the working root for review or reuse.

-WorkingRoot
  Defaults to C:\ProgramData\ZiAAS_Woodstock_Baselining. Logs, state, reports, downloads, and backups live here.

-BrandPackPath
  Optional JSON brand pack for product/company names, terminal wording, report footer, and support details.
  Defaults to config\brand.ziaas-woodstock.json when present, otherwise uses a built-in ZiAAS fallback.

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
  Required for Acrobat Pro real deployments before cleanup begins.

-AdobeAcrobatProInstallArguments / -AdobeAcrobatProInstallArgumentLine
  Silent install arguments for the licensed Acrobat Pro package. Use ArgumentLine for one-line calls.
  Include LANG_LIST=en_GB where applicable.

-AllowAcrobatProLanguageNotVerified
  Bypasses the Acrobat Pro UK English proof check. Use only for a pre-configured Adobe enterprise package.

-ComponentDirectory
  Folder containing components\Common.ps1 and the component task scripts.

-ComponentBaseUrl
  Raw URL base used to download missing components. Defaults to the GitHub components folder.

-ComponentPackageUrl
  Zip package fallback used if individual component downloads are unavailable.

-NoComponentDownload
  Fails if a component is missing instead of downloading it.

-UseCachedInstallers
  Allows installer reuse from the working-root cache after size/signature validation. Without it, installers are refreshed.

-ManifestUrl / -ExpectedManifestHash
  Overrides or pins the release manifest used by raw URL bootstrap validation.

-DownloadRetryCount / -DownloadRetryDelaySeconds
  Retries installer/component downloads before failing. Defaults to 3 attempts with 5 seconds between attempts.

Recovery examples
-----------------
Blocking apps:
  Save work, close listed applications, rerun the same command. Use -ForceCloseApps only when user work is saved.

Acrobat Pro:
  Supply a licensed installer path or URL, silent install arguments, and LANG_LIST=en_GB unless using a pre-configured package.

LEAP:
  If official installer discovery fails, retry later or supply -LeapInstallerPath / -LeapInstallerUrl. LEAP always installs last.

Exit codes
----------
0     Success
1     Orchestrator failure
20    Operator cancelled
100   Installer staging/signature verification failed before cleanup
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
        "WorkingRoot", "BrandPackPath", "InstallMode", "Simulation", "SimulationAcrobatProEntitlementLevel", "ForceCloseApps", "SkipOffice", "SkipAdobe",
        "DisableAdobeAutoUpdate", "KeepDownloads", "SkipLeapProfileCleanup", "Unattended", "NoLogo",
        "PreflightOnly", "ResumeLastRun", "CreateSupportBundle", "NoColor", "Quiet", "LogLevel",
        "OfficeDeploymentToolUrl", "OfficeScrubToolUrl", "OfficeProductId", "AdobeProduct", "AdobeReaderInstallerUrl",
        "AdobeAcrobatProInstallerPath", "AdobeAcrobatProInstallerUrl", "AdobeAcrobatProInstallArguments",
        "AdobeAcrobatProInstallArgumentLine",
        "AllowAcrobatProInstallerWithoutArguments", "AllowAcrobatProLanguageNotVerified", "AllowAcrobatProEntitlementNotVerified",
        "AdobeAcrobatProTrustedPublisherFragments", "AdobeCleanerToolUrl", "LeapInstallerPath",
        "LeapInstallerUrl", "LeapDownloadsPageUrl", "LeapInstallerSearchRoots",
        "AllowLocalLeapInstallerFallback", "LeapInstallArguments", "LeapTrustedPublisherFragments",
        "PostCleanupWaitSeconds", "PreLeapWaitSeconds", "ComponentDirectory", "ComponentBaseUrl", "ComponentPackageUrl",
        "NoComponentDownload", "UseCachedInstallers", "ManifestUrl", "ExpectedManifestHash", "ExpectedComponentPackageHash",
        "DownloadRetryCount", "DownloadRetryDelaySeconds"
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
    "Installers.Stage.ps1",
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

function Assert-ZiaasWorkingRoot {
    $candidate = [string]$WorkingRoot
    if ([string]::IsNullOrWhiteSpace($candidate)) {
        throw "WorkingRoot cannot be empty."
    }

    if ($candidate.StartsWith('\\')) {
        throw "WorkingRoot must be a local path, not a UNC path: $candidate"
    }

    try {
        $fullPath = [IO.Path]::GetFullPath($candidate).TrimEnd('\')
    }
    catch {
        throw "WorkingRoot is not a valid local path: $candidate. $($_.Exception.Message)"
    }

    $driveRoot = [IO.Path]::GetPathRoot($fullPath).TrimEnd('\')
    if ([string]::IsNullOrWhiteSpace($driveRoot) -or $fullPath -ieq $driveRoot) {
        throw "WorkingRoot cannot be a drive root: $candidate"
    }

    $protectedPaths = @(
        $env:SystemRoot,
        $env:ProgramFiles,
        ${env:ProgramFiles(x86)},
        (Join-Path $env:SystemDrive "Users"),
        (Join-Path $env:SystemDrive "ProgramData")
    ) | Where-Object { -not [string]::IsNullOrWhiteSpace($_) } | ForEach-Object {
        try { [IO.Path]::GetFullPath($_).TrimEnd('\') } catch { $null }
    } | Where-Object { $_ }

    foreach ($protected in $protectedPaths) {
        if ($fullPath -ieq $protected) {
            throw "WorkingRoot points at a protected system directory: $fullPath"
        }
    }

    if (Test-Path -LiteralPath $fullPath -PathType Leaf) {
        throw "WorkingRoot exists as a file, not a directory: $fullPath"
    }

    $Script:WorkingRoot = $fullPath
    $Script:ValidatedWorkingRoot = $fullPath
}

$Script:RunMutex = $null
function Enter-ZiaasRunMutex {
    $mutexName = "Global\ZiAAS_Woodstock_Baselining"
    try {
        $Script:RunMutex = [System.Threading.Mutex]::new($false, $mutexName)
        if (-not $Script:RunMutex.WaitOne(0)) {
            $Script:RunMutex.Dispose()
            $Script:RunMutex = $null
            throw "Another ZiAAS Woodstock Baselining run is already active. Wait for it to finish or review its log before starting another run."
        }
    }
    catch {
        if ($_.Exception.Message -like "Another ZiAAS*") { throw }
        throw "Could not acquire the ZiAAS run lock. $($_.Exception.Message)"
    }
}

function Exit-ZiaasRunMutex {
    if ($null -eq $Script:RunMutex) { return }
    try {
        [void]$Script:RunMutex.ReleaseMutex()
    }
    catch {
        # Do not mask the deployment result if the lock was already released.
    }
    finally {
        $Script:RunMutex.Dispose()
        $Script:RunMutex = $null
    }
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

    if (-not $Simulation) {
        if ([string]::IsNullOrWhiteSpace($ExpectedComponentPackageHash)) {
            throw "Component package integrity cannot be verified because ExpectedComponentPackageHash was not supplied. Use the signed GitHub entrypoint or provide the release package hash explicitly."
        }
        $downloadHash = (Get-FileHash -LiteralPath $packagePath -Algorithm SHA256).Hash
        if ($downloadHash -ine $ExpectedComponentPackageHash) {
            throw "Component package hash mismatch. Expected $ExpectedComponentPackageHash, got $downloadHash."
        }
    }

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

    # Component scripts are a signed release unit. Do not mix individually downloaded
    # files from an unverified branch with the package that the manifest describes.
    Write-Host "Downloading verified ZiAAS component package..."
    Install-ZiaasComponentPackage
}

Ensure-ZiaasComponents
$ComponentName = "ZiAAS_Woodstock_Baselining-Orchestrator"
. (Join-Path $ComponentDirectory "Common.ps1")

$Script:ComponentResults = @()
$Script:PreflightResults = @()
$Script:StepRegistry = @()
$Script:ResumeCompletedFiles = @()
$Script:ResumeSourceSummary = $null
$Script:DestructiveWorkStarted = $false
$Script:SupportBundlePath = $null
$Script:Manifest = $null
$Script:ComponentHashes = @()
$Script:InstallerSources = @()
$Script:SelectedLabel = $null
$Script:SelectedAdobeLabel = $null
$Script:ConfigPath = $null
$Script:ReportsDir = Join-Path $Script:Root "Reports"
$Script:Brand = $null
$Script:BrandPackResolvedPath = ""
$Script:BrandCompanyName = "ZiAAS"
$Script:BrandSuiteName = "ZiAAS MSP Toolkit"
$Script:BrandProductName = "Woodstock Baselining"
$Script:BrandBannerTitle = "ZiAAS Woodstock Baselining"
$Script:BrandBannerSubtitle = "Safe operational tooling for MSP engineers"
$Script:BrandReportTitle = "ZiAAS Woodstock Baselining Report"
$Script:BrandReportFooter = "Generated by ZiAAS MSP Toolkit."
$Script:BrandSafeName = "ZiAAS_Woodstock_Baselining"

function Convert-ZiaasSafeName {
    param([Parameter(Mandatory = $true)][string]$Value)

    $safe = ($Value -replace "[^A-Za-z0-9]+", "_").Trim("_")
    if ([string]::IsNullOrWhiteSpace($safe)) {
        return "ZiAAS_Woodstock_Baselining"
    }

    return $safe
}

function Get-ZiaasDefaultBrandPack {
    [pscustomobject]@{
        companyName = "ZiAAS"
        suiteName = "ZiAAS MSP Toolkit"
        productName = "Woodstock Baselining"
        shortDescription = "Baselines Office, Adobe, and LEAP safely."
        audience = "Engineer"
        supportEmail = ""
        supportUrl = ""
        workingRootName = "ZiAAS_Woodstock_Baselining"
        terminal = [pscustomobject]@{
            bannerTitle = "ZiAAS Woodstock Baselining"
            bannerSubtitle = "Safe operational tooling for MSP engineers"
            successLine = "Run completed successfully."
            failureLine = "Run stopped before it could complete safely."
        }
        reports = [pscustomobject]@{
            title = "ZiAAS Woodstock Baselining Report"
            footer = "Generated by ZiAAS MSP Toolkit."
        }
    }
}

function Get-ZiaasBrandValue {
    param(
        [Parameter(Mandatory = $true)]$Brand,
        [Parameter(Mandatory = $true)][string[]]$Path,
        [string]$Default = ""
    )

    $current = $Brand
    foreach ($part in $Path) {
        if ($null -eq $current) {
            return $Default
        }

        $property = $current.PSObject.Properties[$part]
        if ($null -eq $property -or $null -eq $property.Value) {
            return $Default
        }

        $current = $property.Value
    }

    $value = [string]$current
    if ([string]::IsNullOrWhiteSpace($value)) {
        return $Default
    }

    return $value
}

function Resolve-ZiaasBrandPackPath {
    if (-not [string]::IsNullOrWhiteSpace($BrandPackPath)) {
        return $BrandPackPath
    }

    $candidates = @(
        (Join-Path $PSScriptRoot "config\brand.ziaas-woodstock.json"),
        (Join-Path (Split-Path -Parent $ComponentDirectory) "config\brand.ziaas-woodstock.json")
    )

    foreach ($candidate in $candidates) {
        if (Test-Path -LiteralPath $candidate) {
            return $candidate
        }
    }

    return ""
}

function Initialize-ZiaasBranding {
    $brand = Get-ZiaasDefaultBrandPack
    $resolvedPath = Resolve-ZiaasBrandPackPath
    if (-not [string]::IsNullOrWhiteSpace($resolvedPath)) {
        if (-not (Test-Path -LiteralPath $resolvedPath)) {
            throw "Brand pack was supplied but not found: $resolvedPath"
        }

        $brand = Get-Content -LiteralPath $resolvedPath -Raw | ConvertFrom-Json
        $Script:BrandPackResolvedPath = (Resolve-Path -LiteralPath $resolvedPath).Path
    }

    $Script:Brand = $brand
    $Script:BrandCompanyName = Get-ZiaasBrandValue -Brand $brand -Path @("companyName") -Default "ZiAAS"
    $Script:BrandSuiteName = Get-ZiaasBrandValue -Brand $brand -Path @("suiteName") -Default "ZiAAS MSP Toolkit"
    $Script:BrandProductName = Get-ZiaasBrandValue -Brand $brand -Path @("productName") -Default "Woodstock Baselining"
    $Script:BrandBannerTitle = Get-ZiaasBrandValue -Brand $brand -Path @("terminal", "bannerTitle") -Default "$Script:BrandCompanyName $Script:BrandProductName"
    $Script:BrandBannerSubtitle = Get-ZiaasBrandValue -Brand $brand -Path @("terminal", "bannerSubtitle") -Default "Safe operational tooling for MSP engineers"
    $Script:BrandReportTitle = Get-ZiaasBrandValue -Brand $brand -Path @("reports", "title") -Default "$Script:BrandBannerTitle Report"
    $Script:BrandReportFooter = Get-ZiaasBrandValue -Brand $brand -Path @("reports", "footer") -Default "Generated by $Script:BrandSuiteName."
    $Script:BrandSafeName = Convert-ZiaasSafeName -Value $Script:BrandBannerTitle
}

Initialize-ZiaasBranding

function Write-ZiaasUiLine {
    param(
        [string]$Text = "",
        [ConsoleColor]$Color = [ConsoleColor]::Gray
    )

    if ($Quiet) {
        return
    }

    if ($NoColor) {
        Write-Host $Text
        return
    }

    Write-Host $Text -ForegroundColor $Color
}

function Write-ZiaasBanner {
    if ($NoLogo) {
        return
    }

    if (-not $Quiet) { Write-Host "" }
    Write-ZiaasUiLine "============================================================" Cyan
    Write-ZiaasUiLine (" {0}" -f $Script:BrandBannerTitle) Cyan
    Write-ZiaasUiLine (" {0}" -f $Script:BrandBannerSubtitle) DarkCyan
    Write-ZiaasUiLine "============================================================" Cyan
    Write-ZiaasUiLine " Use -ShowGuide for arguments, examples, exit codes, and outputs." DarkGray
    if (-not $Quiet) { Write-Host "" }
}

function New-ZiaasStep {
    param(
        [Parameter(Mandatory = $true)][string]$Id,
        [Parameter(Mandatory = $true)][string]$Description,
        [Parameter(Mandatory = $true)][bool]$Applies,
        [string]$FileName,
        [string]$Kind = "Component",
        [int]$FailureExitCode = 1,
        [string]$Risk = "Low",
        [string]$ExpectedOutput = "",
        [string]$Verification = "",
        [string]$RecoveryHint = ""
    )

    [pscustomobject]@{
        Id = $Id
        Description = $Description
        Applies = $Applies
        FileName = $FileName
        Kind = $Kind
        FailureExitCode = $FailureExitCode
        Risk = $Risk
        ExpectedOutput = $ExpectedOutput
        Verification = $Verification
        RecoveryHint = $RecoveryHint
    }
}

function Get-ZiaasStepRegistry {
    param(
        [Parameter(Mandatory = $true)]$Selection,
        [object]$AdobeSelection
    )

    $adobeLabel = if ($AdobeSelection) { $AdobeSelection.Label } else { "selected Adobe product" }
    return @(
        New-ZiaasStep -Id "preflight" -Description "Preflight checks" -Applies $true -Kind "Internal" -Risk "None" -ExpectedOutput "Preflight result set" -Verification "All blocking prerequisites pass" -RecoveryHint "Resolve failed preflight items and rerun."
        New-ZiaasStep -Id "installer-staging" -Description "Download and verify all selected reinstall media" -Applies $true -FileName "Installers.Stage.ps1" -FailureExitCode 100 -Risk "Download" -ExpectedOutput "Signed installers and Office payload cached before cleanup" -Verification "Hashes, signatures, sizes, and Office payload are recorded" -RecoveryHint "Resolve network, proxy, disk-space, URL, or signature errors; no software has been removed yet."
        New-ZiaasStep -Id "leap-remove-clean" -Description "LEAP uninstall and cleanup" -Applies ([bool]$Selection.InstallLeap) -FileName "LEAP.RemoveClean.ps1" -FailureExitCode 101 -Risk "Destructive" -ExpectedOutput "LEAP removed; safe remnants moved/renamed; LEAP Accounting preserved" -Verification "No LEAP uninstall entries remain" -RecoveryHint "Close LEAP apps, review LEAP remove log, then rerun with the same command."
        New-ZiaasStep -Id "adobe-remove-clean" -Description "Adobe Reader/Acrobat uninstall and cleanup" -Applies ([bool]$Selection.InstallAdobe) -FileName "Adobe.RemoveClean.ps1" -FailureExitCode 102 -Risk "Destructive" -ExpectedOutput "Reader/Acrobat removed and AcroCleaner executed" -Verification "No Adobe Reader/Acrobat uninstall entries remain before reinstall" -RecoveryHint "Close Adobe apps, review Adobe remove log, then rerun."
        New-ZiaasStep -Id "office-remove-clean" -Description "Office uninstall and cleanup" -Applies ([bool]$Selection.InstallOffice) -FileName "Office.RemoveClean.ps1" -FailureExitCode 103 -Risk "Destructive" -ExpectedOutput "Click-to-Run removal attempted and Office scrub completed" -Verification "Office scrub tool completes or requests reboot" -RecoveryHint "Close Office apps, reboot if requested, then rerun."
        New-ZiaasStep -Id "post-cleanup-wait" -Description "Wait $PostCleanupWaitSeconds seconds for post-cleanup settling" -Applies ([bool]($Selection.InstallOffice -or $Selection.InstallAdobe)) -Kind "Pause" -Risk "None" -ExpectedOutput "Installer services settle before fresh installs" -Verification "Pause completes" -RecoveryHint "Rerun if interrupted."
        New-ZiaasStep -Id "office-install-verify" -Description "Install Microsoft 365 Apps for enterprise x64 en-GB with Semi-Annual Enterprise requested" -Applies ([bool]$Selection.InstallOffice) -FileName "Office.Install.ps1" -FailureExitCode 104 -Risk "Install" -ExpectedOutput "Office x64 en-GB enterprise installed" -Verification "ProductReleaseIds, platform, culture, version, and exact enterprise audience verified" -RecoveryHint "Review Office install log, network/CDN access, tenant update policy, and ODT logs."
        New-ZiaasStep -Id "adobe-install-verify" -Description "Install $adobeLabel and apply Adobe policies" -Applies ([bool]$Selection.InstallAdobe) -FileName "Adobe.Install.ps1" -FailureExitCode 105 -Risk "Install" -ExpectedOutput "$adobeLabel installed with New Acrobat disabled" -Verification "Reader/Pro product state and FeatureLockDown policy verified" -RecoveryHint "Review Adobe install log and confirm installer source/language arguments."
        New-ZiaasStep -Id "pre-leap-wait" -Description "Wait $PreLeapWaitSeconds seconds before LEAP add-in installation" -Applies ([bool]($Selection.InstallLeap -and ($Selection.InstallOffice -or $Selection.InstallAdobe))) -Kind "Pause" -Risk "None" -ExpectedOutput "Office and Adobe installers finish settling before LEAP" -Verification "Pause completes" -RecoveryHint "Rerun if interrupted."
        New-ZiaasStep -Id "leap-install-verify" -Description "Install LEAP last" -Applies ([bool]$Selection.InstallLeap) -FileName "LEAP.Install.ps1" -FailureExitCode 106 -Risk "Install" -ExpectedOutput "LEAP installed after Office/Adobe" -Verification "LEAP uninstall entry present and post-install launched processes closed" -RecoveryHint "Review LEAP install log and verify installer silent arguments."
        New-ZiaasStep -Id "final-report" -Description "Write final report and optional support bundle" -Applies $true -Kind "Internal" -Risk "None" -ExpectedOutput "Text/JSON report with next action" -Verification "Report files written" -RecoveryHint "Check log directory if report writing fails."
    )
}

function Get-ZiaasPlannedSteps {
    param(
        [Parameter(Mandatory = $true)]$Selection,
        [object]$AdobeSelection
    )

    return @(Get-ZiaasStepRegistry -Selection $Selection -AdobeSelection $AdobeSelection | Where-Object { $_.Applies -and $_.Id -ne "final-report" } | ForEach-Object { $_.Description })
}

function Write-ZiaasPreflightSummary {
    param(
        [Parameter(Mandatory = $true)]$Selection,
        [object]$AdobeSelection
    )

    if (-not $Quiet) { Write-Host "" }
    Write-ZiaasUiLine "Preflight summary" Yellow
    Write-ZiaasUiLine "-----------------" Yellow
    Write-ZiaasUiLine ("Mode:          {0}" -f $Selection.Label)
    Write-ZiaasUiLine ("Office:        {0}" -f ($(if ($Selection.InstallOffice) { "Microsoft 365 Apps for enterprise ($OfficeProductId), x64, en-GB, Semi-Annual Enterprise requested" } else { "Skipped" })))
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
    if (-not $Quiet) { Write-Host "" }
}

function Add-ZiaasPreflightResult {
    param(
        [Parameter(Mandatory = $true)][string]$Name,
        [Parameter(Mandatory = $true)][ValidateSet("Pass", "Warn", "Fail")][string]$Status,
        [Parameter(Mandatory = $true)][string]$Detail,
        [string]$RecoveryHint = ""
    )

    $Script:PreflightResults += [pscustomobject]@{
        Name = $Name
        Status = $Status
        Detail = $Detail
        RecoveryHint = $RecoveryHint
    }
}

function Get-ZiaasErrorCategory {
    param(
        [string]$Message,
        [object[]]$PreflightResults = @()
    )

    $failedPreflight = @($PreflightResults | Where-Object { $_ -and $_.Status -eq "Fail" })
    if ($failedPreflight.Count -gt 0) {
        if (@($failedPreflight | Where-Object { $_.Name -match "(?i)office update policy|managed office policy|cloud update" }).Count -gt 0) {
            return "MachineStateConflict"
        }
        return "UserCorrectable"
    }

    if ([string]::IsNullOrWhiteSpace($Message)) { return "InternalToolBug" }
    if ($Message -match "(?i)preflight failed|preflight") { return "UserCorrectable" }
    if ($Message -match "(?i)operator cancelled|blocking apps|still running|admin|elevated|installer source|silent install|LANG_LIST|disk") { return "UserCorrectable" }
    if ($Message -match "(?i)download|web request|dns|proxy|tls|url|cdn|LEAP downloads page") { return "VendorOrDownloadFailure" }
    if ($Message -match "(?i)signature|publisher|hash|manifest") { return "VerificationFailure" }
    if ($Message -match "(?i)exit code|msiexec|setup.exe|install failed|uninstall failed") { return "InstallerFailure" }
    if ($Message -match "(?i)remain installed|machine state|registry|policy") { return "MachineStateConflict" }
    return "InternalToolBug"
}

function Get-ZiaasNextAction {
    param(
        [Parameter(Mandatory = $true)][string]$Status,
        [string]$FailureMessage,
        [string]$ErrorCategory
    )

    if ($Status -eq "Success") {
        return "No further action required unless component logs indicate a vendor-requested reboot."
    }

    if ($Status -eq "RebootRequired") {
        return "Restart the device, then rerun with -ResumeLastRun. The interrupted step will be re-evaluated before any dependent install begins."
    }

    if ($Status -eq "PreflightOnly") {
        return "Review failed or warning preflight items. Run without -PreflightOnly only when the plan is acceptable."
    }

    if ([string]::IsNullOrWhiteSpace($ErrorCategory)) {
        $ErrorCategory = Get-ZiaasErrorCategory -Message $FailureMessage
    }

    switch ($ErrorCategory) {
        "UserCorrectable" { return "Correct the listed prerequisite, close blocking apps or supply the missing installer details, then rerun the same command." }
        "VendorOrDownloadFailure" { return "Check internet access, proxy/TLS inspection, vendor availability, or supply an explicit installer path/URL." }
        "VerificationFailure" { return "Do not continue until hashes, signatures, language proof, or publisher checks match the expected source." }
        "InstallerFailure" { return "Review the component log and vendor MSI/setup log, reboot if requested, then rerun or resume." }
        "MachineStateConflict" { return "Review remaining product entries or policy state in the component log before rerunning." }
        default { return "Review the orchestrator and component logs, then rerun with -CreateSupportBundle if escalation is needed." }
    }
}

function Get-ZiaasComponentHashes {
    $hashes = @()
    foreach ($fileName in $requiredComponentFiles) {
        $path = Join-Path $ComponentDirectory $fileName
        if (Test-Path -LiteralPath $path) {
            $hash = Get-FileHash -LiteralPath $path -Algorithm SHA256
            $hashes += [pscustomobject]@{
                File = $fileName
                Path = $path
                SHA256 = $hash.Hash
            }
        }
    }
    return @($hashes)
}

function Get-ZiaasInstallerSourceMetadata {
    param(
        [Parameter(Mandatory = $true)]$Selection,
        [object]$AdobeSelection
    )

    $sources = @()
    if ($Selection.InstallOffice) {
        $sources += [pscustomobject]@{ Product = "OfficeDeploymentTool"; Source = $OfficeDeploymentToolUrl; Required = $true }
        $sources += [pscustomobject]@{ Product = "OfficeScrubTool"; Source = $OfficeScrubToolUrl; Required = $true }
    }
    if ($Selection.InstallAdobe -and $AdobeSelection.Product -eq "Reader") {
        $sources += [pscustomobject]@{ Product = "AdobeReader"; Source = $AdobeReaderInstallerUrl; Required = $true }
        $sources += [pscustomobject]@{ Product = "AdobeCleaner"; Source = $AdobeCleanerToolUrl; Required = $true }
    }
    if ($Selection.InstallAdobe -and $AdobeSelection.Product -eq "AcrobatPro") {
        $source = if ($AdobeAcrobatProInstallerPath) { "<local path supplied>" } elseif ($AdobeAcrobatProInstallerUrl) { $AdobeAcrobatProInstallerUrl } else { "<missing>" }
        $sources += [pscustomobject]@{ Product = "AdobeAcrobatPro"; Source = $source; Required = $true }
    }
    if ($Selection.InstallLeap) {
        $source = if ($LeapInstallerPath) { "<local path supplied>" } elseif ($LeapInstallerUrl) { $LeapInstallerUrl } else { $LeapDownloadsPageUrl }
        $sources += [pscustomobject]@{ Product = "LEAP"; Source = $source; Required = $true }
    }
    return @($sources)
}

function Get-ZiaasMinimumFreeBytes {
    param([Parameter(Mandatory = $true)]$Selection)

    [int64]$required = 2GB
    if ($Selection.InstallOffice) { $required += 8GB }
    if ($Selection.InstallAdobe) { $required += 3GB }
    if ($Selection.InstallLeap) { $required += 3GB }
    return $required
}

function Test-ZiaasDiskSpace {
    param([int64]$MinimumFreeBytes = 5368709120)

    try {
        $resolvedRoot = if (Test-Path -LiteralPath $Script:Root) {
            (Resolve-Path -LiteralPath $Script:Root).Path
        }
        else {
            [System.IO.Path]::GetFullPath($Script:Root)
        }

        $driveRoot = [System.IO.Path]::GetPathRoot($resolvedRoot)
        $driveName = $driveRoot.TrimEnd('\').TrimEnd(':')
        $freeBytes = $null

        try {
            $driveInfo = [System.IO.DriveInfo]::new($driveRoot)
            if ($driveInfo.IsReady) {
                $freeBytes = [int64]$driveInfo.AvailableFreeSpace
            }
        }
        catch {
            $freeBytes = $null
        }

        if ($null -eq $freeBytes -or $freeBytes -le 0) {
            $drive = Get-PSDrive -Name $driveName -ErrorAction Stop
            if ($null -ne $drive.Free -and [int64]$drive.Free -gt 0) {
                $freeBytes = [int64]$drive.Free
            }
        }

        if ($null -eq $freeBytes -or $freeBytes -le 0) {
            Add-ZiaasPreflightResult -Name "Disk space" -Status "Warn" -Detail "Could not determine usable free disk space for $driveName." -RecoveryHint "Confirm the working-root drive has enough free space for installers and backups."
        }
        elseif ($freeBytes -lt $MinimumFreeBytes) {
            Add-ZiaasPreflightResult -Name "Disk space" -Status "Fail" -Detail ("{0:N1} GB free on {1}; at least {2:N1} GB recommended." -f ($freeBytes / 1GB), $driveName, ($MinimumFreeBytes / 1GB)) -RecoveryHint "Free disk space or choose a working root on a drive with more capacity."
        }
        else {
            Add-ZiaasPreflightResult -Name "Disk space" -Status "Pass" -Detail ("{0:N1} GB free on {1}." -f ($freeBytes / 1GB), $driveName)
        }
    }
    catch {
        Add-ZiaasPreflightResult -Name "Disk space" -Status "Warn" -Detail "Could not determine free disk space. $($_.Exception.Message)" -RecoveryHint "Confirm the working-root drive has enough free space for installers and backups."
    }
}

function Get-ZiaasBlockingProcessNames {
    param([Parameter(Mandatory = $true)]$Selection)

    $names = New-Object System.Collections.Generic.List[string]
    if ($Selection.InstallOffice) {
        @("winword", "excel", "powerpnt", "outlook", "onenote", "msaccess", "mspub", "visio", "winproj", "lync", "teams", "ms-teams") | ForEach-Object { $names.Add($_) }
    }
    if ($Selection.InstallAdobe) {
        @("AcroRd32", "Acrobat", "AcroCEF", "RdrCEF") | ForEach-Object { $names.Add($_) }
    }
    if ($Selection.InstallLeap) {
        Get-LeapProcessNames | ForEach-Object { $names.Add($_) }
    }
    return @($names | Select-Object -Unique)
}

function Test-ZiaasBlockingApps {
    param([Parameter(Mandatory = $true)]$Selection)

    if ($Simulation) {
        Add-ZiaasPreflightResult -Name "Blocking apps" -Status "Pass" -Detail "Simulation mode: would check Office, Adobe, and LEAP processes."
        return
    }

    $running = @()
    foreach ($name in (Get-ZiaasBlockingProcessNames -Selection $Selection)) {
        $running += @(Get-Process -Name $name -ErrorAction SilentlyContinue)
    }
    $running = @($running | Sort-Object Id -Unique)

    if ($running.Count -eq 0) {
        Add-ZiaasPreflightResult -Name "Blocking apps" -Status "Pass" -Detail "No selected-product blocking processes are running."
        return
    }

    $names = ($running | Select-Object -ExpandProperty ProcessName -Unique | Sort-Object) -join ", "
    if ($ForceCloseApps) {
        Add-ZiaasPreflightResult -Name "Blocking apps" -Status "Warn" -Detail "Blocking apps are running and will be force-closed: $names" -RecoveryHint "Confirm user work is saved before continuing."
    }
    else {
        Add-ZiaasPreflightResult -Name "Blocking apps" -Status "Fail" -Detail "Blocking apps are running: $names" -RecoveryHint "Close the listed apps and rerun, or use -ForceCloseApps only after user work is saved."
    }
}

function Test-ZiaasInstalledState {
    param([Parameter(Mandatory = $true)]$Selection)

    if ($Simulation) {
        Add-ZiaasPreflightResult -Name "Installed state" -Status "Pass" -Detail "Simulation mode: would inventory Office, Adobe, and LEAP install state."
        return
    }

    try {
        if ($Selection.InstallAdobe) {
            $adobeEntries = @(Get-AdobeReaderAndAcrobatEntries)
            Add-ZiaasPreflightResult -Name "Adobe inventory" -Status "Pass" -Detail ("Found {0} Adobe Reader/Acrobat uninstall entr{1}." -f $adobeEntries.Count, $(if ($adobeEntries.Count -eq 1) { "y" } else { "ies" }))
        }
        if ($Selection.InstallLeap) {
            $leapEntries = @(Get-LeapEntries)
            Add-ZiaasPreflightResult -Name "LEAP inventory" -Status "Pass" -Detail ("Found {0} LEAP uninstall entr{1}." -f $leapEntries.Count, $(if ($leapEntries.Count -eq 1) { "y" } else { "ies" }))
        }
        if ($Selection.InstallOffice) {
            $officeKey = "HKLM:\SOFTWARE\Microsoft\Office\ClickToRun\Configuration"
            $detail = if (Test-Path -LiteralPath $officeKey) { "Office Click-to-Run configuration key is present." } else { "Office Click-to-Run configuration key is not present." }
            Add-ZiaasPreflightResult -Name "Office inventory" -Status "Pass" -Detail $detail
        }

        if (($Selection.InstallAdobe -or $Selection.InstallLeap) -and $Script:UserHiveEnumerationIncomplete) {
            Add-ZiaasPreflightResult -Name "User uninstall inventory" -Status "Fail" -Detail "One or more local user uninstall hives could not be loaded safely, so per-user Adobe or LEAP remnants may be missed." -RecoveryHint "Log off other users, close registry/profile tools, reboot if necessary, and rerun before cleanup."
        }
    }
    catch {
        Add-ZiaasPreflightResult -Name "Installed state" -Status "Warn" -Detail "Installed product inventory was incomplete. $($_.Exception.Message)" -RecoveryHint "Continue only if the selected cleanup mode is appropriate for this machine."
    }
}

function Test-ZiaasOfficeUpdatePolicy {
    param([Parameter(Mandatory = $true)]$Selection)

    if (-not $Selection.InstallOffice) {
        return
    }

    if ($Simulation) {
        Add-ZiaasPreflightResult -Name "Office update policy" -Status "Pass" -Detail "Simulation mode: would check Cloud Update and machine Office update-channel policy precedence before cleanup."
        return
    }

    $policySources = @(
        [pscustomobject]@{
            Name = "Cloud Update"
            Path = "HKLM:\SOFTWARE\Policies\Microsoft\cloud\office\16.0\Common\officeupdate"
        },
        [pscustomobject]@{
            Name = "Machine policy"
            Path = "HKLM:\SOFTWARE\Policies\Microsoft\office\16.0\Common\officeupdate"
        }
    )

    $blockingPolicies = @()
    foreach ($source in $policySources) {
        if (-not (Test-Path -LiteralPath $source.Path)) {
            continue
        }

        $policy = Get-ItemProperty -LiteralPath $source.Path -ErrorAction SilentlyContinue
        $updatePath = [string](Get-ObjectPropertyValue -InputObject $policy -Name "UpdatePath")
        $updateBranch = [string](Get-ObjectPropertyValue -InputObject $policy -Name "UpdateBranch")

        if (-not [string]::IsNullOrWhiteSpace($updatePath)) {
            $blockingPolicies += "$($source.Name) UpdatePath='$updatePath'"
            continue
        }

        if (-not [string]::IsNullOrWhiteSpace($updateBranch) -and ($updateBranch -notmatch "(?i)SemiAnnual")) {
            $blockingPolicies += "$($source.Name) UpdateBranch='$updateBranch'"
        }
    }

    if ($blockingPolicies.Count -gt 0) {
        Add-ZiaasPreflightResult `
            -Name "Office update policy" `
            -Status "Fail" `
            -Detail ("A higher-precedence Office update policy overrides the requested Semi-Annual Enterprise channel: {0}." -f ($blockingPolicies -join "; ")) `
            -RecoveryHint "Change the client-managed Cloud Update/Intune/GPO channel to Semi-Annual Enterprise, or remove the conflicting policy through the client's approved management system, then rerun. ZiAAS will not overwrite that policy automatically."
        return
    }

    Add-ZiaasPreflightResult -Name "Office update policy" -Status "Pass" -Detail "No higher-precedence Cloud Update or machine policy conflicts with the requested Semi-Annual Enterprise channel."
}

function Invoke-ZiaasPreflightChecks {
    param(
        [Parameter(Mandatory = $true)]$Selection,
        [object]$AdobeSelection
    )

    $Script:PreflightResults = @()
    $Script:ComponentHashes = @(Get-ZiaasComponentHashes)
    $Script:InstallerSources = @(Get-ZiaasInstallerSourceMetadata -Selection $Selection -AdobeSelection $AdobeSelection)

    Add-ZiaasPreflightResult -Name "Platform" -Status "Pass" -Detail "64-bit Windows and elevation checks passed."
    if (Test-ZiaasRequiredComponentsPresent) {
        Add-ZiaasPreflightResult -Name "Components" -Status "Pass" -Detail "All required component scripts are present."
    }
    else {
        Add-ZiaasPreflightResult -Name "Components" -Status "Fail" -Detail "One or more required component scripts are missing." -RecoveryHint "Run without -NoComponentDownload or rebuild the component package."
    }

    Test-ZiaasDiskSpace -MinimumFreeBytes (Get-ZiaasMinimumFreeBytes -Selection $Selection)
    Test-ZiaasBlockingApps -Selection $Selection
    Test-ZiaasInstalledState -Selection $Selection
    Test-ZiaasOfficeUpdatePolicy -Selection $Selection

    try {
        if ($Selection.InstallOffice) {
            Assert-RemoteUrlReachable -Url $OfficeDeploymentToolUrl -Description "Microsoft Office Deployment Tool"
            Assert-RemoteUrlReachable -Url $OfficeScrubToolUrl -Description "Microsoft Office scrub tool"
            Add-ZiaasPreflightResult -Name "Office installer sources" -Status "Pass" -Detail "Microsoft ODT and scrub-tool endpoints are reachable; signed payloads will be downloaded and staged before cleanup."
        }
    }
    catch {
        Add-ZiaasPreflightResult -Name "Office installer sources" -Status "Fail" -Detail $_.Exception.Message -RecoveryHint "Check Microsoft download access, proxy/TLS inspection, DNS, and the configured Office URLs."
    }

    try {
        if ($Selection.InstallAdobe) {
            Assert-AdobeInstallerSourceAvailable -AdobeSelection $AdobeSelection
            Add-ZiaasPreflightResult -Name "Adobe installer source" -Status "Pass" -Detail "$($AdobeSelection.Label) installer preflight passed."
        }
    }
    catch {
        Add-ZiaasPreflightResult -Name "Adobe installer source" -Status "Fail" -Detail $_.Exception.Message -RecoveryHint "For Reader, check Adobe URL access. For Acrobat Pro, provide a licensed installer source, silent args, and LANG_LIST=en_GB."
    }

    try {
        if ($Selection.InstallLeap) {
            Assert-LeapInstallerSourceAvailable
            Add-ZiaasPreflightResult -Name "LEAP installer source" -Status "Pass" -Detail "LEAP installer source preflight passed."
        }
    }
    catch {
        Add-ZiaasPreflightResult -Name "LEAP installer source" -Status "Fail" -Detail $_.Exception.Message -RecoveryHint "Check the LEAP downloads page or supply -LeapInstallerPath / -LeapInstallerUrl."
    }

    $failures = @($Script:PreflightResults | Where-Object { $_.Status -eq "Fail" })
    return ($failures.Count -eq 0)
}

function Write-ZiaasPreflightResults {
    if ($Quiet) { return }

    Write-ZiaasUiLine "Preflight checks:" Yellow
    foreach ($result in @($Script:PreflightResults)) {
        $color = switch ($result.Status) {
            "Pass" { [ConsoleColor]::Green }
            "Warn" { [ConsoleColor]::Yellow }
            "Fail" { [ConsoleColor]::Red }
        }
        Write-ZiaasUiLine ("  [{0}] {1}: {2}" -f $result.Status, $result.Name, $result.Detail) $color
        if ($result.RecoveryHint) {
            Write-ZiaasUiLine ("      Next: {0}" -f $result.RecoveryHint) DarkGray
        }
    }
    Write-ZiaasUiLine ""
}

function Import-ZiaasResumeState {
    if (-not $ResumeLastRun) {
        return
    }

    $reportsDir = Join-Path $Script:Root "Reports"
    if (-not (Test-Path -LiteralPath $reportsDir)) {
        throw "-ResumeLastRun was supplied, but no previous Reports folder exists under $Script:Root."
    }

    $latestSummaryFile = Get-ChildItem -LiteralPath $reportsDir -Filter "summary-*.json" -File -ErrorAction SilentlyContinue |
        Sort-Object LastWriteTime -Descending |
        Select-Object -First 1

    if (-not $latestSummaryFile) {
        throw "-ResumeLastRun was supplied, but no previous summary JSON was found under $reportsDir."
    }

    $summary = Get-Content -LiteralPath $latestSummaryFile.FullName -Raw | ConvertFrom-Json
    if ([string]$summary.Status -eq "Success") {
        throw "-ResumeLastRun found a successful previous run. Nothing needs to be resumed."
    }

    if ([string]::IsNullOrWhiteSpace([string]$summary.ConfigPath) -or (-not (Test-Path -LiteralPath $summary.ConfigPath))) {
        throw "-ResumeLastRun could not find the previous run config referenced by $($latestSummaryFile.FullName)."
    }

    $Script:ResumeSourceSummary = $latestSummaryFile.FullName
    # A reboot-required component is not a safe resume boundary. It may have left
    # services, files, or registry state pending until Windows restarts.
    $Script:ResumeCompletedFiles = @($summary.Components | Where-Object { $_.Status -eq "Success" } | Select-Object -ExpandProperty File)

    Write-Log "Resume requested. Loading previous run config: $($summary.ConfigPath)"
    Import-ZiaasDeploymentConfig -Path $summary.ConfigPath
    Write-Log "Resume source summary: $Script:ResumeSourceSummary"
    if ($Script:ResumeCompletedFiles.Count -gt 0) {
        Write-Log "Resume will skip already completed component file(s): $($Script:ResumeCompletedFiles -join ', ')" "WARN"
    }
}

function Test-ZiaasResumeStepAlreadyComplete {
    param([Parameter(Mandatory = $true)]$Step)

    if ($Step.Id -eq "installer-staging") {
        return $false
    }

    if (-not $ResumeLastRun) {
        return $false
    }

    if ([string]::IsNullOrWhiteSpace([string]$Step.FileName)) {
        return $false
    }

    return ($Script:ResumeCompletedFiles -contains $Step.FileName)
}

function New-ZiaasMachineSummary {
    $os = Get-CimInstance Win32_OperatingSystem -ErrorAction SilentlyContinue
    [pscustomobject]@{
        ComputerName = $env:COMPUTERNAME
        User = "<redacted>"
        Is64BitOperatingSystem = [Environment]::Is64BitOperatingSystem
        PowerShellVersion = $PSVersionTable.PSVersion.ToString()
        OS = if ($os) { "$($os.Caption) $($os.Version)" } else { "Unknown" }
        WorkingRoot = ConvertTo-ZiaasSanitizedText -Text $Script:Root
        RunStamp = $Script:RunStamp
        Generated = (Get-Date).ToString("s")
    }
}

function ConvertTo-ZiaasSanitizedText {
    param([AllowEmptyString()][string]$Text)

    if ([string]::IsNullOrEmpty($Text)) { return $Text }
    $sanitized = $Text
    if (-not [string]::IsNullOrWhiteSpace($env:USERPROFILE)) {
        $sanitized = $sanitized.Replace($env:USERPROFILE, "%USERPROFILE%")
    }
    if (-not [string]::IsNullOrWhiteSpace($env:USERNAME)) {
        $userPattern = [regex]::Escape($env:USERNAME)
        $sanitized = $sanitized -replace ('(?i)\\Users\\' + $userPattern + '(?=\\|"|$)'), '\Users\<redacted>'
        $sanitized = $sanitized -replace ('(?i)(AzureAD\\|[^\s"\\]+\\)' + $userPattern + '(?=\s|"|$)'), '$1<redacted>'
    }
    $sanitized = $sanitized -replace '(?i)([?&](sig|signature|token|access_token|auth|authorization|apikey|api_key|key|code)=)[^&\s"'']+', '$1<redacted>'
    return $sanitized
}

function Copy-ZiaasSanitizedFolder {
    param(
        [Parameter(Mandatory = $true)][string]$Source,
        [Parameter(Mandatory = $true)][string]$Destination
    )

    if (-not (Test-Path -LiteralPath $Source -PathType Container)) { return }
    New-Item -Path $Destination -ItemType Directory -Force | Out-Null
    $sourcePrefix = (Resolve-Path -LiteralPath $Source).Path.TrimEnd('\')
    foreach ($file in @(Get-ChildItem -LiteralPath $Source -Recurse -File -ErrorAction SilentlyContinue)) {
        if ($file.Extension -notin @(".log", ".txt", ".json", ".xml")) { continue }
        $relative = $file.FullName.Substring($sourcePrefix.Length).TrimStart('\')
        $target = Join-Path $Destination $relative
        $targetParent = Split-Path -Parent $target
        if (-not (Test-Path -LiteralPath $targetParent)) {
            New-Item -Path $targetParent -ItemType Directory -Force | Out-Null
        }
        $content = Get-Content -LiteralPath $file.FullName -Raw -ErrorAction SilentlyContinue
        ConvertTo-ZiaasSanitizedText -Text $content | Set-Content -LiteralPath $target -Encoding UTF8
    }
}

function New-ZiaasSupportBundle {
    if (-not $CreateSupportBundle) {
        return $null
    }

    $bundleRoot = Join-Path $Script:Root "$Script:BrandSafeName-SupportBundle-$Script:RunStamp"
    $bundleZip = Join-Path $Script:Root "$Script:BrandSafeName-SupportBundle-$Script:RunStamp.zip"
    if (Test-Path -LiteralPath $bundleRoot) {
        Remove-Item -LiteralPath $bundleRoot -Recurse -Force
    }
    if (Test-Path -LiteralPath $bundleZip) {
        Remove-Item -LiteralPath $bundleZip -Force
    }

    New-Item -Path $bundleRoot -ItemType Directory -Force | Out-Null
    foreach ($folderName in @("Logs", "Reports", "RunState")) {
        $source = Join-Path $Script:Root $folderName
        Copy-ZiaasSanitizedFolder -Source $source -Destination (Join-Path $bundleRoot $folderName)
    }

    if (Test-Path -LiteralPath (Join-Path $PSScriptRoot "app.manifest.json")) {
        Copy-Item -LiteralPath (Join-Path $PSScriptRoot "app.manifest.json") -Destination (Join-Path $bundleRoot "app.manifest.json") -Force
    }
    elseif (Test-Path -LiteralPath (Join-Path (Split-Path -Parent $ComponentDirectory) "app.manifest.json")) {
        Copy-Item -LiteralPath (Join-Path (Split-Path -Parent $ComponentDirectory) "app.manifest.json") -Destination (Join-Path $bundleRoot "app.manifest.json") -Force
    }

    New-ZiaasMachineSummary | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath (Join-Path $bundleRoot "machine-summary.json") -Encoding UTF8
    ConvertTo-ZiaasSanitizedText -Text ($Script:InstallerSources | ConvertTo-Json -Depth 5) | Set-Content -LiteralPath (Join-Path $bundleRoot "installer-sources.json") -Encoding UTF8
    ConvertTo-ZiaasSanitizedText -Text ($Script:PreflightResults | ConvertTo-Json -Depth 5) | Set-Content -LiteralPath (Join-Path $bundleRoot "preflight-results.json") -Encoding UTF8
    $Script:ComponentHashes | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath (Join-Path $bundleRoot "component-hashes.json") -Encoding UTF8
    if ($Script:Brand) {
        $Script:Brand | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath (Join-Path $bundleRoot "brand-pack.json") -Encoding UTF8
    }

    $bundleItems = @(Get-ChildItem -LiteralPath $bundleRoot -Force)
    if ($bundleItems.Count -eq 0) {
        throw "Support bundle staging folder is empty: $bundleRoot"
    }

    Compress-Archive -Path (Join-Path $bundleRoot "*") -DestinationPath $bundleZip -Force
    if (-not (Test-Path -LiteralPath $bundleZip)) {
        throw "Support bundle archive was not created: $bundleZip"
    }

    Remove-Item -LiteralPath $bundleRoot -Recurse -Force -ErrorAction SilentlyContinue
    $Script:SupportBundlePath = $bundleZip
    Write-Log "Created sanitized support bundle: $bundleZip"
    return $bundleZip
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
    $errorCategory = if ($FailureMessage) {
        Get-ZiaasErrorCategory -Message $FailureMessage -PreflightResults @($Script:PreflightResults)
    }
    else { "" }
    $nextAction = Get-ZiaasNextAction -Status $Status -FailureMessage $FailureMessage -ErrorCategory $errorCategory
    $summary = [ordered]@{
        App = $Script:BrandBannerTitle
        Company = $Script:BrandCompanyName
        Suite = $Script:BrandSuiteName
        Product = $Script:BrandProductName
        BrandPackPath = $Script:BrandPackResolvedPath
        Status = $Status
        ExitCode = $ExitCode
        ErrorCategory = $errorCategory
        RebootRequired = [bool]$Script:RebootRequired
        PartialStatePossible = [bool]($Script:DestructiveWorkStarted -and $Status -notin @("Success", "PreflightOnly"))
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
        NextAction = $nextAction
        ResumeRequested = [bool]$ResumeLastRun
        ResumeSourceSummary = $Script:ResumeSourceSummary
        Preflight = @($Script:PreflightResults)
        PlannedSteps = @($Script:StepRegistry | Where-Object { $_.Applies })
        ComponentHashes = @($Script:ComponentHashes)
        InstallerSources = @($Script:InstallerSources)
        SupportBundlePath = $Script:SupportBundlePath
        Components = @($Script:ComponentResults)
    }

    $jsonPath = Join-Path $Script:ReportsDir "summary-$Script:RunStamp.json"
    $textPath = Join-Path $Script:ReportsDir "summary-$Script:RunStamp.txt"
    $summary | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $jsonPath -Encoding UTF8

    $lines = New-Object System.Collections.Generic.List[string]
    $lines.Add($Script:BrandReportTitle)
    $lines.Add(("=" * $Script:BrandReportTitle.Length))
    $lines.Add("Company: $Script:BrandCompanyName")
    $lines.Add("Suite: $Script:BrandSuiteName")
    if ($Script:BrandPackResolvedPath) { $lines.Add("Brand pack: $Script:BrandPackResolvedPath") }
    $lines.Add("Status: $Status")
    $lines.Add("Exit code: $ExitCode")
    $lines.Add("Reboot required: $($Script:RebootRequired)")
    $lines.Add("Partial state possible: $([bool]($Script:DestructiveWorkStarted -and $Status -notin @('Success', 'PreflightOnly')))")
    $lines.Add("Selection: $($Script:SelectedLabel)")
    $lines.Add("Adobe: $($Script:SelectedAdobeLabel)")
    $lines.Add("Elapsed: $($summary.Elapsed)")
    if ($FailureMessage) { $lines.Add("Failure: $FailureMessage") }
    if ($errorCategory) { $lines.Add("Category: $errorCategory") }
    $lines.Add("Next action: $nextAction")
    if ($Script:SupportBundlePath) { $lines.Add("Support bundle: $Script:SupportBundlePath") }
    $lines.Add("")
    $lines.Add("Preflight:")
    foreach ($result in @($Script:PreflightResults)) {
        $lines.Add(("  - [{0}] {1}: {2}" -f $result.Status, $result.Name, $result.Detail))
        if ($result.RecoveryHint) {
            $lines.Add(("    Next: {0}" -f $result.RecoveryHint))
        }
    }
    $lines.Add("")
    $lines.Add("Components:")
    foreach ($component in @($Script:ComponentResults)) {
        $lines.Add(("  - {0}: {1} (exit {2})" -f $component.Description, $component.Status, $component.ExitCode))
    }
    $lines.Add("")
    $lines.Add("Logs: $Script:LogDir")
    $lines.Add("JSON report: $jsonPath")
    if ($Script:BrandReportFooter) {
        $lines.Add("")
        $lines.Add($Script:BrandReportFooter)
    }
    $lines | Set-Content -LiteralPath $textPath -Encoding UTF8

    if ($CreateSupportBundle -and (-not $Script:SupportBundlePath)) {
        New-ZiaasSupportBundle | Out-Null
        $summary["SupportBundlePath"] = $Script:SupportBundlePath
        $summary | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $jsonPath -Encoding UTF8
        $lines.Insert(($lines.Count - 2), "Support bundle: $Script:SupportBundlePath")
        $lines | Set-Content -LiteralPath $textPath -Encoding UTF8
    }

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
    if ($Script:SupportBundlePath) {
        Write-ZiaasUiLine ("Support bundle:  {0}" -f $Script:SupportBundlePath)
    }
    Write-ZiaasUiLine ("Next action:     {0}" -f $nextAction)
    if (-not $Quiet) { Write-Host "" }
}

function New-ZiaasRunConfig {
    param(
        [Parameter(Mandatory = $true)]$Selection,
        [object]$AdobeSelection
    )

    $resolvedAdobeProduct = if ($AdobeSelection) { $AdobeSelection.Product } else { $AdobeProduct }

    [ordered]@{
        WorkingRoot = $WorkingRoot
        BrandPackPath = $BrandPackPath
        BrandPackResolvedPath = $Script:BrandPackResolvedPath
        Brand = [ordered]@{
            CompanyName = $Script:BrandCompanyName
            SuiteName = $Script:BrandSuiteName
            ProductName = $Script:BrandProductName
            BannerTitle = $Script:BrandBannerTitle
            ReportTitle = $Script:BrandReportTitle
        }
        DeploymentConfigPath = $DeploymentConfigPath
        InstallMode = $InstallMode
        InstallModeParameterWasUsed = $PSBoundParameters.ContainsKey("InstallMode")
        SkipOfficeParameterWasUsed = $PSBoundParameters.ContainsKey("SkipOffice")
        SkipAdobeParameterWasUsed = $PSBoundParameters.ContainsKey("SkipAdobe")
        Simulation = [bool]$Simulation
        SimulationAcrobatProEntitlementLevel = $SimulationAcrobatProEntitlementLevel
        ForceCloseApps = [bool]$ForceCloseApps
        SkipOffice = [bool]$SkipOffice
        SkipAdobe = [bool]$SkipAdobe
        DisableAdobeAutoUpdate = [bool]$DisableAdobeAutoUpdate
        KeepDownloads = [bool]$KeepDownloads
        SkipLeapProfileCleanup = [bool]$SkipLeapProfileCleanup
        Unattended = [bool]$Unattended
        PreflightOnly = [bool]$PreflightOnly
        ResumeLastRun = [bool]$ResumeLastRun
        CreateSupportBundle = [bool]$CreateSupportBundle
        NoColor = [bool]$NoColor
        Quiet = [bool]$Quiet
        LogLevel = $LogLevel
        OfficeDeploymentToolUrl = $OfficeDeploymentToolUrl
        OfficeScrubToolUrl = $OfficeScrubToolUrl
        OfficeProductId = $OfficeProductId
        AdobeProduct = $resolvedAdobeProduct
        AdobeReaderInstallerUrl = $AdobeReaderInstallerUrl
        AdobeAcrobatProInstallerPath = $AdobeAcrobatProInstallerPath
        AdobeAcrobatProInstallerUrl = $AdobeAcrobatProInstallerUrl
        AdobeAcrobatProInstallArguments = @($AdobeAcrobatProInstallArguments)
        AdobeAcrobatProInstallArgumentLine = $AdobeAcrobatProInstallArgumentLine
        AllowAcrobatProInstallerWithoutArguments = [bool]$AllowAcrobatProInstallerWithoutArguments
        AllowAcrobatProLanguageNotVerified = [bool]$AllowAcrobatProLanguageNotVerified
        AllowAcrobatProEntitlementNotVerified = [bool]$AllowAcrobatProEntitlementNotVerified
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
        UseCachedInstallers = [bool]$UseCachedInstallers
        ManifestUrl = $ManifestUrl
        ExpectedManifestHash = $ExpectedManifestHash
        ExpectedComponentPackageHash = $ExpectedComponentPackageHash
        DownloadRetryCount = $DownloadRetryCount
        DownloadRetryDelaySeconds = $DownloadRetryDelaySeconds
        RunStamp = $Script:RunStamp
        InstallOffice = [bool]$Selection.InstallOffice
        InstallAdobe = [bool]$Selection.InstallAdobe
        InstallLeap = [bool]$Selection.InstallLeap
        SelectionLabel = $Selection.Label
    }
}

function Get-ZiaasPowerShellHost {
    if ([Environment]::Is64BitOperatingSystem -and (-not [Environment]::Is64BitProcess)) {
        $sysnativeHost = Join-Path $env:SystemRoot "Sysnative\WindowsPowerShell\v1.0\powershell.exe"
        if (Test-Path -LiteralPath $sysnativeHost -PathType Leaf) {
            return $sysnativeHost
        }
    }

    $systemHost = Join-Path $env:SystemRoot "System32\WindowsPowerShell\v1.0\powershell.exe"
    if (Test-Path -LiteralPath $systemHost -PathType Leaf) {
        return $systemHost
    }

    return "powershell.exe"
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
    $powerShellHost = Get-ZiaasPowerShellHost
    & $powerShellHost -NoProfile -ExecutionPolicy Bypass -File $componentPath -ConfigPath $ConfigPath
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
        Write-Log "Component requested a reboot; stopping before the next deployment step. Restart the device and use -ResumeLastRun." "WARN"
        $Script:ComponentResults += [pscustomobject]@{
            File = $FileName
            Description = $Description
            Status = "RebootRequired"
            ExitCode = $exitCode
            LogFile = $componentLogPath
        }
        $rebootException = New-Object System.Exception("Component requested a reboot before the next deployment step: $Description")
        $rebootException.Data["ZiaasExitCode"] = 3010
        throw $rebootException
    }

    $Script:ComponentResults += [pscustomobject]@{
        File = $FileName
        Description = $Description
        Status = "Failed"
        ExitCode = $exitCode
        LogFile = $componentLogPath
    }

    $componentException = New-Object System.Exception("Component failed with exit code ${exitCode}: $Description")
    $componentException.Data["ZiaasExitCode"] = [int]$exitCode
    throw $componentException
}

function Add-ZiaasSkippedComponentResult {
    param(
        [Parameter(Mandatory = $true)]$Step,
        [Parameter(Mandatory = $true)][string]$Reason
    )

    $Script:ComponentResults += [pscustomobject]@{
        File = $Step.FileName
        Description = $Step.Description
        Status = "Skipped"
        ExitCode = 0
        LogFile = ""
        Reason = $Reason
    }
}

function Invoke-ZiaasRegisteredStep {
    param(
        [Parameter(Mandatory = $true)]$Step,
        [Parameter(Mandatory = $true)][string]$ConfigPath,
        [Parameter(Mandatory = $true)][int]$Index,
        [Parameter(Mandatory = $true)][int]$Total
    )

    if (-not $Step.Applies) {
        Write-Log "Skipping step '$($Step.Description)' because it does not apply to selected deployment mode." "DEBUG"
        return
    }

    if ($Step.Id -in @("preflight", "final-report")) {
        return
    }

    Write-ZiaasUiLine ("Step {0}/{1}: {2}" -f $Index, $Total, $Step.Description) Cyan
    Write-Log "Step $Index/$Total started: $($Step.Description). Risk=$($Step.Risk). Expected=$($Step.ExpectedOutput)"

    if ($Step.Risk -in @("Destructive", "Install")) {
        $Script:DestructiveWorkStarted = $true
    }

    if (Test-ZiaasResumeStepAlreadyComplete -Step $Step) {
        Write-Log "Resume mode: skipping already completed component step: $($Step.FileName)" "WARN"
        Add-ZiaasSkippedComponentResult -Step $Step -Reason "Completed in previous run: $Script:ResumeSourceSummary"
        return
    }

    switch ($Step.Kind) {
        "Pause" {
            if ($Step.Id -eq "post-cleanup-wait") {
                Invoke-DeploymentPause -Seconds $PostCleanupWaitSeconds -Reason "post-cleanup settling before fresh installs"
            }
            elseif ($Step.Id -eq "pre-leap-wait") {
                Invoke-DeploymentPause -Seconds $PreLeapWaitSeconds -Reason "Office/Adobe installation completion before LEAP add-in install"
            }
            return
        }
        "Component" {
            Invoke-ZiaasComponentScript -FileName $Step.FileName -Description $Step.Description -ConfigPath $ConfigPath
            return
        }
        default {
            Write-Log "Internal step '$($Step.Id)' has no executable action." "DEBUG"
        }
    }
}

try {
    Assert-ZiaasWorkingRoot
    Enter-ZiaasRunMutex
    Initialize-DeploymentFolders
    Write-ZiaasBanner
    Write-Log "$Script:BrandBannerTitle orchestration started."
    Write-Log "Log file: $Script:LogFile"
    Write-Log "Working root: $Script:Root"
    Write-Log "Component directory: $ComponentDirectory"
    Assert-AdminAndPlatform
    Import-ZiaasResumeState

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
    }
    else {
        $Script:SelectedAdobeLabel = "Skipped"
    }

    $Script:StepRegistry = @(Get-ZiaasStepRegistry -Selection $selection -AdobeSelection $adobeSelection)

    $runStateDir = Join-Path $Script:Root "RunState"
    if (-not (Test-Path -LiteralPath $runStateDir)) {
        New-Item -Path $runStateDir -ItemType Directory -Force | Out-Null
    }

    $configPath = Join-Path $runStateDir "ZiAAS-Woodstock-Baselining-$Script:RunStamp.json"
    $config = New-ZiaasRunConfig -Selection $selection -AdobeSelection $adobeSelection
    $config | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $configPath -Encoding UTF8
    $Script:ConfigPath = $configPath
    Write-Log "Wrote run configuration: $configPath"

    $preflightPassed = Invoke-ZiaasPreflightChecks -Selection $selection -AdobeSelection $adobeSelection

    Write-ZiaasPreflightSummary -Selection $selection -AdobeSelection $adobeSelection
    Write-ZiaasPreflightResults

    if (-not $preflightPassed) {
        throw "Preflight failed. Resolve failed preflight items before cleanup or installation begins."
    }

    if ($PreflightOnly) {
        Write-Log "Preflight-only mode completed. No cleanup or installation steps were run." "SUCCESS"
        Write-ZiaasSummaryReport -Status "PreflightOnly" -ExitCode 0
        exit 0
    }

    Confirm-ZiaasInteractiveRun -Selection $selection

    $stepsToRun = @($Script:StepRegistry | Where-Object { $_.Applies -and $_.Id -notin @("preflight", "final-report") })
    $stepIndex = 1
    foreach ($step in $stepsToRun) {
        Invoke-ZiaasRegisteredStep -Step $step -ConfigPath $configPath -Index $stepIndex -Total $stepsToRun.Count
        $stepIndex++
    }

    Remove-WorkingDownloadsIfRequested

    $elapsed = New-TimeSpan -Start $Script:StartTime -End (Get-Date)
    Write-Log ("{0} orchestration completed in {1:g}." -f $Script:BrandBannerTitle, $elapsed) "SUCCESS"
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
    $exitCode = 1
    if ($failureMessage -like "Operator cancelled*") {
        $exitCode = 20
    }
    elseif ($_.Exception.Data -and $_.Exception.Data.Contains("ZiaasExitCode")) {
        $exitCode = [int]$_.Exception.Data["ZiaasExitCode"]
    }
    try {
        Write-Log $failureMessage "ERROR"
        Write-Log "$Script:BrandBannerTitle orchestration failed. See component logs in $Script:LogDir." "ERROR"
        $failureStatus = if ($exitCode -eq 3010) { "RebootRequired" } else { "Failed" }
        Write-ZiaasSummaryReport -Status $failureStatus -ExitCode $exitCode -FailureMessage $failureMessage
    }
    catch {
        Write-Host "$Script:BrandBannerTitle orchestration failed before logging was available. $failureMessage"
    }
    exit $exitCode
}
finally {
    Exit-ZiaasRunMutex
}
