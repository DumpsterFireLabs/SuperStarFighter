[CmdletBinding()]
param(
    [ValidateRange(1024, 65535)]
    [int]$Port = 7000,
    [ValidateLength(1, 40)]
    [string]$ServerName = 'Super Star Fighter Server',
    [Parameter(Mandatory)]
    [ValidateLength(1, 64)]
    [string]$Password,
    [ValidateRange(2, 32)]
    [int]$MaxPlayers = 32,
    [ValidateRange(1, 5)]
    [int]$RoundsToWin = 3
)

$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'common.ps1')

$godot = Get-SsfGodotExecutable
& $godot --headless --path $SsfRepositoryRoot -- --server "--password=$Password" "--port=$Port" "--server-name=$ServerName" "--max-players=$MaxPlayers" "--rounds-to-win=$RoundsToWin"
exit $LASTEXITCODE
