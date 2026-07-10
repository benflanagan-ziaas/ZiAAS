#requires -version 5.1
<#
ZiAAS Woodstock Baselining GitHub entrypoint.

Downloads the validated core script and component package from this repository,
decodes them into ProgramData, and starts the core script with the original
arguments. The core script handles product selection, cleanup, install order,
logging, reports, and component extraction.
#>

[CmdletBinding()]
param(
    [Parameter(ValueFromRemainingArguments = $true)]
    [object[]]$ForwardedArguments
)

Set-StrictMode -Version 2.0
$ErrorActionPreference = "Stop"
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

$defaultRawBase = "https://raw.githubusercontent.com/benflanagan-ziaas/ZiAAS/refs/heads/main/ZiAAS_Woodstock_Baselining"
$rawBase = if ([string]::IsNullOrWhiteSpace($env:ZIAAS_WOODSTOCK_RAW_BASE)) { $defaultRawBase } else { $env:ZIAAS_WOODSTOCK_RAW_BASE.TrimEnd("/") }
$root = if ([string]::IsNullOrWhiteSpace($env:ZIAAS_WOODSTOCK_BOOTSTRAP_ROOT)) { Join-Path $env:ProgramData "ZiAAS_Woodstock_Baselining" } else { $env:ZIAAS_WOODSTOCK_BOOTSTRAP_ROOT }
$componentDir = Join-Path $root "components"
$corePath = Join-Path $root "ZiAAS_Woodstock_Baselining.core.ps1"
$coreB64Path = "$corePath.b64"
$packageB64Path = Join-Path $root "ZiAAS_Woodstock_Baselining.components.zip.b64"
$packageZipPath = Join-Path $root "ZiAAS_Woodstock_Baselining.components.zip"
$manifestPath = Join-Path $root "app.manifest.json"

function Get-ZiaasForwardedArgumentValue {
    param(
        [Parameter(Mandatory = $true)][string]$Name,
        [object[]]$ScriptArguments
    )

    for ($index = 0; $index -lt @($ScriptArguments).Count; $index++) {
        if ([string]$ScriptArguments[$index] -ieq "-$Name") {
            if ($index + 1 -lt @($ScriptArguments).Count) {
                return [string]$ScriptArguments[$index + 1]
            }
            return ""
        }
    }

    return ""
}

function Save-ZiaasRawFile {
    param(
        [Parameter(Mandatory = $true)][string]$Url,
        [Parameter(Mandatory = $true)][string]$Path
    )

    $tmp = "$Path.tmp"
    if (Test-Path -LiteralPath $tmp) {
        Remove-Item -LiteralPath $tmp -Force
    }

    Invoke-WebRequest -Uri $Url -OutFile $tmp -UseBasicParsing -TimeoutSec 120
    Move-Item -LiteralPath $tmp -Destination $Path -Force
}

function Save-ZiaasRawFileParts {
    param(
        [Parameter(Mandatory = $true)][string]$UrlPrefix,
        [Parameter(Mandatory = $true)][int]$PartCount,
        [Parameter(Mandatory = $true)][string]$Path
    )

    $tmp = "$Path.tmp"
    if (Test-Path -LiteralPath $tmp) {
        Remove-Item -LiteralPath $tmp -Force
    }

    for ($index = 1; $index -le $PartCount; $index++) {
        $partName = ("{0}.part{1:00}" -f $UrlPrefix, $index)
        $partPath = "$tmp.part$index"
        Save-ZiaasRawFile -Url $partName -Path $partPath
        Add-Content -LiteralPath $tmp -Value (Get-Content -LiteralPath $partPath -Raw).Trim() -NoNewline
        Remove-Item -LiteralPath $partPath -Force
    }

    Move-Item -LiteralPath $tmp -Destination $Path -Force
}

function Test-ZiaasArgumentPresent {
    param(
        [Parameter(Mandatory = $true)][string]$Name,
        [object[]]$ScriptArguments
    )

    foreach ($argument in @($ScriptArguments)) {
        if ([string]$argument -ieq "-$Name") {
            return $true
        }
    }

    return $false
}

function Get-ZiaasManifestArtifactHash {
    param(
        [Parameter(Mandatory = $true)]$Manifest,
        [Parameter(Mandatory = $true)][string]$Name
    )

    foreach ($artifact in @($Manifest.artifacts)) {
        if ([string]$artifact.name -eq $Name) {
            return [string]$artifact.sha256
        }
    }

    return ""
}

