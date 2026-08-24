$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'common.ps1')

$godot = Get-SsfGodotExecutable
$verificationCount = 0
$verificationLogRoot = Join-Path $SsfToolsRoot 'verification-logs'
New-Item -ItemType Directory -Path $verificationLogRoot -Force | Out-Null

function Invoke-FoundationCheck {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Name,
        [Parameter(Mandatory = $true)]
        [string[]]$Arguments,
        [int]$ExpectedExitCode = 0,
        [string]$ExpectedMarker = '',
        [string[]]$AllowedErrorFragments = @()
    )

    Write-Host "`n== $Name =="
    $logName = ($Name -replace '[^a-zA-Z0-9]+', '-').Trim('-').ToLowerInvariant() + '.log'
    $logPath = ((Join-Path $verificationLogRoot $logName) -replace '\\', '/')
    $separatorIndex = [Array]::IndexOf($Arguments, '--')
    if ($separatorIndex -ge 0) {
        $engineArguments = @($Arguments[0..($separatorIndex - 1)]) + @('--log-file', $logPath) + @($Arguments[$separatorIndex..($Arguments.Length - 1)])
    }
    else {
        $engineArguments = @($Arguments) + @('--log-file', $logPath)
    }
    $output = (& $godot @engineArguments 2>&1 | Out-String)
    $exitCode = $LASTEXITCODE
    Write-Host $output.TrimEnd()
    if ($exitCode -ne $ExpectedExitCode) {
        throw "$Name exited with $exitCode; expected $ExpectedExitCode."
    }
    if ($ExpectedMarker -and -not $output.Contains($ExpectedMarker)) {
        throw "$Name did not emit expected marker: $ExpectedMarker"
    }
    $allowedErrors = @('Failed to read the root certificate store.') + $AllowedErrorFragments
    $unexpectedErrors = $output -split "`r?`n" | Where-Object {
        if (-not $_.StartsWith('ERROR:') -and -not $_.StartsWith('SCRIPT ERROR:')) {
            return $false
        }
        foreach ($allowedFragment in $allowedErrors) {
            if ($_.Contains($allowedFragment)) {
                return $false
            }
        }
        return $true
    }
    if ($unexpectedErrors) {
        throw "$Name emitted unexpected Godot errors: $($unexpectedErrors -join ' | ')"
    }
    $script:verificationCount += 1
}

Invoke-FoundationCheck -Name 'Editor import and global class registration' -Arguments @(
    '--headless', '--editor', '--path', $SsfRepositoryRoot, '--quit'
) -AllowedErrorFragments @("Could not open 'user://' directory")
Invoke-FoundationCheck -Name 'Client startup' -Arguments @(
    '--headless', '--path', $SsfRepositoryRoot, '--quit-after', '5'
) -ExpectedMarker 'SSF_MODE_READY=client'

$scripts = @('src', 'tests') | ForEach-Object {
    Get-ChildItem -LiteralPath (Join-Path $SsfRepositoryRoot $_) -Filter '*.gd' -Recurse
} | Sort-Object FullName
foreach ($scriptFile in $scripts) {
    $relativePath = $scriptFile.FullName.Substring($SsfRepositoryRoot.Length + 1) -replace '\\', '/'
    Invoke-FoundationCheck -Name "Parse $relativePath" -Arguments @(
        '--headless', '--path', $SsfRepositoryRoot, '--script', "res://$relativePath", '--check-only'
    )
}
Invoke-FoundationCheck -Name 'Server startup and argument parsing' -Arguments @(
    '--headless', '--path', $SsfRepositoryRoot, '--quit-after', '5', '--',
    '--server', '--port=7123', '--max-players=16', '--rounds-to-win=4'
) -ExpectedMarker 'SSF_MODE_READY=server port=7123 max_players=16 rounds_to_win=4'
Invoke-FoundationCheck -Name 'Bot-client startup' -Arguments @(
    '--headless', '--path', $SsfRepositoryRoot, '--quit-after', '5', '--',
    '--bot-client=FoundationBot', '--port=7123'
) -ExpectedMarker 'SSF_MODE_READY=bot_client name=FoundationBot port=7123'
Invoke-FoundationCheck -Name 'Passing test suite' -Arguments @(
    '--headless', '--path', $SsfRepositoryRoot, '--', '--run-tests'
) -ExpectedMarker 'failed=0'
Invoke-FoundationCheck -Name 'Failing test exit path' -Arguments @(
    '--headless', '--path', $SsfRepositoryRoot, '--', '--run-tests', '--force-test-failure'
) -ExpectedExitCode 1 -ExpectedMarker 'failed=1'

Write-Host "`nProject verification passed ($verificationCount checks)."
exit 0
