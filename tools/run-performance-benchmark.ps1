[CmdletBinding()]
param([string]$Map = 'core_arena', [switch]$IncludeAttribution, [switch]$StrictPhysicsBudget)
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'common.ps1')
$godot = Get-SsfGodotExecutable
$fixtures = @(
    @{ Name = 'performance-unprofiled'; Arguments = @('res://scenes/test/performance_benchmark.tscn', '--', "--benchmark-map=$Map"); Marker = 'SSF_MINE_PERFORMANCE_RESULT' },
    @{ Name = 'performance-combined'; Arguments = @('--script', 'res://src/test/combined_performance_benchmark.gd', '--', "--benchmark-map=$Map"); Marker = 'SSF_COMBINED_PERFORMANCE=' }
)
if ($StrictPhysicsBudget) { $fixtures[1].Arguments += '--strict-physics-budget' }
if ($IncludeAttribution) {
    $fixtures += @{ Name = 'performance-attribution'; Arguments = @('res://scenes/test/performance_benchmark.tscn', '--', "--benchmark-map=$Map", '--profile'); Marker = 'detailed_profiling=true' }
}
foreach ($fixture in $fixtures) {
    $logPath = New-SsfVerificationLogPath -Name $fixture.Name
    Write-Host "Evidence: $logPath"
    $ErrorActionPreference = 'Continue'
    try {
        $output = & $godot --headless --path $SsfRepositoryRoot --log-file $logPath @($fixture.Arguments) 2>&1 | Out-String
        $exitCode = $LASTEXITCODE
    }
    finally { $ErrorActionPreference = 'Stop' }
    Write-Output $output
    Assert-SsfGodotResult -Output $output -ExitCode $exitCode -Name $fixture.Name -ExpectedPattern $fixture.Marker
}
