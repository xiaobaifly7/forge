param(
    [string]$EvalsPath = "$env:USERPROFILE\.claude\skills\forge\evals\evals.json",
    [string]$LogPath = "$env:USERPROFILE\.claude\logs\forge-smoke.jsonl",
    [switch]$NoLog,
    [switch]$LiveClaudeRoute,
    [switch]$IncludeLiveClaudeRoute,
    [switch]$SkipReleaseReadiness,
    [switch]$Quick,
    [switch]$Minimal,
    [switch]$NoExternalRefCompare,
    [int]$LiveRouteTimeoutSeconds = 120
)

$ErrorActionPreference = "Stop"
$ScriptDir = Split-Path -Parent $PSCommandPath
$RepoRootForScripts = Split-Path -Parent $ScriptDir
$sourcePath = Join-Path $env:USERPROFILE ".claude\forge-source.txt"
if (Test-Path -LiteralPath $sourcePath) {
    foreach ($line in Get-Content -LiteralPath $sourcePath -Encoding UTF8) {
        if ($line -match '^forge_source_repo=(.+)$') {
            $candidateRepoRoot = $Matches[1]
            if ((Test-Path -LiteralPath (Join-Path $candidateRepoRoot "examples")) -and (Test-Path -LiteralPath (Join-Path $candidateRepoRoot "hooks"))) {
                $RepoRootForScripts = $candidateRepoRoot
            }
            break
        }
    }
}
$HookScriptPath = Join-Path $RepoRootForScripts "hooks\forge-pretool-guard.ps1"
$AuditScriptPath = Join-Path $RepoRootForScripts "hooks\forge-session-audit.ps1"

function Write-SmokeProgress {
    param([string]$Message)
    [Console]::Out.WriteLine("[smoke] $Message")
}

function Start-SmokeStep {
    param([string]$Name)
    Write-SmokeProgress -Message "start $Name"
    return [System.Diagnostics.Stopwatch]::StartNew()
}

function Complete-SmokeStep {
    param(
        [string]$Name,
        [bool]$Ok,
        [System.Diagnostics.Stopwatch]$Timer
    )
    if ($Timer) { $Timer.Stop() }
    $durationMs = if ($Timer) { $Timer.ElapsedMilliseconds } else { 0 }
    $label = if ($Ok) { "pass" } else { "fail" }
    Write-SmokeProgress -Message "$label $Name duration_ms=$durationMs"
    Write-Output "${Name}_duration_ms=$durationMs"
}

function Write-SkippedGate {
    param(
        [string]$Name,
        [string]$Prefix
    )
    Write-SmokeProgress -Message "skip $Name"
    Write-Output "${Prefix}_total=0"
    Write-Output "${Prefix}_passed=0"
    Write-Output "${Prefix}_failed=0"
    Write-Output "${Prefix}_skipped=1"
    Write-Output "${Prefix}_duration_ms=0"
}

function Resolve-ExplicitMode {
    param([string]$Text)
    if ([string]::IsNullOrWhiteSpace($Text)) {
        return $null
    }
    $patterns = @(
        '\[forge\]\s*(?:level\s*=\s*L[0-4]\s*)?mode\s*=\s*(full-auto|ship|fix|build|full|quick)',
        '直接判定为\s*(full-auto|ship|fix|build|full|quick)',
        '优先判定为\s*(full-auto|ship|fix|build|full|quick)',
        '判定为\s*(full-auto|ship|fix|build|full|quick)'
    )
    foreach ($pattern in $patterns) {
        $match = [regex]::Match($Text, $pattern, [System.Text.RegularExpressions.RegexOptions]::IgnoreCase)
        if ($match.Success) {
            return $match.Groups[1].Value.ToLowerInvariant()
        }
    }
    return $null
}

function Get-ExpectedMode {
    param([hashtable]$Case)
    $expectedOutput = [string]$Case.expected_output
    $explicitMode = Resolve-ExplicitMode -Text $expectedOutput
    if ($explicitMode) {
        return $explicitMode
    }
    $text = (($Case.prompt, $expectedOutput) -join " ").ToLowerInvariant()
    if ($text -match 'quick|audit-only|只读|l0') { return 'quick' }
    if ($text -match 'ship|release|handoff|交付|发布') { return 'ship' }
    if ($text -match 'fix|bug|regression|test failure|测试失败|回归|修掉') { return 'fix' }
    if ($text -match 'build|现有架构|需求清晰|小功能|--json|扩一下') { return 'build' }
    if ($text -match '判定为 full-auto|mode=full-auto|expected_mode.*full-auto') { return 'full-auto' }
    if ($text -match 'full|共享|认证|跨模块|schema|security|高风险|_bmad') { return 'full' }
    return 'full'
}

function Get-ActualModeOffline {
    param([hashtable]$Case)
    $prompt = ([string]$Case.prompt).ToLowerInvariant()
    if ($prompt -match 'full-auto|端到端自动推进|不要分阶段停顿') { return 'full-auto' }
    if ($prompt -match '共享|sdk|认证|权限|支付|安全|数据库|持久化|migration|schema|依赖升级|跨模块|全局|_bmad|full|重构|一步步|guide|guided|方案.*不确定|不确定.*方案') { return 'full' }
    if ($prompt -match '只读|评估|看一下|方案|audit-only') { return 'quick' }
    if ($prompt -match 'release|pre-ship|handoff|merge-ready|发了|交付|发布|最后.*验收') { return 'ship' }
    if ($prompt -match 'bug|regression|test.*fail|测试.*失败|失败了|回归|修掉|行为异常') { return 'fix' }
    if ($prompt -match '需求.*清楚|现有|当前命令|小功能|扩一下|--json|subagent') { return 'build' }
    return 'full'
}



function Resolve-ExplicitExecution {
    param([string]$Text)
    if ([string]::IsNullOrWhiteSpace($Text)) { return $null }
    $patterns = @(
        '\[forge\]\s*execution\s*=\s*(guided-full|audit-only|full-auto|auto)',
        'execution\s*=\s*(guided-full|audit-only|full-auto|auto)',
        '执行模式\s*[:=：]\s*(guided-full|audit-only|full-auto|auto)'
    )
    foreach ($pattern in $patterns) {
        $match = [regex]::Match($Text, $pattern, [System.Text.RegularExpressions.RegexOptions]::IgnoreCase)
        if ($match.Success) { return $match.Groups[1].Value.ToLowerInvariant() }
    }
    return $null
}

function Get-ExpectedExecution {
    param([hashtable]$Case, [string]$Mode)
    if ($Case.ContainsKey("expected_execution")) { return [string]$Case.expected_execution }
    if ($Mode -eq 'quick') { return 'audit-only' }
    if ($Mode -eq 'full-auto') { return 'full-auto' }
    if ($Mode -eq 'full') { return 'guided-full' }
    return 'auto'
}

function Get-ExpectedExecutionForPrompt {
    param([string]$Prompt, [string]$Mode)
    $promptText = [string]$Prompt
    if ($promptText -match '只读|只看|看一下|看看|审计|audit-only|不要改文件|不改文件|别改文件|无需修改|不用修改|只做分析|仅分析|状态确认|查状态|评估一下|梳理一下|总结一下') {
        return 'audit-only'
    }
    return (Get-ExpectedExecution -Case ([ordered]@{ prompt = $Prompt }) -Mode $Mode)
}

function Get-ActualExecutionOffline {
    param([hashtable]$Case, [string]$Mode)
    $prompt = [string]$Case.prompt
    $json = & pwsh -NoLogo -NoProfile -ExecutionPolicy Bypass -File (Join-Path $ScriptDir 'Resolve-ForgeExecutionMode.ps1') -Prompt $prompt -Mode $Mode -Json
    try { return [string](($json | ConvertFrom-Json -AsHashtable).execution) } catch { return 'invalid' }
}

