#requires -Version 5.1
[CmdletBinding()]
param(
    [string]$AnalyzerPath = (Join-Path (Split-Path -Parent $PSScriptRoot) 'Invoke-PSCP.ps1'),
    [string]$PSScriptAnalyzerVersion = '1.25.0'
)

Set-StrictMode -Version 3.0
$ErrorActionPreference = 'Stop'
$failures = New-Object 'System.Collections.Generic.List[string]'
$passes = New-Object 'System.Collections.Generic.List[string]'

function Assert-PSCP {
    param(
        [Parameter(Mandatory = $true)][bool]$Condition,
        [Parameter(Mandatory = $true)][string]$Message
    )
    if ($Condition) { $null = $passes.Add($Message) }
    else { $null = $failures.Add($Message) }
}

function Invoke-PSCPFixture {
    param(
        [Parameter(Mandatory = $true)][string]$HostPath,
        [Parameter(Mandatory = $true)][string]$FixturePath,
        [Parameter(Mandatory = $true)][string]$Name,
        [Parameter(Mandatory = $true)][string]$WorkPath,
        [ValidateSet('Quick', 'Standard', 'Maximum')][string]$AnalysisProfile = 'Quick',
        [string]$DependencyMode = 'Require',
        [string]$RequiredVersion = '1.25.0',
        [string]$ToolCachePath = ''
    )
    $reportPath = Join-Path $WorkPath ($Name + '.json')
    $arguments = @(
        '-NoLogo', '-NoProfile', '-NonInteractive', '-File', $AnalyzerPath,
        '-Path', $FixturePath, '-AnalysisProfile', $AnalysisProfile,
        '-DependencyMode', $DependencyMode, '-PSScriptAnalyzerVersion', $RequiredVersion,
        '-OutputFormat', 'Json', '-OutputPath', $reportPath
    )
    if ($ToolCachePath) { $arguments += @('-ToolCachePath', $ToolCachePath) }
    $stdout = @(& $HostPath @arguments 2>&1)
    $processExit = $LASTEXITCODE
    if (-not (Test-Path -LiteralPath $reportPath -PathType Leaf)) {
        throw "Fixture '$Name' did not produce a report. Exit=$processExit; output=$($stdout -join ' ')"
    }
    $raw = [IO.File]::ReadAllText($reportPath)
    $report = $raw | ConvertFrom-Json
    return [pscustomobject]@{ name=$Name; exitCode=$processExit; report=$report; raw=$raw; stdout=($stdout -join [Environment]::NewLine); reportPath=$reportPath }
}

$analyzerFullPath = [IO.Path]::GetFullPath($AnalyzerPath)
$fixtureRoot = Join-Path $PSScriptRoot 'fixtures'
$temporaryRoot = Join-Path ([IO.Path]::GetTempPath()) ('pscp-validation-' + [Guid]::NewGuid().ToString('N'))
$sentinelPath = Join-Path $temporaryRoot 'target-executed.txt'
$oldSentinel = $env:PSCP_TEST_SENTINEL
$null = New-Item -ItemType Directory -Path $temporaryRoot -Force
$env:PSCP_TEST_SENTINEL = $sentinelPath

