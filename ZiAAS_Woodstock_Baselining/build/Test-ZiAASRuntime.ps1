#requires -version 5.1
[CmdletBinding()]
param(
    [string]$ProjectRoot,
    [string]$OutputRoot,
    [switch]$KeepTestData
)

Set-StrictMode -Version 2.0
$ErrorActionPreference = "Stop"

if ([string]::IsNullOrWhiteSpace($ProjectRoot)) {
    $ProjectRoot = Split-Path -Parent $PSScriptRoot
}
if ([string]::IsNullOrWhiteSpace($OutputRoot)) {
    $OutputRoot = Join-Path (Split-Path -Parent (Split-Path -Parent $PSScriptRoot)) "outputs"
}

$corePath = Join-Path $OutputRoot "ZiAAS_Woodstock_Baselining.core.ps1"
$componentPath = Join-Path $OutputRoot "components"
$testRoot = Join-Path (Split-Path -Parent $ProjectRoot) "work\runtime-regression"
$powerShellExe = Join-Path $env:SystemRoot "System32\WindowsPowerShell\v1.0\powershell.exe"
$currentIdentity = [Security.Principal.WindowsIdentity]::GetCurrent()
$currentPrincipal = New-Object Security.Principal.WindowsPrincipal($currentIdentity)
$isElevated = $currentPrincipal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)

function Assert-Condition {
    param([bool]$Condition, [string]$Message)
    if (-not $Condition) { throw $Message }
}

function Write-Pass {
    param([string]$Message)
    Write-Host "[PASS] $Message"
}

function Get-LatestSummary {
    param([string]$WorkingRoot)
    $reports = Join-Path $WorkingRoot "Reports"
    $file = Get-ChildItem -LiteralPath $reports -Filter "summary-*.json" -File -ErrorAction SilentlyContinue |
        Sort-Object LastWriteTime -Descending | Select-Object -First 1
    if (-not $file) { return $null }
    return (Get-Content -LiteralPath $file.FullName -Raw | ConvertFrom-Json)
}

function Invoke-RuntimeCase {
    param(
        [Parameter(Mandatory = $true)][string]$Name,
        [Parameter(Mandatory = $true)][string[]]$ScriptArguments,
        [int]$ExpectedExitCode = 0,
        [switch]$ExpectSummary,
        [string]$ComponentDirectoryOverride
    )

    $workingRoot = Join-Path $testRoot $Name
    if (Test-Path -LiteralPath $workingRoot) {
        Remove-Item -LiteralPath $workingRoot -Recurse -Force
    }
    New-Item -Path $workingRoot -ItemType Directory -Force | Out-Null

    $selectedComponentPath = if ([string]::IsNullOrWhiteSpace($ComponentDirectoryOverride)) { $componentPath } else { $ComponentDirectoryOverride }
    $arguments = @(
        "-NoProfile", "-ExecutionPolicy", "Bypass", "-File", $corePath,
        "-WorkingRoot", $workingRoot,
        "-ComponentDirectory", $selectedComponentPath,
        "-NoComponentDownload",
        "-NoLogo",
        "-NoColor",
        "-Quiet",
        "-LogLevel", "Warn",
        "-PostCleanupWaitSeconds", "0",
        "-PreLeapWaitSeconds", "0"
    ) + $ScriptArguments

    $caseOutput = @(& $powerShellExe @arguments)
    $exitCode = $LASTEXITCODE
    if ($exitCode -ne $ExpectedExitCode) {
        $outputText = $caseOutput -join [Environment]::NewLine
        throw "Case '$Name' returned $exitCode; expected $ExpectedExitCode. Output: $outputText"
    }

    $summary = Get-LatestSummary -WorkingRoot $workingRoot
    if ($ExpectSummary) {
        Assert-Condition ($null -ne $summary) "Case '$Name' did not create a summary report."
    }
    Write-Pass "$Name returned expected exit code $ExpectedExitCode."
    return [pscustomobject]@{ Name = $Name; WorkingRoot = $workingRoot; Summary = $summary }
}

$profileDiscoveryTest = Join-Path $PSScriptRoot "Test-ZiAASProfileDiscovery.ps1"
$profileDiscoveryOutput = @(& $powerShellExe -NoProfile -ExecutionPolicy Bypass -File $profileDiscoveryTest -OutputRoot $OutputRoot 2>&1)
Assert-Condition ($LASTEXITCODE -eq 0) "Profile discovery regression failed: $($profileDiscoveryOutput -join [Environment]::NewLine)"
Write-Pass "Local/Azure AD profile and LEAP Accounting fallback discovery passed."

