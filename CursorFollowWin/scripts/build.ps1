#requires -Version 7.0
<#
.SYNOPSIS
    Restore, build, and (optionally) test the CursorFollowWin solution.

.DESCRIPTION
    The developer "is it green?" gate: builds the whole .slnx for one platform/configuration
    and runs the xUnit tests in tests/CursorFollowWin.Tests. Intended for local use and CI.

.PARAMETER Configuration
    Debug (default) or Release.

.PARAMETER SkipTests
    Build only; do not run the test project.

.EXAMPLE
    ./scripts/build.ps1 -Configuration Release
#>
[CmdletBinding()]
param(
    [ValidateSet('Debug', 'Release')]
    [string]$Configuration = 'Debug',
    [switch]$SkipTests
)

$ErrorActionPreference = 'Stop'
$repo = Split-Path -Parent $PSScriptRoot
$sln = Join-Path $repo 'CursorFollowWin.slnx'
$testProj = Join-Path $repo 'tests/CursorFollowWin.Tests/CursorFollowWin.Tests.csproj'

# Build the whole solution. No -p:Platform here: the .slnx mixes per-project platforms (the app
# is x64/x86/ARM64, the test project is AnyCPU), so forcing one platform across the solution is
# rejected as an invalid solution configuration. Each project builds with its own default.
Write-Host "==> Building solution ($Configuration)" -ForegroundColor Cyan
dotnet build $sln -c $Configuration --nologo
if ($LASTEXITCODE -ne 0) { throw "Build failed (exit $LASTEXITCODE)." }

if ($SkipTests) {
    Write-Host "==> Build OK (tests skipped)" -ForegroundColor Green
    return
}

# The test project is plain net10.0 (no platform); build/run it without the Platform flag.
Write-Host "==> Running tests" -ForegroundColor Cyan
dotnet test $testProj -c $Configuration --nologo
if ($LASTEXITCODE -ne 0) { throw "Tests failed (exit $LASTEXITCODE)." }

Write-Host "==> Build + tests green" -ForegroundColor Green
