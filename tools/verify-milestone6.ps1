[CmdletBinding()]
param(
    [ValidateRange(2, 32)]
    [int]$ClientCount = 32,
    [ValidateRange(60, 1800)]
    [int]$SoakDurationSeconds = 600,
    [ValidateRange(1024, 65495)]
    [int]$BasePort = 17400
)

$ErrorActionPreference = 'Stop'

Write-Host '== Foundation, parsing, and unit coverage =='
& (Join-Path $PSScriptRoot 'verify-foundation.ps1')
Write-Host '== Authoritative protocol integration =='
& (Join-Path $PSScriptRoot 'verify-network.ps1') -Port $BasePort
Write-Host '== Complete match integration =='
& (Join-Path $PSScriptRoot 'verify-match-loop.ps1') -Port ($BasePort + 1)
Write-Host '== NPC lobby integration =='
& (Join-Path $PSScriptRoot 'verify-npc-lobby.ps1') -Port ($BasePort + 2)
Write-Host '== Malformed and excessive traffic isolation =='
& (Join-Path $PSScriptRoot 'verify-hardening.ps1') -Port ($BasePort + 3)
Write-Host '== Configurable smoke =='
& (Join-Path $PSScriptRoot 'verify-smoke.ps1') -ClientCount 2 -DurationSeconds 20 -Port ($BasePort + 4)
Write-Host '== Configurable load and soak =='
& (Join-Path $PSScriptRoot 'verify-soak.ps1') -ClientCount $ClientCount -DurationSeconds $SoakDurationSeconds -Port ($BasePort + 5)
Write-Host "Milestone 6 verification passed for $ClientCount clients and a $SoakDurationSeconds-second soak."
