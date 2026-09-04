$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'common.ps1')

$godot = Get-SsfGodotExecutable
$output = (& $godot --headless --path $SsfRepositoryRoot -- --run-tests 2>&1 | Out-String)
$testExitCode = $LASTEXITCODE
Write-Output $output.TrimEnd()
# Godot can abort an individual test function on a script error yet still reach
# the summary and exit zero. Treat that incomplete run as a failed test gate.
if ($output.Contains('SCRIPT ERROR:') -or $output -notmatch 'TEST_SUMMARY passed=\d+ failed=0') {
    exit 1
}
exit $testExitCode
