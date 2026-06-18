#requires -Version 7.0
<#
.SYNOPSIS
    Produce a self-contained, ReadyToRun publish of CursorFollowWin for one runtime.

.DESCRIPTION
    Wraps `dotnet publish` with the project's publish profile. Trimming is disabled in the
    project (WinUI/XAML reflection is not trim-safe); this script just selects the RID and
    configuration and returns the absolute publish path so package.ps1 can harvest it.

.PARAMETER Rid
    Runtime identifier: win-x64 (default), win-x86, or win-arm64.

.PARAMETER Configuration
    Build configuration. Release (default) for shippable output.

.EXAMPLE
    ./scripts/publish.ps1 -Rid win-x64
#>
[CmdletBinding()]
param(
    [ValidateSet('win-x64', 'win-x86', 'win-arm64')]
    [string]$Rid = 'win-x64',
    [ValidateSet('Release', 'Debug')]
    [string]$Configuration = 'Release'
)

$ErrorActionPreference = 'Stop'
$repo = Split-Path -Parent $PSScriptRoot          # CursorFollowWin/
$proj = Join-Path $repo 'CursorFollowWin.csproj'
$platform = @{ 'win-x64' = 'x64'; 'win-x86' = 'x86'; 'win-arm64' = 'ARM64' }[$Rid]

Write-Host "==> Publishing $Configuration / $Rid (self-contained, ReadyToRun)" -ForegroundColor Cyan
# Route dotnet's stdout to the host so it does not pollute this script's success stream
# (callers capture the returned publish path).
dotnet publish $proj -c $Configuration -p:Platform=$platform -p:PublishProfile="win-$platform" --nologo | Out-Host
if ($LASTEXITCODE -ne 0) { throw "dotnet publish failed (exit $LASTEXITCODE)." }

# Path mirrors the publish profile's PublishDir: bin\<Config>\<tfm>\<rid>\publish
$tfm = 'net10.0-windows10.0.26100.0'
$publishDir = Join-Path $repo "bin/$Configuration/$tfm/$Rid/publish"
if (-not (Test-Path $publishDir)) { throw "Publish folder not found: $publishDir" }

$exe = Join-Path $publishDir 'CursorFollowWin.exe'
if (-not (Test-Path $exe)) { throw "Published exe missing: $exe" }
# Guard against the WinUI publish PRI-drop regression (see CursorFollowWin.csproj _CopyAppPriToPublish).
if (-not (Test-Path (Join-Path $publishDir 'CursorFollowWin.pri'))) {
    throw "Root resources PRI (CursorFollowWin.pri) missing from publish — the app would fail to load XAML."
}

$resolved = (Resolve-Path $publishDir).Path
Write-Host "==> Publish OK: $resolved" -ForegroundColor Green
return $resolved
