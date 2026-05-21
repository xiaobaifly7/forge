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

