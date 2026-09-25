param(
    [ValidateRange(1024, 65535)]
    [int]$Port = 7000,
    [ValidateLength(1, 40)]
    [string]$ServerName = 'Super Star Fighter Server',
    [string]$PasswordFile,
    [ValidateRange(0, 65535)]
    [int]$AdminPort = 0,
    [string]$AdminPasswordFile,
    [string]$BanFile,
    [ValidateRange(2, 32)]
    [int]$MaxPlayers = 32,
    [ValidateRange(1, 5)]
    [int]$RoundsToWin = 3,
    [switch]$CompetitiveView,
    [switch]$AutoStart,
    [string]$Bind,
    [switch]$BehindProxy,
    [switch]$NonInteractive,
    [string]$LogFile,
    [string]$ServerExecutable
)

$ErrorActionPreference = 'Stop'
$packagedServer = Join-Path $PSScriptRoot 'SuperStarFighter-Server.exe'
if (-not $ServerExecutable -and (Test-Path -LiteralPath $packagedServer -PathType Leaf)) {
    $ServerExecutable = $packagedServer
}
if ($ServerExecutable) {
    $serverBinary = (Resolve-Path -LiteralPath $ServerExecutable -ErrorAction Stop).Path
    $engineArguments = @('--headless')
}
else {
    . (Join-Path $PSScriptRoot 'common.ps1')
    $serverBinary = Get-SsfGodotExecutable
    $engineArguments = @('--headless', '--path', $SsfRepositoryRoot)
}
if ($LogFile) {
    $resolvedLogFile = [System.IO.Path]::GetFullPath($LogFile)
    New-Item -ItemType Directory -Path (Split-Path -Parent $resolvedLogFile) -Force | Out-Null
    $engineArguments += @('--log-file', $resolvedLogFile)
}
$userArguments = @('--server', "--port=$Port", "--server-name=$ServerName", "--max-players=$MaxPlayers", "--rounds-to-win=$RoundsToWin")
if ($CompetitiveView) { $userArguments += "--competitive-view" }
if ($AutoStart) { $userArguments += '--auto-start' }
if (-not [string]::IsNullOrWhiteSpace($Bind)) { $userArguments += "--bind=$Bind" }
if ($BehindProxy) { $userArguments += '--behind-proxy' }
if (-not [string]::IsNullOrWhiteSpace($PasswordFile)) {
    $resolvedPasswordFile = (Resolve-Path -LiteralPath $PasswordFile -ErrorAction Stop).Path
    $userArguments += "--password-file=$resolvedPasswordFile"
}
if ($AdminPort -gt 0) { $userArguments += "--admin-port=$AdminPort" }
if (-not [string]::IsNullOrWhiteSpace($AdminPasswordFile)) {
    $resolvedAdminPasswordFile = (Resolve-Path -LiteralPath $AdminPasswordFile -ErrorAction Stop).Path
    $userArguments += "--admin-password-file=$resolvedAdminPasswordFile"
}
if (-not [string]::IsNullOrWhiteSpace($BanFile)) {
    $resolvedBanFile = [System.IO.Path]::GetFullPath($BanFile)
    $userArguments += "--ban-file=$resolvedBanFile"
}

$priorLobbyPassword = [Environment]::GetEnvironmentVariable('SSF_LOBBY_PASSWORD', 'Process')
$priorAdminPassword = [Environment]::GetEnvironmentVariable('SSF_ADMIN_PASSWORD', 'Process')
$secretPointers = [System.Collections.Generic.List[System.IntPtr]]::new()
try {
    if ([string]::IsNullOrWhiteSpace($PasswordFile) -and [string]::IsNullOrEmpty($priorLobbyPassword)) {
        if ($NonInteractive) { throw 'Unattended startup requires -PasswordFile or SSF_LOBBY_PASSWORD.' }
        $secureLobbyPassword = Read-Host 'Lobby password' -AsSecureString
        $lobbyPointer = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($secureLobbyPassword)
        $secretPointers.Add($lobbyPointer)
        $plainLobbyPassword = [Runtime.InteropServices.Marshal]::PtrToStringBSTR($lobbyPointer)
        if ([string]::IsNullOrEmpty($plainLobbyPassword) -or $plainLobbyPassword.Length -gt 64) {
            throw 'Lobby password must contain 1-64 printable characters.'
        }
        [Environment]::SetEnvironmentVariable('SSF_LOBBY_PASSWORD', $plainLobbyPassword, 'Process')
        $plainLobbyPassword = $null
    }
    if ($AdminPort -gt 0 -and [string]::IsNullOrWhiteSpace($AdminPasswordFile) -and [string]::IsNullOrEmpty($priorAdminPassword)) {
        if ($NonInteractive) { throw 'Unattended administration requires -AdminPasswordFile or SSF_ADMIN_PASSWORD.' }
        $secureAdminPassword = Read-Host 'Admin password' -AsSecureString
        $adminPointer = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($secureAdminPassword)
        $secretPointers.Add($adminPointer)
        $plainAdminPassword = [Runtime.InteropServices.Marshal]::PtrToStringBSTR($adminPointer)
        if ([string]::IsNullOrEmpty($plainAdminPassword) -or $plainAdminPassword.Length -lt 12 -or $plainAdminPassword.Length -gt 64) {
            throw 'Admin password must contain 12-64 printable characters.'
        }
        [Environment]::SetEnvironmentVariable('SSF_ADMIN_PASSWORD', $plainAdminPassword, 'Process')
        $plainAdminPassword = $null
    }
    if ($ServerExecutable) {
        # The exported Windows template is a GUI-subsystem executable: '&'
        # can return before it exits. Retain its handle and wait explicitly so
        # supervisors see the real lifetime/exit code and secrets stay in scope.
        $nativeArguments = @($engineArguments + @('--') + $userArguments | ForEach-Object {
            $escapedArgument = [regex]::Replace($_, '(\\*)"', '$1$1\"')
            '"' + [regex]::Replace($escapedArgument, '(\\+)$', '$1$1') + '"'
        })
        $serverProcess = Start-Process -FilePath $serverBinary -ArgumentList $nativeArguments -WindowStyle Hidden -PassThru
        $serverProcess.EnableRaisingEvents = $true
        $null = $serverProcess.Handle
        $serverProcess.WaitForExit()
        $serverExitCode = $serverProcess.ExitCode
    }
    else {
        & $serverBinary @engineArguments -- @userArguments
        $serverExitCode = $LASTEXITCODE
    }
}
finally {
    [Environment]::SetEnvironmentVariable('SSF_LOBBY_PASSWORD', $priorLobbyPassword, 'Process')
    [Environment]::SetEnvironmentVariable('SSF_ADMIN_PASSWORD', $priorAdminPassword, 'Process')
    foreach ($secretPointer in $secretPointers) {
        [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($secretPointer)
    }
    $plainLobbyPassword = $null
    $plainAdminPassword = $null
}
exit $serverExitCode
