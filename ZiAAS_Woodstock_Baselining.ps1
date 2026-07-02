#requires -version 5.1
<#
Deploys Microsoft 365 Apps for enterprise, Adobe Acrobat Reader/Acrobat Pro, and LEAP on Windows.

Defaults:
  - Prompts for Office, Adobe, LEAP, or useful combinations of them
  - When LEAP is selected, removes LEAP first and installs LEAP last so add-ins bind
    to the freshly installed Office and Adobe applications
  - Microsoft 365 Apps for enterprise, 64-bit, en-GB, Semi-Annual Enterprise Channel
  - Removes existing Office Click-to-Run products via ODT Remove All
  - Scrubs Office remnants via Microsoft's OfficeScrubScenario command-line Get Help tool
  - Keeps RemoveMSI in the Office install XML as a belt-and-braces MSI cleanup guard
  - When Adobe is selected, prompts for Acrobat Reader or Acrobat Pro
  - Adobe Acrobat Reader 64-bit MUI by default
  - Acrobat Pro requires a supplied licensed installer/package path or URL and silent
    arguments unless explicitly allowed
  - Removes existing Adobe Reader/Acrobat MSI products first
  - Cleans Adobe remnants via Adobe AcroCleaner after standard uninstall
  - Disables Adobe's modern "New Acrobat" UI by policy
  - Removes existing LEAP installs via MSI product code or registered quiet uninstall command
  - Moves known LEAP residual folders to timestamped backup storage
  - Preserves AppData\Roaming\LEAP Accounting because it may contain incomplete timesheet data
  - Resolves the latest LEAP Desktop installer from the official LEAP downloads page
  - Can optionally fall back to a local trusted LEAP installer from common installer folders

Run from an elevated PowerShell session:
  powershell.exe -ExecutionPolicy Bypass -File .\ZiAAS_Woodstock_Baselining.ps1

For unattended use:
  powershell.exe -ExecutionPolicy Bypass -File .\ZiAAS_Woodstock_Baselining.ps1 -InstallMode All -AdobeProduct Reader

For sandbox testing without touching installed software:
  powershell.exe -ExecutionPolicy Bypass -File .\ZiAAS_Woodstock_Baselining.ps1 -Simulation -InstallMode All -WorkingRoot .\sandbox-test

Use -ForceCloseApps only if the user has saved their work.
#>

[CmdletBinding()]
param(
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

    [string]$OfficeDeploymentToolUrl = "https://download.microsoft.com/download/6c1eeb25-cf8b-41d9-8d0d-cc1dbc032140/officedeploymenttool_20026-20112.exe",

    [string]$OfficeScrubToolUrl = "https://aka.ms/SaRA_EnterpriseVersionFiles",

    [ValidateSet("Prompt", "Reader", "AcrobatPro")]
    [string]$AdobeProduct = "Prompt",

    [string]$AdobeReaderInstallerUrl = "https://ardownload2.adobe.com/pub/adobe/acrobat/win/AcrobatDC/2600121691/AcroRdrDCx642600121691_MUI.exe",

    [string]$AdobeAcrobatProInstallerPath,

    [string]$AdobeAcrobatProInstallerUrl,

    [string[]]$AdobeAcrobatProInstallArguments = @(),

    [switch]$AllowAcrobatProInstallerWithoutArguments,

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

    [int]$PreLeapWaitSeconds = 60
)

Set-StrictMode -Version 2.0
$ErrorActionPreference = "Stop"

$Script:InstallModeParameterWasUsed = $PSBoundParameters.ContainsKey("InstallMode")
$Script:SkipOfficeParameterWasUsed = $PSBoundParameters.ContainsKey("SkipOffice")
$Script:SkipAdobeParameterWasUsed = $PSBoundParameters.ContainsKey("SkipAdobe")

$Script:StartTime = Get-Date
$Script:Root = $WorkingRoot
$Script:DownloadDir = Join-Path $Script:Root "Downloads"
$Script:OfficeDir = Join-Path $Script:Root "OfficeODT"
$Script:LogDir = Join-Path $Script:Root "Logs"
$Script:BackupDir = Join-Path $Script:Root "Backups"
$Script:RunStamp = Get-Date -Format "yyyyMMdd-HHmmss"
$Script:LogFile = Join-Path $Script:LogDir "ZiAAS_Woodstock_Baselining-$Script:RunStamp.log"
$Script:RebootRequired = $false
$Script:SimulationAdobeProductsRemoved = $false
$Script:SimulationLeapProductsRemoved = $false
$Script:SimulationLeapInstalled = $false
$Script:AutoDiscoveredLeapInstallerPath = $null
$Script:ResolvedLeapInstallerUrl = $null
$Script:ResolvedLeapInstallerVersion = $null
$Script:ResolvedLeapInstallerFileName = $null
$Script:LeapResidualMoved = 0
$Script:LeapResidualRenamed = 0
$Script:LeapResidualSkipped = 0
$Script:LeapResidualPreserved = 0
$Script:LeapResidualErrors = 0

function Initialize-DeploymentFolders {
    foreach ($path in @($Script:Root, $Script:DownloadDir, $Script:OfficeDir, $Script:LogDir, $Script:BackupDir)) {
        if (-not (Test-Path -LiteralPath $path)) {
            New-Item -Path $path -ItemType Directory -Force | Out-Null
        }
    }
}

function Write-Log {
    param(
        [Parameter(Mandatory = $true)][string]$Message,
        [ValidateSet("INFO", "WARN", "ERROR", "SUCCESS")][string]$Level = "INFO"
    )

    $line = "{0} [{1}] {2}" -f (Get-Date -Format "yyyy-MM-dd HH:mm:ss"), $Level, $Message
    Write-Host $line
    Add-Content -LiteralPath $Script:LogFile -Value $line
}

function ConvertTo-SafeFileName {
    param([Parameter(Mandatory = $true)][string]$Name)

    if ([string]::IsNullOrWhiteSpace($Name)) {
        return "Unnamed"
    }

    $safeName = $Name
    foreach ($character in [System.IO.Path]::GetInvalidFileNameChars()) {
        $safeName = $safeName.Replace([string]$character, "_")
    }

    return $safeName
}

function Get-UniquePath {
    param([Parameter(Mandatory = $true)][string]$Path)

    if (-not (Test-Path -LiteralPath $Path)) {
        return $Path
    }

    $parent = Split-Path -Parent $Path
    $leaf = Split-Path -Leaf $Path
    $suffix = [guid]::NewGuid().ToString("N").Substring(0, 8)
    return (Join-Path $parent "$leaf-$suffix")
}