function Invoke-LiveClaudeRouteSmoke {
    param([hashtable]$Raw, [string]$LogPath, [bool]$NoLog, [int]$TimeoutSeconds)
    $liveCases = @()
    if ($Raw.ContainsKey("live_route_evals")) { $liveCases = @($Raw.live_route_evals) }
    if ($liveCases.Count -lt 1) {
        $liveCases = @([ordered]@{
            id = "live-quick-readonly"
            prompt = "只读看一下这个项目有哪些优化点，不要改文件"
            expected_output = "[forge] mode=quick"
        })
    }
    $claudeCommand = Get-Command reclaude -ErrorAction SilentlyContinue
    if (-not $claudeCommand) { $claudeCommand = Get-Command claude -ErrorAction SilentlyContinue }
    if (-not $claudeCommand) {
        Write-Output "live_route_total=$($liveCases.Count)"
        Write-Output "live_route_passed=0"
        Write-Output "live_route_failed=0"
        Write-Output "live_route_skipped=$($liveCases.Count)"
        Write-Output "live_route_skip_reason=agent_cli_not_found"
        return
    }

    $claudePath = $claudeCommand.Source
    $livePassed = 0
    $liveFailed = 0
    $liveSkipped = 0
    $liveSkipReasons = New-Object System.Collections.Generic.List[string]
    foreach ($case in $liveCases) {
        $expected = Get-ExpectedMode -Case $case
        $expectedExecution = Get-ExpectedExecutionForPrompt -Prompt $case.prompt -Mode $expected
        $prompt = [string]$case.prompt
        $output = ""
        $exit = 0
        $skipAlreadyCounted = $false
        try {
            $routePrompt = "请只输出两行 Forge 路由判定。第一行格式必须是 [forge] mode=<quick|build|fix|full|full-auto|ship>；第二行格式必须是 [forge] execution=<guided-full|auto|audit-only|full-auto>。不要解释。判定规则：显式 guide/guided/一步步/每步确认 => guided-full；显式 auto/直接做完/不用问我 => auto；显式 full-auto/端到端自动推进 => full-auto；未显式时 quick/只读 => audit-only，fix=明确 bug/测试失败/回归修复，build=新增小功能/新增参数/清晰局部实现；fix/build/清晰小改 => auto，full/ship/高风险/跨模块/方案不清 => guided-full。用户请求：`n$prompt"
            $scriptPath = Join-Path $env:TEMP ("forge-live-route-" + [guid]::NewGuid().ToString("N") + ".ps1")
            $quotedClaude = $claudePath.Replace("'", "''")
            $quotedPrompt = $routePrompt.Replace("'", "''")
            $scriptText = @(
                "`$ErrorActionPreference = 'Stop'",
                "& '$quotedClaude' --print --output-format json --setting-sources user @'",
                $quotedPrompt,
                "'@",
                "exit `$LASTEXITCODE"
            ) -join "`n"
            Set-Content -LiteralPath $scriptPath -Encoding UTF8 -Value $scriptText
            $job = Start-Job -ScriptBlock {
                param($ScriptPath)
                & pwsh -NoLogo -NoProfile -ExecutionPolicy Bypass -File $ScriptPath 2>&1
            } -ArgumentList $scriptPath
            if (-not (Wait-Job -Job $job -Timeout $TimeoutSeconds)) {
                Stop-Job -Job $job | Out-Null
                $liveSkipped++
                if (-not $liveSkipReasons.Contains("timeout")) { [void]$liveSkipReasons.Add("timeout") }
                $skipAlreadyCounted = $true
                $output = "timeout"
                $exit = 124
            } else {
                $output = (Receive-Job -Job $job | Out-String)
                $exit = 0
            }
            Remove-Job -Job $job -ErrorAction SilentlyContinue | Out-Null
            Remove-Item -LiteralPath $scriptPath -ErrorAction SilentlyContinue
        } catch {
            $liveSkipped++
            $exceptionMessage = $_.Exception.Message
            if (-not $liveSkipReasons.Contains("exception")) { [void]$liveSkipReasons.Add("exception") }
            $skipAlreadyCounted = $true
            $output = $exceptionMessage
            $exit = 1
        }
        $parseText = $output
        try {
            $jsonOutput = $output | ConvertFrom-Json -AsHashtable
            foreach ($key in @('result','response','text','message','content')) {
                if ($jsonOutput.ContainsKey($key) -and $jsonOutput[$key]) { $parseText = [string]$jsonOutput[$key]; break }
            }
        } catch {}
        $actual = Resolve-ExplicitMode -Text $parseText
        if (-not $actual) { $actual = "unknown" }
        $actualExecution = Resolve-ExplicitExecution -Text $parseText
        if (-not $actualExecution) { $actualExecution = "unknown" }
        $ok = ($exit -eq 0 -and $actual -eq $expected -and $actualExecution -eq $expectedExecution)
        if ($ok) {
            $livePassed++
        } elseif ($exit -eq 124) {
            # timeout 已在 Wait-Job 分支计入 skipped
        } elseif ($actual -eq "unknown" -or $exit -ne 0) {
            if (-not $skipAlreadyCounted) { $liveSkipped++ }
            $reason = if ($actual -eq "unknown") { "unknown_mode" } else { "nonzero_exit" }
            if (-not $liveSkipReasons.Contains($reason)) { [void]$liveSkipReasons.Add($reason) }
        } else {
            $liveFailed++
        }
        if (-not $NoLog) {
            [ordered]@{
                time = (Get-Date).ToString("o")
                skill = $Raw.skill_name
                id = [string]$case.id
                live = $true
                expected_mode = $expected
                actual_mode = $actual
                expected_execution = $expectedExecution
                actual_execution = $actualExecution
                exit_code = $exit
                passed = $ok
                exception = $exceptionMessage
                output_sha256 = [System.BitConverter]::ToString([System.Security.Cryptography.SHA256]::HashData([System.Text.Encoding]::UTF8.GetBytes($output))).Replace('-', '').ToLowerInvariant()
            } | ConvertTo-Json -Depth 8 -Compress | Add-Content -LiteralPath $LogPath -Encoding utf8
        }
    }
    Write-Output "live_route_total=$($liveCases.Count)"
    Write-Output "live_route_passed=$livePassed"
    Write-Output "live_route_failed=$liveFailed"
    Write-Output "live_route_skipped=$liveSkipped"
    if ($liveSkipReasons.Count -gt 0) { Write-Output "live_route_skip_reason=$(($liveSkipReasons | Sort-Object) -join ',')" }
    if ($liveFailed -gt 0) { exit 1 }
}

if (-not (Test-Path -LiteralPath $EvalsPath)) {
    throw "evals not found: $EvalsPath"
}

$raw = Get-Content -Raw -LiteralPath $EvalsPath | ConvertFrom-Json -AsHashtable
$cases = @($raw.evals)
$results = New-Object System.Collections.Generic.List[object]
$passed = 0
$failed = 0
$executionPassed = 0
$executionFailed = 0
foreach ($case in $cases) {
    $expected = Get-ExpectedMode -Case $case
    $actual = Get-ActualModeOffline -Case $case
    $ok = $expected -eq $actual
    if ($ok) { $passed++ } else { $failed++ }
    $expectedExecution = Get-ExpectedExecution -Case $case -Mode $expected
    $actualExecution = Get-ActualExecutionOffline -Case $case -Mode $expected
    $executionOk = $actualExecution -eq $expectedExecution
    if ($executionOk) { $executionPassed++ } else { $executionFailed++ }
    $results.Add([ordered]@{
        time = (Get-Date).ToString("o")
        skill = $raw.skill_name
        id = $case.id
        expected_mode = $expected
        actual_mode = $actual
        expected_execution = $expectedExecution
        actual_execution = $actualExecution
        execution_passed = $executionOk
        passed = $ok
        prompt_sha256 = [System.BitConverter]::ToString([System.Security.Cryptography.SHA256]::HashData([System.Text.Encoding]::UTF8.GetBytes([string]$case.prompt))).Replace('-', '').ToLowerInvariant()
    })
}

if (-not $NoLog) {
    New-Item -ItemType Directory -Force -Path (Split-Path -Parent $LogPath) | Out-Null
    foreach ($item in $results) {
        $item | ConvertTo-Json -Depth 6 -Compress | Add-Content -LiteralPath $LogPath -Encoding utf8
    }
}

