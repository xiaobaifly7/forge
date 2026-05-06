#requires -Version 7.0
[CmdletBinding()]
param(
    [string]$RepoPath = '',
    [ValidateSet('SessionStart','Stop')][string]$Event = 'SessionStart',
    [ValidateSet('warn','fail-close')][string]$Mode = 'warn',
    [switch]$DryRun
)

$ErrorActionPreference = 'Stop'
$hookStart = Get-Date
$hookName = 'forge-session-audit'

if ($PSBoundParameters.ContainsKey('Verbose') -and $VerbosePreference -ne 'SilentlyContinue') {
    $env:FORGE_HOOK_VERBOSE = '1'
}

# ── 模块加载（失败 fail-open） ──────────────────────────────
try {
    Import-Module (Join-Path $PSScriptRoot 'forge-hook-common.psm1') -Force -DisableNameChecking
} catch {
    $fallback = Join-Path $env:USERPROFILE '.claude\logs\forge-hook-fallback.jsonl'
    try {
        $dir = Split-Path -Parent $fallback
        if (-not (Test-Path -LiteralPath $dir)) { New-Item -ItemType Directory -Force -Path $dir | Out-Null }
        ([ordered]@{ time=(Get-Date).ToString('o'); hook=$hookName; code='module_load_failed'; detail=$_.Exception.Message } | ConvertTo-Json -Compress) | Add-Content -LiteralPath $fallback -Encoding UTF8
    } catch {}
    exit 0
}

# ── #18 fail-close 严重等级用 hashtable 而不是正则 ──────────
# 维护代价低，新增一个直接加 key；行为可读
$Script:FailCloseCodes = @{
    'state_expired'                                = $true
    'drill_state_expired'                          = $true
    'lock_expired'                                 = $true
    'missing_expires_at'                           = $true
    'missing_lock_expires_at'                      = $true
    'invalid_expires_at'                           = $true
    'invalid_lock_expires_at'                      = $true
    'state_lock_session_mismatch'                  = $true
    'm1_started_without_completed'                 = $true
    'm1_phase_without_routing_log'                 = $true
    'missing_todowrite_ref_for_high_risk'          = $true
    'missing_tdd_ref_for_high_risk'                = $true
    'missing_test_ref_for_high_risk'               = $true
    'test_skipped_for_high_risk'                   = $true
    'tdd_skipped_for_high_risk'                    = $true
    'missing_unit_or_integration_test_ref_for_high_risk' = $true
    'typecheck_only_for_high_risk'                 = $true
    'missing_l4_batch_protocol'                    = $true
    'missing_l4_downgrade_reason'                  = $true
    'missing_l4_parent_plan_ref'                   = $true
}

function Get-Severity {
    param([string]$Issue)
    # 兼容 "code:group" 格式（M1 compliance issues 带 group 后缀）
    $bare = $Issue
    $idx = $Issue.IndexOf(':')
    if ($idx -gt 0) { $bare = $Issue.Substring(0, $idx) }
    if ($Script:FailCloseCodes.ContainsKey($bare)) { return 'fail-close' }
    return 'warn'
}

function Add-Issue {
    param([System.Collections.Generic.List[string]]$Issues, [string]$Code)
    if (-not $Issues.Contains($Code)) { [void]$Issues.Add($Code) }
}

