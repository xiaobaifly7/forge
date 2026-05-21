[CmdletBinding()]
param(
    [string]$Prompt = '',
    [ValidateSet('quick','build','fix','full','ship','full-auto')][string]$Mode = 'quick',
    [ValidateSet('audit-only','auto','guided-full','full-auto')][string]$Execution = 'audit-only',
    [string]$Phase = '',
    [switch]$Json
)

$ErrorActionPreference = 'Stop'
$text = ([string]$Prompt).ToLowerInvariant()
$reasons = [System.Collections.Generic.List[string]]::new()
function Add-Reason { param([string]$Reason) if (-not $reasons.Contains($Reason)) { [void]$reasons.Add($Reason) } }

$ceAvailable = $false
$claudeSkills = Join-Path $env:USERPROFILE '.claude\skills'
$codexSkills = Join-Path $env:USERPROFILE '.codex\skills'
foreach ($root in @($claudeSkills, $codexSkills)) {
    if (Test-Path -LiteralPath (Join-Path $root 'ce-compound\SKILL.md')) { $ceAvailable = $true }
}

$enabled = $false
$commands = @()
if ($text -match '/ce-|\$ce-|\blfg\b|/lfg|用\s*ce|compound engineering') {
    $enabled = $true; Add-Reason 'explicit_ce_request'
}
if ($Mode -eq 'ship' -or $Phase -match 'ship|release|handoff|review|qa|m1|done') {
    $enabled = $true; Add-Reason 'phase_or_ship_compound'
}
if ($Execution -eq 'guided-full' -or $Mode -in @('full','full-auto')) {
    if ($text -match '复盘|沉淀|总结|learnings|learning|review pattern|可复用|知识|经验') {
        $enabled = $true; Add-Reason 'full_learning_signal'
    }
}
if ($text -match 'pr|pull request|代码审查|code review|review|反馈|resolve.*feedback|浏览器测试|test browser') {
    $enabled = $true; Add-Reason 'review_or_pr_signal'
}
if ($text -match 'debug|排查|定位|根因|复现') {
    $enabled = $true; Add-Reason 'debug_signal'
}

if ($enabled -and $ceAvailable) {
    if ($text -match 'debug|排查|定位|根因|复现') { $commands += 'ce-debug' }
    if ($text -match 'pr|pull request|反馈|resolve.*feedback') { $commands += 'ce-resolve-pr-feedback' }
    if ($text -match '代码审查|code review|review|高风险|安全|认证|schema|数据库|迁移') { $commands += 'ce-code-review' }
    if ($text -match '浏览器测试|test browser') { $commands += 'ce-test-browser' }
    if ($text -match '复盘|沉淀|总结|learnings|learning|可复用|知识|经验' -or $Mode -eq 'ship' -or $Phase -match 'ship|release|handoff|m1|done') { $commands += 'ce-compound' }
    if ($commands.Count -lt 1) { $commands += 'ce-compound' }
}

$result = [ordered]@{
    ok = $true
    ce_available = $ceAvailable
    enabled = [bool]($enabled -and $ceAvailable)
    mode = $Mode
    execution = $Execution
    phase = $Phase
    commands = @($commands | Select-Object -Unique)
    reasons = @($reasons)
}
if ($Json) { $result | ConvertTo-Json -Depth 8 } else { "ce_enabled=$($result.enabled)"; "commands=$(@($result.commands) -join ',')"; "reasons=$(@($result.reasons) -join ',')" }
