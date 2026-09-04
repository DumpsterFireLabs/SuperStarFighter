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
    [switch]$CompetitiveView
)

$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'common.ps1')

$godot = Get-SsfGodotExecutable
$userArguments = @('--server', "--port=$Port", "--server-name=$ServerName", "--max-players=$MaxPlayers", "--rounds-to-win=$RoundsToWin")
if ($CompetitiveView) { $userArguments += "--competitive-view" }
if (-not [string]::IsNullOrWhiteSpace($PasswordFile)) {
    $resolvedPasswordFile = (Resolve-Path -LiteralPath $PasswordFile -ErrorAction Stop).Path
    $userArguments += "--password-file=$resolvedPasswordFile"
}
if ($AdminPort -gt 0) {
    $userArguments += "--admin-port=$AdminPort"
    if (-not [string]::IsNullOrWhiteSpace($AdminPasswordFile)) {
        $resolvedAdminPasswordFile = (Resolve-Path -LiteralPath $AdminPasswordFile -ErrorAction Stop).Path
        $userArguments += "--admin-password-file=$resolvedAdminPasswordFile"
    }
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
        $secureAdminPassword = Read-Host 'Admin password' -AsSecureString
        $adminPointer = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($secureAdminPassword)
        $secretPointers.Add($adminPointer)
        $plainAdminPassword = [Runtime.InteropServices.Marshal]::PtrToStringBSTR($adminPointer)
        if ([string]::IsNullOrEmpty($plainAdminPassword) -or $plainAdminPassword.Length -gt 64) {
            throw 'Admin password must contain 1-64 printable characters.'
        }
        [Environment]::SetEnvironmentVariable('SSF_ADMIN_PASSWORD', $plainAdminPassword, 'Process')
        $plainAdminPassword = $null
    }
    & $godot --headless --path $SsfRepositoryRoot -- @userArguments
    $serverExitCode = $LASTEXITCODE
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
