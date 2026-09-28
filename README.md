# Claude Desktop Watchdog

A small Windows tool that keeps the **Claude desktop app** running. It starts with
Windows, checks every 10 minutes whether Claude is open, and reopens it if it is
not. It keeps working when Claude updates itself.

> Unofficial community tool. Not affiliated with or endorsed by Anthropic.

## Requirements

**Nothing to install.** No Python, no libraries, no administrator rights. It only
uses what already comes with Windows.

- Windows 10 or 11
- The Claude desktop app

## Install (3 steps)

1. **[Download ClaudeWatchdog.zip](https://github.com/crisau-fintech/claude-desktop-watchdog/releases/latest/download/ClaudeWatchdog.zip)**
2. Right-click the downloaded file → **Extract All...** → **Extract**
3. In the folder that opens, double-click **`install.bat`**

Done. The watchdog is running and will start by itself every time you sign in to
Windows. You can delete the downloaded ZIP and folder: the program has been copied
to its own place.

> **Windows may warn you** the first time ("Windows protected your PC" or "Do you
> want to run this file?"). That is normal for any script downloaded from the
> internet. Click **More info → Run anyway** (or **Run**). The scripts are plain
> text; feel free to read them first.

## Everyday use

Everything is in the **Start menu → Claude Watchdog** folder:

| Shortcut | What it does |
|---|---|
| **Status** | Is the watchdog running? Is Claude open? Shows the latest activity |
| **Live monitor** | Live dashboard with a countdown to the next check (close it or press Ctrl+C) |
| **Pause for 2 hours** | Stops reopening Claude, for when you want it closed |
| **Resume** | Ends a pause early |
| **Check now** | Checks immediately and opens Claude if it is closed |
| **Open log** | The full activity history in Notepad |
| **Restart watchdog** | Restarts it if the Status screen says something is wrong |
| **Uninstall** | Removes everything (Claude itself is not touched) |

## What it does, exactly

- **Checks every 10 minutes.** After reopening Claude, it checks every minute for
  the next 5 checks, in case it closes again straight away.
- **Confirms every reopen**: waits up to 60 seconds to see Claude actually running.
- **Survives Claude updates.** It opens Claude the same way the Start menu does,
  not through a file path that changes with every version.
- **Is not fooled by leftovers.** Claude runs around 15 background processes. The
  watchdog looks only at the main one, so a closed window whose helper processes
  linger is correctly seen as closed.
- **Backs off when something is wrong**: if Claude cannot be opened, it waits 2,
  then 4, 8 and 15 minutes between attempts instead of retrying non-stop.
- **Tells you if it gets stuck.** If the watchdog stops checking in when expected,
  the Status screen says so in red.
- **Runs invisibly**, with no window, and never more than one copy at a time.

## Uninstall

**Start menu → Claude Watchdog → Uninstall.** It removes the program, its logs,
the Start menu folder and the automatic start. Claude itself is not affected.

## Troubleshooting

**Status says the watchdog "has not checked in when expected".** Use
**Restart watchdog**. This warning can also show for a few minutes right after the
PC wakes from sleep; that case is harmless.

**Status says the watchdog is STOPPED.** Use **Restart watchdog**.

**Claude is not detected.** Use **Check now**. The first lines show what was found:
`source=msix` is the normal case. If it says `not-found`, the Claude desktop app is
not installed, or is installed in a way this tool does not recognise. Please
[open an issue](https://github.com/crisau-fintech/claude-desktop-watchdog/issues)
and include that output.

**"The ZIP file has not been extracted yet".** You opened `install.bat` from inside
the ZIP. Right-click the ZIP → **Extract All...**, then run `install.bat` from the
extracted folder.

## Limitations

- **Relies on the Store package being named "Claude".** If Anthropic renames it,
  detection stops working until `common.ps1` is updated.
- **Tested only with the Microsoft Store version of Claude.** There is untested
  support for classic installs; the log shows a `WARN` if it is ever used.
- **Per user**: it watches Claude for the Windows account that installed it.
- **It reopens Claude whenever it is closed**, including on purpose. Use
  **Pause for 2 hours** for that.

---

## Technical details

### Why a naive watchdog breaks

1. **Claude Desktop is an MSIX (Microsoft Store) package** installed under
   `C:\Program Files\WindowsApps\Claude_<version>_x64__<id>\`. The folder name
   changes with every update, and Windows blocks launching executables from there
   directly.
2. **There is a second `claude.exe`**: the Claude Code CLI, downloaded by the app to
   `%APPDATA%\Claude\claude-code\<version>\`. Same name, different program.

The watchdog launches Claude through its **AppUserModelId**
(`explorer.exe shell:AppsFolder\Claude_pzs8sxrjxfjjc!Claude`), which does not
change between versions, and identifies the main process by its install path and
command line.

### Files

| File | Role |
|---|---|
| `claude-watchdog.ps1` | Main loop: check, relaunch, log, write status |
| `common.ps1` | Shared "where is Claude / is it running" logic, used by the watchdog and both status screens so they never disagree |
| `install.ps1` / `uninstall.ps1` | Copy the program, create the Start menu folder and the hidden Startup launcher, or remove all of it |
| `status.ps1` / `monitor.ps1` | The two status screens |
| `pause.ps1` | Writes or removes `PAUSE.txt` |
| `*.bat` | Double-click wrappers. `install`, `uninstall`, `check-now`, `pause` and `resume` also save their output to `_last-run.log` |
| `tools/build-release.ps1` | Builds the release ZIP (maintainers only) |

### Where things are stored

| What | Where |
|---|---|
| Program | `%LOCALAPPDATA%\Programs\ClaudeWatchdog\` |
| Log (rotates at 1 MB) and status | `%LOCALAPPDATA%\ClaudeWatchdog\logs\` |
| Automatic start | `%APPDATA%\Microsoft\Windows\Start Menu\Programs\Startup\claude-watchdog.vbs` |
| Start menu shortcuts | `%APPDATA%\Microsoft\Windows\Start Menu\Programs\Claude Watchdog\` |
| Pause flag | `PAUSE.txt` in the program folder, only while paused |

### Settings

Defaults live in the `param()` block at the top of `claude-watchdog.ps1`
(`IntervalSeconds` 600, `FastIntervalSeconds` 60, `FastCycles` 5,
`StartDelaySeconds` 45). Edit the installed copy, then use **Restart watchdog**.

### Development notes

- Keep `.ps1` files **ASCII-only**: Windows PowerShell 5.1 reads BOM-less scripts
  in the system code page and garbles accented characters.
- Keep `.bat` files with **CRLF** line endings (`.gitattributes` stores them
  verbatim; the release script refuses to ship LF ones).
- All detection logic belongs in `common.ps1`.
- To test the relaunch path without closing Claude, point a copy of the scripts at
  Calculator (`Microsoft.WindowsCalculator` / `CalculatorApp.exe`) with its own
  mutex name and log folder.
- Releases: `powershell -ExecutionPolicy Bypass -File tools\build-release.ps1`, then
  `gh release create vX.Y.Z dist\ClaudeWatchdog.zip`. Keep the asset name
  `ClaudeWatchdog.zip`: the download link above depends on it.

## License

[MIT](LICENSE)
