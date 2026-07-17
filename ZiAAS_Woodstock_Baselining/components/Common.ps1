#requires -version 5.1
<#
Shared library for ZiAAS Woodstock Baselining component scripts.
Do not run this file directly; run ZiAAS_Woodstock_Baselining.ps1.
#>

Set-StrictMode -Version 2.0
$ErrorActionPreference = "Stop"
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
Import-Module Microsoft.PowerShell.Utility -ErrorAction SilentlyContinue

function Resolve-ZiaasConfigValue {
    param(
        [Parameter(Mandatory = $true)][string]$Name,
        [object]$Default = $null
    )

    $configVariable = Get-Variable -Name ZiaasConfig -Scope Script -ErrorAction SilentlyContinue
    if ($configVariable -and $null -ne $configVariable.Value) {
        $property = $configVariable.Value.PSObject.Properties[$Name]
        if ($null -ne $property -and $null -ne $property.Value) {
            return $property.Value
        }
    }

    $variable = Get-Variable -Name $Name -Scope Script -ErrorAction SilentlyContinue
    if ($variable) {
        return $variable.Value
    }

    return $Default
}

function Resolve-ZiaasConfigBool {
    param(
        [Parameter(Mandatory = $true)][string]$Name,
        [bool]$Default = $false
    )

    $value = Resolve-ZiaasConfigValue -Name $Name -Default $Default
    if ($null -eq $value) {
        return $Default
    }
    if ($value -is [System.Management.Automation.SwitchParameter]) {
        return $value.IsPresent
    }
    if ($value -is [bool]) {
        return $value
    }
    if ($value -is [string]) {
        return [System.Convert]::ToBoolean($value)
    }
    return [System.Convert]::ToBoolean($value)
}

function Resolve-ZiaasConfigArray {
    param(
        [Parameter(Mandatory = $true)][string]$Name,
        [object[]]$Default = @()
    )

    $value = Resolve-ZiaasConfigValue -Name $Name -Default $Default
    if ($null -eq $value) {
        return @()
    }
    if ($value -is [string]) {
        if ([string]::IsNullOrWhiteSpace($value)) {
            return @()
        }
        return @($value)
    }
    if ($value -is [System.Collections.IEnumerable]) {
        return @($value | ForEach-Object { [string]$_ })
    }
    return @([string]$value)
}

$WorkingRoot = [string](Resolve-ZiaasConfigValue -Name "WorkingRoot" -Default "$env:ProgramData\ZiAAS_Woodstock_Baselining")
$InstallMode = [string](Resolve-ZiaasConfigValue -Name "InstallMode" -Default "Prompt")
$Simulation = Resolve-ZiaasConfigBool -Name "Simulation" -Default $false
$SimulationAcrobatProEntitlementLevel = [int](Resolve-ZiaasConfigValue -Name "SimulationAcrobatProEntitlementLevel" -Default 300)
$ForceCloseApps = Resolve-ZiaasConfigBool -Name "ForceCloseApps" -Default $false
$Quiet = Resolve-ZiaasConfigBool -Name "Quiet" -Default $false
$NoColor = Resolve-ZiaasConfigBool -Name "NoColor" -Default $false
$LogLevel = [string](Resolve-ZiaasConfigValue -Name "LogLevel" -Default "Info")
$UseCachedInstallers = Resolve-ZiaasConfigBool -Name "UseCachedInstallers" -Default $false
$SkipOffice = Resolve-ZiaasConfigBool -Name "SkipOffice" -Default $false
$SkipAdobe = Resolve-ZiaasConfigBool -Name "SkipAdobe" -Default $false
$DisableAdobeAutoUpdate = Resolve-ZiaasConfigBool -Name "DisableAdobeAutoUpdate" -Default $false
$KeepDownloads = Resolve-ZiaasConfigBool -Name "KeepDownloads" -Default $false
$SkipLeapProfileCleanup = Resolve-ZiaasConfigBool -Name "SkipLeapProfileCleanup" -Default $false
$OfficeDeploymentToolUrl = [string](Resolve-ZiaasConfigValue -Name "OfficeDeploymentToolUrl" -Default "https://download.microsoft.com/download/6c1eeb25-cf8b-41d9-8d0d-cc1dbc032140/officedeploymenttool_20026-20112.exe")
$OfficeScrubToolUrl = [string](Resolve-ZiaasConfigValue -Name "OfficeScrubToolUrl" -Default "https://aka.ms/SaRA_EnterpriseVersionFiles")
$OfficeProductId = [string](Resolve-ZiaasConfigValue -Name "OfficeProductId" -Default "O365ProPlusRetail")
$AdobeProduct = [string](Resolve-ZiaasConfigValue -Name "AdobeProduct" -Default "Prompt")
$AdobeReaderInstallerUrl = [string](Resolve-ZiaasConfigValue -Name "AdobeReaderInstallerUrl" -Default "https://ardownload2.adobe.com/pub/adobe/acrobat/win/AcrobatDC/2600121691/AcroRdrDCx642600121691_MUI.exe")
$AdobeAcrobatProInstallerPath = [string](Resolve-ZiaasConfigValue -Name "AdobeAcrobatProInstallerPath" -Default "")
$AdobeAcrobatProInstallerUrl = [string](Resolve-ZiaasConfigValue -Name "AdobeAcrobatProInstallerUrl" -Default "")
$AdobeAcrobatProInstallArguments = [string[]]@(Resolve-ZiaasConfigArray -Name "AdobeAcrobatProInstallArguments" -Default @())
$AdobeAcrobatProInstallArgumentLine = [string](Resolve-ZiaasConfigValue -Name "AdobeAcrobatProInstallArgumentLine" -Default "")
$AllowAcrobatProInstallerWithoutArguments = Resolve-ZiaasConfigBool -Name "AllowAcrobatProInstallerWithoutArguments" -Default $false
$AllowAcrobatProLanguageNotVerified = Resolve-ZiaasConfigBool -Name "AllowAcrobatProLanguageNotVerified" -Default $false
$AllowAcrobatProEntitlementNotVerified = Resolve-ZiaasConfigBool -Name "AllowAcrobatProEntitlementNotVerified" -Default $false
$AdobeAcrobatProTrustedPublisherFragments = [string[]]@(Resolve-ZiaasConfigArray -Name "AdobeAcrobatProTrustedPublisherFragments" -Default @("Adobe", "Adobe Inc."))
$AdobeCleanerToolUrl = [string](Resolve-ZiaasConfigValue -Name "AdobeCleanerToolUrl" -Default "https://ardownload2.adobe.com/pub/adobe/acrobat/win/AcrobatDC/2100120135/x64/AdobeAcroCleaner_DC2021.exe")
$LeapInstallerPath = [string](Resolve-ZiaasConfigValue -Name "LeapInstallerPath" -Default "")
$LeapInstallerUrl = [string](Resolve-ZiaasConfigValue -Name "LeapInstallerUrl" -Default "")
$LeapDownloadsPageUrl = [string](Resolve-ZiaasConfigValue -Name "LeapDownloadsPageUrl" -Default "https://community.leap.co.uk/s/downloads")
$LeapInstallerSearchRoots = [string[]]@(Resolve-ZiaasConfigArray -Name "LeapInstallerSearchRoots" -Default @("$env:USERPROFILE\Downloads", "$env:PUBLIC\Downloads", "$env:SystemDrive\Installers", "$env:SystemDrive\Temp", "$env:ProgramData\ZiAAS_Woodstock_Baselining\Downloads"))
$AllowLocalLeapInstallerFallback = Resolve-ZiaasConfigBool -Name "AllowLocalLeapInstallerFallback" -Default $false
$LeapInstallArguments = [string[]]@(Resolve-ZiaasConfigArray -Name "LeapInstallArguments" -Default @())
$LeapTrustedPublisherFragments = [string[]]@(Resolve-ZiaasConfigArray -Name "LeapTrustedPublisherFragments" -Default @("LEAP"))
$PostCleanupWaitSeconds = [int](Resolve-ZiaasConfigValue -Name "PostCleanupWaitSeconds" -Default 60)
$PreLeapWaitSeconds = [int](Resolve-ZiaasConfigValue -Name "PreLeapWaitSeconds" -Default 60)
$DownloadRetryCount = [int](Resolve-ZiaasConfigValue -Name "DownloadRetryCount" -Default 3)
$DownloadRetryDelaySeconds = [int](Resolve-ZiaasConfigValue -Name "DownloadRetryDelaySeconds" -Default 5)
$ComponentName = [string](Resolve-ZiaasConfigValue -Name "ComponentName" -Default "ZiAAS_Woodstock_Baselining")
$ZiaasRunStamp = [string](Resolve-ZiaasConfigValue -Name "RunStamp" -Default (Get-Date -Format "yyyyMMdd-HHmmss-fff"))

if ($DownloadRetryCount -lt 1) { $DownloadRetryCount = 1 }
if ($DownloadRetryDelaySeconds -lt 0) { $DownloadRetryDelaySeconds = 0 }

$Script:InstallModeParameterWasUsed = Resolve-ZiaasConfigBool -Name "InstallModeParameterWasUsed" -Default ($InstallMode -ne "Prompt")
$Script:SkipOfficeParameterWasUsed = Resolve-ZiaasConfigBool -Name "SkipOfficeParameterWasUsed" -Default $false
$Script:SkipAdobeParameterWasUsed = Resolve-ZiaasConfigBool -Name "SkipAdobeParameterWasUsed" -Default $false

$Script:StartTime = Get-Date
$Script:Root = $WorkingRoot
$Script:DownloadDir = Join-Path $Script:Root "Downloads"
$Script:OfficeDir = Join-Path $Script:Root "OfficeODT"
$Script:LogDir = Join-Path $Script:Root "Logs"
$Script:BackupDir = Join-Path $Script:Root "Backups"
$Script:RunStamp = $ZiaasRunStamp
$Script:LogFile = Join-Path $Script:LogDir "$ComponentName-$Script:RunStamp.log"
$Script:RebootRequired = $false
$Script:LastProcessExitCode = 0
$Script:UserHiveEnumerationIncomplete = $false
$Script:SimulationAdobeProductsRemoved = Resolve-ZiaasConfigBool -Name "SimulationAdobeProductsRemoved" -Default $false
$Script:SimulationLeapProductsRemoved = Resolve-ZiaasConfigBool -Name "SimulationLeapProductsRemoved" -Default $false
$Script:SimulationLeapInstalled = Resolve-ZiaasConfigBool -Name "SimulationLeapInstalled" -Default $false
$Script:AutoDiscoveredLeapInstallerPath = $null
$Script:ResolvedLeapInstallerUrl = $null
$Script:ResolvedLeapInstallerVersion = $null
$Script:ResolvedLeapInstallerFileName = $null
$Script:LeapResidualMoved = 0
$Script:LeapResidualRenamed = 0
$Script:LeapResidualSkipped = 0
$Script:LeapResidualPreserved = 0
$Script:LeapResidualErrors = 0
if ($LogLevel -notin @("Debug", "Info", "Warn")) {
    $LogLevel = "Info"
}
if ($OfficeProductId -notin @("O365ProPlusRetail", "O365ProPlusEEANoTeamsRetail")) {
    throw "Unsupported Office product ID '$OfficeProductId'. Only Microsoft enterprise product IDs O365ProPlusRetail and O365ProPlusEEANoTeamsRetail are allowed."
}

function Initialize-DeploymentFolders {
    foreach ($path in @($Script:Root, $Script:DownloadDir, $Script:OfficeDir, $Script:LogDir, $Script:BackupDir)) {
        if (-not (Test-Path -LiteralPath $path)) {
            New-Item -Path $path -ItemType Directory -Force | Out-Null
        }
    }
}

function Test-ZiaasConsoleLogEnabled {
    param([Parameter(Mandatory = $true)][string]$Level)

    if ($Quiet -and $Level -notin @("ERROR", "SUCCESS")) {
        return $false
    }

    $rank = @{
        "DEBUG" = 0
        "INFO" = 1
        "SUCCESS" = 1
        "WARN" = 2
        "ERROR" = 3
    }
    $threshold = @{
        "Debug" = 0
        "Info" = 1
        "Warn" = 2
    }[$LogLevel]

    return ($rank[$Level] -ge $threshold)
}

function Write-Log {
    param(
        [Parameter(Mandatory = $true)][string]$Message,
        [ValidateSet("DEBUG", "INFO", "WARN", "ERROR", "SUCCESS")][string]$Level = "INFO"
    )

    $line = "{0} [{1}] {2}" -f (Get-Date -Format "yyyy-MM-dd HH:mm:ss"), $Level, $Message
    if (Test-ZiaasConsoleLogEnabled -Level $Level) {
        if ($NoColor) {
            Write-Host $line
        }
        else {
            $color = switch ($Level) {
                "ERROR" { "Red" }
                "WARN" { "Yellow" }
                "SUCCESS" { "Green" }
                "DEBUG" { "DarkGray" }
                default { "Gray" }
            }
            Write-Host $line -ForegroundColor $color
        }
    }
    Add-Content -LiteralPath $Script:LogFile -Value $line
}

