[CmdletBinding()]
param(
    [ValidateSet('x86_64', 'arm64')]
    [string]$Architecture = 'x86_64',
    [switch]$SkipFoundationGate
)

$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'common.ps1')
Assert-SsfShippingPolicy

$isArm64 = $Architecture -eq 'arm64'
$presetName = if ($isArm64) { "Linux ARM64 $($SsfRelease.label)" } else { "Linux $($SsfRelease.label)" }
$releaseLabel = "$($SsfRelease.label)"
$expectedGameVersion = "$($SsfRelease.version)"
$buildRoot = Join-Path $SsfRepositoryRoot "$($SsfRelease.directory)"
$clientPath = Join-Path $buildRoot $(if ($isArm64) { "SuperStarFighter-$($SsfRelease.tag).arm64" } else { "SuperStarFighter-$($SsfRelease.tag).x86_64" })
$archivePath = Join-Path $buildRoot $(if ($isArm64) { "SuperStarFighter-$($SsfRelease.tag)-Linux-arm64.zip" } else { "SuperStarFighter-$($SsfRelease.tag)-Linux-x64.zip" })
$friendReadme = Join-Path $buildRoot 'README-BETA-LINUX.txt'
$notices = Join-Path $buildRoot 'THIRD-PARTY-NOTICES-LINUX.txt'
$engineNotices = Join-Path $buildRoot 'GODOT_COPYRIGHT.txt'
$expectedMachineByte = if ($isArm64) { 0xb7 } else { 0x3e }
$architectureDescription = if ($isArm64) { 'ARM64/AArch64' } else { 'x86_64' }

function Assert-BetaBuildPath {
    param([Parameter(Mandatory = $true)][string]$Path)

    $resolvedBuildRoot = [System.IO.Path]::GetFullPath((Join-Path $SsfRepositoryRoot 'builds')).TrimEnd('\') + '\'
    $resolvedPath = [System.IO.Path]::GetFullPath($Path)
    if (-not $resolvedPath.StartsWith($resolvedBuildRoot, [System.StringComparison]::OrdinalIgnoreCase)) {
        throw "Refusing to write beta output outside $resolvedBuildRoot`: $resolvedPath"
    }
}

foreach ($path in @($buildRoot, $clientPath, $archivePath, $friendReadme, $notices)) {
    Assert-BetaBuildPath -Path $path
}

$projectText = Get-Content -LiteralPath (Join-Path $SsfRepositoryRoot 'project.godot') -Raw
$projectVersionMatch = [regex]::Match($projectText, 'config/version="([^"]+)"')
if (-not $projectVersionMatch.Success -or $projectVersionMatch.Groups[1].Value -ne $expectedGameVersion) {
    throw "Project version must be $expectedGameVersion before producing $releaseLabel."
}

if (-not $SkipFoundationGate) {
    Write-Host 'Running the complete project gate before export...'
    & (Join-Path $PSScriptRoot 'verify-foundation.ps1')
    if ($LASTEXITCODE -ne 0) {
        throw "Foundation verification failed with exit code $LASTEXITCODE."
    }
}

$godot = Get-SsfGodotExecutable
New-Item -ItemType Directory -Path $buildRoot -Force | Out-Null
Remove-Item -LiteralPath @($clientPath, $archivePath, $friendReadme, $notices) -Force -ErrorAction SilentlyContinue

Write-Host "Exporting $presetName..."
$previousErrorActionPreference = $ErrorActionPreference
$ErrorActionPreference = 'Continue'
try {
    $exportOutput = (& $godot --headless --path $SsfRepositoryRoot --export-release $presetName $clientPath 2>&1 | Out-String)
    $exportExitCode = $LASTEXITCODE
} finally {
    $ErrorActionPreference = $previousErrorActionPreference
}
Write-Host $exportOutput.TrimEnd()
Assert-SsfGodotResult -Output $exportOutput -ExitCode $exportExitCode -Name 'Linux export'
if (-not (Test-Path -LiteralPath $clientPath -PathType Leaf)) {
    throw "Linux export did not create $clientPath."
}
& python (Join-Path $PSScriptRoot 'audit-package.py') $clientPath --output (Join-Path $buildRoot "linux-$Architecture-package-audit.json")
if ($LASTEXITCODE -ne 0) { throw 'Linux package resource audit failed.' }

$stream = [System.IO.File]::OpenRead($clientPath)
try {
    $header = New-Object byte[] 20
    if ($stream.Read($header, 0, $header.Length) -ne $header.Length) {
        throw 'Linux export is too short to contain an ELF header.'
    }
} finally {
    $stream.Dispose()
}
if ($header[0] -ne 0x7f -or $header[1] -ne 0x45 -or $header[2] -ne 0x4c -or $header[3] -ne 0x46) {
    throw 'Linux export does not contain the expected ELF signature.'
}
if ($header[4] -ne 2 -or $header[5] -ne 1 -or $header[18] -ne $expectedMachineByte -or $header[19] -ne 0) {
    throw "Linux export is not a little-endian 64-bit $architectureDescription ELF executable."
}

$binaryBytes = [System.IO.File]::ReadAllBytes($clientPath)
$binaryText = [System.Text.Encoding]::UTF8.GetString($binaryBytes)
if (-not $binaryText.Contains($expectedGameVersion)) {
    throw "Linux export does not contain the expected packaged version $expectedGameVersion."
}

Copy-Item -LiteralPath (Join-Path $SsfRepositoryRoot 'docs\BETA_README.txt') -Destination $friendReadme
Copy-Item -LiteralPath (Join-Path $SsfRepositoryRoot 'docs\THIRD_PARTY_NOTICES.txt') -Destination $notices
Copy-Item -LiteralPath (Join-Path $SsfRepositoryRoot 'docs/GODOT_COPYRIGHT.txt') -Destination $engineNotices
Compress-Archive -LiteralPath @($clientPath, $friendReadme, $notices, $engineNotices) -DestinationPath $archivePath -CompressionLevel Optimal -Force

$clientHash = (Get-FileHash -LiteralPath $clientPath -Algorithm SHA256).Hash
$archiveHash = (Get-FileHash -LiteralPath $archivePath -Algorithm SHA256).Hash
Write-Host ''
Write-Host "Linux $architectureDescription $releaseLabel package passed export and static ELF verification."
Write-Host "Runtime launch verification must be completed on a Linux $architectureDescription host."
Write-Host "Executable: $clientPath"
Write-Host "Executable SHA-256: $clientHash"
Write-Host "Friend ZIP: $archivePath"
Write-Host "ZIP SHA-256: $archiveHash"
