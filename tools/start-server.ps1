[CmdletBinding()]
param(
    [ValidateRange(1024, 65535)]
    [int]$Port = 7000,
    [ValidateRange(2, 32)]
    [int]$MaxPlayers = 32,
    [ValidateRange(1, 5)]
    [int]$RoundsToWin = 3
)

$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'common.ps1')

$godot = Get-SsfGodotExecutable
& $godot --headless --path $SsfRepositoryRoot -- --server "--port=$Port" "--max-players=$MaxPlayers" "--rounds-to-win=$RoundsToWin"
exit $LASTEXITCODE

