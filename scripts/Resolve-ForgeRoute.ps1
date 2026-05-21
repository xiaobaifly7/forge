[CmdletBinding()]
param(
    [string]$Prompt = '',
    [ValidateSet('quick','build','fix','full','ship','full-auto')][string]$Mode = 'quick',
    [string]$Phase = '',
    [switch]$Json
)

$ErrorActionPreference = 'Stop'
$executionJson = & pwsh -NoLogo -NoProfile -ExecutionPolicy Bypass -File (Join-Path $PSScriptRoot 'Resolve-ForgeExecutionMode.ps1') -Prompt $Prompt -Mode $Mode -Json
$execution = $executionJson | ConvertFrom-Json
$ceJson = & pwsh -NoLogo -NoProfile -ExecutionPolicy Bypass -File (Join-Path $PSScriptRoot 'Resolve-ForgeCeActivation.ps1') -Prompt $Prompt -Mode $Mode -Execution $execution.execution -Phase $Phase -Json
$ce = $ceJson | ConvertFrom-Json
$text = ([string]$Prompt).ToLowerInvariant()

$level = 'L1'
if ($execution.execution -eq 'audit-only') { $level = 'L0' }
elseif ($Mode -in @('build','fix')) { $level = 'L2' }
elseif ($Mode -in @('full','ship','full-auto') -or $text -match '认证|安全|权限|支付|数据库|schema|migration|持久化|共享|跨模块|全局|依赖升级|高风险') { $level = 'L3' }
if ($text -match 'l4|长期|多阶段|milestone|phase|阶段|自治|持续') { $level = 'L4' }

$frameworks = [ordered]@{
    forge = 'router,state,verify'
    bmad = if ($execution.execution -eq 'audit-only') { 'skip' } elseif ($level -in @('L3','L4') -or $Mode -in @('full','full-auto')) { 'planning:requirements,architecture,stories,acceptance' } else { 'skip' }
    superpowers = if ($execution.execution -ne 'audit-only') { 'execution:tdd,debug,verification' } else { 'audit-only' }
    ce = if ($ce.enabled) { @($ce.commands) } else { @() }
    gsd = if ($level -eq 'L4' -or $Mode -eq 'ship' -or $Phase -match 'handoff|ship|done') { 'handoff,next-actions' } else { 'skip' }
    gstack = if ($Mode -eq 'ship' -or $text -match 'ship|release|qa|canary|benchmark|最终|验收') { 'final-gate' } elseif ($level -in @('L3','L4') -and $text -match 'review|审查|高风险|安全|认证') { 'review-gate' } else { 'skip' }
}

$result = [ordered]@{
    ok = $true
    level = $level
    mode = $Mode
    execution = $execution.execution
    explicit = $execution.explicit
    phase = $Phase
    frameworks = $frameworks
    ce_enabled = $ce.enabled
    ce_commands = @($ce.commands)
    reasons = @($execution.reasons + $ce.reasons | Select-Object -Unique)
}
if ($Json) { $result | ConvertTo-Json -Depth 10 } else {
    "level=$($result.level)"
    "mode=$($result.mode)"
    "execution=$($result.execution)"
    "frameworks=$(($result.frameworks.GetEnumerator() | ForEach-Object { $_.Key + ':' + (@($_.Value) -join '+') }) -join ',')"
    "reasons=$(@($result.reasons) -join ',')"
}
