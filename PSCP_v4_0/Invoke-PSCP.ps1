#requires -Version 5.1
<#
.SYNOPSIS
    Performs deterministic, non-executing static analysis of PowerShell source files.

.DESCRIPTION
    PSCP parses PowerShell source, runs a pinned Microsoft PSScriptAnalyzer release,
    applies bundled security, malware-indicator, obfuscation, secret, safety, quality,
    compatibility, dependency, and maintainability checks, and emits an agent-friendly
    report. Target scripts and their tests are never executed or imported.

    Runtime dependencies are limited to PSScriptAnalyzer from PSGallery. All additional
    rules are implemented in this file and use the PowerShell AST or bounded data decoding.

.PARAMETER Path
    One or more PowerShell files or directories. Directories are scanned recursively unless
    -NoRecurse is specified. Defaults to the current directory.

.PARAMETER AnalysisProfile
    Quick runs parser, default PSScriptAnalyzer, and core custom checks. Standard adds the
    security/function presets. Maximum adds every bundled PSScriptAnalyzer preset,
    compatibility profiles, bounded decoding, and maintainability detail. -Profile is an alias.

.PARAMETER DependencyMode
    AutoInstall saves the pinned PSScriptAnalyzer release into a PSCP-local cache when needed.
    Require uses an exact installed or cached version and never downloads. Offline is the
    same as Require but records that network access was deliberately prohibited.

.PARAMETER OutputFormat
    Json is intended for agents and automation. Object returns a PowerShell object. Text
    provides a concise terminal summary.

.PARAMETER OutputPath
    Optionally writes the selected output format to a UTF-8 file in addition to stdout.

.PARAMETER NoExit
    Does not set a process exit code. Useful when calling PSCP from another PowerShell script.

.EXAMPLE
    .\Invoke-PSCP.ps1 -Path .\Deploy.ps1 -OutputFormat Json

.EXAMPLE
    .\Invoke-PSCP.ps1 -Path . -Profile Maximum -DependencyMode AutoInstall -OutputPath .\pscp.json

.NOTES
    Exit codes: 0 PASS_STATIC, 1 REVIEW, 2 BLOCK, 3 INCOMPLETE, 4 fatal/usage error.
#>
[Diagnostics.CodeAnalysis.SuppressMessageAttribute(
    'PSUseSingularNouns',
    '',
    Scope = 'Function',
    Target = '*',
    Justification = 'Private, non-exported PSCP helpers intentionally use plural nouns when they return collections.'
)]
[CmdletBinding()]
param(
    [Parameter(Position = 0)]
    [ValidateNotNullOrEmpty()]
    [string[]]$Path = @('.'),

    [Alias('Profile')]
    [ValidateSet('Quick', 'Standard', 'Maximum')]
    [string]$AnalysisProfile = 'Maximum',

    [ValidateSet('AutoInstall', 'Require', 'Offline')]
    [string]$DependencyMode = 'AutoInstall',

    [ValidatePattern('^\d+\.\d+\.\d+(?:\.\d+)?$')]
    [string]$PSScriptAnalyzerVersion = '1.25.0',

    [string]$ToolCachePath,

    [ValidateSet('Json', 'Object', 'Text')]
    [string]$OutputFormat = 'Json',

    [string]$OutputPath,

    [ValidateSet('Critical', 'Error', 'Warning', 'Information')]
    [string]$MinimumSeverity = 'Information',

    [ValidateRange(1, 100000)]
    [int]$MaxFileCount = 5000,

    [ValidateRange(1024, 104857600)]
    [int]$MaxFileBytes = 10485760,

    [ValidateRange(1024, 10485760)]
    [int]$MaxDecodedBytes = 1048576,

    [ValidateRange(1, 8)]
    [int]$MaxDecodeDepth = 3,

    [switch]$NoRecurse,
    [switch]$NoExit
)

Set-StrictMode -Version 3.0
$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'
$InformationPreference = 'SilentlyContinue'

$script:PSCPVersion = '4.0.0'
$script:AnalysisStarted = [DateTime]::UtcNow
$script:Findings = New-Object 'System.Collections.Generic.List[object]'
$script:Files = New-Object 'System.Collections.Generic.List[object]'
$script:Engines = New-Object 'System.Collections.Generic.List[object]'
$script:DecodedArtifacts = New-Object 'System.Collections.Generic.List[object]'
$script:FindingKeys = @{}
$script:ArtifactKeys = @{}
$script:AnalysisErrors = New-Object 'System.Collections.Generic.List[string]'
$script:SkippedPaths = New-Object 'System.Collections.Generic.List[object]'
$script:CapabilityIndex = @{}
$script:TargetWasExecuted = $false
$script:TestsWereExecuted = $false

function Get-PSCPSeverityRank {
    param([Parameter(Mandatory = $true)][string]$Severity)
    switch ($Severity) {
        'Critical' { return 0 }
        'Error' { return 1 }
        'Warning' { return 2 }
        default { return 3 }
    }
}

function Get-PSCPSha256Bytes {
    param([Parameter(Mandatory = $true)][byte[]]$Bytes)
    $sha = [System.Security.Cryptography.SHA256]::Create()
    try {
        return ([BitConverter]::ToString($sha.ComputeHash($Bytes))).Replace('-', '')
    }
    finally {
        $sha.Dispose()
    }
}

function Get-PSCPSha256Text {
    param([AllowEmptyString()][string]$Text)
    if ($null -eq $Text) { $Text = '' }
    return Get-PSCPSha256Bytes -Bytes ([Text.Encoding]::UTF8.GetBytes($Text))
}

function Get-PSCPSha256File {
    param([Parameter(Mandatory = $true)][string]$LiteralPath)
    $stream = [IO.File]::Open($LiteralPath, [IO.FileMode]::Open, [IO.FileAccess]::Read, [IO.FileShare]::Read)
    $sha = [System.Security.Cryptography.SHA256]::Create()
    try {
        return ([BitConverter]::ToString($sha.ComputeHash($stream))).Replace('-', '')
    }
    finally {
        $sha.Dispose()
        $stream.Dispose()
    }
}

function ConvertTo-PSCPSafeText {
    param(
        [AllowNull()][string]$Text,
        [int]$MaximumLength = 360
    )
    if ([string]::IsNullOrEmpty($Text)) { return '' }
    $safe = $Text
    $safe = [regex]::Replace($safe, '(?is)-----BEGIN (?:RSA |EC |OPENSSH |DSA )?PRIVATE KEY-----.*?-----END (?:RSA |EC |OPENSSH |DSA )?PRIVATE KEY-----', '<redacted-private-key>')
    $safe = [regex]::Replace($safe, '(?i)\bAKIA[0-9A-Z]{16}\b', 'AKIA<redacted>')
    $safe = [regex]::Replace($safe, '(?i)\bgh[pousr]_[A-Za-z0-9]{20,}\b', 'gh*_&lt;redacted&gt;')
    $safe = [regex]::Replace($safe, '\bxox[baprs]-[A-Za-z0-9-]{10,}\b', 'xox*-<redacted>')
    $safe = [regex]::Replace($safe, '\beyJ[A-Za-z0-9_-]{8,}\.[A-Za-z0-9_-]{8,}\.[A-Za-z0-9_-]{8,}\b', '<redacted-jwt>')
    $safe = [regex]::Replace($safe, '(?i)(://[^\s/:@]+:)[^\s/@]+(@)', '$1<redacted>$2')
    $safe = [regex]::Replace($safe, '(?i)((?:password|passwd|pwd|secret|token|api[_-]?key|client[_-]?secret|access[_-]?token|accountkey)\s*[:=]\s*)["''][^"'']+["'']', '$1''<redacted>''')
    $safe = [regex]::Replace($safe, '\s+', ' ').Trim()
    if ($safe.Length -gt $MaximumLength) {
        $safe = $safe.Substring(0, $MaximumLength) + '...'
    }
    return $safe
}

function Get-PSCPRelativePath {
    param(
        [Parameter(Mandatory = $true)][string]$BasePath,
        [Parameter(Mandatory = $true)][string]$TargetPath
    )
    try {
        $baseFull = [IO.Path]::GetFullPath($BasePath).TrimEnd([IO.Path]::DirectorySeparatorChar, [IO.Path]::AltDirectorySeparatorChar) + [IO.Path]::DirectorySeparatorChar
        $targetFull = [IO.Path]::GetFullPath($TargetPath)
        $baseUri = New-Object Uri($baseFull)
        $targetUri = New-Object Uri($targetFull)
        if ($baseUri.Scheme -ne $targetUri.Scheme) { return $targetFull }
        $relative = [Uri]::UnescapeDataString($baseUri.MakeRelativeUri($targetUri).ToString())
        return $relative.Replace('/', [IO.Path]::DirectorySeparatorChar)
    }
    catch {
        return $TargetPath
    }
}

function Get-PSCPLocationFromOffset {
    param(
        [AllowEmptyString()][string]$Text,
        [int]$Offset
    )
    if ($Offset -lt 1) {
        return [pscustomobject]@{ line = 1; column = 1 }
    }
    $bounded = [Math]::Min($Offset, $Text.Length)
    $prefix = $Text.Substring(0, $bounded)
    $parts = @($prefix -split '\r?\n', -1)
    return [pscustomobject]@{
        line = $parts.Count
        column = $parts[$parts.Count - 1].Length + 1
    }
}

function Add-PSCPEngine {
    param(
        [Parameter(Mandatory = $true)][string]$Name,
        [ValidateSet('completed', 'failed', 'skipped', 'unavailable', 'degraded')][string]$Status,
        [bool]$Required,
        [AllowEmptyString()][string]$Version = '',
        [AllowEmptyString()][string]$Message = '',
        [int]$DurationMs = 0,
        [AllowNull()][object]$Details = $null
    )
    $null = $script:Engines.Add([pscustomobject][ordered]@{
        name = $Name
        status = $Status
        required = $Required
        version = $Version
        durationMs = $DurationMs
        message = ConvertTo-PSCPSafeText -Text $Message -MaximumLength 800
        details = $Details
    })
}

function Add-PSCPFinding {
    param(
        [Parameter(Mandatory = $true)][string]$RuleId,
        [Parameter(Mandatory = $true)][string]$Engine,
        [Parameter(Mandatory = $true)][string]$Category,
        [ValidateSet('Critical', 'Error', 'Warning', 'Information')][string]$Severity,
        [ValidateSet('High', 'Medium', 'Low')][string]$Confidence,
        [bool]$Blocking,
        [Parameter(Mandatory = $true)][string]$File,
        [AllowEmptyString()][string]$FileHash = '',
        [int]$Line = 1,
        [int]$Column = 1,
        [int]$EndLine = 0,
        [int]$EndColumn = 0,
        [Parameter(Mandatory = $true)][string]$Message,
        [Parameter(Mandatory = $true)][string]$Consequence,
        [Parameter(Mandatory = $true)][string]$Remediation,
        [AllowEmptyString()][string]$Evidence = '',
        [string[]]$Tags = @(),
        [string[]]$References = @(),
        [AllowEmptyString()][string]$Cwe = '',
        [string[]]$Attack = @(),
        [AllowNull()][object[]]$SuggestedCorrections = @(),
        [bool]$Suppressed = $false,
        [AllowEmptyString()][string]$SuppressionId = ''
    )
    if ($Line -lt 1) { $Line = 1 }
    if ($Column -lt 1) { $Column = 1 }
    if ($EndLine -lt 1) { $EndLine = $Line }
    if ($EndColumn -lt 1) { $EndColumn = $Column }
    $safeEvidence = ConvertTo-PSCPSafeText -Text $Evidence
    $keyText = '{0}|{1}|{2}|{3}|{4}|{5}' -f $RuleId, $File, $Line, $Column, $Message, $safeEvidence
    $fingerprint = (Get-PSCPSha256Text -Text $keyText).Substring(0, 24).ToLowerInvariant()
    if ($script:FindingKeys.ContainsKey($fingerprint)) { return }
    $script:FindingKeys[$fingerprint] = $true
    $null = $script:Findings.Add([pscustomobject][ordered]@{
        ruleId = $RuleId
        engine = $Engine
        category = $Category
        severity = $Severity
        confidence = $Confidence
        blocking = $Blocking
        suppressed = $Suppressed
        suppressionId = $SuppressionId
        file = $File
        fileHash = $FileHash
        line = $Line
        column = $Column
        endLine = $EndLine
        endColumn = $EndColumn
        message = $Message
        consequence = $Consequence
        remediation = $Remediation
        evidence = $safeEvidence
        tags = @($Tags | Sort-Object -Unique)
        cwe = $Cwe
        attack = @($Attack | Sort-Object -Unique)
        references = @($References | Sort-Object -Unique)
        suggestedCorrections = @($SuggestedCorrections)
        fingerprint = $fingerprint
    })
}

function Add-PSCPCapability {
    param(
        [Parameter(Mandatory = $true)][string]$Name,
        [Parameter(Mandatory = $true)][string]$File,
        [int]$Line,
        [Parameter(Mandatory = $true)][string]$Operation,
        [AllowEmptyString()][string]$Evidence = ''
    )
    if (-not $script:CapabilityIndex.ContainsKey($Name)) {
        $script:CapabilityIndex[$Name] = New-Object 'System.Collections.Generic.List[object]'
    }
    $safeEvidence = ConvertTo-PSCPSafeText -Text $Evidence -MaximumLength 180
    $key = '{0}|{1}|{2}|{3}' -f $File, $Line, $Operation, $safeEvidence
    $exists = @($script:CapabilityIndex[$Name] | Where-Object { $_.key -eq $key }).Count -gt 0
    if (-not $exists) {
        $null = $script:CapabilityIndex[$Name].Add([pscustomobject]@{
            key = $key
            file = $File
            line = [Math]::Max(1, $Line)
            operation = $Operation
            evidence = $safeEvidence
        })
    }
}

function Get-PSCPCodeWithoutComments {
    param(
        [Parameter(Mandatory = $true)][string]$Raw,
        [object[]]$Tokens
    )
    $output = $Raw
    $comments = @($Tokens | Where-Object { $_.Kind.ToString() -eq 'Comment' } | Sort-Object { $_.Extent.StartOffset } -Descending)
    foreach ($token in $comments) {
        $start = [int]$token.Extent.StartOffset
        $length = [int]($token.Extent.EndOffset - $token.Extent.StartOffset)
        if ($length -gt 0 -and $start -ge 0 -and ($start + $length) -le $output.Length) {
            $output = $output.Remove($start, $length).Insert($start, (' ' * $length))
        }
    }
    return $output
}

function Get-PSCPTextInfo {
    param([Parameter(Mandatory = $true)][string]$LiteralPath)
    $bytes = [IO.File]::ReadAllBytes($LiteralPath)
    $encoding = 'unknown'
    $hasBom = $false
    $validUtf8 = $false
    $text = ''

    if ($bytes.Length -ge 4 -and $bytes[0] -eq 0x00 -and $bytes[1] -eq 0x00 -and $bytes[2] -eq 0xFE -and $bytes[3] -eq 0xFF) {
        $encoding = 'utf-32be-bom'
        $hasBom = $true
        $utf32be = New-Object Text.UTF32Encoding($true, $true, $true)
        $text = $utf32be.GetString($bytes, 4, $bytes.Length - 4)
    }
    elseif ($bytes.Length -ge 4 -and $bytes[0] -eq 0xFF -and $bytes[1] -eq 0xFE -and $bytes[2] -eq 0x00 -and $bytes[3] -eq 0x00) {
        $encoding = 'utf-32le-bom'
        $hasBom = $true
        $utf32le = New-Object Text.UTF32Encoding($false, $true, $true)
        $text = $utf32le.GetString($bytes, 4, $bytes.Length - 4)
    }
    elseif ($bytes.Length -ge 3 -and $bytes[0] -eq 0xEF -and $bytes[1] -eq 0xBB -and $bytes[2] -eq 0xBF) {
        $encoding = 'utf-8-bom'
        $hasBom = $true
        $validUtf8 = $true
        $utf8 = New-Object Text.UTF8Encoding($false, $true)
        $text = $utf8.GetString($bytes, 3, $bytes.Length - 3)
    }
    elseif ($bytes.Length -ge 2 -and $bytes[0] -eq 0xFF -and $bytes[1] -eq 0xFE) {
        $encoding = 'utf-16le-bom'
        $hasBom = $true
        $text = [Text.Encoding]::Unicode.GetString($bytes, 2, $bytes.Length - 2)
    }
    elseif ($bytes.Length -ge 2 -and $bytes[0] -eq 0xFE -and $bytes[1] -eq 0xFF) {
        $encoding = 'utf-16be-bom'
        $hasBom = $true
        $text = [Text.Encoding]::BigEndianUnicode.GetString($bytes, 2, $bytes.Length - 2)
    }
    else {
        try {
            $strictUtf8 = New-Object Text.UTF8Encoding($false, $true)
            $text = $strictUtf8.GetString($bytes)
            $encoding = 'utf-8-no-bom'
            $validUtf8 = $true
        }
        catch {
            $encoding = 'system-default'
            $text = [Text.Encoding]::Default.GetString($bytes)
        }
    }

    $containsNonAscii = [regex]::IsMatch($text, '[^\x00-\x7F]')
    $nullCount = @($bytes | Where-Object { $_ -eq 0 }).Count
    return [pscustomobject]@{
        bytes = $bytes
        text = $text
        encoding = $encoding
        hasBom = $hasBom
        validUtf8 = $validUtf8
        containsNonAscii = $containsNonAscii
        nullByteCount = $nullCount
    }
}

function Get-PSCPAuthenticodeInfo {
    param([Parameter(Mandatory = $true)][string]$LiteralPath)
    if ($env:OS -ne 'Windows_NT') {
        return [pscustomobject]@{ available = $false; status = 'Unavailable'; signer = ''; timestamp = '' }
    }
    try {
        $signature = Get-AuthenticodeSignature -FilePath $LiteralPath -ErrorAction Stop
        $signer = ''
        if ($signature.SignerCertificate) { $signer = $signature.SignerCertificate.Subject }
        $timestamp = ''
        if ($signature.TimeStamperCertificate) { $timestamp = $signature.TimeStamperCertificate.NotBefore.ToUniversalTime().ToString('o') }
        return [pscustomobject]@{
            available = $true
            status = $signature.Status.ToString()
            signer = $signer
            timestamp = $timestamp
        }
    }
    catch {
        return [pscustomobject]@{ available = $true; status = 'Error'; signer = ''; timestamp = ''; error = $_.Exception.Message }
    }
}

