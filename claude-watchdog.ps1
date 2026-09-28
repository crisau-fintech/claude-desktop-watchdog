<#
    claude-watchdog.ps1
    Keeps the Claude desktop app running: checks periodically and relaunches it
    when it is not running.

    Why the AppUserModelId instead of a hard-coded .exe path:
    Claude Desktop ships as an MSIX package installed under
    C:\Program Files\WindowsApps\Claude_<version>_x64__<publisherId>\app\Claude.exe
    That folder name changes on every update, and executables inside WindowsApps
    cannot be launched reliably by path (ACLs block it). The AppUserModelId
    (e.g. "Claude_pzs8sxrjxfjjc!Claude") derives from the package family name,
    which stays identical across updates, so launching through the shell
    survives them.

    Note: %APPDATA%\Claude\claude-code\<version>\claude.exe is the Claude Code CLI
    that the app downloads, NOT the desktop app. Launching it is a common mistake.
#>

param(
    [switch]$Once,                     # single check with console output
    [switch]$NoLaunch,                 # diagnose only, never launch (for testing)
    [int]$IntervalSeconds = 600,       # normal pace: every 10 minutes
    [int]$FastIntervalSeconds = 60,    # faster pace right after a relaunch
    [int]$FastCycles = 5,              # how many checks the faster pace lasts
    [int]$StartDelaySeconds = 45       # initial wait after Windows sign-in
)

$ErrorActionPreference = 'Continue'
$ProgressPreference    = 'SilentlyContinue'

$Root = Split-Path -Parent $MyInvocation.MyCommand.Definition

# Logs live outside the project folder on purpose: if the project sits in a
# cloud-synced folder (OneDrive, Google Drive, Dropbox), every write would
# trigger an upload. LOCALAPPDATA is never synced.
$LogDir     = Join-Path $env:LOCALAPPDATA 'ClaudeWatchdog\logs'
$LogFile    = Join-Path $LogDir 'watchdog.log'
$StatusFile = Join-Path $LogDir 'status.json'

# PAUSE.txt lives in the project folder: it is only written when you pause, and
# it is visible at a glance there.
$PauseFile = Join-Path $Root 'PAUSE.txt'

$script:ToConsole = [bool]$Once
$MaxLogBytes = 1MB

# ---------------------------------------------------------------------------
# Utilities
# ---------------------------------------------------------------------------

function Initialize-Paths {
    if (-not (Test-Path -LiteralPath $LogDir)) {
        New-Item -ItemType Directory -Path $LogDir -Force | Out-Null
    }
}

function Invoke-LogRotation {
    try {
        if (-not (Test-Path -LiteralPath $LogFile)) { return }
        if ((Get-Item -LiteralPath $LogFile).Length -lt $MaxLogBytes) { return }
        $old = Join-Path $LogDir 'watchdog.1.log'
        if (Test-Path -LiteralPath $old) { Remove-Item -LiteralPath $old -Force }
        Move-Item -LiteralPath $LogFile -Destination $old -Force
    } catch { }
}

function Write-Log {
    param([string]$Message, [string]$Level = 'INFO')
    $line = '[{0}] [{1}] {2}' -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'), $Level.PadRight(5), $Message
    if ($script:ToConsole) { Write-Host $line }
    try {
        Invoke-LogRotation
        Add-Content -LiteralPath $LogFile -Value $line -Encoding UTF8
    } catch { }
}

function Format-Wait {
    param([int]$Seconds)
    if ($Seconds -ge 60) { return ('{0} min' -f [int]($Seconds / 60)) }
    return ('{0} s' -f $Seconds)
}

function Save-Status {
    param([hashtable]$Data)
    try {
        $Data['updated'] = (Get-Date -Format 'yyyy-MM-dd HH:mm:ss')
        ($Data | ConvertTo-Json -Depth 4) | Set-Content -LiteralPath $StatusFile -Encoding UTF8
    } catch { }
}

