<#
    status.ps1
    One-shot summary: is the watchdog alive, is Claude running, and the most
    recent log lines.
#>

$Root       = Split-Path -Parent $MyInvocation.MyCommand.Definition
$LogDir     = Join-Path $env:LOCALAPPDATA 'ClaudeWatchdog\logs'
$LogFile    = Join-Path $LogDir 'watchdog.log'
$StatusFile = Join-Path $LogDir 'status.json'
$PauseFile  = Join-Path $Root 'PAUSE.txt'
$StartupDir = Join-Path $env:APPDATA 'Microsoft\Windows\Start Menu\Programs\Startup'
$Launcher   = Join-Path $StartupDir 'claude-watchdog.vbs'

# Same detection rule the watchdog uses, so this panel never contradicts it.
. (Join-Path $Root 'common.ps1')

Write-Host ''
Write-Host '=== CLAUDE WATCHDOG STATUS ===' -ForegroundColor Cyan
Write-Host ''

$running = @(Get-CimInstance Win32_Process -Filter "Name='powershell.exe' OR Name='pwsh.exe'" -ErrorAction SilentlyContinue |
             Where-Object { [string]$_.CommandLine -match 'claude-watchdog\.ps1' -and [string]$_.CommandLine -notmatch '-Once' })

if ($running.Count -gt 0) {
    Write-Host ("Watchdog:     RUNNING (PID {0})" -f ($running[0].ProcessId)) -ForegroundColor Green
} else {
    Write-Host 'Watchdog:     STOPPED' -ForegroundColor Red
    Write-Host '              -> run install.bat to start it'
}

if (Test-Path -LiteralPath $Launcher) {
    Write-Host 'Autostart:    installed in the Windows Startup folder' -ForegroundColor Green
} else {
    Write-Host 'Autostart:    NOT installed' -ForegroundColor Red
}

$target    = Get-ClaudeTarget
$principal = @(Get-ClaudeDesktopProcess -Target $target)
if ($principal.Count -gt 0) {
    Write-Host ("Claude app:   RUNNING (version {0})" -f $target.Version) -ForegroundColor Green
} elseif ($target.Source -eq 'not-found') {
    Write-Host 'Claude app:   NOT INSTALLED (or not detected)' -ForegroundColor Red
} else {
    Write-Host 'Claude app:   NOT RUNNING' -ForegroundColor Yellow
}

if (Test-Path -LiteralPath $PauseFile) {
    $until = (Get-Content -LiteralPath $PauseFile -Raw)
    if ($until) { $until = $until.Trim() }
    if (-not $until) { $until = 'indefinitely' }
    Write-Host ("Pause:        ACTIVE until {0}" -f $until) -ForegroundColor Yellow
}

if (Test-Path -LiteralPath $StatusFile) {
    try {
        $st = Get-Content -LiteralPath $StatusFile -Raw | ConvertFrom-Json
        Write-Host ''
        Write-Host ("Last check:   {0}  (state: {1})" -f $st.updated, $st.state)
        Write-Host ("Checks: {0}   Relaunches: {1}" -f $st.checks, $st.relaunches)
        if ($running.Count -gt 0 -and (Test-WatchdogStale -Status $st)) {
            Write-Host ''
            Write-Host 'WARNING: the watchdog is running but has not checked in when expected.' -ForegroundColor Red
            Write-Host '         If the PC was not just woken from sleep, it may be stuck.' -ForegroundColor Red
            Write-Host '         Run install.bat to restart it.' -ForegroundColor Red
        }
    } catch { }
}

if (Test-Path -LiteralPath $LogFile) {
    Write-Host ''
    Write-Host '--- Last 20 log lines ---' -ForegroundColor Cyan
    Get-Content -LiteralPath $LogFile -Tail 20 -Encoding UTF8 | ForEach-Object { Write-Host $_ }
} else {
    Write-Host ''
    Write-Host 'No log yet.' -ForegroundColor Yellow
}

Write-Host ''
Write-Host ("Full log: {0}" -f $LogFile) -ForegroundColor DarkGray
Write-Host ''
