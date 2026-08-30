param(
    [ValidateRange(1024, 65535)]
    [int]$Port = 7001,
    [Parameter(Mandatory)]
    [ValidateSet('status', 'players', 'kick', 'ban', 'block', 'unblock', 'set', 'set-password', 'shutdown')]
    [string]$Command,
    [int]$PeerId = 0,
    [string]$Source,
    [string]$Setting,
    [string]$Value,
    [string]$AdminPasswordFile
)

$ErrorActionPreference = 'Stop'

function Read-SecretText {
    param([string]$Prompt, [string]$FilePath, [string]$EnvironmentName)
    if (-not [string]::IsNullOrWhiteSpace($FilePath)) {
        return [System.IO.File]::ReadAllText((Resolve-Path -LiteralPath $FilePath).Path).TrimEnd("`r", "`n")
    }
    $environmentValue = [Environment]::GetEnvironmentVariable($EnvironmentName, 'Process')
    if (-not [string]::IsNullOrEmpty($environmentValue)) {
        return $environmentValue
    }
    $secureValue = Read-Host $Prompt -AsSecureString
    $pointer = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($secureValue)
    try {
        return [Runtime.InteropServices.Marshal]::PtrToStringBSTR($pointer)
    }
    finally {
        [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($pointer)
    }
}

function Get-Sha256Hex {
    param([string]$Text)
    $sha256 = [Security.Cryptography.SHA256]::Create()
    try {
        $bytes = [Text.Encoding]::UTF8.GetBytes($Text)
        return ([BitConverter]::ToString($sha256.ComputeHash($bytes))).Replace('-', '').ToLowerInvariant()
    }
    finally {
        $sha256.Dispose()
    }
}

$adminPassword = Read-SecretText -Prompt 'Admin password' -FilePath $AdminPasswordFile -EnvironmentName 'SSF_ADMIN_PASSWORD'
$client = [Net.Sockets.TcpClient]::new()
$reader = $null
$writer = $null
try {
    $client.Connect('127.0.0.1', $Port)
    $stream = $client.GetStream()
    $reader = [IO.StreamReader]::new($stream, [Text.Encoding]::UTF8, $false, 4096, $true)
    $writer = [IO.StreamWriter]::new($stream, [Text.UTF8Encoding]::new($false), 4096, $true)
    $writer.AutoFlush = $true
    $challengeLine = $reader.ReadLine()
    if ($null -eq $challengeLine) {
        throw 'The admin endpoint closed before sending a challenge.'
    }
    $challengeMessage = $challengeLine | ConvertFrom-Json
    if ($challengeMessage.event -ne 'challenge' -or $challengeMessage.challenge -notmatch '^[0-9a-f]{64}$') {
        throw 'The server did not provide a valid admin challenge.'
    }
    $separator = [char]0x1f
    $proof = Get-Sha256Hex -Text ("ssf-admin-auth-v1$separator$($challengeMessage.challenge)$separator$adminPassword")
    $writer.WriteLine((@{ command = 'authenticate'; proof = $proof } | ConvertTo-Json -Compress))
    $authenticationLine = $reader.ReadLine()
    if ($null -eq $authenticationLine) {
        throw 'The admin endpoint closed during authentication.'
    }
    $authentication = $authenticationLine | ConvertFrom-Json
    if (-not $authentication.ok) {
        throw 'Admin authentication failed.'
    }
    $request = @{ command = $Command.Replace('-', '_') }
    switch ($Command) {
        'kick' { $request.peer_id = $PeerId }
        'ban' { $request.peer_id = $PeerId }
        'block' { $request.source = $Source }
        'unblock' { $request.source = $Source }
        'set' {
            $request.setting = $Setting
            try { $request.value = $Value | ConvertFrom-Json } catch { $request.value = $Value }
        }
        'set-password' {
            $request.password = Read-SecretText -Prompt 'New lobby password' -FilePath '' -EnvironmentName 'SSF_NEW_LOBBY_PASSWORD'
        }
    }
    $writer.WriteLine(($request | ConvertTo-Json -Compress))
    $responseLine = $reader.ReadLine()
    if ($null -eq $responseLine) {
        throw 'The admin endpoint closed before sending a response.'
    }
    $response = $responseLine | ConvertFrom-Json
    $response | ConvertTo-Json -Depth 12
    if (-not $response.ok) {
        exit 1
    }
}
finally {
    $adminPassword = $null
    if ($null -ne $reader) { $reader.Dispose() }
    if ($null -ne $writer) { $writer.Dispose() }
    $client.Dispose()
}