function Assert-ZiaasSafePath {
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [Parameter(Mandatory = $true)][string[]]$AllowedRoots,
        [Parameter(Mandatory = $true)][string]$Purpose
    )

    if ([string]::IsNullOrWhiteSpace($Path)) {
        throw "Refusing $Purpose because the target path is blank."
    }

    $fullPath = [System.IO.Path]::GetFullPath($Path)
    $allowed = $false
    foreach ($root in @($AllowedRoots | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })) {
        $fullRoot = [System.IO.Path]::GetFullPath($root).TrimEnd('\')
        if ($fullPath.Equals($fullRoot, [System.StringComparison]::OrdinalIgnoreCase) -or
            $fullPath.StartsWith("$fullRoot\", [System.StringComparison]::OrdinalIgnoreCase)) {
            $allowed = $true
            break
        }
    }

    if (-not $allowed) {
        throw "Refusing $Purpose outside approved cleanup roots. Target: $fullPath"
    }
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

function Write-AdobeAcrobatProPrerequisiteNotice {
    Write-Host ""
    Write-Host "Adobe Acrobat Pro selected." -ForegroundColor Yellow
    Write-Host "Acrobat Pro is licensed software; this tool cannot automatically download it like Reader." -ForegroundColor Yellow
    Write-Host "Before continuing, supply a licensed enterprise Pro installer/package with -AdobeAcrobatProInstallerPath or -AdobeAcrobatProInstallerUrl." -ForegroundColor Yellow
    Write-Host "Also supply silent install arguments, including LANG_LIST=en_GB where applicable." -ForegroundColor Yellow
    Write-Host "The Adobe cleanup step removes existing Reader/Acrobat first, so an already-installed copy is not a reinstall source." -ForegroundColor Yellow
}

function New-AdobeProductSelection {
    param(
        [Parameter(Mandatory = $true)][ValidateSet("Reader", "AcrobatPro")][string]$Product
    )

    $label = if ($Product -eq "Reader") { "Adobe Acrobat Reader" } else { "Adobe Acrobat Pro" }

    return [pscustomobject]@{
        Product = $Product
        Label = $label
    }
}

function Confirm-AdobeAcrobatProInteractiveSelection {
    Write-AdobeAcrobatProPrerequisiteNotice
    $confirmation = Read-Host "Type PRO to confirm the licensed Pro installer/package details are ready, or press Enter to choose again"
    return ($confirmation -ieq "PRO")
}

function Resolve-AdobeProductSelection {
    param([Parameter(Mandatory = $true)][bool]$InstallAdobe)

    if (-not $InstallAdobe) {
        return $null
    }

    switch ($AdobeProduct) {
        "Reader" {
            return New-AdobeProductSelection -Product "Reader"
        }
        "AcrobatPro" {
            Write-AdobeAcrobatProPrerequisiteNotice
            return New-AdobeProductSelection -Product "AcrobatPro"
        }
        "Prompt" {
            Write-Host ""
            Write-Host "Choose Adobe product:"
            Write-Host "  1. Adobe Acrobat Reader"
            Write-Host "  2. Adobe Acrobat Pro (licensed installer/package required)"
            Write-Host ""

            while ($true) {
                do {
                    $choice = Read-Host "Enter 1 or 2"
                } until ($choice -in @("1", "2"))

                switch ($choice) {
                    "1" {
                        return New-AdobeProductSelection -Product "Reader"
                    }
                    "2" {
                        if (Confirm-AdobeAcrobatProInteractiveSelection) {
                            return New-AdobeProductSelection -Product "AcrobatPro"
                        }

                        Write-Host ""
                        Write-Host "Acrobat Pro was not confirmed. Choose Reader or Pro again." -ForegroundColor Yellow
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
        [string]$WorkingDirectory,
        [ValidateRange(1, 86400)]
        [int]$TimeoutSeconds = 7200,
        [ValidateSet("Hidden", "Normal", "Minimized", "Maximized")]
        [string]$WindowStyle = "Hidden",
        [scriptblock]$WhileRunning
    )

    $displayArgs = $ArgumentList -join " "
    Write-Log "$Description started."
    Write-Log "Command: `"$FilePath`" $displayArgs"

    if ($Simulation) {
        Write-Log "SIMULATION: Would run process and treat exit code as 0."
        Write-Log "$Description finished with exit code 0."
        $Script:LastProcessExitCode = 0
        return
    }

    $startInfo = @{
        FilePath = $FilePath
        PassThru = $true
        WindowStyle = $WindowStyle
    }
    if ($ArgumentList.Count -gt 0) {
        $startInfo.ArgumentList = $ArgumentList
    }
    if ($WorkingDirectory) {
        $startInfo.WorkingDirectory = $WorkingDirectory
    }

    $process = Start-Process @startInfo
    Write-Log "$Description process ID: $($process.Id); timeout: $TimeoutSeconds seconds."
    if ($WhileRunning) {
        $deadline = (Get-Date).AddSeconds($TimeoutSeconds)
        $finished = $false
        do {
            if ($process.HasExited) {
                $finished = $true
                break
            }

            try {
                [void](& $WhileRunning)
            }
            catch {
                Write-Log "Process monitor callback failed for $Description. $($_.Exception.Message)" "WARN"
            }

            if ((Get-Date) -ge $deadline) {
                break
            }
            Start-Sleep -Milliseconds 250
        } while ($true)
    }
    else {
        $finished = $process.WaitForExit($TimeoutSeconds * 1000)
    }
    if (-not $finished) {
        Write-Log "$Description exceeded its $TimeoutSeconds second timeout. Terminating process tree $($process.Id)." "ERROR"
        try {
            & "$env:SystemRoot\System32\taskkill.exe" /PID $process.Id /T /F 2>&1 | ForEach-Object { Write-Log "taskkill: $_" "WARN" }
        }
        catch {
            Write-Log "Process-tree termination was unavailable for $($process.Id). $($_.Exception.Message)" "WARN"
        }
        $process.Refresh()
        if (-not $process.HasExited) {
            try {
                $process.Kill()
                $process.WaitForExit(5000) | Out-Null
                Write-Log "Terminated timed-out parent process $($process.Id) through its process handle." "WARN"
            }
            catch {
                Write-Log "Could not terminate timed-out parent process $($process.Id). $($_.Exception.Message)" "ERROR"
            }
        }
        $process.Refresh()
        if (-not $process.HasExited) {
            throw "$Description timed out after $TimeoutSeconds seconds and process $($process.Id) could not be terminated. Stop it manually before rerunning."
        }
        $timeoutException = New-Object System.TimeoutException("$Description timed out after $TimeoutSeconds seconds. Its process was terminated and no later deployment step was started.")
        $timeoutException.Data["ZiaasTimedOutProcessId"] = [int]$process.Id
        throw $timeoutException
    }
    $process.WaitForExit()
    $exitCode = $process.ExitCode
    $Script:LastProcessExitCode = [int]$exitCode
    Write-Log "$Description finished with exit code $exitCode."

    if ($exitCode -eq 3010) {
        $Script:RebootRequired = $true
        Write-Log "$Description requested a reboot." "WARN"
    }

    if ($SuccessExitCodes -notcontains $exitCode) {
        throw "$Description failed with exit code $exitCode. See $Script:LogFile."
    }

}

function Get-AdobeAcrobatProInstallArgumentList {
    $arguments = @($AdobeAcrobatProInstallArguments | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
    if (-not [string]::IsNullOrWhiteSpace($AdobeAcrobatProInstallArgumentLine)) {
        $arguments += $AdobeAcrobatProInstallArgumentLine.Trim()
    }

    return [string[]]$arguments
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

function Invoke-WebRequestWithRetry {
    param(
        [Parameter(Mandatory = $true)][string]$Uri,
        [string]$OutFile,
        [int]$TimeoutSec = 120,
        [string]$Description = "Web request"
    )

    $null = Assert-HttpsUrl -Url $Uri -Description $Description
    $attemptLimit = [Math]::Max(1, $DownloadRetryCount)
    $lastError = $null
    for ($attempt = 1; $attempt -le $attemptLimit; $attempt++) {
        try {
            if ($attempt -gt 1) {
                Write-Log "Retrying $Description ($attempt of $attemptLimit)."
            }

            if ([string]::IsNullOrWhiteSpace($OutFile)) {
                return Invoke-WebRequest -Uri $Uri -UseBasicParsing -TimeoutSec $TimeoutSec
            }

            Invoke-WebRequest -Uri $Uri -OutFile $OutFile -UseBasicParsing -TimeoutSec $TimeoutSec
            return $null
        }
        catch {
            $lastError = $_.Exception.Message
            if ($attempt -ge $attemptLimit) {
                break
            }

            Write-Log "$Description attempt $attempt failed. Retrying in $DownloadRetryDelaySeconds seconds. $lastError" "WARN"
            if ($DownloadRetryDelaySeconds -gt 0) {
                Start-Sleep -Seconds $DownloadRetryDelaySeconds
            }
        }
    }

    throw "$Description failed after $attemptLimit attempt(s). Last error: $lastError"
}

function Assert-RemoteUrlReachable {
    param(
        [Parameter(Mandatory = $true)][string]$Url,
        [Parameter(Mandatory = $true)][string]$Description
    )

    $uri = Assert-HttpsUrl -Url $Url -Description $Description
    if ($Simulation) {
        Write-Log "SIMULATION: Would test $Description URL reachability: $($uri.GetLeftPart([UriPartial]::Path))"
        return
    }

    $lastError = $null
    for ($attempt = 1; $attempt -le [Math]::Max(1, $DownloadRetryCount); $attempt++) {
        $response = $null
        try {
            $request = [System.Net.HttpWebRequest]::Create($uri)
            $request.Method = "HEAD"
            $request.AllowAutoRedirect = $true
            $request.Timeout = 30000
            $request.ReadWriteTimeout = 30000
            $request.UserAgent = "ZiAAS-Woodstock-Baselining"
            $response = [System.Net.HttpWebResponse]$request.GetResponse()
            $statusCode = [int]$response.StatusCode
            if (($statusCode -ge 200 -and $statusCode -lt 400) -or $statusCode -eq 405) {
                Write-Log "$Description URL reachability passed with HTTP $statusCode."
                return
            }
            throw "HTTP $statusCode"
        }
        catch [System.Net.WebException] {
            $webResponse = $_.Exception.Response
            if ($webResponse -and [int]$webResponse.StatusCode -eq 405) {
                Write-Log "$Description endpoint is reachable and does not support HEAD (HTTP 405); the staging gate will verify the GET download."
                return
            }
            $lastError = $_.Exception.Message
        }
        catch {
            $lastError = $_.Exception.Message
        }
        finally {
            if ($response) { $response.Close() }
        }

        if ($attempt -lt [Math]::Max(1, $DownloadRetryCount) -and $DownloadRetryDelaySeconds -gt 0) {
            Start-Sleep -Seconds $DownloadRetryDelaySeconds
        }
    }
    throw "$Description URL was not reachable after $([Math]::Max(1, $DownloadRetryCount)) attempt(s). Last error: $lastError"
}

function Get-ZiaasStagingManifestPath {
    return (Join-Path (Join-Path $Script:Root "RunState") "staged-installers-$Script:RunStamp.json")
}

function Write-ZiaasStagingManifest {
    param(
        [string[]]$Files = @(),
        [string]$OfficePayloadPath = ""
    )

    $runStateDir = Join-Path $Script:Root "RunState"
    if (-not (Test-Path -LiteralPath $runStateDir)) {
        New-Item -Path $runStateDir -ItemType Directory -Force | Out-Null
    }

    $fileRecords = @()
    foreach ($path in @($Files | Where-Object { -not [string]::IsNullOrWhiteSpace($_) } | Select-Object -Unique)) {
        if (-not (Test-Path -LiteralPath $path -PathType Leaf)) {
            throw "Cannot register missing staged installer file: $path"
        }
        $item = Get-Item -LiteralPath $path
        $fileRecords += [pscustomobject]@{
            Path = $item.FullName
            Bytes = [int64]$item.Length
            Sha256 = (Get-FileHash -LiteralPath $item.FullName -Algorithm SHA256).Hash
        }
    }

    $officePayload = [ordered]@{ Ready = $false; Path = ""; FileCount = 0; TotalBytes = 0 }
    if (-not [string]::IsNullOrWhiteSpace($OfficePayloadPath)) {
        if ($Simulation) {
            $officePayload = [ordered]@{ Ready = $true; Path = $OfficePayloadPath; FileCount = 1; TotalBytes = 1 }
        }
        elseif (Test-Path -LiteralPath $OfficePayloadPath -PathType Container) {
            $payloadFiles = @(Get-ChildItem -LiteralPath $OfficePayloadPath -Recurse -File -ErrorAction SilentlyContinue)
            $payloadBytes = [int64]0
            foreach ($payloadFile in $payloadFiles) { $payloadBytes += [int64]$payloadFile.Length }
            $officePayload = [ordered]@{
                Ready = ($payloadFiles.Count -gt 0 -and $payloadBytes -gt 100MB)
                Path = (Resolve-Path -LiteralPath $OfficePayloadPath).Path
                FileCount = $payloadFiles.Count
                TotalBytes = $payloadBytes
            }
        }
    }

    $manifest = [ordered]@{
        RunStamp = $Script:RunStamp
        Created = (Get-Date).ToString("s")
        Files = $fileRecords
        OfficePayload = $officePayload
    }
    $manifestPath = Get-ZiaasStagingManifestPath
    $manifest | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath $manifestPath -Encoding UTF8
    Write-Log "Wrote verified installer staging manifest: $manifestPath"
    return $manifestPath
}

function Test-ZiaasStagedInstallerFile {
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [int64]$MinimumBytes = 1
    )

    $manifestPath = Get-ZiaasStagingManifestPath
    if (-not (Test-Path -LiteralPath $manifestPath -PathType Leaf) -or -not (Test-Path -LiteralPath $Path -PathType Leaf)) {
        return $false
    }

    try {
        $manifest = Get-Content -LiteralPath $manifestPath -Raw | ConvertFrom-Json
        if ([string]$manifest.RunStamp -ne $Script:RunStamp) { return $false }
        $resolvedPath = (Resolve-Path -LiteralPath $Path).Path
        $record = @($manifest.Files | Where-Object { [string]$_.Path -ieq $resolvedPath } | Select-Object -First 1)
        if ($record.Count -eq 0) { return $false }
        $item = Get-Item -LiteralPath $resolvedPath
        if ($item.Length -lt $MinimumBytes -or [int64]$record[0].Bytes -ne [int64]$item.Length) { return $false }
        $actualHash = (Get-FileHash -LiteralPath $resolvedPath -Algorithm SHA256).Hash
        if ($actualHash -ine [string]$record[0].Sha256) { return $false }
        Write-Log "Reusing installer verified during this run's staging gate: $resolvedPath"
        return $true
    }
    catch {
        Write-Log "Staged installer validation failed and the file will be downloaded again. $($_.Exception.Message)" "WARN"
        return $false
    }
}

function Test-ZiaasStagedOfficePayload {
    $manifestPath = Get-ZiaasStagingManifestPath
    if (-not (Test-Path -LiteralPath $manifestPath -PathType Leaf)) { return $false }
    try {
        $manifest = Get-Content -LiteralPath $manifestPath -Raw | ConvertFrom-Json
        if ([string]$manifest.RunStamp -ne $Script:RunStamp -or -not [bool]$manifest.OfficePayload.Ready) { return $false }
        if ($Simulation) { return $true }
        $path = [string]$manifest.OfficePayload.Path
        if (-not (Test-Path -LiteralPath $path -PathType Container)) { return $false }
        $files = @(Get-ChildItem -LiteralPath $path -Recurse -File -ErrorAction SilentlyContinue)
        $bytes = [int64]0
        foreach ($file in $files) { $bytes += [int64]$file.Length }
        return ($files.Count -ge [int]$manifest.OfficePayload.FileCount -and $bytes -ge [int64]$manifest.OfficePayload.TotalBytes -and $bytes -gt 100MB)
    }
    catch {
        Write-Log "Staged Office payload validation failed. $($_.Exception.Message)" "WARN"
        return $false
    }
}

function Save-Download {
    param(
        [Parameter(Mandatory = $true)][string]$Url,
        [Parameter(Mandatory = $true)][string]$Destination,
        [int64]$MinimumBytes = 1024,
        [switch]$AlwaysDownload
    )

    $null = Assert-HttpsUrl -Url $Url -Description "Installer download"
    if (Test-ZiaasStagedInstallerFile -Path $Destination -MinimumBytes $MinimumBytes) {
        return
    }

    if (Test-Path -LiteralPath $Destination) {
        $existingLength = (Get-Item -LiteralPath $Destination).Length
        if ((-not $AlwaysDownload) -and $UseCachedInstallers -and ($existingLength -ge $MinimumBytes)) {
            Write-Log "Using cached installer after size preflight: $Destination"
            return
        }

        if ($UseCachedInstallers -and ($existingLength -lt $MinimumBytes)) {
            Write-Log "Cached file is too small and will be refreshed: $Destination" "WARN"
        }
        elseif (-not $UseCachedInstallers) {
            Write-Log "Refreshing installer/cache file because -UseCachedInstallers was not supplied: $Destination" "DEBUG"
        }
        else {
            Write-Log "Refreshing existing download: $Destination"
        }
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
    $attemptLimit = [Math]::Max(1, $DownloadRetryCount)
    $lastError = $null
    for ($attempt = 1; $attempt -le $attemptLimit; $attempt++) {
        if (Test-Path -LiteralPath $tmp) {
            Remove-Item -LiteralPath $tmp -Force
        }

        try {
            if ($attempt -gt 1) {
                Write-Log "Retrying download ($attempt of $attemptLimit): $Url"
            }

            try {
                Start-BitsTransfer -Source $Url -Destination $tmp -ErrorAction Stop
            }
            catch {
                Write-Log "BITS download failed, falling back to direct web download. $($_.Exception.Message)" "WARN"
                Invoke-WebRequest -Uri $Url -OutFile $tmp -UseBasicParsing -TimeoutSec 120
            }

            $downloaded = Get-Item -LiteralPath $tmp
            if ($downloaded.Length -lt $MinimumBytes) {
                throw "Downloaded file is unexpectedly small: $tmp"
            }

            Move-Item -LiteralPath $tmp -Destination $Destination -Force
            Write-Log "Downloaded to $Destination ($($downloaded.Length) bytes)."
            return
        }
        catch {
            $lastError = $_.Exception.Message
            if ($attempt -ge $attemptLimit) {
                break
            }

            Write-Log "Download attempt $attempt failed. Retrying in $DownloadRetryDelaySeconds seconds. $lastError" "WARN"
            if ($DownloadRetryDelaySeconds -gt 0) {
                Start-Sleep -Seconds $DownloadRetryDelaySeconds
            }
        }
    }

    if (Test-Path -LiteralPath $tmp) {
        Remove-Item -LiteralPath $tmp -Force -ErrorAction SilentlyContinue
    }

    throw "Download failed after $attemptLimit attempt(s): $Url. Last error: $lastError"
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
        $escapedFragment = [regex]::Escape([string]$fragment)
        if ($subject -match "(?i)(^|[^A-Za-z0-9])$escapedFragment([^A-Za-z0-9]|$)") {
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
            $escapedFragment = [regex]::Escape([string]$fragment)
            if ($subject -match "(?i)(^|[^A-Za-z0-9])$escapedFragment([^A-Za-z0-9]|$)") {
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

    $null = Assert-HttpsUrl -Url $Url -Description "Remote filename request"
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
        if ((-not [string]::IsNullOrWhiteSpace($fileName)) -and $fileName -ne "Unnamed") {
            return $fileName
        }

        if ($fileName -eq "Unnamed") {
            Write-Log "Remote filename header was blank; using fallback filename $FallbackFileName." "WARN"
        }
    }
    catch {
        Write-Log "Could not read remote filename from download headers. $($_.Exception.Message)" "WARN"
    }

    return $FallbackFileName
}

function Assert-HttpsUrl {
    param(
        [Parameter(Mandatory = $true)][string]$Url,
        [Parameter(Mandatory = $true)][string]$Description
    )

    $uri = $null
    if (-not [Uri]::TryCreate($Url, [UriKind]::Absolute, [ref]$uri)) {
        throw "$Description URL is not a valid absolute URL."
    }
    if ($uri.Scheme -ne "https") {
        throw "$Description URL must use HTTPS."
    }
    return $uri
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

    $candidates = New-Object System.Collections.Generic.List[object]
    $labelledMatch = [regex]::Match(
        $normalized,
        '(?is)"label"\s*:\s*\{[^}]*"value"\s*:\s*"Download\s+LEAP\s+Desktop".*?"url"\s*:\s*\{[^}]*"value"\s*:\s*"(?<url>https://leaphome\.sharepoint\.com[^"]+)"'
    )
    if ($labelledMatch.Success) {
        $labelUrl = $labelledMatch.Groups["url"].Value
        $labelVersionMatch = [regex]::Match($labelUrl, '(?<version>\d+(?:\.\d+){2,3})')
        $labelVersion = if ($labelVersionMatch.Success) { $labelVersionMatch.Groups["version"].Value } else { $version }
        $candidates.Add([pscustomobject]@{ Url = $labelUrl; Version = $labelVersion })
    }

    $anchorMatch = [regex]::Match(
        $normalized,
        '(?is)<a[^>]+href="(?<url>https://leaphome\.sharepoint\.com[^"]+)"[^>]*>\s*Download\s+LEAP\s+Desktop\s*</a>'
    )
    if ($anchorMatch.Success) {
        $anchorUrl = $anchorMatch.Groups["url"].Value
        $anchorVersionMatch = [regex]::Match($anchorUrl, '(?<version>\d+(?:\.\d+){2,3})')
        $anchorVersion = if ($anchorVersionMatch.Success) { $anchorVersionMatch.Groups["version"].Value } else { $version }
        $candidates.Add([pscustomobject]@{ Url = $anchorUrl; Version = $anchorVersion })
    }

    # Salesforce/Aura has changed the shape of this page more than once. Keep
    # the extraction broad enough for the labelled link, but keep the trust
    # boundary narrow: the final file is still required to be HTTPS and
    # Authenticode-signed by LEAP before it can be staged or executed.
    $urlMatches = [regex]::Matches($normalized, 'https://(?:leaphome\.sharepoint\.com|community\.leap\.co\.uk)[^"''<>\s\\]+')
    foreach ($match in $urlMatches) {
        $start = [Math]::Max(0, $match.Index - 800)
        $length = [Math]::Min(1600, $normalized.Length - $start)
        $nearbyText = $normalized.Substring($start, $length)
        $looksLikeDownload = $match.Value -match '(?i)(?:\.exe|\.msi)(?:\?|$)|/download|download\.aspx' -or
            $nearbyText -match '(?i)Download\s+LEAP\s+Desktop|LEAPDesktopX64setup|LEAP\s+Desktop'
        if ($looksLikeDownload -and ($nearbyText -notmatch '(?i)System\s+Audit') -and ($match.Value -notmatch '(?i)/s/downloads(?:[?#]|$)')) {
            $urlVersionMatch = [regex]::Match($match.Value, '(?<version>\d+(?:\.\d+){2,3})')
            # Prefer a version embedded in the candidate URL. The page-level
            # "Latest Version" label describes the page, not necessarily the
            # first URL emitted by an Aura payload containing older links.
            $candidateVersion = if ($urlVersionMatch.Success) { $urlVersionMatch.Groups["version"].Value } else { $version }
            $candidates.Add([pscustomobject]@{ Url = $match.Value; Version = $candidateVersion })
        }
    }

    $uniqueCandidates = @($candidates | Group-Object Url | ForEach-Object { $_.Group | Select-Object -First 1 })
    if ($uniqueCandidates.Count -eq 0) {
        return $null
    }

    $ranked = foreach ($candidate in $uniqueCandidates) {
        $sortVersion = [Version]"0.0.0.0"
        $versionText = [string]$candidate.Version
        $versionNumber = [regex]::Match($versionText, '^\d+(?:\.\d+){1,3}')
        if ($versionNumber.Success) {
            try { $sortVersion = [Version]::Parse($versionNumber.Value) } catch { }
        }
        [pscustomobject]@{ Url = $candidate.Url; Version = $candidate.Version; SortVersion = $sortVersion }
    }

    return ($ranked | Sort-Object SortVersion -Descending | Select-Object -First 1 | Select-Object Url, Version)
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
    $pageUrls = @(
        $LeapDownloadsPageUrl,
        ($LeapDownloadsPageUrl + $(if ($LeapDownloadsPageUrl -match '\?') { '&' } else { '?' }) + "ziaas_refresh=$([DateTime]::UtcNow.Ticks)")
    )
    $pageContent = $null
    $directInfo = $null
    foreach ($pageUrl in $pageUrls) {
        $pageResponse = Invoke-WebRequestWithRetry -Uri $pageUrl -TimeoutSec 60 -Description "LEAP downloads page request"
        $pageContent = $pageResponse.Content
        $directInfo = Get-LeapInstallerLinkFromContent -Content $pageContent
        if ($directInfo) {
            break
        }
        Write-Log "LEAP downloads page response did not expose the installer link yet; trying a cache-busted page request." "WARN"
    }

    if ($directInfo) {
        $directUri = Assert-HttpsUrl -Url $directInfo.Url -Description "LEAP installer"
        if ($directUri.Host -notin @("leaphome.sharepoint.com", "community.leap.co.uk")) {
            throw "LEAP downloads page returned an installer link from an unapproved host: $($directUri.Host)"
        }
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
    $bootstrapResponse = Invoke-WebRequestWithRetry -Uri $bootstrapUrl -TimeoutSec 60 -Description "LEAP downloads bootstrap request"
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
    $componentResponse = Invoke-WebRequestWithRetry -Uri $componentUrl -TimeoutSec 60 -Description "LEAP downloads component request"
    $componentInfo = Get-LeapInstallerLinkFromContent -Content $componentResponse.Content
    if (-not $componentInfo) {
        throw "Could not find the Download LEAP Desktop installer link on the official LEAP downloads page."
    }

    $componentUri = Assert-HttpsUrl -Url $componentInfo.Url -Description "LEAP installer"
    if ($componentUri.Host -notin @("leaphome.sharepoint.com", "community.leap.co.uk")) {
        throw "LEAP downloads component returned an installer link from an unapproved host: $($componentUri.Host)"
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
    param(
        [string[]]$ProcessNames,
        [string[]]$AutoForceProcessNames = @()
    )

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

    if ($stillRunning.Count -gt 0 -and $AutoForceProcessNames.Count -gt 0) {
        $autoForceSet = @{}
        foreach ($name in $AutoForceProcessNames) {
            if (-not [string]::IsNullOrWhiteSpace($name)) {
                $autoForceSet[$name.ToLowerInvariant()] = $true
            }
        }

        $autoForceRunning = @($stillRunning | Where-Object { $autoForceSet.ContainsKey($_.ProcessName.ToLowerInvariant()) })
        if ($autoForceRunning.Count -gt 0) {
            $autoForceNames = ($autoForceRunning | Select-Object -ExpandProperty ProcessName -Unique | Sort-Object) -join ", "
            Write-Log "Force-closing known background/helper processes after normal close timeout: $autoForceNames" "WARN"
            foreach ($process in $autoForceRunning) {
                Stop-Process -Id $process.Id -Force -ErrorAction SilentlyContinue
            }

            Start-Sleep -Seconds 5
            $stillRunning = @()
            foreach ($name in $ProcessNames) {
                $stillRunning += @(Get-Process -Name $name -ErrorAction SilentlyContinue)
            }
        }
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
    <Product ID="$OfficeProductId">
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

function Invoke-OfficeInstall {
    param([Parameter(Mandatory = $true)]$Assets)

    if (Test-ZiaasStagedOfficePayload) {
        Write-Log "Using Office installation payload verified by the pre-cleanup staging gate."
    }
    else {
        Invoke-ProcessChecked `
            -FilePath $Assets.Setup `
            -ArgumentList @("/download", $Assets.InstallConfig) `
            -Description "Microsoft 365 Apps installation file download" `
            -WorkingDirectory $Script:OfficeDir
    }

    Invoke-ProcessChecked `
        -FilePath $Assets.Setup `
        -ArgumentList @("/configure", $Assets.InstallConfig) `
        -Description "Microsoft 365 Apps for enterprise installation" `
        -WorkingDirectory $Script:OfficeDir

    if ($Simulation) {
        Write-Log "SIMULATION: Office Click-to-Run ProductReleaseIds: $OfficeProductId"
        Write-Log "SIMULATION: Office Platform: x64"
        Write-Log "SIMULATION: Office ClientCulture: en-gb"
        Write-Log "SIMULATION: Office UpdateChannel: SemiAnnual"
        return
    }

    $configKey = "HKLM:\SOFTWARE\Microsoft\Office\ClickToRun\Configuration"
    if (Test-Path -LiteralPath $configKey) {
        $cfg = Get-ItemProperty -LiteralPath $configKey
        $productReleaseIds = [string](Get-ObjectPropertyValue -InputObject $cfg -Name 'ProductReleaseIds')
        $platform = [string](Get-ObjectPropertyValue -InputObject $cfg -Name 'Platform')
        $clientCulture = [string](Get-ObjectPropertyValue -InputObject $cfg -Name 'ClientCulture')
        $cdnBaseUrl = [string](Get-ObjectPropertyValue -InputObject $cfg -Name 'CDNBaseUrl')
        $updateChannel = [string](Get-ObjectPropertyValue -InputObject $cfg -Name 'UpdateChannel')
        $audienceId = [string](Get-ObjectPropertyValue -InputObject $cfg -Name 'AudienceId')
        $audienceData = [string](Get-ObjectPropertyValue -InputObject $cfg -Name 'AudienceData')
        $versionToReport = [string](Get-ObjectPropertyValue -InputObject $cfg -Name 'VersionToReport')

        Write-Log "Office Click-to-Run ProductReleaseIds: $productReleaseIds"
        Write-Log "Office Platform: $platform"
        Write-Log "Office ClientCulture: $clientCulture"
        Write-Log "Office CDNBaseUrl: $cdnBaseUrl"
        Write-Log "Office UpdateChannel: $updateChannel"
        Write-Log "Office AudienceId: $audienceId"
        Write-Log "Office AudienceData: $audienceData"
        Write-Log "Office VersionToReport: $versionToReport"

        if ($productReleaseIds -notmatch "(?i)(^|;)\s*$([regex]::Escape($OfficeProductId))\s*(;|$)") {
            throw "Office verification failed: expected enterprise ProductReleaseIds to include $OfficeProductId, found '$productReleaseIds'."
        }

        if ($platform -ne "x64") {
            throw "Office verification failed: expected x64 platform, found '$platform'."
        }

        if ($clientCulture -notmatch "(?i)^en-gb$") {
            throw "Office verification failed: expected en-gb client culture, found '$clientCulture'."
        }

        $semiAnnualAudienceId = "7ffbc6bf-bc32-4f92-8982-f9dd17fd3114"
        $monthlyEnterpriseAudienceId = "55336b82-a18d-4dd6-b5f6-9e5095c314a6"
        $channelEvidence = @($audienceId, $audienceData, $updateChannel, $cdnBaseUrl) -join " "
        if ($channelEvidence -match [regex]::Escape($semiAnnualAudienceId)) {
            Write-Log "Verified Office Semi-Annual Enterprise channel audience: $semiAnnualAudienceId"
        }
        elseif ($channelEvidence -match [regex]::Escape($monthlyEnterpriseAudienceId)) {
            $versionBuild = 0
            $versionRevision = 0
            if ($versionToReport -match "^16\.0\.(?<build>\d+)\.(?<revision>\d+)$") {
                $versionBuild = [int]$matches["build"]
                $versionRevision = [int]$matches["revision"]
            }
            $isMicrosoftUnifiedChannelBuild = ($versionBuild -gt 20131) -or ($versionBuild -eq 20131 -and $versionRevision -ge 20000)
            if (-not $isMicrosoftUnifiedChannelBuild) {
                throw "Office verification failed: XML requested Semi-Annual Enterprise, but this pre-unification build reports Monthly Enterprise audience $monthlyEnterpriseAudienceId. Version='$versionToReport', AudienceData='$audienceData'."
            }
            Write-Log "Office requested Semi-Annual Enterprise, but Microsoft unifies SAEC into Monthly Enterprise from Version 2606 (build 20131.20000+) in July 2026. Verified expected unified enterprise audience $monthlyEnterpriseAudienceId for version $versionToReport." "WARN"
        }
        else {
            throw "Office verification failed: Semi-Annual Enterprise channel could not be proven. AudienceId='$audienceId', AudienceData='$audienceData', UpdateChannel='$updateChannel', CDNBaseUrl='$cdnBaseUrl'."
        }
    }
    else {
        throw "Office verification failed: Click-to-Run configuration registry key was not found after install."
    }
}

function Invoke-OfficeDeployment {
    $assets = Get-OfficeDeploymentAssets
    Invoke-OfficeUninstallAndCleanup -Assets $assets
    Invoke-OfficeInstall -Assets $assets
}

function Get-LocalUserProfileRecords {
    $profileListPath = "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\ProfileList\*"
    $usersRoot = [IO.Path]::GetFullPath((Join-Path $env:SystemDrive "Users"))

    foreach ($profileRecord in @(Get-ItemProperty -Path $profileListPath -ErrorAction SilentlyContinue)) {
        $sid = [string](Get-ObjectPropertyValue -InputObject $profileRecord -Name "PSChildName")
        $profileImagePath = [string](Get-ObjectPropertyValue -InputObject $profileRecord -Name "ProfileImagePath")
        if ([string]::IsNullOrWhiteSpace($sid) -or [string]::IsNullOrWhiteSpace($profileImagePath)) {
            continue
        }

        try {
            [void](New-Object Security.Principal.SecurityIdentifier($sid))
            $expandedPath = [Environment]::ExpandEnvironmentVariables($profileImagePath)
            $fullPath = [IO.Path]::GetFullPath($expandedPath).TrimEnd('\')
            if (-not $fullPath.StartsWith("$usersRoot\", [StringComparison]::OrdinalIgnoreCase)) {
                continue
            }
            if (-not (Test-Path -LiteralPath $fullPath -PathType Container)) {
                continue
            }

            [pscustomobject]@{
                Sid = $sid
                LocalPath = $fullPath
                HiveLoaded = Test-Path -LiteralPath "Registry::HKEY_USERS\$sid"
            }
        }
        catch {
            Write-Log "Ignoring invalid or inaccessible local profile record '$sid' at '$profileImagePath'. $($_.Exception.Message)" "DEBUG"
        }
    }
}

function Get-UninstallEntries {
    $paths = @(
        [pscustomobject]@{ Path = "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*"; Scope = "Machine64"; UserSid = $null; UserProfilePath = $null },
        [pscustomobject]@{ Path = "HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*"; Scope = "Machine32"; UserSid = $null; UserProfilePath = $null }
    )

    $profiles = @(Get-LocalUserProfileRecords)
    $loadedUserSids = @($profiles | Where-Object { $_.HiveLoaded } | Select-Object -ExpandProperty Sid -Unique)
    $offlineHiveNames = New-Object System.Collections.Generic.List[string]
    foreach ($profileRecord in @($profiles | Where-Object { $_.HiveLoaded })) {
        $paths += [pscustomobject]@{
            Path = "Registry::HKEY_USERS\$($profileRecord.Sid)\Software\Microsoft\Windows\CurrentVersion\Uninstall\*"
            Scope = "User:$($profileRecord.Sid)"
            UserSid = $profileRecord.Sid
            UserProfilePath = $profileRecord.LocalPath
        }
    }

    # Uninstall entries are commonly written to each user's NTUSER.DAT. Load
    # offline hives briefly so cleanup does not silently miss logged-out users.
    $regExe = Join-Path $env:SystemRoot "System32\reg.exe"
    foreach ($profileRecord in @($profiles | Where-Object { -not $_.HiveLoaded })) {
        $hivePath = Join-Path $profileRecord.LocalPath "NTUSER.DAT"
        if (-not (Test-Path -LiteralPath $hivePath -PathType Leaf)) {
            continue
        }

        $hiveName = "ZiAAS_Offline_$($profileRecord.Sid -replace '[^A-Za-z0-9_]', '_')"
        $hiveRegistryPath = "Registry::HKEY_USERS\$hiveName"
        if (Test-Path -LiteralPath $hiveRegistryPath) {
            $Script:UserHiveEnumerationIncomplete = $true
            Write-Log "Could not safely load offline user hive because the temporary hive key already exists: $hiveName" "WARN"
            continue
        }

        $loadOutput = @(& $regExe LOAD "HKU\$hiveName" $hivePath 2>&1)
        if ($LASTEXITCODE -ne 0) {
            $Script:UserHiveEnumerationIncomplete = $true
            Write-Log "Could not load offline user hive for $($profileRecord.LocalPath). Windows returned $LASTEXITCODE. $($loadOutput -join ' ')" "WARN"
            continue
        }

        $offlineHiveNames.Add($hiveName)
        $paths += [pscustomobject]@{
            Path = "$hiveRegistryPath\Software\Microsoft\Windows\CurrentVersion\Uninstall\*"
            Scope = "User:$($profileRecord.Sid):Offline"
            UserSid = $profileRecord.Sid
            UserProfilePath = $profileRecord.LocalPath
        }
    }

    $currentSid = [Security.Principal.WindowsIdentity]::GetCurrent().User.Value
    if ($loadedUserSids -notcontains $currentSid) {
        $currentProfilePath = [Environment]::GetFolderPath("UserProfile")
        $paths += [pscustomobject]@{ Path = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Uninstall\*"; Scope = "CurrentUser:$currentSid"; UserSid = $currentSid; UserProfilePath = $currentProfilePath }
    }

    try {
        foreach ($location in $paths) {
            Get-ItemProperty -Path $location.Path -ErrorAction SilentlyContinue | ForEach-Object {
                [pscustomobject]@{
                    DisplayName = Get-ObjectPropertyValue -InputObject $_ -Name "DisplayName"
                    DisplayVersion = Get-ObjectPropertyValue -InputObject $_ -Name "DisplayVersion"
                    Publisher = Get-ObjectPropertyValue -InputObject $_ -Name "Publisher"
                    PSChildName = Get-ObjectPropertyValue -InputObject $_ -Name "PSChildName"
                    UninstallString = Get-ObjectPropertyValue -InputObject $_ -Name "UninstallString"
                    QuietUninstallString = Get-ObjectPropertyValue -InputObject $_ -Name "QuietUninstallString"
                    InstallLocation = Get-ObjectPropertyValue -InputObject $_ -Name "InstallLocation"
                    WindowsInstaller = Get-ObjectPropertyValue -InputObject $_ -Name "WindowsInstaller"
                    RegistryPath = Get-ObjectPropertyValue -InputObject $_ -Name "PSPath"
                    Scope = $location.Scope
                    UserSid = $location.UserSid
                    UserProfilePath = $location.UserProfilePath
                }
            }
        }
    }
    finally {
        foreach ($hiveName in $offlineHiveNames) {
            $unloadOutput = @(& $regExe UNLOAD "HKU\$hiveName" 2>&1)
            if ($LASTEXITCODE -ne 0) {
                $Script:UserHiveEnumerationIncomplete = $true
                Write-Log "Could not unload temporary offline user hive $hiveName. $($unloadOutput -join ' ')" "WARN"
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

function Invoke-MsiUninstallWithRetry {
    param(
        [Parameter(Mandatory = $true)][string]$ProductCode,
        [Parameter(Mandatory = $true)][string]$MsiLog,
        [Parameter(Mandatory = $true)][string]$ProductName,
        [string]$VendorLabel = "MSI"
    )

    $maxAttempts = 4
    $uninstallCompleted = $false
    for ($attempt = 1; $attempt -le $maxAttempts; $attempt++) {
        Invoke-ProcessChecked `
            -FilePath "$env:SystemRoot\System32\msiexec.exe" `
            -ArgumentList @("/x", $ProductCode, "/qn", "/norestart", "/L*v", $MsiLog) `
            -SuccessExitCodes @(0, 1605, 1614, 1618, 3010) `
            -Description "$VendorLabel uninstall: $ProductName attempt $attempt of $maxAttempts"
        $exitCode = [int]$Script:LastProcessExitCode

        if ($exitCode -eq 1618) {
            if ($attempt -ge $maxAttempts) {
                throw "$VendorLabel uninstall remained blocked by Windows Installer error 1618 after $maxAttempts attempts. Reboot the machine, confirm no other installer is active, and rerun."
            }

            Write-Log "$VendorLabel uninstall returned Windows Installer error 1618 (another installation is in progress). Waiting 30 seconds before retry $($attempt + 1) of $maxAttempts." "WARN"
            Start-Sleep -Seconds 30
            continue
        }

        $uninstallCompleted = $true
        break
    }

    if (-not $uninstallCompleted) {
        throw "$VendorLabel uninstall did not complete for $ProductName."
    }
}

function Invoke-AdobeMsiUninstallWithRetry {
    param(
        [Parameter(Mandatory = $true)][string]$ProductCode,
        [Parameter(Mandatory = $true)][string]$MsiLog,
        [Parameter(Mandatory = $true)][string]$ProductName
    )

    Invoke-MsiUninstallWithRetry `
        -ProductCode $ProductCode `
        -MsiLog $MsiLog `
        -ProductName $ProductName `
        -VendorLabel "Adobe"
}

function Get-AdobeSafeRemnantEntries {
    if ($Simulation) {
        return @()
    }

    Get-UninstallEntries | Where-Object {
        $_.DisplayName -match "(?i)^Adobe Refresh Manager$"
    } | Sort-Object DisplayName, DisplayVersion -Unique
}

function Remove-AdobeSafeRemnantEntries {
    $entries = @(Get-AdobeSafeRemnantEntries)
    if ($entries.Count -eq 0) {
        Write-Log "No allowlisted Adobe remnant MSI entries found."
        return
    }

    foreach ($entry in $entries) {
        Write-Log "Found allowlisted Adobe remnant: $($entry.DisplayName) $($entry.DisplayVersion)"
        $productCode = Get-MsiProductCode -Entry $entry
        if (-not $productCode) {
            throw "Allowlisted Adobe remnant '$($entry.DisplayName)' has no MSI product code. Refusing to remove it by an unverified command."
        }

        $safeName = ($entry.DisplayName -replace "[^A-Za-z0-9._-]", "_")
        $msiLog = Join-Path $Script:LogDir "Uninstall-$safeName-$Script:RunStamp.log"
        Invoke-AdobeMsiUninstallWithRetry `
            -ProductCode $productCode `
            -MsiLog $msiLog `
            -ProductName ([string]$entry.DisplayName)
    }

    $remaining = @(Get-AdobeSafeRemnantEntries)
    if ($remaining.Count -gt 0) {
        $names = ($remaining | ForEach-Object { "$($_.DisplayName) $($_.DisplayVersion)" }) -join "; "
        throw "Allowlisted Adobe remnants remain after uninstall: $names"
    }
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

        Invoke-AdobeMsiUninstallWithRetry `
            -ProductCode $productCode `
            -MsiLog $msiLog `
            -ProductName ([string]$entry.DisplayName)
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

    Remove-AdobeSafeRemnantEntries

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
            Assert-ZiaasSafePath -Path $dir -AllowedRoots @($env:ProgramFiles, ${env:ProgramFiles(x86)}, $env:ProgramData) -Purpose "Adobe machine-level cleanup"
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

function Get-AdobeReaderInstallerPath {
    $readerFileName = Get-RemoteFileNameFromUrl -Url $AdobeReaderInstallerUrl -FallbackFileName "AcroRdrDCx64_MUI.exe"
    $readerExe = Join-Path $Script:DownloadDir $readerFileName
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

    throw "Acrobat Pro was selected, but no licensed Acrobat Pro installer source was supplied. Provide -AdobeAcrobatProInstallerPath or -AdobeAcrobatProInstallerUrl before starting the run."
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
    $arguments = @(Get-AdobeAcrobatProInstallArgumentList)

    if ($extension -ieq ".msi") {
        $filePath = "$env:SystemRoot\System32\msiexec.exe"
        $arguments = @("/i", $InstallerPath) + $arguments
        $description = "Adobe Acrobat Pro MSI installation"
    }

    if ($arguments.Count -eq 0 -and $Simulation) {
        Write-Log "SIMULATION: No Acrobat Pro install arguments were supplied. A real run would require -AdobeAcrobatProInstallArgumentLine or -AdobeAcrobatProInstallArguments unless -AllowAcrobatProInstallerWithoutArguments is supplied." "WARN"
    }
    elseif ($arguments.Count -eq 0) {
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
    param([Parameter(Mandatory = $true)]$AdobeSelection)

    Write-Log "Applying Adobe Reader/Acrobat enterprise policies."

    if ($Simulation) {
        Write-Log "SIMULATION: Would set bEnableAV2Enterprise=0 and bWhatsNewExp=1 under Adobe FeatureLockDown policy keys."
        if ($AdobeSelection.Product -eq "Reader") {
            Write-Log "SIMULATION: Would enforce Adobe unified-app Reader mode with bIsSCReducedModeEnforcedEx=1."
        }
        else {
            Write-Log "SIMULATION: Would remove any Reader reduced-mode enforcement before Acrobat Pro verification."
        }
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

    $unifiedPolicyPath = "HKLM:\SOFTWARE\Policies\Adobe\Adobe Acrobat\DC\FeatureLockDown"
    if ($AdobeSelection.Product -eq "Reader") {
        New-ItemProperty -LiteralPath $unifiedPolicyPath -Name "bIsSCReducedModeEnforcedEx" -Value 1 -PropertyType DWord -Force | Out-Null
        Write-Log "Enforced Reader-only reduced mode for Adobe's 64-bit unified app at $unifiedPolicyPath"
    }
    else {
        Remove-ItemProperty -LiteralPath $unifiedPolicyPath -Name "bIsSCReducedModeEnforcedEx" -Force -ErrorAction SilentlyContinue
        Write-Log "Removed Reader reduced-mode enforcement for Acrobat Pro deployment."
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

    $policyPath = "HKLM:\SOFTWARE\Policies\Adobe\Adobe Acrobat\DC\FeatureLockDown"

    if ($Simulation) {
        Write-Log "SIMULATION: Would verify bEnableAV2Enterprise=0 under $($AdobeSelection.Label) FeatureLockDown policy."
        if ($AdobeSelection.Product -eq "Reader") {
            Write-Log "SIMULATION: Would verify bIsSCReducedModeEnforcedEx=1 for Reader-only mode."
        }
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

    $reducedModeValue = Get-ObjectPropertyValue -InputObject $policy -Name "bIsSCReducedModeEnforcedEx"
    if ($AdobeSelection.Product -eq "Reader" -and $reducedModeValue -ne 1) {
        throw "Adobe Reader-only reduced mode is not enforced. Expected bIsSCReducedModeEnforcedEx=1, found '$reducedModeValue'."
    }
    if ($AdobeSelection.Product -eq "AcrobatPro" -and $reducedModeValue -eq 1) {
        throw "Acrobat Pro verification failed because Reader reduced mode is still enforced."
    }

    Write-Log "Verified Adobe New Acrobat/Modern Viewer is disabled by policy for $($AdobeSelection.Label)."
    if ($AdobeSelection.Product -eq "Reader") {
        Write-Log "Verified Adobe unified app is locked to Reader-only reduced mode."
    }
}

function Test-AdobeReaderInstallEntry {
    param([Parameter(Mandatory = $true)]$Entry)

    $name = [string]$Entry.DisplayName
    $productCodeText = @($Entry.PSChildName, $Entry.UninstallString, $Entry.QuietUninstallString) -join " "

    if ($name -match "(?i)^Adobe Acrobat Reader(\s|$|\()") {
        return $true
    }

    if ($name -match "(?i)^Adobe Reader(\s|$|\()") {
        return $true
    }

    return ($productCodeText -match "(?i)\{AC76BA86-[0-9A-F]{4}-FF00-7760-BC15014EA700\}")
}

function Test-AdobeUnified64BitInstallEntry {
    param([Parameter(Mandatory = $true)]$Entry)

    $name = [string]$Entry.DisplayName
    $productCodeText = @($Entry.PSChildName, $Entry.UninstallString, $Entry.QuietUninstallString) -join " "
    return (($name -match "(?i)^Adobe Acrobat(\s|$|\()") -and ($productCodeText -match "(?i)\{AC76BA86-" -or $name -match "(?i)64-bit"))
}

function Get-AdobeCurrentUserEntitlementLevel {
    $path = "HKCU:\Software\Adobe\Adobe Acrobat\DC\AVEntitlement"
    if (-not (Test-Path -LiteralPath $path)) {
        return $null
    }

    $value = Get-ObjectPropertyValue -InputObject (Get-ItemProperty -LiteralPath $path) -Name "iEntitlementLevel"
    $parsed = 0
    if ([int]::TryParse([string]$value, [ref]$parsed)) {
        return $parsed
    }
    return $null
}

function Write-AdobeInstallSummary {
    param([Parameter(Mandatory = $true)]$AdobeSelection)

    if ($Simulation) {
        if ($AdobeSelection.Product -eq "AcrobatPro") {
            if ($SimulationAcrobatProEntitlementLevel -eq 200) {
                throw "Adobe Acrobat Pro simulation found a Standard entitlement (200), not Pro (300)."
            }
            if ($SimulationAcrobatProEntitlementLevel -ne 300 -and (-not $AllowAcrobatProEntitlementNotVerified)) {
                throw "Adobe Acrobat Pro simulation could not verify entitlement level 300."
            }
            Write-Log "SIMULATION: Adobe installed entry: Adobe Acrobat Pro from supplied enterprise installer/package."
            if ($SimulationAcrobatProEntitlementLevel -eq 300) {
                Write-Log "SIMULATION: Verified current-user Acrobat Pro entitlement level 300."
            }
        }
        else {
            Write-Log "SIMULATION: Adobe installed entry: 64-bit unified Adobe app locked to Reader mode, MUI requested with LANG_LIST=en_GB (mapped by Adobe to en_US English resources)."
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

    $readerEntries = @($entries | Where-Object { Test-AdobeReaderInstallEntry -Entry $_ })
    $unifiedEntries = @($entries | Where-Object { Test-AdobeUnified64BitInstallEntry -Entry $_ })
    $explicitProEntries = @($entries | Where-Object { [string]$_.DisplayName -match "(?i)^Adobe Acrobat (Pro|Standard)(\s|$|\()" })
    $acrobat64Path = Join-Path $env:ProgramFiles "Adobe\Acrobat DC\Acrobat\Acrobat.exe"
    $readerLegacyX86Path = Join-Path ${env:ProgramFiles(x86)} "Adobe\Acrobat Reader DC\Reader\AcroRd32.exe"
    $reader11X86Path = Join-Path ${env:ProgramFiles(x86)} "Adobe\Reader 11.0\Reader\AcroRd32.exe"
    $acrobatLegacyX86Path = Join-Path ${env:ProgramFiles(x86)} "Adobe\Acrobat DC\Acrobat\Acrobat.exe"
    $entitlementLevel = Get-AdobeCurrentUserEntitlementLevel

    if ($AdobeSelection.Product -eq "Reader") {
        if (($readerEntries.Count + $unifiedEntries.Count) -eq 0) {
            throw "Adobe Reader verification failed: neither a Reader entry nor Adobe's 64-bit unified app entry was found."
        }

        if ($explicitProEntries.Count -gt 0) {
            $names = ($explicitProEntries | ForEach-Object { "$($_.DisplayName) $($_.DisplayVersion)" }) -join "; "
            throw "Adobe Acrobat Pro/Standard product remains installed after Reader deployment: $names"
        }

        if (-not (Test-Path -LiteralPath $acrobat64Path)) {
            throw "Adobe Reader verification failed: expected 64-bit unified executable was not found: $acrobat64Path"
        }
        if ((Test-Path -LiteralPath $readerLegacyX86Path) -or (Test-Path -LiteralPath $reader11X86Path) -or (Test-Path -LiteralPath $acrobatLegacyX86Path)) {
            throw "Adobe Reader verification failed: a legacy 32-bit Adobe executable path remains after x64 deployment."
        }

        $acrobatInstallRoot = Split-Path -Parent $acrobat64Path
        $englishLocalePath = Join-Path $acrobatInstallRoot "Locale\en_US"
        if (-not (Test-Path -LiteralPath $englishLocalePath)) {
            throw "Adobe Reader language verification failed: expected English resource folder was not found at $englishLocalePath."
        }

        $installerKey = "HKLM:\SOFTWARE\Adobe\Adobe Acrobat\DC\Installer"
        $languageKey = "HKLM:\SOFTWARE\Adobe\Adobe Acrobat\DC\Language"
        if (-not (Test-Path -LiteralPath $installerKey)) {
            throw "Adobe Reader language verification failed: the unified Adobe installer registry key was not found."
        }
        if (-not (Test-Path -LiteralPath $languageKey)) {
            throw "Adobe Reader language verification failed: the unified Adobe language registry key was not found."
        }
        $installerState = Get-ItemProperty -LiteralPath $installerKey
        $appLanguage = [string](Get-ObjectPropertyValue -InputObject $installerState -Name "APP_LANG")
        $isMui = [int](Get-ObjectPropertyValue -InputObject $installerState -Name "IsMUI")
        $englishTransform = [string](Get-ObjectPropertyValue -InputObject (Get-ItemProperty -LiteralPath $languageKey) -Name "ENU")
        if ($appLanguage -notmatch "(?i)^MUI$" -or $isMui -ne 1 -or $englishTransform -notmatch "(?i)^en_US$") {
            throw "Adobe Reader language verification failed: expected Adobe MUI state with the en_GB-to-en_US English transform. APP_LANG='$appLanguage', IsMUI='$isMui', ENU='$englishTransform'."
        }

        Write-Log "Verified Adobe Reader executable under 64-bit Program Files path: $acrobat64Path"
        Write-Log "Verified Reader-only enforcement policy and Adobe MUI language state. Installer requested LANG_LIST=en_GB; Adobe maps International English en_GB to its en_US English resource transform at $englishLocalePath."
        if ($null -ne $entitlementLevel) {
            Write-Log "Adobe current-user entitlement level after Reader deployment: $entitlementLevel. Machine policy keeps the unified app in Reader-only reduced mode."
        }
        return
    }

    if (($unifiedEntries.Count + $explicitProEntries.Count) -eq 0) {
        throw "Adobe Acrobat Pro was not found after install."
    }

    if ($readerEntries.Count -gt 0) {
        $names = ($readerEntries | ForEach-Object { "$($_.DisplayName) $($_.DisplayVersion)" }) -join "; "
        throw "Adobe Reader product remains installed after Acrobat Pro deployment: $names"
    }

    if (-not (Test-Path -LiteralPath $acrobat64Path)) {
        throw "Adobe Acrobat Pro verification failed: expected 64-bit executable was not found: $acrobat64Path"
    }
    if ((Test-Path -LiteralPath $readerLegacyX86Path) -or (Test-Path -LiteralPath $reader11X86Path) -or (Test-Path -LiteralPath $acrobatLegacyX86Path)) {
        throw "Adobe Acrobat Pro verification failed: a legacy 32-bit Adobe executable path remains."
    }
    if ($entitlementLevel -eq 200) {
        throw "Adobe Acrobat Pro verification found a Standard entitlement (200), not Pro (300), for the current user."
    }
    if ($entitlementLevel -eq 300) {
        Write-Log "Verified current-user Acrobat Pro entitlement level 300."
    }
    elseif (-not $AllowAcrobatProEntitlementNotVerified) {
        throw "Adobe Acrobat Pro verification failed: Acrobat Pro entitlement level 300 was not visible for the current user. Sign in with the licensed account or explicitly use -AllowAcrobatProEntitlementNotVerified for an approved enterprise package whose entitlement is intentionally deferred."
    }
    else {
        Write-Log "Acrobat Pro binaries are present, but a Pro entitlement is not yet visible for the deployment account. The licensed user may need to sign in before entitlement level 300 can be verified." "WARN"
    }
    Write-Log "Verified Adobe Acrobat Pro 64-bit deployment. Locale selection depends on the supplied licensed enterprise package and required LANG_LIST=en_GB preflight."
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

    $entries = @(Get-UninstallEntries | Where-Object {
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

            $isNonProductUtility = $name -match "(?i)\bSystem\s+Audit\b|\bAudit\s+Tool\b|\bUpdate(?:r|\s+Service)\b"
            (-not $isNonProductUtility) -and ($looksLikeLeap -or ($publisherLooksLikeLeap -and $name -match "(?i)\bLEAP\b"))
        }
    })

    foreach ($profileRecord in @(Get-LocalUserProfileRecords)) {
        $installLocation = Join-Path $profileRecord.LocalPath "AppData\Local\LEAP-Accounting-Plus"
        $updateExe = Join-Path $installLocation "Update.exe"
        if (-not (Test-Path -LiteralPath $updateExe -PathType Leaf)) {
            continue
        }

        $alreadyRegistered = @($entries | Where-Object {
            -not [string]::IsNullOrWhiteSpace($_.InstallLocation) -and
            ([IO.Path]::GetFullPath([string]$_.InstallLocation).TrimEnd('\') -eq [IO.Path]::GetFullPath($installLocation).TrimEnd('\'))
        }).Count -gt 0
        if ($alreadyRegistered) {
            continue
        }

        Write-Log "Found LEAP Accounting Plus from its per-user installation path because that user's uninstall hive is not available: $installLocation" "WARN"
        $entries += [pscustomobject]@{
            DisplayName = "LEAP Accounting Plus"
            DisplayVersion = "profile-install"
            Publisher = "LEAP Software Developments"
            PSChildName = "LEAP-Accounting-Plus"
            UninstallString = "`"$updateExe`" --uninstall"
            QuietUninstallString = "`"$updateExe`" --uninstall -s"
            InstallLocation = $installLocation
            WindowsInstaller = 0
            RegistryPath = $null
            Scope = "UserProfile:$($profileRecord.Sid)"
            UserSid = $profileRecord.Sid
            UserProfilePath = $profileRecord.LocalPath
        }
    }

    $entries | Sort-Object DisplayName, DisplayVersion, InstallLocation -Unique
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
            $candidates += @(Get-ChildItem -LiteralPath $root -File -Recurse -ErrorAction SilentlyContinue |
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
        Assert-LeapInstallerArchitecture -Path $resolved
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
        Assert-LeapInstallerArchitecture -Path $installer
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
        Save-Download -Url $websiteInstaller.Url -Destination $installer -MinimumBytes 10000000 -AlwaysDownload:(-not $UseCachedInstallers)
        Assert-TrustedSignature -Path $installer -ExpectedPublisherFragments $LeapTrustedPublisherFragments
        Assert-LeapInstallerArchitecture -Path $installer
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

function Assert-LeapInstallerArchitecture {
    param([Parameter(Mandatory = $true)][string]$Path)

    if ($Simulation) {
        Write-Log "SIMULATION: Would verify the LEAP installer is x64: $Path"
        return
    }

    $extension = [IO.Path]::GetExtension($Path)
    if ($extension -ieq ".msi") {
        try {
            $windowsInstaller = New-Object -ComObject WindowsInstaller.Installer
            $database = $windowsInstaller.OpenDatabase($Path, 0)
            $view = $database.OpenView("SELECT `Value` FROM `Property` WHERE `Property`='Template'")
            $view.Execute()
            $record = $view.Fetch()
            $template = if ($record) { [string]$record.StringData(1) } else { "" }
            if ($template -notmatch "(?i)(^|;)x64(;|$)|(^|;)AMD64(;|$)") {
                throw "LEAP MSI Template property does not prove x64: '$template'"
            }
            Write-Log "Verified LEAP MSI installer architecture from its Template property: x64 ($Path)"
            return
        }
        catch {
            throw "Could not verify that the LEAP MSI is x64. $($_.Exception.Message) Path: $Path"
        }
    }

    if ($extension -ine @(".exe", ".com")) {
        throw "LEAP installer must be an x64 EXE or MSI: $Path"
    }

    $bytes = [IO.File]::ReadAllBytes($Path)
    if ($bytes.Length -lt 64 -or $bytes[0] -ne 0x4D -or $bytes[1] -ne 0x5A) {
        throw "LEAP installer is not a valid PE executable: $Path"
    }

    $peOffset = [BitConverter]::ToInt32($bytes, 0x3C)
    if ($peOffset -lt 0 -or ($peOffset + 6) -gt $bytes.Length -or $bytes[$peOffset] -ne 0x50 -or $bytes[$peOffset + 1] -ne 0x45) {
        throw "LEAP installer does not contain a valid PE header: $Path"
    }

    $machine = [BitConverter]::ToUInt16($bytes, $peOffset + 4)
    if ($machine -ne 0x8664) {
        throw "LEAP installer is not x64. PE machine value was 0x$('{0:X4}' -f $machine): $Path"
    }

    Write-Log "Verified LEAP installer architecture: x64 ($Path)"
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
        Assert-LeapInstallerArchitecture -Path $LeapInstallerPath
        Assert-TrustedSignature -Path $LeapInstallerPath -ExpectedPublisherFragments $LeapTrustedPublisherFragments
        Write-Log "LEAP installer source preflight passed: $LeapInstallerPath"
        return
    }

    if ($LeapInstallerUrl) {
        Assert-RemoteUrlReachable -Url $LeapInstallerUrl -Description "LEAP installer"
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

function Get-LeapProcessNames {
    return @(
        "LEAP",
        "LEAP Accounting Plus",
        "LEAPAccountingPlus",
        "LEAPAccounting",
        "LEAPClient",
        "LEAPDesktop",
        "LEAP.Office",
        "LEAPOffice",
        "LeapOfficeXE.NetClient",
        "LEAPLauncher",
        "LEAPCloud",
        "leapsystray"
    )
}

function Get-LeapBackgroundHelperProcessNames {
    return @(
        "LEAPLauncher",
        "LEAPCloud",
        "LeapOfficeXE.NetClient",
        "leapsystray"
    )
}

function Get-LeapPostInstallProcesses {
    param([switch]$IncludeSetupProcesses)

    if ($Simulation) {
        return @()
    }

    $backgroundProcessNames = @(
        "leaplauncher",
        "leapcloud",
        "leapofficexe.netclient",
        "leapsystray"
    )

    $processes = @(Get-Process -ErrorAction SilentlyContinue | Where-Object {
        $processName = [string]$_.ProcessName
        $normalisedName = $processName.ToLowerInvariant()
        $windowTitle = ""
        $windowHandle = [IntPtr]::Zero
        try {
            $windowTitle = [string]$_.MainWindowTitle
            $windowHandle = $_.MainWindowHandle
        }
        catch { }

        $hasVisibleLeapWindow = ($windowHandle -ne [IntPtr]::Zero) -and ($windowTitle -match "(?i)LEAP|Accounting")
        $knownClientProcess = $normalisedName -match "^(leap|leapdesktop|leapaccountingplus|leapaccounting|leapclient|leap\.office|leapoffice|leapofficexe\.netclient|leaplauncher|leapcloud|leapsystray)$"
        $knownSetupProcess = $processName -match "(?i)LEAP.*setup|setup.*LEAP"

        # Never terminate the active installer or its setup child from the
        # while-running watcher. The post-install gate may close a setup UI
        # only after the installer wrapper has finished.
        if ($knownSetupProcess -and (-not $IncludeSetupProcesses)) {
            return $false
        }

        if (($backgroundProcessNames -contains $normalisedName) -and (-not $hasVisibleLeapWindow)) {
            return $false
        }

        if ($knownClientProcess -or ($knownSetupProcess -and $IncludeSetupProcesses) -or $hasVisibleLeapWindow) {
            return $true
        }

        try {
            $processPath = [string]$_.Path
            $leapPath = $processPath -match "(?i)(?:\\LEAP(?:[^\\]*)\\|\\LEAP-Accounting-Plus\\|\\LEAPDesktop)"
            return ($leapPath -and ($windowHandle -ne [IntPtr]::Zero))
        }
        catch {
            return $false
        }
    })
    return @($processes | Sort-Object Id -Unique)
}

function Close-LeapPostInstallProcesses {
    param(
        [switch]$LogWhenClosed,
        [switch]$IncludeSetupProcesses
    )

    $running = @(Get-LeapPostInstallProcesses -IncludeSetupProcesses:$IncludeSetupProcesses)
    if ($running.Count -eq 0) {
        return $false
    }

    if ($LogWhenClosed) {
        $names = ($running | Select-Object -ExpandProperty ProcessName -Unique | Sort-Object) -join ", "
        Write-Log "Closing LEAP post-install client processes immediately after detection: $names" "WARN"
    }

    foreach ($process in $running) {
        try {
            Stop-Process -Id $process.Id -Force -ErrorAction Stop
        }
        catch {
            Write-Log "Could not close LEAP process $($process.ProcessName) PID $($process.Id). $($_.Exception.Message)" "WARN"
        }
    }

    Start-Sleep -Milliseconds 250
    $remaining = @(Get-LeapPostInstallProcesses -IncludeSetupProcesses:$IncludeSetupProcesses | Where-Object { $_.Id -in @($running | Select-Object -ExpandProperty Id) })
    if ($remaining.Count -gt 0) {
        $names = ($remaining | Select-Object -ExpandProperty ProcessName -Unique | Sort-Object) -join ", "
        Write-Log "LEAP processes remained after the close request: $names" "WARN"
    }
    return $true
}

function Test-LeapAccountingPlusFallbackEligibility {
    param([Parameter(Mandatory = $true)]$Entry)

    if ([string]$Entry.DisplayName -notmatch "(?i)^LEAP Accounting Plus$") {
        return $false
    }

    $profileRoot = [string]$Entry.UserProfilePath
    $installLocation = [string]$Entry.InstallLocation
    if ([string]::IsNullOrWhiteSpace($profileRoot) -or [string]::IsNullOrWhiteSpace($installLocation)) {
        return $false
    }

    try {
        $profileRoot = [IO.Path]::GetFullPath($profileRoot).TrimEnd('\')
        $installLocation = [IO.Path]::GetFullPath($installLocation).TrimEnd('\')
        $expectedLocation = [IO.Path]::GetFullPath((Join-Path $profileRoot "AppData\Local\LEAP-Accounting-Plus")).TrimEnd('\')
        if ($installLocation -ne $expectedLocation) {
            Write-Log "Refusing LEAP Accounting Plus fallback because the registered install path is outside its expected per-user location: $installLocation" "WARN"
            return $false
        }

        $usersRoot = [IO.Path]::GetFullPath((Join-Path $env:SystemDrive "Users")).TrimEnd('\')
        if (-not $profileRoot.StartsWith("$usersRoot\", [StringComparison]::OrdinalIgnoreCase)) {
            Write-Log "Refusing LEAP Accounting Plus fallback because its profile path is outside the local Users root: $profileRoot" "WARN"
            return $false
        }

        return Test-Path -LiteralPath (Join-Path $installLocation "Update.exe") -PathType Leaf
    }
    catch {
        Write-Log "Could not validate LEAP Accounting Plus fallback scope. $($_.Exception.Message)" "WARN"
        return $false
    }
}

function Remove-LeapPerUserUninstallRegistration {
    param([Parameter(Mandatory = $true)]$Entry)

    if ([string]::IsNullOrWhiteSpace([string]$Entry.RegistryPath)) {
        return
    }

    $registryPath = ([string]$Entry.RegistryPath) -replace "^Microsoft\.PowerShell\.Core\\", ""
    $expectedRegistryRoots = @(
        "Registry::HKEY_USERS\$($Entry.UserSid)\Software\Microsoft\Windows\CurrentVersion\Uninstall\",
        "Registry::HKEY_CURRENT_USER\Software\Microsoft\Windows\CurrentVersion\Uninstall\"
    )
    if (-not (@($expectedRegistryRoots | Where-Object { $registryPath.StartsWith($_, [StringComparison]::OrdinalIgnoreCase) }).Count -gt 0)) {
        throw "Refusing to remove unexpected LEAP per-user uninstall registration path: $registryPath"
    }

    if (Test-Path -LiteralPath $Entry.RegistryPath) {
        Remove-Item -LiteralPath $Entry.RegistryPath -Recurse -Force -ErrorAction Stop
        Write-Log "Removed stale LEAP per-user uninstall registration: $registryPath"
    }
}

function Invoke-LeapAccountingPlusFallbackRemoval {
    param([Parameter(Mandatory = $true)]$Entry)

    if (-not (Test-LeapAccountingPlusFallbackEligibility -Entry $Entry)) {
        throw "LEAP Accounting Plus vendor uninstall failed and its fallback scope could not be validated. Stopping safely."
    }

    $installLocation = [string]$Entry.InstallLocation
    $running = @(Get-Process -Name "LEAP Accounting Plus" -ErrorAction SilentlyContinue)
    if ($running.Count -gt 0) {
        if (-not $ForceCloseApps) {
            throw "LEAP Accounting Plus is still running after its vendor uninstall failed. Close it and rerun, or use -ForceCloseApps after confirming user work is saved."
        }

        foreach ($process in $running) {
            Stop-Process -Id $process.Id -Force -ErrorAction Stop
        }
        Start-Sleep -Seconds 2
    }

    Assert-ZiaasSafePath -Path $installLocation -AllowedRoots @([string]$Entry.UserProfilePath) -Purpose "LEAP Accounting Plus fallback removal"
    Write-Log "Moving only the validated LEAP Accounting Plus per-user application folder to the run backup and preserving roaming LEAP Accounting data." "WARN"
    Move-LeapResidualToBackup -Path $installLocation -Label "$(Split-Path -Leaf ([string]$Entry.UserProfilePath))-Local-LEAP-Accounting-Plus-Fallback"
    if (Test-Path -LiteralPath $installLocation) {
        throw "LEAP Accounting Plus fallback could not move its application folder: $installLocation"
    }

    Remove-LeapPerUserUninstallRegistration -Entry $Entry
    Write-Log "LEAP Accounting Plus fallback removal completed without touching AppData\Roaming\LEAP Accounting." "WARN"
}

function Uninstall-Leap {
    $maxPasses = 3
    $foundAnyLeapEntry = $false

    for ($pass = 1; $pass -le $maxPasses; $pass++) {
        $entries = @(Get-LeapEntries)
        if ($entries.Count -eq 0) {
            if ($foundAnyLeapEntry) {
                Write-Log "No LEAP uninstall entries remain after uninstall pass $($pass - 1)."
            }
            else {
                Write-Log "No existing LEAP uninstall entries found."
            }
            return
        }

        $foundAnyLeapEntry = $true
        Write-Log "LEAP uninstall pass $pass found $($entries.Count) uninstall entr$(if ($entries.Count -eq 1) { 'y' } else { 'ies' })."
        foreach ($entry in $entries) {
            Write-Log "Found LEAP product: $($entry.DisplayName) $($entry.DisplayVersion)"
        }

        Stop-DeploymentBlockingApps -ProcessNames (Get-LeapProcessNames) -AutoForceProcessNames (Get-LeapBackgroundHelperProcessNames)

        $processedEntries = @()
        foreach ($entry in $entries) {
            if (Test-LeapAccountingPlusFallbackEligibility -Entry $entry) {
                Write-Log "Using the validated LEAP Accounting Plus local-app fallback directly; its per-user Squirrel uninstaller is skipped because it can launch a visible window under an elevated administrator context." "WARN"
                Invoke-LeapAccountingPlusFallbackRemoval -Entry $entry
                $processedEntries += $entry
                continue
            }

            $productCode = Get-MsiProductCode -Entry $entry
            if ($productCode) {
                $safeName = ($entry.DisplayName -replace "[^A-Za-z0-9._-]", "_")
                $msiLog = Join-Path $Script:LogDir "Uninstall-$safeName-$Script:RunStamp-pass$pass.log"

                Invoke-MsiUninstallWithRetry `
                    -ProductCode $productCode `
                    -MsiLog $msiLog `
                    -ProductName "LEAP uninstall pass ${pass}: $($entry.DisplayName)" `
                    -VendorLabel "LEAP"
                $processedEntries += $entry
                continue
            }

            if (-not [string]::IsNullOrWhiteSpace($entry.QuietUninstallString)) {
                $quietUninstall = Split-CommandLine -CommandLine $entry.QuietUninstallString
                try {
                    Invoke-ProcessChecked `
                        -FilePath $quietUninstall.FilePath `
                        -ArgumentList $quietUninstall.Arguments `
                        -SuccessExitCodes @(0, 3010) `
                        -Description "LEAP quiet uninstall pass ${pass}: $($entry.DisplayName)"
                }
                catch {
                    if (-not (Test-LeapAccountingPlusFallbackEligibility -Entry $entry)) {
                        throw
                    }

                    Write-Log "LEAP Accounting Plus quiet uninstaller failed: $($_.Exception.Message)" "WARN"
                    Invoke-LeapAccountingPlusFallbackRemoval -Entry $entry
                }
                $processedEntries += $entry
                continue
            }

            throw "LEAP product '$($entry.DisplayName)' does not expose an MSI product code or QuietUninstallString. Stopping rather than guessing a silent uninstall command."
        }

        if ($Simulation) {
            $Script:SimulationLeapProductsRemoved = $true
            $Script:SimulationLeapInstalled = $false
        }
        else {
            Start-Sleep -Seconds 5

            foreach ($entry in $processedEntries) {
                if ($entry.DisplayName -notmatch "(?i)^LEAP Accounting Plus$") {
                    continue
                }

                $installLocation = [string]$entry.InstallLocation
                if (-not [string]::IsNullOrWhiteSpace($installLocation) -and (Test-Path -LiteralPath $installLocation)) {
                    $allowedProfileRoot = if ([string]::IsNullOrWhiteSpace([string]$entry.UserProfilePath)) { Join-Path $env:SystemDrive "Users" } else { [string]$entry.UserProfilePath }
                    Assert-ZiaasSafePath -Path $installLocation -AllowedRoots @($allowedProfileRoot) -Purpose "LEAP Accounting Plus post-uninstall residual"
                    Move-LeapResidualToBackup -Path $installLocation -Label "$(Split-Path -Leaf $allowedProfileRoot)-Local-LEAP-Accounting-Plus"
                    if (Test-Path -LiteralPath $installLocation) {
                        Write-Log "Keeping the LEAP Accounting Plus uninstall registration because its installation folder could not be removed: $installLocation" "WARN"
                        continue
                    }
                }

                if (-not [string]::IsNullOrWhiteSpace([string]$entry.RegistryPath) -and (Test-Path -LiteralPath $entry.RegistryPath)) {
                    Remove-LeapPerUserUninstallRegistration -Entry $entry
                }
            }
        }
    }

    $remaining = @(Get-LeapEntries)
    if ($remaining.Count -gt 0) {
        foreach ($entry in $remaining) {
            Write-Log "Still present after $maxPasses LEAP uninstall pass(es): $($entry.DisplayName) $($entry.DisplayVersion)" "WARN"
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
        Assert-ZiaasSafePath -Path $Path -AllowedRoots @($env:ProgramFiles, ${env:ProgramFiles(x86)}, $env:ProgramData, (Join-Path $env:SystemDrive "Users")) -Purpose "LEAP residual move"
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
        Assert-ZiaasSafePath -Path $Path -AllowedRoots @($env:ProgramFiles, ${env:ProgramFiles(x86)}, $env:ProgramData, (Join-Path $env:SystemDrive "Users")) -Purpose "LEAP residual rename"
        Write-Log "Renaming LEAP residual: $Path -> $oldPath"
        Rename-Item -LiteralPath $Path -NewName (Split-Path -Leaf $oldPath) -Force -ErrorAction Stop
        $Script:LeapResidualRenamed++
    }
    catch {
        Write-Log "Could not rename LEAP residual $Path. $($_.Exception.Message)" "ERROR"
        $Script:LeapResidualErrors++
    }
}

function Remove-StaleLeapServices {
    if ($Simulation) {
        Write-Log "SIMULATION: Would stop and remove the known LEAP Office integration services before reinstall or final cleanup."
        return
    }

    foreach ($serviceName in @("LeapOfficeXE", "PrintToLEAP")) {
        $service = Get-CimInstance Win32_Service -Filter "Name='$serviceName'" -ErrorAction SilentlyContinue
        if (-not $service) {
            continue
        }

        $servicePath = [string]$service.PathName
        if ($servicePath -notmatch "(?i)LEAP") {
            throw "Refusing to remove service '$serviceName' because its binary path is not recognised as a LEAP path: $servicePath"
        }

        if ([string]$service.State -ne "Stopped") {
            Stop-Service -Name $serviceName -Force -ErrorAction Stop
            Write-Log "Stopped stale LEAP integration service: $serviceName"
        }

        $scOutput = @(& "$env:SystemRoot\System32\sc.exe" delete $serviceName 2>&1)
        if ($LASTEXITCODE -notin @(0, 1060)) {
            throw "Could not remove stale LEAP integration service '$serviceName'. $($scOutput -join ' ')"
        }

        Write-Log "Removed stale LEAP integration service: $serviceName"
    }
}

function Get-LocalUserProfilePaths {
    Get-LocalUserProfileRecords | Select-Object -ExpandProperty LocalPath -Unique
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

    foreach ($userProfilePath in $profiles) {
        $userName = Split-Path -Leaf $userProfilePath
        $roamingPath = Join-Path $userProfilePath "AppData\Roaming"
        $localPath = Join-Path $userProfilePath "AppData\Local"
        $tempPath = Join-Path $localPath "Temp"

        Write-Log "Cleaning LEAP remnants in profile: $userProfilePath"

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
            Move-LeapResidualToBackup -Path (Join-Path $localPath "LEAP-Accounting-Plus") -Label "$userName-Local-LEAP-Accounting-Plus"
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
        Remove-StaleLeapServices
        Write-Log "SIMULATION: Would unregister stale LEAP scheduled tasks."
        Write-Log "SIMULATION: Would move known machine-level LEAP folders to backup and rename selected ProgramData folders."
        return
    }

    Remove-StaleLeapServices

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

function Get-DefaultLeapInstallArguments {
    return @(
        "/s",
        "/SMS",
        "/v`"/qn REBOOT=ReallySuppress`""
    )
}

function Stop-LeapPostInstallLaunches {
    param(
        [int]$WaitSeconds = 20,
        [switch]$IncludeSetupProcesses
    )

    if ($Simulation) {
        Write-Log "SIMULATION: Would close LEAP post-install client/tray launches if they appear."
        return
    }

    $deadline = (Get-Date).AddSeconds([Math]::Max(0, $WaitSeconds))
    $closeAttempted = $false
    do {
        if (Close-LeapPostInstallProcesses -LogWhenClosed -IncludeSetupProcesses:$IncludeSetupProcesses) {
            $closeAttempted = $true
        }

        if ((Get-Date) -ge $deadline) {
            break
        }
        Start-Sleep -Milliseconds 250
    } while ($true)

    $remaining = @(Get-LeapPostInstallProcesses -IncludeSetupProcesses:$IncludeSetupProcesses)

    if ($remaining.Count -gt 0) {
        $remainingNames = ($remaining | Select-Object -ExpandProperty ProcessName -Unique | Sort-Object) -join ", "
        Write-Log "LEAP post-install processes are still running after close attempt: $remainingNames" "WARN"
    }
    elseif ($closeAttempted) {
        Write-Log "LEAP post-install client/tray processes closed immediately after detection."
    }
    else {
        Write-Log "No LEAP post-install client/tray processes remained open."
    }
}

function Install-Leap {
    param([Parameter(Mandatory = $true)][string]$InstallerPath)

    $leapWindowStyle = "Hidden"
    Write-Log "LEAP's official installer may auto-launch the LEAP client when installation completes; the post-install gate will close detected client/tray processes before verification." "WARN"
    $effectiveLeapInstallArguments = @($LeapInstallArguments)
    if ($LeapInstallArguments.Count -eq 0) {
        $effectiveLeapInstallArguments = @(Get-DefaultLeapInstallArguments)
        Write-Log "No LEAP install arguments were supplied. Using detected InstallShield silent defaults: $($effectiveLeapInstallArguments -join ' ')." "WARN"
    }

    try {
        $maxAttempts = 4
        $installationCompleted = $false
        for ($attempt = 1; $attempt -le $maxAttempts; $attempt++) {
            Invoke-ProcessChecked `
                -FilePath $InstallerPath `
                -ArgumentList $effectiveLeapInstallArguments `
                -Description "LEAP installation attempt $attempt of $maxAttempts" `
                -SuccessExitCodes @(0, 1618, 3010) `
                -WindowStyle $leapWindowStyle `
                -WhileRunning { [void](Close-LeapPostInstallProcesses -LogWhenClosed) }
            $exitCode = [int]$Script:LastProcessExitCode

            if ($exitCode -eq 1618) {
                if ($attempt -ge $maxAttempts) {
                    throw "LEAP installation remained blocked by Windows Installer error 1618 after $maxAttempts attempts. Reboot the machine, confirm no other installer is active, and rerun."
                }

                Write-Log "LEAP installation returned Windows Installer error 1618 (another installation is in progress). Closing any LEAP child launches and waiting 30 seconds before retry $($attempt + 1) of $maxAttempts." "WARN"
                Stop-LeapPostInstallLaunches -WaitSeconds 1
                Start-Sleep -Seconds 30
                continue
            }

            $installationCompleted = $true
            break
        }

        if (-not $installationCompleted) {
            throw "LEAP installation did not complete."
        }
    }
    finally {
        Stop-LeapPostInstallLaunches -WaitSeconds 20 -IncludeSetupProcesses
    }

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
        if ((-not $Simulation) -and ([string]$entry.Publisher -notmatch "(?i)LEAP")) {
            throw "LEAP verification failed: installed entry publisher was not recognised as LEAP. Product '$($entry.DisplayName)' publisher '$($entry.Publisher)'."
        }
    }

    $remainingProcesses = @(Get-LeapPostInstallProcesses -IncludeSetupProcesses)
    if ($remainingProcesses.Count -gt 0) {
        $remainingNames = ($remainingProcesses | Select-Object -ExpandProperty ProcessName -Unique | Sort-Object) -join ", "
        throw "LEAP verification failed: the installer left a LEAP client/setup process running after the bounded close gate: $remainingNames"
    }

    if (-not [string]::IsNullOrWhiteSpace($Script:ResolvedLeapInstallerVersion)) {
        $reportedVersion = @($entries | ForEach-Object { [string]$_.DisplayVersion } | Where-Object { $_ }) -join "; "
        if ($reportedVersion -and ($reportedVersion -notmatch [regex]::Escape($Script:ResolvedLeapInstallerVersion))) {
            Write-Log "LEAP installer page reported latest version $Script:ResolvedLeapInstallerVersion, while the uninstall entry reports '$reportedVersion'. Treating the signed installer as authoritative but flagging the version discrepancy for review." "WARN"
        }
    }

    Test-LeapIntegrationEvidence
}

function Test-LeapIntegrationEvidence {
    if ($Simulation) {
        Write-Log "SIMULATION: Would verify LEAP Office automation and Adobe integration evidence after install."
        return
    }

    $evidence = @(
        (Join-Path $env:ProgramData "LEAP Office\Cloud\Extras\Acrobat Extras\LEAPIcons.pdf"),
        (Join-Path $env:ProgramData "LEAP Office\Cloud\Extras\Acrobat Extras\InstallLauncher.exe"),
        (Join-Path $env:ProgramData "LEAP Office\Cloud\Extras\Acrobat Extras\LEAPForAcrobatSetup.exe"),
        (Join-Path $env:ProgramFiles "LEAP Office\Office Automation"),
        (Join-Path ${env:ProgramFiles(x86)} "LEAP Office\Office Automation")
    ) | Where-Object { -not [string]::IsNullOrWhiteSpace($_) } | Select-Object -Unique

    $present = @($evidence | Where-Object { Test-Path -LiteralPath $_ })
    $missing = @($evidence | Where-Object { -not (Test-Path -LiteralPath $_) })
    if ($present.Count -gt 0) {
        Write-Log "LEAP integration evidence present: $($present -join '; ')"
    }
    if ($missing.Count -gt 0) {
        Write-Log "LEAP integration evidence was not found yet: $($missing -join '; '). The installer completed, but Office/Adobe add-in binding should be checked before handover; run the vendor's Office repair/add-in repair procedure if required." "WARN"
    }
}

function Remove-WorkingDownloadsIfRequested {
    if ($KeepDownloads) {
        Write-Log "Keeping downloads in $Script:DownloadDir"
        return
    }

    try {
        Assert-ZiaasSafePath -Path $Script:DownloadDir -AllowedRoots @($Script:Root) -Purpose "temporary installer download cleanup"
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
function ConvertTo-SafeFileName {
    param(
        [Parameter(Mandatory = $false)]
        [Alias("Name")]
        [AllowEmptyString()]
        [string]$FileName
    )

    if ([string]::IsNullOrWhiteSpace($FileName)) {
        return "Unnamed"
    }

    $safe = $FileName
    foreach ($character in [System.IO.Path]::GetInvalidFileNameChars()) {
        $safe = $safe.Replace([string]$character, "_")
    }

    if ([string]::IsNullOrWhiteSpace($safe)) {
        return "Unnamed"
    }

    return $safe
}

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
        $officeRemovalError = $_.Exception.Message
        Write-Log "Office Click-to-Run removal returned a non-success result. Continuing to Microsoft Office scrub cleanup because ODT Remove All can fail when Office is already absent or partially removed." "WARN"
        Write-Log "Office Click-to-Run removal detail: $officeRemovalError" "WARN"
    }

    Invoke-OfficeScrubCleanup
}

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

function Assert-AdobeAcrobatProLanguageSelection {
    if ($AllowAcrobatProLanguageNotVerified) {
        Write-Log "Acrobat Pro UK English language proof was explicitly bypassed. Ensure the supplied Adobe enterprise package is pre-configured for en_GB." "WARN"
        return
    }

    $argumentText = (@(Get-AdobeAcrobatProInstallArgumentList) -join " ")
    if ($argumentText -match "(?i)(^|\s)LANG_LIST\s*=\s*en_GB(\s|$)") {
        $prefix = if ($Simulation) { "SIMULATION: " } else { "" }
        Write-Log "${prefix}Acrobat Pro language preflight passed: LANG_LIST=en_GB was supplied. Adobe maps International English en_GB to its en_US English resource transform."
        return
    }

    throw "Acrobat Pro was selected, but UK/British English was not verified. Add LANG_LIST=en_GB to -AdobeAcrobatProInstallArgumentLine or -AdobeAcrobatProInstallArguments, or use -AllowAcrobatProLanguageNotVerified only for a pre-configured Adobe enterprise package."
}

function Assert-AdobeInstallerSourceAvailable {
    param([Parameter(Mandatory = $true)]$AdobeSelection)

    if ($AdobeSelection.Product -eq "Reader") {
        $readerUri = $null
        if (-not [Uri]::TryCreate($AdobeReaderInstallerUrl, [UriKind]::Absolute, [ref]$readerUri)) {
            throw "Adobe Reader installer URL is not a valid absolute URL: $AdobeReaderInstallerUrl"
        }
        if ($readerUri.Scheme -ne "https") {
            throw "Adobe Reader installer URL must use HTTPS."
        }
        $readerLeaf = Split-Path -Leaf $readerUri.AbsolutePath
        if ($readerLeaf -notmatch "(?i)^AcroRdrDCx64.*_MUI\.exe$") {
            throw "Adobe Reader installer must be the official 64-bit MUI package. Configured filename: $readerLeaf"
        }
        Assert-RemoteUrlReachable -Url $AdobeReaderInstallerUrl -Description "Adobe Reader 64-bit MUI installer"
        Write-Log "Adobe Reader installer source preflight passed: official-format 64-bit MUI URL configured with LANG_LIST=en_GB. Adobe maps International English en_GB to en_US English resources."
        return
    }

    $hasPath = -not [string]::IsNullOrWhiteSpace($AdobeAcrobatProInstallerPath)
    $hasUrl = -not [string]::IsNullOrWhiteSpace($AdobeAcrobatProInstallerUrl)

    if (-not $hasPath -and -not $hasUrl) {
        throw "Acrobat Pro was selected, but no licensed Acrobat Pro installer source was supplied. Provide -AdobeAcrobatProInstallerPath or -AdobeAcrobatProInstallerUrl before starting the run. The script cannot reinstall Pro from an already-installed copy because Adobe cleanup removes existing Reader/Acrobat first."
    }

    if ($hasPath) {
        Assert-AdobeAcrobatProInstallerFileSupported -Path $AdobeAcrobatProInstallerPath
        if ((-not $Simulation) -and (-not (Test-Path -LiteralPath $AdobeAcrobatProInstallerPath))) {
            throw "Acrobat Pro installer path was supplied but not found: $AdobeAcrobatProInstallerPath"
        }
        if (-not $Simulation) {
            Assert-TrustedSignature -Path $AdobeAcrobatProInstallerPath -ExpectedPublisherFragments $AdobeAcrobatProTrustedPublisherFragments
        }
        $prefix = if ($Simulation) { "SIMULATION: " } else { "" }
        Write-Log "${prefix}Acrobat Pro installer path preflight passed: $AdobeAcrobatProInstallerPath"
    }

    if ($hasUrl) {
        $proUri = $null
        if (-not [Uri]::TryCreate($AdobeAcrobatProInstallerUrl, [UriKind]::Absolute, [ref]$proUri)) {
            throw "Acrobat Pro installer URL is not a valid absolute URL."
        }
        if ($proUri.Scheme -ne "https") {
            throw "Acrobat Pro installer URL must use HTTPS."
        }
        $leaf = Split-Path -Leaf $proUri.AbsolutePath
        if ([string]::IsNullOrWhiteSpace($leaf)) {
            throw "Acrobat Pro installer URL must end with an installer filename."
        }
        Assert-AdobeAcrobatProInstallerFileSupported -Path $leaf
        Assert-RemoteUrlReachable -Url $AdobeAcrobatProInstallerUrl -Description "Acrobat Pro licensed installer"
        $prefix = if ($Simulation) { "SIMULATION: " } else { "" }
        Write-Log "${prefix}Acrobat Pro installer URL preflight passed."
    }

    $acrobatProArguments = @(Get-AdobeAcrobatProInstallArgumentList)
    if ($acrobatProArguments.Count -eq 0 -and (-not $AllowAcrobatProInstallerWithoutArguments)) {
        throw "Acrobat Pro was selected, but no silent install arguments were supplied. Provide -AdobeAcrobatProInstallArgumentLine or -AdobeAcrobatProInstallArguments for your licensed Adobe package before starting the run, or deliberately add -AllowAcrobatProInstallerWithoutArguments."
    }

    if ($acrobatProArguments.Count -eq 0) {
        Write-Log "No Acrobat Pro install arguments were supplied. This was explicitly allowed; installer UI may appear." "WARN"
    }

    Assert-AdobeAcrobatProLanguageSelection
}

function Invoke-ZiaasComponent {
    param(
        [Parameter(Mandatory = $true)][string]$Name,
        [Parameter(Mandatory = $true)][int]$FailureExitCode,
        [Parameter(Mandatory = $true)][scriptblock]$ScriptBlock
    )

    try {
        Initialize-DeploymentFolders
        Write-Log "$Name started."
        Write-Log "Log file: $Script:LogFile"
        Write-Log "Working root: $Script:Root"
        Assert-AdminAndPlatform

        & $ScriptBlock

        $elapsed = New-TimeSpan -Start $Script:StartTime -End (Get-Date)
        Write-Log ("$Name completed in {0:g}." -f $elapsed) "SUCCESS"
        if ($Script:RebootRequired) {
            Write-Log "$Name completed but a reboot is required." "WARN"
            exit 3010
        }

        exit 0
    }
    catch {
        try {
            Write-Log $_.Exception.Message "ERROR"
            Write-Log "$Name failed. See $Script:LogFile." "ERROR"
        }
        catch {
            Write-Host "$Name failed before logging was available. $($_.Exception.Message)"
        }
        exit $FailureExitCode
    }
}
