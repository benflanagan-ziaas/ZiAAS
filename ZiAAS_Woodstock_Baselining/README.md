# ZiAAS Woodstock Baselining

MSP deployment tooling for clean Office, Adobe Reader/Acrobat, and LEAP baselining.

## Recommended Invocation

The original root URL is preserved and now launches this foldered app:

```powershell
$u='https://raw.githubusercontent.com/benflanagan-ziaas/ZiAAS/refs/heads/main/ZiAAS_Woodstock_Baselining.ps1'
$p="$env:ProgramData\ZiAAS_Woodstock_Baselining.ps1"
Invoke-WebRequest $u -OutFile $p -UseBasicParsing
powershell.exe -NoProfile -ExecutionPolicy Bypass -File $p
```

For engineer-led use from a batch file, use:

```cmd
Run-ZiAAS_Woodstock_Baselining.cmd
```

The batch launcher is deliberately plain and auditable: it downloads the root
entrypoint to `ProgramData`, verifies its SHA-256 hash, then runs it locally
with `RemoteSigned`. It does not use encoded PowerShell, hidden execution,
`Invoke-Expression`, or in-memory script execution.

## Common Unattended Examples

Full Office + Adobe Reader + LEAP flow:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File $p -InstallMode All -AdobeProduct Reader -Unattended
```

Office only:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File $p -InstallMode Office -Unattended
```

Adobe Reader only:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File $p -InstallMode Adobe -AdobeProduct Reader -Unattended
```

Acrobat Pro requires a licensed enterprise installer source and silent arguments before the run starts.
Do not rely on an already-installed Acrobat Pro copy; the Adobe cleanup phase removes existing Reader/Acrobat first.

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File $p -InstallMode Adobe -AdobeProduct AcrobatPro -AdobeAcrobatProInstallerPath C:\Installers\AcrobatPro.exe -AdobeAcrobatProInstallArgumentLine '/sAll /rs /msi /qn EULA_ACCEPT=YES REBOOT=ReallySuppress LANG_LIST=en_GB' -Unattended
```

## Runtime Guarantees

- Office installs as Microsoft 365 Apps for enterprise, x64, en-GB, Semi-Annual Enterprise channel.
- Adobe Reader installs as the 64-bit MUI package with `LANG_LIST=en_GB`.
- Adobe New Acrobat is disabled with enterprise FeatureLockDown policy.
- LEAP is removed first and installed last so Office/Adobe add-ins can bind after both applications are present.
- Component logs, summary reports, and JSON reports are written under the working root.
