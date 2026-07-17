#requires -version 5.1
<#
Compatibility entrypoint for the previous ZiAAS Office/Adobe/LEAP raw URL.

The canonical script is now ZiAAS_Woodstock_Baselining.ps1. This wrapper keeps
older run commands alive by downloading the canonical entrypoint and forwarding
all supplied arguments.
#>

[CmdletBinding()]
param(
    [Parameter(ValueFromRemainingArguments = $true)]
    [object[]]$ForwardedArguments
)

Set-StrictMode -Version 2.0
$ErrorActionPreference = "Stop"
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

$defaultRawBase = "https://raw.githubusercontent.com/benflanagan-ziaas/ZiAAS/refs/heads/main"
$rawBase = if ([string]::IsNullOrWhiteSpace($env:ZIAAS_WOODSTOCK_RAW_BASE)) { $defaultRawBase } else { $env:ZIAAS_WOODSTOCK_RAW_BASE.TrimEnd("/") }
$scriptUrl = if ([string]::IsNullOrWhiteSpace($env:ZIAAS_WOODSTOCK_ENTRYPOINT_URL)) {
    "$rawBase/ZiAAS_Woodstock_Baselining/ZiAAS_Woodstock_Baselining.ps1"
}
else {
    $env:ZIAAS_WOODSTOCK_ENTRYPOINT_URL
}
$root = if ([string]::IsNullOrWhiteSpace($env:ZIAAS_WOODSTOCK_BOOTSTRAP_ROOT)) {
    Join-Path $env:ProgramData "ZiAAS_Woodstock_Baselining"
}
else {
    $env:ZIAAS_WOODSTOCK_BOOTSTRAP_ROOT
}
$scriptPath = Join-Path $root "ZiAAS_Woodstock_Baselining.ps1"

function Assert-CompatibilityBootstrapUrl {
    param([Parameter(Mandatory = $true)][string]$Url, [Parameter(Mandatory = $true)][string]$Description)

    $uri = $null
    if (-not [Uri]::TryCreate($Url, [UriKind]::Absolute, [ref]$uri) -or $uri.Scheme -ne "https") {
        throw "$Description must be an absolute HTTPS URL: $Url"
    }
    return $uri
}

function Assert-CompatibilityBootstrapRoot {
    if ($root.StartsWith("\\")) {
        throw "Bootstrap root must be a local path, not a UNC path: $root"
    }
    $fullPath = [IO.Path]::GetFullPath($root).TrimEnd('\')
    $driveRoot = [IO.Path]::GetPathRoot($fullPath).TrimEnd('\')
    if ([string]::IsNullOrWhiteSpace($driveRoot) -or $fullPath -ieq $driveRoot) {
        throw "Bootstrap root cannot be a drive root: $fullPath"
    }
    $protected = @(
        $env:SystemRoot,
        $env:ProgramFiles,
        ${env:ProgramFiles(x86)},
        (Join-Path $env:SystemDrive "Users"),
        (Join-Path $env:SystemDrive "ProgramData")
    ) | Where-Object { $_ } | ForEach-Object { [IO.Path]::GetFullPath($_).TrimEnd('\') }
    if (@($protected | Where-Object { $fullPath -ieq $_ }).Count -gt 0) {
        throw "Bootstrap root points at a protected system directory: $fullPath"
    }
}

Assert-CompatibilityBootstrapUrl -Url $rawBase -Description "Compatibility bootstrap base URL" | Out-Null
Assert-CompatibilityBootstrapUrl -Url $scriptUrl -Description "Compatibility entrypoint URL" | Out-Null
Assert-CompatibilityBootstrapRoot

if (-not (Test-Path -LiteralPath $root)) {
    New-Item -Path $root -ItemType Directory -Force | Out-Null
}

$tmp = "$scriptPath.tmp"
if (Test-Path -LiteralPath $tmp) {
    Remove-Item -LiteralPath $tmp -Force
}

$manifestUrl = "$rawBase/ZiAAS_Woodstock_Baselining/app.manifest.json"
$manifestPath = Join-Path $root "app.manifest.json"
$manifestTmp = "$manifestPath.tmp"
if (Test-Path -LiteralPath $manifestTmp) {
    Remove-Item -LiteralPath $manifestTmp -Force
}

Write-Host "Downloading ZiAAS Woodstock Baselining release manifest..."
Invoke-WebRequest -Uri $manifestUrl -OutFile $manifestTmp -UseBasicParsing -TimeoutSec 120
$manifest = Get-Content -LiteralPath $manifestTmp -Raw | ConvertFrom-Json
if ([string]$manifest.publisher -ne "ZiAAS" -or [string]$manifest.rawBaseUrl.TrimEnd('/') -ne "$rawBase/ZiAAS_Woodstock_Baselining".TrimEnd('/')) {
    throw "Compatibility release manifest failed publisher or source validation."
}
$expectedManifestHash = $env:ZIAAS_WOODSTOCK_EXPECTED_MANIFEST_HASH
if (-not [string]::IsNullOrWhiteSpace($expectedManifestHash)) {
    $actualManifestHash = (Get-FileHash -LiteralPath $manifestTmp -Algorithm SHA256).Hash
    if ($actualManifestHash -ine $expectedManifestHash) {
        throw "Compatibility release manifest hash mismatch. Expected $expectedManifestHash, got $actualManifestHash."
    }
}
Move-Item -LiteralPath $manifestTmp -Destination $manifestPath -Force

$entrypointArtifact = @($manifest.artifacts | Where-Object { [string]$_.name -eq "entrypoint" }) | Select-Object -First 1
if ($null -eq $entrypointArtifact -or [string]$entrypointArtifact.sha256 -notmatch '^[0-9A-Fa-f]{64}$') {
    throw "Compatibility release manifest did not contain a valid entrypoint SHA-256 hash."
}

Write-Host "Downloading ZiAAS Woodstock Baselining entrypoint..."
Invoke-WebRequest -Uri $scriptUrl -OutFile $tmp -UseBasicParsing -TimeoutSec 120
$actualEntrypointHash = (Get-FileHash -LiteralPath $tmp -Algorithm SHA256).Hash
if ($actualEntrypointHash -ine [string]$entrypointArtifact.sha256) {
    throw "Compatibility entrypoint hash mismatch. Expected $($entrypointArtifact.sha256), got $actualEntrypointHash."
}
Move-Item -LiteralPath $tmp -Destination $scriptPath -Force

Write-Host "Starting ZiAAS Woodstock Baselining..."
$powerShellHost = Join-Path $env:SystemRoot "System32\WindowsPowerShell\v1.0\powershell.exe"
if (-not [Environment]::Is64BitProcess -and [Environment]::Is64BitOperatingSystem) {
    $sysnativeHost = Join-Path $env:SystemRoot "Sysnative\WindowsPowerShell\v1.0\powershell.exe"
    if (Test-Path -LiteralPath $sysnativeHost -PathType Leaf) {
        $powerShellHost = $sysnativeHost
    }
}
if (-not (Test-Path -LiteralPath $powerShellHost -PathType Leaf)) {
    $powerShellHost = "powershell.exe"
}
& $powerShellHost -NoProfile -ExecutionPolicy Bypass -File $scriptPath @ForwardedArguments
exit $LASTEXITCODE
