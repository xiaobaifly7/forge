[CmdletBinding()]
param(
    [string]$LogPath = "$env:USERPROFILE\.claude\logs\forge-smoke.jsonl",
    [int]$MaxAgeHours = 24,
    [string]$RequiredClaudeVersion = "",
    [switch]$Json
)

$ErrorActionPreference = "Stop"
$requiredModes = @('quick','fix','build','full','ship')
$requiredExecutions = @('audit-only','auto','guided-full')
$issues = [System.Collections.Generic.List[string]]::new()
function Add-Issue { param([string]$Code) if (-not $issues.Contains($Code)) { [void]$issues.Add($Code) } }

if (-not (Test-Path -LiteralPath $LogPath)) {
    Add-Issue 'live_route_log_missing'
    $result = [ordered]@{ ok=$false; log_path=$LogPath; max_age_hours=$MaxAgeHours; required_modes=$requiredModes; required_executions=$requiredExecutions; covered_modes=@(); covered_executions=@(); issues=@($issues) }
    if ($Json) { $result | ConvertTo-Json -Depth 8 } else { foreach($i in $issues){ "issue=$i" } }
    exit 1
}

$events = @()
foreach ($line in Get-Content -LiteralPath $LogPath -Encoding UTF8) {
    if ([string]::IsNullOrWhiteSpace($line)) { continue }
    try {
        $item = $line | ConvertFrom-Json -AsHashtable
        if ($item.Contains('live') -and [bool]$item.live) { $events += $item }
    } catch {}
}
if ($events.Count -eq 0) { Add-Issue 'live_route_events_missing' }

$latestByMode = @{}
foreach ($event in $events) {
    $mode = [string]$event.expected_mode
    if ([string]::IsNullOrWhiteSpace($mode)) { $mode = [string]$event.actual_mode }
    if ([string]::IsNullOrWhiteSpace($mode)) { continue }
    try { $time = [datetime]::Parse([string]$event.time) } catch { continue }
    if (-not $latestByMode.ContainsKey($mode) -or $time -gt [datetime]$latestByMode[$mode].parsed_time) {
        $copy = [ordered]@{}
        foreach ($k in $event.Keys) { $copy[$k] = $event[$k] }
        $copy['parsed_time'] = $time
        $latestByMode[$mode] = $copy
    }
}

$now = Get-Date
$coveredModes = @()
$coveredExecutions = @()
$executionResults = @()
$latestByExecution = @{}
foreach ($event in $events) {
    $executionKey = [string]$event.expected_execution
    if ([string]::IsNullOrWhiteSpace($executionKey)) { $executionKey = [string]$event.actual_execution }
    if ([string]::IsNullOrWhiteSpace($executionKey)) { continue }
    try { $executionTime = [datetime]::Parse([string]$event.time) } catch { continue }
    if (-not $latestByExecution.ContainsKey($executionKey) -or $executionTime -gt [datetime]$latestByExecution[$executionKey].parsed_time) {
        $copy = [ordered]@{}
        foreach ($k in $event.Keys) { $copy[$k] = $event[$k] }
        $copy['parsed_time'] = $executionTime
        $latestByExecution[$executionKey] = $copy
    }
}
$modeResults = @()
foreach ($mode in $requiredModes) {
    if (-not $latestByMode.ContainsKey($mode)) {
        Add-Issue "missing_live_route_mode:$mode"
        $modeResults += [ordered]@{ mode=$mode; ok=$false; issue='missing' }
        continue
    }
    $event = $latestByMode[$mode]
    $ageHours = ($now - [datetime]$event.parsed_time).TotalHours
    $passed = $false
    try { $passed = [bool]$event.passed } catch {}
    $exitCode = if ($event.Contains('exit_code')) { [int]$event.exit_code } else { $null }
    $actual = [string]$event.actual_mode
    $actualExecutionForMode = [string]$event.actual_execution
    $expectedExecutionForMode = [string]$event.expected_execution
    $ok = $true
    $modeIssues = @()
    if (-not $passed) { $ok = $false; $modeIssues += 'not_passed'; Add-Issue "live_route_not_passed:$mode" }
    if ($null -ne $exitCode -and $exitCode -ne 0) { $ok = $false; $modeIssues += "exit_code:$exitCode"; Add-Issue "live_route_exit_nonzero:$mode" }
    if ($actual -and $actual -ne $mode) { $ok = $false; $modeIssues += "actual_mode:$actual"; Add-Issue "live_route_mode_mismatch:$mode" }
    if ([string]::IsNullOrWhiteSpace($expectedExecutionForMode) -or [string]::IsNullOrWhiteSpace($actualExecutionForMode)) { $ok = $false; $modeIssues += 'missing_execution'; Add-Issue "live_route_missing_execution:$mode" }
    elseif ($actualExecutionForMode -ne $expectedExecutionForMode) { $ok = $false; $modeIssues += "actual_execution:$actualExecutionForMode"; Add-Issue "live_route_execution_mismatch:$mode" }
    if ($ageHours -gt $MaxAgeHours) { $ok = $false; $modeIssues += ('stale_hours:{0:N2}' -f $ageHours); Add-Issue "live_route_stale:$mode" }
    if ($ok) { $coveredModes += $mode }
    $modeResults += [ordered]@{
        mode = $mode
        ok = $ok
        id = [string]$event.id
        time = [string]$event.time
        age_hours = [Math]::Round($ageHours, 2)
        expected_mode = [string]$event.expected_mode
        actual_mode = $actual
        expected_execution = $expectedExecutionForMode
        actual_execution = $actualExecutionForMode
        passed = $passed
        exit_code = $exitCode
        output_sha256 = [string]$event.output_sha256
        issues = @($modeIssues)
    }
}

