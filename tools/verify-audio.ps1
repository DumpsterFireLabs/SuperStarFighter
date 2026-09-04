[CmdletBinding()]
param(
    [ValidateRange(1, 20)]
    [int]$Samples = 3,
    [string]$BaselineRevision = '',
    [switch]$SkipRecording
)

$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'common.ps1')
$godot = Get-SsfGodotExecutable
$outputRoot = Join-Path $SsfRepositoryRoot 'reports/audio-verification'
New-Item -ItemType Directory -Path $outputRoot -Force | Out-Null
$baselineArgument = @()
if ($BaselineRevision) {
    $source = (& git -c "safe.directory=$($SsfRepositoryRoot.Replace('\', '/'))" show "${BaselineRevision}:src/client/presentation/audio_director.gd" | Out-String)
    if ($LASTEXITCODE -ne 0) { throw 'Could not load the requested baseline revision.' }
    $source = $source.Replace('class_name AudioDirector', 'class_name AudioDirectorBefore')
    [System.IO.File]::WriteAllText((Join-Path $outputRoot 'audio_before.gd'), $source)
    $baselineArgument = @('--baseline-script=res://reports/audio-verification/audio_before.gd')
}

$measurements = @()
for ($index = 1; $index -le $Samples; $index++) {
    foreach ($variant in @('before', 'after')) {
        if ($variant -eq 'before' -and -not $BaselineRevision) { continue }
        $extra = if ($variant -eq 'before') { $baselineArgument } else { @() }
        $output = (& $godot --headless --path $SsfRepositoryRoot --script res://src/test/audio_memory_probe.gd -- @extra 2>&1 | Out-String)
        $output | Set-Content -Encoding UTF8 (Join-Path $outputRoot "$variant-$index.log")
        if ($LASTEXITCODE -ne 0 -or $output.Contains('SCRIPT ERROR:') -or $output -notmatch 'AUDIO_OS_MEMORY=([^\r\n]+)') {
            throw "Audio memory probe failed: $output"
        }
        $measurements += $Matches[1] | ConvertFrom-Json
    }
}
$measurements | ConvertTo-Json -Depth 8 | Set-Content -Encoding UTF8 (Join-Path $outputRoot 'process-memory.json')

if (-not $SkipRecording) {
    $output = (& $godot --headless --path $SsfRepositoryRoot --audio-driver Dummy --script res://src/test/audio_verifier.gd -- --record-audio --audio-output=res://reports/audio-verification 2>&1 | Out-String)
    $output | Set-Content -Encoding UTF8 (Join-Path $outputRoot 'recording.log')
    if ($LASTEXITCODE -ne 0 -or $output.Contains('SCRIPT ERROR:') -or $output.Contains('leaked at exit') -or $output.Contains('resources still in use') -or $output -notmatch 'SSF_AUDIO_VERIFY_OK=') {
        throw "Audio recording verification failed: $output"
    }
}
Write-Host "Audio evidence written to $outputRoot. WAV recordings require a listening review; they are not a human audition result."
