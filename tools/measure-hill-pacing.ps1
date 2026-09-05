param(
    [ValidateSet('production', 'legacy-limit', 'short-target', 'slow-respawn', 'crowded-limit')][string]$Profile = 'production',
    [ValidateRange(1, 20)][int]$Seeds = 3,
    [string]$OutputPath = 'reports/hill-pacing.json'
)
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'common.ps1')
$outputFile = [System.IO.Path]::GetFullPath($OutputPath, $SsfRepositoryRoot)
[System.IO.Directory]::CreateDirectory([System.IO.Path]::GetDirectoryName($outputFile)) | Out-Null
$engineLog = New-SsfVerificationLogPath -Name 'hill-pacing'
$ErrorActionPreference = 'Continue'
try {
    $output = (& (Get-SsfGodotExecutable) --headless --path $SsfRepositoryRoot --log-file $engineLog --script res://src/test/hill_pacing_study.gd -- "--profile=$Profile" "--seeds=$Seeds" "--output=$outputFile" 2>&1 | Out-String)
    $studyExit = $LASTEXITCODE
} finally { $ErrorActionPreference = 'Stop' }
Write-Output $output.TrimEnd()
Assert-SsfGodotResult -Output $output -ExitCode $studyExit -Name 'Hill pacing study' -ExpectedPattern "SSF_HILL_STUDY_COMPLETE profile=$Profile rows=$($Seeds * 9)"
