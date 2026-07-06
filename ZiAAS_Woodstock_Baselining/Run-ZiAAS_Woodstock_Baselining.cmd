@echo off
setlocal EnableExtensions
title ZiAAS Woodstock Baselining Launcher

set "APP_NAME=ZiAAS Woodstock Baselining"
set "SCRIPT_URL=https://raw.githubusercontent.com/benflanagan-ziaas/ZiAAS/refs/heads/main/ZiAAS_Woodstock_Baselining.ps1"
set "EXPECTED_SHA256=1DFB246423C4DD81C3F08AE6B89E22F4E09B2BDA9126DCA0C6B25E00C24E5DAD"
set "WORK_ROOT=%ProgramData%\ZiAAS_Woodstock_Baselining"
set "SCRIPT_PATH=%WORK_ROOT%\ZiAAS_Woodstock_Baselining.ps1"
set "DOWNLOAD_PATH=%SCRIPT_PATH%.download"

echo %APP_NAME%
echo Source: %SCRIPT_URL%
echo Target: %SCRIPT_PATH%
echo.

net session >nul 2>&1
if not "%errorlevel%"=="0" (
    echo This launcher must be run as Administrator.
    echo Right-click this file and choose Run as administrator.
    echo.
    pause
    exit /b 1
)

if not exist "%WORK_ROOT%" (
    mkdir "%WORK_ROOT%"
    if errorlevel 1 (
        echo Could not create working folder: %WORK_ROOT%
        pause
        exit /b 1
    )
)

echo Downloading verified release entrypoint...
powershell.exe -NoLogo -NoProfile -Command "$ErrorActionPreference='Stop'; $ProgressPreference='SilentlyContinue'; [Net.ServicePointManager]::SecurityProtocol=[Net.SecurityProtocolType]::Tls12; Invoke-WebRequest -Uri '%SCRIPT_URL%' -OutFile '%DOWNLOAD_PATH%' -UseBasicParsing -TimeoutSec 120; $hash=(Get-FileHash -Algorithm SHA256 -LiteralPath '%DOWNLOAD_PATH%').Hash; if ($hash -ne '%EXPECTED_SHA256%') { throw ('Downloaded script hash mismatch. Expected %EXPECTED_SHA256%, got ' + $hash) }; Move-Item -LiteralPath '%DOWNLOAD_PATH%' -Destination '%SCRIPT_PATH%' -Force"
if errorlevel 1 (
    echo Download or verification failed.
    echo Nothing has been installed.
    pause
    exit /b 1
)

echo.
echo Starting %APP_NAME%...
powershell.exe -NoLogo -NoProfile -ExecutionPolicy RemoteSigned -File "%SCRIPT_PATH%" %*
set "EXITCODE=%errorlevel%"

echo.
echo %APP_NAME% finished with exit code %EXITCODE%.
if "%EXITCODE%"=="3010" echo A reboot is required to complete one or more changes.
pause
exit /b %EXITCODE%
