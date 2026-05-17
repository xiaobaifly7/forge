#requires -Version 7.0
[CmdletBinding()]
param(
    [string]$RepoPath = '',
    [switch]$DryRun
)

$ErrorActionPreference = 'Stop'
$hookStart = Get-Date
$hookName = 'forge-pretool-guard'
$script:tool = ''
$script:targetPath = ''

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

# ── 业务专用辅助函数 ────────────────────────────────────────

function Test-M1WriteReady {
    param([object[]]$Events)
    $started = @($Events | Where-Object { [string]$_.group_status -eq 'started' })
    return ($started.Count -gt 0)
}

function Test-L4InheritanceReady {
    param([hashtable]$State, [object[]]$Events)
    $parentLevel = Get-StateValue -State $State -Name 'parent_level'
    if ($parentLevel -ne 'L4') { return $true }
    $stateInheritedFrom = Get-StateValue -State $State -Name 'inherited_from'
    $stateScope = Get-StateValue -State $State -Name 'execution_scope'
    if ([string]::IsNullOrWhiteSpace($stateInheritedFrom) -or [string]::IsNullOrWhiteSpace($stateScope)) { return $false }
    $started = @($Events | Where-Object { [string]$_.group_status -eq 'started' })
    if ($started.Count -lt 1) { return $false }
    foreach ($event in $started) {
        $level = if (-not [string]::IsNullOrWhiteSpace([string]$event.project_level)) { [string]$event.project_level } else { [string]$event.level }
        if ($level -ne 'L4') { return $false }
        if ([string]$event.parent_level -and [string]$event.parent_level -ne 'L4') { return $false }
        if ([string]::IsNullOrWhiteSpace([string]$event.inherited_from)) { return $false }
        if ([string]::IsNullOrWhiteSpace([string]$event.execution_scope)) { return $false }
    }
    return $true
}

function Test-HighRiskEvidencePlanned {
    param([object[]]$Events)
    $started = @($Events | Where-Object { [string]$_.group_status -eq 'started' })
    foreach ($event in $started) {
        $projectLevel = [string]$event.project_level
        if ([string]::IsNullOrWhiteSpace($projectLevel)) { $projectLevel = [string]$event.level }
        $highRisk = [string]$event.high_risk
        $reasonText = (@($event.reason) -join ' ')
        $riskText = (($highRisk, $reasonText, [string]$event.risk, [string]$event.write_scope) -join ' ')
        $isHighRisk = $projectLevel -eq 'L4' -or $riskText -match 'high|auth|security|release|shared|contract|migration|schema|persistence|高风险|安全|发布|共享|契约|数据库|持久化'
        if (-not $isHighRisk) { continue }
        $todoRef = [string]$event.todo_ref
        $tddRef = [string]$event.tdd_ref
        $testRef = [string]$event.test_ref
        if ($todoRef -match '^TodoWrite:' -and -not [string]::IsNullOrWhiteSpace($tddRef) -and $tddRef -notmatch '^skip:' -and -not [string]::IsNullOrWhiteSpace($testRef) -and $testRef -notmatch '^skip:' -and $testRef -match '(^|[;,: ])(unit|integration)([:; ,]|$)') {
            return $true
        }
        return $false
    }
    return $true
}

function Resolve-BmadRoot {
    param([string]$RepoRoot, [string]$BmadRoot)
    if ([string]::IsNullOrWhiteSpace($BmadRoot)) { return '' }
    if ([System.IO.Path]::IsPathFullyQualified($BmadRoot)) { return [System.IO.Path]::GetFullPath($BmadRoot) }
    return [System.IO.Path]::GetFullPath((Join-Path $RepoRoot $BmadRoot))
}

