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
