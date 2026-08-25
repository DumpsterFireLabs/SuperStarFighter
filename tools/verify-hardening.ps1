[CmdletBinding()]
param(
    [ValidateRange(1024, 65535)]
    [int]$Port = 17347
)

$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'common.ps1')

$godot = Get-SsfGodotExecutable
$logRoot = Join-Path $SsfToolsRoot 'hardening-verification'
Assert-SsfPathWithinTools -Path $logRoot
New-Item -ItemType Directory -Path $logRoot -Force | Out-Null
$names = @('server', 'alpha', 'beta', 'malformed', 'excessive')
foreach ($name in $names) {
    foreach ($suffix in @('out.log', 'err.log', 'godot.log')) {
        Remove-Item -LiteralPath (Join-Path $logRoot "$name.$suffix") -Force -ErrorAction SilentlyContinue
    }
}
$processes = [System.Collections.Generic.List[System.Diagnostics.Process]]::new()

function Start-SsfHardeningProcess {
    param([string]$Name, [string[]]$UserArguments)
    $stdout = Join-Path $logRoot "$Name.out.log"
    $stderr = Join-Path $logRoot "$Name.err.log"
    $godotLog = (Join-Path $logRoot "$Name.godot.log") -replace '\\', '/'
    $arguments = @('--headless', '--path', '.', '--log-file', $godotLog, '--') + $UserArguments
    $process = Start-Process -FilePath $godot -ArgumentList $arguments -WorkingDirectory $SsfRepositoryRoot `
        -RedirectStandardOutput $stdout -RedirectStandardError $stderr -WindowStyle Hidden -PassThru
    $processes.Add($process)
    return $process
}

function Get-SsfHardeningOutput {
    param([string]$Name)
    $content = ''
    foreach ($suffix in @('out.log', 'err.log')) {
        $path = Join-Path $logRoot "$Name.$suffix"
        if (Test-Path -LiteralPath $path) { $content += Get-Content -LiteralPath $path -Raw }
    }
    return $content
}

function Wait-SsfHardeningCondition {
    param([scriptblock]$Condition, [string]$Description, [int]$TimeoutSeconds = 20)
    $deadline = [DateTime]::UtcNow.AddSeconds($TimeoutSeconds)
    while ([DateTime]::UtcNow -lt $deadline) {
        if (& $Condition) { return }
        Start-Sleep -Milliseconds 200
    }
    throw "Timed out waiting for $Description."
}

try {
    $server = Start-SsfHardeningProcess -Name 'server' -UserArguments @(
        '--server', "--port=$Port", '--max-players=4', '--rounds-to-win=2', '--test-fast-match', '--test-server-duration=35'
    )
    Start-Sleep -Milliseconds 600
    $alpha = Start-SsfHardeningProcess -Name 'alpha' -UserArguments @('--bot-client=Alpha', '--host=127.0.0.1', "--port=$Port")
    $beta = Start-SsfHardeningProcess -Name 'beta' -UserArguments @('--bot-client=Beta', '--host=127.0.0.1', "--port=$Port")
    Wait-SsfHardeningCondition -Description 'healthy clients entering combat' -Condition {
        (Get-SsfHardeningOutput 'alpha').Contains('SSF_BOT_STATE state=ACTIVE_HEAT') -and
        (Get-SsfHardeningOutput 'beta').Contains('SSF_BOT_STATE state=ACTIVE_HEAT')
    }

    $malformed = Start-SsfHardeningProcess -Name 'malformed' -UserArguments @(
        '--bot-client=Malformed', '--bot-malformed-input', '--host=127.0.0.1', "--port=$Port"
    )
    Wait-SsfHardeningCondition -Description 'malformed peer isolation' -Condition {
        (Get-SsfHardeningOutput 'malformed').Contains('SSF_BOT_REJECTED reason=MALFORMED_TRAFFIC') -and
        (Get-SsfHardeningOutput 'server').Contains('"event":"traffic_peer_isolated"')
    }

    $excessive = Start-SsfHardeningProcess -Name 'excessive' -UserArguments @(
        '--bot-client=Excessive', '--bot-excessive-input', '--host=127.0.0.1', "--port=$Port"
    )
    Wait-SsfHardeningCondition -Description 'excessive peer isolation' -TimeoutSeconds 12 -Condition {
        (Get-SsfHardeningOutput 'excessive').Contains('SSF_BOT_REJECTED reason=MALFORMED_TRAFFIC')
    }
    Wait-SsfHardeningCondition -Description 'healthy clients continuing after malicious traffic' -TimeoutSeconds 15 -Condition {
        (Get-SsfHardeningOutput 'alpha').Contains('SSF_BOT_HEARTBEAT') -and
        (Get-SsfHardeningOutput 'beta').Contains('SSF_BOT_HEARTBEAT') -and
        -not $server.HasExited
    }
    Wait-SsfHardeningCondition -Description 'clean hardening server shutdown' -TimeoutSeconds 40 -Condition { $server.HasExited }

    $serverText = Get-SsfHardeningOutput 'server'
    foreach ($marker in @('"event":"server_started"', '"event":"match_seed"', '"event":"match_event"', '"event":"simulation_metrics"', '"event":"server_shutdown"')) {
        if (-not $serverText.Contains($marker)) { throw "Structured server log is missing $marker." }
    }
    if ($serverText.Contains('127.0.0.1') -or $serverText -match '"ip"\s*:') {
        throw 'Server logs contain a client address, which is forbidden by the logging contract.'
    }
    $combined = $serverText + (Get-SsfHardeningOutput 'alpha') + (Get-SsfHardeningOutput 'beta') + `
        (Get-SsfHardeningOutput 'malformed') + (Get-SsfHardeningOutput 'excessive')
    $unexpectedErrors = $combined -split "`r?`n" | Where-Object {
        ($_ -match '^(SCRIPT ERROR:|ERROR:)') -and (-not $_.Contains('Failed to read the root certificate store.'))
    }
    if ($unexpectedErrors) { throw "Hardening verification emitted unexpected errors: $($unexpectedErrors -join ' | ')" }
    if ($server.ExitCode -ne 0) { throw "Hardening server exited with code $($server.ExitCode)." }
    Write-Host 'Hardening verification passed: malformed and excessive peers were isolated while healthy clients continued; bounded structured logs and clean shutdown verified.'
}
finally {
    foreach ($process in $processes) {
        if (-not $process.HasExited) { Stop-Process -Id $process.Id -Force }
    }
}
