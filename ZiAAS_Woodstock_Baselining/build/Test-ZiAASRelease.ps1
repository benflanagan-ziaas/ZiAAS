#requires -version 5.1
[CmdletBinding()]
param(
    [string]$ProjectRoot,
    [string]$OutputRoot,
    [switch]$ForPublish,
    [switch]$SkipGitCheck
)

Set-StrictMode -Version 2.0
$ErrorActionPreference = "Stop"

if ([string]::IsNullOrWhiteSpace($ProjectRoot)) {
    $ProjectRoot = Split-Path -Parent $PSScriptRoot
}
if ([string]::IsNullOrWhiteSpace($OutputRoot)) {
    $OutputRoot = Join-Path (Split-Path -Parent (Split-Path -Parent $PSScriptRoot)) "outputs"
}

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

function Write-Check {
    param(
        [Parameter(Mandatory = $true)][string]$Message,
        [ValidateSet("Pass", "Info")][string]$Status = "Pass"
    )

    $prefix = if ($Status -eq "Pass") { "[PASS]" } else { "[INFO]" }
    Write-Host "$prefix $Message"
}

function Assert-Condition {
    param(
        [Parameter(Mandatory = $true)][bool]$Condition,
        [Parameter(Mandatory = $true)][string]$Message
    )

    if (-not $Condition) {
        throw $Message
    }
}

function Assert-FileHashMatches {
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [Parameter(Mandatory = $true)][string]$ExpectedHash,
        [Parameter(Mandatory = $true)][string]$Description
    )

    Assert-Condition -Condition (Test-Path -LiteralPath $Path) -Message "$Description file is missing: $Path"
    $actualHash = (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash
    Assert-Condition -Condition ($actualHash -ieq $ExpectedHash) -Message "$Description hash mismatch. Expected $ExpectedHash, got $actualHash."
}

function Get-ManifestArtifact {
    param(
        [Parameter(Mandatory = $true)]$Manifest,
        [Parameter(Mandatory = $true)][string]$Name
    )

    foreach ($artifact in @($Manifest.artifacts)) {
        if ([string]$artifact.name -eq $Name) {
            return $artifact
        }
    }

    throw "Manifest artifact '$Name' is missing."
}

function Test-PowerShellParse {
    param([Parameter(Mandatory = $true)][string[]]$Roots)

    $files = @()
    foreach ($root in $Roots) {
        if (Test-Path -LiteralPath $root) {
            $files += @(Get-ChildItem -LiteralPath $root -Recurse -Filter *.ps1 -File)
        }
    }

    foreach ($file in $files) {
        $tokens = $null
        $errors = $null
        [System.Management.Automation.Language.Parser]::ParseFile($file.FullName, [ref]$tokens, [ref]$errors) | Out-Null
        if ($errors.Count -gt 0) {
            $messages = @($errors | ForEach-Object { "{0} at line {1}" -f $_.Message, $_.Extent.StartLineNumber })
            throw "PowerShell parse failed for $($file.FullName): $($messages -join '; ')"
        }
    }

    Write-Check "Parsed $($files.Count) PowerShell files."
}

function Test-HighSignalScriptAnalysis {
    $analyzer = Get-Module -ListAvailable PSScriptAnalyzer | Sort-Object Version -Descending | Select-Object -First 1
    if (-not $analyzer) {
        Write-Check "PSScriptAnalyzer is not installed; high-signal analyzer checks were skipped." "Info"
        return
    }

    Import-Module $analyzer.Path -Force -ErrorAction Stop
    $rules = @(
        "PSAvoidAssignmentToAutomaticVariable",
        "PSAvoidUsingInvokeExpression",
        "PSAvoidUsingPlainTextForPassword",
        "PSAvoidUsingConvertToSecureStringWithPlainText",
        "PSAvoidUsingUsernameAndPasswordParams"
    )
    $findings = @(Invoke-ScriptAnalyzer -Path $ProjectRoot -Recurse -IncludeRule $rules)
    if ($findings.Count -gt 0) {
        $details = @($findings | ForEach-Object {
            "{0}:{1} [{2}] {3}" -f $_.ScriptName, $_.Line, $_.RuleName, $_.Message
        })
        throw "High-signal PowerShell static analysis failed: $($details -join '; ')"
    }

    Write-Check "High-signal PowerShell static-analysis rules returned no findings."
}

