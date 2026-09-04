$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'common.ps1')

$marker = 'TEST_SUMMARY passed=1 failed=0'
Assert-SsfGodotResult -Output $marker -ExitCode 0 -ExpectedPattern 'TEST_SUMMARY passed=\d+ failed=0\b'
Assert-SsfGodotResult -Output "ERROR: Failed to read the root certificate store.`n$marker" -ExitCode 0 -ExpectedPattern $marker
Assert-SsfGodotResult -Output 'EXPECTED_FAILURE' -ExitCode 1 -ExpectedExitCode 1 -ExpectedPattern 'EXPECTED_FAILURE'

foreach ($case in @(
    @{ Output = "ERROR: Typed dictionary lookup failed.`n$marker"; ExitCode = 0 },
    @{ Output = "SCRIPT ERROR: Failed to read the root certificate store.`n$marker"; ExitCode = 0 },
    @{ Output = "ERROR: Failed to read the root certificate store. Unexpected extra error`n$marker"; ExitCode = 0 },
    @{ Output = $marker; ExitCode = 1 },
    @{ Output = 'incomplete run'; ExitCode = 0 }
)) {
    $rejected = $false
    try { Assert-SsfGodotResult -Output $case.Output -ExitCode $case.ExitCode -ExpectedPattern $marker }
    catch { $rejected = $true }
    if (-not $rejected) { throw "Verification gate accepted an invalid run: $($case.Output)" }
}

# Exercise the actual engine failure mode: push_error continues, prints a passing
# summary and exits zero. The common acceptance boundary must still reject it.
$engineLog = New-SsfVerificationLogPath -Name 'gate-negative-fixture'
$fixturePath = [System.IO.Path]::ChangeExtension($engineLog, '.gd')
@'
extends SceneTree
func _initialize() -> void:
    push_error("SSF_GATE_DELIBERATE_ENGINE_ERROR")
    print("TEST_SUMMARY passed=1 failed=0")
    quit(0)
'@ | Set-Content -LiteralPath $fixturePath -Encoding UTF8
try {
    $ErrorActionPreference = 'Continue'
    try {
        $output = (& (Get-SsfGodotExecutable) --headless --path $SsfRepositoryRoot --log-file $engineLog --script $fixturePath 2>&1 | Out-String)
        $engineExitCode = $LASTEXITCODE
    }
    finally { $ErrorActionPreference = 'Stop' }
    if ($engineExitCode -ne 0 -or -not $output.Contains($marker) -or $output -notmatch '(?m)^ERROR: SSF_GATE_DELIBERATE_ENGINE_ERROR') {
        throw "Engine fixture failed to exercise a zero-exit error: $output"
    }
    $rejected = $false
    try { Assert-SsfGodotResult -Output $output -ExitCode $engineExitCode -ExpectedPattern $marker }
    catch { $rejected = $_.Exception.Message.Contains('SSF_GATE_DELIBERATE_ENGINE_ERROR') }
    if (-not $rejected) { throw 'Verification gate accepted a real engine error.' }
}
finally { Remove-Item -LiteralPath $fixturePath -Force }
Write-Output 'Verification gate passed: 9 acceptance cases, including a real zero-exit engine error.'
exit 0
