[CmdletBinding()]
param(
    [ValidateRange(1024, 65535)]
    [int]$Port = 17343
)

$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'common.ps1')

$godot = Get-SsfGodotExecutable
$logRoot = Join-Path $SsfToolsRoot 'network-verification'
Assert-SsfPathWithinTools -Path $logRoot
New-Item -ItemType Directory -Path $logRoot -Force | Out-Null

$names = @('server', 'alpha', 'beta', 'gamma', 'badversion', 'badname', 'full')
$knownLogs = foreach ($name in $names) {
    Join-Path $logRoot "$name.out.log"
    Join-Path $logRoot "$name.err.log"
    Join-Path $logRoot "$name.godot.log"
}
Remove-Item -LiteralPath $knownLogs -Force -ErrorAction SilentlyContinue

$processes = [System.Collections.Generic.List[System.Diagnostics.Process]]::new()

function Start-SsfProcess {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Name,
        [Parameter(Mandatory = $true)]
        [string[]]$UserArguments
    )

    $stdout = Join-Path $logRoot "$Name.out.log"
    $stderr = Join-Path $logRoot "$Name.err.log"
    $godotLog = (Join-Path $logRoot "$Name.godot.log") -replace '\\', '/'
    $arguments = @('--headless', '--path', '.', '--log-file', $godotLog, '--') + $UserArguments
    $process = Start-Process -FilePath $godot `
        -ArgumentList $arguments `
        -WorkingDirectory $SsfRepositoryRoot `
        -RedirectStandardOutput $stdout `
        -RedirectStandardError $stderr `
        -WindowStyle Hidden `
        -PassThru
    $processes.Add($process)
    return $process
}

function Get-SsfOutput {
    param([Parameter(Mandatory = $true)][string]$Name)

    $content = ''
    foreach ($extension in @('out.log', 'err.log')) {
        $path = Join-Path $logRoot "$Name.$extension"
        if (Test-Path -LiteralPath $path) {
            $content += Get-Content -LiteralPath $path -Raw
        }
    }
    return $content
}

function Wait-SsfCondition {
    param(
        [Parameter(Mandatory = $true)]
        [scriptblock]$Condition,
        [Parameter(Mandatory = $true)]
        [string]$Description,
        [int]$TimeoutSeconds = 12
    )

    $deadline = [DateTime]::UtcNow.AddSeconds($TimeoutSeconds)
    while ([DateTime]::UtcNow -lt $deadline) {
        if (& $Condition) {
            return
        }
        Start-Sleep -Milliseconds 200
    }
    throw "Timed out waiting for $Description."
}

function Assert-SsfContains {
    param(
        [Parameter(Mandatory = $true)][string]$Text,
        [Parameter(Mandatory = $true)][string]$Pattern,
        [Parameter(Mandatory = $true)][string]$Description
    )

    if (-not $Text.Contains($Pattern)) {
        throw "$Description was not observed. Missing marker: $Pattern"
    }
}

