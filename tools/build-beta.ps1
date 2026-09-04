[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'common.ps1')

$presetName = 'Windows Beta 10'
$releaseLabel = 'Beta 10'
$expectedGameVersion = '0.1.0-beta.10'
$expectedWindowsVersion = '0.1.0.10'
$buildRoot = Join-Path $SsfRepositoryRoot 'builds\beta-10'
$clientPath = Join-Path $buildRoot 'SuperStarFighter-Beta10.exe'
$archivePath = Join-Path $buildRoot 'SuperStarFighter-Beta10-Windows-x64.zip'
$smokeLog = Join-Path $buildRoot 'beta-smoke.log'
$friendReadme = Join-Path $buildRoot 'README-BETA.txt'
$notices = Join-Path $buildRoot 'THIRD-PARTY-NOTICES.txt'
$musicRoot = Join-Path $SsfRepositoryRoot 'assets\audio\music'
$gameplayMusicRoot = Join-Path $musicRoot 'gameplay'
$supportedAudioExtensions = @('.wav', '.ogg', '.mp3')

function Get-SupportedAudioFiles {
    param([Parameter(Mandatory = $true)][string]$Path)

    if (-not (Test-Path -LiteralPath $Path -PathType Container)) {
        return @()
    }
    return @(Get-ChildItem -LiteralPath $Path -File | Where-Object {
        $supportedAudioExtensions -contains $_.Extension.ToLowerInvariant()
    })
}

$sourceRootMusic = @(Get-SupportedAudioFiles -Path $musicRoot)
$expectedMenuMusic = if (@($sourceRootMusic | Where-Object { $_.Name.ToLowerInvariant().StartsWith('main_menu.') }).Count -gt 0) { 1 } else { 0 }
$expectedWinMusic = if (@($sourceRootMusic | Where-Object { $_.Name.ToLowerInvariant().StartsWith('win.') }).Count -gt 0) { 1 } else { 0 }
$expectedGameplayMusic = @(Get-SupportedAudioFiles -Path $gameplayMusicRoot).Count

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

$projectText = Get-Content -LiteralPath (Join-Path $SsfRepositoryRoot 'project.godot') -Raw
$projectVersionMatch = [regex]::Match($projectText, 'config/version="([^"]+)"')
if (-not $projectVersionMatch.Success -or $projectVersionMatch.Groups[1].Value -ne $expectedGameVersion) {
    throw "Project version must be $expectedGameVersion before producing $releaseLabel."
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
$versionInfo = (Get-Item -LiteralPath $clientPath).VersionInfo
if ($versionInfo.FileVersion -ne $expectedWindowsVersion -or $versionInfo.ProductVersion -ne $expectedWindowsVersion) {
    throw "Exported Windows metadata mismatch. Expected $expectedWindowsVersion; file=$($versionInfo.FileVersion), product=$($versionInfo.ProductVersion)."
}
Write-Host "Windows metadata verified: game=$expectedGameVersion file/product=$expectedWindowsVersion"

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
$unexpectedSmokeErrors = @($smokeText -split "`r?`n" | Where-Object {
    $_.StartsWith('ERROR:') -and -not $_.Contains('Failed to read the root certificate store.')
})
if (-not $smokeText.Contains('SSF_MODE_READY=client') -or $smokeText.Contains('SCRIPT ERROR:') -or $unexpectedSmokeErrors.Count -gt 0) {
    throw 'Exported client smoke log failed ready/error validation.'
}
$audioReadyMatch = [regex]::Match($smokeText, 'SSF_AUDIO_READY menu=(\d+) gameplay=(\d+) win=(\d+)')
if (-not $audioReadyMatch.Success) {
    throw 'Exported client did not report its authored music inventory.'
}
$exportedMenuMusic = [int]$audioReadyMatch.Groups[1].Value
$exportedGameplayMusic = [int]$audioReadyMatch.Groups[2].Value
$exportedWinMusic = [int]$audioReadyMatch.Groups[3].Value
if ($exportedMenuMusic -ne $expectedMenuMusic -or $exportedGameplayMusic -ne $expectedGameplayMusic -or $exportedWinMusic -ne $expectedWinMusic) {
    throw "Exported music inventory mismatch. Source: menu=$expectedMenuMusic gameplay=$expectedGameplayMusic win=$expectedWinMusic; export: menu=$exportedMenuMusic gameplay=$exportedGameplayMusic win=$exportedWinMusic."
}
Write-Host "Exported music inventory verified: menu=$exportedMenuMusic gameplay=$exportedGameplayMusic win=$exportedWinMusic"

Copy-Item -LiteralPath (Join-Path $SsfRepositoryRoot 'docs\BETA_README.txt') -Destination $friendReadme
Copy-Item -LiteralPath (Join-Path $SsfRepositoryRoot 'docs\THIRD_PARTY_NOTICES.txt') -Destination $notices
Compress-Archive -LiteralPath @($clientPath, $friendReadme, $notices) -DestinationPath $archivePath -CompressionLevel Optimal -Force

$clientHash = (Get-FileHash -LiteralPath $clientPath -Algorithm SHA256).Hash
$archiveHash = (Get-FileHash -LiteralPath $archivePath -Algorithm SHA256).Hash
Write-Host ''
Write-Host "Windows $releaseLabel package passed export and launch smoke verification."
Write-Host "Executable: $clientPath"
Write-Host "Executable SHA-256: $clientHash"
Write-Host "Friend ZIP: $archivePath"
Write-Host "ZIP SHA-256: $archiveHash"
