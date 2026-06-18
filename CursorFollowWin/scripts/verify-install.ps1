#requires -Version 7.0
<#
.SYNOPSIS
    End-to-end verification of the CursorFollowWin MSI: install, assert, smoke-launch,
    uninstall, assert cleanup.

.DESCRIPTION
    Drives a per-user MSI through its full lifecycle on the current machine and checks that
    each stage did what it should. Safe to run on a dev box: it installs per-user (no UAC),
    smoke-launches the app for a few seconds, then uninstalls and verifies nothing is left
    behind. To exercise the "Start with Windows" cleanup it plants a sentinel Run value before
    installing and asserts the uninstaller removes it.

    Exit code 0 = all checks passed; non-zero = a check failed (details printed).

.PARAMETER Msi
    Path to the MSI to verify. Defaults to the newest MSI in installer/dist.

.PARAMETER KeepInstalled
    Skip the uninstall + cleanup phase (leave the app installed for manual inspection).

.EXAMPLE
    ./scripts/verify-install.ps1
#>
[CmdletBinding()]
param(
    [string]$Msi,
    [switch]$KeepInstalled
)

$ErrorActionPreference = 'Stop'
$repo = Split-Path -Parent $PSScriptRoot

if (-not $Msi) {
    $distDir = Join-Path $repo 'installer/dist'
    $Msi = (Get-ChildItem $distDir -Filter '*.msi' -ErrorAction SilentlyContinue |
        Sort-Object LastWriteTime -Descending | Select-Object -First 1).FullName
    if (-not $Msi) { throw "No MSI given and none found in $distDir. Run package.ps1 first." }
}
$Msi = (Resolve-Path $Msi).Path

$installDir = Join-Path $env:LOCALAPPDATA 'Programs\CursorFollowWin'
$dataDir = Join-Path $env:LOCALAPPDATA 'CursorFollowWin'
$installedExe = Join-Path $installDir 'CursorFollowWin.exe'
$shortcut = Join-Path $env:APPDATA 'Microsoft\Windows\Start Menu\Programs\CursorFollow.lnk'
$runKey = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Run'
$sentinel = 'C:\Sentinel\CursorFollowWin.exe'   # fake prior "Start with Windows" value

$script:failures = 0
function Check {
    param([string]$Name, [bool]$Condition)
    if ($Condition) { Write-Host "  [PASS] $Name" -ForegroundColor Green }
    else { Write-Host "  [FAIL] $Name" -ForegroundColor Red; $script:failures++ }
}

# The ARP (Add/Remove Programs) entry can land in any of the per-user/per-machine Uninstall
# hives depending on install scope and MSI architecture; search them all.
function Test-ArpEntry {
    $hives = @(
        'HKCU:\Software\Microsoft\Windows\CurrentVersion\Uninstall',
        'HKLM:\Software\Microsoft\Windows\CurrentVersion\Uninstall',
        'HKLM:\Software\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall'
    )
    foreach ($h in $hives) {
        $hit = Get-ChildItem $h -ErrorAction SilentlyContinue |
            ForEach-Object { Get-ItemProperty $_.PSPath } |
            Where-Object { $_.DisplayName -eq 'CursorFollow for Windows' }
        if ($hit) { return $true }
    }
    return $false
}

function Invoke-Msi {
    param([string[]]$MsiArgs, [string]$LogName)
    $log = Join-Path $env:TEMP $LogName
    $all = $MsiArgs + @('/qn', '/norestart', '/l*v', $log)
    $p = Start-Process msiexec.exe -ArgumentList $all -Wait -PassThru
    if ($p.ExitCode -ne 0) {
        Write-Host "  msiexec exit $($p.ExitCode); tail of ${log}:" -ForegroundColor Yellow
        Get-Content $log -Tail 15 | ForEach-Object { Write-Host "    $_" }
    }
    return $p.ExitCode
}

Write-Host "==> Verifying MSI: $Msi" -ForegroundColor Cyan
Get-Process CursorFollowWin -ErrorAction SilentlyContinue | Stop-Process -Force

# Plant a sentinel Run value so we can prove the uninstaller removes it.
New-ItemProperty -Path $runKey -Name 'CursorFollowWin' -Value $sentinel -PropertyType String -Force | Out-Null

# ---- Install ----
Write-Host "==> Install" -ForegroundColor Cyan
$rc = Invoke-Msi -MsiArgs @('/i', $Msi) -LogName 'cfw-install.log'
Check 'msiexec install returned 0' ($rc -eq 0)
Check 'install dir exists' (Test-Path $installDir)
Check 'CursorFollowWin.exe installed' (Test-Path $installedExe)
Check 'root resources PRI present' (Test-Path (Join-Path $installDir 'CursorFollowWin.pri'))
Check 'Start-menu shortcut created' (Test-Path $shortcut)
Check 'ARP (Add/Remove Programs) entry present' (Test-ArpEntry)

# ---- Smoke launch ----
Write-Host "==> Smoke launch (installed exe)" -ForegroundColor Cyan
$ok = $false
if (Test-Path $installedExe) {
    $proc = Start-Process $installedExe -PassThru
    Start-Sleep -Seconds 6
    $alive = -not $proc.HasExited
    $log = Get-ChildItem (Join-Path $dataDir 'Logs') -Filter *.log -ErrorAction SilentlyContinue |
        Sort-Object LastWriteTime | Select-Object -Last 1
    $startupComplete = $false
    if ($log) { $startupComplete = (Get-Content $log.FullName -Tail 25) -match 'Startup complete' }
    $ok = $alive -and $startupComplete
    if ($proc -and -not $proc.HasExited) { Stop-Process -Id $proc.Id -Force }
}
Check 'installed app launches and reaches "Startup complete"' $ok

if ($KeepInstalled) {
    Write-Host "==> KeepInstalled set; leaving app installed. Failures: $script:failures" -ForegroundColor Yellow
    exit ([int]($script:failures -gt 0))
}

# ---- Uninstall ----
Write-Host "==> Uninstall" -ForegroundColor Cyan
Get-Process CursorFollowWin -ErrorAction SilentlyContinue | Stop-Process -Force
$rc = Invoke-Msi -MsiArgs @('/x', $Msi) -LogName 'cfw-uninstall.log'
Check 'msiexec uninstall returned 0' ($rc -eq 0)
Check 'install dir removed' (-not (Test-Path $installDir))
Check 'Start-menu shortcut removed' (-not (Test-Path $shortcut))
Check 'data folder (settings + logs) removed' (-not (Test-Path $dataDir))
$runVal = (Get-ItemProperty -Path $runKey -Name 'CursorFollowWin' -ErrorAction SilentlyContinue).CursorFollowWin
Check 'Run value removed on uninstall' ($null -eq $runVal)
Check 'ARP entry removed' (-not (Test-ArpEntry))

# Clean up the sentinel if anything left it behind.
Remove-ItemProperty -Path $runKey -Name 'CursorFollowWin' -ErrorAction SilentlyContinue

Write-Host ""
if ($script:failures -eq 0) { Write-Host "==> ALL CHECKS PASSED" -ForegroundColor Green }
else { Write-Host "==> $script:failures CHECK(S) FAILED" -ForegroundColor Red }
exit ([int]($script:failures -gt 0))