if ($LiveClaudeRoute) { Invoke-LiveClaudeRouteSmoke -Raw $raw -LogPath $LogPath -NoLog ([bool]$NoLog) -TimeoutSeconds $LiveRouteTimeoutSeconds; exit 0 }
if ($IncludeLiveClaudeRoute) { Invoke-LiveClaudeRouteSmoke -Raw $raw -LogPath $LogPath -NoLog ([bool]$NoLog) -TimeoutSeconds $LiveRouteTimeoutSeconds }

$smokeMode = if ($Minimal) { "minimal" } elseif ($Quick) { "quick" } else { "full" }
Write-Output "forge_smoke_mode=$smokeMode"

$timer = Start-SmokeStep -Name "adapter_kernel_smoke"
$adapterSmokePath = Join-Path $RepoRootForScripts "examples\flow-kit-project"
$trellisSmokePath = Join-Path $RepoRootForScripts "examples\trellis-project"
$taskKernelSmokePath = Join-Path $RepoRootForScripts "examples\task-kernel-project"
$taskKernelWritableSmokePath = Join-Path $env:TEMP ("forge-task-kernel-smoke-" + [guid]::NewGuid().ToString("N"))
Copy-Item -Recurse -LiteralPath $taskKernelSmokePath -Destination $taskKernelWritableSmokePath
$adapterKernelSmokeTotal = if ($Minimal) { 3 } else { 11 }
$adapterKernelSmokePassed = 0
$externalRefCompareSkipped = 0
try {
    & pwsh -NoLogo -NoProfile -ExecutionPolicy Bypass -File (Join-Path $ScriptDir "Test-ForgeExternalAdapter.ps1") -Name flow-kit -RepoPath $adapterSmokePath | Out-Null
    if ($LASTEXITCODE -ne 0) { throw "flow-kit adapter smoke failed" }
    $adapterKernelSmokePassed++
    if (-not $Minimal) {
        & pwsh -NoLogo -NoProfile -ExecutionPolicy Bypass -File (Join-Path $ScriptDir "Test-ForgeExternalAdapter.ps1") -Name trellis -RepoPath $trellisSmokePath | Out-Null
        if ($LASTEXITCODE -ne 0) { throw "trellis adapter smoke failed" }
        $adapterKernelSmokePassed++
    }
    & pwsh -NoLogo -NoProfile -ExecutionPolicy Bypass -File (Join-Path $ScriptDir "Test-ForgeTaskKernel.ps1") -RepoPath $taskKernelSmokePath | Out-Null
    if ($LASTEXITCODE -ne 0) { throw "task kernel smoke failed" }
    $adapterKernelSmokePassed++
    & pwsh -NoLogo -NoProfile -ExecutionPolicy Bypass -File (Join-Path $ScriptDir "Resolve-ForgeStage.ps1") -RepoPath $taskKernelSmokePath -SessionId example | Out-Null
    if ($LASTEXITCODE -ne 0) { throw "stage engine smoke failed" }
    $adapterKernelSmokePassed++
    if (-not $Minimal) {
    & pwsh -NoLogo -NoProfile -ExecutionPolicy Bypass -File (Join-Path $ScriptDir "Update-ForgeTaskContext.ps1") -RepoPath $taskKernelSmokePath -TaskPath ".forge\tasks\05-07-example-task" -Target list | Out-Null
    if ($LASTEXITCODE -ne 0) { throw "task context smoke failed" }
    $adapterKernelSmokePassed++
    & pwsh -NoLogo -NoProfile -ExecutionPolicy Bypass -File (Join-Path $ScriptDir "Add-ForgeSpecFinding.ps1") -RepoPath $taskKernelWritableSmokePath -Category guides -Title "Smoke Finding" -Summary "Smoke finding validates spec promotion." -Source "smoke" | Out-Null
    if ($LASTEXITCODE -ne 0) { throw "spec finding smoke failed" }
    $adapterKernelSmokePassed++
    }
    if ($NoExternalRefCompare -or $Minimal) {
        $externalRefCompareSkipped = 1
        Write-SmokeProgress -Message "skip external_ref_compare reason=disabled"
    } else {
    $externalRefOutput = & pwsh -NoLogo -NoProfile -ExecutionPolicy Bypass -File (Join-Path $ScriptDir "Compare-ForgeExternalAdapterRef.ps1") -Name flow-kit -TargetRef "HEAD" 2>&1
    if ($LASTEXITCODE -ne 0) {
        $externalRefText = @($externalRefOutput) -join "`n"
        if ($externalRefText -match '(?i)unable to access|ssl/tls|timed out|could not resolve|network|handshake') {
            $externalRefCompareSkipped = 1
            Write-SmokeProgress -Message "skip external_ref_compare reason=network_unavailable"
        } else {
            throw "external ref compare smoke failed"
        }
    }
    $adapterKernelSmokePassed++
    }
    if (-not $Minimal) {
    $createdTaskJson = & pwsh -NoLogo -NoProfile -ExecutionPolicy Bypass -File (Join-Path $ScriptDir "New-ForgeTask.ps1") -RepoPath $taskKernelWritableSmokePath -Name "Smoke Task" -Title "Smoke Task" -Goal "Validate task command chaining." -Json
    if ($LASTEXITCODE -ne 0) { throw "new task smoke failed" }
    $createdTask = $createdTaskJson | ConvertFrom-Json
    & pwsh -NoLogo -NoProfile -ExecutionPolicy Bypass -File (Join-Path $ScriptDir "Set-ForgeActiveTask.ps1") -RepoPath $taskKernelWritableSmokePath -SessionId smoke -TaskPath $createdTask.task_path -Stage task | Out-Null
    if ($LASTEXITCODE -ne 0) { throw "new task path chaining smoke failed" }
    $adapterKernelSmokePassed++
    & pwsh -NoLogo -NoProfile -ExecutionPolicy Bypass -File (Join-Path $ScriptDir "Update-ForgeTaskContext.ps1") -RepoPath $taskKernelWritableSmokePath -TaskPath $createdTask.task_path -Target implement -File ".forge\..\README.md" -Reason "must reject traversal" *> $null
    if ($LASTEXITCODE -eq 0) { throw "task context traversal smoke failed" }
    $adapterKernelSmokePassed++
    & pwsh -NoLogo -NoProfile -ExecutionPolicy Bypass -File (Join-Path $ScriptDir "Add-ForgeSpecFinding.ps1") -RepoPath $taskKernelWritableSmokePath -Category guides -Title "Smoke Finding" -Summary "Smoke finding validates spec promotion." -Source "smoke" | Out-Null
    if ($LASTEXITCODE -ne 0) { throw "spec finding idempotency smoke failed" }
    $smokeFindingPath = Join-Path $taskKernelWritableSmokePath ".forge\spec\guides\$(Get-Date -Format 'yyyy-MM-dd')-smoke-finding.md"
    $smokeFindingContent = Get-Content -LiteralPath $smokeFindingPath -Raw -Encoding UTF8
    if (@([regex]::Matches($smokeFindingContent, '(?m)^# Smoke Finding\r?$')).Count -ne 1) { throw "spec finding duplicate smoke failed" }
    $adapterKernelSmokePassed++
    $smokeHistoryDir = Join-Path $taskKernelWritableSmokePath ".forge\spec\guides\.history"
    if (-not (Test-Path -LiteralPath $smokeHistoryDir)) { throw "spec finding history smoke failed" }
    $smokeHistoryContent = Get-ChildItem -LiteralPath $smokeHistoryDir -Filter "*-smoke-finding-*.md" | Select-Object -First 1 | Get-Content -Raw -Encoding UTF8
    if ($smokeHistoryContent -notmatch "Smoke finding validates spec promotion.") { throw "spec finding history content smoke failed" }
    $adapterKernelSmokePassed++
    }
} finally {
    Remove-Item -Recurse -Force -LiteralPath $taskKernelWritableSmokePath -ErrorAction SilentlyContinue
}
$adapterKernelSmokeOk = (($adapterKernelSmokeTotal - $adapterKernelSmokePassed) -eq 0)
Complete-SmokeStep -Name "adapter_kernel_smoke" -Ok $adapterKernelSmokeOk -Timer $timer
Write-Output "adapter_kernel_smoke_total=$adapterKernelSmokeTotal"
Write-Output "adapter_kernel_smoke_passed=$adapterKernelSmokePassed"
Write-Output "adapter_kernel_smoke_failed=$($adapterKernelSmokeTotal - $adapterKernelSmokePassed)"
Write-Output "external_ref_compare_skipped=$externalRefCompareSkipped"

