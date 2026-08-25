[CmdletBinding()]
param(
    [int]$Port = 17659
)

$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'common.ps1')

if ($Port -lt 1024 -or $Port -gt 65535) {
    throw 'Port must be from 1024 through 65535.'
}

$godot = Get-SsfGodotExecutable
$output = & $godot --headless --path $SsfRepositoryRoot --script res://src/test/local_host_verifier.gd -- "--verification-port=$Port" 2>&1
$exitCode = $LASTEXITCODE
$combined = $output -join [Environment]::NewLine
if ($exitCode -ne 0 -or -not $combined.Contains('SSF_LOCAL_HOST_OK=connected_admitted_discovered') -or $combined.Contains('SCRIPT ERROR:')) {
    throw "Local host verification failed (exit $exitCode):`n$combined"
}
Write-Host "Local host verification passed: in-process authority started, loopback client was admitted, LAN discovery found the server, and both sides shut down cleanly."
