# Claude Desktop Watchdog

A small Windows watchdog that keeps the **Claude desktop app** running. It starts
with Windows, checks every 10 minutes whether Claude is open, and relaunches it
if it is not, surviving Claude's automatic updates.

No installer, no admin rights, no dependencies: just PowerShell scripts that ship
with Windows, plus double-clickable `.bat` files.

> Unofficial community tool. Not affiliated with or endorsed by Anthropic.

---

## Why this exists

The obvious way to write this kind of watchdog, "find `Claude.exe` and start it",
breaks on Windows, for two reasons:

1. **Claude Desktop is a Microsoft Store (MSIX) package.** It lives in
   `C:\Program Files\WindowsApps\Claude_<version>_x64__<id>\`, and that folder
   name **changes with every update**. Any hard-coded path stops working after the
   next update, and Windows blocks running executables from that folder directly.
2. **There is another `claude.exe` on the system.** The app downloads the Claude
   Code CLI to `%APPDATA%\Claude\claude-code\<version>\claude.exe`. It has the same
   name but is a different program. Launching that one does not open the app.

This watchdog avoids both by asking Windows to open the app through its
**AppUserModelId** (`Claude_pzs8sxrjxfjjc!Claude`), the stable identity the Start
menu uses. That identifier does not change between versions.

## Features

- **Update-proof**: launches Claude the same way the Start menu does.
- **Accurate detection**: counts only Claude's main process, not its ~15 helper
  processes or the Claude Code CLI. A window that closed while helpers linger is
  correctly seen as closed.
- **Verified relaunches**: after launching, it waits up to 60 s to confirm the
  app is actually running.
- **Two-speed checking**: every 10 min normally, every 1 min for the 5 checks
  after a relaunch (to catch an immediate re-crash).
- **Backoff on failure**: 2, 4, 8, then 15 min between attempts, so a missing
  or updating Claude is not hammered.
- **Hang protection**: queries to Windows have time limits. The status panels
  warn you if the watchdog is running but has stopped checking in.
- **Invisible**: runs with no console window. Everything goes to a log file.
- **Single instance**: starting it twice leaves only one running.
- **Pause switch**: pause for 2 hours when you want Claude closed.
- **Cloud-folder friendly**: logs are written to `%LOCALAPPDATA%`, never to the
  project folder, so a project inside OneDrive, Google Drive or Dropbox does not
  sync on every check.

## Requirements

- Windows 10 or 11
- Claude desktop app installed (tested with the Microsoft Store / MSIX version)
- Windows PowerShell 5.1 (built into Windows; nothing to install)

## Installation

1. Download the project: **Code → Download ZIP** on GitHub (then extract it), or
   `git clone`.
2. Put the folder somewhere permanent, for example `C:\Tools\claude-watchdog`.
   The autostart entry points to this location. If you move the folder later,
   run `install.bat` again.
3. Double-click **`install.bat`**.

That's it. The watchdog starts immediately and on every Windows sign-in from
now on.

> If Windows SmartScreen or your antivirus warns about the downloaded `.bat`
> files, that is normal for scripts from the internet. Read them first: they
> are short and plain text.

## Usage

Double-click any of these:

| File | What it does |
|---|---|
| `status.bat` | One-shot summary: watchdog alive?, Claude running?, last 20 log lines |
| `live-monitor.bat` | Live dashboard with counters and a countdown to the next check (Ctrl+C to exit) |
| `open-log.bat` | Opens the full log in Notepad |
| `check-now.bat` | Runs one check immediately and shows what was detected. Launches Claude if it is closed |
| `pause.bat` | Pauses the watchdog for 2 hours |
| `resume.bat` | Cancels a pause |
| `install.bat` | Installs or reinstalls the autostart entry and restarts the watchdog |
| `uninstall.bat` | Removes the autostart entry and stops the watchdog |

`install`, `uninstall`, `check-now`, `pause` and `resume` also save their output
to `_last-run.log` in the project folder, which is handy if something fails.

### Pausing for a custom time

```bat
powershell -ExecutionPolicy Bypass -File pause.ps1 -Hours 8
```

An empty `PAUSE.txt` in the project folder pauses the watchdog indefinitely.
Delete the file to resume.

## How it works

```
Windows sign-in
   └─ Startup folder: claude-watchdog.vbs    (hidden launcher, written by install.bat)
        └─ claude-watchdog.ps1                (the loop)
             ├─ every 10 min: is Claude's main process running?
             ├─ no  → open it via shell:AppsFolder\<AUMID>, confirm within 60 s
             │        then check every 1 min for the next 5 checks
             └─ log → %LOCALAPPDATA%\ClaudeWatchdog\logs\watchdog.log
```

| File | Role |
|---|---|
| `claude-watchdog.ps1` | Main loop: check, relaunch, log, write `status.json` |
| `common.ps1` | Shared "where is Claude / is it running" logic, used by the watchdog and both panels so they never disagree |
| `install.ps1` / `uninstall.ps1` | Create or remove the hidden Startup launcher |
| `status.ps1` / `monitor.ps1` | The two status panels |
| `pause.ps1` | Writes or removes `PAUSE.txt` |

### Where things are stored

| What | Where |
|---|---|
| Log (rotates at 1 MB, keeps one old file) | `%LOCALAPPDATA%\ClaudeWatchdog\logs\watchdog.log` |
| Latest status | `%LOCALAPPDATA%\ClaudeWatchdog\logs\status.json` |
| Autostart entry | `%APPDATA%\Microsoft\Windows\Start Menu\Programs\Startup\claude-watchdog.vbs` |
| Pause flag | `PAUSE.txt` in the project folder (only while paused) |

### Configuration

Defaults are set in the `param()` block at the top of `claude-watchdog.ps1`:

| Parameter | Default | Meaning |
|---|---|---|
| `IntervalSeconds` | `600` | Normal time between checks |
| `FastIntervalSeconds` | `60` | Time between checks right after a relaunch |
| `FastCycles` | `5` | How many fast checks follow a relaunch |
| `StartDelaySeconds` | `45` | Wait after sign-in before the first check |

Edit them there, then run `install.bat` to restart the watchdog.

## Troubleshooting

**`status.bat` says the watchdog is running but "has not checked in when
expected".** The process is alive but stuck. Run `install.bat` to restart it.
This warning can also appear for a few minutes right after the PC wakes from
sleep. That is harmless.

**`status.bat` says the watchdog is STOPPED.** Run `install.bat`.

**Claude is not detected.** Run `check-now.bat`. The first lines show what was
found (`source=msix` is the normal case). If it says `not-found`, the Claude
desktop app is not installed, or is installed in a way this tool does not know.
Please open an issue with that output.

**I moved the project folder.** Run `install.bat` again. The autostart entry
stores the full path.

**I want Claude closed for a while.** Use `pause.bat`, or `uninstall.bat` to
stop the watchdog for good.

## Uninstall

Double-click `uninstall.bat`, then delete the project folder and, optionally,
`%LOCALAPPDATA%\ClaudeWatchdog`.

## Limitations

- **Relies on the package being named "Claude".** If Anthropic ever renames the
  Store package, detection stops working until `common.ps1` is updated.
- **Non-Store installs are untested.** `common.ps1` has fallbacks for a classic
  `.exe` or Squirrel-style install, but they have never run against a real Claude
  install of that kind. The log shows a `WARN` if they are ever used.
- **Windows only**, and it runs per user: it watches Claude for the account that
  installed it.
- **It reopens Claude whenever it is closed**, including when you close it on
  purpose. Use `pause.bat` for that.

## License

[MIT](LICENSE)
