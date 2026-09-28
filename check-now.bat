@echo off
title Claude Watchdog - check now
rem Output is also saved to _last-run.log so errors can be copied or shared.
set "LOG=%~dp0_last-run.log"
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0claude-watchdog.ps1" -Once > "%LOG%" 2>&1
set "RC=%ERRORLEVEL%"
type "%LOG%"
if not "%RC%"=="0" (
    echo.
    echo Something went wrong. Full output saved to: %LOG%
)
echo.
pause
