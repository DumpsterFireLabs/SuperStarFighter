$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'common.ps1')

$godot = Get-SsfGodotExecutable
& $godot --editor --path $SsfRepositoryRoot
exit $LASTEXITCODE

