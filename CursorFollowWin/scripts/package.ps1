#requires -Version 7.0
<#
.SYNOPSIS
    Build the per-user MSI installer for CursorFollowWin.

.DESCRIPTION
    Publishes the self-contained app (via publish.ps1), reads the product version from the
    built exe, then builds the WiX installer project against that publish folder. The MSI is
    copied to installer/dist/.

    Optional code signing: pass -CertThumbprint (a cert in the user's "My" store) or
    -CertPath/-CertPassword (a PFX). When supplied, the app exe and the final MSI are signed
    with signtool. Without a cert the build still succeeds and prints an unsigned-output notice.
    See docs/CodeSigning.md for the full signing plan.

.PARAMETER Rid
    Runtime identifier to package: win-x64 (default), win-x86, win-arm64.

.PARAMETER CertThumbprint
    SHA1 thumbprint of a code-signing cert in Cert:\CurrentUser\My to sign with.

.PARAMETER CertPath
    Path to a PFX code-signing certificate (alternative to -CertThumbprint).

.PARAMETER CertPassword
    Password for the PFX given by -CertPath.

.PARAMETER TimestampUrl
    RFC3161 timestamp server URL used when signing.

.EXAMPLE
    ./scripts/package.ps1 -Rid win-x64

.EXAMPLE
    ./scripts/package.ps1 -Rid win-x64 -CertThumbprint ABC123... -TimestampUrl http://timestamp.digicert.com
#>
[CmdletBinding()]
param(
    [ValidateSet('win-x64', 'win-x86', 'win-arm64')]
    [string]$Rid = 'win-x64',
    [string]$CertThumbprint,
    [string]$CertPath,
    [string]$CertPassword,
    [string]$TimestampUrl = 'http://timestamp.digicert.com'
)

$ErrorActionPreference = 'Stop'
$repo = Split-Path -Parent $PSScriptRoot
$wixproj = Join-Path $repo 'installer/CursorFollowWin.Installer.wixproj'
$distDir = Join-Path $repo 'installer/dist'

function Find-SignTool {
    $cmd = Get-Command signtool.exe -ErrorAction SilentlyContinue
    if ($cmd) { return $cmd.Source }
    $candidates = Get-ChildItem 'C:\Program Files (x86)\Windows Kits\10\bin\*\x64\signtool.exe' -ErrorAction SilentlyContinue |
        Sort-Object FullName -Descending
    if ($candidates) { return $candidates[0].FullName }
    return $null
}

function Invoke-Sign {
    param([string]$File)
    if (-not $CertThumbprint -and -not $CertPath) { return $false }
    $signtool = Find-SignTool
    if (-not $signtool) { throw "signtool.exe not found (install the Windows SDK) but signing was requested." }
    $args = @('sign', '/fd', 'SHA256', '/tr', $TimestampUrl, '/td', 'SHA256')
    if ($CertThumbprint) { $args += @('/sha1', $CertThumbprint) }
    else { $args += @('/f', $CertPath); if ($CertPassword) { $args += @('/p', $CertPassword) } }
    $args += $File
    Write-Host "==> Signing $([IO.Path]::GetFileName($File))" -ForegroundColor Cyan
    & $signtool @args
    if ($LASTEXITCODE -ne 0) { throw "signtool failed for $File (exit $LASTEXITCODE)." }
    return $true
}

# 1. Publish the self-contained app.
$publishDir = & (Join-Path $PSScriptRoot 'publish.ps1') -Rid $Rid -Configuration Release
$publishDir = "$publishDir".Trim()

# 2. Read the product version from the built exe (single source of truth = the csproj <Version>).
$exe = Join-Path $publishDir 'CursorFollowWin.exe'
$fileVer = (Get-Item $exe).VersionInfo.FileVersion         # e.g. 0.4.0.0
$version = ($fileVer -split '\.')[0..2] -join '.'           # -> 0.4.0 (MSI uses 3 fields)
Write-Host "==> Product version: $version (from $fileVer)" -ForegroundColor Cyan

# 3. Optionally sign the app exe before it is embedded in the MSI cab.
$signed = Invoke-Sign -File $exe

# 4. Build the MSI.
Write-Host "==> Building MSI ($Rid)" -ForegroundColor Cyan
# -t:Rebuild: the WiX SDK's incremental up-to-date check does not track the Version/PublishDir
# MSBuild properties, so a version bump or a re-publish with identical file names would otherwise
# be skipped and ship a stale MSI. Always rebuild.
dotnet build $wixproj -c Release -t:Rebuild -p:Version=$version -p:RidLabel=$Rid -p:PublishDir="$publishDir" --nologo | Out-Host
if ($LASTEXITCODE -ne 0) { throw "WiX build failed (exit $LASTEXITCODE)." }

$builtMsi = Join-Path $repo "installer/bin/Release/CursorFollowWin-$version-$Rid.msi"
if (-not (Test-Path $builtMsi)) { throw "MSI not produced: $builtMsi" }

# 5. Sign the MSI and stage it in dist/.
[void](Invoke-Sign -File $builtMsi)
New-Item -ItemType Directory -Force -Path $distDir | Out-Null
$finalMsi = Join-Path $distDir (Split-Path -Leaf $builtMsi)
Copy-Item $builtMsi $finalMsi -Force

$sizeMb = [math]::Round((Get-Item $finalMsi).Length / 1MB, 1)
Write-Host ""
Write-Host "==> MSI ready: $finalMsi ($sizeMb MB)" -ForegroundColor Green
if (-not $signed) {
    Write-Host "    NOTE: output is UNSIGNED. Provide -CertThumbprint or -CertPath to sign. See docs/CodeSigning.md." -ForegroundColor Yellow
}
return $finalMsi
