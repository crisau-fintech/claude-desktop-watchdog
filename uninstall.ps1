<#
    uninstall.ps1
    Removes everything install.ps1 created: the running watchdog, the Startup
    launcher, the Start menu folder, the installed program and its logs.
#>

$ErrorActionPreference = 'Stop'

$Root       = Split-Path -Parent $MyInvocation.MyCommand.Definition
$InstallDir = Join-Path $env:LOCALAPPDATA 'Programs\ClaudeWatchdog'
$DataDir    = Join-Path $env:LOCALAPPDATA 'ClaudeWatchdog'
$StartupDir = Join-Path $env:APPDATA 'Microsoft\Windows\Start Menu\Programs\Startup'
$Launcher   = Join-Path $StartupDir 'claude-watchdog.vbs'
$MenuDir    = Join-Path $env:APPDATA 'Microsoft\Windows\Start Menu\Programs\Claude Watchdog'

Write-Host ''
Write-Host '=== UNINSTALLING CLAUDE WATCHDOG ===' -ForegroundColor Cyan
Write-Host ''

$stoppedIds = @()
foreach ($p in @(Get-CimInstance Win32_Process -Filter "Name='powershell.exe' OR Name='pwsh.exe' OR Name='wscript.exe'" -ErrorAction SilentlyContinue)) {
    if ($p.ProcessId -eq $PID) { continue }
    $cmd = [string]$p.CommandLine
    if ($cmd -match 'uninstall\.ps1') { continue }
    if ($cmd -match 'claude-watchdog\.ps1' -or $cmd -match 'claude-watchdog\.vbs') {
        try { Stop-Process -Id $p.ProcessId -Force -ErrorAction Stop; $stoppedIds += $p.ProcessId } catch { }
    }
}
# Stop-Process returns before the process has fully exited and released its
# open log file; deleting the logs right away failed in testing.
if ($stoppedIds.Count -gt 0) { Wait-Process -Id $stoppedIds -Timeout 10 -ErrorAction SilentlyContinue }
Write-Host ("1. Watchdog stopped ({0} process)." -f $stoppedIds.Count)

if (Test-Path -LiteralPath $Launcher) { Remove-Item -LiteralPath $Launcher -Force }
Write-Host '2. Removed from Windows startup.'

if (Test-Path -LiteralPath $MenuDir) { Remove-Item -LiteralPath $MenuDir -Recurse -Force }
Write-Host '3. Start menu folder removed.'

for ($i = 0; $i -lt 5 -and (Test-Path -LiteralPath $DataDir); $i++) {
    Remove-Item -LiteralPath $DataDir -Recurse -Force -ErrorAction SilentlyContinue
    if (Test-Path -LiteralPath $DataDir) { Start-Sleep -Seconds 1 }
}
if (Test-Path -LiteralPath $DataDir) {
    Write-Host ("4. Could not remove the logs; delete this folder by hand: {0}" -f $DataDir) -ForegroundColor Yellow
} else {
    Write-Host '4. Logs removed.'
}

if (Test-Path -LiteralPath $InstallDir) {
    $runningFromInstall = [string]::Equals(
        [IO.Path]::GetFullPath($Root).TrimEnd('\'),
        [IO.Path]::GetFullPath($InstallDir).TrimEnd('\'),
        [StringComparison]::OrdinalIgnoreCase)

    if ($runningFromInstall) {
        # This script (and the uninstall.bat window around it) is running from
        # the folder being deleted. Deleting it now would break that window, so a
        # hidden helper waits for the window to close and deletes it then.
        $waitFor = $PID
        try {
            $parent = Get-CimInstance Win32_Process -Filter "ProcessId=$PID" -ErrorAction Stop
            $parentProc = Get-CimInstance Win32_Process -Filter ("ProcessId={0}" -f $parent.ParentProcessId) -ErrorAction Stop
            if ($parentProc.Name -eq 'cmd.exe') { $waitFor = $parentProc.ProcessId }
        } catch { }
        $dir = $InstallDir.Replace("'", "''")
        $cleanup = "Wait-Process -Id $waitFor -ErrorAction SilentlyContinue; Start-Sleep -Seconds 1; Remove-Item -LiteralPath '$dir' -Recurse -Force -ErrorAction SilentlyContinue"
        Start-Process -FilePath 'powershell.exe' -WindowStyle Hidden `
            -ArgumentList @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-Command', $cleanup)
        Write-Host '5. Program folder will be deleted when this window closes.'
    } else {
        Remove-Item -LiteralPath $InstallDir -Recurse -Force
        Write-Host '5. Program folder removed.'
    }
} else {
    Write-Host '5. Program folder was not installed.'
}

Write-Host ''
Write-Host 'Claude Watchdog has been completely removed.' -ForegroundColor Green
Write-Host 'Claude itself is not affected.'
Write-Host ''
