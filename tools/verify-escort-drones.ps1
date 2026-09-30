[CmdletBinding()]
param(
    [int]$Port = 17671
)

$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'common.ps1')

if ($Port -lt 1024 -or $Port -gt 65535) {
    throw 'Port must be from 1024 through 65535.'
}

$godot = Get-SsfGodotExecutable
$logPath = New-SsfVerificationLogPath -Name 'escort-drones'
$ErrorActionPreference = 'Continue'
try {
    $combined = (& $godot --headless --path $SsfRepositoryRoot --log-file $logPath --script res://src/test/escort_drone_verifier.gd -- "--verification-port=$Port" 2>&1 | Out-String)
    $exitCode = $LASTEXITCODE
}
finally { $ErrorActionPreference = 'Stop' }
Assert-SsfGodotResult -Output $combined -ExitCode $exitCode -Name 'Escort drone verification' -ExpectedPattern 'LIVE_SUMMARY failures=0'
Write-Host 'Escort drone verification passed: live replication, cloak withdrawal and reveal over a hosted session.'