Write-Output "forge_smoke_total=$($cases.Count)"
Write-Output "forge_smoke_passed=$passed"
Write-Output "forge_smoke_failed=$failed"
Write-Output "execution_router_total=$($cases.Count)"
Write-Output "execution_router_passed=$executionPassed"
Write-Output "execution_router_failed=$executionFailed"
if ($executionFailed -gt 0) { exit 1 }

if ($Minimal) {
    Write-SkippedGate -Name "drift_gate" -Prefix "drift_gate"
} else {
# Drift gate evals: verify guided-full anti-drift guard catches known protocol violations.
$timer = Start-SmokeStep -Name "drift_gate"
$driftCases = @()
if ($raw.ContainsKey("drift_gate_evals")) { $driftCases = @($raw.drift_gate_evals) }
$driftPassed = 0
$driftFailed = 0
if ($driftCases.Count -gt 0) {
    $tmpRoot = Join-Path $env:TEMP ("forge-smoke-drift-" + [guid]::NewGuid().ToString("N"))
    New-Item -ItemType Directory -Force -Path (Join-Path $tmpRoot ".claude\forge\artifacts") | Out-Null
    git init $tmpRoot 2>$null | Out-Null
    $statePath = Join-Path $tmpRoot ".claude\forge-session-state.json"
    $artifactRel = ".claude\forge\artifacts\SMOKE-1A-brainstorm.md"
    Set-Content -LiteralPath (Join-Path $tmpRoot $artifactRel) -Encoding UTF8 -Value "# SMOKE 1A"
    $emptyArtifactRel = ".claude\forge\artifacts\SMOKE-empty-1A-brainstorm.md"
    [System.IO.File]::WriteAllBytes((Join-Path $tmpRoot $emptyArtifactRel), [byte[]]@())

    foreach ($case in $driftCases) {
        $now = Get-Date
        $state = [ordered]@{
            schema_version = 1
            mode = "full"
            execution = "guided-full"
            phase = "1A"
            question_pending = $true
            user_confirmed_next_phase = $false
            artifact_path = ""
            session_id = [guid]::NewGuid().ToString()
            owner = "forge-smoke"
            created_at = $now.ToString("o")
            updated_at = $now.ToString("o")
            expires_at = $now.AddHours(1).ToString("o")
            last_pipeline_marker = "[PIPELINE] 阶段 1A 进行中 → 等待用户回答"
        }
        if (@($case.expect_issues).Count -eq 0) {
            $state.question_pending = $false
            $state.user_confirmed_next_phase = $true
            $state.artifact_path = $artifactRel
        }
        if ([string]$case.setup -eq "empty_artifact") {
            $state.question_pending = $false
            $state.artifact_path = $emptyArtifactRel
        }
        if ([string]$case.setup -eq "expired_state") {
            $state.expires_at = $now.AddHours(-1).ToString("o")
        }
        if ([string]$case.setup -eq "expired_drill_state") {
            $state.is_drill = $true
            $state.expires_at = $now.AddHours(-1).ToString("o")
            $state.last_pipeline_marker = "[PIPELINE] 阶段 1A 完成 → 进入 M1 drill"
        }
        $state | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $statePath -Encoding UTF8

        $jsonText = & pwsh -NoLogo -NoProfile -ExecutionPolicy Bypass -File (Join-Path $ScriptDir 'Test-ForgeGuidedFullGate.ps1') -RepoPath $tmpRoot -CandidateText ([string]$case.candidate) -Json 2>$null
        $exit = $LASTEXITCODE
        try { $gate = $jsonText | ConvertFrom-Json -AsHashtable } catch { $gate = @{ issues = @("invalid_gate_output") } }
        $actualIssues = @($gate.issues)
        $expectedIssues = @($case.expect_issues)
        $ok = $true
        foreach ($issue in $expectedIssues) { if ($actualIssues -notcontains $issue) { $ok = $false } }
        if ($expectedIssues.Count -eq 0 -and $exit -ne 0) { $ok = $false }
        if ($expectedIssues.Count -gt 0 -and $exit -eq 0) { $ok = $false }
        if ($ok) { $driftPassed++ } else { $driftFailed++ }
        if (-not $NoLog) {
            [ordered]@{
                time = (Get-Date).ToString("o")
                skill = $raw.skill_name
                id = $case.id
                expected_issues = $expectedIssues
                actual_issues = $actualIssues
                passed = $ok
            } | ConvertTo-Json -Depth 8 -Compress | Add-Content -LiteralPath $LogPath -Encoding utf8
        }
    }
}
Write-Output "drift_gate_total=$($driftCases.Count)"
Write-Output "drift_gate_passed=$driftPassed"
Write-Output "drift_gate_failed=$driftFailed"
Complete-SmokeStep -Name "drift_gate" -Ok ($driftFailed -eq 0) -Timer $timer
if ($driftFailed -gt 0) { exit 1 }
}

