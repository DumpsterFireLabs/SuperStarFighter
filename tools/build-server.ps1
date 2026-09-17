[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'common.ps1')
Assert-SsfShippingPolicy
$godot = Get-SsfGodotExecutable
$buildRoot = Join-Path $SsfRepositoryRoot "$($SsfRelease.directory)/server"
$serverPath = Join-Path $buildRoot 'SuperStarFighter-Server.exe'
$logPath = Join-Path $buildRoot 'server-smoke.log'
New-Item -ItemType Directory -Path $buildRoot -Force | Out-Null

& python (Join-Path $PSScriptRoot 'update-export-policy.py') --check
if ($LASTEXITCODE -ne 0) { throw 'Export resource lists are stale.' }
& (Join-Path $PSScriptRoot 'verify-foundation.ps1')
if ($LASTEXITCODE -ne 0) { throw 'Foundation verification failed.' }
& $godot --headless --path $SsfRepositoryRoot --export-release 'Windows Dedicated Server' $serverPath
if ($LASTEXITCODE -ne 0) { throw 'Dedicated server export failed.' }
& python (Join-Path $PSScriptRoot 'audit-package.py') $serverPath --server --output (Join-Path $buildRoot 'package-audit.json')
if ($LASTEXITCODE -ne 0) { throw 'Dedicated server package audit failed.' }

# Run outside the source tree, without --path or --server: the artifact must
# select server mode and resolve its own embedded resources independently.
$process = Start-Process -FilePath $serverPath -WorkingDirectory $buildRoot -WindowStyle Hidden -PassThru `
    -ArgumentList @('--log-file', $logPath, '--', '--password=export-smoke', '--port=17820', '--test-server-duration=2')
if (-not $process.WaitForExit(20000)) { Stop-Process -Id $process.Id -Force; throw 'Server smoke timed out.' }
$text = Get-Content -LiteralPath $logPath -Raw
$errors = $text -split "`r?`n" | Where-Object { $_ -match '^(SCRIPT ERROR:|ERROR:)' -and $_ -notmatch 'root certificate store' }
if ($process.ExitCode -ne 0 -or $errors -or -not $text.Contains('SSF_MODE_READY=server') -or -not $text.Contains('SSF_SERVER_GRACEFUL_SHUTDOWN=test_duration')) {
    throw 'Standalone server smoke failed.'
}
foreach ($name in @('THIRD_PARTY_NOTICES.txt', 'GODOT_COPYRIGHT.txt', 'SERVER_README.txt')) {
    Copy-Item -LiteralPath (Join-Path $SsfRepositoryRoot "docs/$name") -Destination $buildRoot
}
$files = @($serverPath) + @('THIRD_PARTY_NOTICES.txt', 'GODOT_COPYRIGHT.txt', 'SERVER_README.txt' | ForEach-Object { Join-Path $buildRoot $_ })
Compress-Archive -LiteralPath $files -DestinationPath (Join-Path $buildRoot "SuperStarFighter-$($SsfRelease.tag)-Server-Windows-x64.zip") -Force
Write-Host "Dedicated server export, resource audit and isolated startup passed: $serverPath"
