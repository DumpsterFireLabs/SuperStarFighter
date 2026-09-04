[CmdletBinding()]
param(
    [ValidateRange(2, 32)]
    [int]$ClientCount = 32,
    [ValidateRange(60, 1800)]
    [int]$DurationSeconds = 600,
    [ValidateRange(1024, 65535)]
    [int]$Port = 17349
)

$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'common.ps1')
$godot = Get-SsfGodotExecutable
$logRoot = Join-Path $SsfToolsRoot 'soak-verification'
Assert-SsfPathWithinTools -Path $logRoot
New-Item -ItemType Directory -Path $logRoot -Force | Out-Null
$processes = [System.Collections.Generic.List[System.Diagnostics.Process]]::new()
$clientProcesses = @{}
$botNames = 1..$ClientCount | ForEach-Object { 'Load{0:D2}' -f $_ }
$allNames = @('server', 'LateSpectator') + $botNames
foreach ($name in $allNames) {
    foreach ($suffix in @('out.log', 'err.log', 'godot.log')) {
        Remove-Item -LiteralPath (Join-Path $logRoot "$name.$suffix") -Force -ErrorAction SilentlyContinue
    }
}
Remove-Item -LiteralPath (Join-Path $logRoot 'summary.json') -Force -ErrorAction SilentlyContinue

