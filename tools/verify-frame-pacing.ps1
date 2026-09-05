[CmdletBinding()]
param([ValidateRange(30, 300)][int]$DurationSeconds = 45)

$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'common.ps1')
$godot = Get-SsfGodotExecutable
foreach ($fixture in @(
    @{ Name = 'frame-control'; Script = 'frame_pacing_control.gd'; Marker = 'SSF_FRAME_CONTROL='; Arguments = @() },
    @{ Name = 'frame-live'; Script = 'live_render_verifier.gd'; Marker = 'SSF_LIVE_RENDER_RESULT='; Arguments = @('--', "--duration=$DurationSeconds", '--frame-cap=0') }
)) {
    $frameLog = New-SsfVerificationLogPath -Name $fixture.Name
    Write-Host "Evidence: $frameLog"
    $ErrorActionPreference = 'Continue'
    try {
        $output = (& $godot --path $SsfRepositoryRoot --audio-driver Dummy --resolution 1920x1080 --position 0,0 --log-file $frameLog --script "res://src/test/$($fixture.Script)" @($fixture.Arguments) 2>&1 | Out-String)
        $frameExitCode = $LASTEXITCODE
    }
    finally { $ErrorActionPreference = 'Stop' }
    Assert-SsfGodotResult -Output $output -ExitCode $frameExitCode -Name $fixture.Name -ExpectedPattern $fixture.Marker
    $row = @($output -split "`r?`n" | Where-Object { $_.StartsWith($fixture.Marker) })[0]
    Write-Output $row
    $row.Substring($fixture.Marker.Length) | Set-Content -LiteralPath ($frameLog + '.json') -Encoding UTF8
}
Write-Host 'Frame measurements completed. Coverage and error checks passed; compare reported intervals with the 16.67 ms target.'
