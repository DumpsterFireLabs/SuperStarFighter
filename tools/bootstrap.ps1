[CmdletBinding()]
param(
    [switch]$Force
)

$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'common.ps1')

$downloadRoot = Join-Path $SsfToolsRoot 'downloads'
$templateStageRoot = Join-Path $SsfToolsRoot 'template-stage'
$engineArchiveName = 'Godot_v4.7.2-stable_win64.exe.zip'
$templateArchiveName = 'Godot_v4.7.2-stable_export_templates.tpz'
$checksumName = 'SHA512-SUMS.txt'
$releaseRoot = "https://github.com/godotengine/godot/releases/download/$SsfGodotVersionTag"

foreach ($path in @($SsfToolsRoot, $downloadRoot, $SsfGodotDataRoot)) {
    if (-not (Test-Path -LiteralPath $path)) {
        New-Item -ItemType Directory -Path $path | Out-Null
    }
}

function Get-ReleaseAsset {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Name
    )

    $destination = Join-Path $downloadRoot $Name
    if ($Force -or -not (Test-Path -LiteralPath $destination -PathType Leaf)) {
        Write-Host "Downloading $Name..."
        Invoke-WebRequest -Uri "$releaseRoot/$Name" -OutFile $destination
    }
    return $destination
}

function Assert-ReleaseChecksum {
    param(
        [Parameter(Mandatory = $true)]
        [string]$FilePath,
        [Parameter(Mandatory = $true)]
        [string]$ChecksumPath
    )

    $fileName = Split-Path -Leaf $FilePath
    $escapedName = [regex]::Escape($fileName)
    $match = Select-String -LiteralPath $ChecksumPath -Pattern "(?i)^([0-9a-f]{128})\s+\*?.*$escapedName$" | Select-Object -First 1
    if (-not $match) {
        throw "No official SHA-512 entry was found for $fileName."
    }
    $expected = $match.Matches[0].Groups[1].Value.ToUpperInvariant()
    $actual = (Get-FileHash -LiteralPath $FilePath -Algorithm SHA512).Hash.ToUpperInvariant()
    if ($actual -ne $expected) {
        throw "SHA-512 verification failed for $fileName. Expected $expected, received $actual."
    }
    Write-Host "Verified $fileName ($actual)."
}

$checksumPath = Get-ReleaseAsset -Name $checksumName
$engineArchivePath = Get-ReleaseAsset -Name $engineArchiveName
$templateArchivePath = Get-ReleaseAsset -Name $templateArchiveName
Assert-ReleaseChecksum -FilePath $engineArchivePath -ChecksumPath $checksumPath
Assert-ReleaseChecksum -FilePath $templateArchivePath -ChecksumPath $checksumPath

if ($Force -and (Test-Path -LiteralPath $SsfGodotRoot)) {
    Assert-SsfPathWithinTools -Path $SsfGodotRoot
    Remove-Item -LiteralPath $SsfGodotRoot -Recurse -Force
}
if (-not (Test-Path -LiteralPath $SsfGodotExecutable -PathType Leaf)) {
    New-Item -ItemType Directory -Path $SsfGodotRoot -Force | Out-Null
    Expand-Archive -LiteralPath $engineArchivePath -DestinationPath $SsfGodotRoot -Force
}

$selfContainedMarker = Join-Path $SsfGodotRoot '_sc_'
if (-not (Test-Path -LiteralPath $selfContainedMarker -PathType Leaf)) {
    New-Item -ItemType File -Path $selfContainedMarker | Out-Null
}

$signature = Get-AuthenticodeSignature -LiteralPath $SsfGodotExecutable
if ($signature.Status -ne 'Valid') {
    throw "The downloaded Godot executable does not have a valid Authenticode signature: $($signature.Status)."
}
Write-Host "Verified executable signature: $($signature.SignerCertificate.Subject)"

if ($Force -and (Test-Path -LiteralPath $SsfExportTemplateRoot)) {
    Assert-SsfPathWithinTools -Path $SsfExportTemplateRoot
    Remove-Item -LiteralPath $SsfExportTemplateRoot -Recurse -Force
}
if (-not (Test-Path -LiteralPath (Join-Path $SsfExportTemplateRoot 'windows_release_x86_64.exe'))) {
    if (Test-Path -LiteralPath $templateStageRoot) {
        Assert-SsfPathWithinTools -Path $templateStageRoot
        Remove-Item -LiteralPath $templateStageRoot -Recurse -Force
    }
    New-Item -ItemType Directory -Path $templateStageRoot | Out-Null
    $templateZipPath = Join-Path $downloadRoot 'export_templates.zip'
    Copy-Item -LiteralPath $templateArchivePath -Destination $templateZipPath -Force
    Expand-Archive -LiteralPath $templateZipPath -DestinationPath $templateStageRoot -Force
    $templateSource = Get-ChildItem -LiteralPath $templateStageRoot -Directory -Recurse |
        Where-Object { $_.Name -eq 'templates' } |
        Select-Object -First 1
    if (-not $templateSource) {
        throw 'The export template archive did not contain a templates directory.'
    }
    New-Item -ItemType Directory -Path $SsfExportTemplateRoot -Force | Out-Null
    Get-ChildItem -LiteralPath $templateSource.FullName | Copy-Item -Destination $SsfExportTemplateRoot -Recurse -Force
    Remove-Item -LiteralPath $templateStageRoot -Recurse -Force
    Remove-Item -LiteralPath $templateZipPath -Force
}

if (-not (Test-Path -LiteralPath (Join-Path $SsfExportTemplateRoot 'windows_debug_x86_64.exe'))) {
    throw 'The Windows debug export template is missing after extraction.'
}
if (-not (Test-Path -LiteralPath (Join-Path $SsfExportTemplateRoot 'windows_release_x86_64.exe'))) {
    throw 'The Windows release export template is missing after extraction.'
}

$version = & $SsfGodotExecutable --headless --version
if ($LASTEXITCODE -ne 0 -or -not ($version -like '4.7.2*')) {
    throw "Unexpected Godot version output: $version"
}

Write-Host "Godot $version is ready."
Write-Host "Self-contained editor data and export templates are ready at $SsfGodotDataRoot."