function Test-DuplicateFunctionDefinitions {
    param([Parameter(Mandatory = $true)][string[]]$Roots)

    $files = @()
    foreach ($root in $Roots) {
        if (Test-Path -LiteralPath $root) {
            $files += @(Get-ChildItem -LiteralPath $root -Recurse -Filter *.ps1 -File)
        }
    }

    foreach ($file in $files) {
        $tokens = $null
        $errors = $null
        $ast = [System.Management.Automation.Language.Parser]::ParseFile($file.FullName, [ref]$tokens, [ref]$errors)
        $functions = @($ast.FindAll({ param($node) $node -is [System.Management.Automation.Language.FunctionDefinitionAst] }, $true))
        $duplicates = @($functions | Group-Object Name | Where-Object { $_.Count -gt 1 })
        if ($duplicates.Count -gt 0) {
            $detail = @($duplicates | ForEach-Object {
                $lines = @($_.Group | ForEach-Object { $_.Extent.StartLineNumber }) -join ", "
                "$($_.Name) at lines $lines"
            }) -join "; "
            throw "Duplicate function definitions found in $($file.FullName): $detail"
        }
    }

    Write-Check "No PowerShell file contains duplicate function definitions."
}

function Test-JsonFiles {
    param([Parameter(Mandatory = $true)][string[]]$Roots)

    $files = @()
    foreach ($root in $Roots) {
        if (Test-Path -LiteralPath $root) {
            $files += @(Get-ChildItem -LiteralPath $root -Recurse -Filter *.json -File)
        }
    }

    foreach ($file in $files) {
        Get-Content -LiteralPath $file.FullName -Raw | ConvertFrom-Json | Out-Null
    }

    Write-Check "Validated $($files.Count) JSON files."
}

function Test-SourceOutputSync {
    $srcRoot = Join-Path $ProjectRoot "src"
    $srcComponents = Join-Path $srcRoot "components"
    $srcConfig = Join-Path $srcRoot "config"
    $outComponents = Join-Path $OutputRoot "components"
    $outConfig = Join-Path $OutputRoot "config"

    $pairs = @(
        @("Core script", (Join-Path $srcRoot "ZiAAS_Woodstock_Baselining.ps1"), (Join-Path $OutputRoot "ZiAAS_Woodstock_Baselining.core.ps1")),
        @("Public entrypoint", (Join-Path $srcRoot "ZiAAS_Woodstock_Baselining.entrypoint.ps1"), (Join-Path $OutputRoot "ZiAAS_Woodstock_Baselining.ps1")),
        @("Trace entrypoint copy", (Join-Path $srcRoot "ZiAAS_Woodstock_Baselining.entrypoint.ps1"), (Join-Path $OutputRoot "ZiAAS_Woodstock_Baselining.entrypoint.ps1")),
        @("Command launcher", (Join-Path $srcRoot "ZiAAS_Woodstock_Baselining.cmd"), (Join-Path $OutputRoot "ZiAAS_Woodstock_Baselining.cmd"))
    )

    foreach ($component in $requiredComponents) {
        $pairs += ,@("Component $component", (Join-Path $srcComponents $component), (Join-Path $outComponents $component))
    }
    if (Test-Path -LiteralPath $srcConfig) {
        foreach ($config in @(Get-ChildItem -LiteralPath $srcConfig -Filter *.json -File)) {
            $pairs += ,@("Config $($config.Name)", $config.FullName, (Join-Path $outConfig $config.Name))
        }
    }

    foreach ($pair in $pairs) {
        $label = $pair[0]
        $source = $pair[1]
        $output = $pair[2]
        Assert-Condition -Condition (Test-Path -LiteralPath $source) -Message "$label source missing: $source"
        Assert-Condition -Condition (Test-Path -LiteralPath $output) -Message "$label output missing: $output"
        $sourceHash = (Get-FileHash -LiteralPath $source -Algorithm SHA256).Hash
        $outputHash = (Get-FileHash -LiteralPath $output -Algorithm SHA256).Hash
        Assert-Condition -Condition ($sourceHash -eq $outputHash) -Message "$label output is stale. Rebuild before release."
    }

    Write-Check "Source tree and generated output files are in sync."
}

function Test-ComponentPackage {
    param([Parameter(Mandatory = $true)]$Manifest)

    $zipArtifact = Get-ManifestArtifact -Manifest $Manifest -Name "componentsZip"
    $zipPath = Join-Path $OutputRoot $zipArtifact.file
    Assert-FileHashMatches -Path $zipPath -ExpectedHash $zipArtifact.sha256 -Description "Component zip"

    $extractRoot = Join-Path ([System.IO.Path]::GetTempPath()) ("ZiAAS-release-check-{0}" -f ([guid]::NewGuid().ToString("N")))
    New-Item -Path $extractRoot -ItemType Directory -Force | Out-Null
    try {
        Expand-Archive -LiteralPath $zipPath -DestinationPath $extractRoot -Force
        foreach ($component in $requiredComponents) {
            Assert-Condition -Condition (Test-Path -LiteralPath (Join-Path $extractRoot $component)) -Message "Component zip does not contain $component."
        }
    }
    finally {
        if (Test-Path -LiteralPath $extractRoot) {
            Remove-Item -LiteralPath $extractRoot -Recurse -Force
        }
    }

    Write-Check "Component package contains all required component scripts."
}

