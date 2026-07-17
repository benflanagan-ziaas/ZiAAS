#requires -version 5.1
[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)][string]$CommonPath
)

Set-StrictMode -Version 2.0
$ErrorActionPreference = "Stop"

$testRoot = Join-Path ([IO.Path]::GetTempPath()) "ZiAAS-LeapHardening-$PID"
New-Item -Path $testRoot -ItemType Directory -Force | Out-Null

try {
    $Script:ZiaasConfig = [pscustomobject]@{
        WorkingRoot = $testRoot
        Simulation = $false
        ComponentName = "LeapHardeningTest"
        RunStamp = Get-Date -Format "yyyyMMdd-HHmmss"
    }
    . $CommonPath

    $pagePayload = @"
Latest Version: 2.5.620.0
Download LEAP Desktop
https://leaphome.sharepoint.com/sites/download/2.5.619.0/LEAPDesktopX64Setup.exe
Download LEAP Desktop
https://leaphome.sharepoint.com/sites/download/2.5.620.0/LEAPDesktopX64Setup.exe
"@
    $resolved = Get-LeapInstallerLinkFromContent -Content $pagePayload
    if (-not $resolved -or $resolved.Version -ne "2.5.620.0" -or $resolved.Url -notmatch "2\.5\.620\.0") {
        throw "LEAP download parser did not select the highest versioned official installer candidate."
    }

    function Get-UninstallEntries {
        return @(
            [pscustomobject]@{ DisplayName = "LEAP Desktop"; DisplayVersion = "2.5.620.0"; Publisher = "LEAP Legal Software"; InstallLocation = "C:\Program Files\LEAP Office" },
            [pscustomobject]@{ DisplayName = "LEAP Accounting Plus"; DisplayVersion = "1.0"; Publisher = "LEAP Software Developments"; InstallLocation = "C:\Users\Test\AppData\Local\LEAP-Accounting-Plus" },
            [pscustomobject]@{ DisplayName = "LEAP System Audit"; DisplayVersion = "1.0"; Publisher = "LEAP"; InstallLocation = "C:\Program Files\LEAP System Audit" }
        )
    }
    function Get-LocalUserProfileRecords { return @() }
    $entries = @(Get-LeapEntries)
    if (@($entries | Where-Object { $_.DisplayName -eq "LEAP System Audit" }).Count -ne 0) {
        throw "LEAP System Audit was incorrectly classified as a removable LEAP product."
    }
    if (@($entries | Where-Object { $_.DisplayName -eq "LEAP Desktop" }).Count -ne 1) {
        throw "LEAP Desktop was not detected from its uninstall entry."
    }

    $hostExe = Join-Path $env:SystemRoot "System32\WindowsPowerShell\v1.0\powershell.exe"
    $fakeLeapExe = Join-Path $testRoot "LEAPAccounting.exe"
    Copy-Item -LiteralPath $hostExe -Destination $fakeLeapExe -Force
    $fakeProcess = Start-Process -FilePath $fakeLeapExe -ArgumentList @("-NoProfile", "-Command", "Start-Sleep -Seconds 90") -WindowStyle Hidden -PassThru
    try {
        Start-Sleep -Milliseconds 750
        $detected = @(Get-LeapPostInstallProcesses | Where-Object { $_.Id -eq $fakeProcess.Id })
        if ($detected.Count -ne 1) {
            throw "The LEAP post-install process detector did not identify the actual LEAPAccounting process name."
        }
    }
    finally {
        if (-not $fakeProcess.HasExited) {
            Stop-Process -Id $fakeProcess.Id -Force -ErrorAction SilentlyContinue
        }
    }

    Write-Host "[PASS] LEAP download selection, product filtering, and post-install process detection hardening passed."
}
finally {
    if (Test-Path -LiteralPath $testRoot) {
        Remove-Item -LiteralPath $testRoot -Recurse -Force -ErrorAction SilentlyContinue
    }
}
