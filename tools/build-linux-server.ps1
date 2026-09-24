[CmdletBinding()]
param(
    [ValidateSet('x86_64', 'arm64')][string]$Architecture = 'x86_64',
    [switch]$SkipFoundationGate
)
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'common.ps1')
Assert-SsfShippingPolicy
if (-not $SkipFoundationGate) {
    & (Join-Path $PSScriptRoot 'verify-foundation.ps1')
    if ($LASTEXITCODE -ne 0) { throw 'Foundation verification failed.' }
}
$buildRoot = Join-Path $SsfRepositoryRoot "$($SsfRelease.directory)/server-linux-$Architecture"
New-Item -ItemType Directory -Path $buildRoot -Force | Out-Null
$serverPath = Join-Path $buildRoot "SuperStarFighter-Server.$Architecture"
$godot = Get-SsfGodotExecutable
$ErrorActionPreference = 'Continue'
$output = (& $godot --headless --path $SsfRepositoryRoot --export-release "Linux $Architecture Dedicated Server" $serverPath 2>&1 | Out-String)
$exportExit = $LASTEXITCODE
$ErrorActionPreference = 'Stop'
Write-Host $output
Assert-SsfGodotResult -Output $output -ExitCode $exportExit -Name 'Linux dedicated server export'
& python (Join-Path $PSScriptRoot 'audit-package.py') $serverPath --server --output (Join-Path $buildRoot 'package-audit.json')
if ($LASTEXITCODE -ne 0) { throw 'Server resource audit failed.' }
& python (Join-Path $PSScriptRoot 'package-linux-server.py') $Architecture
if ($LASTEXITCODE -ne 0) { throw 'Linux server packaging failed.' }