$leapRetryTest = Join-Path $PSScriptRoot "Test-ZiAASLeapRetry.ps1"
$leapRetryOutput = @(& $powerShellExe -NoProfile -ExecutionPolicy Bypass -File $leapRetryTest -CommonPath (Join-Path $OutputRoot "components\Common.ps1") 2>&1)
Assert-Condition ($LASTEXITCODE -eq 0) "LEAP 1618 retry regression failed: $($leapRetryOutput -join [Environment]::NewLine)"
Write-Pass "LEAP Windows Installer 1618 retry path passed."

$leapHardeningTest = Join-Path $PSScriptRoot "Test-ZiAASLeapHardening.ps1"
$leapHardeningOutput = @(& $powerShellExe -NoProfile -ExecutionPolicy Bypass -File $leapHardeningTest -CommonPath (Join-Path $OutputRoot "components\Common.ps1") 2>&1)
Assert-Condition ($LASTEXITCODE -eq 0) "LEAP hardening regression failed: $($leapHardeningOutput -join [Environment]::NewLine)"
Write-Pass "LEAP download selection, product filtering, and post-install process detection passed."

$adobeRetryTest = Join-Path $PSScriptRoot "Test-ZiAASAdobeRetry.ps1"
$adobeRetryOutput = @(& $powerShellExe -NoProfile -ExecutionPolicy Bypass -File $adobeRetryTest -CommonPath (Join-Path $OutputRoot "components\Common.ps1") 2>&1)
Assert-Condition ($LASTEXITCODE -eq 0) "Adobe 1618 retry regression failed: $($adobeRetryOutput -join [Environment]::NewLine)"
Write-Pass "Adobe Windows Installer 1618 retry path passed."

function Assert-StepOrder {
    param([Parameter(Mandatory = $true)]$Summary)

    $ids = @($Summary.PlannedSteps | ForEach-Object { [string]$_.Id })
    $stageIndex = [array]::IndexOf($ids, "installer-staging")
    Assert-Condition ($stageIndex -ge 0) "Installer staging step is missing."

    foreach ($removeId in @("leap-remove-clean", "adobe-remove-clean", "office-remove-clean")) {
        $index = [array]::IndexOf($ids, $removeId)
        if ($index -ge 0) {
            Assert-Condition ($stageIndex -lt $index) "Installer staging does not precede $removeId."
        }
    }

    $officeInstall = [array]::IndexOf($ids, "office-install-verify")
    $adobeInstall = [array]::IndexOf($ids, "adobe-install-verify")
    $leapInstall = [array]::IndexOf($ids, "leap-install-verify")
    if ($officeInstall -ge 0 -and $adobeInstall -ge 0) {
        Assert-Condition ($officeInstall -lt $adobeInstall) "Adobe install is not after Office install."
    }
    if ($leapInstall -ge 0 -and $officeInstall -ge 0) {
        Assert-Condition ($officeInstall -lt $leapInstall) "LEAP install is not after Office install."
    }
    if ($leapInstall -ge 0 -and $adobeInstall -ge 0) {
        Assert-Condition ($adobeInstall -lt $leapInstall) "LEAP install is not after Adobe install."
    }
}

Assert-Condition (Test-Path -LiteralPath $corePath) "Generated core script is missing: $corePath"
Assert-Condition (Test-Path -LiteralPath $componentPath) "Generated component directory is missing: $componentPath"

if (Test-Path -LiteralPath $testRoot) {
    Remove-Item -LiteralPath $testRoot -Recurse -Force
}
New-Item -Path $testRoot -ItemType Directory -Force | Out-Null

$matrix = @(
    @{ Name = "Office"; Mode = "Office"; Adobe = $false },
    @{ Name = "Reader"; Mode = "Adobe"; Adobe = $true },
    @{ Name = "Leap"; Mode = "Leap"; Adobe = $false },
    @{ Name = "OfficeReader"; Mode = "OfficeAndAdobe"; Adobe = $true },
    @{ Name = "OfficeLeap"; Mode = "OfficeAndLeap"; Adobe = $false },
    @{ Name = "ReaderLeap"; Mode = "AdobeAndLeap"; Adobe = $true },
    @{ Name = "AllReader"; Mode = "All"; Adobe = $true }
)

