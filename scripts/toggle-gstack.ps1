[CmdletBinding()]
param(
    [ValidateSet('enable','disable','status')]
    [string]$Action = 'status',
    [string]$SkillsRoot = (Join-Path $env:USERPROFILE '.claude\skills')
)

$ErrorActionPreference = 'Stop'

$active = Join-Path $SkillsRoot 'gstack'
$disabled = Join-Path $SkillsRoot '.gstack-disabled'

function Invoke-SafeRename {
    param([string]$From, [string]$NewName)
    try {
        Rename-Item -LiteralPath $From -NewName $NewName -ErrorAction Stop
        return $true
    } catch {
        Write-Host ("Rename failed: {0}" -f $_.Exception.Message) -ForegroundColor Red
        Write-Host 'Possible cause: a process (Claude Code / editor / shell) has files under gstack open.' -ForegroundColor Red
        Write-Host 'Try: close Claude Code completely, then re-run this script from a fresh shell.' -ForegroundColor Yellow
        return $false
    }
}

switch ($Action) {
    'status' {
        if (Test-Path -LiteralPath $active) { Write-Host 'gstack: ENABLED' -ForegroundColor Green }
        elseif (Test-Path -LiteralPath $disabled) { Write-Host 'gstack: DISABLED' -ForegroundColor Yellow }
        else { Write-Host 'gstack: NOT FOUND' -ForegroundColor Red }
    }
    'enable' {
        if (Test-Path -LiteralPath $disabled) {
            if (Invoke-SafeRename -From $disabled -NewName 'gstack') {
                Write-Host 'gstack ENABLED (restart Claude Code to take effect)' -ForegroundColor Green
            }
        } elseif (Test-Path -LiteralPath $active) {
            Write-Host 'gstack already enabled' -ForegroundColor Yellow
        } else {
            Write-Host 'gstack not found' -ForegroundColor Red
        }
    }
    'disable' {
        if (Test-Path -LiteralPath $active) {
            if (Invoke-SafeRename -From $active -NewName '.gstack-disabled') {
                Write-Host 'gstack DISABLED (restart Claude Code to take effect)' -ForegroundColor Green
            }
        } elseif (Test-Path -LiteralPath $disabled) {
            Write-Host 'gstack already disabled' -ForegroundColor Yellow
        } else {
            Write-Host 'gstack not found' -ForegroundColor Red
        }
    }
}
