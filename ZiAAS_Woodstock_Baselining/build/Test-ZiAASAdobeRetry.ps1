#requires -version 5.1
[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)][string]$CommonPath
)

Set-StrictMode -Version 2.0
$ErrorActionPreference = "Stop"

$testRoot = Join-Path ([IO.Path]::GetTempPath()) "ZiAAS-AdobeRetry-$PID"
New-Item -Path (Join-Path $testRoot "Logs") -ItemType Directory -Force | Out-Null
$Script:ZiaasConfig = [pscustomobject]@{
    WorkingRoot = $testRoot
    Simulation = $true
    ComponentName = "AdobeRetryTest"
    RunStamp = Get-Date -Format "yyyyMMdd-HHmmss"
}
. $CommonPath

$Script:attempts = 0
$Script:sleepCalls = @()

function Invoke-ProcessChecked {
    param(
        [string]$FilePath,
        [string[]]$ArgumentList,
        [int[]]$SuccessExitCodes,
        [string]$Description
    )

    $Script:attempts++
    $Script:LastProcessExitCode = if ($Script:attempts -eq 1) { 1618 } else { 0 }
}

function Start-Sleep {
    param([int]$Seconds, [int]$Milliseconds)
    $Script:sleepCalls += [pscustomobject]@{ Seconds = $Seconds; Milliseconds = $Milliseconds }
}

Invoke-AdobeMsiUninstallWithRetry `
    -ProductCode "{11111111-2222-3333-4444-555555555555}" `
    -MsiLog (Join-Path $testRoot "Logs\Adobe-retry.log") `
    -ProductName "Adobe Acrobat (64-bit)"

if ($Script:attempts -ne 2) {
    throw "Adobe retry test expected exactly two MSI uninstall attempts, observed $Script:attempts."
}
if (@($Script:sleepCalls | Where-Object { $_.Seconds -eq 30 }).Count -ne 1) {
    throw "Adobe retry test did not perform the expected bounded 30-second wait."
}

Write-Host "[PASS] Adobe Windows Installer 1618 retry path completed after one bounded retry."