function Write-AuditLine {
    param(
        [string]$Path,
        [hashtable]$Data
    )
    $dir = Split-Path -Parent $Path
    if (-not (Test-Path -LiteralPath $dir)) { New-Item -ItemType Directory -Force -Path $dir | Out-Null }
    $line = $Data | ConvertTo-Json -Depth 20 -Compress
    $errors = @()
    for ($attempt = 1; $attempt -le 3; $attempt++) {
        try {
            $line | Add-Content -LiteralPath $Path -Encoding UTF8 -ErrorAction Stop
            return @{ ok = $true; path = $Path; attempts = $attempt; fallback = $false; errors = @($errors) }
        } catch {
            $errors += "attempt_${attempt}:$($_.Exception.Message)"
            Start-Sleep -Milliseconds (120 * $attempt)
        }
    }
    # 主 path 写失败 → 退到 fallback log
    $fallbackData = [ordered]@{
        time = (Get-Date).ToString('o')
        original_path = $Path
        write_errors = @($errors)
        record = $Data
    }
    $fallbackJson = $fallbackData | ConvertTo-Json -Depth 24 -Compress
    $fallbackCandidates = @(
        (Join-Path $env:USERPROFILE '.claude\logs\forge-drift-audit-fallback.jsonl'),
        (Join-Path $env:TEMP 'forge-drift-audit-fallback.jsonl')
    )
    foreach ($fallback in $fallbackCandidates) {
        try {
            $fallbackDir = Split-Path -Parent $fallback
            if (-not (Test-Path -LiteralPath $fallbackDir)) { New-Item -ItemType Directory -Force -Path $fallbackDir | Out-Null }
            $fallbackJson | Add-Content -LiteralPath $fallback -Encoding UTF8 -ErrorAction Stop
            return @{ ok = $false; path = $Path; attempts = 3; fallback = $true; fallback_path = $fallback; errors = @($errors) }
        } catch {
            $errors += "fallback:${fallback}:$($_.Exception.Message)"
        }
    }
    return @{ ok = $false; path = $Path; attempts = 3; fallback = $false; errors = @($errors) }
}

# ── 主流程 ──────────────────────────────────────────────────

