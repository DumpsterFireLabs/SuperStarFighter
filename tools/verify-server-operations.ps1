[CmdletBinding()]
param(
    [ValidateRange(1024, 65535)][int]$Port = 17830,
    [ValidateRange(1024, 65535)][int]$AdminPort = 17831,
    [string]$ServerExecutable
)

$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'common.ps1')
if ($Port -eq $AdminPort) { throw 'Use distinct gameplay and admin ports.' }
$logRoot = Join-Path $SsfToolsRoot ('server operations-' + [Guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $logRoot -Force | Out-Null
$lobbySecret = Join-Path $logRoot 'lobby password.txt'
$adminSecret = Join-Path $logRoot 'admin password.txt'
[IO.File]::WriteAllText($lobbySecret, 'operations-lobby-test')
[IO.File]::WriteAllText($adminSecret, 'operations-admin-test')
$logFile = Join-Path $logRoot 'server health.log'
$launcher = Join-Path $PSScriptRoot 'start-server.ps1'
$adminTool = Join-Path $PSScriptRoot 'admin.ps1'
if ($ServerExecutable) {
    $ServerExecutable = (Resolve-Path -LiteralPath $ServerExecutable).Path
    $launcher = Join-Path (Split-Path -Parent $ServerExecutable) 'start-server.ps1'
    $adminTool = Join-Path (Split-Path -Parent $ServerExecutable) 'admin.ps1'
}
$shellExecutable = (Get-Process -Id $PID).Path
$arguments = @('-NoProfile', '-NonInteractive', '-File', $launcher, '-NonInteractive',
    '-Port', "$Port", '-AdminPort', "$AdminPort", '-PasswordFile', $lobbySecret,
    '-AdminPasswordFile', $adminSecret, '-LogFile', $logFile)
if ($ServerExecutable) { $arguments += @('-ServerExecutable', $ServerExecutable) }
# Start-Process joins its argument array on Windows. Quote each controlled
# argument to exercise installation, password and log paths containing spaces.
$quotedArguments = @($arguments | ForEach-Object { '"' + $_ + '"' })
$process = $null

function Invoke-OperationsAdmin {
    param([string]$Command)
    $output = & $adminTool -Port $AdminPort -Command $Command -AdminPasswordFile $adminSecret -NonInteractive -TimeoutSeconds 3
    if ($LASTEXITCODE -ne 0) { throw "Admin $Command failed." }
    return ($output | Out-String | ConvertFrom-Json)
}

try {
    $process = Start-Process -FilePath $shellExecutable -ArgumentList $quotedArguments -WorkingDirectory $logRoot `
        -WindowStyle Hidden -PassThru -RedirectStandardOutput (Join-Path $logRoot 'launcher.out.log') `
        -RedirectStandardError (Join-Path $logRoot 'launcher.err.log')
    $process.EnableRaisingEvents = $true
    $null = $process.Handle
    $deadline = [DateTime]::UtcNow.AddSeconds(30)
    do {
        if ($process.HasExited) { throw "Launcher exited before health was available. See $logRoot" }
        $text = if (Test-Path -LiteralPath $logFile) { Get-Content -LiteralPath $logFile -Raw } else { '' }
        if ($text -match '"event":"simulation_metrics"') { break }
        if ([DateTime]::UtcNow -ge $deadline) { throw 'Idle server failed to publish its health window.' }
        Start-Sleep -Milliseconds 250
    } while ($true)
    $status = Invoke-OperationsAdmin 'status'
    if (-not $status.ok -or $status.human_count -ne 0 -or $status.match_active -or
        $status.metrics.physics_ticks_per_second -lt 57 -or $status.metrics_age_seconds -gt 5) {
        throw 'Idle admin health was stale, unavailable or below the tick-rate budget.'
    }
    $status | ConvertTo-Json -Depth 12 | Set-Content -LiteralPath (Join-Path $logRoot 'status.json') -Encoding UTF8
	$engine = Get-SsfGodotExecutable
	$probeOutput = (& $engine --headless --path $SsfRepositoryRoot --script res://tests/integration/admin_connection_probe.gd -- "--admin-port=$AdminPort" "--admin-password-file=$adminSecret" 2>&1 | Out-String)
	$probeExit = $LASTEXITCODE
	if ($probeExit -ne 0 -or $probeOutput -notmatch 'ADMIN_CLIENT_PROBE=passed') { throw "In-game admin transport probe failed: $probeOutput" }
	$inGameProbeOutput = (& $engine --headless --path $SsfRepositoryRoot --script res://tests/integration/in_game_admin_probe.gd 2>&1 | Out-String)
	$inGameProbeExit = $LASTEXITCODE
	if ($inGameProbeExit -ne 0 -or $inGameProbeOutput -notmatch 'IN_GAME_ADMIN_PROBE=passed') { throw "In-game password administration probe failed: $inGameProbeOutput" }
	$players = Invoke-OperationsAdmin 'players'
	if (-not $players.ok -or @($players.players).Count -ne 0) { throw 'Idle player list was incorrect.' }
	$restartOutput = & $adminTool -Port $AdminPort -Command restart-match -AdminPasswordFile $adminSecret -NonInteractive -TimeoutSeconds 3
	if ($LASTEXITCODE -ne 1 -or ($restartOutput | Out-String | ConvertFrom-Json).ok) { throw 'Idle match restart should be rejected.' }
    $shutdown = Invoke-OperationsAdmin 'shutdown'
    if (-not $shutdown.shutdown -or -not $process.WaitForExit(10000)) { throw 'Admin shutdown did not stop the launcher and server.' }
    $process.WaitForExit()
    $text = Get-Content -LiteralPath $logFile -Raw
    Assert-SsfGodotResult -Output $text -ExitCode $process.ExitCode -Name 'Server operations' -ExpectedPattern 'SSF_SERVER_GRACEFUL_SHUTDOWN=admin'
    if ([regex]::Matches($text, '"event":"server_shutdown"').Count -ne 1) { throw 'Expected exactly one server shutdown.' }
    if ($text.Contains('operations-lobby-test') -or $text.Contains('operations-admin-test')) { throw 'Operational logs exposed a test credential.' }
    Write-Host "Server operations passed: unattended launcher, paths with spaces, idle health, in-game password administration, authenticated status and graceful shutdown. Evidence: $logRoot"
}
finally {
    if ($null -ne $process -and -not $process.HasExited) {
        try { $null = Invoke-OperationsAdmin 'shutdown' } catch { Write-Warning "Admin cleanup failed: $_" }
        $null = $process.WaitForExit(5000)
    }
    if ($null -ne $process -and -not $process.HasExited) {
        # Only the process tree created by this verification is eligible for cleanup.
        & taskkill.exe /PID $process.Id /T /F | Out-Null
    }
    Remove-Item -LiteralPath $lobbySecret, $adminSecret -Force
}
