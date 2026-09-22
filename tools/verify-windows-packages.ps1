[CmdletBinding()]
param(
    [ValidateRange(0, 1800)]
    [int]$SoakSeconds = 0,
    [ValidateRange(1024, 65535)]
    [int]$Port = 18375,
    [string]$GodotExecutable = ''
)

$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'common.ps1')
if ($SoakSeconds -gt 0 -and $SoakSeconds -lt 60) { throw 'A requested soak must last at least 60 seconds.' }
# Private runtime qualification; release publishing still uses the build scripts
# and their attribution/sign-off gates. Do not conflate interoperability with
# asset provenance approval.
& python (Join-Path $PSScriptRoot 'update-release-metadata.py')
if ($LASTEXITCODE -ne 0) { throw 'Release metadata is stale.' }
& python (Join-Path $PSScriptRoot 'update-export-policy.py') --check
if ($LASTEXITCODE -ne 0) { throw 'Shipping resource allowlists are stale.' }
$godot = if ($GodotExecutable) { (Resolve-Path -LiteralPath $GodotExecutable).Path } else { Get-SsfGodotExecutable }
$outputRoot = Join-Path $SsfToolsRoot ('package-acceptance/' + [DateTime]::UtcNow.ToString('yyyyMMddTHHmmss') + '-' + [Guid]::NewGuid().ToString('N').Substring(0, 8))
Assert-SsfPathWithinTools -Path $outputRoot
New-Item -ItemType Directory -Path $outputRoot -Force | Out-Null
$serverPath = Join-Path $outputRoot 'SSF-server.exe'
$clientPath = Join-Path $outputRoot 'SSF-client.exe'
$importText = (& $godot --headless --path $SsfRepositoryRoot --log-file (Join-Path $outputRoot 'import.log') --editor --quit 2>&1 | Out-String)
Assert-SsfGodotResult -Output $importText -ExitCode $LASTEXITCODE -Name 'Package resource import'

foreach ($package in @(
    @{ Name = 'server'; Preset = 'Windows Dedicated Server'; Path = $serverPath },
    @{ Name = 'client'; Preset = "Windows $($SsfRelease.label)"; Path = $clientPath }
)) {
    $logPath = Join-Path $outputRoot "$($package.Name)-export.log"
    $text = (& $godot --headless --path $SsfRepositoryRoot --log-file $logPath --export-release $package.Preset $package.Path 2>&1 | Out-String)
    Assert-SsfGodotResult -Output $text -ExitCode $LASTEXITCODE -Name "$($package.Name) export"
    if (-not (Test-Path -LiteralPath $package.Path -PathType Leaf)) { throw 'Export artifact missing.' }
    $auditArguments = @((Join-Path $PSScriptRoot 'audit-package.py'), $package.Path, '--output', (Join-Path $outputRoot "$($package.Name)-audit.json"))
    if ($package.Name -eq 'server') { $auditArguments += '--server' }
    & python @auditArguments
    if ($LASTEXITCODE -ne 0) { throw "$($package.Name) resource audit failed." }
}
& python (Join-Path $PSScriptRoot 'verify-packaged-interop.py') --godot $godot --server $serverPath --client $clientPath --port $Port
if ($LASTEXITCODE -ne 0) { throw 'Packaged interoperability failed.' }
if ($SoakSeconds -gt 0) {
    & (Join-Path $PSScriptRoot 'verify-soak.ps1') -ClientCount 32 -DurationSeconds $SoakSeconds -Port $Port -ServerExecutable $serverPath
    if ($LASTEXITCODE -ne 0) { throw 'Packaged server soak failed.' }
}
Write-Host "Windows package acceptance passed. Private verification artifacts: $outputRoot"
