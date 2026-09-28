<#
    common.ps1
    Claude Desktop resolution and detection, shared by claude-watchdog.ps1,
    status.ps1 and monitor.ps1.

    Why a shared file: the status panels used to carry their own, looser copy of
    "is Claude really running?". They could report RUNNING at the very moment the
    watchdog, applying a stricter rule, decided the app was closed and relaunched
    it. One definition for all three scripts removes that contradiction.
#>

function Get-ClaudeTarget {
    $target = @{
        Aumid           = $null
        InstallLocation = $null
        Exe             = $null
        Version         = $null
        Source          = 'not-found'
    }

    # 1) MSIX / Microsoft Store install (the standard one on Windows 11)
    $pkg = $null
    try {
        $pkgs = @(Get-AppxPackage -Name 'Claude*' -ErrorAction SilentlyContinue |
                  Where-Object { -not $_.IsFramework })
        if ($pkgs.Count -gt 0) {
            $pkg = $pkgs | Where-Object { $_.Name -eq 'Claude' } | Select-Object -First 1
            if (-not $pkg) { $pkg = $pkgs[0] }
        }
    } catch { }

    if ($pkg) {
        $appId = 'Claude'
        try {
            $apps = @((Get-AppxPackageManifest $pkg.PackageFullName).Package.Applications.Application)
            if ($apps.Count -gt 0 -and $apps[0].Id) { $appId = $apps[0].Id }
        } catch { }

        $target.Aumid           = '{0}!{1}' -f $pkg.PackageFamilyName, $appId
        $target.InstallLocation = $pkg.InstallLocation
        $target.Version         = [string]$pkg.Version
        $target.Source          = 'msix'

        $exe = Join-Path $pkg.InstallLocation 'app\Claude.exe'
        if (Test-Path -LiteralPath $exe) {
            $target.Exe = $exe
        } else {
            $found = Get-ChildItem -LiteralPath $pkg.InstallLocation -Filter 'Claude.exe' -Recurse -ErrorAction SilentlyContinue |
                     Select-Object -First 1
            if ($found) { $target.Exe = $found.FullName }
        }
        return $target
    }

    # 2) Classic .exe installer, in case Claude ever ships that way.
    #    UNTESTED: this branch and the Squirrel one below have never run against
    #    a real Claude install; the paths follow common Electron conventions.
    #    The watchdog logs a WARN at startup if it ever resolves Claude this way.
    $candidates = @(
        (Join-Path $env:LOCALAPPDATA 'AnthropicClaude\Claude.exe'),
        (Join-Path $env:LOCALAPPDATA 'Programs\Claude\Claude.exe'),
        (Join-Path $env:ProgramFiles  'Claude\Claude.exe')
    )
    foreach ($c in $candidates) {
        if (Test-Path -LiteralPath $c) {
            $target.Exe    = $c
            $target.Source = 'exe'
            return $target
        }
    }

    # 3) Squirrel-style install: AnthropicClaude\app-<version>\Claude.exe (UNTESTED)
    $squirrel = Join-Path $env:LOCALAPPDATA 'AnthropicClaude'
    if (Test-Path -LiteralPath $squirrel) {
        $best = $null
        $bestVer = [version]'0.0.0'
        foreach ($dir in Get-ChildItem -LiteralPath $squirrel -Directory -Filter 'app-*' -ErrorAction SilentlyContinue) {
            $exe = Join-Path $dir.FullName 'Claude.exe'
            if (-not (Test-Path -LiteralPath $exe)) { continue }
            $ver = [version]'0.0.0'
            try { $ver = [version]($dir.Name -replace '^app-', '') } catch { }
            if ($ver -ge $bestVer) { $bestVer = $ver; $best = $exe }
        }
        if ($best) {
            $target.Exe     = $best
            $target.Version = [string]$bestVer
            $target.Source  = 'squirrel'
            return $target
        }
    }

    return $target
}

function Get-ClaudeTargetSafe {
    param([int]$TimeoutSeconds = 60)

    # Get-AppxPackage has no timeout of its own, and right after sign-in (while
    # the AppX deployment service is still starting) it has been observed to
    # emit "System error" and then hang forever, freezing the whole watchdog
    # before it ever wrote a log line. Running it in a separate job lets us
    # abandon it after a deadline instead. Returns $null on timeout or failure.
    $common = Join-Path $PSScriptRoot 'common.ps1'
    $job = Start-Job -ArgumentList $common -ScriptBlock {
        param($path)
        . $path
        Get-ClaudeTarget
    }
    try {
        if (Wait-Job -Job $job -Timeout $TimeoutSeconds) {
            $result = Receive-Job -Job $job -ErrorAction SilentlyContinue | Select-Object -Last 1
            if ($result -is [hashtable]) { return $result }
            return $null
        }
        return $null
    } finally {
        Stop-Job -Job $job -ErrorAction SilentlyContinue
        Remove-Job -Job $job -Force -ErrorAction SilentlyContinue
    }
}

function Test-WatchdogStale {
    param($Status, [int]$GraceSeconds = 300)

    # The watchdog rewrites status.json on every check and states when the next
    # one is due. If that moment is long past, the process is alive but stuck:
    # exactly the silent failure a hang right after sign-in once produced.
    if (-not $Status -or -not $Status.updated) { return $false }
    try {
        $updated = [datetime]::ParseExact([string]$Status.updated, 'yyyy-MM-dd HH:mm:ss', $null)
        $due = $updated.AddSeconds([int]$Status.intervalSeconds + $GraceSeconds)
        return ((Get-Date) -gt $due)
    } catch {
        return $false
    }
}

function Test-ClaudeInstallPath {
    param([string]$Path, $Target)
    if (-not $Path) { return $false }

    # The Claude Code CLI is also named claude.exe; it is not the desktop app.
    if ($Path -like '*\Claude\claude-code\*') { return $false }

    if ($Target -and $Target.InstallLocation -and
        $Path.StartsWith($Target.InstallLocation, [StringComparison]::OrdinalIgnoreCase)) { return $true }
    if ($Path -match '\\WindowsApps\\Claude[^\\]*\\')                            { return $true }
    if ($Target -and $Target.Exe -and $Path -eq $Target.Exe)                     { return $true }
    if ($Path -like '*\AnthropicClaude\*' -or $Path -like '*\Programs\Claude\*') { return $true }
    return $false
}

function Get-ClaudeDesktopProcess {
    param($Target)

    # Only the MAIN Electron process counts. Helpers (renderer, gpu-process,
    # utility, crashpad) carry --type= on their command line and can linger for
    # a while after the window closes; counting them would make a closed app
    # look like it is still running.
    $listed = $null
    # The timeout keeps a stuck WMI service from freezing the watchdog.
    try { $listed = @(Get-CimInstance Win32_Process -Filter "Name='claude.exe'" -OperationTimeoutSec 30 -ErrorAction Stop) } catch { $listed = $null }

    if ($null -ne $listed) {
        $found = @()
        foreach ($p in $listed) {
            if ([string]$p.CommandLine -match '--type=') { continue }
            if (Test-ClaudeInstallPath -Path ([string]$p.ExecutablePath) -Target $Target) { $found += $p }
        }
        return $found
    }

    # Fallback when WMI is unavailable: no command lines, so any app process
    # counts (over-counting beats relaunching an app that is already open).
    $found = @()
    foreach ($p in @(Get-Process -Name 'claude' -ErrorAction SilentlyContinue)) {
        $path = $null
        try { $path = $p.Path } catch { }
        if (Test-ClaudeInstallPath -Path $path -Target $Target) { $found += $p }
    }
    return $found
}
