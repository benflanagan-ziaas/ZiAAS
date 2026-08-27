#requires -Version 5.1
<#
.SYNOPSIS
    Downloads, verifies, caches, and runs the immutable PSCP PowerShell static analyzer.

.DESCRIPTION
    The analyzer is fetched from an immutable GitHub commit and must match the pinned
    SHA-256 before it is cached or executed. Target PowerShell is analyzed statically;
    this launcher never imports, dot-sources, or executes the target.
#>
[CmdletBinding(SupportsShouldProcess = $true)]
param(
    [Parameter(Mandatory = $true, Position = 0)]
    [ValidateNotNullOrEmpty()]
    [string[]]$Path,

    [ValidateSet('Quick', 'Standard', 'Maximum')]
    [string]$AnalysisProfile = 'Maximum',

    [ValidateSet('AutoInstall', 'Require', 'Offline')]
    [string]$DependencyMode = 'AutoInstall',

    [ValidateSet('Critical', 'Error', 'Warning', 'Information')]
    [string]$MinimumSeverity = 'Information',

    [string]$OutputPath,
    [string]$AnalyzerCachePath,
    [switch]$Refresh,
    [switch]$Offline,
    [switch]$NoExit
)

Set-StrictMode -Version 3.0
$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'

$analyzerVersion = '4.0.0'
$analyzerUri = 'https://raw.githubusercontent.com/benflanagan-ziaas/ZiAAS/a49352f0cbaf61486141b59995f93799efd02e34/PSCP_v4_0/Invoke-PSCP.ps1'
$expectedSha256 = 'A09E1895621DE9811C64F656FC0C86113207EB6297B7E3B4A801EF1826BBFA52'
$exitCode = 4

function Get-LauncherSha256 {
    param([Parameter(Mandatory = $true)][string]$LiteralPath)
    return (Get-FileHash -LiteralPath $LiteralPath -Algorithm SHA256 -ErrorAction Stop).Hash.ToUpperInvariant()
}

function Write-LauncherFailure {
    [CmdletBinding(SupportsShouldProcess = $true)]
    param([Parameter(Mandatory = $true)][string]$Message)
    $result = [pscustomobject][ordered]@{
        tool                      = [pscustomobject]@{ name = 'PowerShell Static Gate Launcher'; analyzer = 'PSCP'; analyzerVersion = $analyzerVersion }
        verdict                   = 'FATAL'
        exitCode                  = 4
        analysisComplete          = $false
        safeToBeginSandboxTesting = $false
        summary                   = [pscustomobject]@{
            directAnswer      = 'The mandatory PowerShell static gate could not run. Do not treat the script as validated.'
            recommendedAction = $Message
        }
    }
    $json = $result | ConvertTo-Json -Depth 6
    if ($OutputPath) {
        $parent = Split-Path -Parent ([IO.Path]::GetFullPath($OutputPath))
        if ($parent -and -not (Test-Path -LiteralPath $parent)) {
            if ($PSCmdlet.ShouldProcess($parent, 'Create report directory')) {
                $null = New-Item -ItemType Directory -Path $parent -Force -ErrorAction Stop
            }
        }
        $fullOutputPath = [IO.Path]::GetFullPath($OutputPath)
        if ($PSCmdlet.ShouldProcess($fullOutputPath, 'Write fatal gate report')) {
            [IO.File]::WriteAllText($fullOutputPath, $json, (New-Object Text.UTF8Encoding($false)))
        }
    }
    Write-Output $json
}

