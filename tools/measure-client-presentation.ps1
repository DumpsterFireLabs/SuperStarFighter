$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'common.ps1')
$godot = Get-SsfGodotExecutable
$logPath = New-SsfVerificationLogPath -Name 'client-presentation-cpu'
$ErrorActionPreference = 'Continue'
try {
    $output = (& $godot --headless --path $SsfRepositoryRoot --log-file $logPath --script res://src/test/client_presentation_benchmark.gd 2>&1 | Out-String)
    $resultCode = $LASTEXITCODE
}
finally { $ErrorActionPreference = 'Stop' }
Assert-SsfGodotResult -Output $output -ExitCode $resultCode -Name 'Client presentation CPU benchmark' -ExpectedPattern 'SSF_CLIENT_PRESENTATION_BENCHMARK='
Write-Output $output.TrimEnd()
Write-Host "Evidence: $logPath"
