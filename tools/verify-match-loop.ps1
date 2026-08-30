[CmdletBinding()]
param(
    [ValidateRange(1024, 65535)]
    [int]$Port = 17345
)

$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'common.ps1')

$godot = Get-SsfGodotExecutable
$logRoot = Join-Path $SsfToolsRoot 'match-loop-verification'
Assert-SsfPathWithinTools -Path $logRoot
New-Item -ItemType Directory -Path $logRoot -Force | Out-Null

$knownLogs = foreach ($name in @('server', 'alpha', 'beta')) {
    Join-Path $logRoot "$name.out.log"
    Join-Path $logRoot "$name.err.log"
    Join-Path $logRoot "$name.godot.log"
}
Remove-Item -LiteralPath $knownLogs -Force -ErrorAction SilentlyContinue
$processes = [System.Collections.Generic.List[System.Diagnostics.Process]]::new()

function Start-SsfMatchProcess {
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

function Get-SsfMatchOutput {
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

function Wait-SsfMatchCondition {
    param(
        [Parameter(Mandatory = $true)][scriptblock]$Condition,
        [Parameter(Mandatory = $true)][string]$Description,
        [int]$TimeoutSeconds = 35
    )
    $deadline = [DateTime]::UtcNow.AddSeconds($TimeoutSeconds)
    while ([DateTime]::UtcNow -lt $deadline) {
        if (& $Condition) { return }
        Start-Sleep -Milliseconds 200
    }
    throw "Timed out waiting for $Description."
}

try {
    $server = Start-SsfMatchProcess -Name 'server' -UserArguments @(
        '--server', '--password=test-lobby', "--port=$Port", '--max-players=2', '--rounds-to-win=1',
        '--auto-start', '--test-fast-match', '--test-match-seed=4242',
        '--test-server-duration=35'
    )
    Start-Sleep -Milliseconds 600
    $alpha = Start-SsfMatchProcess -Name 'alpha' -UserArguments @(
        '--bot-client=Alpha', '--password=test-lobby', '--host=127.0.0.1', "--port=$Port"
    )
    Start-Sleep -Milliseconds 350
    $beta = Start-SsfMatchProcess -Name 'beta' -UserArguments @(
        '--bot-client=Beta', '--password=test-lobby', '--bot-passive', '--bot-draft-timeout',
        '--host=127.0.0.1', "--port=$Port"
    )

    Wait-SsfMatchCondition -Description 'two complete matches and lobby resets' -Condition {
        $alphaText = Get-SsfMatchOutput -Name 'alpha'
        return (
            ([regex]::Matches($alphaText, 'SSF_BOT_MATCH_RESULT')).Count -ge 2 -and
            ([regex]::Matches($alphaText, 'SSF_BOT_LOBBY_RETURN')).Count -ge 2
        )
    }

    $alphaText = Get-SsfMatchOutput -Name 'alpha'
    $betaText = Get-SsfMatchOutput -Name 'beta'
    $serverText = Get-SsfMatchOutput -Name 'server'
    if (-not $betaText.Contains('SSF_BOT_DRAFT_OFFER cards=5 timeout=true')) {
        throw 'Draft-timeout behavior was not observed.'
    }
    if (-not $alphaText.Contains('SSF_BOT_DRAFT_OFFER cards=5 timeout=false')) {
        throw 'Validated card selection was not observed.'
    }
    if (([regex]::Matches($serverText, '"state":"MATCH_RESULT"')).Count -lt 2) {
        throw 'The authoritative server did not complete two matches.'
    }
    if (([regex]::Matches($alphaText, 'SSF_BOT_LOBBY_RETURN count=\d+ builds=2 scores=2')).Count -lt 2) {
        throw 'Lobby return did not expose reset builds and scores for both connected players.'
    }

    $combined = $serverText + $alphaText + $betaText
    $unexpectedErrors = $combined -split "`r?`n" | Where-Object {
        ($_ -match '^(SCRIPT ERROR:|ERROR:)') -and
        (-not $_.Contains('Failed to read the root certificate store.'))
    }
    if ($unexpectedErrors) {
        throw "Match-loop verification emitted unexpected Godot errors: $($unexpectedErrors -join ' | ')"
    }

    Wait-SsfMatchCondition -Description 'clean server shutdown' -TimeoutSeconds 35 -Condition {
        $server.HasExited -and (Get-SsfMatchOutput -Name 'server').Contains('SSF_SERVER_GRACEFUL_SHUTDOWN=test_duration')
    }
    if (-not (Get-SsfMatchOutput -Name 'server').Contains('"event":"server_shutdown"')) {
        throw 'Clean ENet shutdown was not logged.'
    }
    Write-Host 'Match-loop verification passed: private picks, timeout auto-pick, two full matches, reset, rematch, and clean shutdown.'
}
finally {
    foreach ($process in $processes) {
        if (-not $process.HasExited) {
            Stop-Process -Id $process.Id -Force
        }
    }
}
