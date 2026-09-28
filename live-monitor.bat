@echo off
title Claude Watchdog - live
mode con: cols=110 lines=40
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0monitor.ps1"
echo.
pause