foreach ($execution in $requiredExecutions) {
    if (-not $latestByExecution.ContainsKey($execution)) {
        Add-Issue "missing_live_route_execution:$execution"
        $executionResults += [ordered]@{ execution=$execution; ok=$false; issue='missing' }
        continue
    }
    $event = $latestByExecution[$execution]
    $ageHours = ($now - [datetime]$event.parsed_time).TotalHours
    $passed = $false
    try { $passed = [bool]$event.passed } catch {}
    $exitCode = if ($event.Contains('exit_code')) { [int]$event.exit_code } else { $null }
    $actualExecution = [string]$event.actual_execution
    $expectedExecution = [string]$event.expected_execution
    $executionIssues = @()
    $ok = $true
    if (-not $passed) { $ok = $false; $executionIssues += 'not_passed'; Add-Issue "live_route_execution_not_passed:$execution" }
    if ($null -ne $exitCode -and $exitCode -ne 0) { $ok = $false; $executionIssues += "exit_code:$exitCode"; Add-Issue "live_route_execution_exit_nonzero:$execution" }
    if ([string]::IsNullOrWhiteSpace($expectedExecution) -or [string]::IsNullOrWhiteSpace($actualExecution)) { $ok = $false; $executionIssues += 'missing_execution'; Add-Issue "live_route_missing_execution:$execution" }
    elseif ($actualExecution -ne $execution) { $ok = $false; $executionIssues += "actual_execution:$actualExecution"; Add-Issue "live_route_execution_mismatch:$execution" }
    if ($ageHours -gt $MaxAgeHours) { $ok = $false; $executionIssues += ('stale_hours:{0:N2}' -f $ageHours); Add-Issue "live_route_execution_stale:$execution" }
    if ($ok) { $coveredExecutions += $execution }
    $executionResults += [ordered]@{
        execution = $execution
        ok = $ok
        id = [string]$event.id
        mode = [string]$event.expected_mode
        time = [string]$event.time
        age_hours = [Math]::Round($ageHours, 2)
        expected_execution = $expectedExecution
        actual_execution = $actualExecution
        passed = $passed
        exit_code = $exitCode
        output_sha256 = [string]$event.output_sha256
        issues = @($executionIssues)
    }
}

$claudeVersion = $null
try { $claudeVersion = (& claude --version 2>$null | Select-Object -First 1).Trim() } catch {}
if ($RequiredClaudeVersion) {
    if (-not $claudeVersion -or $claudeVersion -notmatch [regex]::Escape($RequiredClaudeVersion)) { Add-Issue 'claude_version_mismatch' }
}

$result = [ordered]@{
    ok = ($issues.Count -eq 0)
    log_path = $LogPath
    max_age_hours = $MaxAgeHours
    checked_at = (Get-Date).ToString('o')
    claude_version = $claudeVersion
    required_claude_version = $RequiredClaudeVersion
    required_modes = $requiredModes
    covered_modes = @($coveredModes)
    required_executions = $requiredExecutions
    covered_executions = @($coveredExecutions)
    mode_results = @($modeResults)
    execution_results = @($executionResults)
    issues = @($issues)
}

if ($Json) { $result | ConvertTo-Json -Depth 12 }
else {
    if ($result.ok) { Write-Output 'forge_live_route_freshness=ok' } else { Write-Output 'forge_live_route_freshness=fail' }
    Write-Output "covered_modes=$(@($coveredModes) -join ',')"
    Write-Output "covered_executions=$(@($coveredExecutions) -join ',')"
    foreach ($issue in $issues) { Write-Output "issue=$issue" }
}
if (-not $result.ok) { exit 1 }
exit 0
