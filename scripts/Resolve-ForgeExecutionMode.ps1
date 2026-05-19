[CmdletBinding()]
param(
    [string]$Prompt,
    [ValidateSet('quick','build','fix','full','ship','full-auto')][string]$Mode = 'full',
    [string]$PromptText = '',
    [switch]$Json
)
$ErrorActionPreference = 'Stop'
# 统一 prompt 文本源：PromptText 优先（调用方更明确的显式传参），否则回退 Prompt。
$rawText = if([string]::IsNullOrEmpty($PromptText)) { [string]$Prompt } else { [string]$PromptText }
$text = $rawText.ToLowerInvariant()
$reasons = [System.Collections.Generic.List[string]]::new()
function Add-Reason($r){ if(-not $reasons.Contains($r)){ [void]$reasons.Add($r) } }
$explicit = $false
$execution = $null

# full-auto 反向 gate 白名单（governance §11 升档加强 A）。
$FullAutoKeywords = @('full-auto','full auto','端到端自动推进','不要分阶段停顿','一气呵成')
function Test-FullAutoExplicit {
    param([string]$Source)
    if([string]::IsNullOrWhiteSpace($Source)) { return $false }
    $lower = $Source.ToLowerInvariant()
    foreach($kw in $FullAutoKeywords){
        if($lower.Contains($kw.ToLowerInvariant())) { return $true }
    }
    return $false
}

# Explicit user intent always wins.
if($text -match 'full-auto|端到端自动推进|不要分阶段停顿') { $explicit=$true; $execution='full-auto'; Add-Reason 'explicit_full_auto' }
elseif($text -match '只读|只看|看一下|看看|审计|audit-only|不要改文件|不改文件|别改文件|无需修改|不用修改|只做分析|仅分析|状态确认|查状态|评估一下|梳理一下|总结一下') { $explicit=$true; $execution='audit-only'; Add-Reason 'explicit_readonly_or_audit' }
elseif($text -match '(?<!不)(?<!别)(?<!无需)(?<!不要)\bauto\b|自动模式|自动去做|自动执行|自己做完|直接做完|直接搞定|全自动') { $explicit=$true; $execution='auto'; Add-Reason 'explicit_auto' }
elseif($text -match '\bguide\b|guided|指导模式|引导模式|带我一步步|一步一步|一步步|教我|先问我|每步确认|分阶段确认|等我确认') { $explicit=$true; $execution='guided-full'; Add-Reason 'explicit_guided' }

if(-not $execution){
    if($Mode -eq 'quick') { $execution='audit-only'; Add-Reason 'quick_audit_only' }
    elseif($Mode -eq 'full-auto') { $execution='full-auto'; Add-Reason 'mode_full_auto' }
    elseif($Mode -eq 'ship') { $execution='auto'; Add-Reason 'ship_default_auto_with_gate' }
    elseif($Mode -in @('build','fix') -and $text -match '需求.*清楚|需求已经定|现有|当前|修掉|失败|bug|test|测试|实现|加一个|扩一下|帮我搞定|继续') { $execution='auto'; Add-Reason 'clear_build_or_fix_auto' }
    elseif($text -match '方案|规划|设计|架构|怎么做|评估|有哪些|不确定|先看|先分析|需求不清|讨论') { $execution='guided-full'; Add-Reason 'needs_guidance_or_clarification' }
    elseif($Mode -eq 'full' -or $text -match '认证|安全|权限|支付|数据库|schema|migration|持久化|共享|跨模块|全局|依赖升级|高风险|长期|多阶段') { $execution='guided-full'; Add-Reason 'high_risk_or_full_default_guided' }
    else { $execution='auto'; Add-Reason 'default_auto_for_clear_task' }
}

# full-auto 反向 gate：execution=full-auto 必须由 prompt 中明确关键词触发，否则强制降级。
$fullAutoExplicit = $false
$downgradeReason = $null
if($execution -eq 'full-auto'){
    $fullAutoExplicit = Test-FullAutoExplicit -Source $rawText
    if(-not $fullAutoExplicit){
        $downgradeReason = if([string]::IsNullOrWhiteSpace($rawText)) { 'full_auto_missing_prompt_text' } else { 'full_auto_keyword_absent' }
        Write-Warning "[forge] full-auto 反向 gate 触发：$downgradeReason；强制降级 execution=guided-full。允许关键词：$($FullAutoKeywords -join ', ')"
        $execution = 'guided-full'
        $explicit = $false
        Add-Reason "downgraded_from_full_auto:$downgradeReason"
    }
}

$result=[ordered]@{
    ok=$true
    mode=$Mode
    execution=$execution
    explicit=$explicit
    full_auto_explicit=$fullAutoExplicit
    downgrade_reason=$downgradeReason
    reasons=@($reasons)
}
if($Json){ $result | ConvertTo-Json -Depth 6 }
else {
    "forge_execution=$execution"
    "explicit=$explicit"
    "full_auto_explicit=$fullAutoExplicit"
    if($downgradeReason){ "downgrade_reason=$downgradeReason" }
    "reasons=$(@($reasons) -join ',')"
}