function Test-BmadArtifactReady {
    param([string]$RepoRoot, [string]$BmadRoot, [string]$Phase)
    $root = Resolve-BmadRoot -RepoRoot $RepoRoot -BmadRoot $BmadRoot
    if ([string]::IsNullOrWhiteSpace($root)) { return $false }
    $requirements = Join-Path $root 'requirements.md'
    $architecture = Join-Path $root 'architecture.md'
    $stories = Join-Path $root 'stories'
    $acceptance = Join-Path $root 'acceptance.md'
    if ($Phase -eq '1A' -or $Phase -eq 'requirements') { return (Test-Path -LiteralPath $requirements) }
    if ($Phase -eq '1B' -or $Phase -eq 'architecture') { return ((Test-Path -LiteralPath $requirements) -and (Test-Path -LiteralPath $architecture)) }
    if ($Phase -match '^M1' -or $Phase -eq 'stories' -or $Phase -eq 'acceptance') {
        $hasStories = (Test-Path -LiteralPath $stories) -and @((Get-ChildItem -LiteralPath $stories -Filter '*.md' -File -ErrorAction SilentlyContinue)).Count -gt 0
        return ((Test-Path -LiteralPath $requirements) -and (Test-Path -LiteralPath $architecture) -and $hasStories -and (Test-Path -LiteralPath $acceptance))
    }
    return (Test-Path -LiteralPath $requirements)
}

function Write-Block {
    # PreToolUse 支持 hookSpecificOutput.additionalContext + permissionDecision，
    # 让拦截原因能进入 Claude 上下文（旧版本回退到 stderr）。
    param([string]$Cn, [string]$En, [string]$Code)
    $msg = "$Cn`n$En"
    [Console]::Error.WriteLine($msg)
    @{
        hookSpecificOutput = @{
            hookEventName = 'PreToolUse'
            additionalContext = $msg
            permissionDecision = 'deny'
            permissionDecisionReason = $Code
        }
    } | ConvertTo-Json -Compress -Depth 10
    if ($DryRun) {
        Write-VerboseTrace -Hook $hookName -Message 'dry-run-block' -Extra @{ code=$Code }
        Write-HookMetrics -Hook $hookName -Event 'PreToolUse' -Tool $script:tool -Verdict 'dry-run-block' -DurationMs ((Get-Date) - $hookStart).TotalMilliseconds -Extra @{ block_code=$Code; target=$script:targetPath }
        exit 0
    }
    Write-HookMetrics -Hook $hookName -Event 'PreToolUse' -Tool $script:tool -Verdict 'block' -DurationMs ((Get-Date) - $hookStart).TotalMilliseconds -Extra @{ block_code=$Code; target=$script:targetPath }
    exit 2
}

# ── 主流程 ──────────────────────────────────────────────────