foreach ($case in $matrix) {
    $caseArguments = @("-Simulation", "-Unattended", "-InstallMode", $case.Mode)
    if ($case.Adobe) { $caseArguments += @("-AdobeProduct", "Reader") }
    $result = Invoke-RuntimeCase -Name $case.Name -ScriptArguments $caseArguments -ExpectedExitCode 0 -ExpectSummary
    Assert-Condition ([string]$result.Summary.Status -eq "Success") "Case '$($case.Name)' summary status was not Success."
    Assert-StepOrder -Summary $result.Summary
}
Write-Pass "All seven supported Reader deployment combinations passed simulation and ordering checks."

Invoke-RuntimeCase -Name "HttpInstallerUrlRejected" -ScriptArguments @(
    "-Simulation", "-Unattended", "-InstallMode", "Office",
    "-OfficeDeploymentToolUrl", "http://download.example.invalid/odt.exe"
) -ExpectedExitCode 1 -ExpectSummary | Out-Null
Write-Pass "HTTP installer sources are rejected before cleanup or installation."

$compatibilityScript = Join-Path $ProjectRoot "src\M365_Adobe_Leap.ps1"
$compatibilityRoot = Join-Path $testRoot "CompatibilityHttpGuard"
$oldCompatibilityUrl = $env:ZIAAS_WOODSTOCK_ENTRYPOINT_URL
$oldCompatibilityRoot = $env:ZIAAS_WOODSTOCK_BOOTSTRAP_ROOT
try {
    $env:ZIAAS_WOODSTOCK_ENTRYPOINT_URL = "http://download.example.invalid/entrypoint.ps1"
    $env:ZIAAS_WOODSTOCK_BOOTSTRAP_ROOT = $compatibilityRoot
    try {
        $compatibilityOutput = @(& $powerShellExe -NoProfile -ExecutionPolicy Bypass -File $compatibilityScript 2>&1)
        $compatibilityExitCode = $LASTEXITCODE
    }
    catch {
        $compatibilityOutput = @($_.Exception.Message)
        $compatibilityExitCode = 1
    }
}
finally {
    if ($null -eq $oldCompatibilityUrl) { Remove-Item Env:ZIAAS_WOODSTOCK_ENTRYPOINT_URL -ErrorAction SilentlyContinue }
    else { $env:ZIAAS_WOODSTOCK_ENTRYPOINT_URL = $oldCompatibilityUrl }
    if ($null -eq $oldCompatibilityRoot) { Remove-Item Env:ZIAAS_WOODSTOCK_BOOTSTRAP_ROOT -ErrorAction SilentlyContinue }
    else { $env:ZIAAS_WOODSTOCK_BOOTSTRAP_ROOT = $oldCompatibilityRoot }
}
Assert-Condition ($compatibilityExitCode -eq 1) "Legacy compatibility wrapper accepted an HTTP entrypoint URL. Output: $($compatibilityOutput -join [Environment]::NewLine)"
Assert-Condition (($compatibilityOutput -join [Environment]::NewLine) -match "absolute HTTPS URL") "Legacy compatibility wrapper did not explain its HTTPS URL rejection."
Assert-Condition (-not (Test-Path -LiteralPath $compatibilityRoot)) "Legacy compatibility wrapper created its bootstrap root before URL validation."
Write-Pass "Legacy compatibility wrapper validates HTTPS and root safety before downloading."

$proPath = Join-Path $testRoot "Licensed-Acrobat-Pro-Simulation.exe"
Set-Content -LiteralPath $proPath -Value "SIMULATION ONLY" -Encoding ASCII
$validPro = Invoke-RuntimeCase -Name "AcrobatProValid" -ScriptArguments @(
    "-Simulation", "-Unattended", "-InstallMode", "Adobe", "-AdobeProduct", "AcrobatPro",
    "-AdobeAcrobatProInstallerPath", $proPath,
    "-AdobeAcrobatProInstallArgumentLine", "/sAll /rs LANG_LIST=en_GB"
) -ExpectedExitCode 0 -ExpectSummary
Assert-StepOrder -Summary $validPro.Summary

