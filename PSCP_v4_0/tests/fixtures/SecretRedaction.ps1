[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
$clientSecret = 'super-secret-static-value-12345'
$connectionString = 'Server=db.invalid;User Id=admin;Password=DoNotLeakThisPassword!;'
Write-Output $clientSecret
Write-Output $connectionString