try {
    foreach ($hostName in @('pwsh', 'powershell.exe')) {
        $hostCommand = Get-Command -Name $hostName -ErrorAction SilentlyContinue
        if (-not $hostCommand) {
            $null = $failures.Add("Required validation host is unavailable: $hostName")
            continue
        }
        $encodedPath = [Convert]::ToBase64String([Text.Encoding]::Unicode.GetBytes($analyzerFullPath))
        $parseCommand = @'
$path = [Text.Encoding]::Unicode.GetString([Convert]::FromBase64String('__PATH__'))
$tokens = $null
$errors = $null
[void][Management.Automation.Language.Parser]::ParseFile($path, [ref]$tokens, [ref]$errors)
if ($errors.Count) { $errors | ForEach-Object Message; exit 91 }
'@ -replace '__PATH__', $encodedPath
        $encodedCommand = [Convert]::ToBase64String([Text.Encoding]::Unicode.GetBytes($parseCommand))
        $parseOutput = @(& $hostCommand.Source -NoLogo -NoProfile -NonInteractive -EncodedCommand $encodedCommand 2>&1)
        Assert-PSCP -Condition ($LASTEXITCODE -eq 0) -Message "$hostName parses the analyzer without errors. $($parseOutput -join ' ')"
    }

    $pwshPath = (Get-Command pwsh -ErrorAction Stop).Source
    $benign = Invoke-PSCPFixture -HostPath $pwshPath -FixturePath (Join-Path $fixtureRoot 'Benign.ps1') -Name 'benign-maximum' -WorkPath $temporaryRoot -AnalysisProfile Maximum -RequiredVersion $PSScriptAnalyzerVersion
    Assert-PSCP -Condition ($benign.exitCode -eq 0 -and $benign.report.verdict -eq 'PASS_STATIC' -and $benign.report.analysisComplete) -Message 'Benign fixture receives a complete PASS_STATIC result.'
    Assert-PSCP -Condition (-not $benign.report.tool.targetWasExecuted -and -not $benign.report.tool.testsWereExecuted) -Message 'The report states that target code and target tests were not executed.'
    Assert-PSCP -Condition (@($benign.report.coverage | Where-Object { $_.required -and $_.status -ne 'completed' }).Count -eq 0) -Message 'Every required engine completes for the benign fixture.'
    Assert-PSCP -Condition ($benign.report.coverage[-1].version -eq $PSScriptAnalyzerVersion) -Message 'The exact requested PSScriptAnalyzer version is reported.'
    $null = $benign.stdout | ConvertFrom-Json
    Assert-PSCP -Condition $true -Message 'Stdout is valid standalone JSON without diagnostic contamination.'

    $dangerous = Invoke-PSCPFixture -HostPath $pwshPath -FixturePath (Join-Path $fixtureRoot 'Dangerous.ps1') -Name 'dangerous' -WorkPath $temporaryRoot -RequiredVersion $PSScriptAnalyzerVersion
    $dangerousRules = @($dangerous.report.findings | ForEach-Object { $_.ruleId })
    Assert-PSCP -Condition ($dangerous.exitCode -eq 2 -and $dangerous.report.verdict -eq 'BLOCK') -Message 'Dangerous fixture is blocked with exit code 2.'
    Assert-PSCP -Condition ($dangerous.report.malwareAssessment -eq 'HighRiskIndicators') -Message 'Dangerous fixture receives a high-risk malware-indicator assessment.'
    foreach ($rule in @('PSCP.MALWARE.DirectDownloadExecute', 'PSCP.MALWARE.DefenderConfigurationChange', 'PSCP.MALWARE.RegistryCredentialHiveExport', 'PSCP.MALWARE.LsassMiniDump', 'PSCP.MALWARE.RegistryAutorun')) {
        Assert-PSCP -Condition ($dangerousRules -contains $rule) -Message "Dangerous fixture triggers $rule."
    }

    $obfuscated = Invoke-PSCPFixture -HostPath $pwshPath -FixturePath (Join-Path $fixtureRoot 'Obfuscated.ps1') -Name 'obfuscated' -WorkPath $temporaryRoot -AnalysisProfile Maximum -RequiredVersion $PSScriptAnalyzerVersion
    Assert-PSCP -Condition ($obfuscated.exitCode -eq 2 -and $obfuscated.report.verdict -eq 'BLOCK') -Message 'Encoded dangerous PowerShell is blocked.'
    Assert-PSCP -Condition (@($obfuscated.report.decodedArtifacts).Count -ge 1) -Message 'The encoded fixture produces a hashed decoded artifact.'
    Assert-PSCP -Condition (@($obfuscated.report.findings | Where-Object { $_.ruleId -eq 'PSCP.MALWARE.DecodedDangerousContent' }).Count -ge 1) -Message 'Dangerous commands are identified inside decoded PowerShell.'

    $compressed = Invoke-PSCPFixture -HostPath $pwshPath -FixturePath (Join-Path $fixtureRoot 'Compressed.ps1') -Name 'compressed' -WorkPath $temporaryRoot -AnalysisProfile Maximum -RequiredVersion $PSScriptAnalyzerVersion
    Assert-PSCP -Condition ($compressed.exitCode -eq 2 -and @($compressed.report.decodedArtifacts | Where-Object { $_.transform -eq 'base64+gzip' }).Count -eq 1) -Message 'Bounded gzip expansion exposes and blocks a compressed PowerShell payload.'
    Assert-PSCP -Condition (@($compressed.report.findings | Where-Object { $_.ruleId -eq 'PSCP.MALWARE.DecodedDangerousContent' }).Count -ge 1) -Message 'Dangerous commands are identified after decompression.'

    $malformed = Invoke-PSCPFixture -HostPath $pwshPath -FixturePath (Join-Path $fixtureRoot 'Malformed.ps1') -Name 'malformed' -WorkPath $temporaryRoot -RequiredVersion $PSScriptAnalyzerVersion
    Assert-PSCP -Condition ($malformed.exitCode -eq 2 -and @($malformed.report.findings | Where-Object { $_.engine -eq 'PowerShell.Parser' }).Count -ge 1) -Message 'Malformed PowerShell is blocked with exact parser diagnostics.'

    $sideEffect = Invoke-PSCPFixture -HostPath $pwshPath -FixturePath (Join-Path $fixtureRoot 'SideEffectSentinel.ps1') -Name 'side-effect' -WorkPath $temporaryRoot -RequiredVersion $PSScriptAnalyzerVersion
    Assert-PSCP -Condition (-not (Test-Path -LiteralPath $sentinelPath)) -Message 'The side-effect sentinel proves the target was not executed.'
    Assert-PSCP -Condition ($sideEffect.report.analysisComplete) -Message 'A script containing a runtime side effect can still be analyzed statically to completion.'

    $secret = Invoke-PSCPFixture -HostPath $pwshPath -FixturePath (Join-Path $fixtureRoot 'SecretRedaction.ps1') -Name 'secret-redaction' -WorkPath $temporaryRoot -RequiredVersion $PSScriptAnalyzerVersion
    Assert-PSCP -Condition (-not $secret.raw.Contains('super-secret-static-value-12345') -and -not $secret.raw.Contains('DoNotLeakThisPassword!')) -Message 'Literal secrets never appear in the JSON report.'
    Assert-PSCP -Condition ($secret.raw.Contains('<redacted>')) -Message 'Secret findings contain an explicit redaction marker.'

    $emptyCache = Join-Path $temporaryRoot 'empty-cache'
    $null = New-Item -ItemType Directory -Path $emptyCache
    $offline = Invoke-PSCPFixture -HostPath $pwshPath -FixturePath (Join-Path $fixtureRoot 'Benign.ps1') -Name 'offline-missing' -WorkPath $temporaryRoot -DependencyMode Offline -RequiredVersion '0.0.1' -ToolCachePath $emptyCache
    Assert-PSCP -Condition ($offline.exitCode -eq 3 -and $offline.report.verdict -eq 'INCOMPLETE' -and -not $offline.report.analysisComplete) -Message 'A missing required engine fails closed as INCOMPLETE with exit code 3.'

    $repeatA = Invoke-PSCPFixture -HostPath $pwshPath -FixturePath (Join-Path $fixtureRoot 'Benign.ps1') -Name 'determinism-a' -WorkPath $temporaryRoot -RequiredVersion $PSScriptAnalyzerVersion
    $repeatB = Invoke-PSCPFixture -HostPath $pwshPath -FixturePath (Join-Path $fixtureRoot 'Benign.ps1') -Name 'determinism-b' -WorkPath $temporaryRoot -RequiredVersion $PSScriptAnalyzerVersion
    $fingerprintsA = @($repeatA.report.findings | ForEach-Object fingerprint) -join ','
    $fingerprintsB = @($repeatB.report.findings | ForEach-Object fingerprint) -join ','
    Assert-PSCP -Condition ($repeatA.report.verdict -eq $repeatB.report.verdict -and $fingerprintsA -eq $fingerprintsB -and $repeatA.report.files[0].sha256 -eq $repeatB.report.files[0].sha256) -Message 'Stable inputs produce the same verdict, finding fingerprints, and file hash.'

    $windowsPowerShell = Get-Command powershell.exe -ErrorAction SilentlyContinue
    if ($windowsPowerShell) {
        $desktop = Invoke-PSCPFixture -HostPath $windowsPowerShell.Source -FixturePath (Join-Path $fixtureRoot 'Benign.ps1') -Name 'windows-powershell-5.1' -WorkPath $temporaryRoot -RequiredVersion $PSScriptAnalyzerVersion
        Assert-PSCP -Condition ($desktop.report.analysisComplete -and $desktop.report.environment.powerShellVersion -like '5.1.*') -Message 'The complete analyzer workflow succeeds under Windows PowerShell 5.1.'
    }
}
finally {
    $env:PSCP_TEST_SENTINEL = $oldSentinel
    $resolvedTemporaryRoot = [IO.Path]::GetFullPath($temporaryRoot)
    $resolvedSystemTemp = [IO.Path]::GetFullPath([IO.Path]::GetTempPath())
    if ($resolvedTemporaryRoot.StartsWith($resolvedSystemTemp, [StringComparison]::OrdinalIgnoreCase) -and (Split-Path -Leaf $resolvedTemporaryRoot) -like 'pscp-validation-*') {
        Remove-Item -LiteralPath $resolvedTemporaryRoot -Recurse -Force -ErrorAction SilentlyContinue
    }
}

$result = [pscustomobject][ordered]@{
    passed = $failures.Count -eq 0
    passCount = $passes.Count
    failureCount = $failures.Count
    passes = $passes.ToArray()
    failures = $failures.ToArray()
}
$result | ConvertTo-Json -Depth 5
if ($failures.Count -gt 0) { exit 1 }
exit 0