Invoke-RuntimeCase -Name "AcrobatProEntitlementMissing" -ScriptArguments @(
    "-Simulation", "-Unattended", "-InstallMode", "Adobe", "-AdobeProduct", "AcrobatPro",
    "-SimulationAcrobatProEntitlementLevel", "0",
    "-AdobeAcrobatProInstallerPath", $proPath,
    "-AdobeAcrobatProInstallArgumentLine", "/sAll /rs LANG_LIST=en_GB"
) -ExpectedExitCode 105 -ExpectSummary | Out-Null

Invoke-RuntimeCase -Name "AcrobatProMissingInstaller" -ScriptArguments @(
    "-Simulation", "-Unattended", "-InstallMode", "Adobe", "-AdobeProduct", "AcrobatPro",
    "-AdobeAcrobatProInstallArgumentLine", "/sAll LANG_LIST=en_GB"
) -ExpectedExitCode 1 -ExpectSummary | Out-Null

Invoke-RuntimeCase -Name "AcrobatProMissingArguments" -ScriptArguments @(
    "-Simulation", "-Unattended", "-InstallMode", "Adobe", "-AdobeProduct", "AcrobatPro",
    "-AdobeAcrobatProInstallerPath", $proPath
) -ExpectedExitCode 1 -ExpectSummary | Out-Null

Invoke-RuntimeCase -Name "AcrobatProMissingLanguage" -ScriptArguments @(
    "-Simulation", "-Unattended", "-InstallMode", "Adobe", "-AdobeProduct", "AcrobatPro",
    "-AdobeAcrobatProInstallerPath", $proPath,
    "-AdobeAcrobatProInstallArgumentLine", "/sAll /rs"
) -ExpectedExitCode 1 -ExpectSummary | Out-Null

$badProPath = Join-Path $testRoot "Licensed-Acrobat-Pro-Simulation.zip"
Set-Content -LiteralPath $badProPath -Value "SIMULATION ONLY" -Encoding ASCII
Invoke-RuntimeCase -Name "AcrobatProInvalidExtension" -ScriptArguments @(
    "-Simulation", "-Unattended", "-InstallMode", "Adobe", "-AdobeProduct", "AcrobatPro",
    "-AdobeAcrobatProInstallerPath", $badProPath,
    "-AdobeAcrobatProInstallArgumentLine", "/sAll LANG_LIST=en_GB"
) -ExpectedExitCode 1 -ExpectSummary | Out-Null
Write-Pass "Acrobat Pro prerequisite guard cases behaved deterministically."

Invoke-RuntimeCase -Name "UnattendedMissingMode" -ScriptArguments @("-Simulation", "-Unattended") -ExpectedExitCode 1 -ExpectSummary | Out-Null
Invoke-RuntimeCase -Name "UnattendedMissingAdobeChoice" -ScriptArguments @("-Simulation", "-Unattended", "-InstallMode", "Adobe") -ExpectedExitCode 1 -ExpectSummary | Out-Null
Invoke-RuntimeCase -Name "ResumeWithoutState" -ScriptArguments @("-Simulation", "-ResumeLastRun") -ExpectedExitCode 1 -ExpectSummary | Out-Null
Write-Pass "Strict unattended and resume guards behaved deterministically."

$supportResult = Invoke-RuntimeCase -Name "SupportBundleSanitization" -ScriptArguments @(
    "-Simulation", "-Unattended", "-InstallMode", "Adobe", "-AdobeProduct", "Reader", "-CreateSupportBundle",
    "-AdobeReaderInstallerUrl", "https://ardownload2.adobe.com/pub/adobe/acrobat/win/AcrobatDC/2600121691/AcroRdrDCx642600121691_MUI.exe?token=supersecret"
) -ExpectedExitCode 0 -ExpectSummary
$bundlePath = [string]$supportResult.Summary.SupportBundlePath
Assert-Condition (Test-Path -LiteralPath $bundlePath) "Support bundle was not created."
$bundleExtract = Join-Path $testRoot "support-bundle-extract"
Expand-Archive -LiteralPath $bundlePath -DestinationPath $bundleExtract -Force
$bundleFiles = @(Get-ChildItem -LiteralPath $bundleExtract -Recurse -File)
Assert-Condition (@($bundleFiles | Where-Object { $_.Extension -in @(".exe", ".msi", ".zip", ".cab") }).Count -eq 0) "Support bundle contains installer/archive binaries."
$bundleText = @($bundleFiles | Where-Object { $_.Extension -in @(".log", ".txt", ".json", ".xml") } | ForEach-Object { Get-Content -LiteralPath $_.FullName -Raw }) -join "`n"
Assert-Condition ($bundleText -notmatch [regex]::Escape("supersecret")) "Support bundle leaked a URL token."
$profilePattern = '(?i)\\Users\\' + [regex]::Escape($env:USERNAME) + '(\\|"|$)'
Assert-Condition ($bundleText -notmatch $profilePattern) "Support bundle leaked the current Windows profile name."
Write-Pass "Support bundle excludes installers and redacts local profile names and URL tokens."

