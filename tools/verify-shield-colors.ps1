$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'common.ps1')
$captureRoot = Join-Path $SsfToolsRoot 'shield-color-verification'
New-Item -ItemType Directory -Path $captureRoot -Force | Out-Null
$stdout = Join-Path $captureRoot 'render.out.log'
$stderr = Join-Path $captureRoot 'render.err.log'
$engineLog = Join-Path $captureRoot 'render.engine.log'
$capture = Join-Path $captureRoot 'shield-colours.png'
$process = Start-Process -FilePath (Get-SsfGodotExecutable) -ArgumentList @(
    '--path', '.', '--audio-driver', 'Dummy', '--resolution', '1280x720',
    '--position', '-10000,-10000', '--log-file', ('"' + $engineLog + '"'),
    '--script', 'res://src/test/shield_color_verifier.gd', '--', ('"--capture=' + $capture + '"')
) -WorkingDirectory $SsfRepositoryRoot -WindowStyle Hidden -PassThru -Wait -RedirectStandardOutput $stdout -RedirectStandardError $stderr
$output = (Get-Content $stdout -Raw) + (Get-Content $stderr -Raw)
Assert-SsfGodotResult -Output $output -ExitCode $process.ExitCode -Name 'Rendered shield colours' -ExpectedPattern 'SHIELD_COLOURS_OK samples=24 guard_indicators=16'
Write-Output "Shield colour verification passed: four rarities, normal/window/confirmed states, both reduced-flash settings. Capture: $capture"