function Test-Base64Artifact {
    param(
        [Parameter(Mandatory = $true)]$Manifest,
        [Parameter(Mandatory = $true)][string]$ArtifactName
    )

    $artifact = Get-ManifestArtifact -Manifest $Manifest -Name $ArtifactName
    $b64Path = Join-Path $OutputRoot $artifact.file
    Assert-FileHashMatches -Path $b64Path -ExpectedHash $artifact.sha256 -Description "$ArtifactName artifact"

    Assert-Condition -Condition ($null -ne $artifact.PSObject.Properties["partCount"]) -Message "$ArtifactName manifest entry is missing partCount."
    $expectedPartCount = [int]$artifact.partCount
    Assert-Condition -Condition ($expectedPartCount -gt 0) -Message "$ArtifactName has invalid partCount $expectedPartCount."

    $parts = @(Get-ChildItem -LiteralPath $OutputRoot -Filter "$($artifact.file).part*" -File | Sort-Object Name)
    Assert-Condition -Condition ($parts.Count -eq $expectedPartCount) -Message "$ArtifactName part count mismatch. Manifest says $expectedPartCount; found $($parts.Count)."

    $rebuilt = ""
    foreach ($part in $parts) {
        $rebuilt += (Get-Content -LiteralPath $part.FullName -Raw).Trim()
    }
    $expected = (Get-Content -LiteralPath $b64Path -Raw).Trim()
    Assert-Condition -Condition ($rebuilt -ceq $expected) -Message "$ArtifactName base64 parts do not reconstruct the artifact exactly."

    Write-Check "$ArtifactName base64 parts reconstruct exactly."
}

function Test-Manifest {
    $manifestPath = Join-Path $OutputRoot "app.manifest.json"
    Assert-Condition -Condition (Test-Path -LiteralPath $manifestPath) -Message "Manifest missing: $manifestPath"
    $manifest = Get-Content -LiteralPath $manifestPath -Raw | ConvertFrom-Json

    foreach ($name in @("coreScript", "coreBase64", "componentsZip", "componentsBase64", "entrypoint")) {
        $artifact = Get-ManifestArtifact -Manifest $manifest -Name $name
        Assert-FileHashMatches -Path (Join-Path $OutputRoot $artifact.file) -ExpectedHash $artifact.sha256 -Description "Manifest artifact $name"
    }

    $manifestComponents = @($manifest.requiredComponents | ForEach-Object { [string]$_ })
    foreach ($component in $requiredComponents) {
        Assert-Condition -Condition ($manifestComponents -contains $component) -Message "Manifest requiredComponents is missing $component."
    }

    Test-Base64Artifact -Manifest $manifest -ArtifactName "coreBase64"
    Test-Base64Artifact -Manifest $manifest -ArtifactName "componentsBase64"
    Test-ComponentPackage -Manifest $manifest
    Write-Check "Manifest hashes, required components, and artifacts are valid."
}

function Test-GitState {
    if ($SkipGitCheck) {
        Write-Check "Git check skipped by request." "Info"
        return
    }

    $git = Get-Command git -ErrorAction SilentlyContinue
    if ($null -eq $git) {
        if ($ForPublish) {
            throw "Cannot publish because git is not available on PATH."
        }

        Write-Check "Git not available on PATH; publish cleanliness was not checked." "Info"
        return
    }

    $repoRoot = Split-Path -Parent (Split-Path -Parent $ProjectRoot)
    $inside = & $git.Source -C $repoRoot rev-parse --is-inside-work-tree 2>$null
    if ($LASTEXITCODE -ne 0 -or [string]$inside -ne "true") {
        if ($ForPublish) {
            throw "Cannot publish because $repoRoot is not a git worktree."
        }

        Write-Check "$repoRoot is not a git worktree; publish cleanliness was not checked." "Info"
        return
    }

    $status = & $git.Source -C $repoRoot status --porcelain
    if ($ForPublish -and -not [string]::IsNullOrWhiteSpace(($status -join ""))) {
        throw "Cannot publish because the git working tree has uncommitted changes."
    }

    if ([string]::IsNullOrWhiteSpace(($status -join ""))) {
        Write-Check "Git working tree is clean."
    }
    else {
        Write-Check "Git working tree has uncommitted changes; run with -ForPublish to enforce failure." "Info"
    }
}

Assert-Condition -Condition (Test-Path -LiteralPath $ProjectRoot) -Message "Project root not found: $ProjectRoot"
Assert-Condition -Condition (Test-Path -LiteralPath $OutputRoot) -Message "Output root not found: $OutputRoot"

Test-PowerShellParse -Roots @($ProjectRoot, $OutputRoot)
Test-HighSignalScriptAnalysis
Test-DuplicateFunctionDefinitions -Roots @($ProjectRoot, $OutputRoot)
Test-JsonFiles -Roots @($ProjectRoot, $OutputRoot)
Test-SourceOutputSync
Test-Manifest
Test-GitState

Write-Host "ZiAAS Woodstock Baselining release checks passed."
