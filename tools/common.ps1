Set-StrictMode -Version Latest

$SsfRepositoryRoot = Split-Path -Parent $PSScriptRoot
$SsfGodotVersionTag = '4.7.2-stable'
$SsfGodotTemplateVersion = '4.7.2.stable'
$SsfToolsRoot = Join-Path $SsfRepositoryRoot '.tools'
$SsfGodotRoot = Join-Path $SsfToolsRoot 'godot'
$SsfGodotExecutable = Join-Path $SsfGodotRoot 'Godot_v4.7.2-stable_win64_console.exe'
$SsfGodotDataRoot = Join-Path $SsfGodotRoot 'editor_data'
$SsfExportTemplateRoot = Join-Path $SsfGodotDataRoot "export_templates\$SsfGodotTemplateVersion"

function Get-SsfGodotExecutable {
    if (-not (Test-Path -LiteralPath $SsfGodotExecutable -PathType Leaf)) {
        throw "Godot $SsfGodotVersionTag is not bootstrapped. Run .\tools\bootstrap.ps1 first."
    }
    return $SsfGodotExecutable
}

function New-SsfVerificationLogPath {
    param([Parameter(Mandatory = $true)][string]$Name)
    $logRoot = Join-Path $SsfToolsRoot 'verification-logs'
    New-Item -ItemType Directory -Path $logRoot -Force | Out-Null
    $label = $Name -replace '[^a-zA-Z0-9-]', '-'
    return Join-Path $logRoot "$label-$([Guid]::NewGuid().ToString('N')).log"
}

function Assert-SsfGodotResult {
    param(
        [Parameter(Mandatory = $true)][AllowEmptyString()][string]$Output,
        [Parameter(Mandatory = $true)][int]$ExitCode,
        [string]$Name = 'Godot verification',
        [int]$ExpectedExitCode = 0,
        [string]$ExpectedPattern = '',
        [string[]]$AllowedErrorPatterns = @()
    )
    if ($ExitCode -ne $ExpectedExitCode) {
        throw "$Name exited with $ExitCode; expected $ExpectedExitCode."
    }
    if ($ExpectedPattern -and $Output -notmatch $ExpectedPattern) {
        throw "$Name did not emit the required completion marker."
    }
    # Engine errors can return a value and allow an otherwise passing summary.
    # Script errors are never allowlisted; environment allowances match full lines.
    $allowed = @('^ERROR: Failed to read the root certificate store\.$') + $AllowedErrorPatterns
    $unexpected = @($Output -split "`r?`n" | Where-Object {
        $line = $_.TrimStart()
        if ($line.StartsWith('SCRIPT ERROR:')) { return $true }
        if (-not $line.StartsWith('ERROR:')) { return $false }
        foreach ($pattern in $allowed) {
            if ($line -match $pattern) { return $false }
        }
        return $true
    })
    if ($unexpected.Count -gt 0) {
        throw "$Name emitted unexpected Godot errors: $($unexpected -join ' | ')"
    }
}

function Assert-SsfShippingPolicy {
    & python (Join-Path $SsfRepositoryRoot 'tools/update-export-policy.py') --check
    if ($LASTEXITCODE -ne 0) { throw 'Shipping resource allowlists are stale.' }
    & python (Join-Path $SsfRepositoryRoot 'tools/verify-attribution.py')
    if ($LASTEXITCODE -ne 0) { throw 'Attribution inventory verification failed.' }
}

function Assert-SsfPathWithinTools {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Path
    )

    $resolvedTools = [System.IO.Path]::GetFullPath($SsfToolsRoot).TrimEnd('\') + '\'
    $resolvedPath = [System.IO.Path]::GetFullPath($Path)
    if (-not $resolvedPath.StartsWith($resolvedTools, [System.StringComparison]::OrdinalIgnoreCase)) {
        throw "Refusing to modify a tool path outside $SsfToolsRoot`: $resolvedPath"
    }
}
