#requires -version 5.1
[CmdletBinding()]
param(
    [string]$OutputRoot
)

Set-StrictMode -Version 2.0
$ErrorActionPreference = "Stop"

if ([string]::IsNullOrWhiteSpace($OutputRoot)) {
    $OutputRoot = Join-Path (Split-Path -Parent (Split-Path -Parent $PSScriptRoot)) "outputs"
}

$commonPath = Join-Path $OutputRoot "components\Common.ps1"
if (-not (Test-Path -LiteralPath $commonPath -PathType Leaf)) {
    throw "Generated Common.ps1 was not found: $commonPath"
}

$testRoot = Join-Path ([IO.Path]::GetTempPath()) "ZiAAS-ProfileDiscovery-$PID"
$Script:ZiaasConfig = [pscustomobject]@{
    WorkingRoot = $testRoot
    Simulation = $false
    ComponentName = "ProfileDiscoveryTest"
    RunStamp = Get-Date -Format "yyyyMMdd-HHmmss"
}

. $commonPath

$profiles = @(Get-LocalUserProfileRecords)
$duplicateSids = @($profiles | Group-Object Sid | Where-Object { $_.Count -gt 1 })
if ($duplicateSids.Count -gt 0) {
    throw "Profile discovery returned duplicate SID records: $($duplicateSids.Name -join ', ')"
}

foreach ($profileRecord in $profiles) {
    [void](New-Object Security.Principal.SecurityIdentifier([string]$profileRecord.Sid))
    if (-not (Test-Path -LiteralPath $profileRecord.LocalPath -PathType Container)) {
        throw "Profile discovery returned an inaccessible path: $($profileRecord.LocalPath)"
    }
}

$currentProfile = [IO.Path]::GetFullPath([Environment]::GetFolderPath("UserProfile")).TrimEnd('\')
$usersRoot = [IO.Path]::GetFullPath((Join-Path $env:SystemDrive "Users"))
if ($currentProfile.StartsWith("$usersRoot\", [StringComparison]::OrdinalIgnoreCase)) {
    $currentSid = [Security.Principal.WindowsIdentity]::GetCurrent().User.Value
    $currentMatches = @($profiles | Where-Object { $_.Sid -eq $currentSid -and $_.LocalPath -eq $currentProfile })
    if ($currentMatches.Count -ne 1) {
        throw "The current local/Azure AD profile was not discovered exactly once. SID=$currentSid Path=$currentProfile"
    }
}

$accountingFolders = @($profiles | ForEach-Object {
    Join-Path $_.LocalPath "AppData\Local\LEAP-Accounting-Plus"
} | Where-Object {
    Test-Path -LiteralPath (Join-Path $_ "Update.exe") -PathType Leaf
})

if ($accountingFolders.Count -gt 0) {
    $entries = @(Get-LeapEntries | Where-Object { $_.DisplayName -eq "LEAP Accounting Plus" })
    foreach ($folder in $accountingFolders) {
        $matchingEntries = @($entries | Where-Object {
            -not [string]::IsNullOrWhiteSpace([string]$_.InstallLocation) -and
            [IO.Path]::GetFullPath([string]$_.InstallLocation).TrimEnd('\') -eq [IO.Path]::GetFullPath($folder).TrimEnd('\')
        })
        if ($matchingEntries.Count -lt 1) {
            throw "LEAP Accounting Plus was not discovered from profile path: $folder"
        }
        if (@($matchingEntries | Where-Object { [string]::IsNullOrWhiteSpace([string]$_.QuietUninstallString) }).Count -gt 0) {
            throw "A discovered LEAP Accounting Plus entry does not expose a quiet uninstall command: $folder"
        }
    }
}

Write-Host "[PASS] Local and Azure AD profile discovery returned $($profiles.Count) valid profile record(s)."
Write-Host "[PASS] LEAP Accounting profile-path fallback is coherent for $($accountingFolders.Count) detected installation(s)."
