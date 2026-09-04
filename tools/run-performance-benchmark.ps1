[CmdletBinding()]
param([string]$Map = 'core_arena')
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'common.ps1')

$godot = Get-SsfGodotExecutable
& $godot --headless --path $SsfRepositoryRoot res://scenes/test/performance_benchmark.tscn -- "--benchmark-map=$Map"
exit $LASTEXITCODE
