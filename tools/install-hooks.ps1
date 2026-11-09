<#
.SYNOPSIS
Installs the repository's opt-in Git pre-commit hook.

.DESCRIPTION
The hook runs the export-allowlist and release-metadata checks (both well under
a second) so a stale export_presets.cfg is caught before commit instead of in CI.
Nothing installs it automatically. Re-run with -Force to replace a different
existing hook; remove .git/hooks/pre-commit to uninstall.
#>
[CmdletBinding()]
param([switch]$Force)

$ErrorActionPreference = 'Stop'
$repositoryRoot = Split-Path -Parent $PSScriptRoot
$hooksPath = (& git -C $repositoryRoot rev-parse --git-path hooks).Trim()
if ($LASTEXITCODE -ne 0) { throw 'This is not a Git checkout.' }
if (-not [System.IO.Path]::IsPathRooted($hooksPath)) { $hooksPath = Join-Path $repositoryRoot $hooksPath }
New-Item -ItemType Directory -Path $hooksPath -Force | Out-Null

$source = Join-Path $PSScriptRoot 'git-hooks/pre-commit'
$destination = Join-Path $hooksPath 'pre-commit'
if ((Test-Path -LiteralPath $destination) -and -not $Force) {
    if ((Get-FileHash -LiteralPath $destination).Hash -eq (Get-FileHash -LiteralPath $source).Hash) {
        Write-Host "The pre-commit hook is already installed at $destination."
        return
    }
    throw "A different pre-commit hook already exists at $destination. Re-run with -Force to replace it."
}
Copy-Item -LiteralPath $source -Destination $destination -Force
Write-Host "Installed the pre-commit hook at $destination."