function Assert-AdminAndPlatform {
    if ($Simulation) {
        Write-Log "SIMULATION: Skipping administrator check and machine changes."
        if (-not [Environment]::Is64BitOperatingSystem) {
            throw "This deployment requires a 64-bit Windows operating system."
        }
        [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
        return
    }

    $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = New-Object Security.Principal.WindowsPrincipal($identity)

    if (-not $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
        throw "Run this script from an elevated PowerShell session."
    }

    if (-not [Environment]::Is64BitOperatingSystem) {
        throw "This deployment requires a 64-bit Windows operating system."
    }

    [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
}

function New-InstallSelection {
    param(
        [Parameter(Mandatory = $true)][bool]$InstallOffice,
        [Parameter(Mandatory = $true)][bool]$InstallAdobe,
        [Parameter(Mandatory = $true)][bool]$InstallLeap,
        [Parameter(Mandatory = $true)][string]$Label
    )

    return [pscustomobject]@{
        InstallOffice = $InstallOffice
        InstallAdobe = $InstallAdobe
        InstallLeap = $InstallLeap
        Label = $Label
    }
}

function Resolve-InstallSelection {
    if (($Script:SkipOfficeParameterWasUsed -or $Script:SkipAdobeParameterWasUsed) -and $Script:InstallModeParameterWasUsed) {
        throw "Use either -InstallMode or the legacy -SkipOffice/-SkipAdobe switches, not both."
    }

    if ($Script:SkipOfficeParameterWasUsed -or $Script:SkipAdobeParameterWasUsed) {
        if ($SkipOffice -and $SkipAdobe) {
            throw "Both -SkipOffice and -SkipAdobe were supplied, leaving nothing to install."
        }

        if ($SkipOffice) {
            return New-InstallSelection -InstallOffice $false -InstallAdobe $true -InstallLeap $false -Label "Adobe only"
        }

        if ($SkipAdobe) {
            return New-InstallSelection -InstallOffice $true -InstallAdobe $false -InstallLeap $false -Label "Office only"
        }
    }

    switch ($InstallMode) {
        "Office" {
            return New-InstallSelection -InstallOffice $true -InstallAdobe $false -InstallLeap $false -Label "Office only"
        }
        "OfficeAndAdobe" {
            return New-InstallSelection -InstallOffice $true -InstallAdobe $true -InstallLeap $false -Label "Office + Adobe"
        }
        "OfficeAndAdobeReader" {
            return New-InstallSelection -InstallOffice $true -InstallAdobe $true -InstallLeap $false -Label "Office + Adobe"
        }
        "Adobe" {
            return New-InstallSelection -InstallOffice $false -InstallAdobe $true -InstallLeap $false -Label "Adobe only"
        }
        "AdobeReader" {
            return New-InstallSelection -InstallOffice $false -InstallAdobe $true -InstallLeap $false -Label "Adobe only"
        }
        "Leap" {
            return New-InstallSelection -InstallOffice $false -InstallAdobe $false -InstallLeap $true -Label "LEAP only"
        }
        "OfficeAndLeap" {
            return New-InstallSelection -InstallOffice $true -InstallAdobe $false -InstallLeap $true -Label "Office + LEAP"
        }
        "AdobeAndLeap" {
            return New-InstallSelection -InstallOffice $false -InstallAdobe $true -InstallLeap $true -Label "Adobe + LEAP"
        }
        "AdobeReaderAndLeap" {
            return New-InstallSelection -InstallOffice $false -InstallAdobe $true -InstallLeap $true -Label "Adobe + LEAP"
        }
        "OfficeAndAdobeAndLeap" {
            return New-InstallSelection -InstallOffice $true -InstallAdobe $true -InstallLeap $true -Label "Office + Adobe + LEAP"
        }
        "OfficeAndAdobeReaderAndLeap" {
            return New-InstallSelection -InstallOffice $true -InstallAdobe $true -InstallLeap $true -Label "Office + Adobe + LEAP"
        }
        "All" {
            return New-InstallSelection -InstallOffice $true -InstallAdobe $true -InstallLeap $true -Label "Office + Adobe + LEAP"
        }
        "Prompt" {
            Write-Host ""
            Write-Host "Choose what to install:"
            Write-Host "  1. Office only"
            Write-Host "  2. Office + Adobe"
            Write-Host "  3. Adobe only"
            Write-Host "  4. LEAP only"
            Write-Host "  5. Office + LEAP"
            Write-Host "  6. Adobe + LEAP"
            Write-Host "  7. Office + Adobe + LEAP"
            Write-Host ""

            do {
                $choice = Read-Host "Enter 1 to 7"
            } until ($choice -in @("1", "2", "3", "4", "5", "6", "7"))

            switch ($choice) {
                "1" { return New-InstallSelection -InstallOffice $true -InstallAdobe $false -InstallLeap $false -Label "Office only" }
                "2" { return New-InstallSelection -InstallOffice $true -InstallAdobe $true -InstallLeap $false -Label "Office + Adobe" }
                "3" { return New-InstallSelection -InstallOffice $false -InstallAdobe $true -InstallLeap $false -Label "Adobe only" }
                "4" { return New-InstallSelection -InstallOffice $false -InstallAdobe $false -InstallLeap $true -Label "LEAP only" }
                "5" { return New-InstallSelection -InstallOffice $true -InstallAdobe $false -InstallLeap $true -Label "Office + LEAP" }
                "6" { return New-InstallSelection -InstallOffice $false -InstallAdobe $true -InstallLeap $true -Label "Adobe + LEAP" }
                "7" { return New-InstallSelection -InstallOffice $true -InstallAdobe $true -InstallLeap $true -Label "Office + Adobe + LEAP" }
            }
        }
    }

    throw "Unknown install mode: $InstallMode"
}

function Resolve-AdobeProductSelection {
    param([Parameter(Mandatory = $true)][bool]$InstallAdobe)

    if (-not $InstallAdobe) {
        return $null
    }

    switch ($AdobeProduct) {
        "Reader" {
            return [pscustomobject]@{
                Product = "Reader"
                Label = "Adobe Acrobat Reader"
            }
        }
        "AcrobatPro" {
            return [pscustomobject]@{
                Product = "AcrobatPro"
                Label = "Adobe Acrobat Pro"
            }
        }
        "Prompt" {
            Write-Host ""
            Write-Host "Choose Adobe product:"
            Write-Host "  1. Adobe Acrobat Reader"
            Write-Host "  2. Adobe Acrobat Pro"
            Write-Host ""

            do {
                $choice = Read-Host "Enter 1 or 2"
            } until ($choice -in @("1", "2"))

            switch ($choice) {
                "1" {
                    return [pscustomobject]@{
                        Product = "Reader"
                        Label = "Adobe Acrobat Reader"
                    }
                }
                "2" {
                    return [pscustomobject]@{
                        Product = "AcrobatPro"
                        Label = "Adobe Acrobat Pro"
                    }
                }
            }
        }
    }

    throw "Unknown Adobe product: $AdobeProduct"
}

function Get-ObjectPropertyValue {
    param(
        [Parameter(Mandatory = $true)]$InputObject,
        [Parameter(Mandatory = $true)][string]$Name
    )

    $property = $InputObject.PSObject.Properties[$Name]
    if ($null -eq $property) {
        return $null
    }

    return $property.Value
}

function Escape-XmlAttribute {
    param([Parameter(Mandatory = $true)][string]$Value)

    return [System.Security.SecurityElement]::Escape($Value)
}

function Invoke-ProcessChecked {
    param(
        [Parameter(Mandatory = $true)][string]$FilePath,
        [Parameter(Mandatory = $true)]
        [AllowEmptyCollection()]
        [string[]]$ArgumentList,
        [int[]]$SuccessExitCodes = @(0, 3010),
        [string]$Description = $FilePath,
        [string]$WorkingDirectory
    )

    $displayArgs = $ArgumentList -join " "
    Write-Log "$Description started."
    Write-Log "Command: `"$FilePath`" $displayArgs"

    if ($Simulation) {
        Write-Log "SIMULATION: Would run process and treat exit code as 0."
        Write-Log "$Description finished with exit code 0."
        return
    }

    $startInfo = @{
        FilePath = $FilePath
        Wait = $true
        PassThru = $true
        WindowStyle = "Hidden"
    }
    if ($ArgumentList.Count -gt 0) {
        $startInfo.ArgumentList = $ArgumentList
    }
    if ($WorkingDirectory) {
        $startInfo.WorkingDirectory = $WorkingDirectory
    }

    $process = Start-Process @startInfo
    $exitCode = $process.ExitCode
    Write-Log "$Description finished with exit code $exitCode."

    if ($exitCode -eq 3010) {
        $Script:RebootRequired = $true
        Write-Log "$Description requested a reboot." "WARN"
    }

    if ($SuccessExitCodes -notcontains $exitCode) {
        throw "$Description failed with exit code $exitCode. See $Script:LogFile."
    }
}

function Split-CommandLine {
    param([Parameter(Mandatory = $true)][string]$CommandLine)

    $trimmed = $CommandLine.Trim()
    if ([string]::IsNullOrWhiteSpace($trimmed)) {
        throw "Command line is empty."
    }

    if ($trimmed -match '^"([^"]+)"\s*(.*)$') {
        return [pscustomobject]@{
            FilePath = $matches[1]
            Arguments = if ($matches[2]) { @($matches[2]) } else { @() }
        }
    }

    if ($trimmed -match '^(\S+)\s*(.*)$') {
        return [pscustomobject]@{
            FilePath = $matches[1]
            Arguments = if ($matches[2]) { @($matches[2]) } else { @() }
        }
    }

    throw "Could not parse command line: $CommandLine"
}

function Save-Download {
    param(
        [Parameter(Mandatory = $true)][string]$Url,
        [Parameter(Mandatory = $true)][string]$Destination,
        [int64]$MinimumBytes = 1024,
        [switch]$AlwaysDownload
    )

    if ((-not $AlwaysDownload) -and (Test-Path -LiteralPath $Destination) -and ((Get-Item -LiteralPath $Destination).Length -ge $MinimumBytes)) {
        Write-Log "Using existing download: $Destination"
        return
    }

    if ($AlwaysDownload -and (Test-Path -LiteralPath $Destination)) {
        Write-Log "Refreshing existing download: $Destination"
    }

    if ($Simulation) {
        $simulationContent = "SIMULATION ONLY - would download $Url"
        Set-Content -LiteralPath $Destination -Value $simulationContent -Encoding ASCII
        Write-Log "SIMULATION: Would download $Url to $Destination"
        return
    }

    $tmp = "$Destination.tmp"
    if (Test-Path -LiteralPath $tmp) {
        Remove-Item -LiteralPath $tmp -Force
    }

    Write-Log "Downloading $Url"
    try {
        Start-BitsTransfer -Source $Url -Destination $tmp -ErrorAction Stop
    }
    catch {
        Write-Log "BITS download failed, falling back to direct web download. $($_.Exception.Message)" "WARN"
        Invoke-WebRequest -Uri $Url -OutFile $tmp -UseBasicParsing
    }

    $downloaded = Get-Item -LiteralPath $tmp
    if ($downloaded.Length -lt $MinimumBytes) {
        throw "Downloaded file is unexpectedly small: $tmp"
    }

    Move-Item -LiteralPath $tmp -Destination $Destination -Force
    Write-Log "Downloaded to $Destination ($($downloaded.Length) bytes)."
}

function Assert-TrustedSignature {
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [Parameter(Mandatory = $true)][string[]]$ExpectedPublisherFragments
    )

    if ($Simulation) {
        $publisher = $ExpectedPublisherFragments -join " or "
        Write-Log "SIMULATION: Would verify trusted signature for $Path from $publisher."
        return
    }

    $signature = Get-AuthenticodeSignature -LiteralPath $Path
    if ($signature.Status -ne "Valid") {
        throw "Signature check failed for $Path. Status: $($signature.Status)"
    }

    $subject = $signature.SignerCertificate.Subject
    $isExpectedPublisher = $false
    foreach ($fragment in $ExpectedPublisherFragments) {
        if ($subject -like "*$fragment*") {
            $isExpectedPublisher = $true
            break
        }
    }

    if (-not $isExpectedPublisher) {
        throw "Unexpected publisher for $Path. Signer: $subject"
    }

    Write-Log "Signature OK: $Path signed by $subject"
}

function Test-TrustedSignature {
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [Parameter(Mandatory = $true)][string[]]$ExpectedPublisherFragments
    )

    if (-not (Test-Path -LiteralPath $Path)) {
        return $false
    }

    try {
        $signature = Get-AuthenticodeSignature -LiteralPath $Path
        if ($signature.Status -ne "Valid") {
            return $false
        }

        $subject = $signature.SignerCertificate.Subject
        foreach ($fragment in $ExpectedPublisherFragments) {
            if ($subject -like "*$fragment*") {
                return $true
            }
        }
    }
    catch {
        return $false
    }

    return $false
}

function Resolve-AbsoluteUrl {
    param(
        [Parameter(Mandatory = $true)][string]$BaseUrl,
        [Parameter(Mandatory = $true)][string]$Url
    )

    if ([System.Uri]::IsWellFormedUriString($Url, [System.UriKind]::Absolute)) {
        return $Url
    }

    $baseUri = New-Object System.Uri -ArgumentList $BaseUrl
    $resolvedUri = New-Object System.Uri -ArgumentList $baseUri, $Url
    return $resolvedUri.AbsoluteUri
}

function New-QueryString {
    param([Parameter(Mandatory = $true)][hashtable]$Parameters)

    $parts = @()
    foreach ($key in $Parameters.Keys) {
        $parts += ([System.Uri]::EscapeDataString([string]$key) + "=" + [System.Uri]::EscapeDataString([string]$Parameters[$key]))
    }

    return ($parts -join "&")
}

function ConvertTo-SafeFileName {
    param(
        [Parameter(Mandatory = $true)]
        [Alias("Name")]
        [string]$FileName
    )

    if ([string]::IsNullOrWhiteSpace($FileName)) {
        return "Unnamed"
    }

    $invalidCharacters = [System.IO.Path]::GetInvalidFileNameChars()
    $safe = $FileName
    foreach ($character in $invalidCharacters) {
        $safe = $safe.Replace([string]$character, "_")
    }

    return $safe
}

function Get-RemoteFileNameFromContentDisposition {
    param([object]$ContentDisposition)

    $value = @($ContentDisposition | Select-Object -First 1)
    if ([string]::IsNullOrWhiteSpace($value)) {
        return $null
    }

    if ($value -match "filename\*=utf-8''(?<name>[^;]+)") {
        return (ConvertTo-SafeFileName -FileName ([System.Uri]::UnescapeDataString($matches["name"])))
    }

    if ($value -match 'filename="(?<name>[^"]+)"') {
        return (ConvertTo-SafeFileName -FileName $matches["name"])
    }

    if ($value -match 'filename=(?<name>[^;]+)') {
        return (ConvertTo-SafeFileName -FileName $matches["name"].Trim())
    }

    return $null
}

function Get-RemoteFileNameFromUrl {
    param(
        [Parameter(Mandatory = $true)][string]$Url,
        [Parameter(Mandatory = $true)][string]$FallbackFileName
    )

    try {
        $response = Invoke-WebRequest -Uri $Url -Method Head -MaximumRedirection 10 -UseBasicParsing -TimeoutSec 60
        $contentDisposition = $null
        try {
            if ($response.Headers) {
                if ($response.Headers -is [System.Collections.IDictionary]) {
                    if ($response.Headers.Contains("Content-Disposition")) {
                        $contentDisposition = $response.Headers["Content-Disposition"]
                    }
                    elseif ($response.Headers.Contains("content-disposition")) {
                        $contentDisposition = $response.Headers["content-disposition"]
                    }
                }
                elseif ($response.Headers.PSObject.Methods["Get"]) {
                    $contentDisposition = $response.Headers.Get("Content-Disposition")
                }
            }
        }
        catch {
            $contentDisposition = $null
        }

        try {
            if ((-not $contentDisposition) -and $response.BaseResponse -and $response.BaseResponse.Headers -and $response.BaseResponse.Headers.PSObject.Methods["Get"]) {
                $contentDisposition = $response.BaseResponse.Headers.Get("Content-Disposition")
            }
        }
        catch {
            $contentDisposition = $null
        }

        $fileName = Get-RemoteFileNameFromContentDisposition -ContentDisposition $contentDisposition
        if (-not [string]::IsNullOrWhiteSpace($fileName)) {
            return $fileName
        }
    }
    catch {
        Write-Log "Could not read remote filename from download headers. $($_.Exception.Message)" "WARN"
    }

    return $FallbackFileName
}

function Get-LeapInstallerLinkFromContent {
    param([Parameter(Mandatory = $true)][string]$Content)

    $normalized = $Content -replace '\\/', '/'
    $normalized = $normalized -replace '\\u0026', '&'
    $normalized = [System.Net.WebUtility]::HtmlDecode($normalized)

    $version = $null
    $versionMatch = [regex]::Match($normalized, 'Latest Version:\s*(?<version>[0-9][^<"\\\r\n]*)', [System.Text.RegularExpressions.RegexOptions]::IgnoreCase)
    if ($versionMatch.Success) {
        $version = $versionMatch.Groups["version"].Value.Trim()
    }

    $labelledMatch = [regex]::Match(
        $normalized,
        '(?is)"label"\s*:\s*\{[^}]*"value"\s*:\s*"Download\s+LEAP\s+Desktop".*?"url"\s*:\s*\{[^}]*"value"\s*:\s*"(?<url>https://leaphome\.sharepoint\.com[^"]+)"'
    )
    if ($labelledMatch.Success) {
        return [pscustomobject]@{
            Url = $labelledMatch.Groups["url"].Value
            Version = $version
        }
    }

    $anchorMatch = [regex]::Match(
        $normalized,
        '(?is)<a[^>]+href="(?<url>https://leaphome\.sharepoint\.com[^"]+)"[^>]*>\s*Download\s+LEAP\s+Desktop\s*</a>'
    )
    if ($anchorMatch.Success) {
        return [pscustomobject]@{
            Url = $anchorMatch.Groups["url"].Value
            Version = $version
        }
    }

    $urlMatches = [regex]::Matches($normalized, 'https://leaphome\.sharepoint\.com[^"''<>\s\\]+')
    foreach ($match in $urlMatches) {
        $start = [Math]::Max(0, $match.Index - 800)
        $length = [Math]::Min(1600, $normalized.Length - $start)
        $nearbyText = $normalized.Substring($start, $length)
        if (($nearbyText -match '(?i)Download\s+LEAP\s+Desktop|LEAPDesktopX64setup|LEAP\s+Desktop') -and ($nearbyText -notmatch '(?i)System\s+Audit')) {
            return [pscustomobject]@{
                Url = $match.Value
                Version = $version
            }
        }
    }

    return $null
}

function Resolve-LeapInstallerFromWebsite {
    if ($Script:ResolvedLeapInstallerUrl) {
        return [pscustomobject]@{
            Url = $Script:ResolvedLeapInstallerUrl
            Version = $Script:ResolvedLeapInstallerVersion
            FileName = $Script:ResolvedLeapInstallerFileName
        }
    }

    Write-Log "Resolving latest LEAP Desktop installer from $LeapDownloadsPageUrl"
    $pageResponse = Invoke-WebRequest -Uri $LeapDownloadsPageUrl -UseBasicParsing -TimeoutSec 60
    $pageContent = $pageResponse.Content

    $directInfo = Get-LeapInstallerLinkFromContent -Content $pageContent
    if ($directInfo) {
        $fallbackFileName = "LEAPDesktopX64setup.exe"
        if ($directInfo.Version -match '^(?<version>[0-9.]+)') {
            $fallbackFileName = "$($matches["version"])_LEAPDesktopX64setup.exe"
        }

        $fileName = Get-RemoteFileNameFromUrl -Url $directInfo.Url -FallbackFileName $fallbackFileName
        $Script:ResolvedLeapInstallerUrl = $directInfo.Url
        $Script:ResolvedLeapInstallerVersion = $directInfo.Version
        $Script:ResolvedLeapInstallerFileName = $fileName
        Write-Log "Resolved LEAP Desktop installer from downloads page: $fileName"
        if ($directInfo.Version) {
            Write-Log "LEAP downloads page reports latest version: $($directInfo.Version)"
        }
        return [pscustomobject]@{
            Url = $directInfo.Url
            Version = $directInfo.Version
            FileName = $fileName
        }
    }

    $bootstrapMatch = [regex]::Match($pageContent, '<script[^>]+src="(?<src>[^"]*bootstrap\.js[^"]*)"', [System.Text.RegularExpressions.RegexOptions]::IgnoreCase)
    if (-not $bootstrapMatch.Success) {
        throw "Could not find LEAP downloads page bootstrap data."
    }

    $bootstrapUrl = Resolve-AbsoluteUrl -BaseUrl $LeapDownloadsPageUrl -Url $bootstrapMatch.Groups["src"].Value
    $bootstrapResponse = Invoke-WebRequest -Uri $bootstrapUrl -UseBasicParsing -TimeoutSec 60
    $bootstrapContent = $bootstrapResponse.Content

    $marker = 'Object.assign(window.Aura.appBootstrap, '
    $jsonStart = $bootstrapContent.IndexOf($marker)
    if ($jsonStart -lt 0) {
        throw "Could not find LEAP downloads page bootstrap payload."
    }

    $jsonStart = $jsonStart + $marker.Length
    $jsonEnd = $bootstrapContent.IndexOf(";(function()", $jsonStart)
    if ($jsonEnd -lt $jsonStart) {
        $jsonEnd = $bootstrapContent.IndexOf(";(function", $jsonStart)
    }

    if ($jsonEnd -lt $jsonStart) {
        throw "Could not parse LEAP downloads page bootstrap payload."
    }

    $bootstrapJson = $bootstrapContent.Substring($jsonStart, $jsonEnd - $jsonStart).Trim()
    if ($bootstrapJson.EndsWith(");")) {
        $bootstrapJson = $bootstrapJson.Substring(0, $bootstrapJson.Length - 2).Trim()
    }
    elseif ($bootstrapJson.EndsWith(")")) {
        $bootstrapJson = $bootstrapJson.Substring(0, $bootstrapJson.Length - 1).Trim()
    }

    $bootstrap = $bootstrapJson | ConvertFrom-Json

    $router = @($bootstrap.data.components | Where-Object { $_.componentDef.descriptor -eq "markup://siteforce:routerInitializer" } | Select-Object -First 1)
    if ($router.Count -eq 0) {
        throw "Could not find LEAP downloads page router data."
    }

    $downloadsPath = ([Uri]$LeapDownloadsPageUrl).AbsolutePath
    $routeKey = if ($downloadsPath.StartsWith("/s/")) { $downloadsPath.Substring(2) } else { $downloadsPath }
    if ([string]::IsNullOrWhiteSpace($routeKey)) {
        $routeKey = "/downloads"
    }

    $routeProperty = $router[0].model.routes.PSObject.Properties[$routeKey]
    if (-not $routeProperty) {
        throw "Could not find LEAP downloads route metadata for $routeKey."
    }

    $route = $routeProperty.Value
    $viewUuid = $route.view_uuid
    $viewId = $route.id
    $routeType = $route.event
    $themeLayoutType = $route.themeLayoutType
    $publishedChangelistNum = [int]$bootstrap.data.app.attributes.values.publishedChangelistNum
    $brandingSetId = $bootstrap.data.app.attributes.values.brandingSetId
    $descriptor = "sitelayout://siteforce-generatedpage-$viewUuid.c$publishedChangelistNum"

    $dca = @{
        _pl = @{
            _cn = $descriptor
            _vc = @{
                viewId = $viewId
                routeType = $routeType
                themeLayoutType = $themeLayoutType
                params = @{
                    viewid = $viewUuid
                    view_uddid = ""
                    entity_name = ""
                    audience_name = ""
                    picasso_id = ""
                    routeId = ""
                }
                hasAttrVaringCmps = $false
                pageLoadType = "STANDARD_PAGE_CONTENT"
                includeLayout = $true
            }
            _bsi = $brandingSetId
            _pcn = $publishedChangelistNum
            _ff = "DESKTOP"
        }
    } | ConvertTo-Json -Depth 20 -Compress

    $componentQuery = New-QueryString -Parameters @{
        "_def" = $descriptor
        "_dca" = $dca
        "aura.app" = "markup://siteforce:communityApp"
        "aura.mode" = "PROD"
        "_l" = "true"
        "_ff" = "DESKTOP"
        "_l10n" = "en_US"
    }

    $componentUrl = (Resolve-AbsoluteUrl -BaseUrl $LeapDownloadsPageUrl -Url "/s/sfsites/auraCmpDef") + "?" + $componentQuery
    $componentResponse = Invoke-WebRequest -Uri $componentUrl -UseBasicParsing -TimeoutSec 60
    $componentInfo = Get-LeapInstallerLinkFromContent -Content $componentResponse.Content
    if (-not $componentInfo) {
        throw "Could not find the Download LEAP Desktop installer link on the official LEAP downloads page."
    }

    $fallbackResolvedFileName = "LEAPDesktopX64setup.exe"
    if ($componentInfo.Version -match '^(?<version>[0-9.]+)') {
        $fallbackResolvedFileName = "$($matches["version"])_LEAPDesktopX64setup.exe"
    }

    $resolvedFileName = Get-RemoteFileNameFromUrl -Url $componentInfo.Url -FallbackFileName $fallbackResolvedFileName
    if ($resolvedFileName -notmatch '(?i)\.(exe|msi)$') {
        throw "LEAP download did not resolve to an installer filename. Resolved filename: $resolvedFileName"
    }

    if ($resolvedFileName -notmatch '(?i)x64|64') {
        Write-Log "Resolved LEAP installer filename does not explicitly include x64: $resolvedFileName" "WARN"
    }

    $Script:ResolvedLeapInstallerUrl = $componentInfo.Url
    $Script:ResolvedLeapInstallerVersion = $componentInfo.Version
    $Script:ResolvedLeapInstallerFileName = $resolvedFileName

    Write-Log "Resolved LEAP Desktop installer from official downloads page: $resolvedFileName"
    if ($componentInfo.Version) {
        Write-Log "LEAP downloads page reports latest version: $($componentInfo.Version)"
    }

    return [pscustomobject]@{
        Url = $componentInfo.Url
        Version = $componentInfo.Version
        FileName = $resolvedFileName
    }
}

function Stop-DeploymentBlockingApps {
    param([string[]]$ProcessNames)

    if ($Simulation) {
        Write-Log "SIMULATION: Would check and close blocking apps if needed: $($ProcessNames -join ', ')"
        return
    }

    $running = @()
    foreach ($name in $ProcessNames) {
        $running += @(Get-Process -Name $name -ErrorAction SilentlyContinue)
    }

    $running = @($running | Sort-Object Id -Unique)
    if ($running.Count -eq 0) {
        return
    }

    $names = ($running | Select-Object -ExpandProperty ProcessName -Unique | Sort-Object) -join ", "

    if ($ForceCloseApps) {
        Write-Log "Closing running apps with force: $names" "WARN"
        foreach ($process in $running) {
            Stop-Process -Id $process.Id -Force -ErrorAction SilentlyContinue
        }
        Start-Sleep -Seconds 5
        return
    }

    Write-Log "Running apps may block installation: $names" "WARN"
    Write-Log "Trying a normal close request. Use -ForceCloseApps only after work is saved." "WARN"

    foreach ($process in $running) {
        try {
            if ($process.MainWindowHandle -ne 0) {
                [void]$process.CloseMainWindow()
            }
        }
        catch {
            Write-Log "Could not send close request to $($process.ProcessName) PID $($process.Id)." "WARN"
        }
    }

    Start-Sleep -Seconds 30

    $stillRunning = @()
    foreach ($name in $ProcessNames) {
        $stillRunning += @(Get-Process -Name $name -ErrorAction SilentlyContinue)
    }

    if ($stillRunning.Count -gt 0) {
        $stillNames = ($stillRunning | Select-Object -ExpandProperty ProcessName -Unique | Sort-Object) -join ", "
        throw "These apps are still running and could cause data loss if forced: $stillNames. Save work, close them, and rerun, or rerun with -ForceCloseApps."
    }
}

function Write-OfficeConfigurationFiles {
    $removeXmlPath = Join-Path $Script:OfficeDir "remove-office.xml"
    $installXmlPath = Join-Path $Script:OfficeDir "install-m365-semiannual-en-gb.xml"
    $officeSourcePath = Escape-XmlAttribute -Value $Script:OfficeDir

    $removeXml = @"
<Configuration>
  <Remove All="TRUE" />
  <Display Level="None" AcceptEULA="TRUE" />
  <Property Name="FORCEAPPSHUTDOWN" Value="FALSE" />
</Configuration>
"@

    $installXml = @"
<Configuration>
  <Add OfficeClientEdition="64" Channel="SemiAnnual" SourcePath="$officeSourcePath" AllowCdnFallback="True">
    <Product ID="O365ProPlusRetail">
      <Language ID="en-gb" />
    </Product>
  </Add>
  <RemoveMSI />
  <Updates Enabled="TRUE" Channel="SemiAnnual" />
  <Display Level="None" AcceptEULA="TRUE" />
  <Property Name="FORCEAPPSHUTDOWN" Value="FALSE" />
  <Property Name="PinIconsToTaskbar" Value="FALSE" />
</Configuration>
"@

    Set-Content -LiteralPath $removeXmlPath -Value $removeXml -Encoding UTF8
    Set-Content -LiteralPath $installXmlPath -Value $installXml -Encoding UTF8

    Write-Log "Wrote Office remove configuration: $removeXmlPath"
    Write-Log "Wrote Office install configuration: $installXmlPath"

    return @{
        Remove = $removeXmlPath
        Install = $installXmlPath
    }
}

function Install-OfficeDeploymentTool {
    $odtExe = Join-Path $Script:DownloadDir (Split-Path -Leaf $OfficeDeploymentToolUrl)
    Save-Download -Url $OfficeDeploymentToolUrl -Destination $odtExe -MinimumBytes 1000000
    Assert-TrustedSignature -Path $odtExe -ExpectedPublisherFragments @("Microsoft Corporation")

    $setupPath = Join-Path $Script:OfficeDir "setup.exe"
    if (Test-Path -LiteralPath $setupPath) {
        Remove-Item -LiteralPath $setupPath -Force
    }

    Invoke-ProcessChecked `
        -FilePath $odtExe `
        -ArgumentList @("/quiet", "/extract:$Script:OfficeDir") `
        -Description "Office Deployment Tool extraction"

    if ($Simulation -and (-not (Test-Path -LiteralPath $setupPath))) {
        Set-Content -LiteralPath $setupPath -Value "SIMULATION ONLY - Office Deployment Tool setup.exe placeholder" -Encoding ASCII
        Write-Log "SIMULATION: Created placeholder Office setup.exe at $setupPath"
    }

    if (-not (Test-Path -LiteralPath $setupPath)) {
        throw "Office Deployment Tool setup.exe was not extracted to $setupPath."
    }

    Assert-TrustedSignature -Path $setupPath -ExpectedPublisherFragments @("Microsoft Corporation")
    return $setupPath
}

function Get-OfficeDeploymentAssets {
    $setupPath = Install-OfficeDeploymentTool
    $configs = Write-OfficeConfigurationFiles

    return [pscustomobject]@{
        Setup = $setupPath
        RemoveConfig = $configs.Remove
        InstallConfig = $configs.Install
    }
}

function Stop-OfficeBlockingApps {
    $officeProcesses = @(
        "winword", "excel", "powerpnt", "outlook", "onenote", "msaccess", "mspub",
        "visio", "winproj", "lync", "teams", "ms-teams"
    )

    Stop-DeploymentBlockingApps -ProcessNames $officeProcesses
}

function Get-OfficeScrubToolPath {
    $zipLeaf = Split-Path -Leaf ([Uri]$OfficeScrubToolUrl).AbsolutePath
    if ([string]::IsNullOrWhiteSpace($zipLeaf) -or $zipLeaf -notmatch "\.zip$") {
        $zipLeaf = "GetHelpCmd.zip"
    }
    $zipPath = Join-Path $Script:DownloadDir $zipLeaf
    if ([string]::IsNullOrWhiteSpace((Split-Path -Leaf $zipPath))) {
        $zipPath = Join-Path $Script:DownloadDir "GetHelpCmd.zip"
    }

    $extractDir = Join-Path $Script:Root "OfficeScrubTool"

    if ($Simulation) {
        if (-not (Test-Path -LiteralPath $extractDir)) {
            New-Item -Path $extractDir -ItemType Directory -Force | Out-Null
        }
        $tool = Join-Path $extractDir "GetHelpCmd.exe"
        if (-not (Test-Path -LiteralPath $tool)) {
            Set-Content -LiteralPath $tool -Value "SIMULATION ONLY - GetHelpCmd placeholder" -Encoding ASCII
        }
        Write-Log "SIMULATION: Using placeholder Microsoft Office scrub tool at $tool"
        return $tool
    }

    Save-Download -Url $OfficeScrubToolUrl -Destination $zipPath -MinimumBytes 1000000

    if (Test-Path -LiteralPath $extractDir) {
        Remove-Item -LiteralPath $extractDir -Recurse -Force
    }
    New-Item -Path $extractDir -ItemType Directory -Force | Out-Null
    Expand-Archive -LiteralPath $zipPath -DestinationPath $extractDir -Force

    $tool = Get-ChildItem -LiteralPath $extractDir -Recurse -Filter "GetHelpCmd.exe" -ErrorAction SilentlyContinue | Select-Object -First 1
    if (-not $tool) {
        $tool = Get-ChildItem -LiteralPath $extractDir -Recurse -Filter "SaRACmd.exe" -ErrorAction SilentlyContinue | Select-Object -First 1
    }

    if (-not $tool) {
        throw "Could not find GetHelpCmd.exe or SaRACmd.exe after extracting the Office scrub tool."
    }

    Assert-TrustedSignature -Path $tool.FullName -ExpectedPublisherFragments @("Microsoft Corporation")
    return $tool.FullName
}

function Invoke-OfficeScrubCleanup {
    $scrubTool = Get-OfficeScrubToolPath
    $scrubLogDir = Join-Path $Script:LogDir "OfficeScrub-$Script:RunStamp"
    if (-not (Test-Path -LiteralPath $scrubLogDir)) {
        New-Item -Path $scrubLogDir -ItemType Directory -Force | Out-Null
    }

    Invoke-ProcessChecked `
        -FilePath $scrubTool `
        -ArgumentList @("-S", "OfficeScrubScenario", "-AcceptEula", "-OfficeVersion", "All", "-LogFolder", $scrubLogDir) `
        -SuccessExitCodes @(0, 3010) `
        -Description "Microsoft Office scrub cleanup"
}

function Invoke-OfficeUninstallAndCleanup {
    param([Parameter(Mandatory = $true)]$Assets)

    Stop-OfficeBlockingApps

    Invoke-ProcessChecked `
        -FilePath $Assets.Setup `
        -ArgumentList @("/configure", $Assets.RemoveConfig) `
        -Description "Office Click-to-Run removal" `
        -WorkingDirectory $Script:OfficeDir

    Invoke-OfficeScrubCleanup
}

function Invoke-OfficeInstall {
    param([Parameter(Mandatory = $true)]$Assets)

    Invoke-ProcessChecked `
        -FilePath $Assets.Setup `
        -ArgumentList @("/download", $Assets.InstallConfig) `
        -Description "Microsoft 365 Apps installation file download" `
        -WorkingDirectory $Script:OfficeDir

    Invoke-ProcessChecked `
        -FilePath $Assets.Setup `
        -ArgumentList @("/configure", $Assets.InstallConfig) `
        -Description "Microsoft 365 Apps for enterprise installation" `
        -WorkingDirectory $Script:OfficeDir

    if ($Simulation) {
        Write-Log "SIMULATION: Office Click-to-Run ProductReleaseIds: O365ProPlusRetail"
        Write-Log "SIMULATION: Office Platform: x64"
        Write-Log "SIMULATION: Office ClientCulture: en-gb"
        Write-Log "SIMULATION: Office UpdateChannel: SemiAnnual"
        return
    }

    $configKey = "HKLM:\SOFTWARE\Microsoft\Office\ClickToRun\Configuration"
    if (Test-Path -LiteralPath $configKey) {
        $cfg = Get-ItemProperty -LiteralPath $configKey
        Write-Log "Office Click-to-Run ProductReleaseIds: $(Get-ObjectPropertyValue -InputObject $cfg -Name 'ProductReleaseIds')"
        Write-Log "Office Platform: $(Get-ObjectPropertyValue -InputObject $cfg -Name 'Platform')"
        Write-Log "Office ClientCulture: $(Get-ObjectPropertyValue -InputObject $cfg -Name 'ClientCulture')"
        Write-Log "Office CDNBaseUrl: $(Get-ObjectPropertyValue -InputObject $cfg -Name 'CDNBaseUrl')"
        Write-Log "Office UpdateChannel: $(Get-ObjectPropertyValue -InputObject $cfg -Name 'UpdateChannel')"
    }
    else {
        Write-Log "Office Click-to-Run configuration registry key was not found after install." "WARN"
    }
}

function Invoke-OfficeDeployment {
    $assets = Get-OfficeDeploymentAssets
    Invoke-OfficeUninstallAndCleanup -Assets $assets
    Invoke-OfficeInstall -Assets $assets
}

function Get-UninstallEntries {
    $paths = @(
        "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*",
        "HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*"
    )

    foreach ($path in $paths) {
        Get-ItemProperty -Path $path -ErrorAction SilentlyContinue | ForEach-Object {
            [pscustomobject]@{
                DisplayName = Get-ObjectPropertyValue -InputObject $_ -Name "DisplayName"
                DisplayVersion = Get-ObjectPropertyValue -InputObject $_ -Name "DisplayVersion"
                Publisher = Get-ObjectPropertyValue -InputObject $_ -Name "Publisher"
                PSChildName = Get-ObjectPropertyValue -InputObject $_ -Name "PSChildName"
                UninstallString = Get-ObjectPropertyValue -InputObject $_ -Name "UninstallString"
                QuietUninstallString = Get-ObjectPropertyValue -InputObject $_ -Name "QuietUninstallString"
                WindowsInstaller = Get-ObjectPropertyValue -InputObject $_ -Name "WindowsInstaller"
                RegistryPath = Get-ObjectPropertyValue -InputObject $_ -Name "PSPath"
            }
        }
    }
}

function Get-AdobeReaderAndAcrobatEntries {
    if ($Simulation) {
        if ($Script:SimulationAdobeProductsRemoved) {
            return @()
        }

        return @(
            [pscustomobject]@{
                DisplayName = "Adobe Acrobat Reader DC"
                DisplayVersion = "simulated-existing-reader"
                Publisher = "Adobe Inc."
                PSChildName = "{AC76BA86-7AD7-1033-7B44-AC0F074E4100}"
                UninstallString = "MsiExec.exe /I{AC76BA86-7AD7-1033-7B44-AC0F074E4100}"
                QuietUninstallString = $null
                WindowsInstaller = 1
                RegistryPath = "SIMULATION"
            },
            [pscustomobject]@{
                DisplayName = "Adobe Acrobat"
                DisplayVersion = "simulated-existing-acrobat"
                Publisher = "Adobe Inc."
                PSChildName = "{AC76BA86-1033-FFFF-7760-BC15014EA700}"
                UninstallString = "MsiExec.exe /I{AC76BA86-1033-FFFF-7760-BC15014EA700}"
                QuietUninstallString = $null
                WindowsInstaller = 1
                RegistryPath = "SIMULATION"
            }
        )
    }

    Get-UninstallEntries | Where-Object {
        $name = $_.DisplayName
        if ([string]::IsNullOrWhiteSpace($name)) {
            $false
        }
        else {
            $isAcrobatProduct =
                $name -match "(?i)^Adobe Acrobat(\s|$|\()" -or
                $name -match "(?i)^Adobe Reader(\s|$|\()" -or
                $name -match "(?i)^Adobe Acrobat Reader(\s|$|\()"

            $isExcluded =
                $name -match "(?i)Update Service" -or
                $name -match "(?i)Genuine" -or
                $name -match "(?i)Creative Cloud" -or
                $name -match "(?i)Notification" -or
                $name -match "(?i)Refresh Manager"

            $isAcrobatProduct -and (-not $isExcluded)
        }
    } | Sort-Object DisplayName, DisplayVersion -Unique
}

function Get-MsiProductCode {
    param([Parameter(Mandatory = $true)]$Entry)

    if ($Entry.PSChildName -match "^\{[0-9A-Fa-f-]{36}\}$") {
        return $Entry.PSChildName
    }

    foreach ($candidate in @($Entry.UninstallString, $Entry.QuietUninstallString)) {
        if ($candidate -match "\{[0-9A-Fa-f-]{36}\}") {
            return $matches[0]
        }
    }

    return $null
}

function Uninstall-AdobeReaderAndAcrobat {
    $entries = @(Get-AdobeReaderAndAcrobatEntries)
    if ($entries.Count -eq 0) {
        Write-Log "No existing Adobe Reader/Acrobat uninstall entries found."
        return
    }

    foreach ($entry in $entries) {
        Write-Log "Found Adobe product: $($entry.DisplayName) $($entry.DisplayVersion)"
    }

    $adobeProcesses = @("AcroRd32", "Acrobat", "AcroCEF", "RdrCEF")
    Stop-DeploymentBlockingApps -ProcessNames $adobeProcesses

    foreach ($entry in $entries) {
        $productCode = Get-MsiProductCode -Entry $entry
        if (-not $productCode) {
            Write-Log "Skipping non-MSI uninstall entry without a product code: $($entry.DisplayName)" "WARN"
            continue
        }

        $safeName = ($entry.DisplayName -replace "[^A-Za-z0-9._-]", "_")
        $msiLog = Join-Path $Script:LogDir "Uninstall-$safeName-$Script:RunStamp.log"

        Invoke-ProcessChecked `
            -FilePath "$env:SystemRoot\System32\msiexec.exe" `
            -ArgumentList @("/x", $productCode, "/qn", "/norestart", "/L*v", $msiLog) `
            -SuccessExitCodes @(0, 1605, 1614, 3010) `
            -Description "Adobe uninstall: $($entry.DisplayName)"
    }

    if ($Simulation) {
        $Script:SimulationAdobeProductsRemoved = $true
    }

    $remaining = @(Get-AdobeReaderAndAcrobatEntries)
    if ($remaining.Count -gt 0) {
        foreach ($entry in $remaining) {
            Write-Log "Still present after uninstall attempt: $($entry.DisplayName) $($entry.DisplayVersion)" "WARN"
        }
        throw "One or more Adobe Reader/Acrobat products remain installed. Stopping before folder cleanup and fresh Adobe install."
    }
}

function Remove-StaleAdobeMachineRemnants {
    Write-Log "Cleaning safe Adobe machine-level remnants."

    if ($Simulation) {
        Write-Log "SIMULATION: Would stop Adobe update service, unregister stale Adobe update tasks, and remove known machine-level Adobe cache/remnant folders only."
        return
    }

    $serviceNames = @("AdobeARMservice")
    foreach ($serviceName in $serviceNames) {
        $service = Get-Service -Name $serviceName -ErrorAction SilentlyContinue
        if ($service) {
            try {
                if ($service.Status -ne "Stopped") {
                    Stop-Service -Name $serviceName -Force -ErrorAction SilentlyContinue
                }
                Write-Log "Stopped stale service: $serviceName"
            }
            catch {
                Write-Log "Could not stop service $serviceName. $($_.Exception.Message)" "WARN"
            }
        }
    }

    try {
        Get-ScheduledTask -TaskName "Adobe Acrobat Update Task*" -ErrorAction SilentlyContinue | ForEach-Object {
            Unregister-ScheduledTask -TaskName $_.TaskName -TaskPath $_.TaskPath -Confirm:$false -ErrorAction SilentlyContinue
            Write-Log "Removed stale scheduled task: $($_.TaskPath)$($_.TaskName)"
        }
    }
    catch {
        Write-Log "Could not enumerate/remove Adobe scheduled tasks. $($_.Exception.Message)" "WARN"
    }

    $safeDirs = @(
        "$env:ProgramFiles\Adobe\Acrobat DC",
        "${env:ProgramFiles(x86)}\Adobe\Acrobat Reader DC",
        "${env:ProgramFiles(x86)}\Adobe\Reader 11.0",
        "$env:ProgramData\Adobe\ARM",
        "$env:ProgramData\Adobe\Setup"
    )

    foreach ($dir in $safeDirs) {
        if ([string]::IsNullOrWhiteSpace($dir) -or (-not (Test-Path -LiteralPath $dir))) {
            continue
        }

        try {
            Remove-Item -LiteralPath $dir -Recurse -Force -ErrorAction Stop
            Write-Log "Removed stale Adobe folder: $dir"
        }
        catch {
            Write-Log "Could not remove stale Adobe folder $dir. $($_.Exception.Message)" "WARN"
        }
    }
}

function Get-AdobeCleanerPath {
    $cleanerExe = Join-Path $Script:DownloadDir (Split-Path -Leaf ([Uri]$AdobeCleanerToolUrl).AbsolutePath)
    if ([string]::IsNullOrWhiteSpace((Split-Path -Leaf $cleanerExe))) {
        $cleanerExe = Join-Path $Script:DownloadDir "AdobeAcroCleaner.exe"
    }

    Save-Download -Url $AdobeCleanerToolUrl -Destination $cleanerExe -MinimumBytes 1000000
    Assert-TrustedSignature -Path $cleanerExe -ExpectedPublisherFragments @("Adobe", "Adobe Inc.")
    return $cleanerExe
}

function Invoke-AdobeCleanerCleanup {
    $cleanerExe = Get-AdobeCleanerPath

    foreach ($productId in @(1, 0)) {
        $productName = if ($productId -eq 1) { "Reader" } else { "Acrobat" }
        Invoke-ProcessChecked `
            -FilePath $cleanerExe `
            -ArgumentList @("/silent", "/product=$productId", "/cleanlevel=1", "/scanforothers=1") `
            -SuccessExitCodes @(0, 3010) `
            -Description "Adobe AcroCleaner cleanup for $productName"
    }

    if (-not $Simulation) {
        $Script:RebootRequired = $true
    }
    Write-Log "Adobe recommends restarting after AcroCleaner. Continuing because this deployment flow reinstalls before LEAP, but a reboot should be scheduled afterward." "WARN"
}

function Get-AdobeReaderInstallerPath {
    $readerExe = Join-Path $Script:DownloadDir (Split-Path -Leaf $AdobeReaderInstallerUrl)
    Save-Download -Url $AdobeReaderInstallerUrl -Destination $readerExe -MinimumBytes 100000000
    Assert-TrustedSignature -Path $readerExe -ExpectedPublisherFragments @("Adobe", "Adobe Inc.")

    return $readerExe
}

function Assert-AdobeAcrobatProInstallerFileSupported {
    param([Parameter(Mandatory = $true)][string]$Path)

    $extension = [System.IO.Path]::GetExtension($Path)
    if ($extension -notin @(".exe", ".msi")) {
        throw "Acrobat Pro installer must be an .exe or .msi. If Adobe supplied an archive, extract it first and pass the setup executable or MSI."
    }
}

function Assert-AdobeInstallerSourceAvailable {
    param([Parameter(Mandatory = $true)]$AdobeSelection)

    if ($AdobeSelection.Product -eq "Reader") {
        Write-Log "Adobe Reader installer source preflight passed: public Adobe MUI installer URL configured."
        return
    }

    if ($Simulation) {
        Write-Log "SIMULATION: Acrobat Pro installer source and silent argument preflight would pass."
        return
    }

    $hasPath = -not [string]::IsNullOrWhiteSpace($AdobeAcrobatProInstallerPath)
    $hasUrl = -not [string]::IsNullOrWhiteSpace($AdobeAcrobatProInstallerUrl)

    if (-not $hasPath -and -not $hasUrl) {
        throw "Acrobat Pro was selected, but no licensed Acrobat Pro installer source was supplied. Provide -AdobeAcrobatProInstallerPath or -AdobeAcrobatProInstallerUrl before running a real cleanup."
    }

    if ($hasPath) {
        if (-not (Test-Path -LiteralPath $AdobeAcrobatProInstallerPath)) {
            throw "Acrobat Pro installer path was supplied but not found: $AdobeAcrobatProInstallerPath"
        }
        Assert-AdobeAcrobatProInstallerFileSupported -Path $AdobeAcrobatProInstallerPath
        Write-Log "Acrobat Pro installer source preflight passed: $AdobeAcrobatProInstallerPath"
    }

    if ($hasUrl) {
        $leaf = Split-Path -Leaf ([Uri]$AdobeAcrobatProInstallerUrl).AbsolutePath
        if ([string]::IsNullOrWhiteSpace($leaf)) {
            throw "Acrobat Pro installer URL must end with an installer filename."
        }
        Assert-AdobeAcrobatProInstallerFileSupported -Path $leaf
        Write-Log "Acrobat Pro installer source preflight passed: direct URL supplied."
    }

    if ($AdobeAcrobatProInstallArguments.Count -eq 0 -and (-not $AllowAcrobatProInstallerWithoutArguments)) {
        throw "Acrobat Pro was selected, but no silent install arguments were supplied. Provide -AdobeAcrobatProInstallArguments for your licensed Adobe package, or deliberately add -AllowAcrobatProInstallerWithoutArguments."
    }

    if ($AdobeAcrobatProInstallArguments.Count -eq 0) {
        Write-Log "Acrobat Pro install will run without arguments because -AllowAcrobatProInstallerWithoutArguments was supplied." "WARN"
    }
}

function Get-AdobeAcrobatProInstallerPath {
    if ($AdobeAcrobatProInstallerPath) {
        if (-not (Test-Path -LiteralPath $AdobeAcrobatProInstallerPath)) {
            throw "Acrobat Pro installer path was supplied but not found: $AdobeAcrobatProInstallerPath"
        }

        $resolved = (Resolve-Path -LiteralPath $AdobeAcrobatProInstallerPath).Path
        Assert-AdobeAcrobatProInstallerFileSupported -Path $resolved
        if (-not $Simulation) {
            Assert-TrustedSignature -Path $resolved -ExpectedPublisherFragments $AdobeAcrobatProTrustedPublisherFragments
        }
        else {
            Write-Log "SIMULATION: Would use local Acrobat Pro installer path $resolved"
        }
        return $resolved
    }

    if ($AdobeAcrobatProInstallerUrl) {
        $leaf = Split-Path -Leaf ([Uri]$AdobeAcrobatProInstallerUrl).AbsolutePath
        if ([string]::IsNullOrWhiteSpace($leaf)) {
            $leaf = "Adobe-Acrobat-Pro-Installer.exe"
        }

        Assert-AdobeAcrobatProInstallerFileSupported -Path $leaf
        $installer = Join-Path $Script:DownloadDir $leaf
        Save-Download -Url $AdobeAcrobatProInstallerUrl -Destination $installer -MinimumBytes 1000000
        Assert-TrustedSignature -Path $installer -ExpectedPublisherFragments $AdobeAcrobatProTrustedPublisherFragments
        return $installer
    }

    if ($Simulation) {
        $installer = Join-Path $Script:DownloadDir "Adobe-Acrobat-Pro-Installer-Simulation.exe"
        if (-not (Test-Path -LiteralPath $installer)) {
            Set-Content -LiteralPath $installer -Value "SIMULATION ONLY - Acrobat Pro installer placeholder" -Encoding ASCII
        }
        Write-Log "SIMULATION: Using placeholder Acrobat Pro installer at $installer"
        return $installer
    }

    throw "Acrobat Pro was selected, but no licensed Acrobat Pro installer source was supplied."
}

function Get-AdobeSelectedInstallerPath {
    param([Parameter(Mandatory = $true)]$AdobeSelection)

    switch ($AdobeSelection.Product) {
        "Reader" {
            return Get-AdobeReaderInstallerPath
        }
        "AcrobatPro" {
            return Get-AdobeAcrobatProInstallerPath
        }
    }

    throw "Unknown Adobe product: $($AdobeSelection.Product)"
}

function Install-AdobeReader {
    param([Parameter(Mandatory = $true)][string]$ReaderInstallerPath)

    $readerExe = $ReaderInstallerPath
    $installLog = Join-Path $Script:LogDir "AdobeReader-Install-$Script:RunStamp.log"
    $arguments = @(
        "/sAll",
        "/rs",
        "/rps",
        "/msi",
        "/qn",
        "EULA_ACCEPT=YES",
        "REBOOT=ReallySuppress",
        "DISABLEDESKTOPSHORTCUT=1",
        "SUPPRESSLANGSELECTION=YES",
        "LANG_LIST=en_GB",
        "/L*v",
        $installLog
    )

    Invoke-ProcessChecked `
        -FilePath $readerExe `
        -ArgumentList $arguments `
        -Description "Adobe Acrobat Reader 64-bit MUI installation"
}

function Install-AdobeAcrobatPro {
    param([Parameter(Mandatory = $true)][string]$InstallerPath)

    $extension = [System.IO.Path]::GetExtension($InstallerPath)
    $description = "Adobe Acrobat Pro installation"
    $filePath = $InstallerPath
    $arguments = $AdobeAcrobatProInstallArguments

    if ($extension -ieq ".msi") {
        $filePath = "$env:SystemRoot\System32\msiexec.exe"
        $arguments = @("/i", $InstallerPath) + $AdobeAcrobatProInstallArguments
        $description = "Adobe Acrobat Pro MSI installation"
    }

    if ($AdobeAcrobatProInstallArguments.Count -eq 0 -and $Simulation) {
        Write-Log "SIMULATION: No Acrobat Pro install arguments were supplied. A real run would require -AdobeAcrobatProInstallArguments unless -AllowAcrobatProInstallerWithoutArguments is supplied." "WARN"
    }
    elseif ($AdobeAcrobatProInstallArguments.Count -eq 0) {
        Write-Log "No Acrobat Pro install arguments were supplied. This was explicitly allowed; installer UI may appear." "WARN"
    }

    Invoke-ProcessChecked `
        -FilePath $filePath `
        -ArgumentList $arguments `
        -Description $description
}

function Install-AdobeProduct {
    param(
        [Parameter(Mandatory = $true)]$AdobeSelection,
        [Parameter(Mandatory = $true)][string]$InstallerPath
    )

    switch ($AdobeSelection.Product) {
        "Reader" {
            Install-AdobeReader -ReaderInstallerPath $InstallerPath
            return
        }
        "AcrobatPro" {
            Install-AdobeAcrobatPro -InstallerPath $InstallerPath
            return
        }
    }

    throw "Unknown Adobe product: $($AdobeSelection.Product)"
}

function Set-AdobeEnterprisePolicies {
    Write-Log "Applying Adobe Reader/Acrobat enterprise policies."

    if ($Simulation) {
        Write-Log "SIMULATION: Would set bEnableAV2Enterprise=0 and bWhatsNewExp=1 under Adobe FeatureLockDown policy keys."
        if ($DisableAdobeAutoUpdate) {
            Write-Log "SIMULATION: Would also set bUpdater=0 and disable Adobe update tasks." "WARN"
        }
        return
    }

    $featureLockdownPaths = @(
        "HKLM:\SOFTWARE\Policies\Adobe\Acrobat Reader\DC\FeatureLockDown",
        "HKLM:\SOFTWARE\Policies\Adobe\Adobe Acrobat\DC\FeatureLockDown"
    )

    foreach ($path in $featureLockdownPaths) {
        if (-not (Test-Path -LiteralPath $path)) {
            New-Item -Path $path -Force | Out-Null
        }

        New-ItemProperty -LiteralPath $path -Name "bEnableAV2Enterprise" -Value 0 -PropertyType DWord -Force | Out-Null
        New-ItemProperty -LiteralPath $path -Name "bWhatsNewExp" -Value 1 -PropertyType DWord -Force | Out-Null
        Write-Log "Set modern Acrobat UI off and What's New off at $path"

        if ($DisableAdobeAutoUpdate) {
            New-ItemProperty -LiteralPath $path -Name "bUpdater" -Value 0 -PropertyType DWord -Force | Out-Null
            Write-Log "Disabled Adobe product auto-updater by policy at $path" "WARN"
        }
    }

    if ($DisableAdobeAutoUpdate) {
        try {
            Get-ScheduledTask -TaskName "Adobe Acrobat Update Task*" -ErrorAction SilentlyContinue | ForEach-Object {
                Disable-ScheduledTask -TaskName $_.TaskName -TaskPath $_.TaskPath -ErrorAction SilentlyContinue | Out-Null
                Write-Log "Disabled Adobe scheduled update task: $($_.TaskPath)$($_.TaskName)"
            }
        }
        catch {
            Write-Log "Could not disable Adobe scheduled update task. $($_.Exception.Message)" "WARN"
        }
    }
}

function Test-AdobeEnterprisePolicies {
    param([Parameter(Mandatory = $true)]$AdobeSelection)

    $policyPath = if ($AdobeSelection.Product -eq "AcrobatPro") {
        "HKLM:\SOFTWARE\Policies\Adobe\Adobe Acrobat\DC\FeatureLockDown"
    }
    else {
        "HKLM:\SOFTWARE\Policies\Adobe\Acrobat Reader\DC\FeatureLockDown"
    }

    if ($Simulation) {
        Write-Log "SIMULATION: Would verify bEnableAV2Enterprise=0 under $($AdobeSelection.Label) FeatureLockDown policy."
        return
    }

    if (-not (Test-Path -LiteralPath $policyPath)) {
        throw "$($AdobeSelection.Label) FeatureLockDown policy key was not created."
    }

    $policy = Get-ItemProperty -LiteralPath $policyPath
    $modernViewerValue = Get-ObjectPropertyValue -InputObject $policy -Name "bEnableAV2Enterprise"
    if ($modernViewerValue -ne 0) {
        throw "Adobe New Acrobat/Modern Viewer policy is not disabled. Expected bEnableAV2Enterprise=0, found '$modernViewerValue'."
    }

    Write-Log "Verified Adobe New Acrobat/Modern Viewer is disabled by policy for $($AdobeSelection.Label)."
}

function Write-AdobeInstallSummary {
    param([Parameter(Mandatory = $true)]$AdobeSelection)

    if ($Simulation) {
        if ($AdobeSelection.Product -eq "AcrobatPro") {
            Write-Log "SIMULATION: Adobe installed entry: Adobe Acrobat Pro from supplied enterprise installer/package."
        }
        else {
            Write-Log "SIMULATION: Adobe installed entry: Adobe Acrobat Reader 64-bit MUI with LANG_LIST=en_GB"
        }
        return
    }

    $entries = @(Get-AdobeReaderAndAcrobatEntries)
    if ($entries.Count -eq 0) {
        throw "No Adobe Reader/Acrobat install entry found after install."
    }

    foreach ($entry in $entries) {
        Write-Log "Adobe installed entry: $($entry.DisplayName) $($entry.DisplayVersion)"
    }

    $readerEntries = @($entries | Where-Object { $_.DisplayName -match "(?i)^Adobe Acrobat Reader(\s|$|\()" })
    $acrobatEntries = @($entries | Where-Object { $_.DisplayName -match "(?i)^Adobe Acrobat(\s|$|\()" -and $_.DisplayName -notmatch "(?i)^Adobe Acrobat Reader(\s|$|\()" })

    if ($AdobeSelection.Product -eq "Reader") {
        if ($readerEntries.Count -eq 0) {
            throw "Adobe Acrobat Reader was not found after install."
        }

        if ($acrobatEntries.Count -gt 0) {
            $names = ($acrobatEntries | ForEach-Object { "$($_.DisplayName) $($_.DisplayVersion)" }) -join "; "
            throw "Adobe Acrobat non-Reader product remains installed after Reader deployment: $names"
        }

        Write-Log "Verified Adobe Reader-only deployment. Requested installer language: LANG_LIST=en_GB."
        return
    }

    if ($acrobatEntries.Count -eq 0) {
        throw "Adobe Acrobat Pro was not found after install."
    }

    if ($readerEntries.Count -gt 0) {
        $names = ($readerEntries | ForEach-Object { "$($_.DisplayName) $($_.DisplayVersion)" }) -join "; "
        throw "Adobe Reader product remains installed after Acrobat Pro deployment: $names"
    }

    Write-Log "Verified Adobe Acrobat Pro deployment. Locale and 64-bit selection depend on the supplied licensed enterprise package."
}

function Get-LeapEntries {
    if ($Simulation) {
        if ($Script:SimulationLeapProductsRemoved -and (-not $Script:SimulationLeapInstalled)) {
            return @()
        }

        if ($Script:SimulationLeapInstalled) {
            return @(
                [pscustomobject]@{
                    DisplayName = "LEAP Desktop"
                    DisplayVersion = "simulated-fresh-install"
                    Publisher = "LEAP"
                    PSChildName = "{11111111-2222-3333-4444-555555555555}"
                    UninstallString = "MsiExec.exe /I{11111111-2222-3333-4444-555555555555}"
                    QuietUninstallString = $null
                    WindowsInstaller = 1
                    RegistryPath = "SIMULATION"
                }
            )
        }

        return @(
            [pscustomobject]@{
                DisplayName = "LEAP Desktop"
                DisplayVersion = "simulated-existing-leap"
                Publisher = "LEAP"
                PSChildName = "{11111111-2222-3333-4444-555555555555}"
                UninstallString = "MsiExec.exe /I{11111111-2222-3333-4444-555555555555}"
                QuietUninstallString = $null
                WindowsInstaller = 1
                RegistryPath = "SIMULATION"
            }
        )
    }

    Get-UninstallEntries | Where-Object {
        $name = $_.DisplayName
        $publisher = $_.Publisher
        if ([string]::IsNullOrWhiteSpace($name)) {
            $false
        }
        else {
            $looksLikeLeap =
                $name -match "(?i)^(LEAP|LEAP Desktop|LEAP Office|LEAP Legal)(\s|$|\()" -or
                $name -match "(?i)\bLEAP Desktop\b" -or
                $name -match "(?i)\bLEAP Office\b"

            $publisherLooksLikeLeap =
                -not [string]::IsNullOrWhiteSpace($publisher) -and
                $publisher -match "(?i)LEAP"

            $looksLikeLeap -or ($publisherLooksLikeLeap -and $name -match "(?i)\bLEAP\b")
        }
    } | Sort-Object DisplayName, DisplayVersion -Unique
}

function Find-TrustedLeapInstallerPath {
    if ($Script:AutoDiscoveredLeapInstallerPath -and (Test-Path -LiteralPath $Script:AutoDiscoveredLeapInstallerPath)) {
        return $Script:AutoDiscoveredLeapInstallerPath
    }

    $roots = @($LeapInstallerSearchRoots | Where-Object {
        -not [string]::IsNullOrWhiteSpace($_)
    } | Select-Object -Unique)

    if ($roots.Count -eq 0) {
        return $null
    }

    Write-Log "Searching for a local LEAP installer in: $($roots -join '; ')"

    $candidates = @()
    foreach ($root in $roots) {
        if (-not (Test-Path -LiteralPath $root)) {
            continue
        }

        try {
            $candidates += @(Get-ChildItem -LiteralPath $root -File -ErrorAction SilentlyContinue |
                Where-Object {
                    $_.Extension -match "(?i)^\.(exe|msi)$" -and
                    $_.Name -match "(?i)leap"
                })
        }
        catch {
            Write-Log "Could not search LEAP installer folder $root. $($_.Exception.Message)" "WARN"
        }
    }

    $candidates = @($candidates | Sort-Object FullName -Unique)
    if ($candidates.Count -eq 0) {
        Write-Log "No local LEAP installer candidates were found in configured search folders." "WARN"
        return $null
    }

    $trustedCandidates = @()
    foreach ($candidate in $candidates) {
        if (Test-TrustedSignature -Path $candidate.FullName -ExpectedPublisherFragments $LeapTrustedPublisherFragments) {
            $trustedCandidates += $candidate
        }
        else {
            Write-Log "Ignoring LEAP-named installer candidate without a trusted LEAP signature: $($candidate.FullName)" "WARN"
        }
    }

    if ($trustedCandidates.Count -eq 0) {
        Write-Log "LEAP-named installer files were found, but none had a trusted LEAP signature." "WARN"
        return $null
    }

    if ($trustedCandidates.Count -gt 1) {
        $candidateList = ($trustedCandidates | ForEach-Object { $_.FullName }) -join "; "
        throw "Multiple trusted LEAP installer candidates were found. Supply -LeapInstallerPath explicitly. Candidates: $candidateList"
    }

    $resolved = $trustedCandidates[0].FullName
    $Script:AutoDiscoveredLeapInstallerPath = $resolved
    Write-Log "Auto-discovered trusted LEAP installer: $resolved"
    return $resolved
}

function Get-LeapInstallerPath {
    if ($LeapInstallerPath) {
        if (-not (Test-Path -LiteralPath $LeapInstallerPath)) {
            throw "LEAP installer path was supplied but not found: $LeapInstallerPath"
        }

        $resolved = (Resolve-Path -LiteralPath $LeapInstallerPath).Path
        if (-not $Simulation) {
            Assert-TrustedSignature -Path $resolved -ExpectedPublisherFragments $LeapTrustedPublisherFragments
        }
        else {
            Write-Log "SIMULATION: Would use local LEAP installer path $resolved"
        }
        return $resolved
    }

    if ($LeapInstallerUrl) {
        $leaf = Get-RemoteFileNameFromUrl -Url $LeapInstallerUrl -FallbackFileName "LEAP-Installer.exe"

        $installer = Join-Path $Script:DownloadDir $leaf
        Save-Download -Url $LeapInstallerUrl -Destination $installer -MinimumBytes 10000000
        Assert-TrustedSignature -Path $installer -ExpectedPublisherFragments $LeapTrustedPublisherFragments
        return $installer
    }

    if ($Simulation) {
        $installer = Join-Path $Script:DownloadDir "LEAP-Installer-Simulation.exe"
        if (-not (Test-Path -LiteralPath $installer)) {
            Set-Content -LiteralPath $installer -Value "SIMULATION ONLY - LEAP installer placeholder" -Encoding ASCII
        }
        Write-Log "SIMULATION: Using placeholder LEAP installer at $installer"
        return $installer
    }

    try {
        $websiteInstaller = Resolve-LeapInstallerFromWebsite
        $installerFileName = $websiteInstaller.FileName
        if ([string]::IsNullOrWhiteSpace($installerFileName)) {
            $installerFileName = "LEAPDesktopX64setup.exe"
        }

        $installer = Join-Path $Script:DownloadDir $installerFileName
        Save-Download -Url $websiteInstaller.Url -Destination $installer -MinimumBytes 10000000 -AlwaysDownload
        Assert-TrustedSignature -Path $installer -ExpectedPublisherFragments $LeapTrustedPublisherFragments
        return $installer
    }
    catch {
        if (-not $AllowLocalLeapInstallerFallback) {
            throw
        }

        Write-Log "LEAP website installer resolution failed; checking local fallback because -AllowLocalLeapInstallerFallback was supplied. $($_.Exception.Message)" "WARN"
    }

    if ($AllowLocalLeapInstallerFallback) {
        $autoDiscoveredInstaller = Find-TrustedLeapInstallerPath
        if ($autoDiscoveredInstaller) {
            Assert-TrustedSignature -Path $autoDiscoveredInstaller -ExpectedPublisherFragments $LeapTrustedPublisherFragments
            return $autoDiscoveredInstaller
        }
    }

    throw "LEAP was selected, but the latest LEAP Desktop installer could not be resolved from $LeapDownloadsPageUrl."
}

function Assert-LeapInstallerSourceAvailable {
    if ($Simulation) {
        Write-Log "SIMULATION: LEAP installer source preflight would pass."
        return
    }

    if ($LeapInstallerPath) {
        if (-not (Test-Path -LiteralPath $LeapInstallerPath)) {
            throw "LEAP installer path was supplied but not found: $LeapInstallerPath"
        }
        Write-Log "LEAP installer source preflight passed: $LeapInstallerPath"
        return
    }

    if ($LeapInstallerUrl) {
        Write-Log "LEAP installer source preflight passed: direct URL supplied."
        return
    }

    try {
        $websiteInstaller = Resolve-LeapInstallerFromWebsite
        if ($websiteInstaller -and $websiteInstaller.Url) {
            Write-Log "LEAP installer source preflight passed: latest installer resolved from official LEAP downloads page."
            return
        }
    }
    catch {
        if (-not $AllowLocalLeapInstallerFallback) {
            throw
        }

        Write-Log "LEAP website installer preflight failed; checking local fallback because -AllowLocalLeapInstallerFallback was supplied. $($_.Exception.Message)" "WARN"
    }

    if ($AllowLocalLeapInstallerFallback) {
        $autoDiscoveredInstaller = Find-TrustedLeapInstallerPath
        if ($autoDiscoveredInstaller) {
            Write-Log "LEAP installer source preflight passed: auto-discovered trusted local installer fallback."
            return
        }
    }

    throw "LEAP was selected, but the latest LEAP Desktop installer could not be resolved from $LeapDownloadsPageUrl. Stopping before cleanup."
}

function Uninstall-Leap {
    $entries = @(Get-LeapEntries)
    if ($entries.Count -eq 0) {
        Write-Log "No existing LEAP uninstall entries found."
        return
    }

    foreach ($entry in $entries) {
        Write-Log "Found LEAP product: $($entry.DisplayName) $($entry.DisplayVersion)"
    }

    $leapProcesses = @("LEAP", "LEAPDesktop", "LEAP.Office", "LEAPOffice", "LEAPLauncher", "LEAPCloud")
    Stop-DeploymentBlockingApps -ProcessNames $leapProcesses

    foreach ($entry in $entries) {
        $productCode = Get-MsiProductCode -Entry $entry
        if ($productCode) {
            $safeName = ($entry.DisplayName -replace "[^A-Za-z0-9._-]", "_")
            $msiLog = Join-Path $Script:LogDir "Uninstall-$safeName-$Script:RunStamp.log"

            Invoke-ProcessChecked `
                -FilePath "$env:SystemRoot\System32\msiexec.exe" `
                -ArgumentList @("/x", $productCode, "/qn", "/norestart", "/L*v", $msiLog) `
                -SuccessExitCodes @(0, 1605, 1614, 3010) `
                -Description "LEAP uninstall: $($entry.DisplayName)"
            continue
        }

        if (-not [string]::IsNullOrWhiteSpace($entry.QuietUninstallString)) {
            $quietUninstall = Split-CommandLine -CommandLine $entry.QuietUninstallString
            Invoke-ProcessChecked `
                -FilePath $quietUninstall.FilePath `
                -ArgumentList $quietUninstall.Arguments `
                -SuccessExitCodes @(0, 3010) `
                -Description "LEAP quiet uninstall: $($entry.DisplayName)"
            continue
        }

        throw "LEAP product '$($entry.DisplayName)' does not expose an MSI product code or QuietUninstallString. Stopping rather than guessing a silent uninstall command."
    }

    if ($Simulation) {
        $Script:SimulationLeapProductsRemoved = $true
        $Script:SimulationLeapInstalled = $false
    }

    $remaining = @(Get-LeapEntries)
    if ($remaining.Count -gt 0) {
        foreach ($entry in $remaining) {
            Write-Log "Still present after LEAP uninstall attempt: $($entry.DisplayName) $($entry.DisplayVersion)" "WARN"
        }
        throw "One or more LEAP products remain installed. Stopping before LEAP folder cleanup and reinstall."
    }
}

function Get-LeapResidualBackupDir {
    $backupDir = Join-Path $Script:BackupDir "LEAP-Residual-$Script:RunStamp"
    if (-not (Test-Path -LiteralPath $backupDir)) {
        New-Item -Path $backupDir -ItemType Directory -Force | Out-Null
    }

    return $backupDir
}

function Move-LeapResidualToBackup {
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [Parameter(Mandatory = $true)][string]$Label
    )

    if (-not (Test-Path -LiteralPath $Path)) {
        Write-Log "LEAP residual not present, skipping: $Path"
        $Script:LeapResidualSkipped++
        return
    }

    $backupDir = Get-LeapResidualBackupDir
    $safeLabel = ConvertTo-SafeFileName -FileName $Label
    $destination = Get-UniquePath -Path (Join-Path $backupDir $safeLabel)

    try {
        Write-Log "Moving LEAP residual to backup: $Path -> $destination"
        Move-Item -LiteralPath $Path -Destination $destination -Force -ErrorAction Stop
        $Script:LeapResidualMoved++
    }
    catch {
        Write-Log "Could not move LEAP residual $Path. $($_.Exception.Message)" "ERROR"
        $Script:LeapResidualErrors++
    }
}

function Rename-LeapResidualFolder {
    param([Parameter(Mandatory = $true)][string]$Path)

    if (-not (Test-Path -LiteralPath $Path)) {
        Write-Log "LEAP residual not present, skipping: $Path"
        $Script:LeapResidualSkipped++
        return
    }

    $oldPath = "$Path.old"
    if (Test-Path -LiteralPath $oldPath) {
        $oldPath = "$Path.old.$Script:RunStamp"
    }

    try {
        Write-Log "Renaming LEAP residual: $Path -> $oldPath"
        Rename-Item -LiteralPath $Path -NewName (Split-Path -Leaf $oldPath) -Force -ErrorAction Stop
        $Script:LeapResidualRenamed++
    }
    catch {
        Write-Log "Could not rename LEAP residual $Path. $($_.Exception.Message)" "ERROR"
        $Script:LeapResidualErrors++
    }
}

function Get-LocalUserProfilePaths {
    $usersRootPattern = Join-Path $env:SystemDrive "Users\*"

    Get-CimInstance Win32_UserProfile | Where-Object {
        (-not $_.Special) -and
        (-not [string]::IsNullOrWhiteSpace($_.LocalPath)) -and
        (Test-Path -LiteralPath $_.LocalPath) -and
        ($_.LocalPath -like $usersRootPattern)
    } | Select-Object -ExpandProperty LocalPath -Unique
}

function Remove-StaleLeapUserProfileRemnants {
    if ($SkipLeapProfileCleanup) {
        Write-Log "Skipping LEAP user profile residual cleanup because -SkipLeapProfileCleanup was supplied." "WARN"
        return
    }

    Write-Log "Cleaning known LEAP user profile remnants by moving them to backup."
    Write-Log "Preserving AppData\Roaming\LEAP Accounting because it may contain incomplete LEAP Accounting timesheet entries." "WARN"

    if ($Simulation) {
        Write-Log "SIMULATION: Would enumerate non-special local user profiles and move known LEAP profile leftovers to backup."
        Write-Log "SIMULATION: Would preserve AppData\Roaming\LEAP Accounting in each profile if present." "WARN"
        return
    }

    $profiles = @(Get-LocalUserProfilePaths)
    if ($profiles.Count -eq 0) {
        Write-Log "No local user profiles found for LEAP profile cleanup."
        return
    }

    foreach ($profile in $profiles) {
        $userName = Split-Path -Leaf $profile
        $roamingPath = Join-Path $profile "AppData\Roaming"
        $localPath = Join-Path $profile "AppData\Local"
        $tempPath = Join-Path $localPath "Temp"

        Write-Log "Cleaning LEAP remnants in profile: $profile"

        if (Test-Path -LiteralPath $roamingPath) {
            Move-LeapResidualToBackup -Path (Join-Path $roamingPath "4D") -Label "$userName-Roaming-4D"
            Move-LeapResidualToBackup -Path (Join-Path $roamingPath "LEAP Desktop") -Label "$userName-Roaming-LEAP Desktop"
            Move-LeapResidualToBackup -Path (Join-Path $roamingPath "LEAP Legal Software") -Label "$userName-Roaming-LEAP Legal Software"

            $leapAccountingPath = Join-Path $roamingPath "LEAP Accounting"
            if (Test-Path -LiteralPath $leapAccountingPath) {
                Write-Log "Preserving LEAP Accounting profile folder: $leapAccountingPath" "WARN"
                $Script:LeapResidualPreserved++
            }
        }

        if (Test-Path -LiteralPath $localPath) {
            Rename-LeapResidualFolder -Path (Join-Path $localPath "LEAP_Desktop")
            Move-LeapResidualToBackup -Path (Join-Path $localPath "LEAP") -Label "$userName-Local-LEAP"
            Move-LeapResidualToBackup -Path (Join-Path $localPath "LEAP Office Installations") -Label "$userName-Local-LEAP Office Installations"
            Move-LeapResidualToBackup -Path (Join-Path $localPath "LEAP_Legal") -Label "$userName-Local-LEAP_Legal"

            $microsoftCorporationPath = Join-Path $localPath "Microsoft Corporation"
            if (Test-Path -LiteralPath $microsoftCorporationPath) {
                Get-ChildItem -LiteralPath $microsoftCorporationPath -Directory -ErrorAction SilentlyContinue |
                    Where-Object { $_.Name -like "*LEAP*" } |
                    ForEach-Object {
                        Move-LeapResidualToBackup -Path $_.FullName -Label "$userName-Local-Microsoft Corporation-$($_.Name)"
                    }
            }
        }

        if (Test-Path -LiteralPath $tempPath) {
            Move-LeapResidualToBackup -Path (Join-Path $tempPath "4D") -Label "$userName-Temp-4D"
            Move-LeapResidualToBackup -Path (Join-Path $tempPath "LEAP") -Label "$userName-Temp-LEAP"
            Move-LeapResidualToBackup -Path (Join-Path $tempPath "LEAP_Legal") -Label "$userName-Temp-LEAP_Legal"
            Move-LeapResidualToBackup -Path (Join-Path $tempPath "LEAP_Cloud") -Label "$userName-Temp-LEAP_Cloud"
            Move-LeapResidualToBackup -Path (Join-Path $tempPath "LEAP_Desktop") -Label "$userName-Temp-LEAP_Desktop"
        }
    }
}

function Remove-StaleLeapMachineRemnants {
    Write-Log "Cleaning safe LEAP machine-level remnants by moving or renaming them."

    if ($Simulation) {
        Write-Log "SIMULATION: Would unregister stale LEAP scheduled tasks."
        Write-Log "SIMULATION: Would move known machine-level LEAP folders to backup and rename selected ProgramData folders."
        return
    }

    try {
        Get-ScheduledTask -TaskName "LEAP*" -ErrorAction SilentlyContinue | ForEach-Object {
            Unregister-ScheduledTask -TaskName $_.TaskName -TaskPath $_.TaskPath -Confirm:$false -ErrorAction SilentlyContinue
            Write-Log "Removed stale LEAP scheduled task: $($_.TaskPath)$($_.TaskName)"
        }
    }
    catch {
        Write-Log "Could not enumerate/remove LEAP scheduled tasks. $($_.Exception.Message)" "WARN"
    }

    foreach ($name in @("LEAP Office", "LEAP Accounting")) {
        Rename-LeapResidualFolder -Path (Join-Path $env:ProgramData $name)
    }

    $safeDirs = @()
    $machineRoots = @($env:ProgramFiles, ${env:ProgramFiles(x86)}, $env:ProgramData) | Where-Object {
        -not [string]::IsNullOrWhiteSpace($_)
    } | Select-Object -Unique

    foreach ($root in $machineRoots) {
        foreach ($name in @("LEAP", "LEAP Legal Software", "LEAP Office", "LEAP Accounting")) {
            $safeDirs += Join-Path $root $name
        }
    }

    foreach ($dir in ($safeDirs | Select-Object -Unique)) {
        Move-LeapResidualToBackup -Path $dir -Label (($dir -replace "^[A-Za-z]:\\", "") -replace "\\", "-")
    }
}

function Write-LeapResidualCleanupSummary {
    if ($Simulation) {
        Write-Log "SIMULATION: LEAP residual backup path would be under $Script:BackupDir"
        return
    }

    Write-Log "LEAP residual cleanup backup path: $(Join-Path $Script:BackupDir "LEAP-Residual-$Script:RunStamp")"
    Write-Log "LEAP residual folders moved to backup: $Script:LeapResidualMoved"
    Write-Log "LEAP residual folders renamed in place: $Script:LeapResidualRenamed"
    Write-Log "LEAP residual paths skipped because missing: $Script:LeapResidualSkipped"
    Write-Log "LEAP residual folders preserved: $Script:LeapResidualPreserved"
    Write-Log "LEAP residual cleanup errors: $Script:LeapResidualErrors"

    if ($Script:LeapResidualErrors -gt 0) {
        throw "LEAP residual cleanup encountered errors. Restart and rerun before continuing with Office, Adobe, or LEAP reinstall."
    }
}

function Install-Leap {
    param([Parameter(Mandatory = $true)][string]$InstallerPath)

    if ($LeapInstallArguments.Count -eq 0) {
        Write-Log "No LEAP silent install arguments were supplied. The installer may display UI. Provide -LeapInstallArguments if LEAP support gives you a silent command line." "WARN"
    }

    Invoke-ProcessChecked `
        -FilePath $InstallerPath `
        -ArgumentList $LeapInstallArguments `
        -Description "LEAP installation"

    if ($Simulation) {
        $Script:SimulationLeapInstalled = $true
    }
}

function Write-LeapInstallSummary {
    $entries = @(Get-LeapEntries)
    if ($entries.Count -eq 0) {
        throw "No LEAP install entry found after install."
    }

    foreach ($entry in $entries) {
        Write-Log "LEAP installed entry: $($entry.DisplayName) $($entry.DisplayVersion)"
    }
}

function Remove-WorkingDownloadsIfRequested {
    if ($KeepDownloads) {
        Write-Log "Keeping downloads in $Script:DownloadDir"
        return
    }

    try {
        Remove-Item -LiteralPath $Script:DownloadDir -Recurse -Force -ErrorAction Stop
        Write-Log "Removed temporary downloads: $Script:DownloadDir"
    }
    catch {
        Write-Log "Could not remove temporary downloads. $($_.Exception.Message)" "WARN"
    }
}

function Invoke-DeploymentPause {
    param(
        [Parameter(Mandatory = $true)][int]$Seconds,
        [Parameter(Mandatory = $true)][string]$Reason
    )

    if ($Seconds -le 0) {
        Write-Log "Skipping pause for $Reason because duration is $Seconds seconds."
        return
    }

    if ($Simulation) {
        Write-Log "SIMULATION: Would wait $Seconds seconds for $Reason."
        return
    }

    Write-Log "Waiting $Seconds seconds for $Reason."
    Start-Sleep -Seconds $Seconds
}

try {
    Initialize-DeploymentFolders
    Write-Log "Deployment started."
    Write-Log "Log file: $Script:LogFile"
    Write-Log "Working root: $Script:Root"
    Assert-AdminAndPlatform

    $selection = Resolve-InstallSelection
    $installOffice = [bool]$selection.InstallOffice
    $installAdobe = [bool]$selection.InstallAdobe
    $installLeap = [bool]$selection.InstallLeap
    Write-Log "Selected deployment mode: $($selection.Label)"

    $adobeSelection = Resolve-AdobeProductSelection -InstallAdobe $installAdobe
    if ($installAdobe) {
        Write-Log "Selected Adobe product: $($adobeSelection.Label)"
        Assert-AdobeInstallerSourceAvailable -AdobeSelection $adobeSelection
    }

    if ($installLeap) {
        Assert-LeapInstallerSourceAvailable
    }

    $leapInstallerResolvedPath = $null
    if ($installLeap) {
        Write-Log "Removing LEAP first so no existing LEAP add-ins remain attached to Office or Adobe."
        Uninstall-Leap
        Remove-StaleLeapUserProfileRemnants
        Remove-StaleLeapMachineRemnants
        Write-LeapResidualCleanupSummary
    }
    else {
        Write-Log "Skipping LEAP removal/cleanup for selected deployment mode." "WARN"
    }

    $officeAssets = $null

    if ($installOffice) {
        $officeAssets = Get-OfficeDeploymentAssets
        Invoke-OfficeUninstallAndCleanup -Assets $officeAssets
    }
    else {
        Write-Log "Skipping Office removal/cleanup for selected deployment mode." "WARN"
    }

    if ($installAdobe) {
        Uninstall-AdobeReaderAndAcrobat
        Remove-StaleAdobeMachineRemnants
        Invoke-AdobeCleanerCleanup
    }
    else {
        Write-Log "Skipping Adobe removal/cleanup for selected deployment mode." "WARN"
    }

    if ($installOffice -or $installAdobe) {
        Invoke-DeploymentPause -Seconds $PostCleanupWaitSeconds -Reason "post-cleanup settling before fresh Office/Adobe installs"
    }

    if ($installOffice) {
        Invoke-OfficeInstall -Assets $officeAssets
    }

    $adobeInstallerPath = $null
    if ($installAdobe) {
        Write-Log "Pre-staging $($adobeSelection.Label) installer after cleanup and before fresh Adobe install."
        $adobeInstallerPath = Get-AdobeSelectedInstallerPath -AdobeSelection $adobeSelection
        Install-AdobeProduct -AdobeSelection $adobeSelection -InstallerPath $adobeInstallerPath
        Set-AdobeEnterprisePolicies
        Test-AdobeEnterprisePolicies -AdobeSelection $adobeSelection
        Write-AdobeInstallSummary -AdobeSelection $adobeSelection
    }

    if ($installOffice -or $installAdobe) {
        Invoke-DeploymentPause -Seconds $PreLeapWaitSeconds -Reason "Office/Adobe installation completion before LEAP add-in install"
    }

    if ($installLeap) {
        if ($installOffice -or $installAdobe) {
            Write-Log "Office/Adobe selected work is complete. Starting LEAP install last so it can install its add-ins."
        }
        else {
            Write-Log "Starting LEAP install."
        }
        $leapInstallerResolvedPath = Get-LeapInstallerPath
        Install-Leap -InstallerPath $leapInstallerResolvedPath
        Write-LeapInstallSummary
    }
    else {
        Write-Log "Skipping LEAP install for selected deployment mode." "WARN"
    }

    Remove-WorkingDownloadsIfRequested

    $elapsed = New-TimeSpan -Start $Script:StartTime -End (Get-Date)
    Write-Log ("Deployment completed in {0:g}." -f $elapsed) "SUCCESS"
    if ($Script:RebootRequired) {
        Write-Log "A reboot is required to finish one or more changes." "WARN"
        exit 3010
    }

    exit 0
}
catch {
    Write-Log $_.Exception.Message "ERROR"
    Write-Log "Deployment failed. See the log above plus component logs in $Script:LogDir." "ERROR"
    exit 1
}