function Resolve-PSCPTargetFiles {
    param(
        [Parameter(Mandatory = $true)][string[]]$InputPaths,
        [bool]$Recurse,
        [int]$Limit
    )
    $seen = @{}
    $result = New-Object 'System.Collections.Generic.List[object]'
    $extensions = @('.ps1', '.psm1', '.psd1')
    $excludedDirectoryPattern = '[/\\](?:\.git|\.pscp|node_modules|packages)[/\\]'

    foreach ($inputPath in $InputPaths) {
        try {
            $resolvedItems = @(Resolve-Path -LiteralPath $inputPath -ErrorAction Stop)
        }
        catch {
            $null = $script:SkippedPaths.Add([pscustomobject]@{ path = $inputPath; reason = 'Path could not be resolved'; error = $_.Exception.Message })
            continue
        }

        foreach ($resolvedItem in $resolvedItems) {
            $item = Get-Item -LiteralPath $resolvedItem.ProviderPath -Force -ErrorAction Stop
            $candidates = @()
            if ($item.PSIsContainer) {
                if ($Recurse) {
                    $candidates = @(Get-ChildItem -LiteralPath $item.FullName -Recurse -File -Force -ErrorAction SilentlyContinue)
                }
                else {
                    $candidates = @(Get-ChildItem -LiteralPath $item.FullName -File -Force -ErrorAction SilentlyContinue)
                }
            }
            else {
                $candidates = @($item)
            }

            foreach ($candidate in $candidates) {
                if ($extensions -notcontains $candidate.Extension.ToLowerInvariant()) { continue }
                if ($candidate.FullName -match $excludedDirectoryPattern -and -not ($item -is [IO.FileInfo])) { continue }
                if (($candidate.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) {
                    $null = $script:SkippedPaths.Add([pscustomobject]@{ path = $candidate.FullName; reason = 'Reparse-point file skipped'; error = '' })
                    continue
                }
                $full = [IO.Path]::GetFullPath($candidate.FullName)
                if ($seen.ContainsKey($full)) { continue }
                $seen[$full] = $true
                $null = $result.Add($candidate)
                if ($result.Count -gt $Limit) {
                    throw "File count exceeds MaxFileCount ($Limit). Narrow the target or increase the explicit limit."
                }
            }
        }
    }
    return @($result | Sort-Object FullName)
}

function Resolve-PSCPPssaModule {
    param(
        [Parameter(Mandatory = $true)][string]$RequiredVersion,
        [Parameter(Mandatory = $true)][string]$CachePath,
        [Parameter(Mandatory = $true)][string]$Mode
    )
    $started = [Diagnostics.Stopwatch]::StartNew()
    $manifest = Join-Path (Join-Path (Join-Path $CachePath 'PSScriptAnalyzer') $RequiredVersion) 'PSScriptAnalyzer.psd1'
    $selected = $null

    if (Test-Path -LiteralPath $manifest -PathType Leaf) {
        $selected = Get-Item -LiteralPath $manifest
    }
    else {
        $installed = @(Get-Module -ListAvailable -Name PSScriptAnalyzer -ErrorAction SilentlyContinue |
            Where-Object { $_.Version.ToString() -eq $RequiredVersion } |
            Sort-Object Path)
        if ($installed.Count -gt 0) {
            $selected = Get-Item -LiteralPath $installed[0].Path
        }
    }

    if (-not $selected -and $Mode -eq 'AutoInstall') {
        if (-not (Test-Path -LiteralPath $CachePath)) {
            $null = New-Item -ItemType Directory -Path $CachePath -Force
        }
        $gallery = Get-PSRepository -Name PSGallery -ErrorAction Stop
        if ($gallery.SourceLocation -notmatch '^https://www\.powershellgallery\.com/api/v2/?$') {
            throw "PSGallery source is unexpected: $($gallery.SourceLocation)"
        }
        $package = Find-Module -Name PSScriptAnalyzer -RequiredVersion $RequiredVersion -Repository PSGallery -ErrorAction Stop
        if ($package.Name -ne 'PSScriptAnalyzer' -or $package.Version.ToString() -ne $RequiredVersion) {
            throw 'PSGallery returned package metadata that did not match the requested name and version.'
        }
        Save-Module -Name PSScriptAnalyzer -RequiredVersion $RequiredVersion -Repository PSGallery -Path $CachePath -Force -ErrorAction Stop
        if (-not (Test-Path -LiteralPath $manifest -PathType Leaf)) {
            throw "Save-Module completed but the expected manifest was not found: $manifest"
        }
        $selected = Get-Item -LiteralPath $manifest
    }

    if (-not $selected) {
        throw "PSScriptAnalyzer $RequiredVersion is unavailable and DependencyMode '$Mode' does not permit downloading it."
    }

    $moduleBase = Split-Path -Parent $selected.FullName
    $signatureResults = @()
    if ($env:OS -eq 'Windows_NT') {
        $signatureResults = @(Get-ChildItem -LiteralPath $moduleBase -Recurse -File |
            Where-Object { $_.Extension -in '.psd1', '.psm1', '.dll' } |
            ForEach-Object {
                $sig = Get-AuthenticodeSignature -FilePath $_.FullName -ErrorAction Stop
                [pscustomobject]@{ path = $_.FullName; status = $sig.Status.ToString() }
            })
        $badSignatures = @($signatureResults | Where-Object { $_.status -ne 'Valid' })
        if ($badSignatures.Count -gt 0) {
            throw "PSScriptAnalyzer dependency validation failed: $($badSignatures.Count) module file(s) did not have a valid Authenticode signature."
        }
    }

    $imported = Import-Module -Name $selected.FullName -Force -PassThru -ErrorAction Stop
    if ($imported.Name -ne 'PSScriptAnalyzer' -or $imported.Version.ToString() -ne $RequiredVersion) {
        throw "Imported module identity mismatch: $($imported.Name) $($imported.Version)"
    }
    if (-not (Get-Command -Name Invoke-ScriptAnalyzer -Module PSScriptAnalyzer -ErrorAction SilentlyContinue)) {
        throw 'The validated PSScriptAnalyzer module did not export Invoke-ScriptAnalyzer.'
    }

    $started.Stop()
    return [pscustomobject]@{
        module = $imported
        manifestPath = $selected.FullName
        manifestHash = Get-PSCPSha256File -LiteralPath $selected.FullName
        signaturesChecked = $signatureResults.Count
        durationMs = [int]$started.ElapsedMilliseconds
    }
}

function Get-PSCPStaticArgument {
    param(
        [Parameter(Mandatory = $true)][System.Management.Automation.Language.CommandAst]$CommandAst,
        [string[]]$ParameterNames = @(),
        [int]$Position = -1
    )
    $elements = @($CommandAst.CommandElements)
    for ($index = 1; $index -lt $elements.Count; $index++) {
        $element = $elements[$index]
        if ($element -is [System.Management.Automation.Language.CommandParameterAst]) {
            if ($ParameterNames -contains $element.ParameterName) {
                if ($element.Argument) { return $element.Argument }
                if (($index + 1) -lt $elements.Count -and -not ($elements[$index + 1] -is [System.Management.Automation.Language.CommandParameterAst])) {
                    return $elements[$index + 1]
                }
            }
            continue
        }
    }
    if ($Position -ge 0) {
        $positionals = @($elements | Select-Object -Skip 1 | Where-Object { -not ($_ -is [System.Management.Automation.Language.CommandParameterAst]) })
        if ($Position -lt $positionals.Count) { return $positionals[$Position] }
    }
    return $null
}

function Get-PSCPAstConstantText {
    param([AllowNull()][object]$Ast)
    if ($null -eq $Ast) { return $null }
    if ($Ast -is [System.Management.Automation.Language.StringConstantExpressionAst]) { return [string]$Ast.Value }
    if ($Ast -is [System.Management.Automation.Language.ConstantExpressionAst]) { return [string]$Ast.Value }
    return $null
}

function Get-PSCPCommandName {
    param([Parameter(Mandatory = $true)][System.Management.Automation.Language.CommandAst]$CommandAst)
    try {
        $name = $CommandAst.GetCommandName()
        if ($name) { return $name }
        if ($CommandAst.CommandElements.Count -gt 0 -and $CommandAst.CommandElements[0] -is [System.Management.Automation.Language.ScriptBlockExpressionAst]) {
            return '<literal-scriptblock>'
        }
        return $null
    }
    catch {
        return $null
    }
}

function Get-PSCPContainingFunction {
    param([Parameter(Mandatory = $true)][System.Management.Automation.Language.Ast]$Ast)
    $cursor = $Ast
    while ($cursor) {
        if ($cursor -is [System.Management.Automation.Language.FunctionDefinitionAst]) { return $cursor }
        $cursor = $cursor.Parent
    }
    return $null
}

function Get-PSCPScopeName {
    param([Parameter(Mandatory = $true)][System.Management.Automation.Language.Ast]$Ast)
    $functionAst = Get-PSCPContainingFunction -Ast $Ast
    if ($functionAst) { return $functionAst.Name }
    return '<script>'
}

function Test-PSCPSupportsShouldProcess {
    param([Parameter(Mandatory = $true)][System.Management.Automation.Language.Ast]$ScopeAst)
    $paramBlock = $null
    if ($ScopeAst -is [System.Management.Automation.Language.FunctionDefinitionAst]) {
        $paramBlock = $ScopeAst.Body.ParamBlock
    }
    elseif ($ScopeAst -is [System.Management.Automation.Language.ScriptBlockAst]) {
        $paramBlock = $ScopeAst.ParamBlock
    }
    if (-not $paramBlock) { return $false }
    foreach ($attribute in @($paramBlock.Attributes)) {
        if ($attribute.TypeName.Name -ne 'CmdletBinding') { continue }
        foreach ($named in @($attribute.NamedArguments)) {
            if ($named.ArgumentName -ne 'SupportsShouldProcess') { continue }
            if ($named.ExpressionOmitted) { return $true }
            if ($named.Argument -and $named.Argument.Extent.Text -match '^\s*(?:\$true|1)\s*$') { return $true }
        }
    }
    return $false
}

function Test-PSCPCommandIsShouldProcessGuarded {
    param([Parameter(Mandatory = $true)][System.Management.Automation.Language.Ast]$CommandAst)
    $cursor = $CommandAst
    while ($cursor -and $cursor.Parent) {
        if ($cursor.Parent -is [System.Management.Automation.Language.StatementBlockAst] -and
            $cursor.Parent.Parent -is [System.Management.Automation.Language.IfStatementAst]) {
            $block = $cursor.Parent
            $ifAst = $cursor.Parent.Parent
            foreach ($clause in @($ifAst.Clauses)) {
                try {
                    if ($clause.Item2 -eq $block -and $clause.Item1.Extent.Text -match '(?i)(?:\$PSCmdlet|\$pscmdlet)\.ShouldProcess\s*\(') {
                        return $true
                    }
                }
                catch { $null = $_.Exception.Message }
            }
        }
        if ($cursor.Parent -is [System.Management.Automation.Language.FunctionDefinitionAst]) { break }
        $cursor = $cursor.Parent
    }
    return $false
}

function Get-PSCPStateChangeInfo {
    param([AllowNull()][string]$CommandName)
    if ([string]::IsNullOrEmpty($CommandName)) { return $null }
    $name = $CommandName.ToLowerInvariant()
    $excluded = @(
        'new-object', 'new-guid', 'new-timespan', 'new-temporaryfile', 'new-variable',
        'set-strictmode', 'set-variable', 'set-psdebug', 'set-location', 'add-member',
        'add-type', 'start-sleep', 'start-transcript', 'stop-transcript', 'write-output',
        'write-host', 'write-information', 'write-verbose', 'write-debug', 'write-warning',
        'write-error', 'connect-mggraph', 'connect-azaccount', 'connect-exchangeonline',
        'disconnect-mggraph', 'disconnect-azaccount', 'disconnect-exchangeonline'
    )
    if ($excluded -contains $name) { return $null }

    $critical = @('format-volume', 'clear-disk', 'remove-partition', 'remove-volume')
    if ($critical -contains $name) {
        return [pscustomobject]@{ risk = 'critical'; capability = 'destructive-system-change'; operation = $CommandName }
    }

    $capability = 'state-change'
    switch -Regex ($name) {
        '^(remove|clear|move|copy|rename)-(item|content)$' { $capability = 'filesystem-change'; break }
        '^(set|new|remove)-itemproperty$|^(new|remove)-psdrive$' { $capability = 'registry-or-provider-change'; break }
        '^(new|set|remove|start|stop|restart)-service$' { $capability = 'service-change'; break }
        '^(register|set|unregister|start|stop)-scheduledtask$' { $capability = 'scheduled-task-change'; break }
        '^(new|set|remove)-netfirewall' { $capability = 'firewall-change'; break }
        '^(install|uninstall|update|publish|save)-(module|script|psresource)$' { $capability = 'package-change'; break }
        '^(new|set|remove|disable|enable)-(localuser|localgroup|aduser|adgroup)' { $capability = 'identity-change'; break }
        '^(new|set|remove|update|grant|revoke)-(mg|az|exo|pnp|team|intune|graph)' { $capability = 'cloud-change'; break }
    }

    if ($name -match '^(remove|set|new|clear|disable|enable|update|start|stop|restart|add|grant|revoke|register|unregister|install|uninstall|publish|move|copy|rename)-') {
        $risk = if ($name -match '^(remove|clear|disable|uninstall|format)-') { 'high' } else { 'medium' }
        return [pscustomobject]@{ risk = $risk; capability = $capability; operation = $CommandName }
    }
    if ($name -in @('cmd', 'cmd.exe', 'powershell', 'powershell.exe', 'pwsh', 'pwsh.exe', 'wscript', 'cscript', 'mshta', 'rundll32', 'regsvr32')) {
        return [pscustomobject]@{ risk = 'medium'; capability = 'process-execution'; operation = $CommandName }
    }
    return $null
}

function Get-PSCPCapabilityForCommand {
    param([AllowNull()][string]$CommandName)
    if ([string]::IsNullOrEmpty($CommandName)) { return @() }
    $name = $CommandName.ToLowerInvariant()
    $capabilities = New-Object 'System.Collections.Generic.List[string]'
    if ($name -match '^(invoke-webrequest|invoke-restmethod|curl|curl\.exe|wget|wget\.exe|start-bitstransfer|resolve-dnsname|test-netconnection|send-mailmessage)$') { $null = $capabilities.Add('network') }
    if ($name -match '^(get|set|add|clear|out|remove|move|copy|rename)-content$|^(get|set|new|remove|move|copy|rename)-item$|^(export|import)-clixml$|^(export|import)-csv$') { $null = $capabilities.Add('filesystem') }
    if ($name -match 'itemproperty|psdrive|^reg(?:\.exe)?$') { $null = $capabilities.Add('registry') }
    if ($name -match 'service|^sc(?:\.exe)?$') { $null = $capabilities.Add('services') }
    if ($name -match 'scheduledtask|^schtasks(?:\.exe)?$') { $null = $capabilities.Add('scheduled-tasks') }
    if ($name -match '^(start-process|stop-process|debug-process|wait-process|cmd|cmd\.exe|powershell|powershell\.exe|pwsh|pwsh\.exe|wscript|cscript|mshta|rundll32|regsvr32)$') { $null = $capabilities.Add('processes') }
    if ($name -match '^(invoke-command|enter-pssession|new-pssession|receive-pssession|connect-pssession|enable-psremoting)$') { $null = $capabilities.Add('remoting') }
    if ($name -match '^(install|uninstall|update|publish|save)-(module|script|psresource)$|^(import|remove)-module$') { $null = $capabilities.Add('modules-and-packages') }
    if ($name -match '^(get|new|set|remove|update|grant|revoke|connect|disconnect)-(mg|az|exo|pnp|team|intune|graph)') { $null = $capabilities.Add('cloud-services') }
    if ($name -match '^(get-credential|new-localuser|set-localuser|new-aduser|set-adaccountpassword)$') { $null = $capabilities.Add('credentials-or-identity') }
    return @($capabilities | Sort-Object -Unique)
}

function Get-PSCPFunctionComplexity {
    param([Parameter(Mandatory = $true)][System.Management.Automation.Language.FunctionDefinitionAst]$FunctionAst)
    $decisionCount = @($FunctionAst.FindAll({
        param($node)
        $node -is [System.Management.Automation.Language.IfStatementAst] -or
        $node -is [System.Management.Automation.Language.ForEachStatementAst] -or
        $node -is [System.Management.Automation.Language.ForStatementAst] -or
        $node -is [System.Management.Automation.Language.WhileStatementAst] -or
        $node -is [System.Management.Automation.Language.DoWhileStatementAst] -or
        $node -is [System.Management.Automation.Language.DoUntilStatementAst] -or
        $node -is [System.Management.Automation.Language.CatchClauseAst] -or
        $node -is [System.Management.Automation.Language.TrapStatementAst]
    }, $true)).Count
    $switchBranches = 0
    foreach ($switchAst in @($FunctionAst.FindAll({ param($node) $node -is [System.Management.Automation.Language.SwitchStatementAst] }, $true))) {
        $switchBranches += @($switchAst.Clauses).Count
    }
    $logicalOperators = @($FunctionAst.FindAll({
        param($node)
        $node -is [System.Management.Automation.Language.BinaryExpressionAst] -and
        $node.Operator.ToString() -match '^(And|Or|Xor)$'
    }, $true)).Count
    return 1 + $decisionCount + $switchBranches + $logicalOperators
}

function Get-PSCPFunctionNestingDepth {
    param([Parameter(Mandatory = $true)][System.Management.Automation.Language.FunctionDefinitionAst]$FunctionAst)
    $controlTypes = @(
        [System.Management.Automation.Language.IfStatementAst],
        [System.Management.Automation.Language.ForEachStatementAst],
        [System.Management.Automation.Language.ForStatementAst],
        [System.Management.Automation.Language.WhileStatementAst],
        [System.Management.Automation.Language.DoWhileStatementAst],
        [System.Management.Automation.Language.DoUntilStatementAst],
        [System.Management.Automation.Language.SwitchStatementAst],
        [System.Management.Automation.Language.TryStatementAst]
    )
    $maximum = 0
    foreach ($node in @($FunctionAst.FindAll({ $true }, $true))) {
        $depth = 0
        $cursor = $node.Parent
        while ($cursor -and $cursor -ne $FunctionAst) {
            foreach ($type in $controlTypes) {
                if ($type.IsInstanceOfType($cursor)) { $depth++; break }
            }
            $cursor = $cursor.Parent
        }
        if ($depth -gt $maximum) { $maximum = $depth }
    }
    return $maximum
}

function Get-PSCPParameterRecords {
    param([Parameter(Mandatory = $true)][System.Management.Automation.Language.FunctionDefinitionAst]$FunctionAst)
    $parameters = @()
    if ($FunctionAst.Parameters) { $parameters = @($FunctionAst.Parameters) }
    elseif ($FunctionAst.Body.ParamBlock) { $parameters = @($FunctionAst.Body.ParamBlock.Parameters) }
    $records = @()
    foreach ($parameter in $parameters) {
        $mandatory = $false
        $pipeline = $false
        $pipelineByName = $false
        $validations = @()
        foreach ($attribute in @($parameter.Attributes)) {
            $attributeName = $attribute.TypeName.Name
            if ($attributeName -like 'Validate*') { $validations += $attributeName }
            if ($attributeName -eq 'Parameter') {
                foreach ($named in @($attribute.NamedArguments)) {
                    if ($named.ArgumentName -eq 'Mandatory') { $mandatory = $named.ExpressionOmitted -or $named.Argument.Extent.Text -match '^\s*(?:\$true|1)\s*$' }
                    if ($named.ArgumentName -eq 'ValueFromPipeline') { $pipeline = $named.ExpressionOmitted -or $named.Argument.Extent.Text -match '^\s*(?:\$true|1)\s*$' }
                    if ($named.ArgumentName -eq 'ValueFromPipelineByPropertyName') { $pipelineByName = $named.ExpressionOmitted -or $named.Argument.Extent.Text -match '^\s*(?:\$true|1)\s*$' }
                }
            }
        }
        $typeName = 'object'
        if ($parameter.StaticType) { $typeName = $parameter.StaticType.FullName }
        $records += [pscustomobject][ordered]@{
            name = $parameter.Name.VariablePath.UserPath
            type = $typeName
            mandatory = $mandatory
            valueFromPipeline = $pipeline
            valueFromPipelineByPropertyName = $pipelineByName
            validations = @($validations | Sort-Object -Unique)
            hasDefault = $null -ne $parameter.DefaultValue
            line = $parameter.Extent.StartLineNumber
        }
    }
    return $records
}

function Get-PSCPOutputProperties {
    param([Parameter(Mandatory = $true)][System.Management.Automation.Language.FunctionDefinitionAst]$FunctionAst)
    $properties = New-Object 'System.Collections.Generic.List[string]'
    foreach ($convertAst in @($FunctionAst.FindAll({ param($node) $node -is [System.Management.Automation.Language.ConvertExpressionAst] }, $true))) {
        if ($convertAst.Type.TypeName.Name -notmatch '^(pscustomobject|psobject)$') { continue }
        if ($convertAst.Child -is [System.Management.Automation.Language.HashtableAst]) {
            foreach ($pair in @($convertAst.Child.KeyValuePairs)) {
                $key = Get-PSCPAstConstantText -Ast $pair.Item1
                if ($key) { $null = $properties.Add($key) }
            }
        }
    }
    return @($properties | Sort-Object -Unique)
}

function Get-PSCPFunctionRecords {
    param([Parameter(Mandatory = $true)][System.Management.Automation.Language.ScriptBlockAst]$Ast)
    $records = @()
    foreach ($functionAst in @($Ast.FindAll({ param($node) $node -is [System.Management.Automation.Language.FunctionDefinitionAst] }, $true))) {
        $commands = @($functionAst.FindAll({ param($node) $node -is [System.Management.Automation.Language.CommandAst] }, $true) |
            ForEach-Object { Get-PSCPCommandName -CommandAst $_ } | Where-Object { $_ } | Sort-Object -Unique)
        $scopeWrites = @($functionAst.FindAll({
            param($node)
            $node -is [System.Management.Automation.Language.AssignmentStatementAst] -and
            $node.Left -is [System.Management.Automation.Language.VariableExpressionAst] -and
            ($node.Left.VariablePath.IsGlobal -or $node.Left.VariablePath.IsScript)
        }, $true) | ForEach-Object { $_.Left.VariablePath.UserPath } | Sort-Object -Unique)
        $usesShouldProcess = @($functionAst.FindAll({
            param($node)
            $node -is [System.Management.Automation.Language.InvokeMemberExpressionAst] -and
            $node.Member.Extent.Text -match '^(?i:ShouldProcess)$'
        }, $true)).Count -gt 0
        $lineCount = [Math]::Max(1, $functionAst.Extent.EndLineNumber - $functionAst.Extent.StartLineNumber + 1)
        $records += [pscustomobject][ordered]@{
            name = $functionAst.Name
            lineStart = $functionAst.Extent.StartLineNumber
            lineEnd = $functionAst.Extent.EndLineNumber
            lines = $lineCount
            parameters = @(Get-PSCPParameterRecords -FunctionAst $functionAst)
            supportsShouldProcess = Test-PSCPSupportsShouldProcess -ScopeAst $functionAst
            usesShouldProcess = $usesShouldProcess
            hasProcessBlock = $null -ne $functionAst.Body.ProcessBlock
            complexity = Get-PSCPFunctionComplexity -FunctionAst $functionAst
            maximumNestingDepth = Get-PSCPFunctionNestingDepth -FunctionAst $functionAst
            calls = $commands
            scopeWrites = $scopeWrites
            outputProperties = @(Get-PSCPOutputProperties -FunctionAst $functionAst)
            hasCommentHelp = $null -ne $functionAst.GetHelpContent()
        }
    }
    return $records
}

function Get-PSCPTaintMap {
    param([Parameter(Mandatory = $true)][System.Management.Automation.Language.ScriptBlockAst]$Ast)
    $map = @{}

    function Add-Taint {
        param([string]$VariableName, [string[]]$Sources)
        if ([string]::IsNullOrEmpty($VariableName)) { return }
        $normalized = $VariableName.ToLowerInvariant()
        if (-not $map.ContainsKey($normalized)) { $map[$normalized] = @() }
        $map[$normalized] = @($map[$normalized] + $Sources | Where-Object { $_ } | Sort-Object -Unique)
    }

    foreach ($parameter in @($Ast.FindAll({ param($node) $node -is [System.Management.Automation.Language.ParameterAst] }, $true))) {
        Add-Taint -VariableName $parameter.Name.VariablePath.UserPath -Sources @('Parameter')
    }
    Add-Taint -VariableName 'args' -Sources @('ArgumentList')
    Add-Taint -VariableName 'input' -Sources @('PipelineInput')

    $assignments = @($Ast.FindAll({
        param($node)
        $node -is [System.Management.Automation.Language.AssignmentStatementAst] -and
        $node.Left -is [System.Management.Automation.Language.VariableExpressionAst]
    }, $true))

    for ($pass = 0; $pass -lt 6; $pass++) {
        foreach ($assignment in $assignments) {
            $sources = New-Object 'System.Collections.Generic.List[string]'
            foreach ($variable in @($assignment.Right.FindAll({ param($node) $node -is [System.Management.Automation.Language.VariableExpressionAst] }, $true))) {
                $name = $variable.VariablePath.UserPath.ToLowerInvariant()
                if ($name -like 'env:*') { $null = $sources.Add('Environment') }
                if ($map.ContainsKey($name)) {
                    foreach ($source in @($map[$name])) { $null = $sources.Add($source) }
                }
            }
            foreach ($commandAst in @($assignment.Right.FindAll({ param($node) $node -is [System.Management.Automation.Language.CommandAst] }, $true))) {
                $commandName = Get-PSCPCommandName -CommandAst $commandAst
                if (-not $commandName) { continue }
                switch -Regex ($commandName) {
                    '^(Read-Host|Get-Clipboard)$' { $null = $sources.Add('UserInput') }
                    '^(Invoke-WebRequest|Invoke-RestMethod|Start-BitsTransfer|curl|wget)$' { $null = $sources.Add('Network') }
                    '^(Get-Content|Import-Csv|Import-Clixml)$' { $null = $sources.Add('File') }
                }
            }
            $rightText = $assignment.Right.Extent.Text
            if ($rightText -match '(?i)FromBase64String|GZipStream|DeflateStream|\s-bxor\s|\[char\]|ToCharArray') {
                $null = $sources.Add('DecodedData')
            }
            Add-Taint -VariableName $assignment.Left.VariablePath.UserPath -Sources @($sources | Sort-Object -Unique)
        }
    }
    return $map
}

function Get-PSCPTaintSources {
    param(
        [Parameter(Mandatory = $true)][System.Management.Automation.Language.Ast]$Ast,
        [Parameter(Mandatory = $true)][hashtable]$TaintMap
    )
    $sources = New-Object 'System.Collections.Generic.List[string]'
    foreach ($variable in @($Ast.FindAll({ param($node) $node -is [System.Management.Automation.Language.VariableExpressionAst] }, $true))) {
        $name = $variable.VariablePath.UserPath.ToLowerInvariant()
        if ($name -like 'env:*') { $null = $sources.Add('Environment') }
        if ($TaintMap.ContainsKey($name)) {
            foreach ($source in @($TaintMap[$name])) { $null = $sources.Add($source) }
        }
    }
    return @($sources | Sort-Object -Unique)
}

function Get-PSCPShannonEntropy {
    param([AllowEmptyString()][string]$Text)
    if ([string]::IsNullOrEmpty($Text)) { return 0.0 }
    $counts = @{}
    foreach ($character in $Text.ToCharArray()) {
        $key = [int][char]$character
        if (-not $counts.ContainsKey($key)) { $counts[$key] = 0 }
        $counts[$key]++
    }
    $entropy = 0.0
    foreach ($count in $counts.Values) {
        $probability = [double]$count / [double]$Text.Length
        $entropy -= $probability * ([Math]::Log($probability, 2))
    }
    return [Math]::Round($entropy, 3)
}

function Get-PSCPPrintableRatio {
    param([AllowEmptyString()][string]$Text)
    if ([string]::IsNullOrEmpty($Text)) { return 0.0 }
    $printable = 0
    foreach ($character in $Text.ToCharArray()) {
        $code = [int][char]$character
        if ($code -in 9, 10, 13 -or ($code -ge 32 -and $code -le 126) -or $code -ge 160) { $printable++ }
    }
    return [Math]::Round(([double]$printable / [double]$Text.Length), 3)
}

function ConvertFrom-PSCPBytesToText {
    param([Parameter(Mandatory = $true)][byte[]]$Bytes)
    if ($Bytes.Length -eq 0) { return [pscustomobject]@{ text = ''; encoding = 'empty'; printableRatio = 1.0 } }

    $candidates = @()
    if ($Bytes.Length -ge 2 -and $Bytes[0] -eq 0xFF -and $Bytes[1] -eq 0xFE) {
        $candidates += [pscustomobject]@{ text = [Text.Encoding]::Unicode.GetString($Bytes, 2, $Bytes.Length - 2); encoding = 'utf-16le-bom' }
    }
    elseif ($Bytes.Length -ge 2 -and $Bytes[0] -eq 0xFE -and $Bytes[1] -eq 0xFF) {
        $candidates += [pscustomobject]@{ text = [Text.Encoding]::BigEndianUnicode.GetString($Bytes, 2, $Bytes.Length - 2); encoding = 'utf-16be-bom' }
    }
    elseif ($Bytes.Length -ge 3 -and $Bytes[0] -eq 0xEF -and $Bytes[1] -eq 0xBB -and $Bytes[2] -eq 0xBF) {
        $candidates += [pscustomobject]@{ text = [Text.Encoding]::UTF8.GetString($Bytes, 3, $Bytes.Length - 3); encoding = 'utf-8-bom' }
    }

    try {
        $strictUtf8 = New-Object Text.UTF8Encoding($false, $true)
        $candidates += [pscustomobject]@{ text = $strictUtf8.GetString($Bytes); encoding = 'utf-8' }
    }
    catch { $null = $_.Exception.Message }
    if (($Bytes.Length % 2) -eq 0) {
        $candidates += [pscustomobject]@{ text = [Text.Encoding]::Unicode.GetString($Bytes); encoding = 'utf-16le' }
        $candidates += [pscustomobject]@{ text = [Text.Encoding]::BigEndianUnicode.GetString($Bytes); encoding = 'utf-16be' }
    }
    $candidates += [pscustomobject]@{ text = [Text.Encoding]::ASCII.GetString($Bytes); encoding = 'ascii' }

    $best = $null
    $bestRatio = -1.0
    foreach ($candidate in $candidates) {
        $ratio = Get-PSCPPrintableRatio -Text $candidate.text
        if ($ratio -gt $bestRatio) {
            $best = $candidate
            $bestRatio = $ratio
        }
    }
    return [pscustomobject]@{ text = $best.text.Trim([char]0); encoding = $best.encoding; printableRatio = $bestRatio }
}

function Expand-PSCPCompressedBytes {
    param(
        [Parameter(Mandatory = $true)][byte[]]$Bytes,
        [Parameter(Mandatory = $true)][int]$MaximumBytes
    )
    $kind = ''
    if ($Bytes.Length -ge 2 -and $Bytes[0] -eq 0x1F -and $Bytes[1] -eq 0x8B) { $kind = 'gzip' }
    elseif ($Bytes.Length -ge 2 -and $Bytes[0] -eq 0x78) { $kind = 'deflate' }
    if (-not $kind) { return $null }

    $inputStream = New-Object IO.MemoryStream(, $Bytes)
    $decompressor = $null
    $output = New-Object IO.MemoryStream
    try {
        if ($kind -eq 'gzip') {
            $decompressor = New-Object IO.Compression.GZipStream($inputStream, [IO.Compression.CompressionMode]::Decompress, $true)
        }
        else {
            $decompressor = New-Object IO.Compression.DeflateStream($inputStream, [IO.Compression.CompressionMode]::Decompress, $true)
        }
        $buffer = New-Object byte[] 8192
        while (($read = $decompressor.Read($buffer, 0, $buffer.Length)) -gt 0) {
            if (($output.Length + $read) -gt $MaximumBytes) {
                throw "Decompressed content exceeds MaxDecodedBytes ($MaximumBytes)."
            }
            $output.Write($buffer, 0, $read)
        }
        return [pscustomobject]@{ kind = $kind; bytes = $output.ToArray() }
    }
    finally {
        if ($decompressor) { $decompressor.Dispose() }
        $output.Dispose()
        $inputStream.Dispose()
    }
}

function Test-PSCPPowerShellLikeText {
    param([AllowEmptyString()][string]$Text)
    if ([string]::IsNullOrWhiteSpace($Text)) { return $false }
    $signals = 0
    foreach ($pattern in @(
        '(?i)\b(?:function|param|begin|process|end)\b',
        '(?i)\b(?:Get|Set|New|Remove|Invoke|Start|Stop|Write|Import|Export)-[A-Za-z]+\b',
        '(?i)\$(?:env:)?[A-Za-z_][A-Za-z0-9_:]*',
        '(?i)\[(?:System\.)?[A-Za-z][A-Za-z0-9_.]+\]::',
        '(?i)\b(?:iex|Invoke-Expression|powershell(?:\.exe)?|pwsh(?:\.exe)?)\b'
    )) {
        if ($Text -match $pattern) { $signals++ }
    }
    return $signals -ge 2
}

function Add-PSCPDecodedArtifact {
    param(
        [Parameter(Mandatory = $true)][string]$SourceFile,
        [Parameter(Mandatory = $true)][string]$SourceHash,
        [int]$Line,
        [Parameter(Mandatory = $true)][byte[]]$Bytes,
        [Parameter(Mandatory = $true)][int]$Depth,
        [Parameter(Mandatory = $true)][string]$Transform,
        [int]$MaximumBytes,
        [int]$MaximumDepth
    )
    if ($Bytes.Length -gt $MaximumBytes) {
        Add-PSCPFinding -RuleId 'PSCP.OBFUSCATION.DecodedSizeLimit' -Engine 'PSCP.Custom' -Category 'Obfuscation' -Severity 'Warning' -Confidence 'High' -Blocking $false -File $SourceFile -FileHash $SourceHash -Line $Line -Message 'An encoded artifact exceeded the configured safe decoding limit.' -Consequence 'The hidden content could not be fully inspected, so malicious or unsafe behaviour may remain concealed.' -Remediation 'Inspect the artifact in a dedicated malware-analysis environment or increase the explicit limit after confirming the expected size.' -Evidence "Transform=$Transform; bytes=$($Bytes.Length); limit=$MaximumBytes" -Tags @('obfuscation', 'coverage') -Attack @('T1027')
        return
    }

    $artifactHash = Get-PSCPSha256Bytes -Bytes $Bytes
    $artifactKey = '{0}|{1}|{2}' -f $SourceFile, $artifactHash, $Depth
    if ($script:ArtifactKeys.ContainsKey($artifactKey)) { return }
    $script:ArtifactKeys[$artifactKey] = $true

    $isPe = $Bytes.Length -ge 2 -and $Bytes[0] -eq 0x4D -and $Bytes[1] -eq 0x5A
    $textInfo = ConvertFrom-PSCPBytesToText -Bytes $Bytes
    $text = $textInfo.text
    $commands = @()
    $parseErrorMessages = @()
    $urls = @()
    $suspiciousCommands = @()
    $powerShellLike = $false

    if ($textInfo.printableRatio -ge 0.70 -and $text) {
        $powerShellLike = Test-PSCPPowerShellLikeText -Text $text
        $urls = @([regex]::Matches($text, '(?i)https?://[^\s"''<>]+') | ForEach-Object { ConvertTo-PSCPSafeText -Text $_.Value -MaximumLength 180 } | Sort-Object -Unique)
        if ($powerShellLike) {
            $decodedTokens = $null
            $decodedErrors = $null
            try {
                $decodedAst = [System.Management.Automation.Language.Parser]::ParseInput($text, [ref]$decodedTokens, [ref]$decodedErrors)
                $commands = @($decodedAst.FindAll({ param($node) $node -is [System.Management.Automation.Language.CommandAst] }, $true) |
                    ForEach-Object { Get-PSCPCommandName -CommandAst $_ } | Where-Object { $_ } | Sort-Object -Unique)
                $parseErrorMessages = @($decodedErrors | ForEach-Object { $_.Message })
                $suspiciousCommands = @($commands | Where-Object {
                    $_ -match '^(?i:Invoke-Expression|iex|Start-Process|Add-Type|Invoke-Command|cmd|cmd\.exe|powershell|powershell\.exe|pwsh|pwsh\.exe|mshta|rundll32|regsvr32|certutil|bitsadmin)$'
                })
            }
            catch {
                $parseErrorMessages = @($_.Exception.Message)
            }
        }
    }

    $artifactType = if ($isPe) { 'portable-executable' } elseif ($powerShellLike) { 'powershell-text' } elseif ($textInfo.printableRatio -ge 0.70) { 'text' } else { 'binary' }
    $artifactPreview = if ($textInfo.printableRatio -ge 0.70) { ConvertTo-PSCPSafeText -Text $text -MaximumLength 420 } else { '' }
    $null = $script:DecodedArtifacts.Add([pscustomobject][ordered]@{
        sourceFile = $SourceFile
        sourceLine = [Math]::Max(1, $Line)
        depth = $Depth
        transform = $Transform
        sha256 = $artifactHash
        byteLength = $Bytes.Length
        type = $artifactType
        textEncoding = $textInfo.encoding
        printableRatio = $textInfo.printableRatio
        preview = $artifactPreview
        commands = $commands
        urls = $urls
        parseErrors = $parseErrorMessages
    })

    if ($isPe) {
        Add-PSCPFinding -RuleId 'PSCP.MALWARE.EmbeddedExecutable' -Engine 'PSCP.Custom' -Category 'MalwareIndicator' -Severity 'Critical' -Confidence 'High' -Blocking $true -File $SourceFile -FileHash $SourceHash -Line $Line -Message 'An encoded literal decodes to a Windows portable executable.' -Consequence 'The script contains an embedded executable payload that could be written to disk or loaded directly into memory.' -Remediation 'Do not execute the script. Establish the payload provenance and analyze its hash and contents in a dedicated malware-analysis environment.' -Evidence "Transform=$Transform; decodedSha256=$artifactHash; bytes=$($Bytes.Length)" -Tags @('embedded-payload', 'malware') -Attack @('T1027.009')
    }
    elseif ($suspiciousCommands.Count -gt 0) {
        Add-PSCPFinding -RuleId 'PSCP.MALWARE.DecodedDangerousContent' -Engine 'PSCP.Custom' -Category 'MalwareIndicator' -Severity 'Critical' -Confidence 'High' -Blocking $true -File $SourceFile -FileHash $SourceHash -Line $Line -Message 'Encoded content resolves to PowerShell containing dangerous execution commands.' -Consequence 'The visible source conceals executable behaviour, a common defense-evasion and payload-delivery technique.' -Remediation 'Do not execute the script. Review the decoded artifact and replace encoded executable logic with transparent, integrity-checked source.' -Evidence "Transform=$Transform; decodedSha256=$artifactHash; commands=$($suspiciousCommands -join ', ')" -Tags @('obfuscation', 'decoded-code', 'execution') -Attack @('T1027', 'T1059.001')
    }
    elseif ($powerShellLike) {
        Add-PSCPFinding -RuleId 'PSCP.OBFUSCATION.EncodedPowerShell' -Engine 'PSCP.Custom' -Category 'Obfuscation' -Severity 'Warning' -Confidence 'High' -Blocking $false -File $SourceFile -FileHash $SourceHash -Line $Line -Message 'An encoded literal resolves to additional PowerShell source.' -Consequence 'Hidden code reduces reviewability and can conceal unsafe behaviour from simple source inspection.' -Remediation 'Store the logic as readable PowerShell and document any legitimate data encoding. Review the decoded artifact before testing.' -Evidence "Transform=$Transform; decodedSha256=$artifactHash; commands=$($commands -join ', ')" -Tags @('obfuscation', 'decoded-code') -Attack @('T1027.010')
    }

    if ($Depth -ge $MaximumDepth -or -not $text -or $textInfo.printableRatio -lt 0.70) { return }
    foreach ($match in [regex]::Matches($text, '(?<![A-Za-z0-9+/=])[A-Za-z0-9+/]{80,}={0,2}(?![A-Za-z0-9+/=])')) {
        $candidate = $match.Value
        if (($candidate.Length % 4) -ne 0) { continue }
        try {
            $nestedBytes = [Convert]::FromBase64String($candidate)
            Add-PSCPDecodedArtifact -SourceFile $SourceFile -SourceHash $SourceHash -Line $Line -Bytes $nestedBytes -Depth ($Depth + 1) -Transform 'base64-recursive' -MaximumBytes $MaximumBytes -MaximumDepth $MaximumDepth
        }
        catch { $null = $_.Exception.Message }
    }
}

function Invoke-PSCPFileIntegrityChecks {
    param(
        [Parameter(Mandatory = $true)][object]$FileContext,
        [Parameter(Mandatory = $true)][object]$TextInfo
    )
    $file = $FileContext.relativePath
    $hash = $FileContext.sha256
    $raw = $TextInfo.text

    if ($TextInfo.nullByteCount -gt 0 -and $TextInfo.encoding -notmatch '^utf-(16|32)') {
        Add-PSCPFinding -RuleId 'PSCP.FILE.NullBytes' -Engine 'PSCP.Custom' -Category 'FileIntegrity' -Severity 'Error' -Confidence 'High' -Blocking $true -File $file -FileHash $hash -Message 'Unexpected NUL bytes were found in a non-UTF-16/32 PowerShell file.' -Consequence 'The source may be corrupted, binary, or crafted to display differently from what the parser consumes.' -Remediation 'Recover the source from a trusted origin and save it using an explicit PowerShell-compatible text encoding.' -Evidence "NUL bytes=$($TextInfo.nullByteCount); encoding=$($TextInfo.encoding)" -Tags @('encoding', 'source-integrity')
    }
    if ($TextInfo.encoding -eq 'system-default') {
        Add-PSCPFinding -RuleId 'PSCP.FILE.InvalidUtf8' -Engine 'PSCP.Custom' -Category 'Compatibility' -Severity 'Warning' -Confidence 'High' -Blocking $false -File $file -FileHash $hash -Message 'The file is not valid UTF-8 and required the system default encoding.' -Consequence 'The script can parse differently across machines, locales, Windows PowerShell, and PowerShell 7.' -Remediation 'Resave the file using UTF-8 with BOM when Windows PowerShell 5.1 compatibility is required.' -Evidence "Detected encoding=$($TextInfo.encoding)" -Tags @('encoding', 'cross-platform')
    }
    elseif ($TextInfo.encoding -eq 'utf-8-no-bom' -and $TextInfo.containsNonAscii) {
        Add-PSCPFinding -RuleId 'PSCP.FILE.Utf8NoBomWindowsPowerShell' -Engine 'PSCP.Custom' -Category 'Compatibility' -Severity 'Warning' -Confidence 'High' -Blocking $false -File $file -FileHash $hash -Message 'A UTF-8 file containing non-ASCII characters has no BOM.' -Consequence 'Windows PowerShell 5.1 may decode the file using the active ANSI code page and change string or identifier contents.' -Remediation 'Use UTF-8 with BOM for files that must run under Windows PowerShell 5.1, or explicitly require PowerShell 7.' -Evidence 'UTF-8 without BOM and non-ASCII content detected.' -Tags @('encoding', 'windows-powershell-5.1')
    }

    $unicodeMatches = [regex]::Matches($raw, '[\u200B\u200C\u200D\u202A-\u202E\u2066-\u2069\uFEFF]')
    foreach ($match in @($unicodeMatches | Select-Object -First 20)) {
        $location = Get-PSCPLocationFromOffset -Text $raw -Offset $match.Index
        $codePoint = 'U+{0:X4}' -f [int][char]$match.Value[0]
        Add-PSCPFinding -RuleId 'PSCP.FILE.InvisibleUnicode' -Engine 'PSCP.Custom' -Category 'FileIntegrity' -Severity 'Error' -Confidence 'High' -Blocking $true -File $file -FileHash $hash -Line $location.line -Column $location.column -Message "Invisible or bidirectional Unicode control character $codePoint is present." -Consequence 'The displayed source can differ from its logical token order, enabling source-spoofing and review bypass.' -Remediation 'Remove the control character and retype the affected line from a trusted plain-text representation.' -Evidence $codePoint -Tags @('unicode', 'source-spoofing') -Cwe 'CWE-451'
    }

    $lineEndingText = $raw -replace "`r`n", ''
    $hasCrlf = $raw.Contains("`r`n")
    $hasLfOnly = $lineEndingText.Contains("`n")
    if ($hasCrlf -and $hasLfOnly) {
        Add-PSCPFinding -RuleId 'PSCP.FILE.MixedLineEndings' -Engine 'PSCP.Custom' -Category 'Maintainability' -Severity 'Information' -Confidence 'High' -Blocking $false -File $file -FileHash $hash -Message 'The file contains mixed CRLF and LF line endings.' -Consequence 'Formatting tools and source-control diffs may produce noisy or inconsistent changes.' -Remediation 'Normalize line endings according to the repository EditorConfig policy.' -Evidence 'Both CRLF and LF-only line endings detected.' -Tags @('formatting')
    }

    if ($FileContext.authenticode.available -and $FileContext.authenticode.status -notin @('Valid', 'NotSigned')) {
        Add-PSCPFinding -RuleId 'PSCP.FILE.InvalidSignature' -Engine 'PSCP.Custom' -Category 'FileIntegrity' -Severity 'Error' -Confidence 'High' -Blocking $true -File $file -FileHash $hash -Message "Authenticode status is $($FileContext.authenticode.status)." -Consequence 'The signature cannot establish source integrity or publisher identity and may indicate modification after signing.' -Remediation 'Obtain a clean copy from the expected publisher and verify its signature and hash before testing.' -Evidence "Authenticode=$($FileContext.authenticode.status)" -Tags @('authenticode', 'supply-chain')
    }
}

function Get-PSCPDependencyInventory {
    param(
        [Parameter(Mandatory = $true)][System.Management.Automation.Language.ScriptBlockAst]$Ast,
        [Parameter(Mandatory = $true)][AllowEmptyCollection()][System.Management.Automation.Language.CommandAst[]]$CommandAsts,
        [string[]]$LocalFunctions
    )
    $requiredModules = New-Object 'System.Collections.Generic.List[string]'
    $importedModules = New-Object 'System.Collections.Generic.List[string]'
    $moduleQualifiedCommands = New-Object 'System.Collections.Generic.List[string]'
    $nativeCommands = New-Object 'System.Collections.Generic.List[string]'
    $dynamicCommandLines = New-Object 'System.Collections.Generic.List[int]'

    try {
        foreach ($requiredModule in @($Ast.ScriptRequirements.RequiredModules)) {
            if ($requiredModule -is [string]) { $null = $requiredModules.Add($requiredModule) }
            elseif ($requiredModule.Name) { $null = $requiredModules.Add([string]$requiredModule.Name) }
            else { $null = $requiredModules.Add([string]$requiredModule) }
        }
    }
    catch { $null = $_.Exception.Message }

    foreach ($usingAst in @($Ast.FindAll({ param($node) $node -is [System.Management.Automation.Language.UsingStatementAst] }, $true))) {
        try {
            if ($usingAst.UsingStatementKind.ToString() -eq 'Module') {
                $name = [string]$usingAst.Name.Value
                if ($name) { $null = $requiredModules.Add($name) }
            }
        }
        catch { $null = $_.Exception.Message }
    }

    foreach ($commandAst in $CommandAsts) {
        $commandName = Get-PSCPCommandName -CommandAst $commandAst
        if (-not $commandName) {
            $null = $dynamicCommandLines.Add($commandAst.Extent.StartLineNumber)
            continue
        }
        if ($commandName -eq 'Import-Module') {
            $argument = Get-PSCPStaticArgument -CommandAst $commandAst -ParameterNames @('Name', 'FullyQualifiedName') -Position 0
            $moduleName = Get-PSCPAstConstantText -Ast $argument
            if ($moduleName) { $null = $importedModules.Add($moduleName) }
        }
        if ($LocalFunctions -contains $commandName) { continue }
        if ($commandName.Contains('\')) { $null = $moduleQualifiedCommands.Add($commandName) }
        if ($commandName -match '(?i)\.(?:exe|com|bat|cmd|vbs|js|msi)$' -or $commandName -in @('cmd', 'powershell', 'pwsh', 'wscript', 'cscript', 'mshta', 'rundll32', 'regsvr32', 'certutil', 'bitsadmin', 'schtasks', 'sc', 'reg')) {
            $null = $nativeCommands.Add($commandName)
        }
    }

    $requiredPowerShellVersion = ''
    try { $requiredPowerShellVersion = [string]$Ast.ScriptRequirements.RequiredPSVersion } catch { $null = $_.Exception.Message }
    return [pscustomobject][ordered]@{
        requiredPowerShellVersion = $requiredPowerShellVersion
        requiredModules = @($requiredModules | Where-Object { $_ } | Sort-Object -Unique)
        importedModules = @($importedModules | Where-Object { $_ } | Sort-Object -Unique)
        moduleQualifiedCommands = @($moduleQualifiedCommands | Sort-Object -Unique)
        nativeCommands = @($nativeCommands | Sort-Object -Unique)
        dynamicCommandLines = @($dynamicCommandLines | Sort-Object -Unique)
        resolutionNote = 'Command/module resolution is intentionally not performed because discovery can import modules or run module initialization code.'
    }
}

function Invoke-PSCPQualityAndSafetyChecks {
    param(
        [Parameter(Mandatory = $true)][object]$FileContext,
        [Parameter(Mandatory = $true)][System.Management.Automation.Language.ScriptBlockAst]$Ast,
        [Parameter(Mandatory = $true)][AllowEmptyCollection()][object[]]$Tokens,
        [Parameter(Mandatory = $true)][AllowEmptyCollection()][System.Management.Automation.Language.CommandAst[]]$CommandAsts,
        [Parameter(Mandatory = $true)][AllowEmptyCollection()][object[]]$FunctionRecords,
        [string[]]$LocalFunctions,
        [Parameter(Mandatory = $true)][string]$CodeWithoutComments
    )
    $file = $FileContext.relativePath
    $hash = $FileContext.sha256
    $extension = [IO.Path]::GetExtension($FileContext.fullPath).ToLowerInvariant()
    $commandNames = @($CommandAsts | ForEach-Object { Get-PSCPCommandName -CommandAst $_ } | Where-Object { $_ })

    if ($extension -in @('.ps1', '.psm1') -and $commandNames -notcontains 'Set-StrictMode') {
        Add-PSCPFinding -RuleId 'PSCP.QUALITY.StrictModeMissing' -Engine 'PSCP.Custom' -Category 'Reliability' -Severity 'Information' -Confidence 'High' -Blocking $false -File $file -FileHash $hash -Message 'Set-StrictMode is not enabled in this source file.' -Consequence 'Uninitialized variables and some invalid property references can silently produce incorrect behaviour.' -Remediation 'Enable Set-StrictMode -Version 3.0 or Latest near the entry point, then fix any newly exposed issues.' -Evidence 'No Set-StrictMode command found.' -Tags @('reliability')
    }

    $eapStop = @($Ast.FindAll({
        param($node)
        $node -is [System.Management.Automation.Language.AssignmentStatementAst] -and
        $node.Left -is [System.Management.Automation.Language.VariableExpressionAst] -and
        $node.Left.VariablePath.UserPath -match '^(?i:(?:global:|script:|local:)?ErrorActionPreference)$' -and
        $node.Right.Extent.Text -match '(?i)["'']Stop["'']|ActionPreference\]::Stop'
    }, $true)).Count -gt 0
    if ($extension -eq '.ps1' -and -not $eapStop) {
        Add-PSCPFinding -RuleId 'PSCP.QUALITY.NonTerminatingErrors' -Engine 'PSCP.Custom' -Category 'Reliability' -Severity 'Information' -Confidence 'Medium' -Blocking $false -File $file -FileHash $hash -Message 'The entry script does not establish terminating-error behaviour globally.' -Consequence 'A failed cmdlet can allow later destructive or dependent steps to continue with incomplete state.' -Remediation 'Use $ErrorActionPreference = ''Stop'' at the entry point or apply -ErrorAction Stop consistently at every failure-sensitive call.' -Evidence 'No top-level ErrorActionPreference Stop assignment found.' -Tags @('error-handling')
    }

    foreach ($catchAst in @($Ast.FindAll({ param($node) $node -is [System.Management.Automation.Language.CatchClauseAst] }, $true))) {
        $catchText = $catchAst.Body.Extent.Text
        if ($catchText -notmatch '(?i)\b(?:throw|Write-Error|Write-Warning|return|exit)\b') {
            Add-PSCPFinding -RuleId 'PSCP.QUALITY.SwallowedException' -Engine 'PSCP.Custom' -Category 'Reliability' -Severity 'Warning' -Confidence 'Medium' -Blocking $false -File $file -FileHash $hash -Line $catchAst.Extent.StartLineNumber -Column $catchAst.Extent.StartColumnNumber -Message 'A catch block does not clearly report, rethrow, return, or terminate.' -Consequence 'Failures may be hidden and the script can continue in an invalid state.' -Remediation 'Handle the error explicitly, add useful context, and rethrow or return a documented failure result.' -Evidence $catchAst.Extent.Text -Tags @('error-handling')
        }
    }

    foreach ($commandAst in $CommandAsts) {
        $commandName = Get-PSCPCommandName -CommandAst $commandAst
        if (-not $commandName) { continue }
        foreach ($capability in @(Get-PSCPCapabilityForCommand -CommandName $commandName)) {
            Add-PSCPCapability -Name $capability -File $file -Line $commandAst.Extent.StartLineNumber -Operation $commandName -Evidence $commandAst.Extent.Text
        }
        $riskInfo = Get-PSCPStateChangeInfo -CommandName $commandName
        if ($riskInfo -and $LocalFunctions -notcontains $commandName) {
            Add-PSCPCapability -Name $riskInfo.capability -File $file -Line $commandAst.Extent.StartLineNumber -Operation $commandName -Evidence $commandAst.Extent.Text
            $scopeAst = Get-PSCPContainingFunction -Ast $commandAst
            if (-not $scopeAst) { $scopeAst = $Ast }
            $supports = Test-PSCPSupportsShouldProcess -ScopeAst $scopeAst
            $guarded = Test-PSCPCommandIsShouldProcessGuarded -CommandAst $commandAst
            if (-not ($supports -and $guarded)) {
                $severity = if ($riskInfo.risk -in @('critical', 'high')) { 'Error' } else { 'Warning' }
                $blocking = $severity -eq 'Error'
                Add-PSCPFinding -RuleId 'PSCP.SAFETY.ShouldProcessCoverage' -Engine 'PSCP.Custom' -Category 'Safety' -Severity $severity -Confidence 'Medium' -Blocking $blocking -File $file -FileHash $hash -Line $commandAst.Extent.StartLineNumber -Column $commandAst.Extent.StartColumnNumber -Message "State-changing command '$commandName' is not proven to be inside a same-scope ShouldProcess guard." -Consequence 'The operation may run without a reliable -WhatIf preview or user confirmation boundary.' -Remediation "Add [CmdletBinding(SupportsShouldProcess=`$true)] to scope '$(Get-PSCPScopeName -Ast $commandAst)' and execute this command only inside if (`$PSCmdlet.ShouldProcess(...))." -Evidence $commandAst.Extent.Text -Tags @('should-process', $riskInfo.capability)
            }
        }

        if ($commandName -in @('Format-Table', 'Format-List', 'Format-Wide', 'Format-Custom')) {
            Add-PSCPFinding -RuleId 'PSCP.QUALITY.FormattingInLogic' -Engine 'PSCP.Custom' -Category 'AgentReadiness' -Severity 'Warning' -Confidence 'High' -Blocking $false -File $file -FileHash $hash -Line $commandAst.Extent.StartLineNumber -Column $commandAst.Extent.StartColumnNumber -Message "Formatting command '$commandName' is embedded in script logic." -Consequence 'Formatting objects destroy structured pipeline data and make output difficult for agents and callers to consume reliably.' -Remediation 'Return normal objects or JSON from the analyzer logic and apply formatting only in an explicitly selected human-output mode.' -Evidence $commandAst.Extent.Text -Tags @('structured-output', 'agent-readiness')
        }
        if ($commandAst.Extent.Text -match '(?i)-ErrorAction\s+SilentlyContinue|(?:^|\s)2>\s*\$null') {
            Add-PSCPFinding -RuleId 'PSCP.QUALITY.HiddenErrors' -Engine 'PSCP.Custom' -Category 'Reliability' -Severity 'Warning' -Confidence 'Medium' -Blocking $false -File $file -FileHash $hash -Line $commandAst.Extent.StartLineNumber -Column $commandAst.Extent.StartColumnNumber -Message 'A command suppresses errors without a locally visible verification step.' -Consequence 'Dependency, permission, or runtime failures can be misreported as success or empty output.' -Remediation 'Capture the error explicitly and convert it into a structured failed/incomplete result.' -Evidence $commandAst.Extent.Text -Tags @('error-handling', 'false-green')
        }
    }

    foreach ($function in $FunctionRecords) {
        if ($function.complexity -gt 25) {
            Add-PSCPFinding -RuleId 'PSCP.MAINTAINABILITY.ExtremeComplexity' -Engine 'PSCP.Custom' -Category 'Maintainability' -Severity 'Warning' -Confidence 'High' -Blocking $false -File $file -FileHash $hash -Line $function.lineStart -Message "Function '$($function.name)' has estimated cyclomatic complexity $($function.complexity)." -Consequence 'The number of independent paths makes reliable review and test coverage impractical.' -Remediation 'Split the function into cohesive operations with explicit inputs, outputs, and failure contracts.' -Evidence "complexity=$($function.complexity); lines=$($function.lines)" -Tags @('complexity')
        }
        elseif ($function.complexity -gt 15) {
            Add-PSCPFinding -RuleId 'PSCP.MAINTAINABILITY.HighComplexity' -Engine 'PSCP.Custom' -Category 'Maintainability' -Severity 'Warning' -Confidence 'High' -Blocking $false -File $file -FileHash $hash -Line $function.lineStart -Message "Function '$($function.name)' has estimated cyclomatic complexity $($function.complexity)." -Consequence 'Numerous branches increase the chance of missed failure paths and insufficient tests.' -Remediation 'Extract branches into smaller functions and add a test for each remaining decision path.' -Evidence "complexity=$($function.complexity); lines=$($function.lines)" -Tags @('complexity')
        }
        if ($function.maximumNestingDepth -gt 5) {
            Add-PSCPFinding -RuleId 'PSCP.MAINTAINABILITY.DeepNesting' -Engine 'PSCP.Custom' -Category 'Maintainability' -Severity 'Warning' -Confidence 'High' -Blocking $false -File $file -FileHash $hash -Line $function.lineStart -Message "Function '$($function.name)' reaches nesting depth $($function.maximumNestingDepth)." -Consequence 'Deep nesting obscures error and cleanup paths and makes behaviour harder to reason about statically.' -Remediation 'Use guard clauses and extract nested branches into named functions.' -Evidence "maximumNestingDepth=$($function.maximumNestingDepth)" -Tags @('complexity')
        }
        if ($function.lines -gt 250) {
            Add-PSCPFinding -RuleId 'PSCP.MAINTAINABILITY.LongFunction' -Engine 'PSCP.Custom' -Category 'Maintainability' -Severity 'Warning' -Confidence 'High' -Blocking $false -File $file -FileHash $hash -Line $function.lineStart -Message "Function '$($function.name)' spans $($function.lines) lines." -Consequence 'Large functions combine responsibilities and make safe modification and targeted testing harder.' -Remediation 'Separate orchestration, validation, side effects, and reporting into smaller functions.' -Evidence "lines=$($function.lines)" -Tags @('function-size')
        }
        if (@($function.scopeWrites).Count -gt 0) {
            Add-PSCPFinding -RuleId 'PSCP.QUALITY.NonLocalStateWrite' -Engine 'PSCP.Custom' -Category 'Reliability' -Severity 'Warning' -Confidence 'High' -Blocking $false -File $file -FileHash $hash -Line $function.lineStart -Message "Function '$($function.name)' writes script/global state." -Consequence 'Hidden shared state complicates testing, concurrency, reuse, and failure recovery.' -Remediation 'Return state explicitly or encapsulate it in an object passed through well-defined boundaries.' -Evidence ($function.scopeWrites -join ', ') -Tags @('scope', 'testability')
        }
    }

    foreach ($attribute in @($Ast.FindAll({ param($node) $node -is [System.Management.Automation.Language.AttributeAst] -and $node.TypeName.FullName -match 'SuppressMessageAttribute' }, $true))) {
        if ($attribute.Extent.Text -notmatch '(?i)Justification\s*=\s*["''][^"'']{8,}["'']') {
            Add-PSCPFinding -RuleId 'PSCP.GOVERNANCE.UnjustifiedSuppression' -Engine 'PSCP.Custom' -Category 'Governance' -Severity 'Warning' -Confidence 'High' -Blocking $false -File $file -FileHash $hash -Line $attribute.Extent.StartLineNumber -Column $attribute.Extent.StartColumnNumber -Message 'A static-analysis suppression lacks a meaningful justification.' -Consequence 'Real defects can be hidden without an auditable reason for accepting the risk.' -Remediation 'Add a narrow Justification that explains why the finding is safe and how the assumption is maintained.' -Evidence $attribute.Extent.Text -Tags @('suppression', 'governance')
        }
    }

    foreach ($token in @($Tokens | Where-Object { $_.Kind.ToString() -eq 'Comment' })) {
        if ($token.Text -match '(?i)\b(?:TODO|FIXME|HACK|TEMP)\b') {
            Add-PSCPFinding -RuleId 'PSCP.QUALITY.UnresolvedMarker' -Engine 'PSCP.Custom' -Category 'Maintainability' -Severity 'Information' -Confidence 'High' -Blocking $false -File $file -FileHash $hash -Line $token.Extent.StartLineNumber -Column $token.Extent.StartColumnNumber -Message 'An unresolved implementation marker remains in a comment.' -Consequence 'The script may contain intentionally unfinished behaviour or deferred safety work.' -Remediation 'Resolve the marker or replace it with a tracked issue reference and explicit acceptance criteria.' -Evidence $token.Text -Tags @('todo')
        }
    }

    foreach ($match in [regex]::Matches($CodeWithoutComments, '(?i)http://[^\s"''<>]+')) {
        $location = Get-PSCPLocationFromOffset -Text $CodeWithoutComments -Offset $match.Index
        Add-PSCPFinding -RuleId 'PSCP.NETWORK.UnencryptedHttp' -Engine 'PSCP.Custom' -Category 'Security' -Severity 'Warning' -Confidence 'High' -Blocking $false -File $file -FileHash $hash -Line $location.line -Column $location.column -Message 'An unencrypted HTTP URL is embedded in executable source.' -Consequence 'Content or credentials can be modified or observed in transit.' -Remediation 'Use HTTPS and independently verify downloaded content with a pinned hash or trusted signature.' -Evidence $match.Value -Tags @('network', 'transport-security') -Cwe 'CWE-319'
    }
}

function Invoke-PSCPSecurityChecks {
    param(
        [Parameter(Mandatory = $true)][object]$FileContext,
        [Parameter(Mandatory = $true)][System.Management.Automation.Language.ScriptBlockAst]$Ast,
        [Parameter(Mandatory = $true)][AllowEmptyCollection()][System.Management.Automation.Language.CommandAst[]]$CommandAsts,
        [Parameter(Mandatory = $true)][hashtable]$TaintMap
    )
    $file = $FileContext.relativePath
    $hash = $FileContext.sha256
    $networkCommands = @('Invoke-WebRequest', 'Invoke-RestMethod', 'Start-BitsTransfer', 'curl', 'curl.exe', 'wget', 'wget.exe')
    $dynamicExecutionCommands = @('Invoke-Expression', 'iex')

    foreach ($commandAst in $CommandAsts) {
        $commandName = Get-PSCPCommandName -CommandAst $commandAst
        $commandText = $commandAst.Extent.Text
        $sources = @(Get-PSCPTaintSources -Ast $commandAst -TaintMap $TaintMap)
        $sourceText = if ($sources.Count -gt 0) { $sources -join ', ' } else { 'not proven' }

        if (-not $commandName) {
            $firstElement = if ($commandAst.CommandElements.Count -gt 0) { $commandAst.CommandElements[0] } else { $null }
            $dynamicSources = if ($firstElement) { @(Get-PSCPTaintSources -Ast $firstElement -TaintMap $TaintMap) } else { @() }
            $severity = if ($dynamicSources.Count -gt 0) { 'Error' } else { 'Warning' }
            Add-PSCPFinding -RuleId 'PSCP.INJECTION.DynamicCommandName' -Engine 'PSCP.Custom' -Category 'Injection' -Severity $severity -Confidence $(if ($dynamicSources.Count -gt 0) { 'High' } else { 'Medium' }) -Blocking ($severity -eq 'Error') -File $file -FileHash $hash -Line $commandAst.Extent.StartLineNumber -Column $commandAst.Extent.StartColumnNumber -Message 'A command name is computed dynamically and cannot be resolved statically.' -Consequence 'A caller-controlled or modified value could select an unintended command or executable.' -Remediation 'Use an allowlist that maps accepted operation names to fixed command references, then pass arguments separately.' -Evidence "$commandText; sources=$(if ($dynamicSources.Count) { $dynamicSources -join ', ' } else { 'unknown' })" -Tags @('dynamic-execution', 'injection') -Cwe 'CWE-94'
            continue
        }

        if ($dynamicExecutionCommands -contains $commandName) {
            $severity = if ($sources -contains 'Network') { 'Critical' } elseif ($sources.Count -gt 0) { 'Critical' } else { 'Error' }
            $ruleId = if ($sources -contains 'Network') { 'PSCP.MALWARE.NetworkToExpression' } elseif ($sources -contains 'DecodedData') { 'PSCP.MALWARE.DecodedToExpression' } else { 'PSCP.INJECTION.InvokeExpression' }
            $message = if ($sources -contains 'Network') { 'Network-derived content flows into Invoke-Expression.' } elseif ($sources -contains 'DecodedData') { 'Decoded content flows into Invoke-Expression.' } else { 'Invoke-Expression executes text as PowerShell code.' }
            Add-PSCPFinding -RuleId $ruleId -Engine 'PSCP.Custom' -Category 'Injection' -Severity $severity -Confidence $(if ($sources.Count -gt 0) { 'High' } else { 'Medium' }) -Blocking $true -File $file -FileHash $hash -Line $commandAst.Extent.StartLineNumber -Column $commandAst.Extent.StartColumnNumber -Message $message -Consequence 'Untrusted or modified text can become arbitrary PowerShell execution in the script security context.' -Remediation 'Remove Invoke-Expression. Call a fixed command directly and supply typed arguments or use an explicit allowlist.' -Evidence "$commandText; sources=$sourceText" -Tags @('code-injection', 'dynamic-execution') -Cwe 'CWE-94' -Attack @('T1059.001')
        }

        if ($commandName -eq 'Add-Type') {
            $definition = Get-PSCPStaticArgument -CommandAst $commandAst -ParameterNames @('TypeDefinition') -Position 0
            $constantDefinition = Get-PSCPAstConstantText -Ast $definition
            if ($definition -and $null -eq $constantDefinition) {
                $definitionSources = @(Get-PSCPTaintSources -Ast $definition -TaintMap $TaintMap)
                Add-PSCPFinding -RuleId 'PSCP.INJECTION.DynamicAddType' -Engine 'PSCP.Custom' -Category 'Injection' -Severity 'Error' -Confidence 'High' -Blocking $true -File $file -FileHash $hash -Line $commandAst.Extent.StartLineNumber -Column $commandAst.Extent.StartColumnNumber -Message 'Add-Type receives a non-constant type definition.' -Consequence 'Modified input can compile and load arbitrary .NET or native interop code into the process.' -Remediation 'Keep type definitions as reviewed constant source or ship a signed, versioned assembly with an integrity check.' -Evidence "$commandText; sources=$(if ($definitionSources.Count) { $definitionSources -join ', ' } else { 'unknown' })" -Tags @('code-generation', 'injection') -Cwe 'CWE-94'
            }
        }

        if ($commandName -match '^(?i:cmd|cmd\.exe|powershell|powershell\.exe|pwsh|pwsh\.exe)$') {
            if ($commandText -match '(?i)-(?:EncodedCommand|enc)\b') {
                Add-PSCPFinding -RuleId 'PSCP.OBFUSCATION.EncodedCommand' -Engine 'PSCP.Custom' -Category 'Obfuscation' -Severity 'Error' -Confidence 'High' -Blocking $true -File $file -FileHash $hash -Line $commandAst.Extent.StartLineNumber -Column $commandAst.Extent.StartColumnNumber -Message "'$commandName' is launched with an encoded command." -Consequence 'The child process hides executable code from normal review and may bypass simple command-line controls.' -Remediation 'Replace the encoded command with transparent source and fixed parameters. Analyze the decoded artifact before testing.' -Evidence $commandText -Tags @('encoded-command', 'process-execution') -Attack @('T1027.010', 'T1059.001')
            }
            if ($commandText -match '(?i)(?:/c|/k|-command|-c)\s+["''][^"'']*\$[^"'']+["'']') {
                Add-PSCPFinding -RuleId 'PSCP.INJECTION.NativeShellInterpolation' -Engine 'PSCP.Custom' -Category 'Injection' -Severity 'Error' -Confidence 'High' -Blocking $true -File $file -FileHash $hash -Line $commandAst.Extent.StartLineNumber -Column $commandAst.Extent.StartColumnNumber -Message 'An interpolated string is passed to a command interpreter.' -Consequence 'Metacharacters in the interpolated value can alter the command and execute unintended operations.' -Remediation 'Avoid command-string construction. Invoke the intended executable directly and pass validated arguments separately.' -Evidence "$commandText; sources=$sourceText" -Tags @('command-injection', 'native-command') -Cwe 'CWE-78'
            }
        }

        if ($commandName -eq 'Start-Process') {
            $filePathAst = Get-PSCPStaticArgument -CommandAst $commandAst -ParameterNames @('FilePath') -Position 0
            $argumentListAst = Get-PSCPStaticArgument -CommandAst $commandAst -ParameterNames @('ArgumentList') -Position 1
            if ($filePathAst -and $null -eq (Get-PSCPAstConstantText -Ast $filePathAst)) {
                $pathSources = @(Get-PSCPTaintSources -Ast $filePathAst -TaintMap $TaintMap)
                Add-PSCPFinding -RuleId 'PSCP.INJECTION.DynamicExecutablePath' -Engine 'PSCP.Custom' -Category 'Injection' -Severity $(if ($pathSources.Count) { 'Error' } else { 'Warning' }) -Confidence 'Medium' -Blocking ($pathSources.Count -gt 0) -File $file -FileHash $hash -Line $commandAst.Extent.StartLineNumber -Column $commandAst.Extent.StartColumnNumber -Message 'Start-Process receives a dynamic executable path.' -Consequence 'A modified path can select an unintended executable, including one placed in a writable directory.' -Remediation 'Resolve the executable to an allowlisted absolute path and verify its publisher or pinned hash.' -Evidence "$commandText; sources=$(if ($pathSources.Count) { $pathSources -join ', ' } else { 'unknown' })" -Tags @('process-execution', 'path-control') -Cwe 'CWE-427'
            }
            if ($argumentListAst -is [System.Management.Automation.Language.ExpandableStringExpressionAst]) {
                $argumentSources = @(Get-PSCPTaintSources -Ast $argumentListAst -TaintMap $TaintMap)
                if ($argumentSources.Count -gt 0) {
                    Add-PSCPFinding -RuleId 'PSCP.INJECTION.ProcessArgumentString' -Engine 'PSCP.Custom' -Category 'Injection' -Severity 'Warning' -Confidence 'Medium' -Blocking $false -File $file -FileHash $hash -Line $commandAst.Extent.StartLineNumber -Column $commandAst.Extent.StartColumnNumber -Message 'Start-Process builds ArgumentList as one interpolated string from external input.' -Consequence 'Quoting and token boundaries can change, allowing argument or command-line injection into the child program.' -Remediation 'Validate each value and construct an argument array when the target PowerShell/.NET version supports reliable native argument passing.' -Evidence "$commandText; sources=$($argumentSources -join ', ')" -Tags @('argument-injection', 'process-execution') -Cwe 'CWE-88'
                }
            }
        }

        if ($networkCommands -contains $commandName) {
            Add-PSCPCapability -Name 'network' -File $file -Line $commandAst.Extent.StartLineNumber -Operation $commandName -Evidence $commandText
            $methodAst = Get-PSCPStaticArgument -CommandAst $commandAst -ParameterNames @('Method')
            $method = Get-PSCPAstConstantText -Ast $methodAst
            if ($method -and $method -match '^(?i:POST|PUT|PATCH|DELETE)$') {
                Add-PSCPCapability -Name 'remote-state-change' -File $file -Line $commandAst.Extent.StartLineNumber -Operation "$commandName $method" -Evidence $commandText
                if (-not (Test-PSCPCommandIsShouldProcessGuarded -CommandAst $commandAst)) {
                    Add-PSCPFinding -RuleId 'PSCP.SAFETY.RestMutationWithoutGuard' -Engine 'PSCP.Custom' -Category 'Safety' -Severity 'Warning' -Confidence 'High' -Blocking $false -File $file -FileHash $hash -Line $commandAst.Extent.StartLineNumber -Column $commandAst.Extent.StartColumnNumber -Message "An HTTP $method request can mutate remote state without a proven ShouldProcess guard." -Consequence 'The script may change or delete remote resources during a test or accidental invocation.' -Remediation 'Place the request inside a same-scope ShouldProcess check and provide a simulation path that performs no network mutation.' -Evidence $commandText -Tags @('rest', 'should-process')
                }
            }
        }

        if ($commandName -match '^(?i:Install-Module|Install-Script|Save-Module|Save-Script|Install-PSResource|Save-PSResource|Update-Module)$') {
            $versionArgument = Get-PSCPStaticArgument -CommandAst $commandAst -ParameterNames @('RequiredVersion', 'Version')
            if (-not $versionArgument) {
                Add-PSCPFinding -RuleId 'PSCP.SUPPLYCHAIN.UnpinnedPackage' -Engine 'PSCP.Custom' -Category 'SupplyChain' -Severity 'Warning' -Confidence 'High' -Blocking $false -File $file -FileHash $hash -Line $commandAst.Extent.StartLineNumber -Column $commandAst.Extent.StartColumnNumber -Message "'$commandName' does not pin an exact package version." -Consequence 'A future or compromised package release can change script behaviour without a source-code change.' -Remediation 'Pin RequiredVersion/Version, constrain the repository, and record the loaded module path and hash.' -Evidence $commandText -Tags @('dependency', 'supply-chain') -Cwe 'CWE-1104'
            }
            if ($commandText -match '(?i)-(?:SkipPublisherCheck|AllowClobber|TrustRepository)\b') {
                Add-PSCPFinding -RuleId 'PSCP.SUPPLYCHAIN.BypassedPackageValidation' -Engine 'PSCP.Custom' -Category 'SupplyChain' -Severity 'Error' -Confidence 'High' -Blocking $true -File $file -FileHash $hash -Line $commandAst.Extent.StartLineNumber -Column $commandAst.Extent.StartColumnNumber -Message "'$commandName' bypasses a package installation safeguard." -Consequence 'Publisher verification or command-collision protections may be disabled during dependency installation.' -Remediation 'Remove the bypass flag and install the pinned dependency into a private tool cache before importing its exact manifest path.' -Evidence $commandText -Tags @('dependency', 'supply-chain') -Cwe 'CWE-494'
            }
        }

        $pipelineAst = $commandAst.Parent
        while ($pipelineAst -and -not ($pipelineAst -is [System.Management.Automation.Language.PipelineAst])) { $pipelineAst = $pipelineAst.Parent }
        if ($pipelineAst -and $dynamicExecutionCommands -contains $commandName) {
            $pipelineCommands = @($pipelineAst.PipelineElements | Where-Object { $_ -is [System.Management.Automation.Language.CommandAst] } | ForEach-Object { Get-PSCPCommandName -CommandAst $_ })
            if (@($pipelineCommands | Where-Object { $networkCommands -contains $_ }).Count -gt 0) {
                Add-PSCPFinding -RuleId 'PSCP.MALWARE.DirectDownloadExecute' -Engine 'PSCP.Custom' -Category 'MalwareIndicator' -Severity 'Critical' -Confidence 'High' -Blocking $true -File $file -FileHash $hash -Line $pipelineAst.Extent.StartLineNumber -Column $pipelineAst.Extent.StartColumnNumber -Message 'A pipeline downloads remote content and immediately executes it.' -Consequence 'Remote code runs without a durable artifact, publisher verification, or hash validation.' -Remediation 'Download to a quarantined path, verify an expected hash and trusted signature, inspect the content, and invoke only a reviewed fixed entry point.' -Evidence $pipelineAst.Extent.Text -Tags @('download-execute', 'fileless') -Cwe 'CWE-494' -Attack @('T1105', 'T1059.001')
            }
        }
    }

    $dangerousMethods = @('InvokeScript', 'CreateNestedPipeline', 'AddScript', 'NewScriptBlock', 'ExpandString')
    foreach ($memberAst in @($Ast.FindAll({ param($node) $node -is [System.Management.Automation.Language.InvokeMemberExpressionAst] }, $true))) {
        $memberName = $memberAst.Member.Extent.Text.Trim("'", '"')
        $memberSources = @(Get-PSCPTaintSources -Ast $memberAst -TaintMap $TaintMap)
        $isScriptBlockCreate = $memberName -eq 'Create' -and $memberAst.Expression.Extent.Text -match '(?i)ScriptBlock'
        if ($dangerousMethods -contains $memberName -or $isScriptBlockCreate) {
            $ruleName = if ($isScriptBlockCreate) { 'ScriptBlock.Create' } else { $memberName }
            Add-PSCPFinding -RuleId 'PSCP.INJECTION.DangerousMethod' -Engine 'PSCP.Custom' -Category 'Injection' -Severity $(if ($memberSources.Count) { 'Critical' } else { 'Error' }) -Confidence $(if ($memberSources.Count) { 'High' } else { 'Medium' }) -Blocking $true -File $file -FileHash $hash -Line $memberAst.Extent.StartLineNumber -Column $memberAst.Extent.StartColumnNumber -Message "Dynamic code execution method '$ruleName' is used." -Consequence 'Text can be converted into executable PowerShell and run in the current security context.' -Remediation 'Use fixed script blocks and AddCommand/AddParameter APIs with typed, validated values.' -Evidence "$($memberAst.Extent.Text); sources=$(if ($memberSources.Count) { $memberSources -join ', ' } else { 'not proven' })" -Tags @('dynamic-execution', 'injection') -Cwe 'CWE-94'
        }
        if (-not ($memberAst.Member -is [System.Management.Automation.Language.StringConstantExpressionAst]) -and
            -not ($memberAst.Member -is [System.Management.Automation.Language.ConstantExpressionAst])) {
            Add-PSCPFinding -RuleId 'PSCP.INJECTION.DynamicMethod' -Engine 'PSCP.Custom' -Category 'Injection' -Severity $(if ($memberSources.Count) { 'Error' } else { 'Warning' }) -Confidence 'Medium' -Blocking ($memberSources.Count -gt 0) -File $file -FileHash $hash -Line $memberAst.Extent.StartLineNumber -Column $memberAst.Extent.StartColumnNumber -Message 'A method name is selected dynamically.' -Consequence 'External input could invoke an unintended method on the target object.' -Remediation 'Map allowlisted operation names to fixed method calls and reject all other values.' -Evidence "$($memberAst.Extent.Text); sources=$(if ($memberSources.Count) { $memberSources -join ', ' } else { 'unknown' })" -Tags @('method-injection') -Cwe 'CWE-470'
        }
        if ($memberName -match '^(?i:DownloadString|DownloadData|DownloadFile|UploadString|UploadData|UploadFile)$') {
            Add-PSCPCapability -Name 'network' -File $file -Line $memberAst.Extent.StartLineNumber -Operation $memberName -Evidence $memberAst.Extent.Text
        }
        if ($memberName -eq 'Start' -and $memberAst.Expression.Extent.Text -match '(?i)(?:Diagnostics\.)?Process') {
            Add-PSCPCapability -Name 'processes' -File $file -Line $memberAst.Extent.StartLineNumber -Operation 'System.Diagnostics.Process.Start' -Evidence $memberAst.Extent.Text
        }
        $memberTarget = $memberAst.Expression.Extent.Text
        $dotNetStateChange = $null
        if ($memberTarget -match '(?i)(?:\[|\.)?(?:System\.)?IO\.(?:File|Directory)' -and $memberName -match '^(?i:WriteAllText|WriteAllBytes|WriteAllLines|AppendAllText|AppendAllLines|Create|CreateText|Delete|Move|Copy|Replace|SetAttributes|SetCreationTime|SetLastWriteTime|CreateDirectory)$') {
            $dotNetRisk = if ($memberName -in @('Delete', 'Move', 'Replace')) { 'high' } else { 'medium' }
            $dotNetStateChange = [pscustomobject]@{ capability='filesystem'; risk=$dotNetRisk }
        }
        elseif ($memberTarget -match '(?i)(?:Registry|RegistryKey)' -and $memberName -match '^(?i:SetValue|DeleteValue|CreateSubKey|DeleteSubKey|DeleteSubKeyTree|SetAccessControl)$') {
            $dotNetRisk = if ($memberName -match '^Delete') { 'high' } else { 'medium' }
            $dotNetStateChange = [pscustomobject]@{ capability='registry'; risk=$dotNetRisk }
        }
        elseif ($memberTarget -match '(?i)ServiceController' -and $memberName -match '^(?i:Start|Stop|Pause|Continue|ExecuteCommand)$') {
            $dotNetStateChange = [pscustomobject]@{ capability='services'; risk='medium' }
        }
        if ($dotNetStateChange) {
            Add-PSCPCapability -Name $dotNetStateChange.capability -File $file -Line $memberAst.Extent.StartLineNumber -Operation ".NET::$memberName" -Evidence $memberAst.Extent.Text
            $scopeAst = Get-PSCPContainingFunction -Ast $memberAst
            if (-not $scopeAst) { $scopeAst = $Ast }
            $supports = Test-PSCPSupportsShouldProcess -ScopeAst $scopeAst
            $guarded = Test-PSCPCommandIsShouldProcessGuarded -CommandAst $memberAst
            if (-not ($supports -and $guarded)) {
                $severity = if ($dotNetStateChange.risk -eq 'high') { 'Error' } else { 'Warning' }
                Add-PSCPFinding -RuleId 'PSCP.SAFETY.DotNetShouldProcessCoverage' -Engine 'PSCP.Custom' -Category 'Safety' -Severity $severity -Confidence 'Medium' -Blocking ($severity -eq 'Error') -File $file -FileHash $hash -Line $memberAst.Extent.StartLineNumber -Column $memberAst.Extent.StartColumnNumber -Message ".NET state-changing method '$memberName' is not proven to be inside a same-scope ShouldProcess guard." -Consequence 'The operation can bypass PowerShell -WhatIf and confirmation expectations.' -Remediation 'Wrap the method call in a scope that supports ShouldProcess and invoke it only after a same-scope $PSCmdlet.ShouldProcess decision.' -Evidence $memberAst.Extent.Text -Tags @('should-process', $dotNetStateChange.capability)
            }
        }
    }

    foreach ($memberAst in @($Ast.FindAll({
        param($node)
        $node -is [System.Management.Automation.Language.MemberExpressionAst] -and
        -not ($node -is [System.Management.Automation.Language.InvokeMemberExpressionAst])
    }, $true))) {
        if (-not ($memberAst.Member -is [System.Management.Automation.Language.StringConstantExpressionAst]) -and
            -not ($memberAst.Member -is [System.Management.Automation.Language.ConstantExpressionAst])) {
            $propertySources = @(Get-PSCPTaintSources -Ast $memberAst.Member -TaintMap $TaintMap)
            Add-PSCPFinding -RuleId 'PSCP.INJECTION.DynamicProperty' -Engine 'PSCP.Custom' -Category 'Injection' -Severity $(if ($propertySources.Count) { 'Error' } else { 'Warning' }) -Confidence 'Medium' -Blocking ($propertySources.Count -gt 0) -File $file -FileHash $hash -Line $memberAst.Extent.StartLineNumber -Column $memberAst.Extent.StartColumnNumber -Message 'A property name is selected dynamically.' -Consequence 'External input could disclose or modify an unintended property.' -Remediation 'Allowlist property names and use a fixed mapping rather than unrestricted dynamic member access.' -Evidence "$($memberAst.Extent.Text); sources=$(if ($propertySources.Count) { $propertySources -join ', ' } else { 'unknown' })" -Tags @('property-injection') -Cwe 'CWE-470'
        }
    }

    foreach ($replaceAst in @($Ast.FindAll({
        param($node)
        $node -is [System.Management.Automation.Language.BinaryExpressionAst] -and
        $node.Operator.ToString() -match '(?i)Replace' -and
        $node.Right.Extent.Text -match '[`"'']'
    }, $true))) {
        Add-PSCPFinding -RuleId 'PSCP.INJECTION.UnsafeEscaping' -Engine 'PSCP.Custom' -Category 'Injection' -Severity 'Warning' -Confidence 'Low' -Blocking $false -File $file -FileHash $hash -Line $replaceAst.Extent.StartLineNumber -Column $replaceAst.Extent.StartColumnNumber -Message 'String replacement appears to implement manual quote escaping.' -Consequence 'Hand-written escaping is context-sensitive and can permit injection when the result reaches code, command, SQL, LDAP, or another interpreter.' -Remediation 'Avoid constructing interpreter text. Use typed parameters or the target API parameterization mechanism.' -Evidence $replaceAst.Extent.Text -Tags @('escaping', 'injection') -Cwe 'CWE-116'
    }
}

function Invoke-PSCPSecretChecks {
    param(
        [Parameter(Mandatory = $true)][object]$FileContext,
        [Parameter(Mandatory = $true)][System.Management.Automation.Language.ScriptBlockAst]$Ast,
        [Parameter(Mandatory = $true)][string]$Raw
    )
    $file = $FileContext.relativePath
    $hash = $FileContext.sha256
    $secretNamePattern = '(?i)(?:password|passwd|pwd|secret|token|api[_-]?key|client[_-]?secret|access[_-]?token|bearer|credential|accountkey|private[_-]?key)'
    $placeholderPattern = '(?i)^(?:example|sample|placeholder|changeme|replace[-_ ]?me|dummy|test|your[-_ ].+|<.+>|\*+|x+)$'

    foreach ($assignment in @($Ast.FindAll({
        param($node)
        $node -is [System.Management.Automation.Language.AssignmentStatementAst] -and
        $node.Left -is [System.Management.Automation.Language.VariableExpressionAst]
    }, $true))) {
        $variableName = $assignment.Left.VariablePath.UserPath
        if ($variableName -notmatch $secretNamePattern) { continue }
        if ($variableName -match '(?i)(?:pattern|regex|rule|field|name)s?$') { continue }
        $valueAst = $assignment.Right
        if ($valueAst -is [System.Management.Automation.Language.CommandExpressionAst]) { $valueAst = $valueAst.Expression }
        $literal = Get-PSCPAstConstantText -Ast $valueAst
        if ([string]::IsNullOrEmpty($literal) -or $literal -match $placeholderPattern) { continue }
        $valueHash = Get-PSCPSha256Text -Text $literal
        $entropy = Get-PSCPShannonEntropy -Text $literal
        $severity = if ($literal.Length -ge 12 -or $entropy -ge 3.5) { 'Error' } else { 'Warning' }
        Add-PSCPFinding -RuleId 'PSCP.SECRET.HardcodedAssignment' -Engine 'PSCP.Custom' -Category 'Secrets' -Severity $severity -Confidence 'High' -Blocking ($severity -eq 'Error') -File $file -FileHash $hash -Line $assignment.Extent.StartLineNumber -Column $assignment.Extent.StartColumnNumber -Message "Credential-like variable '$variableName' receives a literal value." -Consequence 'The secret can be exposed through source control, logs, reports, process inspection, or unauthorized file access.' -Remediation 'Retrieve the value at runtime from a managed secret store or accept a PSCredential/SecureString without embedding it in source.' -Evidence "variable=$variableName; literalLength=$($literal.Length); literalSha256Prefix=$($valueHash.Substring(0, 12)); entropy=$entropy" -Tags @('secret', 'credential') -Cwe 'CWE-798'
    }

    foreach ($parameter in @($Ast.FindAll({ param($node) $node -is [System.Management.Automation.Language.ParameterAst] -and $null -ne $node.DefaultValue }, $true))) {
        $name = $parameter.Name.VariablePath.UserPath
        if ($name -notmatch $secretNamePattern) { continue }
        $literal = Get-PSCPAstConstantText -Ast $parameter.DefaultValue
        if ([string]::IsNullOrEmpty($literal) -or $literal -match $placeholderPattern) { continue }
        $valueHash = Get-PSCPSha256Text -Text $literal
        Add-PSCPFinding -RuleId 'PSCP.SECRET.HardcodedParameterDefault' -Engine 'PSCP.Custom' -Category 'Secrets' -Severity 'Error' -Confidence 'High' -Blocking $true -File $file -FileHash $hash -Line $parameter.Extent.StartLineNumber -Column $parameter.Extent.StartColumnNumber -Message "Credential-like parameter '$name' has a literal default value." -Consequence 'Every copy of the script contains the credential and may use it silently when the caller omits the parameter.' -Remediation 'Remove the default and require a secure runtime value from a secret store or PSCredential.' -Evidence "parameter=$name; literalLength=$($literal.Length); literalSha256Prefix=$($valueHash.Substring(0, 12))" -Tags @('secret', 'credential') -Cwe 'CWE-798'
    }

    $scanText = [regex]::Replace($Raw, '(?s)# SIG # Begin signature block.*?# SIG # End signature block', '')
    $patterns = @(
        [pscustomobject]@{ id = 'PrivateKey'; pattern = '(?m)-----BEGIN (?:RSA |EC |OPENSSH |DSA )?PRIVATE KEY-----'; message = 'A private-key header is embedded in the file.' },
        [pscustomobject]@{ id = 'AwsAccessKey'; pattern = '\bAKIA[0-9A-Z]{16}\b'; message = 'A value matching an AWS access-key identifier is embedded in the file.' },
        [pscustomobject]@{ id = 'GitHubToken'; pattern = '\bgh[pousr]_[A-Za-z0-9]{20,}\b'; message = 'A value matching a GitHub token is embedded in the file.' },
        [pscustomobject]@{ id = 'SlackToken'; pattern = '\bxox[baprs]-[A-Za-z0-9-]{10,}\b'; message = 'A value matching a Slack token is embedded in the file.' },
        [pscustomobject]@{ id = 'Jwt'; pattern = '\beyJ[A-Za-z0-9_-]{8,}\.[A-Za-z0-9_-]{8,}\.[A-Za-z0-9_-]{8,}\b'; message = 'A JSON Web Token-like value is embedded in the file.' },
        [pscustomobject]@{ id = 'ConnectionStringPassword'; pattern = '(?i)(?:Password|Pwd|AccountKey)\s*=\s*[^;\s"'']{4,}'; message = 'A connection-string credential appears to be embedded in the file.' },
        [pscustomobject]@{ id = 'UrlCredential'; pattern = '(?i)https?://[^\s/:@]+:[^\s/@]+@'; message = 'A URL contains embedded user information.' }
    )
    foreach ($definition in $patterns) {
        foreach ($match in [regex]::Matches($scanText, $definition.pattern)) {
            $location = Get-PSCPLocationFromOffset -Text $scanText -Offset $match.Index
            $secretHash = Get-PSCPSha256Text -Text $match.Value
            Add-PSCPFinding -RuleId "PSCP.SECRET.$($definition.id)" -Engine 'PSCP.Custom' -Category 'Secrets' -Severity 'Critical' -Confidence 'High' -Blocking $true -File $file -FileHash $hash -Line $location.line -Column $location.column -Message $definition.message -Consequence 'The credential may already be compromised through source distribution, logs, or version history.' -Remediation 'Revoke or rotate the credential, remove it from source and history, and retrieve replacements from a managed secret store.' -Evidence "matchedType=$($definition.id); length=$($match.Value.Length); sha256Prefix=$($secretHash.Substring(0, 12)); value=<redacted>" -Tags @('secret') -Cwe 'CWE-798'
        }
    }
}

function Invoke-PSCPMalwareIndicatorChecks {
    param(
        [Parameter(Mandatory = $true)][object]$FileContext,
        [Parameter(Mandatory = $true)][System.Management.Automation.Language.ScriptBlockAst]$Ast,
        [Parameter(Mandatory = $true)][AllowEmptyCollection()][System.Management.Automation.Language.CommandAst[]]$CommandAsts
    )
    $file = $FileContext.relativePath
    $hash = $FileContext.sha256

    foreach ($commandAst in $CommandAsts) {
        $name = Get-PSCPCommandName -CommandAst $commandAst
        if (-not $name) { continue }
        $text = $commandAst.Extent.Text

        if ($name -match '^(?i:Register-ScheduledTask|New-ScheduledTask|New-ScheduledTaskAction|schtasks|schtasks\.exe)$') {
            Add-PSCPCapability -Name 'persistence' -File $file -Line $commandAst.Extent.StartLineNumber -Operation $name -Evidence $text
            Add-PSCPFinding -RuleId 'PSCP.MALWARE.ScheduledTaskPersistence' -Engine 'PSCP.Custom' -Category 'MalwareIndicator' -Severity 'Warning' -Confidence 'High' -Blocking $false -File $file -FileHash $hash -Line $commandAst.Extent.StartLineNumber -Column $commandAst.Extent.StartColumnNumber -Message "The script can create or change a scheduled task using '$name'." -Consequence 'Scheduled tasks can establish persistence or silently execute code under another security context.' -Remediation 'Confirm the task name, principal, trigger, action, and removal path. Require ShouldProcess and test only in a disposable sandbox.' -Evidence $text -Tags @('persistence', 'scheduled-task') -Attack @('T1053.005')
        }

        if ($name -match '^(?i:New-Service|Set-Service|sc|sc\.exe)$' -and $text -match '(?i)\b(?:create|binpath|binarypathname|startupType)\b') {
            Add-PSCPCapability -Name 'persistence' -File $file -Line $commandAst.Extent.StartLineNumber -Operation $name -Evidence $text
            Add-PSCPFinding -RuleId 'PSCP.MALWARE.ServicePersistence' -Engine 'PSCP.Custom' -Category 'MalwareIndicator' -Severity 'Warning' -Confidence 'High' -Blocking $false -File $file -FileHash $hash -Line $commandAst.Extent.StartLineNumber -Column $commandAst.Extent.StartColumnNumber -Message 'The script can install or reconfigure a Windows service executable.' -Consequence 'A service can provide boot persistence and privileged code execution.' -Remediation 'Validate the exact binary path and publisher, protect it from non-admin writes, add ShouldProcess, and document rollback.' -Evidence $text -Tags @('persistence', 'service') -Attack @('T1543.003')
        }

        if ($name -match '^(?i:Set-ItemProperty|New-ItemProperty|reg|reg\.exe)$' -and $text -match '(?i)(?:CurrentVersion\\Run(?:Once)?|Winlogon|Userinit|Shell)') {
            Add-PSCPCapability -Name 'persistence' -File $file -Line $commandAst.Extent.StartLineNumber -Operation $name -Evidence $text
            Add-PSCPFinding -RuleId 'PSCP.MALWARE.RegistryAutorun' -Engine 'PSCP.Custom' -Category 'MalwareIndicator' -Severity 'Error' -Confidence 'High' -Blocking $true -File $file -FileHash $hash -Line $commandAst.Extent.StartLineNumber -Column $commandAst.Extent.StartColumnNumber -Message 'The script writes a registry location commonly used for logon persistence.' -Consequence 'The configured payload can execute automatically when a user signs in or Windows starts.' -Remediation 'Confirm this is a documented product requirement, constrain the exact path/value, require ShouldProcess, and provide verified rollback.' -Evidence $text -Tags @('persistence', 'registry') -Attack @('T1060', 'T1547.001')
        }

        if ($name -match '^(?i:Set-MpPreference|Add-MpPreference|Remove-MpPreference)$' -and $text -match '(?i)(?:Disable|Exclusion|ThreatIDDefaultAction|PUAProtection|MAPSReporting|SubmitSamplesConsent)') {
            Add-PSCPCapability -Name 'security-controls' -File $file -Line $commandAst.Extent.StartLineNumber -Operation $name -Evidence $text
            Add-PSCPFinding -RuleId 'PSCP.MALWARE.DefenderConfigurationChange' -Engine 'PSCP.Custom' -Category 'DefenseEvasion' -Severity 'Error' -Confidence 'High' -Blocking $true -File $file -FileHash $hash -Line $commandAst.Extent.StartLineNumber -Column $commandAst.Extent.StartColumnNumber -Message 'The script changes Microsoft Defender protection or exclusion settings.' -Consequence 'Protection coverage may be reduced, allowing malicious content or locations to evade scanning.' -Remediation 'Do not disable protections. If a narrowly scoped exclusion is operationally required, document approval, expiry, exact scope, and rollback.' -Evidence $text -Tags @('defense-evasion', 'defender') -Attack @('T1562.001')
        }

        if ($name -match '^(?i:reg|reg\.exe)$' -and $text -match '(?i)\bsave\b.*\\(?:SAM|SECURITY|SYSTEM)\b') {
            Add-PSCPCapability -Name 'credential-access' -File $file -Line $commandAst.Extent.StartLineNumber -Operation $name -Evidence $text
            Add-PSCPFinding -RuleId 'PSCP.MALWARE.RegistryCredentialHiveExport' -Engine 'PSCP.Custom' -Category 'CredentialAccess' -Severity 'Critical' -Confidence 'High' -Blocking $true -File $file -FileHash $hash -Line $commandAst.Extent.StartLineNumber -Column $commandAst.Extent.StartColumnNumber -Message 'The script exports a Windows credential-related registry hive.' -Consequence 'Offline extraction can expose local account password hashes and security secrets.' -Remediation 'Do not run the script. Confirm authorization and intent, then isolate and investigate the source as potential credential theft.' -Evidence $text -Tags @('credential-access', 'registry') -Attack @('T1003.002')
        }

        if ($name -match '^(?i:rundll32|rundll32\.exe)$' -and $text -match '(?i)comsvcs\.dll.*MiniDump') {
            Add-PSCPCapability -Name 'credential-access' -File $file -Line $commandAst.Extent.StartLineNumber -Operation $name -Evidence $text
            Add-PSCPFinding -RuleId 'PSCP.MALWARE.LsassMiniDump' -Engine 'PSCP.Custom' -Category 'CredentialAccess' -Severity 'Critical' -Confidence 'High' -Blocking $true -File $file -FileHash $hash -Line $commandAst.Extent.StartLineNumber -Column $commandAst.Extent.StartColumnNumber -Message 'The script invokes the comsvcs MiniDump export, a known LSASS dumping technique.' -Consequence 'Process memory can expose reusable credentials, password hashes, and authentication material.' -Remediation 'Do not run the script. Isolate the source, validate authorization, and investigate it as potential credential theft.' -Evidence $text -Tags @('credential-dumping', 'lolbin') -Attack @('T1003.001')
        }

        if ($name -match '^(?i:mshta|mshta\.exe|regsvr32|regsvr32\.exe|rundll32|rundll32\.exe|certutil|certutil\.exe|bitsadmin|bitsadmin\.exe)$') {
            $suspicious = $text -match '(?i)(?:https?://|javascript:|vbscript:|scrobj\.dll|urlcache|decode|/transfer|\\\\)'
            Add-PSCPCapability -Name 'native-processes' -File $file -Line $commandAst.Extent.StartLineNumber -Operation $name -Evidence $text
            if ($suspicious) {
                Add-PSCPFinding -RuleId 'PSCP.MALWARE.SuspiciousLolBin' -Engine 'PSCP.Custom' -Category 'MalwareIndicator' -Severity 'Error' -Confidence 'High' -Blocking $true -File $file -FileHash $hash -Line $commandAst.Extent.StartLineNumber -Column $commandAst.Extent.StartColumnNumber -Message "Living-off-the-land binary '$name' is used with network, script, or decoding arguments." -Consequence 'The command can proxy execution or transfer/decode a payload while blending into trusted Windows tooling.' -Remediation 'Replace it with a direct, reviewable API and verify any downloaded artifact using a pinned hash and trusted signature.' -Evidence $text -Tags @('lolbin', 'defense-evasion') -Attack @('T1218', 'T1105')
            }
            else {
                Add-PSCPFinding -RuleId 'PSCP.MALWARE.LolBinUse' -Engine 'PSCP.Custom' -Category 'MalwareIndicator' -Severity 'Warning' -Confidence 'Medium' -Blocking $false -File $file -FileHash $hash -Line $commandAst.Extent.StartLineNumber -Column $commandAst.Extent.StartColumnNumber -Message "Dual-use Windows binary '$name' is invoked." -Consequence 'This binary is frequently abused for proxy execution or payload handling, although legitimate uses exist.' -Remediation 'Confirm the exact arguments and necessity; prefer a direct API with allowlisted inputs where practical.' -Evidence $text -Tags @('lolbin') -Attack @('T1218')
            }
        }

        if ($name -match '^(?i:Clear-Disk|Format-Volume|Initialize-Disk|Remove-Partition|Stop-Computer|Restart-Computer)$') {
            Add-PSCPCapability -Name 'destructive-system-change' -File $file -Line $commandAst.Extent.StartLineNumber -Operation $name -Evidence $text
            Add-PSCPFinding -RuleId 'PSCP.SAFETY.HighImpactSystemChange' -Engine 'PSCP.Custom' -Category 'Safety' -Severity 'Error' -Confidence 'High' -Blocking $true -File $file -FileHash $hash -Line $commandAst.Extent.StartLineNumber -Column $commandAst.Extent.StartColumnNumber -Message "High-impact system command '$name' is present." -Consequence 'An incorrect target or partial run can destroy data or make the test host unavailable.' -Remediation 'Require exact target validation, ShouldProcess, explicit confirmation, pre-change backups, and an isolated disposable test machine.' -Evidence $text -Tags @('destructive', 'system-change')
        }
    }

    foreach ($stringAst in @($Ast.FindAll({ param($node) $node -is [System.Management.Automation.Language.StringConstantExpressionAst] }, $true))) {
        $value = [string]$stringAst.Value
        if ($value -match '^(?i:(?:root\\subscription:)?(?:__EventFilter|CommandLineEventConsumer|__FilterToConsumerBinding))$') {
            Add-PSCPFinding -RuleId 'PSCP.MALWARE.WmiEventPersistence' -Engine 'PSCP.Custom' -Category 'MalwareIndicator' -Severity 'Error' -Confidence 'Medium' -Blocking $true -File $file -FileHash $hash -Line $stringAst.Extent.StartLineNumber -Column $stringAst.Extent.StartColumnNumber -Message 'A WMI permanent-event persistence class name is embedded in executable source.' -Consequence 'A WMI event subscription can launch a payload persistently and without an obvious scheduled task or service.' -Remediation 'Confirm all filter, consumer, and binding creation logic and require a deterministic removal path before sandbox testing.' -Evidence $stringAst.Extent.Text -Tags @('persistence', 'wmi') -Attack @('T1546.003')
        }
    }
}

function Invoke-PSCPObfuscationChecks {
    param(
        [Parameter(Mandatory = $true)][object]$FileContext,
        [Parameter(Mandatory = $true)][System.Management.Automation.Language.ScriptBlockAst]$Ast,
        [Parameter(Mandatory = $true)][string]$CodeWithoutComments,
        [bool]$EnableDecoding,
        [int]$MaximumBytes,
        [int]$MaximumDepth
    )
    $file = $FileContext.relativePath
    $hash = $FileContext.sha256
    $decoded = @{}

    foreach ($stringAst in @($Ast.FindAll({ param($node) $node -is [System.Management.Automation.Language.StringConstantExpressionAst] }, $true))) {
        $value = [string]$stringAst.Value
        if ($value.Length -ge 160 -and $value -notmatch '\s' -and (Get-PSCPShannonEntropy -Text $value) -ge 4.7) {
            Add-PSCPFinding -RuleId 'PSCP.OBFUSCATION.HighEntropyLiteral' -Engine 'PSCP.Custom' -Category 'Obfuscation' -Severity 'Warning' -Confidence 'Medium' -Blocking $false -File $file -FileHash $hash -Line $stringAst.Extent.StartLineNumber -Column $stringAst.Extent.StartColumnNumber -Message 'A long, high-entropy string literal may conceal encoded or encrypted content.' -Consequence 'Executable behaviour or payload data may be hidden from normal source review.' -Remediation 'Document the literal format and provenance; decode or unpack it in a bounded static workflow before any execution.' -Evidence "length=$($value.Length); entropy=$(Get-PSCPShannonEntropy -Text $value); sha256Prefix=$((Get-PSCPSha256Text -Text $value).Substring(0,12))" -Tags @('obfuscation', 'entropy') -Attack @('T1027')
        }
        if (-not $EnableDecoding -or $value.Length -lt 80 -or $value.Length -gt ($MaximumBytes * 2)) { continue }
        if ($value -notmatch '^[A-Za-z0-9+/]+={0,2}$' -or ($value.Length % 4) -ne 0) { continue }
        try {
            $bytes = [Convert]::FromBase64String($value)
            $key = Get-PSCPSha256Bytes -Bytes $bytes
            if (-not $decoded.ContainsKey($key)) {
                $decoded[$key] = $true
                Add-PSCPDecodedArtifact -SourceFile $file -SourceHash $hash -Line $stringAst.Extent.StartLineNumber -Bytes $bytes -Depth 1 -Transform 'base64-literal' -MaximumBytes $MaximumBytes -MaximumDepth $MaximumDepth
                try {
                    $expanded = Expand-PSCPCompressedBytes -Bytes $bytes -MaximumBytes $MaximumBytes
                    if ($expanded) {
                        Add-PSCPDecodedArtifact -SourceFile $file -SourceHash $hash -Line $stringAst.Extent.StartLineNumber -Bytes $expanded.bytes -Depth 2 -Transform "base64+$($expanded.kind)" -MaximumBytes $MaximumBytes -MaximumDepth $MaximumDepth
                    }
                }
                catch {
                    Add-PSCPFinding -RuleId 'PSCP.OBFUSCATION.DecompressionFailed' -Engine 'PSCP.Custom' -Category 'Obfuscation' -Severity 'Warning' -Confidence 'High' -Blocking $false -File $file -FileHash $hash -Line $stringAst.Extent.StartLineNumber -Column $stringAst.Extent.StartColumnNumber -Message 'A compressed encoded artifact could not be fully expanded within the static-analysis limits.' -Consequence 'Some hidden content remains unanalyzed.' -Remediation 'Inspect the artifact in an isolated malware-analysis environment or explicitly raise the bounded decode limit.' -Evidence $_.Exception.Message -Tags @('obfuscation', 'coverage') -Attack @('T1027')
                }
            }
        }
        catch { $null = $_.Exception.Message }
    }

    foreach ($memberAst in @($Ast.FindAll({ param($node) $node -is [System.Management.Automation.Language.InvokeMemberExpressionAst] }, $true))) {
        $memberName = $memberAst.Member.Extent.Text.Trim("'", '"')
        if ($memberName -ne 'FromBase64String' -or $memberAst.Arguments.Count -lt 1) { continue }
        $literal = Get-PSCPAstConstantText -Ast $memberAst.Arguments[0]
        if (-not $literal) {
            Add-PSCPFinding -RuleId 'PSCP.OBFUSCATION.DynamicBase64Decode' -Engine 'PSCP.Custom' -Category 'Obfuscation' -Severity 'Warning' -Confidence 'Medium' -Blocking $false -File $file -FileHash $hash -Line $memberAst.Extent.StartLineNumber -Column $memberAst.Extent.StartColumnNumber -Message 'Base64 content is decoded from a value that cannot be resolved statically.' -Consequence 'The resulting bytes and any executable content remain outside static coverage.' -Remediation 'Make the expected artifact reviewable and integrity-pinned, or add a safe fixture containing the exact non-secret payload.' -Evidence $memberAst.Extent.Text -Tags @('obfuscation', 'coverage') -Attack @('T1027.010')
            continue
        }
        if (-not $EnableDecoding) { continue }
        try {
            $bytes = [Convert]::FromBase64String($literal)
            $key = Get-PSCPSha256Bytes -Bytes $bytes
            if (-not $decoded.ContainsKey($key)) {
                $decoded[$key] = $true
                Add-PSCPDecodedArtifact -SourceFile $file -SourceHash $hash -Line $memberAst.Extent.StartLineNumber -Bytes $bytes -Depth 1 -Transform 'FromBase64String' -MaximumBytes $MaximumBytes -MaximumDepth $MaximumDepth
            }
        }
        catch {
            Add-PSCPFinding -RuleId 'PSCP.OBFUSCATION.InvalidBase64Literal' -Engine 'PSCP.Custom' -Category 'Obfuscation' -Severity 'Warning' -Confidence 'High' -Blocking $false -File $file -FileHash $hash -Line $memberAst.Extent.StartLineNumber -Column $memberAst.Extent.StartColumnNumber -Message 'A literal supplied to FromBase64String is not valid Base64.' -Consequence 'The code path will fail or relies on later mutation that the analyzer cannot prove.' -Remediation 'Use a valid, documented artifact with a pinned hash and add an error-path test.' -Evidence $_.Exception.Message -Tags @('obfuscation', 'reliability')
        }
    }

    $xorCount = @([regex]::Matches($CodeWithoutComments, '(?i)\s-bxor\s')).Count
    $charCount = @([regex]::Matches($CodeWithoutComments, '(?i)\[char\]')).Count
    $reverseCount = @([regex]::Matches($CodeWithoutComments, '(?i)(?:Array\]::Reverse|\.Reverse\s*\()')).Count
    if ($xorCount -ge 3 -or $charCount -ge 8 -or ($reverseCount -gt 0 -and ($xorCount + $charCount) -gt 0)) {
        Add-PSCPFinding -RuleId 'PSCP.OBFUSCATION.CharacterTransformChain' -Engine 'PSCP.Custom' -Category 'Obfuscation' -Severity 'Warning' -Confidence 'Medium' -Blocking $false -File $file -FileHash $hash -Message 'Repeated XOR, character conversion, or reversal operations resemble a string/payload decoding chain.' -Consequence 'Runtime-generated text can conceal commands, URLs, or payloads from ordinary review.' -Remediation 'Replace runtime reconstruction with transparent source or provide a deterministic offline decoder and reviewed decoded artifact.' -Evidence "bxor=$xorCount; charCasts=$charCount; reverse=$reverseCount" -Tags @('obfuscation', 'string-decoding') -Attack @('T1027')
    }
}

function Get-PSCPObjectProperty {
    param(
        [AllowNull()][object]$InputObject,
        [Parameter(Mandatory = $true)][string]$Name,
        [AllowNull()][object]$Default = $null
    )
    if ($null -eq $InputObject) { return $Default }
    $property = $InputObject.PSObject.Properties[$Name]
    if ($property) { return $property.Value }
    return $Default
}

function Add-PSCPPssaDiagnostic {
    param(
        [Parameter(Mandatory = $true)][object]$Diagnostic,
        [Parameter(Mandatory = $true)][object]$FileContext,
        [Parameter(Mandatory = $true)][string]$PassName
    )
    $severity = [string](Get-PSCPObjectProperty -InputObject $Diagnostic -Name 'Severity' -Default 'Warning')
    if ($severity -notin @('Error', 'Warning', 'Information')) { $severity = 'Warning' }
    $ruleName = [string](Get-PSCPObjectProperty -InputObject $Diagnostic -Name 'RuleName' -Default 'PSScriptAnalyzer.Unknown')
    $line = [int](Get-PSCPObjectProperty -InputObject $Diagnostic -Name 'Line' -Default 1)
    $column = [int](Get-PSCPObjectProperty -InputObject $Diagnostic -Name 'Column' -Default 1)
    $extent = Get-PSCPObjectProperty -InputObject $Diagnostic -Name 'Extent'
    $endLine = $line
    $endColumn = $column
    $evidence = ''
    if ($extent) {
        $endLine = [int](Get-PSCPObjectProperty -InputObject $extent -Name 'EndLineNumber' -Default $line)
        $endColumn = [int](Get-PSCPObjectProperty -InputObject $extent -Name 'EndColumnNumber' -Default $column)
        $evidence = [string](Get-PSCPObjectProperty -InputObject $extent -Name 'Text' -Default '')
    }
    $suppressionId = [string](Get-PSCPObjectProperty -InputObject $Diagnostic -Name 'RuleSuppressionID' -Default '')
    $isSuppressed = [bool](Get-PSCPObjectProperty -InputObject $Diagnostic -Name 'IsSuppressed' -Default (-not [string]::IsNullOrEmpty($suppressionId)))
    $suppressionJustification = [string](Get-PSCPObjectProperty -InputObject $Diagnostic -Name 'Justification' -Default '')
    if ($isSuppressed -and $suppressionJustification) {
        $evidence = ($evidence + '; suppressionJustification=' + $suppressionJustification).TrimStart([char[]]@(';', ' '))
    }
    $suggested = @()
    foreach ($correction in @(Get-PSCPObjectProperty -InputObject $Diagnostic -Name 'SuggestedCorrections' -Default @())) {
        $suggested += [pscustomobject][ordered]@{
            description = ConvertTo-PSCPSafeText -Text ([string](Get-PSCPObjectProperty -InputObject $correction -Name 'Description' -Default '')) -MaximumLength 500
            text = ConvertTo-PSCPSafeText -Text ([string](Get-PSCPObjectProperty -InputObject $correction -Name 'Text' -Default '')) -MaximumLength 500
            startLine = [int](Get-PSCPObjectProperty -InputObject $correction -Name 'StartLineNumber' -Default $line)
            startColumn = [int](Get-PSCPObjectProperty -InputObject $correction -Name 'StartColumnNumber' -Default $column)
            endLine = [int](Get-PSCPObjectProperty -InputObject $correction -Name 'EndLineNumber' -Default $endLine)
            endColumn = [int](Get-PSCPObjectProperty -InputObject $correction -Name 'EndColumnNumber' -Default $endColumn)
        }
    }
    $message = [string](Get-PSCPObjectProperty -InputObject $Diagnostic -Name 'Message' -Default 'PSScriptAnalyzer reported a diagnostic.')
    Add-PSCPFinding -RuleId "PSSA.$ruleName" -Engine 'PSScriptAnalyzer' -Category 'PSScriptAnalyzer' -Severity $severity -Confidence 'High' -Blocking ($severity -eq 'Error') -File $FileContext.relativePath -FileHash $FileContext.sha256 -Line $line -Column $column -EndLine $endLine -EndColumn $endColumn -Message $message -Consequence 'The source violates a Microsoft PSScriptAnalyzer correctness, security, compatibility, design, or style rule.' -Remediation "Apply the rule-specific correction and rerun PSCP. Diagnostic pass: $PassName." -Evidence $evidence -Tags @('psscriptanalyzer', $PassName) -SuggestedCorrections $suggested -Suppressed $isSuppressed -SuppressionId $suppressionId
}

function Invoke-PSCPPssaAnalysis {
    param(
        [Parameter(Mandatory = $true)][object[]]$FileContexts,
        [Parameter(Mandatory = $true)][object]$ModuleInfo,
        [Parameter(Mandatory = $true)][string]$AnalysisProfile
    )
    $started = [Diagnostics.Stopwatch]::StartNew()
    $passes = New-Object 'System.Collections.Generic.List[object]'
    $settingsDirectory = Join-Path $ModuleInfo.module.ModuleBase 'Settings'
    $definitions = New-Object 'System.Collections.Generic.List[object]'
    $null = $definitions.Add([pscustomobject]@{ name = 'Default'; settings = $null })
    if ($AnalysisProfile -in @('Standard', 'Maximum')) {
        foreach ($name in @('ScriptSecurity', 'ScriptFunctions')) {
            $null = $definitions.Add([pscustomobject]@{ name = $name; settings = (Join-Path $settingsDirectory ($name + '.psd1')) })
        }
    }
    if ($AnalysisProfile -eq 'Maximum') {
        foreach ($name in @('PSGallery', 'CmdletDesign', 'ScriptingStyle', 'CodeFormatting')) {
            $null = $definitions.Add([pscustomobject]@{ name = $name; settings = (Join-Path $settingsDirectory ($name + '.psd1')) })
        }
        $compatibilitySettings = @{
            IncludeRules = @('PSUseCompatibleSyntax', 'PSUseCompatibleCommands', 'PSUseCompatibleTypes')
            Rules = @{
                PSUseCompatibleSyntax = @{ Enable = $true; TargetVersions = @('5.1', '7.0') }
                PSUseCompatibleCommands = @{ Enable = $true; TargetProfiles = @('win-48_x64_10.0.17763.0_5.1.17763.316_x64_4.0.30319.42000_framework', 'win-8_x64_10.0.17763.0_7.0.0_x64_3.1.2_core') }
                PSUseCompatibleTypes = @{ Enable = $true; TargetProfiles = @('win-48_x64_10.0.17763.0_5.1.17763.316_x64_4.0.30319.42000_framework', 'win-8_x64_10.0.17763.0_7.0.0_x64_3.1.2_core') }
            }
        }
        $null = $definitions.Add([pscustomobject]@{ name = 'Compatibility-WindowsPS5.1-PowerShell7'; settings = $compatibilitySettings })
    }

    $failed = $false
    foreach ($definition in $definitions) {
        $passStarted = [Diagnostics.Stopwatch]::StartNew()
        $diagnosticCount = 0
        $passStatus = 'completed'
        $passMessage = ''
        try {
            foreach ($context in $FileContexts) {
                $invokeArguments = @{
                    Path = $context.fullPath
                    IncludeSuppressed = $true
                    ErrorAction = 'Stop'
                    WarningAction = 'SilentlyContinue'
                }
                if ($definition.settings) { $invokeArguments.Settings = $definition.settings }
                $diagnostics = @(Invoke-ScriptAnalyzer @invokeArguments)
                $diagnosticCount += $diagnostics.Count
                foreach ($diagnostic in $diagnostics) {
                    Add-PSCPPssaDiagnostic -Diagnostic $diagnostic -FileContext $context -PassName $definition.name
                }
            }
        }
        catch {
            $failed = $true
            $passStatus = 'failed'
            $passMessage = $_.Exception.Message
            $null = $script:AnalysisErrors.Add("PSScriptAnalyzer pass '$($definition.name)' failed: $($_.Exception.Message)")
        }
        $passStarted.Stop()
        $null = $passes.Add([pscustomobject][ordered]@{ name = $definition.name; status = $passStatus; diagnostics = $diagnosticCount; durationMs = [int]$passStarted.ElapsedMilliseconds; message = ConvertTo-PSCPSafeText -Text $passMessage -MaximumLength 500 })
    }
    $started.Stop()
    Add-PSCPEngine -Name 'PSScriptAnalyzer' -Status $(if ($failed) { 'failed' } else { 'completed' }) -Required $true -Version $ModuleInfo.module.Version.ToString() -Message $(if ($failed) { 'One or more PSScriptAnalyzer passes failed; the result is incomplete.' } else { 'All requested PSScriptAnalyzer passes completed.' }) -DurationMs ([int]$started.ElapsedMilliseconds) -Details $passes.ToArray()
}

function Get-PSCPTestPlan {
    param([Parameter(Mandatory = $true)][AllowEmptyCollection()][object[]]$Capabilities)
    $tests = New-Object 'System.Collections.Generic.List[object]'
    $names = @($Capabilities | ForEach-Object { $_.name })
    $counter = 0
    $baseTests = @(
        [pscustomobject]@{ area='syntax'; scenario='Parse every target under each declared PowerShell host'; expected='No parser errors and the same intended AST structure'; isolation='No execution' },
        [pscustomobject]@{ area='parameters'; scenario='Exercise missing, null, malformed, boundary, and conflicting parameters'; expected='Deterministic validation errors with no side effects'; isolation='Mock or disposable sandbox' },
        [pscustomobject]@{ area='errors'; scenario='Force each external command and API call to fail'; expected='Non-zero/failed structured result; cleanup runs; no false success'; isolation='Mock all external boundaries' },
        [pscustomobject]@{ area='idempotency'; scenario='Run twice against the same prepared state'; expected='Second run is safe and converges without duplicate or destructive changes'; isolation='Disposable sandbox' }
    )
    foreach ($test in $baseTests) { $counter++; $null = $tests.Add([pscustomobject][ordered]@{ id=('T{0:d2}' -f $counter); area=$test.area; scenario=$test.scenario; expected=$test.expected; isolation=$test.isolation }) }
    $capabilityTests = @{
        network = @('network', 'Return timeouts, TLS failures, authentication failures, throttling, and malformed responses', 'Bounded retry/timeout behaviour and explicit failure without executing returned content', 'Mock HTTP or an isolated test endpoint')
        filesystem = @('filesystem', 'Use missing, locked, read-only, long, relative, traversal, and symlink/reparse-point paths', 'Targets remain inside the approved root and partial writes are cleaned up', 'Temporary directory or disposable VM')
        registry = @('registry', 'Use absent keys, denied access, wrong value types, and 32/64-bit registry views', 'No unexpected key creation and rollback is verifiable', 'Disposable Windows VM')
        services = @('services', 'Use missing, running, stopped, disabled, and access-denied services', 'Exact target only; WhatIf is side-effect free; failures propagate', 'Disposable Windows VM')
        'scheduled-tasks' = @('scheduled-tasks', 'Use existing/missing task names and constrained principals', 'Exact task/action/trigger shown in WhatIf; create/update/remove is reversible', 'Disposable Windows VM')
        processes = @('processes', 'Return non-zero exit, timeout, missing executable, hostile arguments, and large output', 'Arguments remain distinct; exit/timeout/stderr are reported', 'Stub executable or disposable VM')
        'native-processes' = @('native-processes', 'Exercise quoting, metacharacters, non-zero exit, and missing binary', 'No shell reinterpretation; exact executable path and argument boundaries are retained', 'Stub executable or disposable VM')
        'remote-state-change' = @('remote-state-change', 'Run -WhatIf and simulate 4xx/5xx responses around each mutation', 'WhatIf sends no mutating request and failures do not report success', 'Mock service')
        persistence = @('persistence', 'Create, inspect, rerun, and remove the persistence mechanism', 'Configuration is exact, approved, idempotent, visible, and fully reversible', 'Disposable Windows VM only')
        'security-controls' = @('security-controls', 'Verify denied changes and restoration after every allowed change', 'Security posture is never silently weakened and rollback is automatic', 'Disposable Windows VM with explicit approval')
        'destructive-system-change' = @('destructive-system-change', 'Exercise only against sacrificial virtual disks or disposable hosts', 'Target confirmation, WhatIf, backup, and rollback gates prevent accidental impact', 'Dedicated disposable VM; never a workstation')
        'credential-access' = @('credential-access', 'Do not execute until authorization and business purpose are independently confirmed', 'No credentials are collected in ordinary testing', 'Dedicated security lab')
    }
    foreach ($name in @($names | Sort-Object -Unique)) {
        if (-not $capabilityTests.ContainsKey($name)) { continue }
        $definition = $capabilityTests[$name]
        $counter++
        $null = $tests.Add([pscustomobject][ordered]@{ id=('T{0:d2}' -f $counter); area=$definition[0]; scenario=$definition[1]; expected=$definition[2]; isolation=$definition[3] })
    }
    return $tests.ToArray()
}

function Write-PSCPResult {
    param(
        [Parameter(Mandatory = $true)][object]$Result,
        [Parameter(Mandatory = $true)][string]$Format,
        [AllowEmptyString()][string]$LiteralOutputPath
    )
    $json = $Result | ConvertTo-Json -Depth 18
    if ($LiteralOutputPath) {
        $parent = Split-Path -Parent ([IO.Path]::GetFullPath($LiteralOutputPath))
        if ($parent -and -not (Test-Path -LiteralPath $parent)) { $null = New-Item -ItemType Directory -Path $parent -Force }
        $utf8NoBom = New-Object Text.UTF8Encoding($false)
        [IO.File]::WriteAllText([IO.Path]::GetFullPath($LiteralOutputPath), $json, $utf8NoBom)
    }
    if ($Format -eq 'Object') {
        Write-Output $Result
    }
    elseif ($Format -eq 'Text') {
        $lines = @(
            "PSCP $($Result.tool.version): $($Result.verdict)",
            $Result.summary.directAnswer,
            "Files: $($Result.summary.filesAnalyzed) | Findings: $($Result.summary.totalFindings) | Critical: $($Result.summary.bySeverity.Critical) | Error: $($Result.summary.bySeverity.Error) | Warning: $($Result.summary.bySeverity.Warning)",
            "Analysis complete: $($Result.analysisComplete) | Safe to begin sandbox testing: $($Result.safeToBeginSandboxTesting)",
            "Next: $($Result.summary.recommendedAction)"
        )
        Write-Output ($lines -join [Environment]::NewLine)
    }
    else {
        Write-Output $json
    }
}

function Get-PSCPResult {
    param(
        [Parameter(Mandatory = $true)][string]$Verdict,
        [Parameter(Mandatory = $true)][int]$ExitCode,
        [Parameter(Mandatory = $true)][bool]$AnalysisComplete,
        [Parameter(Mandatory = $true)][string]$MinimumReportedSeverity
    )
    $orderedFindings = @($script:Findings | Sort-Object @{Expression={ Get-PSCPSeverityRank -Severity $_.severity }}, file, line, column, ruleId, fingerprint)
    $minimumRank = Get-PSCPSeverityRank -Severity $MinimumReportedSeverity
    $reportedFindings = @($orderedFindings | Where-Object { (Get-PSCPSeverityRank -Severity $_.severity) -le $minimumRank })
    $capabilities = @()
    foreach ($name in @($script:CapabilityIndex.Keys | Sort-Object)) {
        $capabilities += [pscustomobject][ordered]@{ name = $name; occurrences = @($script:CapabilityIndex[$name] | ForEach-Object { [pscustomobject][ordered]@{ file=$_.file; line=$_.line; operation=$_.operation; evidence=$_.evidence } }) }
    }
    $severityCounts = [ordered]@{}
    foreach ($severity in @('Critical', 'Error', 'Warning', 'Information')) { $severityCounts[$severity] = @($orderedFindings | Where-Object { $_.severity -eq $severity }).Count }
    $blockingCount = @($orderedFindings | Where-Object { $_.blocking -and -not $_.suppressed }).Count
    $malwareFindings = @($orderedFindings | Where-Object { $_.category -in @('MalwareIndicator', 'DefenseEvasion', 'CredentialAccess') -and -not $_.suppressed })
    $malwareAssessment = if (-not $AnalysisComplete) { 'UnknownIncomplete' } elseif (@($malwareFindings | Where-Object { $_.severity -in @('Critical', 'Error') }).Count -gt 0) { 'HighRiskIndicators' } elseif ($malwareFindings.Count -gt 0) { 'SuspiciousIndicators' } else { 'NoStaticIndicatorsDetected' }
    $directAnswer = switch ($Verdict) {
        'PASS_STATIC' { 'No blocking static issues were found and every required analysis engine completed. This is not proof that the script is safe; begin isolated runtime testing.' }
        'REVIEW' { 'Static analysis completed, but non-blocking issues require review before runtime testing.' }
        'BLOCK' { "Do not run this script yet. $blockingCount blocking finding(s) require remediation or explicit security review." }
        'INCOMPLETE' { 'Do not treat this as a pass. One or more required analysis engines or files could not be analyzed completely.' }
        default { 'The analyzer could not complete the requested assessment.' }
    }
    $recommendedAction = switch ($Verdict) {
        'PASS_STATIC' { 'Execute the generated test plan in a disposable least-privilege sandbox, starting with -WhatIf where supported.' }
        'REVIEW' { 'Resolve or explicitly accept the reported warnings, rerun PSCP, then use a disposable sandbox.' }
        'BLOCK' { 'Fix critical/error findings and rerun PSCP. Escalate malware or credential-access indicators for security review.' }
        'INCOMPLETE' { 'Restore the missing dependency or correct the failed engine/file, then rerun until analysisComplete is true.' }
        default { 'Correct the fatal input or analyzer error and rerun.' }
    }
    $finished = [DateTime]::UtcNow
    $processArchitecture = if ([Environment]::Is64BitProcess) { 'x64' } else { 'x86' }
    return [pscustomobject][ordered]@{
        schemaVersion = '1.0.0'
        tool = [pscustomobject][ordered]@{ name='PSCP'; version=$script:PSCPVersion; mode='static-only'; targetWasExecuted=$script:TargetWasExecuted; testsWereExecuted=$script:TestsWereExecuted }
        verdict = $Verdict
        exitCode = $ExitCode
        analysisComplete = $AnalysisComplete
        safeToBeginSandboxTesting = ($Verdict -eq 'PASS_STATIC')
        malwareAssessment = $malwareAssessment
        summary = [pscustomobject][ordered]@{
            directAnswer = $directAnswer
            recommendedAction = $recommendedAction
            filesAnalyzed = $script:Files.Count
            totalFindings = $orderedFindings.Count
            reportedFindings = $reportedFindings.Count
            blockingFindings = $blockingCount
            suppressedFindings = @($orderedFindings | Where-Object { $_.suppressed }).Count
            bySeverity = [pscustomobject]$severityCounts
        }
        request = [pscustomobject][ordered]@{ paths=@($Path); profile=$AnalysisProfile; dependencyMode=$DependencyMode; minimumReportedSeverity=$MinimumReportedSeverity; recurse=(-not $NoRecurse); limits=[pscustomobject]@{ maxFileCount=$MaxFileCount; maxFileBytes=$MaxFileBytes; maxDecodedBytes=$MaxDecodedBytes; maxDecodeDepth=$MaxDecodeDepth } }
        timing = [pscustomobject][ordered]@{ startedUtc=$script:AnalysisStarted.ToString('o'); finishedUtc=$finished.ToString('o'); durationMs=[int]($finished-$script:AnalysisStarted).TotalMilliseconds }
        environment = [pscustomobject][ordered]@{ powerShellVersion=$PSVersionTable.PSVersion.ToString(); edition=[string]$PSVersionTable.PSEdition; platform=[Environment]::OSVersion.VersionString; processArchitecture=$processArchitecture }
        coverage = $script:Engines.ToArray()
        files = $script:Files.ToArray()
        capabilities = $capabilities
        decodedArtifacts = @($script:DecodedArtifacts | Sort-Object sourceFile, sourceLine, depth, sha256)
        findings = $reportedFindings
        testPlan = @(Get-PSCPTestPlan -Capabilities $capabilities)
        skippedPaths = $script:SkippedPaths.ToArray()
        analysisErrors = @($script:AnalysisErrors | ForEach-Object { ConvertTo-PSCPSafeText -Text $_ -MaximumLength 800 })
        limitations = @(
            'Static analysis cannot prove runtime safety, intent, authorization, remote content, environment state, permissions, race behaviour, or all data flows.',
            'Target scripts, modules, manifests, and tests were parsed/read only; none were imported, dot-sourced, invoked, or executed.',
            'Command resolution is intentionally disabled because discovery can auto-import modules and run initialization code.',
            'Malware assessment reports indicators, not a clean bill of health or a definitive malware classification.',
            'Bounded decoders handle literal Base64 and gzip/deflate content; encrypted, custom-packed, runtime-built, or oversized payloads require an isolated specialist workflow.'
        )
    }
}

$exitCode = 4
try {
    if (-not $ToolCachePath) {
        $localAppData = [Environment]::GetFolderPath([Environment+SpecialFolder]::LocalApplicationData)
        if ([string]::IsNullOrWhiteSpace($localAppData)) { $localAppData = Join-Path ([IO.Path]::GetTempPath()) 'ZiAAS' }
        $ToolCachePath = Join-Path $localAppData 'ZiAAS\PSCP\Modules'
    }

    $targetFiles = @(Resolve-PSCPTargetFiles -InputPaths $Path -Recurse (-not $NoRecurse) -Limit $MaxFileCount)
    if ($targetFiles.Count -eq 0) { throw 'No .ps1, .psm1, or .psd1 files were found in the requested paths.' }

    $customStarted = [Diagnostics.Stopwatch]::StartNew()
    $customFailed = $false
    foreach ($target in $targetFiles) {
        $relative = Get-PSCPRelativePath -BasePath (Get-Location).ProviderPath -TargetPath $target.FullName
        if ($target.Length -gt $MaxFileBytes) {
            $customFailed = $true
            $message = "File exceeds MaxFileBytes: $relative ($($target.Length) bytes; limit $MaxFileBytes)."
            $null = $script:AnalysisErrors.Add($message)
            $null = $script:SkippedPaths.Add([pscustomobject]@{ path=$relative; reason='File size limit exceeded'; error='' })
            continue
        }
        try {
            $textInfo = Get-PSCPTextInfo -LiteralPath $target.FullName
            $fileHash = Get-PSCPSha256Bytes -Bytes $textInfo.bytes
            $authenticode = Get-PSCPAuthenticodeInfo -LiteralPath $target.FullName
            $context = [pscustomobject][ordered]@{ fullPath=$target.FullName; relativePath=$relative; sha256=$fileHash; sizeBytes=[long]$target.Length; extension=$target.Extension.ToLowerInvariant(); encoding=$textInfo.encoding; authenticode=$authenticode }
            $tokens = $null
            $parseErrors = $null
            $ast = [System.Management.Automation.Language.Parser]::ParseInput($textInfo.text, $target.FullName, [ref]$tokens, [ref]$parseErrors)
            foreach ($parseError in @($parseErrors)) {
                Add-PSCPFinding -RuleId ('PSCP.PARSER.' + $parseError.ErrorId) -Engine 'PowerShell.Parser' -Category 'Syntax' -Severity 'Error' -Confidence 'High' -Blocking $true -File $relative -FileHash $fileHash -Line $parseError.Extent.StartLineNumber -Column $parseError.Extent.StartColumnNumber -EndLine $parseError.Extent.EndLineNumber -EndColumn $parseError.Extent.EndColumnNumber -Message $parseError.Message -Consequence 'The script cannot be parsed reliably and may fail before or during execution.' -Remediation 'Correct the syntax error and rerun all static analysis before testing.' -Evidence $parseError.Extent.Text -Tags @('parser', 'syntax')
            }
            $commandAsts = @($ast.FindAll({ param($node) $node -is [System.Management.Automation.Language.CommandAst] }, $true))
            $functionRecords = @(Get-PSCPFunctionRecords -Ast $ast)
            $localFunctions = @($functionRecords | ForEach-Object { $_.name })
            $dependencyInventory = Get-PSCPDependencyInventory -Ast $ast -CommandAsts $commandAsts -LocalFunctions $localFunctions
            $codeWithoutComments = Get-PSCPCodeWithoutComments -Raw $textInfo.text -Tokens $tokens
            $taintMap = Get-PSCPTaintMap -Ast $ast
            Invoke-PSCPFileIntegrityChecks -FileContext $context -TextInfo $textInfo
            Invoke-PSCPQualityAndSafetyChecks -FileContext $context -Ast $ast -Tokens $tokens -CommandAsts $commandAsts -FunctionRecords $functionRecords -LocalFunctions $localFunctions -CodeWithoutComments $codeWithoutComments
            Invoke-PSCPSecurityChecks -FileContext $context -Ast $ast -CommandAsts $commandAsts -TaintMap $taintMap
            Invoke-PSCPSecretChecks -FileContext $context -Ast $ast -Raw $textInfo.text
            Invoke-PSCPMalwareIndicatorChecks -FileContext $context -Ast $ast -CommandAsts $commandAsts
            Invoke-PSCPObfuscationChecks -FileContext $context -Ast $ast -CodeWithoutComments $codeWithoutComments -EnableDecoding ($AnalysisProfile -eq 'Maximum') -MaximumBytes $MaxDecodedBytes -MaximumDepth $MaxDecodeDepth
            $commandRecords = @($commandAsts | ForEach-Object { $commandName=Get-PSCPCommandName -CommandAst $_; $displayName=if ($commandName) { $commandName } else { '<dynamic>' }; [pscustomobject][ordered]@{ name=$displayName; line=$_.Extent.StartLineNumber; scope=Get-PSCPScopeName -Ast $_ } } | Sort-Object line, name)
            $fileRecord = [pscustomobject][ordered]@{
                fullPath = $target.FullName
                relativePath = $relative
                sha256 = $fileHash
                sizeBytes = [long]$target.Length
                extension = $target.Extension.ToLowerInvariant()
                encoding = $textInfo.encoding
                authenticode = $authenticode
                parser = [pscustomobject][ordered]@{ success=(@($parseErrors).Count -eq 0); errorCount=@($parseErrors).Count; tokenCount=@($tokens).Count }
                statistics = [pscustomobject][ordered]@{ lines=(@($textInfo.text -split '\r?\n')).Count; commands=$commandAsts.Count; functions=$functionRecords.Count; parameters=@($ast.FindAll({param($node) $node -is [System.Management.Automation.Language.ParameterAst]},$true)).Count }
                dependencies = $dependencyInventory
                functions = $functionRecords
                commands = $commandRecords
            }
            $null = $script:Files.Add($fileRecord)
        }
        catch {
            $customFailed = $true
            $null = $script:AnalysisErrors.Add("Custom analysis failed for '$relative': $($_.Exception.Message)")
            $null = $script:SkippedPaths.Add([pscustomobject]@{ path=$relative; reason='Analysis failed'; error=(ConvertTo-PSCPSafeText -Text $_.Exception.Message -MaximumLength 600) })
        }
    }
    $customStarted.Stop()
    Add-PSCPEngine -Name 'PowerShell.Parser+PSCP.Custom' -Status $(if ($customFailed) { 'failed' } else { 'completed' }) -Required $true -Version $PSVersionTable.PSVersion.ToString() -Message $(if ($customFailed) { 'One or more target files could not be analyzed completely.' } else { 'Parser and bundled static rules completed without executing target code.' }) -DurationMs ([int]$customStarted.ElapsedMilliseconds) -Details ([pscustomobject]@{ filesRequested=$targetFiles.Count; filesAnalyzed=$script:Files.Count; decodedArtifacts=$script:DecodedArtifacts.Count })

    $pssaInfo = $null
    try {
        $pssaInfo = Resolve-PSCPPssaModule -RequiredVersion $PSScriptAnalyzerVersion -CachePath ([IO.Path]::GetFullPath($ToolCachePath)) -Mode $DependencyMode
        Add-PSCPEngine -Name 'Dependency:PSScriptAnalyzer' -Status 'completed' -Required $true -Version $pssaInfo.module.Version.ToString() -Message 'Pinned PSGallery dependency loaded by exact manifest path after identity and signature validation.' -DurationMs $pssaInfo.durationMs -Details ([pscustomobject]@{ manifestPath=$pssaInfo.manifestPath; manifestSha256=$pssaInfo.manifestHash; signaturesChecked=$pssaInfo.signaturesChecked })
    }
    catch {
        $null = $script:AnalysisErrors.Add("PSScriptAnalyzer dependency unavailable: $($_.Exception.Message)")
        Add-PSCPEngine -Name 'Dependency:PSScriptAnalyzer' -Status 'failed' -Required $true -Version $PSScriptAnalyzerVersion -Message $_.Exception.Message
        Add-PSCPEngine -Name 'PSScriptAnalyzer' -Status 'unavailable' -Required $true -Version $PSScriptAnalyzerVersion -Message 'The required pinned dependency could not be loaded, so Microsoft rule coverage is unavailable.'
    }
    if ($pssaInfo -and $script:Files.Count -gt 0) {
        Invoke-PSCPPssaAnalysis -FileContexts $script:Files.ToArray() -ModuleInfo $pssaInfo -AnalysisProfile $AnalysisProfile
    }

    $requiredFailures = @($script:Engines | Where-Object { $_.required -and $_.status -ne 'completed' }).Count
    $blocking = @($script:Findings | Where-Object { $_.blocking -and -not $_.suppressed }).Count
    $warnings = @($script:Findings | Where-Object { $_.severity -eq 'Warning' -and -not $_.suppressed }).Count
    $analysisComplete = ($requiredFailures -eq 0 -and $script:SkippedPaths.Count -eq 0 -and $script:Files.Count -eq $targetFiles.Count)
    if ($blocking -gt 0) { $verdict='BLOCK'; $exitCode=2 }
    elseif (-not $analysisComplete) { $verdict='INCOMPLETE'; $exitCode=3 }
    elseif ($warnings -gt 0) { $verdict='REVIEW'; $exitCode=1 }
    else { $verdict='PASS_STATIC'; $exitCode=0 }
    $result = Get-PSCPResult -Verdict $verdict -ExitCode $exitCode -AnalysisComplete $analysisComplete -MinimumReportedSeverity $MinimumSeverity
    Write-PSCPResult -Result $result -Format $OutputFormat -LiteralOutputPath $OutputPath
}
catch {
    $null = $script:AnalysisErrors.Add($_.Exception.Message)
    Add-PSCPEngine -Name 'PSCP.Orchestrator' -Status 'failed' -Required $true -Version $script:PSCPVersion -Message $_.Exception.Message
    $result = Get-PSCPResult -Verdict 'FATAL' -ExitCode 4 -AnalysisComplete $false -MinimumReportedSeverity $MinimumSeverity
    Write-PSCPResult -Result $result -Format $OutputFormat -LiteralOutputPath $OutputPath
    $exitCode = 4
}
finally {
    if (-not $NoExit) { exit $exitCode }
}
