$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'common.ps1')
& python (Join-Path $PSScriptRoot 'update-release-metadata.py')
if ($LASTEXITCODE -ne 0) { throw 'Release metadata is stale.' }

$godot = Get-SsfGodotExecutable
$verificationCount = 0

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
    $logPath = New-SsfVerificationLogPath -Name $Name
    $separatorIndex = [Array]::IndexOf($Arguments, '--')
    if ($separatorIndex -ge 0) {
        $engineArguments = @($Arguments[0..($separatorIndex - 1)]) + @('--log-file', $logPath) + @($Arguments[$separatorIndex..($Arguments.Length - 1)])
    }
    else {
        $engineArguments = @($Arguments) + @('--log-file', $logPath)
    }
    # Expected-failure checks deliberately receive stderr and a nonzero native
    # exit. Capture both before restoring strict PowerShell error handling.
    $previousErrorActionPreference = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    try {
        $output = (& $godot @engineArguments 2>&1 | Out-String)
        $exitCode = $LASTEXITCODE
    }
    finally {
        $ErrorActionPreference = $previousErrorActionPreference
    }
    Write-Host $output.TrimEnd()
    $allowedPatterns = @($AllowedErrorFragments | ForEach-Object {
        '^ERROR: .*' + [regex]::Escape($_) + '.*$'
    })
    Assert-SsfGodotResult -Output $output -ExitCode $exitCode -Name $Name `
        -ExpectedExitCode $ExpectedExitCode -ExpectedPattern ([regex]::Escape($ExpectedMarker)) `
        -AllowedErrorPatterns $allowedPatterns
    $script:verificationCount += 1
}

Invoke-FoundationCheck -Name 'Editor import and global class registration' -Arguments @(
    '--headless', '--editor', '--path', $SsfRepositoryRoot, '--quit'
) -AllowedErrorFragments @(
    "Could not open 'user://' directory",
    "Could not create ObjectDB Snapshots directory: user://"
)
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
    '--server', '--password=test-lobby', '--port=7123', '--max-players=16', '--rounds-to-win=4'
) -ExpectedMarker 'SSF_MODE_READY=server port=7123 max_players=16 rounds_to_win=4'
Invoke-FoundationCheck -Name 'Bot-client startup' -Arguments @(
    '--headless', '--path', $SsfRepositoryRoot, '--quit-after', '5', '--',
    '--bot-client=FoundationBot', '--password=test-lobby', '--port=7123'
) -ExpectedMarker 'SSF_MODE_READY=bot_client name=FoundationBot host=127.0.0.1 port=7123'
Invoke-FoundationCheck -Name 'Passing test suite' -Arguments @(
    '--headless', '--path', $SsfRepositoryRoot, '--', '--run-tests'
) -ExpectedMarker 'failed=0'
Invoke-FoundationCheck -Name 'Failing test exit path' -Arguments @(
    '--headless', '--path', $SsfRepositoryRoot, '--', '--run-tests', '--force-test-failure'
) -ExpectedExitCode 1 -ExpectedMarker 'failed=1'

& (Join-Path $PSScriptRoot 'verify-test-gate.ps1')
if ($LASTEXITCODE -ne 0) { throw 'Verification gate regression checks failed.' }
$verificationCount += 1
Write-Host "`nProject verification passed ($verificationCount checks)."
exit 0
