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
$logPath = New-SsfVerificationLogPath -Name 'local-host'
$ErrorActionPreference = 'Continue'
try {
    $combined = (& $godot --headless --path $SsfRepositoryRoot --log-file $logPath --script res://src/test/local_host_verifier.gd -- "--verification-port=$Port" 2>&1 | Out-String)
    $exitCode = $LASTEXITCODE
}
finally { $ErrorActionPreference = 'Stop' }
Assert-SsfGodotResult -Output $combined -ExitCode $exitCode -Name 'Local host verification' -ExpectedPattern 'SSF_LOCAL_HOST_OK=connected_admitted_discovered.*reconnects=1'
Write-Host 'Local host verification passed: admission, LAN discovery, global pause/resume, teardown and reconnect on the same client.'