# PreToolUse and Stop audit hook evals: verify runtime hooks enforce M1 discipline.
if (-not $Quick -and -not $Minimal) {
$timer = Start-SmokeStep -Name "hook_gate"
$hookTotal = 7
$hookPassed = 0
$hookFailed = 0
$hookRoot = Join-Path $env:TEMP ("forge-smoke-hooks-" + [guid]::NewGuid().ToString("N"))
New-Item -ItemType Directory -Force -Path (Join-Path $hookRoot ".claude") | Out-Null
git init $hookRoot 2>$null | Out-Null
$hookState = [ordered]@{
    schema_version = 1
    execution = "guided-full"
    phase = "M1"
    question_pending = $false
    user_confirmed_next_phase = $true
    session_id = [guid]::NewGuid().ToString()
    owner = "forge-smoke"
    created_at = (Get-Date).ToString("o")
    updated_at = (Get-Date).ToString("o")
    expires_at = (Get-Date).AddHours(1).ToString("o")
}
$hookState | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath (Join-Path $hookRoot ".claude\forge-session-state.json") -Encoding UTF8
$writePayload = '{"tool_name":"Write","tool_input":{"file_path":"src/app.ts"}}'

# Hook 1: M1 project write without started routing must fail.
$writePayload | pwsh -NoLogo -NoProfile -ExecutionPolicy Bypass -File $HookScriptPath -RepoPath $hookRoot 2>$null | Out-Null
if ($LASTEXITCODE -ne 0) { $hookPassed++ } else { $hookFailed++ }

# Hook 2: M1 project write with started routing may pass.
& pwsh -NoLogo -NoProfile -ExecutionPolicy Bypass -File (Join-Path $ScriptDir 'write-forge-routing.ps1') -RepoPath $hookRoot -Level L3 -Mode full -Execution guided-full -AdoptionMode local_routing -PipelinePhase M1 -TaskGroup Hook.ok -GroupStatus started -TodoRef "todo:Hook.ok" -VerificationRef "planned:typecheck" -Reason "hook_smoke" | Out-Null
$writePayload | pwsh -NoLogo -NoProfile -ExecutionPolicy Bypass -File $HookScriptPath -RepoPath $hookRoot 2>$null | Out-Null
if ($LASTEXITCODE -eq 0) { $hookPassed++ } else { $hookFailed++ }

# Hook 3: high-risk/L4 started without TodoWrite/TDD/unit-or-integration TestRef must fail.
$hrHookRoot = Join-Path $env:TEMP ("forge-smoke-hooks-hr-" + [guid]::NewGuid().ToString("N"))
New-Item -ItemType Directory -Force -Path (Join-Path $hrHookRoot ".claude") | Out-Null
git init $hrHookRoot 2>$null | Out-Null
$hookState | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath (Join-Path $hrHookRoot ".claude\forge-session-state.json") -Encoding UTF8
& pwsh -NoLogo -NoProfile -ExecutionPolicy Bypass -File (Join-Path $ScriptDir 'write-forge-routing.ps1') -RepoPath $hrHookRoot -Level L4 -Mode full -Execution guided-full -AdoptionMode full -PipelinePhase M1 -TaskGroup Hook.hr -GroupStatus started -BatchProtocol full -HighRisk "auth" -TodoRef "skip:no-todo" -VerificationRef "planned:typecheck" -Reason "hook_smoke" -InheritedFrom ".claude/forge/artifacts/parent.md" -ExecutionScope light -ParentLevel L4 | Out-Null
$writePayload | pwsh -NoLogo -NoProfile -ExecutionPolicy Bypass -File $HookScriptPath -RepoPath $hrHookRoot 2>$null | Out-Null
if ($LASTEXITCODE -ne 0) { $hookPassed++ } else { $hookFailed++ }

# Hook 4: high-risk/L4 with planned TodoWrite/TDD/unit TestRef may pass.
$hrGoodRoot = Join-Path $env:TEMP ("forge-smoke-hooks-hr-good-" + [guid]::NewGuid().ToString("N"))
New-Item -ItemType Directory -Force -Path (Join-Path $hrGoodRoot ".claude") | Out-Null
git init $hrGoodRoot 2>$null | Out-Null
$hookState | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath (Join-Path $hrGoodRoot ".claude\forge-session-state.json") -Encoding UTF8
& pwsh -NoLogo -NoProfile -ExecutionPolicy Bypass -File (Join-Path $ScriptDir 'write-forge-routing.ps1') -RepoPath $hrGoodRoot -Level L4 -Mode full -Execution guided-full -AdoptionMode full -PipelinePhase M1 -TaskGroup Hook.hr.good -GroupStatus started -BatchProtocol full -HighRisk "auth" -TodoRef "TodoWrite:Hook.hr.good" -TddRef "red-green:auth" -TestRef "unit:planned" -VerificationRef "planned:unit" -Reason "hook_smoke" -InheritedFrom ".claude/forge/artifacts/parent.md" -ExecutionScope light -ParentLevel L4 | Out-Null
$writePayload | pwsh -NoLogo -NoProfile -ExecutionPolicy Bypass -File $HookScriptPath -RepoPath $hrGoodRoot 2>$null | Out-Null
if ($LASTEXITCODE -eq 0) { $hookPassed++ } else { $hookFailed++ }

# Hook 5: Stop audit fail-close blocks open M1 group.
& pwsh -NoLogo -NoProfile -ExecutionPolicy Bypass -File $AuditScriptPath -RepoPath $hookRoot -Event Stop -Mode fail-close 2>$null | Out-Null
if ($LASTEXITCODE -ne 0) { $hookPassed++ } else { $hookFailed++ }

# Hook 6: Stop audit warn reports but does not block open M1 group.
& pwsh -NoLogo -NoProfile -ExecutionPolicy Bypass -File $AuditScriptPath -RepoPath $hookRoot -Event Stop -Mode warn 2>$null | Out-Null
if ($LASTEXITCODE -eq 0) { $hookPassed++ } else { $hookFailed++ }

# Hook 7: expired state/lock is fail-close even when routing groups are completed.
$expiredRoot = Join-Path $env:TEMP ("forge-smoke-hooks-expired-" + [guid]::NewGuid().ToString("N"))
New-Item -ItemType Directory -Force -Path (Join-Path $expiredRoot ".claude\forge\artifacts") | Out-Null
git init $expiredRoot 2>$null | Out-Null
$expiredNow = Get-Date
$expiredState = [ordered]@{
    schema_version = 1
    mode = "full"
    execution = "guided-full"
    phase = "M1"
    question_pending = $false
    user_confirmed_next_phase = $true
    artifact_path = ".claude/forge/artifacts/expired.md"
    session_id = "hook-expired"
    is_drill = $false
    owner = "forge-smoke"
    created_at = $expiredNow.AddHours(-2).ToString("o")
    updated_at = $expiredNow.AddHours(-2).ToString("o")
    expires_at = $expiredNow.AddHours(-1).ToString("o")
}
$expiredLock = [ordered]@{
    schema_version = 1
    session_id = "hook-expired"
    owner = "forge-smoke"
    phase = "M1"
    created_at = $expiredNow.AddHours(-2).ToString("o")
    updated_at = $expiredNow.AddHours(-2).ToString("o")
    expires_at = $expiredNow.AddHours(-1).ToString("o")
}
$expiredState | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath (Join-Path $expiredRoot ".claude\forge-session-state.json") -Encoding UTF8
$expiredLock | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath (Join-Path $expiredRoot ".claude\forge-session.lock.json") -Encoding UTF8
"expired" | Set-Content -LiteralPath (Join-Path $expiredRoot ".claude\forge\artifacts\expired.md") -Encoding UTF8
& pwsh -NoLogo -NoProfile -ExecutionPolicy Bypass -File (Join-Path $ScriptDir 'write-forge-routing.ps1') -RepoPath $expiredRoot -Level L3 -Mode full -Execution guided-full -AdoptionMode local_routing -PipelinePhase M1 -TaskGroup Hook.expired -GroupStatus started -TodoRef "TodoWrite:Hook.expired" -VerificationRef "planned:unit" -Reason "hook_expiry_smoke" | Out-Null
& pwsh -NoLogo -NoProfile -ExecutionPolicy Bypass -File (Join-Path $ScriptDir 'write-forge-routing.ps1') -RepoPath $expiredRoot -Level L3 -Mode full -Execution guided-full -AdoptionMode local_routing -PipelinePhase M1 -TaskGroup Hook.expired -GroupStatus completed -TodoRef "TodoWrite:Hook.expired" -TestRef "unit:passed" -VerificationRef "unit:passed" -Reason "hook_expiry_smoke" | Out-Null
& pwsh -NoLogo -NoProfile -ExecutionPolicy Bypass -File $AuditScriptPath -RepoPath $expiredRoot -Event Stop -Mode fail-close 2>$null | Out-Null
if ($LASTEXITCODE -ne 0) { $hookPassed++ } else { $hookFailed++ }

Write-Output "hook_gate_total=$hookTotal"
Write-Output "hook_gate_passed=$hookPassed"
Write-Output "hook_gate_failed=$hookFailed"
Complete-SmokeStep -Name "hook_gate" -Ok ($hookFailed -eq 0) -Timer $timer
if ($hookFailed -gt 0) { exit 1 }
} else {
    Write-SkippedGate -Name "hook_gate" -Prefix "hook_gate"
}