function Get-ZiaasManifestArtifactPartCount {
    param(
        [Parameter(Mandatory = $true)]$Manifest,
        [Parameter(Mandatory = $true)][string]$Name
    )

    foreach ($artifact in @($Manifest.artifacts)) {
        if ([string]$artifact.name -eq $Name) {
            if ($null -eq $artifact.PSObject.Properties["partCount"]) {
                throw "Manifest artifact '$Name' does not declare a partCount."
            }

            $partCount = [int]$artifact.partCount
            if ($partCount -lt 1) {
                throw "Manifest artifact '$Name' has an invalid partCount: $partCount."
            }

            return $partCount
        }
    }

    throw "Manifest artifact '$Name' was not found."
}

function Assert-ZiaasFileHash {
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [Parameter(Mandatory = $true)][string]$ExpectedHash,
        [Parameter(Mandatory = $true)][string]$Description
    )

    if ([string]::IsNullOrWhiteSpace($ExpectedHash)) {
        throw "Manifest did not contain a SHA-256 hash for $Description."
    }

    $actualHash = (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash
    if ($actualHash -ine $ExpectedHash) {
        throw "$Description hash mismatch. Expected $ExpectedHash, got $actualHash."
    }

    Write-Host "$Description hash verified."
}

if (-not (Test-Path -LiteralPath $root)) {
    New-Item -Path $root -ItemType Directory -Force | Out-Null
}
if (-not (Test-Path -LiteralPath $componentDir)) {
    New-Item -Path $componentDir -ItemType Directory -Force | Out-Null
}

Write-Host "Downloading ZiAAS Woodstock Baselining core..."
$manifestUrl = Get-ZiaasForwardedArgumentValue -Name "ManifestUrl" -ScriptArguments $ForwardedArguments
if ([string]::IsNullOrWhiteSpace($manifestUrl)) {
    $manifestUrl = "$rawBase/app.manifest.json"
}

Write-Host "Downloading ZiAAS Woodstock Baselining manifest..."
Save-ZiaasRawFile -Url $manifestUrl -Path $manifestPath
$expectedManifestHash = Get-ZiaasForwardedArgumentValue -Name "ExpectedManifestHash" -ScriptArguments $ForwardedArguments
if (-not [string]::IsNullOrWhiteSpace($expectedManifestHash)) {
    Assert-ZiaasFileHash -Path $manifestPath -ExpectedHash $expectedManifestHash -Description "Release manifest"
}
$manifest = Get-Content -LiteralPath $manifestPath -Raw | ConvertFrom-Json
if ($null -eq $manifest.PSObject.Properties["artifacts"]) {
    throw "Release manifest is missing the artifacts contract."
}

$corePartCount = Get-ZiaasManifestArtifactPartCount -Manifest $manifest -Name "coreBase64"
Save-ZiaasRawFileParts -UrlPrefix "$rawBase/ZiAAS_Woodstock_Baselining.core.ps1.b64" -PartCount $corePartCount -Path $coreB64Path
Assert-ZiaasFileHash -Path $coreB64Path -ExpectedHash (Get-ZiaasManifestArtifactHash -Manifest $manifest -Name "coreBase64") -Description "Core base64 payload"
[System.IO.File]::WriteAllBytes($corePath, [Convert]::FromBase64String((Get-Content -LiteralPath $coreB64Path -Raw).Trim()))
Assert-ZiaasFileHash -Path $corePath -ExpectedHash (Get-ZiaasManifestArtifactHash -Manifest $manifest -Name "coreScript") -Description "Core script"

Write-Host "Downloading ZiAAS Woodstock Baselining component package..."
$componentPartCount = Get-ZiaasManifestArtifactPartCount -Manifest $manifest -Name "componentsBase64"
Save-ZiaasRawFileParts -UrlPrefix "$rawBase/ZiAAS_Woodstock_Baselining.components.zip.b64" -PartCount $componentPartCount -Path $packageB64Path
Assert-ZiaasFileHash -Path $packageB64Path -ExpectedHash (Get-ZiaasManifestArtifactHash -Manifest $manifest -Name "componentsBase64") -Description "Component package base64 payload"
[System.IO.File]::WriteAllBytes($packageZipPath, [Convert]::FromBase64String((Get-Content -LiteralPath $packageB64Path -Raw).Trim()))
Assert-ZiaasFileHash -Path $packageZipPath -ExpectedHash (Get-ZiaasManifestArtifactHash -Manifest $manifest -Name "componentsZip") -Description "Component package zip"
Expand-Archive -LiteralPath $packageZipPath -DestinationPath $componentDir -Force

Write-Host "Starting ZiAAS Woodstock Baselining..."
$bootstrapArgs = @()
if (-not (Test-ZiaasArgumentPresent -Name "ComponentDirectory" -ScriptArguments $ForwardedArguments)) {
    $bootstrapArgs += @("-ComponentDirectory", $componentDir)
}

& powershell.exe -NoProfile -ExecutionPolicy Bypass -File $corePath @bootstrapArgs @ForwardedArguments
exit $LASTEXITCODE
