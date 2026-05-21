[CmdletBinding()]
param(
    [ValidateSet('pretooluse','sessionstart','stop')]
    [string]$Event = 'pretooluse',
    [string]$RepoPath = ''
)

$ErrorActionPreference = 'Continue'
$scriptDir = Split-Path -Parent $PSCommandPath
$userRoot = Split-Path -Parent $scriptDir
$sourceInfoPath = Join-Path $userRoot 'forge-source.txt'
$forgeRoot = $null
if (Test-Path -LiteralPath $sourceInfoPath) {
    foreach ($line in Get-Content -LiteralPath $sourceInfoPath -Encoding UTF8) {
        if ($line -match '^forge_source_repo=(.+)$' -and (Test-Path -LiteralPath $Matches[1])) {
            $forgeRoot = (Resolve-Path -LiteralPath $Matches[1]).Path
            break
        }
    }
}
if (-not $forgeRoot) { $forgeRoot = Split-Path -Parent $scriptDir }

if ([string]::IsNullOrWhiteSpace($RepoPath)) {
    $RepoPath = (Get-Location).Path
}

$hookRoot = Join-Path $forgeRoot 'hooks'
$stdin = [Console]::In.ReadToEnd()
try {
    switch ($Event) {
        'pretooluse' {
            $target = Join-Path $hookRoot 'forge-pretool-guard.ps1'
            if (-not (Test-Path -LiteralPath $target)) { exit 0 }
            $stdin | pwsh -NoLogo -NoProfile -ExecutionPolicy Bypass -File $target -RepoPath $RepoPath
            exit $LASTEXITCODE
        }
        'sessionstart' {
            $target = Join-Path $hookRoot 'forge-session-audit.ps1'
            if (-not (Test-Path -LiteralPath $target)) { exit 0 }
            $stdin | pwsh -NoLogo -NoProfile -ExecutionPolicy Bypass -File $target -RepoPath $RepoPath -Event SessionStart -Mode warn
            exit $LASTEXITCODE
        }
        'stop' {
            $target = Join-Path $hookRoot 'forge-session-audit.ps1'
            if (-not (Test-Path -LiteralPath $target)) { exit 0 }
            $stdin | pwsh -NoLogo -NoProfile -ExecutionPolicy Bypass -File $target -RepoPath $RepoPath -Event Stop -Mode warn
            exit $LASTEXITCODE
        }
    }
} catch {
    Write-Error $_.Exception.Message
    exit 1
}