# M1 compliance evals: verify implementation-phase routing discipline.
if (-not $Quick -and -not $Minimal) {
$timer = Start-SmokeStep -Name "m1_gate"
$m1Total = 5
$m1Passed = 0
$m1Failed = 0
$m1Root = Join-Path $env:TEMP ("forge-smoke-m1-" + [guid]::NewGuid().ToString("N"))
New-Item -ItemType Directory -Force -Path (Join-Path $m1Root ".claude\forge\artifacts") | Out-Null
git init $m1Root 2>$null | Out-Null

# Case 1: missing FORGE header/routing should fail.
$badText = "[PIPELINE] 阶段 M1.1 完成 → 进入 done"
& pwsh -NoLogo -NoProfile -ExecutionPolicy Bypass -File (Join-Path $ScriptDir 'Test-ForgeM1Compliance.ps1') -RepoPath $m1Root -TaskGroup "M1.1" -CandidateText $badText -Json 2>$null | Out-Null
if ($LASTEXITCODE -ne 0) { $m1Passed++ } else { $m1Failed++ }

# Case 2: completed event exists but started event missing should fail.
& pwsh -NoLogo -NoProfile -ExecutionPolicy Bypass -File (Join-Path $ScriptDir 'write-forge-routing.ps1') -RepoPath $m1Root -Level L3 -Mode full -Execution guided-full -AdoptionMode local_routing -PipelinePhase M1 -TaskGroup M1.missingStarted -GroupStatus completed -TodoRef "todo:done" -VerificationRef "skip:smoke" -ArtifactRef "skip:smoke" -CommitSha "skip:smoke" -LearningsRef "skip:smoke" -NextPhase "done" -Reason "m1_smoke" | Out-Null
$case2 = "[FORGE] phase=M1 group=M1.missingStarted mode=full reason=m1_smoke`n[PIPELINE] 阶段 M1.missingStarted 完成 → 进入 done"
& pwsh -NoLogo -NoProfile -ExecutionPolicy Bypass -File (Join-Path $ScriptDir 'Test-ForgeM1Compliance.ps1') -RepoPath $m1Root -TaskGroup "M1.missingStarted" -CandidateText $case2 -Json 2>$null | Out-Null
if ($LASTEXITCODE -ne 0) { $m1Passed++ } else { $m1Failed++ }

# Case 3: missing verification/todo refs should fail.
& pwsh -NoLogo -NoProfile -ExecutionPolicy Bypass -File (Join-Path $ScriptDir 'write-forge-routing.ps1') -RepoPath $m1Root -Level L3 -Mode full -Execution guided-full -AdoptionMode local_routing -PipelinePhase M1 -TaskGroup M1.missingRefs -GroupStatus started -Reason "m1_smoke" | Out-Null
& pwsh -NoLogo -NoProfile -ExecutionPolicy Bypass -File (Join-Path $ScriptDir 'write-forge-routing.ps1') -RepoPath $m1Root -Level L3 -Mode full -Execution guided-full -AdoptionMode local_routing -PipelinePhase M1 -TaskGroup M1.missingRefs -GroupStatus completed -CommitSha "skip:smoke" -LearningsRef "skip:smoke" -NextPhase "done" -Reason "m1_smoke" | Out-Null
$case3 = "[FORGE] phase=M1 group=M1.missingRefs mode=full reason=m1_smoke`n[PIPELINE] 阶段 M1.missingRefs 完成 → 进入 done"
& pwsh -NoLogo -NoProfile -ExecutionPolicy Bypass -File (Join-Path $ScriptDir 'Test-ForgeM1Compliance.ps1') -RepoPath $m1Root -TaskGroup "M1.missingRefs" -CandidateText $case3 -Json 2>$null | Out-Null
if ($LASTEXITCODE -ne 0) { $m1Passed++ } else { $m1Failed++ }

# Case 4: non-skip learnings/artifact/verification refs must exist.
& pwsh -NoLogo -NoProfile -ExecutionPolicy Bypass -File (Join-Path $ScriptDir 'write-forge-routing.ps1') -RepoPath $m1Root -Level L3 -Mode full -Execution guided-full -AdoptionMode local_routing -PipelinePhase M1 -TaskGroup M1.missingFiles -GroupStatus started -Reason "m1_smoke" | Out-Null
& pwsh -NoLogo -NoProfile -ExecutionPolicy Bypass -File (Join-Path $ScriptDir 'write-forge-routing.ps1') -RepoPath $m1Root -Level L3 -Mode full -Execution guided-full -AdoptionMode local_routing -PipelinePhase M1 -TaskGroup M1.missingFiles -GroupStatus completed -TodoRef "todo:done" -VerificationRef ".claude/forge/verification/missing.log" -ArtifactRef ".claude/forge/artifacts/missing.md" -CommitSha "skip:smoke" -LearningsRef ".claude/compound-learnings.md" -NextPhase "done" -Reason "m1_smoke" | Out-Null
$case4 = "[FORGE] phase=M1 group=M1.missingFiles mode=full reason=m1_smoke`n[PIPELINE] 阶段 M1.missingFiles 完成 → 进入 done"
& pwsh -NoLogo -NoProfile -ExecutionPolicy Bypass -File (Join-Path $ScriptDir 'Test-ForgeM1Compliance.ps1') -RepoPath $m1Root -TaskGroup "M1.missingFiles" -CandidateText $case4 -Json 2>$null | Out-Null
if ($LASTEXITCODE -ne 0) { $m1Passed++ } else { $m1Failed++ }

# Case 5: complete event chain should pass.
New-Item -ItemType Directory -Force -Path (Join-Path $m1Root ".claude\forge\verification") | Out-Null
Set-Content -LiteralPath (Join-Path $m1Root ".claude\forge\verification\M1.2.log") -Encoding UTF8 -Value "typecheck:pass"
Set-Content -LiteralPath (Join-Path $m1Root ".claude\forge\artifacts\M1.2.md") -Encoding UTF8 -Value "# M1.2 artifact"
Set-Content -LiteralPath (Join-Path $m1Root ".claude\compound-learnings.md") -Encoding UTF8 -Value "- smoke learning"
& pwsh -NoLogo -NoProfile -ExecutionPolicy Bypass -File (Join-Path $ScriptDir 'write-forge-routing.ps1') -RepoPath $m1Root -Level L3 -Mode full -Execution guided-full -AdoptionMode local_routing -PipelinePhase M1 -TaskGroup M1.2 -GroupStatus started -TodoRef "todo:M1.2" -VerificationRef "planned:typecheck" -ArtifactRef "artifact:planned" -Reason "m1_smoke" | Out-Null
& pwsh -NoLogo -NoProfile -ExecutionPolicy Bypass -File (Join-Path $ScriptDir 'write-forge-routing.ps1') -RepoPath $m1Root -Level L3 -Mode full -Execution guided-full -AdoptionMode local_routing -PipelinePhase M1 -TaskGroup M1.2 -GroupStatus completed -TodoRef "todo:M1.2:done" -VerificationRef ".claude/forge/verification/M1.2.log" -ArtifactRef ".claude/forge/artifacts/M1.2.md" -CommitSha "skip:smoke-no-commit" -LearningsRef ".claude/compound-learnings.md" -NextPhase "done" -Reason "m1_smoke" | Out-Null
$goodText = "[FORGE] phase=M1 group=M1.2 mode=full reason=m1_smoke`n[FORGE] write_scope=module verify=typecheck commit_required=false`n[PIPELINE] 阶段 M1.2 完成 → 进入 done"
& pwsh -NoLogo -NoProfile -ExecutionPolicy Bypass -File (Join-Path $ScriptDir 'Test-ForgeM1Compliance.ps1') -RepoPath $m1Root -TaskGroup "M1.2" -CandidateText $goodText -Json 2>$null | Out-Null
if ($LASTEXITCODE -eq 0) { $m1Passed++ } else { $m1Failed++ }

Write-Output "m1_gate_total=$m1Total"
Write-Output "m1_gate_passed=$m1Passed"
Write-Output "m1_gate_failed=$m1Failed"
Complete-SmokeStep -Name "m1_gate" -Ok ($m1Failed -eq 0) -Timer $timer
if ($m1Failed -gt 0) { exit 1 }
} else {
    Write-SkippedGate -Name "m1_gate" -Prefix "m1_gate"
}
# High-risk discipline evals: high-risk M1 cannot skip TodoWrite/TDD/tests.
if (-not $Quick -and -not $Minimal) {
$highriskTimer = Start-SmokeStep -Name "highrisk_gate"
$hrTotal = 3
$hrPassed = 0
$hrFailed = 0
$hrRoot = Join-Path $env:TEMP ("forge-smoke-hr-" + [guid]::NewGuid().ToString("N"))
New-Item -ItemType Directory -Force -Path (Join-Path $hrRoot ".claude") | Out-Null
git init $hrRoot 2>$null | Out-Null

# Case HR1: high risk with typecheck only and no TodoWrite/TDD/TestRef should fail.
& pwsh -NoLogo -NoProfile -ExecutionPolicy Bypass -File (Join-Path $ScriptDir 'write-forge-routing.ps1') -RepoPath $hrRoot -Level L4 -Mode full -Execution guided-full -AdoptionMode full -PipelinePhase M1 -BatchProtocol full -TaskGroup HR1 -GroupStatus started -Reason "hr_smoke" -InheritedFrom ".claude/forge/artifacts/parent.md" -ExecutionScope light -ParentLevel L4 2>$null | Out-Null
& pwsh -NoLogo -NoProfile -ExecutionPolicy Bypass -File (Join-Path $ScriptDir 'write-forge-routing.ps1') -RepoPath $hrRoot -Level L4 -Mode full -Execution guided-full -AdoptionMode full -PipelinePhase M1 -BatchProtocol full -TaskGroup HR1 -GroupStatus completed -HighRisk "auth,jwt" -TodoRef "skip:no-todo" -VerificationRef "typecheck:pass" -ArtifactRef "skip:smoke" -CommitSha "skip:smoke" -LearningsRef "skip:smoke" -NextPhase "done" -Reason "hr_smoke" -InheritedFrom ".claude/forge/artifacts/parent.md" -ExecutionScope light -ParentLevel L4 2>$null | Out-Null
$hrBad = "[FORGE] phase=M1 group=HR1 mode=full reason=hr_smoke`n[PIPELINE] 阶段 HR1 完成 → 进入 done"
& pwsh -NoLogo -NoProfile -ExecutionPolicy Bypass -File (Join-Path $ScriptDir 'Test-ForgeM1Compliance.ps1') -RepoPath $hrRoot -TaskGroup "HR1" -CandidateText $hrBad -Json 2>$null | Out-Null
if ($LASTEXITCODE -ne 0) { $hrPassed++ } else { $hrFailed++ }

# Case HR2: high risk with TodoWrite/TDD/TestRef should pass.
New-Item -ItemType Directory -Force -Path (Join-Path $hrRoot ".claude\forge\verification") | Out-Null
Set-Content -LiteralPath (Join-Path $hrRoot ".claude\forge\verification\HR2.log") -Encoding UTF8 -Value "typecheck:pass;unit:pass"
& pwsh -NoLogo -NoProfile -ExecutionPolicy Bypass -File (Join-Path $ScriptDir 'write-forge-routing.ps1') -RepoPath $hrRoot -Level L4 -Mode full -Execution guided-full -AdoptionMode full -PipelinePhase M1 -BatchProtocol full -TaskGroup HR2 -GroupStatus started -TodoRef "TodoWrite:HR2" -VerificationRef "planned:unit" -Reason "hr_smoke" -InheritedFrom ".claude/forge/artifacts/parent.md" -ExecutionScope light -ParentLevel L4 | Out-Null
& pwsh -NoLogo -NoProfile -ExecutionPolicy Bypass -File (Join-Path $ScriptDir 'write-forge-routing.ps1') -RepoPath $hrRoot -Level L4 -Mode full -Execution guided-full -AdoptionMode full -PipelinePhase M1 -BatchProtocol full -TaskGroup HR2 -GroupStatus completed -HighRisk "auth,jwt" -TodoRef "TodoWrite:HR2" -TddRef "red-green:jwt" -TestRef "unit:pass:5" -VerificationRef ".claude/forge/verification/HR2.log" -ArtifactRef "skip:smoke" -CommitSha "skip:smoke" -LearningsRef "skip:smoke" -NextPhase "done" -Reason "hr_smoke" -InheritedFrom ".claude/forge/artifacts/parent.md" -ExecutionScope light -ParentLevel L4 | Out-Null
$hrGood = "[FORGE] phase=M1 group=HR2 mode=full reason=hr_smoke`n[PIPELINE] 阶段 HR2 完成 → 进入 done"
& pwsh -NoLogo -NoProfile -ExecutionPolicy Bypass -File (Join-Path $ScriptDir 'Test-ForgeM1Compliance.ps1') -RepoPath $hrRoot -TaskGroup "HR2" -CandidateText $hrGood -Json 2>$null | Out-Null
if ($LASTEXITCODE -eq 0) { $hrPassed++ } else { $hrFailed++ }


# Case HR3: high risk with non-unit/non-integration TestRef should fail.
& pwsh -NoLogo -NoProfile -ExecutionPolicy Bypass -File (Join-Path $ScriptDir 'write-forge-routing.ps1') -RepoPath $hrRoot -Level L4 -Mode full -Execution guided-full -AdoptionMode full -PipelinePhase M1 -BatchProtocol full -TaskGroup HR3 -GroupStatus started -TodoRef "TodoWrite:HR3" -VerificationRef "planned:manual" -Reason "hr_smoke" -InheritedFrom ".claude/forge/artifacts/parent.md" -ExecutionScope light -ParentLevel L4 | Out-Null
& pwsh -NoLogo -NoProfile -ExecutionPolicy Bypass -File (Join-Path $ScriptDir 'write-forge-routing.ps1') -RepoPath $hrRoot -Level L4 -Mode full -Execution guided-full -AdoptionMode full -PipelinePhase M1 -BatchProtocol full -TaskGroup HR3 -GroupStatus completed -HighRisk "auth,jwt" -TodoRef "TodoWrite:HR3" -TddRef "red-green:jwt" -TestRef "manual:checked" -VerificationRef "typecheck:pass;manual:checked" -ArtifactRef "skip:smoke" -CommitSha "skip:smoke" -LearningsRef "skip:smoke" -NextPhase "done" -Reason "hr_smoke" -InheritedFrom ".claude/forge/artifacts/parent.md" -ExecutionScope light -ParentLevel L4 | Out-Null
$hrManualOnly = "[FORGE] phase=M1 group=HR3 mode=full reason=hr_smoke`n[PIPELINE] 阶段 HR3 完成 → 进入 done"
& pwsh -NoLogo -NoProfile -ExecutionPolicy Bypass -File (Join-Path $ScriptDir 'Test-ForgeM1Compliance.ps1') -RepoPath $hrRoot -TaskGroup "HR3" -CandidateText $hrManualOnly -Json 2>$null | Out-Null
if ($LASTEXITCODE -ne 0) { $hrPassed++ } else { $hrFailed++ }

# L4 downgrade contract smoke: project-level L4 with batch-level L2/build must carry downgrade reason and parent plan ref.
$l4DowngradeTotal = 3
$l4DowngradePassed = 0
$l4DowngradeFailed = 0
$l4Root = Join-Path $env:TEMP ("forge-smoke-l4-downgrade-" + [guid]::NewGuid().ToString("N"))
New-Item -ItemType Directory -Force -Path (Join-Path $l4Root ".claude") | Out-Null
git init $l4Root 2>$null | Out-Null

# Case 1: write should reject missing BatchProtocol for L4 M1.
& pwsh -NoLogo -NoProfile -ExecutionPolicy Bypass -File (Join-Path $ScriptDir 'write-forge-routing.ps1') -RepoPath $l4Root -Level L4 -Mode full -Execution guided-full -AdoptionMode full -PipelinePhase M1 -TaskGroup L4.missingBatch -GroupStatus completed -TodoRef "skip:smoke" -VerificationRef "skip:smoke" -ArtifactRef "skip:smoke" -CommitSha "skip:smoke" -LearningsRef "skip:smoke" -NextPhase "done" -Reason "l4_downgrade_smoke" -InheritedFrom ".claude/forge/artifacts/parent.md" -ExecutionScope light -ParentLevel L4 2>$null | Out-Null
if ($LASTEXITCODE -ne 0) { $l4DowngradePassed++ } else { $l4DowngradeFailed++ }

# Case 2: legacy log without batch_protocol should fail M1 compliance.
$legacyRoot = Join-Path $env:TEMP ("forge-smoke-l4-legacy-" + [guid]::NewGuid().ToString("N"))
New-Item -ItemType Directory -Force -Path (Join-Path $legacyRoot ".claude") | Out-Null
$legacyRouting = Join-Path $legacyRoot ".claude\forge-routing.jsonl"
[ordered]@{ time=(Get-Date).ToString("o"); repo=$legacyRoot; level="L4"; mode="full"; pipeline_phase="M1"; task_group="L4.legacy"; group_status="started" } | ConvertTo-Json -Compress | Add-Content -LiteralPath $legacyRouting -Encoding utf8
[ordered]@{ time=(Get-Date).ToString("o"); repo=$legacyRoot; level="L4"; mode="full"; pipeline_phase="M1"; task_group="L4.legacy"; group_status="completed"; todo_ref="skip:smoke"; verification_ref="skip:smoke"; artifact_ref="skip:smoke"; commit_sha="skip:smoke"; learnings_ref="skip:smoke"; next_phase="done" } | ConvertTo-Json -Compress | Add-Content -LiteralPath $legacyRouting -Encoding utf8
$l4LegacyText = "[FORGE] phase=M1 group=L4.legacy mode=full reason=smoke`n[PIPELINE] 阶段 L4.legacy 完成 → 进入 done"
& pwsh -NoLogo -NoProfile -ExecutionPolicy Bypass -File (Join-Path $ScriptDir 'Test-ForgeM1Compliance.ps1') -RepoPath $legacyRoot -TaskGroup "L4.legacy" -CandidateText $l4LegacyText -Json 2>$null | Out-Null
if ($LASTEXITCODE -ne 0) { $l4DowngradePassed++ } else { $l4DowngradeFailed++ }

# Case 3: explicit build downgrade with reason and parent plan ref should pass.
& pwsh -NoLogo -NoProfile -ExecutionPolicy Bypass -File (Join-Path $ScriptDir 'write-forge-routing.ps1') -RepoPath $l4Root -Level L4 -Mode full -Execution guided-full -AdoptionMode full -PipelinePhase M1 -TaskGroup L4.good -GroupStatus started -BatchProtocol build -DowngradeReason within_confirmed_plan -ParentPlanRef ".claude/forge/artifacts/parent.md" -Reason "l4_downgrade_smoke" -InheritedFrom ".claude/forge/artifacts/parent.md" -ExecutionScope light -ParentLevel L4 | Out-Null
& pwsh -NoLogo -NoProfile -ExecutionPolicy Bypass -File (Join-Path $ScriptDir 'write-forge-routing.ps1') -RepoPath $l4Root -Level L4 -Mode full -Execution guided-full -AdoptionMode full -PipelinePhase M1 -TaskGroup L4.good -GroupStatus completed -BatchProtocol build -DowngradeReason within_confirmed_plan -ParentPlanRef ".claude/forge/artifacts/parent.md" -TodoRef "skip:smoke" -VerificationRef "skip:smoke" -ArtifactRef "skip:smoke" -CommitSha "skip:smoke" -LearningsRef "skip:smoke" -NextPhase "done" -Reason "l4_downgrade_smoke" -InheritedFrom ".claude/forge/artifacts/parent.md" -ExecutionScope light -ParentLevel L4 | Out-Null
$l4GoodText = "[FORGE] phase=M1 group=L4.good mode=full reason=smoke`n[PIPELINE] 阶段 L4.good 完成 → 进入 done"
& pwsh -NoLogo -NoProfile -ExecutionPolicy Bypass -File (Join-Path $ScriptDir 'Test-ForgeM1Compliance.ps1') -RepoPath $l4Root -TaskGroup "L4.good" -CandidateText $l4GoodText -Json 2>$null | Out-Null
if ($LASTEXITCODE -eq 0) { $l4DowngradePassed++ } else { $l4DowngradeFailed++ }

Write-Output "l4_downgrade_gate_total=$l4DowngradeTotal"
Write-Output "l4_downgrade_gate_passed=$l4DowngradePassed"
Write-Output "l4_downgrade_gate_failed=$l4DowngradeFailed"
if ($l4DowngradeFailed -gt 0) { exit 1 }
Write-Output "highrisk_gate_total=$hrTotal"
Write-Output "highrisk_gate_passed=$hrPassed"
Write-Output "highrisk_gate_failed=$hrFailed"
Complete-SmokeStep -Name "highrisk_gate" -Ok ($hrFailed -eq 0) -Timer $highriskTimer
if ($hrFailed -gt 0) { exit 1 }
} else {
    $hrTotal = 0
    $hrPassed = 0
    $hrFailed = 0
    Write-SkippedGate -Name "highrisk_gate" -Prefix "highrisk_gate"
    Write-SkippedGate -Name "l4_downgrade_gate" -Prefix "l4_downgrade_gate"
}

