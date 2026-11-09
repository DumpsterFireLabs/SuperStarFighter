param(
    # Run only suites whose file name contains this text, e.g. -Filter input_profile
    [string]$Filter = ''
)

$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'common.ps1')

$godot = Get-SsfGodotExecutable
$logPath = New-SsfVerificationLogPath -Name 'unit-tests'
$userArguments = @('--run-tests')
if ($Filter) { $userArguments += "--test-filter=$Filter" }
$ErrorActionPreference = 'Continue'
try {
    $output = (& $godot --headless --path $SsfRepositoryRoot --log-file $logPath -- @userArguments 2>&1 | Out-String)
    $testExitCode = $LASTEXITCODE
}
finally { $ErrorActionPreference = 'Stop' }
Write-Output $output.TrimEnd()
Assert-SsfGodotResult -Output $output -ExitCode $testExitCode -Name 'Unit tests' -ExpectedPattern 'TEST_SUMMARY passed=\d+ failed=0\b'
exit $testExitCode