# ---------------------------------------------------------------------------
# Claude resolution and detection (shared with status.ps1 and monitor.ps1 so
# no panel can ever disagree with the watchdog about whether Claude is running)
# ---------------------------------------------------------------------------

. (Join-Path $Root 'common.ps1')

function Resolve-ClaudeTarget {
    param($Previous)
    $t = Get-ClaudeTargetSafe -TimeoutSeconds 60
    if ($t) { return $t }
    Write-Log 'Timed out after 60 s asking Windows where Claude is installed (the app service may still be starting). Keeping the last known target; will retry.' 'ERROR'
    if ($Previous) { return $Previous }
    return @{ Aumid = $null; InstallLocation = $null; Exe = $null; Version = $null; Source = 'unresolved' }
}

function Start-ClaudeApp {
    param($Target)

    if ($Target.Aumid) {
        try {
            Start-Process -FilePath 'explorer.exe' -ArgumentList ('shell:AppsFolder\' + $Target.Aumid) -ErrorAction Stop
            Write-Log ('Launching via AUMID: {0}' -f $Target.Aumid)
            return $true
        } catch {
            Write-Log ('Launch via AUMID failed: {0}' -f $_.Exception.Message) 'ERROR'
        }
    }

    if ($Target.Exe) {
        try {
            Start-Process -FilePath $Target.Exe -ErrorAction Stop
            Write-Log ('Launching via direct path: {0}' -f $Target.Exe)
            return $true
        } catch {
            Write-Log ('Launch via direct path failed: {0}' -f $_.Exception.Message) 'ERROR'
        }
    }

    if ($Target.Source -eq 'unresolved') {
        Write-Log 'Cannot launch yet: Windows has not answered where Claude is installed.' 'ERROR'
    } else {
        Write-Log 'No Claude desktop installation found on this computer.' 'ERROR'
    }
    return $false
}

function Wait-ClaudeAlive {
    param($Target, [int]$TimeoutSeconds = 60)
    $deadline = (Get-Date).AddSeconds($TimeoutSeconds)
    while ((Get-Date) -lt $deadline) {
        Start-Sleep -Seconds 3
        if (@(Get-ClaudeDesktopProcess -Target $Target).Count -gt 0) { return $true }
    }
    return $false
}

$script:lastPauseErrorLog = [datetime]::MinValue

function Test-PauseActive {
    if (-not (Test-Path -LiteralPath $PauseFile)) { return $false }
    $raw = $null
    try {
        $raw = (Get-Content -LiteralPath $PauseFile -Raw -ErrorAction Stop)
        if ($raw) { $raw = $raw.Trim() }
        if (-not $raw) { return $true }                 # empty file: indefinite pause
        $until = [datetime]::Parse($raw, [Globalization.CultureInfo]::InvariantCulture)
        if ((Get-Date) -lt $until) { return $true }
        Remove-Item -LiteralPath $PauseFile -Force -ErrorAction SilentlyContinue
        Write-Log 'Pause expired. Monitoring resumed.'
        return $false
    } catch {
        # PAUSE.txt exists but is not a valid date (hand-edited, other format...).
        # Treat it as an indefinite pause to be safe, but ALWAYS log an explicit
        # ERROR: otherwise an accidental pause looks identical to a deliberate one
        # and can silently disable the watchdog.
        if (((Get-Date) - $script:lastPauseErrorLog).TotalMinutes -ge 30) {
            Write-Log ('PAUSE.txt is not a valid date ("{0}"). Treating it as an indefinite pause: delete or fix it if that was not intended.' -f $raw) 'ERROR'
            $script:lastPauseErrorLog = Get-Date
        }
        return $true
    }
}

# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------

Initialize-Paths

# Single instance: if Windows starts the watchdog twice, the second one exits.
if (-not $Once) {
    $mutex = New-Object System.Threading.Mutex($false, 'Local\ClaudeWatchdogSingleInstance')
    $owned = $false
    try { $owned = $mutex.WaitOne(0) } catch { $owned = $true }
    if (-not $owned) { exit 0 }
}

if ($Once) {
    $target = Resolve-ClaudeTarget
    Write-Log '--- Manual check ---'
    Write-Log ('Detected app: source={0} version={1}' -f $target.Source, $target.Version)
    Write-Log ('AUMID: {0}' -f $target.Aumid)
    Write-Log ('Path:  {0}' -f $target.Exe)
    $procs = @(Get-ClaudeDesktopProcess -Target $target)
    if ($procs.Count -gt 0) {
        Write-Log ('Claude IS running ({0} main process).' -f $procs.Count)
    } elseif ($NoLaunch) {
        Write-Log 'Claude is not running (-NoLaunch: not launching).' 'WARN'
    } else {
        Write-Log 'Claude is not running. Launching it to verify...' 'WARN'
        if (Start-ClaudeApp -Target $target) {
            if (Wait-ClaudeAlive -Target $target) { Write-Log 'Launch verified.' }
            else { Write-Log 'Launched, but no process appeared within 60 s.' 'ERROR' }
        }
    }
    exit 0
}

# Log the start BEFORE asking Windows anything: if a system call hangs right
# after sign-in, the log at least shows the watchdog started and where it stopped.
Write-Log '==============================================='
Write-Log ('CLAUDE WATCHDOG - start (PID {0})' -f $PID)
Write-Log ('Normal pace: {0} | after relaunch: {1} x{2} | initial delay: {3}s' -f `
           (Format-Wait $IntervalSeconds), (Format-Wait $FastIntervalSeconds), $FastCycles, $StartDelaySeconds)

# Heartbeat before the first check, so the status panels do not flag a freshly
# started watchdog as stuck. The allowed window covers the delay plus a slow
# first query.
Save-Status @{
    state           = 'starting-up'
    intervalSeconds = $StartDelaySeconds + 120
    checks          = 0
    relaunches      = 0
    lastRelaunch    = 'none yet'
    runningSince    = (Get-Date -Format 'yyyy-MM-dd HH:mm:ss')
    processId       = $PID
}

# Let Windows finish starting its services before the first query.
if ($StartDelaySeconds -gt 0) { Start-Sleep -Seconds $StartDelaySeconds }

$target = Resolve-ClaudeTarget
Write-Log ('App: source={0} version={1}' -f $target.Source, $target.Version)
Write-Log ('AUMID: {0}' -f $target.Aumid)
if ($target.Source -eq 'exe' -or $target.Source -eq 'squirrel') {
    Write-Log ('Claude was resolved via the untested "{0}" fallback. Check Get-ClaudeTarget in common.ps1 if anything misbehaves.' -f $target.Source) 'WARN'
}
if ($target.Source -eq 'not-found') {
    Write-Log 'Claude desktop was not found. The watchdog will keep retrying.' 'WARN'
}
Write-Log '==============================================='

$checks       = 0
$launches      = 0
$failures      = 0            # consecutive launch failures
$fastRemaining = 0            # checks left at the faster pace
$startedAt     = Get-Date
$lastLaunchTxt = 'none yet'
$lastResolve   = Get-Date
$lastPauseLog  = [datetime]::MinValue

while ($true) {
    $checks++

    if (Test-PauseActive) {
        if (((Get-Date) - $lastPauseLog).TotalMinutes -ge 30) {
            Write-Log 'Paused (PAUSE.txt exists). Claude will not be relaunched.'
            $lastPauseLog = Get-Date
        }
        Save-Status @{
            state           = 'paused'
            intervalSeconds = $IntervalSeconds
            checks       = $checks
            relaunches   = $launches
            lastRelaunch = $lastLaunchTxt
            runningSince = $startedAt.ToString('yyyy-MM-dd HH:mm:ss')
            processId    = $PID
        }
        Start-Sleep -Seconds $IntervalSeconds
        continue
    }

    # Re-resolve hourly so updates are picked up without restarting the watchdog.
    if (((Get-Date) - $lastResolve).TotalMinutes -ge 60) {
        $newTarget = Resolve-ClaudeTarget -Previous $target
        if ($newTarget.Version -ne $target.Version -or $newTarget.Source -ne $target.Source) {
            Write-Log ('Installation changed: {0} {1} -> {2} {3}' -f $target.Source, $target.Version, $newTarget.Source, $newTarget.Version)
        }
        $target = $newTarget
        $lastResolve = Get-Date
    }

    $procs = @(Get-ClaudeDesktopProcess -Target $target)

    $state = 'running'

    if ($procs.Count -gt 0) {
        if ($failures -gt 0) { Write-Log 'Claude is available again.' }
        $failures = 0
        if ($fastRemaining -gt 0) {
            $fastRemaining--
            if ($fastRemaining -eq 0) { Write-Log 'Claude stable after relaunch. Back to normal pace.' }
        }
    }
    else {
        # No "recently launched, give it time" grace here on purpose: every launch
        # is already confirmed by Wait-ClaudeAlive, and a failed one is followed
        # by a backoff of at least 2 minutes. A grace period could only ever
        # delay reopening an app that was confirmed running and then crashed.
        Write-Log ('Claude not running (check {0}). Relaunching...' -f $checks) 'WARN'

        # Always re-resolve before launching: if Claude was updated while the
        # watchdog was running, this picks up the new installation.
        $target      = Resolve-ClaudeTarget -Previous $target
        $lastResolve = Get-Date

        if (Start-ClaudeApp -Target $target) {
            $launches++
            $lastLaunchTxt = (Get-Date -Format 'yyyy-MM-dd HH:mm:ss')
            if (Wait-ClaudeAlive -Target $target) {
                Write-Log ('Launch confirmed: Claude is running (relaunch #{0}).' -f $launches)
                $failures = 0
                # Faster pace: if it crashes again right away, catch it in
                # 1 minute instead of 10.
                $fastRemaining = $FastCycles
            } else {
                $failures++
                Write-Log ('Launched, but no process appeared within 60 s (failure {0}).' -f $failures) 'ERROR'
            }
        } else {
            $failures++
        }

        $state = 'relaunched'
        if ($failures -gt 0) { $state = 'error' }
    }

    # Pace: backoff after failures, faster after a relaunch, normal otherwise.
    if ($failures -gt 0) {
        # 2, 4, 8 min capped at 15, so a missing or updating Claude does not get
        # hammered with launch attempts.
        $sleepFor = [int][Math]::Min([Math]::Pow(2, [Math]::Min($failures, 4)) * 60, 900)
    } elseif ($fastRemaining -gt 0) {
        $sleepFor = $FastIntervalSeconds
    } else {
        $sleepFor = $IntervalSeconds
    }

    $detail = ''
    if ($fastRemaining -gt 0) { $detail = ' [fast pace, {0} left]' -f $fastRemaining }
    if ($failures -gt 0)      { $detail = ' [retry after failure {0}]' -f $failures }

    if ($state -eq 'running') {
        Write-Log ('Check {0}: Claude running. Next in {1}.{2}' -f $checks, (Format-Wait $sleepFor), $detail)
    } else {
        Write-Log ('Check {0}: {1}. Next in {2}.{3}' -f $checks, $state, (Format-Wait $sleepFor), $detail)
    }

    $mode = 'normal'
    if ($fastRemaining -gt 0) { $mode = 'fast' }
    if ($failures -gt 0)      { $mode = 'retry' }

    Save-Status @{
        state           = $state
        mode            = $mode
        checks          = $checks
        relaunches      = $launches
        failures        = $failures
        version         = $target.Version
        intervalSeconds = $sleepFor
        lastRelaunch    = $lastLaunchTxt
        runningSince    = $startedAt.ToString('yyyy-MM-dd HH:mm:ss')
        processId       = $PID
    }

    Start-Sleep -Seconds $sleepFor
}
