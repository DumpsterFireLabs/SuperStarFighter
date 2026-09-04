$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'common.ps1')

$godot = Get-SsfGodotExecutable
$logPath = New-SsfVerificationLogPath -Name 'unit-tests'
$ErrorActionPreference = 'Continue'
try {
    $output = (& $godot --headless --path $SsfRepositoryRoot --log-file $logPath -- --run-tests 2>&1 | Out-String)
    $testExitCode = $LASTEXITCODE
}
finally { $ErrorActionPreference = 'Stop' }
Write-Output $output.TrimEnd()
Assert-SsfGodotResult -Output $output -ExitCode $testExitCode -Name 'Unit tests' -ExpectedPattern 'TEST_SUMMARY passed=\d+ failed=0\b'
exit $testExitCode
