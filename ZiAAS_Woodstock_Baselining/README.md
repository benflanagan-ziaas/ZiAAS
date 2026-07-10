# ZiAAS Woodstock Baselining

PowerShell-first MSP tool for baselining Office, Adobe Reader/Acrobat Pro, and LEAP on Windows client machines.

## What it does

The orchestrator removes selected products in a safe order, performs allowlisted cleanup, waits for installer state to settle, then reinstalls the selected products in dependency order:

1. LEAP uninstall and cleanup, if selected
2. Adobe Reader/Acrobat uninstall and cleanup, if selected
3. Office uninstall and cleanup, if selected
4. Wait 60 seconds by default
5. Install Microsoft 365 Apps for enterprise, 64-bit, en-GB, Semi-Annual Enterprise
6. Install Adobe Reader 64-bit MUI with `LANG_LIST=en_GB`, or install a supplied Acrobat Pro package
7. Disable New Acrobat policy
8. Wait 60 seconds by default before LEAP
9. Install LEAP last so Office and Adobe add-ins can bind correctly
10. Write logs, JSON/text reports, and an optional support bundle

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

## Acrobat Pro rule

Reader is fully autonomous. Acrobat Pro is not. Acrobat Pro deployments require a licensed enterprise installer path or URL and silent install arguments before cleanup begins. Include `LANG_LIST=en_GB` unless the package is already pre-configured and `-AllowAcrobatProLanguageNotVerified` is intentionally supplied.

## Safety model

- Default behaviour is guided fail-fast.
- `-PreflightOnly` validates requirements without changing the machine.
- Blocking Office, Adobe, and LEAP apps stop the run unless `-ForceCloseApps` is supplied.
- Cleanup paths are allowlisted.
- LEAP profile cleanup preserves `AppData\Roaming\LEAP Accounting`.
- Raw URL bootstrap downloads a manifest first, then verifies SHA-256 hashes for the core script and component package before execution.

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
