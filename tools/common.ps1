Set-StrictMode -Version Latest

$SsfRepositoryRoot = Split-Path -Parent $PSScriptRoot
$SsfRelease = (& python (Join-Path $PSScriptRoot 'release_metadata.py') | ConvertFrom-Json)
if ($LASTEXITCODE -ne 0) { throw 'Could not load release.json.' }
# The pinned engine lives in tools/engine.json, shared with tools/ssf_tools.py.
$SsfEngine = Get-Content -LiteralPath (Join-Path $PSScriptRoot 'engine.json') -Raw | ConvertFrom-Json
$SsfGodotRelease = [string]$SsfEngine.godot
$SsfGodotVersionTag = "$SsfGodotRelease-$($SsfEngine.status)"
$SsfGodotTemplateVersion = "$SsfGodotRelease.$($SsfEngine.status)"
$SsfToolsRoot = Join-Path $SsfRepositoryRoot '.tools'
$SsfGodotRoot = Join-Path $SsfToolsRoot 'godot'
$SsfGodotExecutable = Join-Path $SsfGodotRoot "Godot_v$($SsfGodotVersionTag)_win64_console.exe"
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

# Returns the engine and script error lines a gate must reject. Script errors are
# never allowlisted; engine errors are accepted only when a whole line matches.
# This is the PowerShell twin of unexpected_errors in tools/ssf_tools.py.
function Get-SsfUnexpectedGodotErrors {
    param(
        [Parameter(Mandatory = $true)][AllowEmptyString()][string]$Output,
        [string[]]$AllowedErrorPatterns = @()
    )
    $allowed = @('^ERROR: Failed to read the root certificate store\.$') + $AllowedErrorPatterns
    # The leading comma keeps an empty or single-line result an array under StrictMode.
    return ,@($Output -split "`r?`n" | ForEach-Object { $_.Trim() } | Where-Object {
        $line = $_
        if ($line.StartsWith('SCRIPT ERROR:')) { return $true }
        if (-not $line.StartsWith('ERROR:')) { return $false }
        foreach ($pattern in $allowed) {
            if ($line -match $pattern) { return $false }
        }
        return $true
    })
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
    $unexpected = Get-SsfUnexpectedGodotErrors -Output $Output -AllowedErrorPatterns $AllowedErrorPatterns
    if ($unexpected.Count -gt 0) {
        throw "$Name emitted unexpected Godot errors: $($unexpected -join ' | ')"
    }
}

function Copy-SsfReleaseDocument {
    param(
        [Parameter(Mandatory = $true)][string]$Source,
        [Parameter(Mandatory = $true)][string]$Destination
    )
    & python (Join-Path $PSScriptRoot 'release_metadata.py') render $Source $Destination
    if ($LASTEXITCODE -ne 0) { throw "Could not render release document $Source." }
    return $Destination
}

function Assert-SsfShippingPolicy {
    & python (Join-Path $PSScriptRoot 'update-release-metadata.py')
    if ($LASTEXITCODE -ne 0) { throw 'Release metadata is stale.' }
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
