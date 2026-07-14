#requires -version 5.1
[CmdletBinding()]
param(
    [string]$CommonPath,
    [string]$WorkingRoot
)

Set-StrictMode -Version 2.0
$ErrorActionPreference = "Stop"

if ([string]::IsNullOrWhiteSpace($CommonPath)) {
    $projectRoot = Split-Path -Parent $PSScriptRoot
    $CommonPath = Join-Path $projectRoot "src\components\Common.ps1"
}
if ([string]::IsNullOrWhiteSpace($WorkingRoot)) {
    $WorkingRoot = Join-Path ([System.IO.Path]::GetTempPath()) ("ZiAAS-timeout-test-" + [guid]::NewGuid().ToString("N"))
}

$Script:ZiaasConfig = [pscustomobject]@{
    WorkingRoot = $WorkingRoot
    Simulation = $false
    ComponentName = "Process-Timeout-Test"
    RunStamp = Get-Date -Format "yyyyMMdd-HHmmss"
    Quiet = $true
    NoColor = $true
    LogLevel = "Warn"
}
. $CommonPath

Initialize-DeploymentFolders
$stopwatch = [Diagnostics.Stopwatch]::StartNew()
$timedOutProcessId = 0
try {
    Invoke-ProcessChecked `
        -FilePath "$env:SystemRoot\System32\WindowsPowerShell\v1.0\powershell.exe" `
        -ArgumentList @("-NoProfile", "-Command", "Start-Sleep -Seconds 30") `
        -Description "Intentional timeout regression process" `
        -TimeoutSeconds 2
    throw "Timeout regression failed: the sleeper returned without a timeout."
}
catch {
    if ($_.Exception.Message -notmatch "timed out after 2 seconds") {
        throw
    }
    if (-not $_.Exception.Data.Contains("ZiaasTimedOutProcessId")) {
        throw "Timeout regression did not report the terminated process ID."
    }
    $timedOutProcessId = [int]$_.Exception.Data["ZiaasTimedOutProcessId"]
}
finally {
    $stopwatch.Stop()
}

if ($stopwatch.Elapsed.TotalSeconds -gt 15) {
    throw "Timeout regression took too long: $($stopwatch.Elapsed)."
}
if (Get-Process -Id $timedOutProcessId -ErrorAction SilentlyContinue) {
    throw "Timed-out regression process $timedOutProcessId is still running."
}

Write-Host "[PASS] Timed-out vendor process trees are terminated and reported within the configured bound."
