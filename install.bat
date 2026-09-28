@echo off
title Install Claude Watchdog
rem Double-clicking a .bat inside a ZIP makes Windows extract only that one
rem file to a temp folder, so the rest of the program is missing. Explain it
rem in plain words instead of failing with a cryptic PowerShell error.
if not exist "%~dp0install.ps1" (
    echo.
    echo The ZIP file has not been extracted yet.
    echo.
    echo  1. Close this window.
    echo  2. Right-click the downloaded ZIP and choose "Extract All...".
    echo  3. Open the extracted folder and double-click install.bat there.
    echo.
    pause
    exit /b 1
)
rem Output is also saved to _last-run.log so errors can be copied or shared.
set "LOG=%~dp0_last-run.log"
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0install.ps1" > "%LOG%" 2>&1
set "RC=%ERRORLEVEL%"
type "%LOG%"
if not "%RC%"=="0" (
    echo.
    echo Something went wrong. Full output saved to: %LOG%
)
echo.
pause
