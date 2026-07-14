#requires -version 5.1
[CmdletBinding()]
param(
    [string]$ProjectRoot,
    [string]$OutputRoot,
    [string]$Version = (Get-Date -Format "yyyy.MM.dd.HHmm"),
    [string]$RawBaseUrl = "https://raw.githubusercontent.com/benflanagan-ziaas/ZiAAS/refs/heads/main/ZiAAS_Woodstock_Baselining"
)

Set-StrictMode -Version 2.0
$ErrorActionPreference = "Stop"

if ([string]::IsNullOrWhiteSpace($ProjectRoot)) {
    $ProjectRoot = Split-Path -Parent $PSScriptRoot
}
if ([string]::IsNullOrWhiteSpace($OutputRoot)) {
    $OutputRoot = Join-Path (Split-Path -Parent (Split-Path -Parent $PSScriptRoot)) "outputs"
}

$srcRoot = Join-Path $ProjectRoot "src"
$srcComponents = Join-Path $srcRoot "components"
$srcConfig = Join-Path $srcRoot "config"
$outComponents = Join-Path $OutputRoot "components"
$outConfig = Join-Path $OutputRoot "config"

$requiredComponents = @(
    "Common.ps1",
    "Installers.Stage.ps1",
    "LEAP.RemoveClean.ps1",
    "Adobe.RemoveClean.ps1",
    "Office.RemoveClean.ps1",
    "Office.Install.ps1",
    "Adobe.Install.ps1",
    "LEAP.Install.ps1"
)

function Split-Base64File {
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [Parameter(Mandatory = $true)][int]$PartSize
    )

    $text = (Get-Content -LiteralPath $Path -Raw).Trim()
    $part = 1
    for ($offset = 0; $offset -lt $text.Length; $offset += $PartSize) {
        $length = [Math]::Min($PartSize, $text.Length - $offset)
        $partPath = "{0}.part{1:00}" -f $Path, $part
        [System.IO.File]::WriteAllText($partPath, $text.Substring($offset, $length), [System.Text.Encoding]::ASCII)
        $part++
    }

    return ($part - 1)
}

function Get-Artifact {
    param(
        [Parameter(Mandatory = $true)][string]$Name,
        [Parameter(Mandatory = $true)][string]$Path,
        [int]$PartCount = 0
    )

    $item = Get-Item -LiteralPath $Path
    $artifact = [ordered]@{
        name = $Name
        file = $item.Name
        bytes = $item.Length
        sha256 = (Get-FileHash -LiteralPath $item.FullName -Algorithm SHA256).Hash
        rawUrl = "$RawBaseUrl/$($item.Name)"
    }
    if ($PartCount -gt 0) {
        $artifact.partCount = $PartCount
    }

    return $artifact
}

if (-not (Test-Path -LiteralPath $srcRoot)) {
    throw "Source root not found: $srcRoot"
}
foreach ($file in @("ZiAAS_Woodstock_Baselining.ps1", "ZiAAS_Woodstock_Baselining.entrypoint.ps1", "ZiAAS_Woodstock_Baselining.cmd")) {
    if (-not (Test-Path -LiteralPath (Join-Path $srcRoot $file))) {
        throw "Missing source file: $file"
    }
}
foreach ($component in $requiredComponents) {
    if (-not (Test-Path -LiteralPath (Join-Path $srcComponents $component))) {
        throw "Missing component source: $component"
    }
}

New-Item -Path $OutputRoot -ItemType Directory -Force | Out-Null
New-Item -Path $outComponents -ItemType Directory -Force | Out-Null
New-Item -Path $outConfig -ItemType Directory -Force | Out-Null

$coreScript = Join-Path $OutputRoot "ZiAAS_Woodstock_Baselining.core.ps1"
$publicEntrypoint = Join-Path $OutputRoot "ZiAAS_Woodstock_Baselining.ps1"
Copy-Item -LiteralPath (Join-Path $srcRoot "ZiAAS_Woodstock_Baselining.ps1") -Destination $coreScript -Force
Copy-Item -LiteralPath (Join-Path $srcRoot "ZiAAS_Woodstock_Baselining.entrypoint.ps1") -Destination $publicEntrypoint -Force
Copy-Item -LiteralPath (Join-Path $srcRoot "ZiAAS_Woodstock_Baselining.entrypoint.ps1") -Destination (Join-Path $OutputRoot "ZiAAS_Woodstock_Baselining.entrypoint.ps1") -Force
Copy-Item -LiteralPath (Join-Path $srcRoot "ZiAAS_Woodstock_Baselining.cmd") -Destination (Join-Path $OutputRoot "ZiAAS_Woodstock_Baselining.cmd") -Force
if (Test-Path -LiteralPath (Join-Path $srcRoot "M365_Adobe_Leap.ps1")) {
    Copy-Item -LiteralPath (Join-Path $srcRoot "M365_Adobe_Leap.ps1") -Destination (Join-Path $OutputRoot "M365_Adobe_Leap.ps1") -Force
}
foreach ($component in $requiredComponents) {
    Copy-Item -LiteralPath (Join-Path $srcComponents $component) -Destination (Join-Path $outComponents $component) -Force
}
if (Test-Path -LiteralPath $srcConfig) {
    Get-ChildItem -LiteralPath $srcConfig -Filter *.json -File | ForEach-Object {
        Copy-Item -LiteralPath $_.FullName -Destination (Join-Path $outConfig $_.Name) -Force
    }
}

