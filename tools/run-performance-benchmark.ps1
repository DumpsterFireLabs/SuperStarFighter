[CmdletBinding()]
param([string]$Map = 'core_arena')
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'common.ps1')

$godot = Get-SsfGodotExecutable
$logPath = New-SsfVerificationLogPath -Name 'performance-benchmark'
$output = & $godot --headless --path $SsfRepositoryRoot --log-file $logPath res://scenes/test/performance_benchmark.tscn -- "--benchmark-map=$Map" 2>&1 | Out-String
$exitCode = $LASTEXITCODE
Write-Output $output
Assert-SsfGodotResult -Output $output -ExitCode $exitCode -Name 'Performance benchmark' -ExpectedPattern 'SSF_MINE_PERFORMANCE_RESULT'
exit $exitCode
