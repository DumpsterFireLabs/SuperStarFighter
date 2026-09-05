[CmdletBinding()]
param(
    [ValidateRange(0, 300)]
    [int]$ChallengeDelayMs = 150,
    [ValidateRange(1024, 65535)]
    [int]$Port = 17940
)

$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'common.ps1')
$godot = Get-SsfGodotExecutable
$logPath = New-SsfVerificationLogPath -Name 'admission-burst'
$ErrorActionPreference = 'Continue'
try {
    $output = (& $godot --headless --path $SsfRepositoryRoot --log-file $logPath --script res://src/test/admission_burst_verifier.gd -- "--delay-ms=$ChallengeDelayMs" "--port=$Port" 2>&1 | Out-String)
    $verificationExitCode = $LASTEXITCODE
}
finally { $ErrorActionPreference = 'Stop' }
Write-Output $output.TrimEnd()
Assert-SsfGodotResult -Output $output -ExitCode $verificationExitCode -Name 'Admission burst' -ExpectedPattern 'SSF_ADMISSION_OK='
exit $verificationExitCode
