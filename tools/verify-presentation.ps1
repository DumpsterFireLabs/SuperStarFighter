[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'common.ps1')

$godot = Get-SsfGodotExecutable
$captureRoot = Join-Path $SsfToolsRoot 'presentation-verification'
Assert-SsfPathWithinTools -Path $captureRoot
New-Item -ItemType Directory -Path $captureRoot -Force | Out-Null

foreach ($resolution in @(
    @{ Label = '1280x720'; Width = 1280; Height = 720 },
    @{ Label = '1920x1080'; Width = 1920; Height = 1080 },
    @{ Label = '2560x1080'; Width = 2560; Height = 1080 },
    @{ Label = '2880x1920'; Width = 2880; Height = 1920 },
    @{ Label = '3440x1440'; Width = 3440; Height = 1440 },
    @{ Label = '5120x1440'; Width = 5120; Height = 1440 }
)) {
    $arguments = @(
        '--path', '.', '--audio-driver', 'Dummy', '--resolution',
        "$($resolution.Width)x$($resolution.Height)", '--position', '-10000,-10000',
        '--script', 'res://src/test/presentation_capture.gd', '--',
        "--capture-dir=$($captureRoot.Replace('\', '/'))",
        "--capture-label=$($resolution.Label)"
    )
    $stdout = Join-Path $captureRoot "$($resolution.Label).out.log"
    $stderr = Join-Path $captureRoot "$($resolution.Label).err.log"
    Remove-Item -LiteralPath @($stdout, $stderr) -Force -ErrorAction SilentlyContinue
    $process = Start-Process -FilePath $godot `
        -ArgumentList $arguments `
        -WorkingDirectory $SsfRepositoryRoot `
        -RedirectStandardOutput $stdout `
        -RedirectStandardError $stderr `
        -WindowStyle Hidden `
        -Wait `
        -PassThru
    $combined = ''
    if (Test-Path -LiteralPath $stdout) { $combined += Get-Content -LiteralPath $stdout -Raw }
    if (Test-Path -LiteralPath $stderr) { $combined += Get-Content -LiteralPath $stderr -Raw }
    if ($process.ExitCode -ne 0 -or -not $combined.Contains("PRESENTATION_CAPTURE_OK=$($resolution.Label)") -or $combined.Contains('SCRIPT ERROR:') -or $combined.Contains('ERROR:')) {
        throw "Presentation capture failed for $($resolution.Label): $combined"
    }
    foreach ($screen in @('splash', 'menu', 'host_menu', 'settings', 'fullscreen_settings', 'controls', 'lobby_32', 'lobby_npc_difficulties', 'draft', 'draft_bye', 'heat_ready', 'heat_begin', 'combat', 'map_core_arena', 'map_riftline', 'map_prism_array', 'map_twin_suns', 'map_dead_freight', 'map_longwave_array', 'map_broken_orbit', 'map_switchyard', 'map_solar_tide', 'map_relay_zero', 'scoreboard', 'scoreboard_card_hover', 'spectator', 'pause', 'results', 'results_card_hover', 'error')) {
        $imagePath = Join-Path $captureRoot "$($resolution.Label)_$screen.png"
        if (-not (Test-Path -LiteralPath $imagePath) -or (Get-Item -LiteralPath $imagePath).Length -lt 4096) {
            throw "Presentation capture $imagePath is missing or unexpectedly small."
        }
    }
}

Write-Host "Presentation verification passed: all ten round maps plus splash, menus, settings, controller bindings, 32-player lobby/options/colour selection, draft, READY/BEGIN alerts, combat powerups, scoreboard/card hover, spectator, pause, results/card hover, and error screens rendered at 1280x720, 1920x1080, 2560x1080, 2880x1920, 3440x1440, and 5120x1440."