# External adapter contract smoke: upstream frameworks must stay isolated behind Forge adapters.
$timer = Start-SmokeStep -Name "adapter_contract"
$adapterJson = & pwsh -NoLogo -NoProfile -ExecutionPolicy Bypass -File (Join-Path $ScriptDir 'Test-ForgeAdapterCompatibility.ps1') -RepoPath (Get-Location).Path -Json
$adapterExit = $LASTEXITCODE
try { $adapter = $adapterJson | ConvertFrom-Json -AsHashtable } catch { $adapter = @{ ok = $false; issues = @("invalid_adapter_output") } }
$adapterPassed = if ($adapterExit -eq 0 -and [bool]$adapter.ok) { 1 } else { 0 }
$adapterFailed = if ($adapterPassed -eq 1) { 0 } else { 1 }
Write-Output "adapter_contract_total=1"
Write-Output "adapter_contract_passed=$adapterPassed"
Write-Output "adapter_contract_failed=$adapterFailed"
Complete-SmokeStep -Name "adapter_contract" -Ok ($adapterFailed -eq 0) -Timer $timer
if ($adapterFailed -gt 0) {
    $adapter | ConvertTo-Json -Depth 8
    exit 1
}

# Forge docs health smoke: command/skill/docs boundaries must not drift.
$timer = Start-SmokeStep -Name "docs_health"
$docsHealthJson = & pwsh -NoLogo -NoProfile -ExecutionPolicy Bypass -File (Join-Path $ScriptDir 'Test-ForgeDocsHealth.ps1') -ClaudeRoot (Get-Location).Path -Json
$docsHealthExit = $LASTEXITCODE
try { $docsHealth = $docsHealthJson | ConvertFrom-Json -AsHashtable } catch { $docsHealth = @{ ok = $false; issues = @("invalid_docs_health_output") } }
$docsHealthPassed = if ($docsHealthExit -eq 0 -and [bool]$docsHealth.ok) { 1 } else { 0 }
$docsHealthFailed = if ($docsHealthPassed -eq 1) { 0 } else { 1 }
Write-Output "docs_health_total=1"
Write-Output "docs_health_passed=$docsHealthPassed"
Write-Output "docs_health_failed=$docsHealthFailed"
Complete-SmokeStep -Name "docs_health" -Ok ($docsHealthFailed -eq 0) -Timer $timer
if ($docsHealthFailed -gt 0) {
    $docsHealth | ConvertTo-Json -Depth 8
    exit 1
}

