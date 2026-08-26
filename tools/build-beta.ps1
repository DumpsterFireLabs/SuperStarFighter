[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'common.ps1')

$presetName = 'Windows Beta 1'
$buildRoot = Join-Path $SsfRepositoryRoot 'builds\beta-1'
$clientPath = Join-Path $buildRoot 'SuperStarFighter-Beta1.exe'
$archivePath = Join-Path $buildRoot 'SuperStarFighter-Beta1-Windows-x64.zip'
$smokeLog = Join-Path $buildRoot 'beta-smoke.log'
$friendReadme = Join-Path $buildRoot 'README-BETA.txt'
$notices = Join-Path $buildRoot 'THIRD-PARTY-NOTICES.txt'

function Assert-BetaBuildPath {
    param([Parameter(Mandatory = $true)][string]$Path)

    $resolvedBuildRoot = [System.IO.Path]::GetFullPath((Join-Path $SsfRepositoryRoot 'builds')).TrimEnd('\') + '\'
    $resolvedPath = [System.IO.Path]::GetFullPath($Path)
    if (-not $resolvedPath.StartsWith($resolvedBuildRoot, [System.StringComparison]::OrdinalIgnoreCase)) {
        throw "Refusing to write beta output outside $resolvedBuildRoot`: $resolvedPath"
    }
}

foreach ($path in @($buildRoot, $clientPath, $archivePath, $smokeLog, $friendReadme, $notices)) {
    Assert-BetaBuildPath -Path $path
}

Write-Host 'Running the complete project gate before export...'
& (Join-Path $PSScriptRoot 'verify-foundation.ps1')
if ($LASTEXITCODE -ne 0) {
    throw "Foundation verification failed with exit code $LASTEXITCODE."
}

$godot = Get-SsfGodotExecutable
New-Item -ItemType Directory -Path $buildRoot -Force | Out-Null
Remove-Item -LiteralPath @($clientPath, $archivePath, $smokeLog, $friendReadme, $notices) -Force -ErrorAction SilentlyContinue

Write-Host "Exporting $presetName..."
$exportOutput = (& $godot --headless --path $SsfRepositoryRoot --export-release $presetName $clientPath 2>&1 | Out-String)
$exportExitCode = $LASTEXITCODE
Write-Host $exportOutput.TrimEnd()
if ($exportExitCode -ne 0) {
    throw "Windows export failed with exit code $exportExitCode."
}
if (-not (Test-Path -LiteralPath $clientPath -PathType Leaf)) {
    throw "Windows export did not create $clientPath."
}

Write-Host 'Launching the exported client through its normal rendered startup path...'
$smokeProcess = Start-Process -FilePath $clientPath `
    -ArgumentList @('--audio-driver', 'Dummy', '--resolution', '1280x720', '--position', '-10000,-10000', '--quit-after', '5', '--log-file', $smokeLog) `
    -WindowStyle Hidden -Wait -PassThru
if ($smokeProcess.ExitCode -ne 0) {
    throw "Exported client smoke test exited with $($smokeProcess.ExitCode)."
}
if (-not (Test-Path -LiteralPath $smokeLog -PathType Leaf)) {
    throw 'Exported client smoke test did not create its log.'
}
$smokeText = Get-Content -LiteralPath $smokeLog -Raw
if (-not $smokeText.Contains('SSF_MODE_READY=client') -or $smokeText.Contains('SCRIPT ERROR:') -or $smokeText.Contains('ERROR:')) {
    throw 'Exported client smoke log failed ready/error validation.'
}

Copy-Item -LiteralPath (Join-Path $SsfRepositoryRoot 'docs\BETA_README.txt') -Destination $friendReadme
Copy-Item -LiteralPath (Join-Path $SsfRepositoryRoot 'docs\THIRD_PARTY_NOTICES.txt') -Destination $notices
Compress-Archive -LiteralPath @($clientPath, $friendReadme, $notices) -DestinationPath $archivePath -CompressionLevel Optimal -Force

$clientHash = (Get-FileHash -LiteralPath $clientPath -Algorithm SHA256).Hash
$archiveHash = (Get-FileHash -LiteralPath $archivePath -Algorithm SHA256).Hash
Write-Host ''
Write-Host 'Windows Beta 1 package passed export and launch smoke verification.'
Write-Host "Executable: $clientPath"
Write-Host "Executable SHA-256: $clientHash"
Write-Host "Friend ZIP: $archivePath"
Write-Host "ZIP SHA-256: $archiveHash"