function Start-SsfSoakProcess {
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

function Get-SsfSoakOutput {
    param([string]$Name)
    $content = ''
    foreach ($suffix in @('out.log', 'err.log')) {
        $path = Join-Path $logRoot "$Name.$suffix"
        if (Test-Path -LiteralPath $path) { $content += Get-Content -LiteralPath $path -Raw }
    }
    return $content
}

function Wait-SsfSoakCondition {
    param([scriptblock]$Condition, [string]$Description, [int]$TimeoutSeconds = 60)
    $deadline = [DateTime]::UtcNow.AddSeconds($TimeoutSeconds)
    while ([DateTime]::UtcNow -lt $deadline) {
        if (& $Condition) { return }
        Start-Sleep -Milliseconds 300
    }
    throw "Timed out waiting for $Description."
}

function Get-SsfJsonEvents {
    param([string]$Text)
    $events = [System.Collections.Generic.List[object]]::new()
    foreach ($line in ($Text -split "`r?`n")) {
        if (-not $line.StartsWith('{')) { continue }
        try { $events.Add(($line | ConvertFrom-Json)) } catch { }
    }
    return @($events)
}

try {
    $serverDuration = $DurationSeconds + 45
    Write-Host "Starting $ClientCount-client ENet soak for at least $DurationSeconds seconds."
    $server = Start-SsfSoakProcess -Name 'server' -UserArguments @(
        '--server', '--password=test-lobby', "--port=$Port", "--max-players=$ClientCount", '--rounds-to-win=5', '--test-fast-match',
        "--test-server-duration=$serverDuration", '--test-match-seed=610632'
    )
    Start-Sleep -Milliseconds 800
    for ($index = 0; $index -lt $botNames.Count; $index++) {
        $name = $botNames[$index]
        $arguments = @("--bot-client=$name", '--password=test-lobby', '--bot-randomized', '--host=127.0.0.1', "--port=$Port")
        if ($index -eq 0) { $arguments += "--bot-start-at=$ClientCount" }
        $clientProcesses[$name] = Start-SsfSoakProcess -Name $name -UserArguments $arguments
        Start-Sleep -Milliseconds 100
    }
    Wait-SsfSoakCondition -Description "all $ClientCount initial clients" -TimeoutSeconds 75 -Condition {
        foreach ($name in $botNames) {
            if (-not (Get-SsfSoakOutput $name).Contains('SSF_BOT_WELCOME')) { return $false }
        }
        return $true
    }
    Write-Host "All $ClientCount initial clients connected."
    Wait-SsfSoakCondition -Description '32-participant combat' -TimeoutSeconds 40 -Condition {
        (Get-SsfSoakOutput 'server').Contains('"state":"ACTIVE_HEAT"')
    }
    Wait-SsfSoakCondition -Description 'overtime activation' -TimeoutSeconds 20 -Condition {
        (Get-SsfSoakOutput 'server').Contains('"event":"overtime_started"')
    }

    $disconnectName = $botNames[$botNames.Count - 1]
    $disconnectOutput = Get-SsfSoakOutput $disconnectName
    $peerMatch = [regex]::Match($disconnectOutput, 'SSF_BOT_WELCOME peer_id=(\d+)')
    if (-not $peerMatch.Success) { throw "Could not identify $disconnectName for the combat disconnect scenario." }
    $disconnectedPeerId = [int]$peerMatch.Groups[1].Value
    Stop-Process -Id $clientProcesses[$disconnectName].Id -Force
    Wait-SsfSoakCondition -Description 'authoritative combat disconnect removal' -Condition {
        $events = Get-SsfJsonEvents (Get-SsfSoakOutput 'server')
        return @($events | Where-Object { $_.event -eq 'peer_left' -and $_.peer_id -eq $disconnectedPeerId }).Count -gt 0
    }
    Write-Host "$disconnectName disconnected during combat and was removed authoritatively."

    $late = Start-SsfSoakProcess -Name 'LateSpectator' -UserArguments @(
        '--bot-client=LateSpectator', '--password=test-lobby', '--bot-randomized', '--host=127.0.0.1', "--port=$Port"
    )
    $clientProcesses['LateSpectator'] = $late
    Wait-SsfSoakCondition -Description 'late spectator admission' -Condition {
        $events = Get-SsfJsonEvents (Get-SsfSoakOutput 'server')
        return (Get-SsfSoakOutput 'LateSpectator').Contains('SSF_BOT_WELCOME') -and
            @($events | Where-Object { $_.event -eq 'peer_joined' -and $_.display_name -eq 'LateSpectator' -and $_.spectator -eq $true }).Count -gt 0
    }
    Write-Host 'Late spectator admitted without participant authority.'

    $nextProgress = [DateTime]::UtcNow.AddSeconds(30)
    while (-not $server.HasExited) {
        if ([DateTime]::UtcNow -ge $nextProgress) {
            $serverEvents = Get-SsfJsonEvents (Get-SsfSoakOutput 'server')
            $metricCount = @($serverEvents | Where-Object { $_.event -eq 'simulation_metrics' }).Count
            Write-Host "Soak active: $metricCount metric windows captured."
            $nextProgress = [DateTime]::UtcNow.AddSeconds(30)
        }
        Start-Sleep -Seconds 1
    }
    Start-Sleep -Seconds 2
    $serverText = Get-SsfSoakOutput 'server'
    $events = Get-SsfJsonEvents $serverText
    $metrics = @($events | Where-Object { $_.event -eq 'simulation_metrics' })
    $minimumMetricWindows = [Math]::Floor($DurationSeconds / 10)
    if ($metrics.Count -lt $minimumMetricWindows) { throw "Only $($metrics.Count) metric windows were captured; expected at least $minimumMetricWindows." }
    $maxP95 = ($metrics | Measure-Object -Property p95_simulation_usec -Maximum).Maximum
    $activeMetrics = @($metrics | Where-Object { $_.active_samples -gt 0 })
    if ($activeMetrics.Count -eq 0) { throw 'No active-combat frame timings were recorded.' }
    $maxActiveP95 = ($activeMetrics | Measure-Object -Property active_p95_usec -Maximum).Maximum
    if ($maxActiveP95 -ge 16667) { throw "Active full-server p95 exceeded 16.67 ms: $maxActiveP95 microseconds." }
    if ($maxP95 -ge 16667) { throw "Simulation p95 exceeded the 16.67 ms budget: $maxP95 microseconds." }
    if (@($metrics | Where-Object { $_.connected_peers -eq $ClientCount }).Count -eq 0) { throw "No metric window observed all $ClientCount connected clients." }
    if (@($metrics | Where-Object { $_.participant_records -gt $ClientCount -or $_.active_ships -gt $ClientCount -or $_.active_projectiles -gt 1024 }).Count -gt 0) {
        throw 'An authoritative entity collection exceeded its configured bound.'
    }
    if (@($metrics | Where-Object { $_.orphan_node_count -gt 0 }).Count -gt 0) { throw 'The server reported orphaned nodes during the soak.' }
    foreach ($property in @('active_projectiles', 'object_count', 'node_count', 'static_memory_bytes')) {
        $values = @($metrics | ForEach-Object { [long]($_.$property) })
        if ($values.Count -lt 6) { continue }
        $strictlyGrowing = $true
        for ($index = 1; $index -lt $values.Count; $index++) {
            if ($values[$index] -le $values[$index - 1]) { $strictlyGrowing = $false; break }
        }
        if ($strictlyGrowing) { throw "$property grew in every metric window, indicating an unbounded collection or allocation trend." }
    }
    if (@($events | Where-Object { $_.event -eq 'match_event' -and $_.PSObject.Properties.Name -contains 'state' -and $_.state -eq 'HEAT_RESULT' }).Count -eq 0) { throw 'The soak did not complete a heat.' }
    if (@($events | Where-Object { $_.event -eq 'overtime_started' }).Count -eq 0) { throw 'The soak did not exercise overtime.' }
    if (@($events | Where-Object { $_.event -eq 'server_shutdown' }).Count -ne 1) { throw 'The soak did not finish with one clean server shutdown.' }
    if ($serverText.Contains('127.0.0.1') -or $serverText -match '"ip"\s*:') { throw 'Server logs exposed a client address.' }

    $combined = $serverText
    foreach ($name in $allNames) { if ($name -ne 'server') { $combined += Get-SsfSoakOutput $name } }
    $unexpectedErrors = $combined -split "`r?`n" | Where-Object {
        ($_ -match '^(SCRIPT ERROR:|ERROR:)') -and (-not $_.Contains('Failed to read the root certificate store.'))
    }
    if ($unexpectedErrors) { throw "Soak emitted unexpected errors: $($unexpectedErrors -join ' | ')" }
    if ($server.ExitCode -ne 0) { throw "Soak server exited with code $($server.ExitCode)." }

    $shutdownDeadline = [DateTime]::UtcNow.AddSeconds(15)
    while ([DateTime]::UtcNow -lt $shutdownDeadline -and @($processes | Where-Object { -not $_.HasExited }).Count -gt 0) {
        Start-Sleep -Milliseconds 250
    }
    $remaining = @($processes | Where-Object { -not $_.HasExited })
    if ($remaining.Count -gt 0) { throw "$($remaining.Count) child processes remained after server shutdown." }

    $summary = [ordered]@{
        client_count = $ClientCount
        duration_seconds = $DurationSeconds
        metric_windows = $metrics.Count
        maximum_p95_simulation_usec = $maxP95
        maximum_p99_simulation_usec = ($metrics | Measure-Object -Property p99_simulation_usec -Maximum).Maximum
        maximum_active_p95_usec = $maxActiveP95
        maximum_active_p99_usec = ($activeMetrics | Measure-Object -Property active_p99_usec -Maximum).Maximum
        maximum_over_budget_percent = ($metrics | Measure-Object -Property over_budget_percent -Maximum).Maximum
        maximum_outbound_payload_bytes_per_window = ($metrics | Measure-Object -Property outbound_bytes -Maximum).Maximum
        mean_world_and_npc_usec = ($metrics | Measure-Object -Property mean_world_and_npc_usec -Average).Average
        mean_coordination_usec = ($metrics | Measure-Object -Property mean_coordination_usec -Average).Average
        mean_replication_usec = ($metrics | Measure-Object -Property mean_replication_usec -Average).Average
        timing_scope = 'Server physics callback including coordination, encoding and ENet enqueue/fan-out; excludes engine transport polling, OS delivery and client rendering.'
        maximum_active_projectiles = ($metrics | Measure-Object -Property active_projectiles -Maximum).Maximum
        maximum_object_count = ($metrics | Measure-Object -Property object_count -Maximum).Maximum
        maximum_static_memory_bytes = ($metrics | Measure-Object -Property static_memory_bytes -Maximum).Maximum
        overtime_events = @($events | Where-Object { $_.event -eq 'overtime_started' }).Count
        heat_results = @($events | Where-Object { $_.event -eq 'match_event' -and $_.PSObject.Properties.Name -contains 'state' -and $_.state -eq 'HEAT_RESULT' }).Count
        combat_disconnect_peer_id = $disconnectedPeerId
        late_spectator = $true
        clean_shutdown = $true
    }
    $summary | ConvertTo-Json | Set-Content -LiteralPath (Join-Path $logRoot 'summary.json') -Encoding UTF8
    Write-Host "Soak verification passed: $ClientCount initial clients, $($metrics.Count) windows, max p95 $maxP95 us, overtime, combat disconnect, late spectator, bounded entities, and clean shutdown."
}
finally {
    foreach ($process in $processes) {
        if (-not $process.HasExited) { Stop-Process -Id $process.Id -Force }
    }
}
