[CmdletBinding()]
param(
    [string]$RepoPath = '.',
    [string]$Prompt = '',
    [ValidateSet('quick','build','fix','full','ship','full-auto')][string]$Mode = 'quick',
    [switch]$Json
)

$ErrorActionPreference = 'Stop'
$repo = (Resolve-Path -LiteralPath $RepoPath).Path
$text = ([string]$Prompt).ToLowerInvariant()
$hasDiff = $false
try {
    $status = @(& rtk git -C $repo status --short 2>$null | Where-Object { $_ -and $_.Trim() -and $_.Trim() -ne 'ok' })
    $hasDiff = ($status.Count -gt 0)
} catch {}

$routeJson = & pwsh -NoLogo -NoProfile -ExecutionPolicy Bypass -File (Join-Path $PSScriptRoot 'Resolve-ForgeRoute.ps1') -Prompt $Prompt -Mode $Mode -Json
$route = $routeJson | ConvertFrom-Json
$highRisk = ($route.level -in @('L3','L4')) -or ($text -match '认证|安全|权限|支付|数据库|schema|migration|持久化|共享|跨模块|public contract|高风险')
$ship = ($Mode -eq 'ship') -or ($text -match 'ship|release|发布|交付|final|最终|qa|canary|benchmark')

$steps = @()
if ($hasDiff -or $Mode -in @('build','fix','full','ship','full-auto')) {
    $steps += [ordered]@{ name='codex_review'; required=$true; command='/codex:review'; purpose='default diff/code review inside Claude Code' }
}
if ($highRisk) {
    $steps += [ordered]@{ name='ce_code_review'; required=$true; command='ce-code-review'; purpose='high-risk specialist review and reusable findings' }
}
if ($ship) {
    $steps += [ordered]@{ name='gstack_gate'; required=$true; command='gstack gate'; purpose='final ship/release gate' }
}
$steps += [ordered]@{ name='forge_verify'; required=$true; command='forge verify -RepoPath <repo> -Full'; purpose='machine release gate' }

$result = [ordered]@{
    ok = $true
    repo = $repo
    has_diff = $hasDiff
    mode = $Mode
    level = $route.level
    high_risk = $highRisk
    ship = $ship
    steps = @($steps)
}
if ($Json) { $result | ConvertTo-Json -Depth 8 } else { foreach($s in $steps){ "$($s.name): $($s.command)" } }
