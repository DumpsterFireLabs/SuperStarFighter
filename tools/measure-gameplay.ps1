param(
    [ValidateSet('all', 'pacing', 'balance', 'fairness')][string]$Section = 'all',
    [ValidateRange(1, 100)][int]$Seeds = 3,
    [string]$OutputPath = 'reports/gameplay-study.json'
)
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'common.ps1')
$godot = Get-SsfGodotExecutable
$studyOutputPath = [System.IO.Path]::GetFullPath($OutputPath, $SsfRepositoryRoot)
[System.IO.Directory]::CreateDirectory([System.IO.Path]::GetDirectoryName($studyOutputPath)) | Out-Null
$studyLines = [System.Collections.Generic.List[string]]::new()
$studyLogPath = New-SsfVerificationLogPath -Name 'gameplay-study'
$ErrorActionPreference = 'Continue'
try {
    & $godot --headless --path $SsfRepositoryRoot --log-file $studyLogPath --script res://src/test/gameplay_study.gd -- "--section=$Section" "--seeds=$Seeds" "--output=$studyOutputPath" 2>&1 | ForEach-Object {
        $line = "$_"
        $studyLines.Add($line)
        Write-Output $line
    }
    $studyExitCode = $LASTEXITCODE
}
finally { $ErrorActionPreference = 'Stop' }
$output = $studyLines -join "`n"
Assert-SsfGodotResult -Output $output -ExitCode $studyExitCode -Name 'Gameplay study' -ExpectedPattern 'SSF_GAMEPLAY_STUDY_COMPLETE'
exit $studyExitCode