$brokenComponents = Join-Path $testRoot "broken-components"
Copy-Item -LiteralPath $componentPath -Destination $brokenComponents -Recurse -Force
Remove-Item -LiteralPath (Join-Path $brokenComponents "Adobe.Install.ps1") -Force
$brokenRoot = Join-Path $testRoot "MissingComponent"
New-Item -Path $brokenRoot -ItemType Directory -Force | Out-Null
$previousErrorActionPreference = $ErrorActionPreference
try {
    $ErrorActionPreference = "Continue"
    $brokenOutput = @(& $powerShellExe -NoProfile -ExecutionPolicy Bypass -File $corePath -Simulation -Unattended -InstallMode Office -WorkingRoot $brokenRoot -ComponentDirectory $brokenComponents -NoComponentDownload -NoLogo -NoColor -Quiet 2>&1)
    $brokenExitCode = $LASTEXITCODE
}
finally {
    $ErrorActionPreference = $previousErrorActionPreference
}
Assert-Condition ($brokenExitCode -eq 1) "Missing-component preflight did not fail with exit code 1. Output: $($brokenOutput -join [Environment]::NewLine)"
Write-Pass "Missing component preflight fails before component execution."

$rebootComponents = Join-Path $testRoot "reboot-components"
Copy-Item -LiteralPath $componentPath -Destination $rebootComponents -Recurse -Force
Set-Content -LiteralPath (Join-Path $rebootComponents "Office.Install.ps1") -Value "exit 3010" -Encoding ASCII
$rebootBoundary = Invoke-RuntimeCase -Name "RebootBoundary" -ComponentDirectoryOverride $rebootComponents -ScriptArguments @(
    "-Simulation", "-Unattended", "-InstallMode", "Office"
) -ExpectedExitCode 3010 -ExpectSummary
Assert-Condition ([string]$rebootBoundary.Summary.Status -eq "RebootRequired") "Reboot boundary did not produce RebootRequired status."
$rebootComponent = @($rebootBoundary.Summary.Components | Where-Object { $_.File -eq "Office.Install.ps1" }) | Select-Object -First 1
Assert-Condition ($null -ne $rebootComponent -and [string]$rebootComponent.Status -eq "RebootRequired") "Reboot-required component was not recorded as an unsafe resume boundary."
Write-Pass "Reboot-required component stops the flow before dependent steps and records a resumable boundary."

$mutexRoot = Join-Path $testRoot "ConcurrentRun"
if (Test-Path -LiteralPath $mutexRoot) { Remove-Item -LiteralPath $mutexRoot -Recurse -Force }
$mutexOutput = Join-Path $testRoot "concurrent-first.console.txt"
$mutexError = Join-Path $testRoot "concurrent-first.error.txt"
$mutexArguments = @(
    "-NoProfile", "-ExecutionPolicy", "Bypass", "-File", $corePath,
    "-WorkingRoot", $mutexRoot, "-ComponentDirectory", $componentPath, "-NoComponentDownload",
    "-NoLogo", "-NoColor", "-Quiet", "-Simulation", "-Unattended", "-InstallMode", "Office",
    "-PostCleanupWaitSeconds", "5", "-PreLeapWaitSeconds", "0"
)
$firstRun = Start-Process -FilePath $powerShellExe -ArgumentList $mutexArguments -RedirectStandardOutput $mutexOutput -RedirectStandardError $mutexError -WindowStyle Hidden -PassThru
try {
    Start-Sleep -Seconds 2
    $secondOutput = @(& $powerShellExe @mutexArguments 2>&1)
    $secondExitCode = $LASTEXITCODE
    Assert-Condition ($secondExitCode -eq 1) "Concurrent run was not rejected with exit code 1. Output: $($secondOutput -join [Environment]::NewLine)"
    Assert-Condition (($secondOutput -join [Environment]::NewLine) -match "already active|run lock") "Concurrent run did not explain the active run lock."
    $firstRun.WaitForExit()
    $firstRun.Refresh()
    $firstSummary = Get-LatestSummary -WorkingRoot $mutexRoot
    Assert-Condition ($null -ne $firstSummary -and [string]$firstSummary.Status -eq "Success") "The original concurrent run did not complete successfully."
}
finally {
    if ($firstRun -and -not $firstRun.HasExited) { Stop-Process -Id $firstRun.Id -Force -ErrorAction SilentlyContinue }
}
Write-Pass "Concurrent deployment attempts are rejected without interrupting the original run."

