# ZiAAS Woodstock Baselining

PowerShell-first MSP tool for baselining Office, Adobe Reader/Acrobat Pro, and LEAP on Windows client machines.

## What it does

The orchestrator validates and stages all selected reinstall media first, removes selected products in a safe order, performs allowlisted cleanup, waits for installer state to settle, then reinstalls the selected products in dependency order:

1. Download and verify all required installers and the Office payload before cleanup
2. LEAP uninstall and cleanup, if selected
3. Adobe Reader/Acrobat uninstall and cleanup, if selected
4. Office uninstall and cleanup, if selected
5. Wait 60 seconds by default
6. Install Microsoft 365 Apps for enterprise, 64-bit, en-GB, requesting Semi-Annual Enterprise
7. Install Adobe Reader 64-bit MUI with `LANG_LIST=en_GB`, or install a supplied Acrobat Pro package
8. Disable New Acrobat and enforce Reader-only reduced mode when Reader is selected
9. Wait 60 seconds by default before LEAP
10. Install LEAP last so Office and Adobe add-ins can bind correctly
11. Write logs, JSON/text reports, and an optional sanitized support bundle

Microsoft is unifying Semi-Annual Enterprise Channel into Monthly Enterprise Channel from Version 2606 in July 2026. The tool still requests `Channel=SemiAnnual`, verifies the exact enterprise audience, and only accepts Monthly Enterprise reporting at or above Microsoft's documented transition build.

Adobe officially maps International English `en_GB` to its `en_US` English resource transform. Verification therefore proves the 64-bit MUI installer request, the mapped English resources, the Reader-only machine policy, and the disabled New Acrobat policy.

## Common commands

Interactive run:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\ZiAAS_Woodstock_Baselining.ps1
```

Full unattended Reader deployment:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\ZiAAS_Woodstock_Baselining.ps1 -InstallMode All -AdobeProduct Reader -Unattended
```

Preflight only:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\ZiAAS_Woodstock_Baselining.ps1 -PreflightOnly -InstallMode All -AdobeProduct Reader
```

Simulation:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\ZiAAS_Woodstock_Baselining.ps1 -Simulation -InstallMode All -AdobeProduct Reader -WorkingRoot .\sandbox-test
```

Show built-in guide:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\ZiAAS_Woodstock_Baselining.ps1 -ShowGuide
```

## Branded GUI example

The production deployment path remains PowerShell-first for RMM, Intune, raw URL,
and unattended use. A non-destructive WPF example is included to demonstrate the
operator experience that can sit in front of the orchestrator:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\examples\ZiAAS_Woodstock_Baselining.GuiExample.ps1
```

The example shows product selection, Reader/Acrobat Pro choice, the enforced
cleanup and install order, preflight gating, progress states, and the final
operator hand-off. It does not change the machine. A production GUI should invoke
the existing orchestrator as a child process, stream its structured reports, and
keep the same fail-fast, logging, exit-code, and unattended behaviour.

## Acrobat Pro rule

Reader is fully autonomous. Acrobat Pro is not. Acrobat Pro deployments require a licensed enterprise installer path or URL and silent install arguments before cleanup begins. Include `LANG_LIST=en_GB` unless the package is already pre-configured and `-AllowAcrobatProLanguageNotVerified` is intentionally supplied.

## Safety model

- Default behaviour is guided fail-fast.
- `-PreflightOnly` validates requirements without changing the machine.
- A real run stages and signature-checks all selected reinstall media before the first uninstall.
- Blocking Office, Adobe, and LEAP apps stop the run unless `-ForceCloseApps` is supplied.
- Cleanup paths are allowlisted.
- LEAP profile cleanup preserves `AppData\Roaming\LEAP Accounting`.
- Raw URL bootstrap downloads a manifest first, then verifies SHA-256 hashes for the core script and component package before execution.
- Component exit codes are preserved by the orchestrator, including exit `100` for a pre-cleanup staging failure.

## Build and release

Canonical source lives under `src`. Generated artifacts live under `..\outputs`.

Build generated artifacts:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\build\Build-ZiAAS_Woodstock_Baselining.ps1
```

Run release checks:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\build\Test-ZiAASRelease.ps1
```

Before publishing from a Git worktree, enforce publish checks:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\build\Test-ZiAASRelease.ps1 -ForPublish
```
