[CmdletBinding()]
param(
    [switch]$SkipFoundationGate
)

$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'common.ps1')

$presetName = 'macOS Beta 8'
$releaseLabel = 'Beta 8'
$expectedGameVersion = '0.1.0-beta.8'
$expectedBundleVersion = '0.1.0.8'
$buildRoot = Join-Path $SsfRepositoryRoot 'builds\beta-8'
$archivePath = Join-Path $buildRoot 'SuperStarFighter-Beta8-macOS-universal.zip'

function Assert-BetaBuildPath {
    param([Parameter(Mandatory = $true)][string]$Path)

    $resolvedBuildRoot = [System.IO.Path]::GetFullPath((Join-Path $SsfRepositoryRoot 'builds')).TrimEnd('\') + '\'
    $resolvedPath = [System.IO.Path]::GetFullPath($Path)
    if (-not $resolvedPath.StartsWith($resolvedBuildRoot, [System.StringComparison]::OrdinalIgnoreCase)) {
        throw "Refusing to write beta output outside $resolvedBuildRoot`: $resolvedPath"
    }
}

function Read-BigEndianUInt32 {
    param(
        [Parameter(Mandatory = $true)][byte[]]$Bytes,
        [Parameter(Mandatory = $true)][int]$Offset
    )

    return [uint32]((([uint32]$Bytes[$Offset]) -shl 24) -bor
        (([uint32]$Bytes[$Offset + 1]) -shl 16) -bor
        (([uint32]$Bytes[$Offset + 2]) -shl 8) -bor
        ([uint32]$Bytes[$Offset + 3]))
}

function Test-ZipEntryContainsText {
    param(
        [Parameter(Mandatory = $true)][System.IO.Compression.ZipArchiveEntry]$Entry,
        [Parameter(Mandatory = $true)][string]$ExpectedText
    )

    $stream = $Entry.Open()
    try {
        $buffer = New-Object byte[] 1048576
        $tail = ''
        while (($read = $stream.Read($buffer, 0, $buffer.Length)) -gt 0) {
            $text = $tail + [System.Text.Encoding]::ASCII.GetString($buffer, 0, $read)
            if ($text.Contains($ExpectedText)) {
                return $true
            }
            $tailLength = [Math]::Min($ExpectedText.Length - 1, $text.Length)
            $tail = $text.Substring($text.Length - $tailLength, $tailLength)
        }
        return $false
    } finally {
        $stream.Dispose()
    }
}

Assert-BetaBuildPath -Path $buildRoot
Assert-BetaBuildPath -Path $archivePath

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
Remove-Item -LiteralPath $archivePath -Force -ErrorAction SilentlyContinue

Write-Host "Exporting $presetName..."
$exportOutput = (& $godot --headless --path $SsfRepositoryRoot --export-release $presetName $archivePath 2>&1 | Out-String)
$exportExitCode = $LASTEXITCODE
Write-Host $exportOutput.TrimEnd()
if ($exportExitCode -ne 0) {
    throw "macOS export failed with exit code $exportExitCode."
}
if (-not (Test-Path -LiteralPath $archivePath -PathType Leaf)) {
    throw "macOS export did not create $archivePath."
}

Add-Type -AssemblyName System.IO.Compression
Add-Type -AssemblyName System.IO.Compression.FileSystem
$archive = [System.IO.Compression.ZipFile]::Open($archivePath, [System.IO.Compression.ZipArchiveMode]::Update)
try {
    $executableEntry = $archive.Entries | Where-Object {
        $_.FullName -match '\.app/Contents/MacOS/[^/]+$'
    } | Select-Object -First 1
    $plistEntry = $archive.Entries | Where-Object {
        $_.FullName -match '\.app/Contents/Info\.plist$'
    } | Select-Object -First 1
    if (-not $executableEntry -or -not $plistEntry) {
        throw 'macOS export is missing its app executable or Info.plist.'
    }

    $unixMode = ($executableEntry.ExternalAttributes -shr 16) -band 0xffff
    if (($unixMode -band 0x49) -ne 0x49) {
        throw ('macOS app executable is missing expected Unix execute permissions (mode=0x{0:X4}).' -f $unixMode)
    }

    $executableStream = $executableEntry.Open()
    try {
        $header = New-Object byte[] 72
        if ($executableStream.Read($header, 0, $header.Length) -ne $header.Length) {
            throw 'macOS app executable is too short to contain a universal Mach-O header.'
        }
    } finally {
        $executableStream.Dispose()
    }

    $magic = Read-BigEndianUInt32 -Bytes $header -Offset 0
    $magicHex = '{0:X8}' -f $magic
    if ($magicHex -ne 'CAFEBABE' -and $magicHex -ne 'CAFEBABF') {
        throw "macOS app executable is not a universal Mach-O binary (magic=0x$magicHex)."
    }
    $architectureCount = Read-BigEndianUInt32 -Bytes $header -Offset 4
    $architectureEntrySize = if ($magicHex -eq 'CAFEBABF') { 32 } else { 20 }
    if ($architectureCount -lt 2 -or $header.Length -lt 8 + ($architectureCount * $architectureEntrySize)) {
        throw "macOS app executable does not contain a valid two-architecture Mach-O table."
    }
    $cpuTypes = @()
    for ($index = 0; $index -lt $architectureCount; $index++) {
        $cpuType = Read-BigEndianUInt32 -Bytes $header -Offset (8 + ($index * $architectureEntrySize))
        $cpuTypes += '{0:X8}' -f $cpuType
    }
    if ($cpuTypes -notcontains '01000007' -or $cpuTypes -notcontains '0100000C') {
        throw 'macOS app executable does not contain both x86_64 and arm64 slices.'
    }

    $plistReader = New-Object System.IO.StreamReader($plistEntry.Open())
    try {
        $plistText = $plistReader.ReadToEnd()
    } finally {
        $plistReader.Dispose()
    }
    if (-not $plistText.Contains('com.dumpsterfirelabs.superstarfighter') -or -not $plistText.Contains($expectedBundleVersion)) {
        throw 'macOS Info.plist does not contain the expected bundle identifier and version.'
    }

    $versionFound = $false
    foreach ($entry in $archive.Entries) {
        if ($entry.FullName -match '\.app/Contents/(MacOS|Resources)/' -and (Test-ZipEntryContainsText -Entry $entry -ExpectedText $expectedGameVersion)) {
            $versionFound = $true
            break
        }
    }
    if (-not $versionFound) {
        throw "macOS export does not contain the expected packaged version $expectedGameVersion."
    }

    foreach ($name in @('README-BETA.txt', 'THIRD-PARTY-NOTICES.txt')) {
        $existing = $archive.GetEntry($name)
        if ($existing) {
            $existing.Delete()
        }
    }
    [System.IO.Compression.ZipFileExtensions]::CreateEntryFromFile(
        $archive,
        (Join-Path $SsfRepositoryRoot 'docs\BETA_README.txt'),
        'README-BETA.txt',
        [System.IO.Compression.CompressionLevel]::Optimal
    ) | Out-Null
    [System.IO.Compression.ZipFileExtensions]::CreateEntryFromFile(
        $archive,
        (Join-Path $SsfRepositoryRoot 'docs\THIRD_PARTY_NOTICES.txt'),
        'THIRD-PARTY-NOTICES.txt',
        [System.IO.Compression.CompressionLevel]::Optimal
    ) | Out-Null
} finally {
    $archive.Dispose()
}

$readArchive = [System.IO.Compression.ZipFile]::OpenRead($archivePath)
try {
    foreach ($entry in $readArchive.Entries) {
        $entryStream = $entry.Open()
        try {
            $buffer = New-Object byte[] 1048576
            $readTotal = 0L
            while (($read = $entryStream.Read($buffer, 0, $buffer.Length)) -gt 0) {
                $readTotal += $read
            }
            if ($readTotal -ne $entry.Length) {
                throw "macOS archive entry length mismatch for $($entry.FullName)."
            }
        } finally {
            $entryStream.Dispose()
        }
    }
} finally {
    $readArchive.Dispose()
}

$archiveHash = (Get-FileHash -LiteralPath $archivePath -Algorithm SHA256).Hash
Write-Host ''
Write-Host "macOS $releaseLabel package passed app-bundle, metadata, universal Mach-O, embedded-version, and archive verification."
Write-Host 'Runtime launch, code-signing, and notarization verification must be completed on a macOS host.'
Write-Host "Universal ZIP: $archivePath"
Write-Host "ZIP SHA-256: $archiveHash"