try {
    if (-not $AnalyzerCachePath) {
        $localAppData = [Environment]::GetFolderPath([Environment+SpecialFolder]::LocalApplicationData)
        if ([string]::IsNullOrWhiteSpace($localAppData)) { throw 'LocalApplicationData is unavailable; provide -AnalyzerCachePath explicitly.' }
        $AnalyzerCachePath = Join-Path $localAppData "ZiAAS\PSCP\SkillCache\$analyzerVersion\Invoke-PSCP.ps1"
    }
    $AnalyzerCachePath = [IO.Path]::GetFullPath($AnalyzerCachePath)
    $cacheDirectory = Split-Path -Parent $AnalyzerCachePath
    $cacheValid = (Test-Path -LiteralPath $AnalyzerCachePath -PathType Leaf) -and ((Get-LauncherSha256 -LiteralPath $AnalyzerCachePath) -eq $expectedSha256)

    if ($Refresh -or -not $cacheValid) {
        if ($Offline) {
            throw "No valid cached PSCP $analyzerVersion analyzer is available and -Offline forbids downloading it."
        }
        if (-not (Test-Path -LiteralPath $cacheDirectory)) {
            if ($PSCmdlet.ShouldProcess($cacheDirectory, 'Create verified analyzer cache directory')) {
                $null = New-Item -ItemType Directory -Path $cacheDirectory -Force -ErrorAction Stop
            }
        }
        $temporaryPath = Join-Path $cacheDirectory ('Invoke-PSCP.' + [Guid]::NewGuid().ToString('N') + '.download')
        try {
            Invoke-WebRequest -Uri $analyzerUri -OutFile $temporaryPath -UseBasicParsing -ErrorAction Stop
            $downloadedHash = Get-LauncherSha256 -LiteralPath $temporaryPath
            if ($downloadedHash -ne $expectedSha256) {
                throw "Downloaded analyzer hash mismatch. Expected $expectedSha256; received $downloadedHash."
            }
            if ($PSCmdlet.ShouldProcess($AnalyzerCachePath, 'Cache verified PSCP analyzer')) {
                Copy-Item -LiteralPath $temporaryPath -Destination $AnalyzerCachePath -Force -ErrorAction Stop
            }
        }
        finally {
            if ($temporaryPath -and (Test-Path -LiteralPath $temporaryPath)) {
                if ($PSCmdlet.ShouldProcess($temporaryPath, 'Remove temporary analyzer download')) {
                    Remove-Item -LiteralPath $temporaryPath -Force -ErrorAction Stop
                }
            }
        }
    }

    $cachedHash = Get-LauncherSha256 -LiteralPath $AnalyzerCachePath
    if ($cachedHash -ne $expectedSha256) { throw "Cached analyzer hash mismatch. Expected $expectedSha256; received $cachedHash." }

    $arguments = @(
        '-NoLogo', '-NoProfile', '-NonInteractive', '-File', $AnalyzerCachePath,
        '-Path'
    ) + @($Path) + @(
        '-AnalysisProfile', $AnalysisProfile,
        '-DependencyMode', $DependencyMode,
        '-MinimumSeverity', $MinimumSeverity,
        '-OutputFormat', 'Json'
    )
    if ($OutputPath) { $arguments += @('-OutputPath', [IO.Path]::GetFullPath($OutputPath)) }

    if ([Environment]::OSVersion.Platform -eq [PlatformID]::Win32NT) {
        if ($PSCmdlet.ShouldProcess($AnalyzerCachePath, 'Run static-only analyzer with Windows PowerShell')) {
            $output = @(powershell.exe @arguments 2>&1)
        }
        else {
            throw 'Static analysis was declined through ShouldProcess.'
        }
    }
    else {
        $null = Get-Command -Name 'pwsh' -ErrorAction Stop
        if ($PSCmdlet.ShouldProcess($AnalyzerCachePath, 'Run static-only analyzer with PowerShell')) {
            $output = @(pwsh @arguments 2>&1)
        }
        else {
            throw 'Static analysis was declined through ShouldProcess.'
        }
    }
    $exitCode = $LASTEXITCODE
    Write-Output ($output -join [Environment]::NewLine)
}
catch {
    Write-LauncherFailure -Message $_.Exception.Message
    $exitCode = 4
    return
}
finally {
    if (-not $NoExit) { exit $exitCode }
}
