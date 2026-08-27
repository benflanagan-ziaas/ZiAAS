[CmdletBinding()]
param(
    [string]$SentinelPath = $env:PSCP_TEST_SENTINEL
)

Set-StrictMode -Version 3.0
$ErrorActionPreference = 'Stop'
if ([string]::IsNullOrWhiteSpace($SentinelPath)) {
    throw 'PSCP_TEST_SENTINEL was not supplied.'
}
[IO.File]::WriteAllText($SentinelPath, 'TARGET WAS EXECUTED')