try {
    $server = Start-SsfProcess -Name 'server' -UserArguments @(
        '--server', "--port=$Port", '--max-players=2', '--rounds-to-win=2', '--auto-start', '--test-server-duration=40'
    )
    Start-Sleep -Milliseconds 600
    $alpha = Start-SsfProcess -Name 'alpha' -UserArguments @(
        '--bot-client=Alpha', '--host=127.0.0.1', "--port=$Port"
    )
    Start-Sleep -Milliseconds 350
    $beta = Start-SsfProcess -Name 'beta' -UserArguments @(
        '--bot-client=Beta', '--host=127.0.0.1', "--port=$Port"
    )

    Wait-SsfCondition -Description 'two admitted clients, snapshots, and projectile replication' -Condition {
        $serverText = Get-SsfOutput -Name 'server'
        $alphaText = Get-SsfOutput -Name 'alpha'
        $betaText = Get-SsfOutput -Name 'beta'
        return (
            $serverText.Contains('"event":"match_event","event_type":"MATCH_START_ACCEPTED"') -and
            $alphaText.Contains('SSF_BOT_WELCOME') -and
            $betaText.Contains('SSF_BOT_WELCOME') -and
            $alphaText.Contains('SSF_BOT_SNAPSHOT') -and
            $betaText.Contains('SSF_BOT_SNAPSHOT') -and
            $betaText.Contains('SSF_BOT_ACK') -and
            $betaText.Contains('SSF_BOT_MOVEMENT') -and
            $betaText.Contains('SSF_BOT_AIM') -and
            $betaText.Contains('SSF_BOT_SHIELD') -and
            $betaText.Contains('SSF_BOT_CORRECTION') -and
            $alphaText.Contains('SSF_BOT_PROJECTILES') -and
            $betaText.Contains('SSF_BOT_PROJECTILES')
        )
    }

    $alphaText = Get-SsfOutput -Name 'alpha'
    $betaText = Get-SsfOutput -Name 'beta'
    $alphaMatch = [regex]::Match($alphaText, 'SSF_BOT_WELCOME peer_id=(\d+)')
    $betaMatch = [regex]::Match($betaText, 'SSF_BOT_WELCOME peer_id=(\d+)')
    if (-not $alphaMatch.Success -or -not $betaMatch.Success) {
        throw 'Could not extract assigned peer IDs from bot welcome messages.'
    }
    $betaId = $betaMatch.Groups[1].Value

    if (-not $alpha.HasExited) {
        Stop-Process -Id $alpha.Id -Force
    }
    Wait-SsfCondition -Description 'leader transfer after Alpha disconnects' -Condition {
        (Get-SsfOutput -Name 'beta').Contains("players=1 leader=$betaId")
    }

    $gamma = Start-SsfProcess -Name 'gamma' -UserArguments @(
        '--bot-client=Gamma', '--host=127.0.0.1', "--port=$Port"
    )
    Wait-SsfCondition -Description 'late spectator admission' -Condition {
        $serverText = Get-SsfOutput -Name 'server'
        $gammaText = Get-SsfOutput -Name 'gamma'
        return $serverText.Contains('"display_name":"Gamma","event":"peer_joined"') -and
            $serverText.Contains('"spectator":true') -and
            $gammaText.Contains('SSF_BOT_WELCOME') -and
            $gammaText.Contains('SSF_BOT_SNAPSHOT')
    }

    $badVersion = Start-SsfProcess -Name 'badversion' -UserArguments @(
        '--bot-client=BadVersion', '--test-protocol-version=999', '--host=127.0.0.1', "--port=$Port"
    )
    Wait-SsfCondition -Description 'version mismatch rejection' -Condition {
        (Get-SsfOutput -Name 'badversion').Contains('SSF_BOT_REJECTED reason=VERSION_MISMATCH')
    }
    Start-Sleep -Milliseconds 300

    $badName = Start-SsfProcess -Name 'badname' -UserArguments @(
        '--bot-client=ABCDEFGHIJKLMNOPQ', '--host=127.0.0.1', "--port=$Port"
    )
    Wait-SsfCondition -Description 'invalid name rejection' -Condition {
        (Get-SsfOutput -Name 'badname').Contains('SSF_BOT_REJECTED reason=INVALID_NAME')
    }
    Start-Sleep -Milliseconds 300

    $full = Start-SsfProcess -Name 'full' -UserArguments @(
        '--bot-client=Full', '--host=127.0.0.1', "--port=$Port"
    )
    Wait-SsfCondition -Description 'server full rejection' -Condition {
        (Get-SsfOutput -Name 'full').Contains('SSF_BOT_REJECTED reason=SERVER_FULL')
    }

    $serverText = Get-SsfOutput -Name 'server'
    $betaText = Get-SsfOutput -Name 'beta'
    $gammaText = Get-SsfOutput -Name 'gamma'
    $badVersionText = Get-SsfOutput -Name 'badversion'
    $badNameText = Get-SsfOutput -Name 'badname'
    $fullText = Get-SsfOutput -Name 'full'
    Assert-SsfContains -Text $serverText -Pattern '"display_name":"Alpha","event":"peer_joined"' -Description 'Alpha admission'
    Assert-SsfContains -Text $serverText -Pattern '"display_name":"Beta","event":"peer_joined"' -Description 'Beta admission'
    Assert-SsfContains -Text $serverText -Pattern '"event":"match_event","event_type":"MATCH_START_ACCEPTED"' -Description 'authoritative start event'
    Assert-SsfContains -Text $betaText -Pattern "players=1 leader=$betaId" -Description 'deterministic leader transfer'
    Assert-SsfContains -Text $gammaText -Pattern 'SSF_BOT_SNAPSHOT' -Description 'late spectator snapshots'
    Assert-SsfContains -Text $badVersionText -Pattern 'reason=VERSION_MISMATCH' -Description 'version mismatch reason code'
    Assert-SsfContains -Text $badNameText -Pattern 'reason=INVALID_NAME' -Description 'invalid name reason code'
    Assert-SsfContains -Text $fullText -Pattern 'reason=SERVER_FULL' -Description 'server capacity reason code'

    $combined = $serverText + $betaText + $gammaText + $badVersionText + $badNameText + $fullText
    $unexpectedErrors = $combined -split "`r?`n" | Where-Object {
        ($_ -match '^(SCRIPT ERROR:|ERROR:)') -and
        (-not $_.Contains('Failed to read the root certificate store.'))
    }
    if ($unexpectedErrors) {
        throw "Network verification emitted unexpected Godot errors: $($unexpectedErrors -join ' | ')"
    }

    Wait-SsfCondition -Description 'graceful server shutdown' -TimeoutSeconds 40 -Condition {
        $server.HasExited -and (Get-SsfOutput -Name 'server').Contains('SSF_SERVER_GRACEFUL_SHUTDOWN=test_duration')
    }
    $serverText = Get-SsfOutput -Name 'server'
    Assert-SsfContains -Text $serverText -Pattern '"event":"server_shutdown"' -Description 'clean ENet shutdown log'

    Write-Host 'Network verification passed: handshake/rejections, lobby authority, input/snapshots, projectiles, leader transfer, and late spectator.'
}
finally {
    foreach ($process in $processes) {
        if (-not $process.HasExited) {
            Stop-Process -Id $process.Id -Force
        }
    }
}