try {
    # #6 UTF-8 stdin
    $raw = Read-StdinUtf8
    $payload = ConvertFrom-StdinPayload -Raw $raw

    # #4/#5 RepoRoot：-RepoPath > payload.cwd > pwd
    $repoRoot = Resolve-RepoRoot -Path $RepoPath -Payload $payload

    $claudeDir = Join-Path $repoRoot '.claude'
    $driftPath = Join-Path $claudeDir 'forge-drift-audit.jsonl'
    $statePath = Join-Path $claudeDir 'forge-session-state.json'
    $routingPath = Join-Path $claudeDir 'forge-routing.jsonl'
    $issues = [System.Collections.Generic.List[string]]::new()

    # ── #5 全局脚本路径（不再硬编码用户名） ────────────────
    $gateScript = Get-ClaudeScriptPath -Name 'Test-ForgeGuidedFullGate.ps1'
    $m1Script = Get-ClaudeScriptPath -Name 'Test-ForgeM1Compliance.ps1'

    # ── 1. guided-full gate（state 存在时调用） ─────────────
    if (Test-Path -LiteralPath $statePath) {
        if (Test-Path -LiteralPath $gateScript) {
            $candidate = '[PIPELINE] 阶段状态检查'
            try {
                # #2 subprocess 调用：保留隔离（脚本会 exit），但路径来自 Get-ClaudeScriptPath
                $jsonText = & pwsh.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File $gateScript `
                    -RepoPath $repoRoot -CandidateText $candidate -Json 2>$null
                if ($LASTEXITCODE -ne 0) {
                    try {
                        $gate = $jsonText | ConvertFrom-Json -AsHashtable
                        foreach ($issue in @($gate.issues)) { Add-Issue $issues ([string]$issue) }
                    } catch {
                        Add-Issue $issues 'guided_full_gate_failed'
                        Write-VerboseTrace -Hook $hookName -Message 'gate-parse-failed' -Extra @{ raw=$jsonText }
                    }
                }
            } catch {
                # 异常不静默：写 fallback log，主流程继续
                Write-FallbackLog -Code 'gate_subprocess_failed' -Detail $_.Exception.Message -Repo $repoRoot
                Add-Issue $issues 'guided_full_gate_failed'
            }
        } else {
            # 全局脚本缺失 → warn 级别，不阻断
            Write-VerboseTrace -Hook $hookName -Message 'gate-script-missing' -Extra @{ path=$gateScript }
        }
    }

    # ── 2. Stop 事件追加 M1/L4 routing 检查（#19 单遍循环） ─
    if ($Event -eq 'Stop') {
        $items = @(Read-M1RoutingItems -Path $routingPath)
        $m1Started = @{}
        $m1Completed = @{}

        # 单次循环聚合 m1Started/m1Completed/L4 batch_protocol 检查
        foreach ($item in $items) {
            $group = [string]$item.task_group
            if ([string]::IsNullOrWhiteSpace($group)) { continue }

            $status = [string]$item.group_status
            if ($status -eq 'started') { $m1Started[$group] = $true }
            elseif ($status -eq 'completed') { $m1Completed[$group] = $true }

            # L4 batch_protocol 检查内联到同一遍
            $projectLevel = [string]$item.project_level
            if ([string]::IsNullOrWhiteSpace($projectLevel)) { $projectLevel = [string]$item.level }
            if ($projectLevel -eq 'L4') {
                $batchProtocol = [string]$item.batch_protocol
                if ([string]::IsNullOrWhiteSpace($batchProtocol)) {
                    Add-Issue $issues "missing_l4_batch_protocol:$group"
                } elseif ($batchProtocol -notin @('full','full-auto','ship')) {
                    if ([string]::IsNullOrWhiteSpace([string]$item.downgrade_reason)) {
                        Add-Issue $issues "missing_l4_downgrade_reason:$group"
                    }
                    if ([string]::IsNullOrWhiteSpace([string]$item.parent_plan_ref)) {
                        Add-Issue $issues "missing_l4_parent_plan_ref:$group"
                    }
                }
            }
        }

        # started 但未 completed
        foreach ($group in $m1Started.Keys) {
            if (-not $m1Completed.ContainsKey($group)) {
                Add-Issue $issues "m1_started_without_completed:$group"
            }
        }

        # M1 compliance 子进程（每个 completed group 一次）
        if (Test-Path -LiteralPath $m1Script) {
            foreach ($group in $m1Completed.Keys) {
                try {
                    $m1Json = & pwsh.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File $m1Script `
                        -RepoPath $repoRoot -TaskGroup $group -Json 2>$null
                    if ($LASTEXITCODE -ne 0) {
                        try {
                            $m1 = $m1Json | ConvertFrom-Json -AsHashtable
                            foreach ($issue in @($m1.issues)) {
                                $code = ([string]$issue) -replace "^$([regex]::Escape($group)):", ''
                                Add-Issue $issues "$code`:$group"
                            }
                        } catch {
                            Add-Issue $issues "m1_compliance_failed:$group"
                        }
                    }
                } catch {
                    Write-FallbackLog -Code 'm1_subprocess_failed' -Detail $_.Exception.Message -Repo $repoRoot
                    Add-Issue $issues "m1_compliance_failed:$group"
                }
            }
        } else {
            Write-VerboseTrace -Hook $hookName -Message 'm1-script-missing' -Extra @{ path=$m1Script }
        }

        # M1 phase 但缺 routing 日志
        $state = Read-SessionState -RepoRoot $repoRoot
        if ($state -and (Test-StateSchemaSupported -State $state)) {
            $phase = Get-StateValue -State $state -Name 'phase'
            if ($phase -match '^M1' -and -not (Test-Path -LiteralPath $routingPath)) {
                Add-Issue $issues 'm1_phase_without_routing_log'
            }
        }
    }

    # ── 3. 计算 effective_severity + 落 audit 行 ───────────
    $issueRecords = @()
    $effectiveSeverity = 'warn'
    foreach ($issue in @($issues)) {
        $severity = Get-Severity -Issue $issue
        if ($severity -eq 'fail-close') { $effectiveSeverity = 'fail-close' }
        $issueRecords += [ordered]@{ code = $issue; severity = $severity }
    }

    $auditRecord = @{
        time = (Get-Date).ToString('o')
        repo = $repoRoot
        event = $Event
        mode = $Mode
        effective_severity = $effectiveSeverity
        issues = @($issues)
        issue_records = @($issueRecords)
        state = if (Test-Path -LiteralPath $statePath) { '.claude/forge-session-state.json' } else { '' }
        routing = if (Test-Path -LiteralPath $routingPath) { '.claude/forge-routing.jsonl' } else { '' }
    }

    if ($DryRun) {
        Write-VerboseTrace -Hook $hookName -Message 'dry-run' -Extra @{ issues=$issues; severity=$effectiveSeverity }
        Write-HookMetrics -Hook $hookName -Event $Event -Tool '' -Verdict 'dry-run' -DurationMs ((Get-Date) - $hookStart).TotalMilliseconds -Extra @{ issue_count=$issues.Count; severity=$effectiveSeverity }
        exit 0
    }

    $writeResult = Write-AuditLine -Path $driftPath -Data $auditRecord
    if (-not $writeResult.ok) {
        $writeMsg = 'Forge hook audit log write failed; fallback=' + [string]$writeResult.fallback + '; path=' + [string]$writeResult.path + '; fallback_path=' + [string]$writeResult.fallback_path
        [Console]::Error.WriteLine($writeMsg)
        Write-FallbackLog -Code 'audit_write_failed' -Detail $writeMsg -Repo $repoRoot
    }

    # ── 4. 输出 + exit ─────────────────────────────────────
    if ($issues.Count -gt 0) {
        $first = ($issues | Select-Object -First 6) -join ', '
        $msgCn = "Forge 会话审计：检出 $($issues.Count) 项异常 → $first"
        $msgEn = "Forge session audit: $($issues.Count) issues detected → $first"
        $msg = "$msgCn`n$msgEn"
        [Console]::Error.WriteLine($msg)

        # Stop hook 不支持 hookSpecificOutput.additionalContext，用 systemMessage
        if ($Event -eq 'Stop') {
            @{ systemMessage = $msg } | ConvertTo-Json -Compress -Depth 10
        } else {
            @{
                hookSpecificOutput = @{
                    hookEventName = $Event
                    additionalContext = $msg
                }
            } | ConvertTo-Json -Compress -Depth 10
        }

        Write-HookMetrics -Hook $hookName -Event $Event -Tool '' -Verdict $effectiveSeverity -DurationMs ((Get-Date) - $hookStart).TotalMilliseconds -Extra @{ issue_count=$issues.Count; severity=$effectiveSeverity }

        if ($Mode -eq 'fail-close' -and $effectiveSeverity -eq 'fail-close') { exit 2 }
        exit 0
    }

    Write-HookMetrics -Hook $hookName -Event $Event -Tool '' -Verdict 'pass' -DurationMs ((Get-Date) - $hookStart).TotalMilliseconds
    exit 0

} catch {
    # #8 任何异常都 fail-open + fallback；记 audit 异常占位行
    $repoRootSafe = $repoRoot
    if ([string]::IsNullOrWhiteSpace($repoRootSafe)) { $repoRootSafe = Resolve-RepoRoot -Path $RepoPath -Payload @{} }
    Write-FallbackLog -Code 'session_audit_exception' -Detail $_.Exception.Message -Repo $repoRootSafe
    try {
        $fallbackDrift = Join-Path $repoRootSafe '.claude\forge-drift-audit.jsonl'
        [void](Write-AuditLine -Path $fallbackDrift -Data @{
            time = (Get-Date).ToString('o')
            repo = $repoRootSafe
            event = $Event
            mode = $Mode
            effective_severity = 'warn'
            issues = @('hook_exception')
            error = $_.Exception.Message
        })
    } catch {}
    [Console]::Error.WriteLine("Forge session-audit fail-open: $($_.Exception.Message)")
    Write-HookMetrics -Hook $hookName -Event $Event -Tool '' -Verdict 'exception' -DurationMs ((Get-Date) - $hookStart).TotalMilliseconds -Extra @{ error=$_.Exception.Message }
    exit 0
}
