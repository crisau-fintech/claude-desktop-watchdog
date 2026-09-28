@echo off
if exist "%LOCALAPPDATA%\ClaudeWatchdog\logs\watchdog.log" (
    start "" notepad.exe "%LOCALAPPDATA%\ClaudeWatchdog\logs\watchdog.log"
) else (
    echo No log yet. Install the watchdog first.
    pause
)
