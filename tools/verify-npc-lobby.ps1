[CmdletBinding()]
param(
    [ValidateRange(1024, 65535)]
    [int]$Port = 17346
)

$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'common.ps1')

$godot = Get-SsfGodotExecutable
$logRoot = Join-Path $SsfToolsRoot 'npc-lobby-verification'
Assert-SsfPathWithinTools -Path $logRoot
New-Item -ItemType Directory -Path $logRoot -Force | Out-Null
$knownLogs = foreach ($name in @('server', 'solo')) {
    Join-Path $logRoot "$name.out.log"
    Join-Path $logRoot "$name.err.log"
    Join-Path $logRoot "$name.godot.log"
}
Remove-Item -LiteralPath $knownLogs -Force -ErrorAction SilentlyContinue
$processes = [System.Collections.Generic.List[System.Diagnostics.Process]]::new()

function Start-SsfNpcProcess {
    param(
        [Parameter(Mandatory = $true)][string]$Name,
        [Parameter(Mandatory = $true)][string[]]$UserArguments
    )
    $arguments = @(
        '--headless', '--path', '.', '--log-file',
        ((Join-Path $logRoot "$Name.godot.log") -replace '\\', '/'), '--'
    ) + $UserArguments
    $process = Start-Process -FilePath $godot `
        -ArgumentList $arguments `
        -WorkingDirectory $SsfRepositoryRoot `
        -RedirectStandardOutput (Join-Path $logRoot "$Name.out.log") `
        -RedirectStandardError (Join-Path $logRoot "$Name.err.log") `
        -WindowStyle Hidden `
        -PassThru
    $processes.Add($process)
    return $process
}

function Get-SsfNpcOutput {
    param([Parameter(Mandatory = $true)][string]$Name)
    $text = ''
    foreach ($extension in @('out.log', 'err.log')) {
        $path = Join-Path $logRoot "$Name.$extension"
        if (Test-Path -LiteralPath $path) {
            $text += Get-Content -LiteralPath $path -Raw
        }
    }
    return $text
}

function Wait-SsfNpcCondition {
    param(
        [Parameter(Mandatory = $true)][scriptblock]$Condition,
        [Parameter(Mandatory = $true)][string]$Description,
        [int]$TimeoutSeconds = 15
    )
    $deadline = [DateTime]::UtcNow.AddSeconds($TimeoutSeconds)
    while ([DateTime]::UtcNow -lt $deadline) {
        if (& $Condition) { return }
        Start-Sleep -Milliseconds 200
    }
    throw "Timed out waiting for $Description."
}

try {
    $server = Start-SsfNpcProcess -Name 'server' -UserArguments @(
        '--server', "--port=$Port", '--max-players=32', '--rounds-to-win=1',
        '--test-fast-match', '--test-match-seed=5150', '--test-server-duration=12'
    )
    Start-Sleep -Milliseconds 600
    $solo = Start-SsfNpcProcess -Name 'solo' -UserArguments @(
        '--bot-client=SoloPilot', '--bot-enable-npcs', '--bot-player-limit=4',
        '--host=127.0.0.1', "--port=$Port"
    )

    Wait-SsfNpcCondition -Description 'solo force-start with three authoritative NPCs' -Condition {
        $serverText = Get-SsfNpcOutput -Name 'server'
        $soloText = Get-SsfNpcOutput -Name 'solo'
        return (
            ([regex]::Matches($serverText, '"event":"npc_added"')).Count -eq 3 -and
            $soloText.Contains('players=4') -and
            $soloText.Contains('limit=4 npcs=3 enabled=true') -and
            $soloText.Contains('SSF_BOT_DRAFT_OFFER cards=5') -and
            $soloText.Contains('SSF_BOT_STATE state=ACTIVE_HEAT') -and
            $soloText.Contains('SSF_BOT_SNAPSHOT')
        )
    }

    $serverText = Get-SsfNpcOutput -Name 'server'
    $soloText = Get-SsfNpcOutput -Name 'solo'
    if (-not $serverText.Contains('"event":"match_event","event_type":"MATCH_START_ACCEPTED"')) {
        throw 'The solo force-start did not create an authoritative match.'
    }
    $combined = $serverText + $soloText
    $unexpectedErrors = $combined -split "`r?`n" | Where-Object {
        ($_ -match '^(SCRIPT ERROR:|ERROR:)') -and
        (-not $_.Contains('Failed to read the root certificate store.'))
    }
    if ($unexpectedErrors) {
        throw "NPC lobby verification emitted unexpected Godot errors: $($unexpectedErrors -join ' | ')"
    }

    Wait-SsfNpcCondition -Description 'clean NPC server shutdown' -TimeoutSeconds 15 -Condition {
        $server.HasExited -and (Get-SsfNpcOutput -Name 'server').Contains('SSF_SERVER_GRACEFUL_SHUTDOWN=test_duration')
    }
    if (-not (Get-SsfNpcOutput -Name 'server').Contains('"event":"server_shutdown"')) {
        throw 'Clean ENet shutdown was not logged.'
    }
    Write-Host 'NPC lobby verification passed: leader limit, NPC fill, solo force-start, draft, snapshots, combat, and clean shutdown.'
}
finally {
    foreach ($process in $processes) {
        if (-not $process.HasExited) {
            Stop-Process -Id $process.Id -Force -ErrorAction SilentlyContinue
        }
    }
}
