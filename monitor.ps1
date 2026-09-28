<#
    monitor.ps1
    Live watchdog dashboard: refreshes every few seconds with the current state
    and the latest log lines. Exit with Ctrl+C.
#>

param([int]$RefreshSeconds = 5)

$Root       = Split-Path -Parent $MyInvocation.MyCommand.Definition
$LogDir     = Join-Path $env:LOCALAPPDATA 'ClaudeWatchdog\logs'
$LogFile    = Join-Path $LogDir 'watchdog.log'
$StatusFile = Join-Path $LogDir 'status.json'
$PauseFile  = Join-Path $Root 'PAUSE.txt'

# Same detection rule the watchdog uses, so this panel never contradicts it.
. (Join-Path $Root 'common.ps1')

function Format-Duration {
    param([TimeSpan]$T)
    if ($T.TotalDays -ge 1) { return ('{0}d {1}h {2}m' -f [int][Math]::Floor($T.TotalDays), $T.Hours, $T.Minutes) }
    if ($T.TotalHours -ge 1) { return ('{0}h {1}m' -f [int][Math]::Floor($T.TotalHours), $T.Minutes) }
    if ($T.TotalMinutes -ge 1) { return ('{0}m {1}s' -f [int][Math]::Floor($T.TotalMinutes), $T.Seconds) }
    return ('{0}s' -f [int]$T.TotalSeconds)
}

function Write-Field {
    param([string]$Label, [string]$Value, [string]$Color = 'Gray')
    Write-Host ('  {0}' -f $Label.PadRight(18)) -NoNewline
    Write-Host $Value -ForegroundColor $Color
}

$target = Get-ClaudeTarget
$lastTargetResolve = Get-Date

while ($true) {
    # Re-resolve every minute so an update while the panel is open is picked up.
    if (((Get-Date) - $lastTargetResolve).TotalSeconds -ge 60) {
        $target = Get-ClaudeTarget
        $lastTargetResolve = Get-Date
    }

    $wd = @(Get-CimInstance Win32_Process -Filter "Name='powershell.exe' OR Name='pwsh.exe'" -ErrorAction SilentlyContinue |
            Where-Object { [string]$_.CommandLine -match 'claude-watchdog\.ps1' -and [string]$_.CommandLine -notmatch '-Once' })

    $principal = @(Get-ClaudeDesktopProcess -Target $target)

    $st = $null
    if (Test-Path -LiteralPath $StatusFile) {
        try { $st = Get-Content -LiteralPath $StatusFile -Raw | ConvertFrom-Json } catch { }
    }

    try { Clear-Host } catch { }
    Write-Host ''
    Write-Host '  ================= CLAUDE WATCHDOG - LIVE =================' -ForegroundColor Cyan
    Write-Host ('  {0}      (Ctrl+C to exit)' -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss')) -ForegroundColor DarkGray
    Write-Host ''

    if ($wd.Count -gt 0) {
        Write-Field 'Watchdog' ('RUNNING  (PID {0})' -f $wd[0].ProcessId) 'Green'
    } else {
        Write-Field 'Watchdog' 'STOPPED  -> run install.bat' 'Red'
    }

    if ($principal.Count -gt 0) {
        Write-Field 'Claude app' ('RUNNING  (version {0})' -f $target.Version) 'Green'
    } else {
        Write-Field 'Claude app' 'NOT RUNNING' 'Yellow'
    }

    if (Test-Path -LiteralPath $PauseFile) {
        $until = (Get-Content -LiteralPath $PauseFile -Raw)
        if ($until) { $until = $until.Trim() }
        if (-not $until) { $until = 'indefinitely' }
        Write-Field 'Pause' ('ACTIVE until {0}' -f $until) 'Yellow'
    }

    if ($st) {
        Write-Host ''
        Write-Field 'Checks' ([string]$st.checks) 'White'
        Write-Field 'Relaunches' ([string]$st.relaunches) $(if ([int]$st.relaunches -gt 0) { 'Yellow' } else { 'White' })
        Write-Field 'Last relaunch' ([string]$st.lastRelaunch) 'White'
        Write-Field 'Failures in a row' ([string]$st.failures) $(if ([int]$st.failures -gt 0) { 'Red' } else { 'White' })
        Write-Field 'Mode' ([string]$st.mode) 'White'

        try {
            $since = [datetime]::ParseExact($st.runningSince, 'yyyy-MM-dd HH:mm:ss', $null)
            Write-Field 'Watching since' ('{0}  ({1})' -f $st.runningSince, (Format-Duration ((Get-Date) - $since))) 'DarkGray'
        } catch { }

        try {
            $last = [datetime]::ParseExact($st.updated, 'yyyy-MM-dd HH:mm:ss', $null)
            $next = $last.AddSeconds([int]$st.intervalSeconds)
            $left = $next - (Get-Date)
            Write-Host ''
            Write-Field 'Last check' ('{0}  ({1} ago)' -f $st.updated, (Format-Duration ((Get-Date) - $last))) 'White'
            if ($left.TotalSeconds -gt 0) {
                Write-Field 'Next check' ('in {0}  ({1})' -f (Format-Duration $left), $next.ToString('HH:mm:ss')) 'Cyan'
            } else {
                Write-Field 'Next check' 'any moment now...' 'Cyan'
            }
            if ($wd.Count -gt 0 -and (Test-WatchdogStale -Status $st)) {
                Write-Host ''
                Write-Host '  WARNING: the watchdog has not checked in when expected. Unless the PC' -ForegroundColor Red
                Write-Host '  was just woken from sleep, it may be stuck: run install.bat to restart it.' -ForegroundColor Red
            }
        } catch { }
    } else {
        Write-Host ''
        Write-Host '  (no status data yet; the watchdog writes it on its first check)' -ForegroundColor DarkGray
    }

    Write-Host ''
    Write-Host '  --------------------------- LOG ---------------------------' -ForegroundColor Cyan
    if (Test-Path -LiteralPath $LogFile) {
        foreach ($line in (Get-Content -LiteralPath $LogFile -Tail 14 -Encoding UTF8 -ErrorAction SilentlyContinue)) {
            $color = 'Gray'
            if ($line -match '\[ERROR\]') { $color = 'Red' }
            elseif ($line -match '\[WARN') { $color = 'Yellow' }
            elseif ($line -match 'Launch confirmed') { $color = 'Green' }
            Write-Host ('  ' + $line) -ForegroundColor $color
        }
    } else {
        Write-Host '  (no log yet)' -ForegroundColor DarkGray
    }
    Write-Host ''

    Start-Sleep -Seconds $RefreshSeconds
}