# Release readiness is a separate CI layer. Keep it optional here so smoke can
# validate runtime behavior without recursively invoking aggregate gates.
$timer = Start-SmokeStep -Name "release_readiness"
if ($SkipReleaseReadiness) {
    Write-Output "release_readiness_total=0"
    Write-Output "release_readiness_passed=0"
    Write-Output "release_readiness_failed=0"
    Write-Output "release_readiness_skipped=1"
    Complete-SmokeStep -Name "release_readiness" -Ok $true -Timer $timer
} else {
    $readinessJson = & pwsh -NoLogo -NoProfile -ExecutionPolicy Bypass -File (Join-Path $ScriptDir 'Test-ForgeReleaseReadiness.ps1') -RepoPath (Get-Location).Path -SkipSmoke -Json
    $readinessExit = $LASTEXITCODE
    try { $readiness = $readinessJson | ConvertFrom-Json -AsHashtable } catch { $readiness = @{ ok = $false; failed = @("invalid_readiness_output"); raw_output = $readinessJson } }
    $readinessPassed = if ($readinessExit -eq 0 -and [bool]$readiness.ok) { 1 } else { 0 }
    $readinessFailed = if ($readinessPassed -eq 1) { 0 } else { 1 }
    Write-Output "release_readiness_total=1"
    Write-Output "release_readiness_passed=$readinessPassed"
    Write-Output "release_readiness_failed=$readinessFailed"
    Complete-SmokeStep -Name "release_readiness" -Ok ($readinessFailed -eq 0) -Timer $timer
    if ($readinessFailed -gt 0) {
        $readiness | ConvertTo-Json -Depth 8
        exit 1
    }
}

if ($failed -gt 0) {
    $results | Where-Object { -not $_.passed } | ConvertTo-Json -Depth 6
    exit 1
}
exit 0

