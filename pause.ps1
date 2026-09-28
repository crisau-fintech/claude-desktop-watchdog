<#
    pause.ps1
    Pauses the watchdog for N hours (default 2) by writing PAUSE.txt with the
    end time. Useful when you want to close Claude without it being reopened,
    or while a large update installs.

    -Hours 0 cancels the pause.
#>

param([double]$Hours = 2)

$Root      = Split-Path -Parent $MyInvocation.MyCommand.Definition
$PauseFile = Join-Path $Root 'PAUSE.txt'

Write-Host ''
if ($Hours -le 0) {
    if (Test-Path -LiteralPath $PauseFile) { Remove-Item -LiteralPath $PauseFile -Force }
    Write-Host 'Pause cancelled. The watchdog is monitoring Claude again.' -ForegroundColor Green
    Write-Host ''
    exit 0
}

$until = (Get-Date).AddHours($Hours)
Set-Content -LiteralPath $PauseFile -Value $until.ToString('yyyy-MM-ddTHH:mm:ss') -Encoding ASCII
Write-Host ("Watchdog paused until {0}." -f $until.ToString('yyyy-MM-dd HH:mm')) -ForegroundColor Yellow
Write-Host 'Claude will not be relaunched until then. To resume earlier: resume.bat'
Write-Host ''
