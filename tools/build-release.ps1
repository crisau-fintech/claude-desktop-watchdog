<#
    tools/build-release.ps1
    Builds ClaudeWatchdog.zip: only the files an end user needs, at the root of
    the ZIP, so "Extract All" gives a folder with install.bat directly inside.

    Usage (from the repo root):
        powershell -ExecutionPolicy Bypass -File tools\build-release.ps1
        gh release create vX.Y.Z dist\ClaudeWatchdog.zip --title "vX.Y.Z" --notes "..."

    The README links to .../releases/latest/download/ClaudeWatchdog.zip, which
    always resolves to the newest release as long as the asset keeps this name.
#>

$ErrorActionPreference = 'Stop'

$Repo  = Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Definition)
$Dist  = Join-Path $Repo 'dist'
$Stage = Join-Path $Dist 'ClaudeWatchdog'
$Zip   = Join-Path $Dist 'ClaudeWatchdog.zip'

$Files = @(
    'install.bat', 'uninstall.bat', 'status.bat', 'live-monitor.bat',
    'check-now.bat', 'pause.bat', 'resume.bat', 'open-log.bat',
    'claude-watchdog.ps1', 'common.ps1', 'install.ps1', 'uninstall.ps1',
    'status.ps1', 'monitor.ps1', 'pause.ps1',
    'README.md', 'LICENSE'
)

if (Test-Path -LiteralPath $Stage) { Remove-Item -LiteralPath $Stage -Recurse -Force }
if (Test-Path -LiteralPath $Zip)   { Remove-Item -LiteralPath $Zip -Force }
New-Item -ItemType Directory -Path $Stage -Force | Out-Null

foreach ($f in $Files) {
    $src = Join-Path $Repo $f
    if (-not (Test-Path -LiteralPath $src)) { throw "Missing file for release: $f" }
    Copy-Item -LiteralPath $src -Destination $Stage
}

# cmd.exe can misparse LF-only batch files; refuse to ship one.
foreach ($bat in Get-ChildItem -LiteralPath $Stage -Filter '*.bat') {
    $bytes = [IO.File]::ReadAllBytes($bat.FullName)
    $cr = @($bytes | Where-Object { $_ -eq 13 }).Count
    $lf = @($bytes | Where-Object { $_ -eq 10 }).Count
    if ($cr -ne $lf) { throw "$($bat.Name) does not have CRLF line endings" }
}

Compress-Archive -Path (Join-Path $Stage '*') -DestinationPath $Zip
Remove-Item -LiteralPath $Stage -Recurse -Force

Write-Host ("Built {0} ({1:N0} KB)" -f $Zip, ((Get-Item -LiteralPath $Zip).Length / 1KB))
