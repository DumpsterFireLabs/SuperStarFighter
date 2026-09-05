$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'common.ps1')

$godot = Get-SsfGodotExecutable
$clientLog = New-SsfVerificationLogPath -Name 'client'
$clientStarted = [DateTime]::UtcNow.ToString('o')
Write-Host "Client log: $clientLog"
& $godot --path $SsfRepositoryRoot --log-file $clientLog
$clientExitCode = $LASTEXITCODE
@{
    started_utc = $clientStarted
    exited_utc = [DateTime]::UtcNow.ToString('o')
    exit_code = $clientExitCode
    godot_log = $clientLog
} | ConvertTo-Json | Set-Content -LiteralPath ($clientLog + '.exit.json') -Encoding UTF8
if ($clientExitCode -ne 0) { Write-Warning "Client exited with code $clientExitCode. See $clientLog" }
exit $clientExitCode
