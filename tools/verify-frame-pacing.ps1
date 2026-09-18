[CmdletBinding()]
param(
    [ValidateRange(30, 300)][int]$DurationSeconds = 45,
    [ValidateRange(1, 240)][double]$ExpectedFps = 60,
    [switch]$IncludeAttribution
)
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'common.ps1')
$godot = Get-SsfGodotExecutable
$results = @{}
$fixtures = @(
    @{ Name = 'control'; Script = 'frame_pacing_control.gd'; Marker = 'SSF_FRAME_CONTROL='; Arguments = @('--', "--expected-fps=$ExpectedFps") },
    @{ Name = 'dense'; Script = 'dense_render_replay.gd'; Marker = 'SSF_DENSE_REPLAY='; Arguments = @('--', "--expected-fps=$ExpectedFps") },
    @{ Name = 'production'; Script = 'production_render_verifier.gd'; Marker = 'SSF_PRODUCTION_RENDER='; Arguments = @('--', "--duration=$DurationSeconds", "--expected-fps=$ExpectedFps") }
)
if ($IncludeAttribution) {
    $fixtures += @{ Name = 'attribution'; Script = 'live_render_verifier.gd'; Marker = 'SSF_LIVE_RENDER_RESULT='; Arguments = @('--', "--duration=$DurationSeconds", '--frame-cap=0', "--expected-fps=$ExpectedFps") }
}
foreach ($fixture in $fixtures) {
    $frameLog = New-SsfVerificationLogPath -Name "frame-$($fixture.Name)"
    Write-Host "Evidence: $frameLog"
    $ErrorActionPreference = 'Continue'
    try {
        # Real audio is required by the production fixture. The empty control uses
        # the same driver/display settings; it simply has no sound sources.
        $output = (& $godot --path $SsfRepositoryRoot --resolution 1920x1080 --position 0,0 --log-file $frameLog --script "res://src/test/$($fixture.Script)" @($fixture.Arguments) 2>&1 | Out-String)
        $frameExitCode = $LASTEXITCODE
    }
    finally { $ErrorActionPreference = 'Stop' }
    Assert-SsfGodotResult -Output $output -ExitCode $frameExitCode -Name $fixture.Name -ExpectedPattern $fixture.Marker
    $row = @($output -split "`r?`n" | Where-Object { $_.StartsWith($fixture.Marker) })[0]
    Write-Output $row
    $json = $row.Substring($fixture.Marker.Length)
    $json | Set-Content -LiteralPath ($frameLog + '.json') -Encoding UTF8
    $results[$fixture.Name] = $json | ConvertFrom-Json
}
$control = $results.control.pacing
foreach ($name in @('dense', 'production')) {
    $pacing = $results[$name].pacing
    [pscustomobject]@{
        workload = $name
        expected_fps = $ExpectedFps
        control_samples = $control.samples
        workload_samples = $pacing.samples
        control_p95_usec = $control.p95_usec
        workload_p95_usec = $pacing.p95_usec
        control_late_percent = $control.late_percent
        workload_late_percent = $pacing.late_percent
        late_increase_percentage_points = $pacing.late_percent - $control.late_percent
        control_severe_frames = $control.severe_frames
        workload_severe_frames = $pacing.severe_frames
    } | ConvertTo-Json -Compress | Write-Output
}
Write-Host "Coverage and error checks passed. Cadence is compared with the empty control at $ExpectedFps FPS; late means budget + 1 ms, severe means 1.5 intervals. Frame differences are diagnostic, not isolated GPU cost or timing acceptance."