try {
    # #6 UTF-8 stdin
    $raw = Read-StdinUtf8
    $payload = ConvertFrom-StdinPayload -Raw $raw

    # #4/#5 RepoRoot：-RepoPath > payload.cwd > pwd
    $repoRoot = Resolve-RepoRoot -Path $RepoPath -Payload $payload

    # #1 P0 短路：state 不在直接放行
    $statePath = Join-Path $repoRoot '.claude\forge-session-state.json'
    if (-not (Test-Path -LiteralPath $statePath)) {
        Write-VerboseTrace -Hook $hookName -Message 'no-state-short-circuit' -Extra @{ repo=$repoRoot }
        Write-HookMetrics -Hook $hookName -Event 'PreToolUse' -Tool '' -Verdict 'no-state' -DurationMs ((Get-Date) - $hookStart).TotalMilliseconds
        exit 0
    }

    $script:tool = Get-ToolName -Payload $payload
    $toolInput = Get-ToolInput -Payload $payload
    $script:targetPath = Get-TargetPath -ToolInput $toolInput

    # #7 Bash 写文件兜底
    if ($script:tool -eq 'Bash') {
        $bashCmd = Get-BashCommand -ToolInput $toolInput
        if (-not (Test-BashWritesFile -Command $bashCmd)) {
            Write-VerboseTrace -Hook $hookName -Message 'bash-readonly-skip'
            Write-HookMetrics -Hook $hookName -Event 'PreToolUse' -Tool 'Bash' -Verdict 'bash-readonly' -DurationMs ((Get-Date) - $hookStart).TotalMilliseconds
            exit 0
        }
    } elseif ($script:tool -notin @('Write','Edit','MultiEdit','NotebookEdit')) {
        Write-VerboseTrace -Hook $hookName -Message 'tool-skip' -Extra @{ tool=$script:tool }
        Write-HookMetrics -Hook $hookName -Event 'PreToolUse' -Tool $script:tool -Verdict 'tool-skip' -DurationMs ((Get-Date) - $hookStart).TotalMilliseconds
        exit 0
    }

    # #17 Schema 校验
    $state = Read-SessionState -RepoRoot $repoRoot
    if (-not $state) {
        Write-HookMetrics -Hook $hookName -Event 'PreToolUse' -Tool $script:tool -Verdict 'state-unreadable' -DurationMs ((Get-Date) - $hookStart).TotalMilliseconds
        exit 0
    }
    if (-not (Test-StateSchemaSupported -State $state)) {
        Write-FallbackLog -Code 'unsupported_schema_version' -Detail "version=$([string]$state.schema_version)" -Repo $repoRoot
        Write-HookMetrics -Hook $hookName -Event 'PreToolUse' -Tool $script:tool -Verdict 'schema-unsupported' -DurationMs ((Get-Date) - $hookStart).TotalMilliseconds
        exit 0
    }

    $execution = Get-StateValue -State $state -Name 'execution'
    $phase = Get-StateValue -State $state -Name 'phase'
    $questionPending = if ($state.ContainsKey('question_pending')) { [bool]$state['question_pending'] } else { $false }
    $userConfirmedNextPhase = if ($state.ContainsKey('user_confirmed_next_phase')) { [bool]$state['user_confirmed_next_phase'] } else { $false }
    $parentLevel = Get-StateValue -State $state -Name 'parent_level'
    $bmadRoot = Get-StateValue -State $state -Name 'bmad_root'

    if ($execution -ne 'guided-full') {
        Write-VerboseTrace -Hook $hookName -Message 'execution-skip' -Extra @{ execution=$execution }
        Write-HookMetrics -Hook $hookName -Event 'PreToolUse' -Tool $script:tool -Verdict 'execution-skip' -DurationMs ((Get-Date) - $hookStart).TotalMilliseconds
        exit 0
    }

    # 写入 forge state 自身一律放行（Bash 因 path 不可解析跳过此放行，由后续 1A 门禁处理）
    if ($script:tool -ne 'Bash' -and (Test-IsRepoForgeStatePath -RepoRoot $repoRoot -TargetPath $script:targetPath)) {
        Write-VerboseTrace -Hook $hookName -Message 'forge-state-write' -Extra @{ target=$script:targetPath }
        Write-HookMetrics -Hook $hookName -Event 'PreToolUse' -Tool $script:tool -Verdict 'forge-state-write' -DurationMs ((Get-Date) - $hookStart).TotalMilliseconds
        exit 0
    }

    # 门禁 1: 1A question_pending
    if ($phase -eq '1A' -and $questionPending -and -not $userConfirmedNextPhase) {
        Write-Block -Code '1A_question_pending' `
            -Cn "Forge guided-full 门禁：当前处于 1A 阶段且有未回答的单问，禁止写入普通项目文件。请先回答 1A 单问，或仅写 .claude/forge-* state。target=$script:targetPath" `
            -En "Forge guided-full guard: in phase 1A with question_pending=true; only writes to .claude/forge-* state are allowed until the question is answered. target=$script:targetPath"
    }

    # Bash 已通过 1A 门禁后放行（更精细的 path 检查交给 PostToolUse 审计）
    if ($script:tool -eq 'Bash') {
        Write-HookMetrics -Hook $hookName -Event 'PreToolUse' -Tool 'Bash' -Verdict 'bash-passed-1a' -DurationMs ((Get-Date) - $hookStart).TotalMilliseconds
        exit 0
    }

    if (-not (Test-IsProjectWritePath -RepoRoot $repoRoot -TargetPath $script:targetPath)) {
        Write-HookMetrics -Hook $hookName -Event 'PreToolUse' -Tool $script:tool -Verdict 'non-project-write' -DurationMs ((Get-Date) - $hookStart).TotalMilliseconds
        exit 0
    }

    # 门禁 2: L4/M1 BMAD artifact
    if ($parentLevel -eq 'L4') {
        if (-not (Test-BmadArtifactReady -RepoRoot $repoRoot -BmadRoot $bmadRoot -Phase $phase)) {
            Write-Block -Code 'bmad_artifact_missing' `
                -Cn "Forge guided-full 门禁：当前 L4/BMAD 流程缺少阶段 $phase 所需的 BMAD artifact。请先在 $bmadRoot 下补齐 requirements/architecture/stories/acceptance。target=$script:targetPath" `
                -En "Forge guided-full guard: L4/BMAD flow missing required artifacts for phase $phase. Populate requirements/architecture/stories/acceptance under $bmadRoot first. target=$script:targetPath"
        }
    }

    # 门禁 3: M1 routing 已 started + L4 继承 + 高风险证据
    if ($phase -match '^M1') {
        $routingPath = Join-Path $repoRoot '.claude\forge-routing.jsonl'
        $events = Read-M1RoutingItems -Path $routingPath -TailLimit 100  # #3 流式读 + 限制 tail

        if (-not (Test-L4InheritanceReady -State $state -Events $events)) {
            Write-Block -Code 'l4_inheritance_incomplete' `
                -Cn "Forge guided-full 门禁：当前 M1 继承 L4，但缺少 inherited_from / execution_scope，或 routing 中 level 发生降级。请保持 level=L4 并使用 execution_scope=light|normal|heavy。target=$script:targetPath" `
                -En "Forge guided-full guard: M1 inherits L4 but inherited_from/execution_scope are missing or routing level downgraded. Keep level=L4 and set execution_scope=light|normal|heavy. target=$script:targetPath"
        }
        if (-not (Test-M1WriteReady -Events $events)) {
            Write-Block -Code 'm1_no_started_routing' `
                -Cn "Forge guided-full 门禁：当前处于 M1 但 .claude/forge-routing.jsonl 缺少 group_status=started 事件，禁止写普通项目文件。请先写入 routing started 事件。target=$script:targetPath" `
                -En "Forge guided-full guard: in phase M1 but no group_status=started event found in .claude/forge-routing.jsonl. Append a started event before writing project files. target=$script:targetPath"
        }
        if (-not (Test-HighRiskEvidencePlanned -Events $events)) {
            Write-Block -Code 'high_risk_evidence_missing' `
                -Cn "Forge guided-full 门禁：当前 M1 命中高风险/L4，但 routing 缺少 TodoWrite / TDD / unit-or-integration TestRef 三件套证据。请补齐计划证据后再写普通项目文件。target=$script:targetPath" `
                -En "Forge guided-full guard: M1 hits high-risk/L4 but routing lacks TodoWrite/TDD/unit-or-integration TestRef evidence. Plan all three before writing project files. target=$script:targetPath"
        }
    }

    Write-VerboseTrace -Hook $hookName -Message 'pass' -Extra @{ phase=$phase; parent_level=$parentLevel; target=$script:targetPath }
    Write-HookMetrics -Hook $hookName -Event 'PreToolUse' -Tool $script:tool -Verdict 'pass' -DurationMs ((Get-Date) - $hookStart).TotalMilliseconds
    exit 0
} catch {
    # #8 任何异常都 fail-open + fallback log，绝不静默
    Write-FallbackLog -Code 'pretool_guard_exception' -Detail $_.Exception.Message -Repo $repoRoot
    [Console]::Error.WriteLine("Forge pretool-guard fail-open: $($_.Exception.Message)")
    Write-HookMetrics -Hook $hookName -Event 'PreToolUse' -Tool $script:tool -Verdict 'exception' -DurationMs ((Get-Date) - $hookStart).TotalMilliseconds -Extra @{ error=$_.Exception.Message }
    exit 0
}
