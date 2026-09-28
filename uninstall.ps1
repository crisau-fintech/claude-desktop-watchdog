<#
    uninstall.ps1
    Removes the watchdog from Windows startup and stops the running instance.
    Project files and logs are left untouched; install.bat reinstalls it.
#>

$ErrorActionPreference = 'Stop'

$StartupDir = Join-Path $env:APPDATA 'Microsoft\Windows\Start Menu\Programs\Startup'
$Launcher   = Join-Path $StartupDir 'claude-watchdog.vbs'

Write-Host ''
Write-Host '=== UNINSTALLING CLAUDE WATCHDOG ===' -ForegroundColor Cyan
Write-Host ''

if (Test-Path -LiteralPath $Launcher) {
    Remove-Item -LiteralPath $Launcher -Force
    Write-Host '1. Startup launcher removed.'
} else {
    Write-Host '1. No Startup launcher was installed.'
}

$stopped = 0
foreach ($p in @(Get-CimInstance Win32_Process -Filter "Name='powershell.exe' OR Name='pwsh.exe' OR Name='wscript.exe'" -ErrorAction SilentlyContinue)) {
    if ($p.ProcessId -eq $PID) { continue }
    $cmd = [string]$p.CommandLine
    if ($cmd -match 'uninstall\.ps1') { continue }
    if ($cmd -match 'claude-watchdog\.ps1' -or $cmd -match 'claude-watchdog\.vbs') {
        try { Stop-Process -Id $p.ProcessId -Force -ErrorAction Stop; $stopped++ } catch { }
    }
}
Write-Host ("2. Watchdog processes stopped: {0}" -f $stopped)

Write-Host ''
Write-Host 'Watchdog uninstalled. Claude will no longer be relaunched automatically.' -ForegroundColor Green
Write-Host ("Logs were kept in: {0}" -f (Join-Path $env:LOCALAPPDATA 'ClaudeWatchdog\logs'))
Write-Host ''
