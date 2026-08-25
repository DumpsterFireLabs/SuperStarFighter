[CmdletBinding()]
param(
    [ValidateRange(2, 32)]
    [int]$ClientCount = 2,
    [ValidateRange(15, 300)]
    [int]$DurationSeconds = 20,
    [ValidateRange(1024, 65535)]
    [int]$Port = 17348
)

$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'common.ps1')
$godot = Get-SsfGodotExecutable
$logRoot = Join-Path $SsfToolsRoot 'smoke-verification'
Assert-SsfPathWithinTools -Path $logRoot
New-Item -ItemType Directory -Path $logRoot -Force | Out-Null
$processes = [System.Collections.Generic.List[System.Diagnostics.Process]]::new()
$botNames = 1..$ClientCount | ForEach-Object { 'Smoke{0:D2}' -f $_ }
foreach ($name in @('server') + $botNames) {
    foreach ($suffix in @('out.log', 'err.log', 'godot.log')) {
        Remove-Item -LiteralPath (Join-Path $logRoot "$name.$suffix") -Force -ErrorAction SilentlyContinue
    }
}

function Start-SsfSmokeProcess {
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

function Get-SsfSmokeOutput {
    param([string]$Name)
    $content = ''
    foreach ($suffix in @('out.log', 'err.log')) {
        $path = Join-Path $logRoot "$Name.$suffix"
        if (Test-Path -LiteralPath $path) { $content += Get-Content -LiteralPath $path -Raw }
    }
    return $content
}

function Wait-SsfSmokeCondition {
    param([scriptblock]$Condition, [string]$Description, [int]$TimeoutSeconds = 30)
    $deadline = [DateTime]::UtcNow.AddSeconds($TimeoutSeconds)
    while ([DateTime]::UtcNow -lt $deadline) {
        if (& $Condition) { return }
        Start-Sleep -Milliseconds 250
    }
    throw "Timed out waiting for $Description."
}

try {
    $serverDuration = $DurationSeconds + 10
    $server = Start-SsfSmokeProcess -Name 'server' -UserArguments @(
        '--server', "--port=$Port", "--max-players=$ClientCount", '--rounds-to-win=2', '--test-fast-match',
        "--test-server-duration=$serverDuration", '--test-match-seed=6106'
    )
    Start-Sleep -Milliseconds 600
    for ($index = 0; $index -lt $botNames.Count; $index++) {
        $arguments = @("--bot-client=$($botNames[$index])", '--bot-randomized', '--host=127.0.0.1', "--port=$Port")
        if ($index -eq 0) { $arguments += "--bot-start-at=$ClientCount" }
        Start-SsfSmokeProcess -Name $botNames[$index] -UserArguments $arguments | Out-Null
        Start-Sleep -Milliseconds 80
    }
    Wait-SsfSmokeCondition -Description "all $ClientCount smoke clients" -TimeoutSeconds 45 -Condition {
        foreach ($name in $botNames) {
            if (-not (Get-SsfSmokeOutput $name).Contains('SSF_BOT_WELCOME')) { return $false }
        }
        return $true
    }
    Wait-SsfSmokeCondition -Description 'smoke combat and metrics' -TimeoutSeconds 25 -Condition {
        $serverText = Get-SsfSmokeOutput 'server'
        return $serverText.Contains('"state":"ACTIVE_HEAT"') -and $serverText.Contains('"event":"simulation_metrics"')
    }
    Wait-SsfSmokeCondition -Description 'clean smoke server shutdown' -TimeoutSeconds ($serverDuration + 15) -Condition { $server.HasExited }
    Start-Sleep -Seconds 1
    $serverText = Get-SsfSmokeOutput 'server'
    if (-not $serverText.Contains('"connected_peers":' + $ClientCount)) { throw "Metrics never observed all $ClientCount clients." }
    if (-not $serverText.Contains('"event":"server_shutdown"')) { throw 'Smoke server did not log a clean shutdown.' }
    $combined = $serverText
    foreach ($name in $botNames) { $combined += Get-SsfSmokeOutput $name }
    $unexpectedErrors = $combined -split "`r?`n" | Where-Object {
        ($_ -match '^(SCRIPT ERROR:|ERROR:)') -and (-not $_.Contains('Failed to read the root certificate store.'))
    }
    if ($unexpectedErrors) { throw "Smoke verification emitted unexpected errors: $($unexpectedErrors -join ' | ')" }
    if ($server.ExitCode -ne 0) { throw "Smoke server exited with code $($server.ExitCode)." }
    Write-Host "Smoke verification passed: $ClientCount real ENet clients drafted, fought, received snapshots, produced metrics, and shut down cleanly."
}
finally {
    foreach ($process in $processes) {
        if (-not $process.HasExited) { Stop-Process -Id $process.Id -Force }
    }
}