$componentZip = Join-Path $OutputRoot "ZiAAS_Woodstock_Baselining.components.zip"
if (Test-Path -LiteralPath $componentZip) {
    Remove-Item -LiteralPath $componentZip -Force
}
$componentPaths = @($requiredComponents | ForEach-Object { Join-Path $outComponents $_ })
Compress-Archive -LiteralPath $componentPaths -DestinationPath $componentZip -Force

$componentB64 = Join-Path $OutputRoot "ZiAAS_Woodstock_Baselining.components.zip.b64"
$coreB64 = Join-Path $OutputRoot "ZiAAS_Woodstock_Baselining.core.ps1.b64"
[System.IO.File]::WriteAllText($componentB64, [Convert]::ToBase64String([System.IO.File]::ReadAllBytes($componentZip)), [System.Text.Encoding]::ASCII)
[System.IO.File]::WriteAllText($coreB64, [Convert]::ToBase64String([System.IO.File]::ReadAllBytes($coreScript)), [System.Text.Encoding]::ASCII)

Get-ChildItem -LiteralPath $OutputRoot -Filter "ZiAAS_Woodstock_Baselining.components.zip.b64.part*" -ErrorAction SilentlyContinue | Remove-Item -Force
Get-ChildItem -LiteralPath $OutputRoot -Filter "ZiAAS_Woodstock_Baselining.core.ps1.b64.part*" -ErrorAction SilentlyContinue | Remove-Item -Force
$componentB64PartCount = Split-Base64File -Path $componentB64 -PartSize 8000
$coreB64PartCount = Split-Base64File -Path $coreB64 -PartSize 7000

$brandPath = Join-Path $outConfig "brand.ziaas-woodstock.json"
$brand = $null
if (Test-Path -LiteralPath $brandPath) {
    $brand = Get-Content -LiteralPath $brandPath -Raw | ConvertFrom-Json
}

$manifest = [ordered]@{
    name = "ZiAAS Woodstock Baselining"
    version = $Version
    publisher = "ZiAAS"
    brand = $brand
    releaseDate = (Get-Date).ToString("s")
    minimumPowerShellVersion = "5.1"
    entrypoint = "ZiAAS_Woodstock_Baselining.ps1"
    launcher = "ZiAAS_Woodstock_Baselining.cmd"
    componentDirectory = "components"
    defaultWorkingRoot = "C:\ProgramData\ZiAAS_Woodstock_Baselining"
    rawBaseUrl = $RawBaseUrl
    componentBaseUrl = "$RawBaseUrl/components"
    downloadRetryDefaults = [ordered]@{
        attempts = 3
        delaySeconds = 5
    }
    requiredComponents = $requiredComponents
    defaultFlow = @(
        "preflight",
        "Installers.Stage",
        "LEAP.RemoveClean",
        "Adobe.RemoveClean",
        "Office.RemoveClean",
        "PostCleanupWait",
        "Office.Install",
        "Adobe.Install",
        "PreLeapWait",
        "LEAP.Install",
        "final-report"
    )
    artifacts = @(
        (Get-Artifact -Name "coreScript" -Path $coreScript),
        (Get-Artifact -Name "coreBase64" -Path $coreB64 -PartCount $coreB64PartCount),
        (Get-Artifact -Name "componentsZip" -Path $componentZip),
        (Get-Artifact -Name "componentsBase64" -Path $componentB64 -PartCount $componentB64PartCount),
        (Get-Artifact -Name "entrypoint" -Path $publicEntrypoint)
    )
    exitCodes = [ordered]@{
        "0" = "Success"
        "1" = "Orchestrator or preflight failure"
        "20" = "Operator cancelled"
        "100" = "Installer staging or signature verification failed before cleanup"
        "101" = "LEAP remove/clean failed"
        "102" = "Adobe remove/clean failed"
        "103" = "Office remove/clean failed"
        "104" = "Office install failed"
        "105" = "Adobe install or policy failed"
        "106" = "LEAP install failed"
        "3010" = "Reboot required"
    }
}

$manifestPath = Join-Path $OutputRoot "app.manifest.json"
$manifest | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath $manifestPath -Encoding UTF8

Write-Host "Built ZiAAS Woodstock Baselining artifacts in $OutputRoot"
Write-Host "Manifest: $manifestPath"
