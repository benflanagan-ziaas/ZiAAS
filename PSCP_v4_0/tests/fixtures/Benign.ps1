#requires -Version 5.1
[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [ValidatePattern('^[A-Za-z0-9._-]{1,64}$')]
    [string]$Name
)

Set-StrictMode -Version 3.0
$ErrorActionPreference = 'Stop'

function ConvertTo-GreetingRecord {
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory = $true, ValueFromPipeline = $true)]
        [ValidatePattern('^[A-Za-z0-9._-]{1,64}$')]
        [string]$InputName
    )
    process {
        [pscustomobject][ordered]@{
            Name    = $InputName
            Message = 'Hello, {0}' -f $InputName
        }
    }
}

try {
    ConvertTo-GreetingRecord -InputName $Name
}
catch {
    throw "Greeting generation failed: $($_.Exception.Message)"
}