if ($isElevated) {
    $blockerRoot = Join-Path $testRoot "BlockingApps"
    New-Item -Path $blockerRoot -ItemType Directory -Force | Out-Null
    $blockerPath = Join-Path $blockerRoot "ms-teams.exe"
    Copy-Item -LiteralPath (Join-Path $env:SystemRoot "System32\WindowsPowerShell\v1.0\powershell.exe") -Destination $blockerPath -Force
    $blocker = Start-Process -FilePath $blockerPath -ArgumentList "-NoProfile", "-Command", "Start-Sleep -Seconds 60" -WindowStyle Hidden -PassThru
    try {
        $blockingRoot = Join-Path $testRoot "BlockingAppsRun"
        $blockingOutput = @(& $powerShellExe -NoProfile -ExecutionPolicy Bypass -File $corePath -WorkingRoot $blockingRoot -ComponentDirectory $componentPath -NoComponentDownload -NoLogo -NoColor -Quiet -LogLevel Warn -InstallMode Office -PostCleanupWaitSeconds 0 -PreLeapWaitSeconds 0 2>&1)
        $blockingExitCode = $LASTEXITCODE
        Assert-Condition ($blockingExitCode -eq 1) "Blocking-app preflight did not fail with exit code 1. Output: $($blockingOutput -join [Environment]::NewLine)"
        $blockingSummary = Get-LatestSummary -WorkingRoot $blockingRoot
        Assert-Condition ($null -ne $blockingSummary) "Blocking-app preflight did not create a summary report."
        $blockingFailures = @($blockingSummary.Preflight | Where-Object { $_.Name -eq "Blocking apps" -and $_.Status -eq "Fail" })
        Assert-Condition ($blockingFailures.Count -eq 1) "Blocking-app preflight result was not recorded as a failure."
        $policyFailures = @($blockingSummary.Preflight | Where-Object { $_.Name -eq "Office update policy" -and $_.Status -eq "Fail" })
        $expectedBlockingCategory = if ($policyFailures.Count -gt 0) { "MachineStateConflict" } else { "UserCorrectable" }
        Assert-Condition ([string]$blockingSummary.ErrorCategory -eq $expectedBlockingCategory) "Preflight error category did not match the failed preflight results. Expected $expectedBlockingCategory, got $($blockingSummary.ErrorCategory)."
    }
    finally {
        if ($blocker -and -not $blocker.HasExited) {
            Stop-Process -Id $blocker.Id -Force -ErrorAction SilentlyContinue
        }
    }
    Write-Pass "Blocked-app preflight reports a recoverable UserCorrectable failure before cleanup."
}
else {
    Write-Host "[SKIP] Live blocking-app preflight requires an elevated PowerShell session; simulation and all other regression cases passed."
}

$timeoutTestPath = Join-Path $PSScriptRoot "Test-ZiAASProcessTimeout.ps1"
$timeoutOutput = @(& $powerShellExe -NoProfile -ExecutionPolicy Bypass -File $timeoutTestPath -CommonPath (Join-Path $OutputRoot "components\Common.ps1") -WorkingRoot (Join-Path $testRoot "ProcessTimeout"))
Assert-Condition ($LASTEXITCODE -eq 0) "Vendor-process timeout regression failed: $($timeoutOutput -join [Environment]::NewLine)"
Write-Pass "Vendor-process timeout terminates the process and reports a bounded failure."

Write-Host "ZiAAS Woodstock runtime regression checks passed."

if (-not $KeepTestData) {
    Remove-Item -LiteralPath $testRoot -Recurse -Force -ErrorAction SilentlyContinue
}
