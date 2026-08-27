# PSCP 4.0

PSCP is an agent-first, static-only PowerShell analyzer. It gives a direct `PASS_STATIC`, `REVIEW`, `BLOCK`, `INCOMPLETE`, or `FATAL` answer; structured findings with evidence, consequence, and remediation; explicit coverage failures; and a capability-driven sandbox test plan.

It never imports, dot-sources, invokes, or tests the target. `PASS_STATIC` means the required static engines completed and found no blocking errors or warnings. It does not mean “safe” or “malware-free”; it means the script is ready for isolated runtime testing.

## Quick start

```powershell
.\Invoke-PSCP.ps1 -Path .\MyScript.ps1 -Profile Maximum -OutputPath .\pscp-report.json
$LASTEXITCODE
```

For an already provisioned or offline machine:

```powershell
.\Invoke-PSCP.ps1 -Path . -Profile Maximum -DependencyMode Require
.\Invoke-PSCP.ps1 -Path . -Profile Maximum -DependencyMode Offline
```

`-Profile` is an alias of `-AnalysisProfile`. JSON is the default output and is the canonical file format written by `-OutputPath`. `-OutputFormat Text` gives a short human summary; `Object` is useful when calling the analyzer from PowerShell with `-NoExit`.

## Dependency policy

The only runtime dependency is Microsoft `PSScriptAnalyzer`, pinned by default to `1.25.0`.

In `AutoInstall` mode PSCP:

1. accepts only the repository named `PSGallery` with the expected HTTPS API endpoint;
2. requests the exact package version with `Find-Module`;
3. downloads it with `Save-Module` into a private per-user tool cache;
4. verifies the returned package name and version;
5. on Windows, requires every `.psd1`, `.psm1`, and `.dll` in the module to have a valid Authenticode signature;
6. imports the exact manifest path, rechecks module identity/version, and records the manifest hash.

It does not use `AllowClobber`, `SkipPublisherCheck`, repository trust changes, unpinned installs, GitHub binaries, Defender, Gitleaks, InjectionHunter, or Revoke-Obfuscation. The latter tools either do not produce the required deterministic source diagnostics, are not PSGallery-first, or are legacy comparison engines. Their useful ideas are represented by bounded custom AST/data-flow rules instead.

## What it analyzes

- PowerShell parser errors, token metadata, encoding, invisible/bidirectional characters, line endings, file hashes, and Authenticode status.
- PSScriptAnalyzer default rules plus security, function, PSGallery, cmdlet-design, scripting-style, formatting, Windows PowerShell 5.1, and PowerShell 7 compatibility passes according to profile.
- Injection sinks and simple taint propagation from parameters, environment/input, files, network responses, and decoded content.
- `Invoke-Expression`, dynamic command/member access, dynamic `Add-Type`, native shell interpolation, `Start-Process` path/argument construction, mutating REST calls, and download-to-execute pipelines.
- State-changing commands and whether the same scope both supports and actually guards the operation with `ShouldProcess`.
- Hard-coded secret patterns. Reports contain only type, length, and a short value hash—not the secret.
- Persistence, Defender/security-control changes, credential-hive export, LSASS dumping, suspicious Windows dual-use binaries, and high-impact destructive operations.
- Literal Base64, recursive Base64, UTF-8/UTF-16 decoded text, embedded PE headers, and bounded gzip/deflate expansion. No decoded content is executed.
- Function complexity, nesting, size, parameters, output shape, non-local state writes, dependencies, native commands, and operational capabilities.
- A test plan derived from actual capabilities such as network, filesystem, registry, services, processes, remote mutation, persistence, credentials, and destructive changes.

## Profiles

| Profile | Coverage |
|---|---|
| `Quick` | Parser, core custom rules, secrets, injection/malware indicators, default PSScriptAnalyzer |
| `Standard` | Quick plus PSScriptAnalyzer security and script-function presets |
| `Maximum` | Standard plus PSGallery, cmdlet design, scripting style, code formatting, PS 5.1/7 compatibility, and bounded payload decoding |

`Maximum` is the default because this tool is intended as the final static gate before testing.

## Verdicts and exit codes

| Exit | Verdict | Meaning |
|---:|---|---|
| 0 | `PASS_STATIC` | All required engines completed; no unsuppressed blocking findings or warnings |
| 1 | `REVIEW` | Analysis completed; one or more warnings require review |
| 2 | `BLOCK` | At least one unsuppressed blocking error/critical finding exists |
| 3 | `INCOMPLETE` | A dependency, required engine, file, or configured coverage step failed |
| 4 | `FATAL` | Invalid request or analyzer orchestration failure |

`BLOCK` takes precedence over `INCOMPLETE` so an agent cannot overlook a known dangerous finding. Always check `analysisComplete` as well.

## Agent contract

The most important properties are:

- `verdict`, `exitCode`, `analysisComplete`, `safeToBeginSandboxTesting`
- `summary.directAnswer`, `summary.recommendedAction`
- `coverage[]` with required/status/version/details
- `malwareAssessment` (`NoStaticIndicatorsDetected`, `SuspiciousIndicators`, `HighRiskIndicators`, or `UnknownIncomplete`)
- `findings[]` with stable fingerprint, exact location, severity, confidence, evidence, consequence, remediation, CWE, ATT&CK, and suggested corrections
- `decodedArtifacts[]` with transform, hash, type, preview, commands, URLs, and parser results
- `capabilities[]` and `testPlan[]`
- `tool.targetWasExecuted` and `tool.testsWereExecuted`, which remain `false`

The full contract is in [`schema/pscp-report.schema.json`](schema/pscp-report.schema.json).

## Validation suite

No Pester dependency is required:

```powershell
.\tests\Test-PSCP.ps1
```

The suite validates both installed PowerShell hosts, the pinned dependency, valid JSON, deterministic fingerprints, a clean fixture, dangerous static indicators, decoded PowerShell, malformed source, secret redaction, fail-closed offline dependency handling, and a sentinel proving target code was not executed.

## Boundaries

Static analysis cannot establish authorization or intent, inspect runtime-only/decrypted values, prove every data flow, contact remote services safely, reproduce permissions and race conditions, or guarantee rollback. After `PASS_STATIC`, follow the emitted test plan in a disposable least-privilege sandbox and begin with `-WhatIf` wherever supported.
