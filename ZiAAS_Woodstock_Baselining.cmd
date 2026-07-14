@echo off
setlocal

net session >nul 2>&1
if %errorlevel% neq 0 (
    echo ZiAAS Woodstock Baselining must be run as Administrator.
    echo Right-click this file and choose Run as administrator.
    pause
    exit /b 1
)

set "SCRIPT_DIR=%~dp0"
set "SCRIPT=%SCRIPT_DIR%ZiAAS_Woodstock_Baselining.ps1"

if not exist "%SCRIPT%" (
    echo Script not found: %SCRIPT%
    pause
    exit /b 1
)

powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%SCRIPT%" %*
set "EXITCODE=%errorlevel%"

echo.
echo ZiAAS Woodstock Baselining finished with exit code %EXITCODE%.
pause
exit /b %EXITCODE%
