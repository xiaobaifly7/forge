[CmdletBinding()]
param(
    [string]$RepoPath = ".",
    [string]$PrNumber = "",
    [switch]$AllowMissingPrChecks,
    [switch]$SkipSmoke,
    [switch]$Full,
    [switch]$Strict,
    [switch]$Json
)

$ErrorActionPreference = "Continue"
$ScriptDir = Split-Path -Parent $PSCommandPath
$RepoRoot = (Resolve-Path -LiteralPath $RepoPath).Path
$checks = @()
$ProgressEnabled = -not $Json

function Write-ReadinessProgress {
    param([string]$Message)
    if ($script:ProgressEnabled) {
        [Console]::Out.WriteLine("[verify] $Message")
    }
}

function Start-ReadinessStep {
    param([string]$Name)
    Write-ReadinessProgress -Message "start $Name"
    return [System.Diagnostics.Stopwatch]::StartNew()
}

function Complete-ReadinessStep {
    param(
        [string]$Name,
        [bool]$Ok,
        [string]$Severity = "error",
        [System.Diagnostics.Stopwatch]$Timer
    )
    if ($Timer) { $Timer.Stop() }
    $durationMs = if ($Timer) { $Timer.ElapsedMilliseconds } else { 0 }
    $label = if ($Ok) { "pass" } elseif ($Severity -eq "warning") { "warn" } else { "fail" }
    Write-ReadinessProgress -Message "$label $Name duration_ms=$durationMs"
    return $durationMs
}

function Add-ReadinessCheck {
    param(
        [string]$Name,
        [bool]$Ok,
        [string]$Severity = "error",
        [string]$Summary = "",
        [object]$Details = $null,
        [long]$DurationMs = -1
    )
    $script:checks += [ordered]@{
        name = $Name
        ok = $Ok
        severity = if ($Ok) { "pass" } else { $Severity }
        summary = $Summary
        details = $Details
        duration_ms = $(if ($DurationMs -ge 0) { $DurationMs } else { $null })
    }
}

function Invoke-ProcessJson {
    param(
        [string[]]$Arguments,
        [string]$WorkingDirectory = $RepoRoot,
        [int]$TimeoutSeconds = 120
    )
    $stdout = [System.IO.Path]::GetTempFileName()
    $stderr = [System.IO.Path]::GetTempFileName()
    try {
        $process = Start-Process -FilePath "pwsh.exe" -ArgumentList $Arguments -WorkingDirectory $WorkingDirectory -NoNewWindow -PassThru -RedirectStandardOutput $stdout -RedirectStandardError $stderr
        if (-not $process.WaitForExit([Math]::Max(1, $TimeoutSeconds) * 1000)) {
            try { $process.Kill($true) } catch { try { $process.Kill() } catch {} }
            return [ordered]@{ exit_code = 124; output = "timeout_after_seconds=$TimeoutSeconds"; json = $null }
        }
        $output = @(
            if (Test-Path -LiteralPath $stdout) { Get-Content -LiteralPath $stdout -Raw -ErrorAction SilentlyContinue }
            if (Test-Path -LiteralPath $stderr) { Get-Content -LiteralPath $stderr -Raw -ErrorAction SilentlyContinue }
        ) -join "`n"
        $parsed = $null
        try { $parsed = $output | ConvertFrom-Json -AsHashtable } catch {}
        return [ordered]@{ exit_code = $process.ExitCode; output = $output; json = $parsed }
    } catch {
        return [ordered]@{ exit_code = 1; output = $_.Exception.Message; json = $null }
    } finally {
        Remove-Item -LiteralPath $stdout, $stderr -Force -ErrorAction SilentlyContinue
    }
}

function Invoke-Git {
    param([string[]]$Arguments)
    $output = & git -C $RepoRoot @Arguments 2>&1
    return [ordered]@{ exit_code = $LASTEXITCODE; output = (@($output) -join "`n") }
}

function Get-ReadinessFixHint {
    param([string]$Name)
    switch ($Name) {
        { $_ -like "adapter_*_baseline" } { return "Run Compare-ForgeExternalAdapterRef.ps1 -Name <adapter> -RecordBaseline after reviewing upstream drift." }
        "quick_health" { return "Run Invoke-ForgeHealth.ps1 -Mode Quick -RepoPath . and fix failed health checks." }
        "hook_source_hash" { return "Copy reviewed hook source files from hooks/ to .claude/hooks/ or intentionally remove stale fixture copies." }
        "smoke" { return "Run forge-smoke.ps1 -NoLog -SkipReleaseReadiness and fix the first failed smoke layer." }
        "diff_check" { return "Run git diff --check and remove whitespace/conflict-marker errors." }
        "worktree_status" { return "Commit, stash, or intentionally document the remaining worktree changes." }
        "pr_checks_present" { return "Wait for GitHub checks or rerun with -AllowMissingPrChecks only for local pre-push." }
        "pr_merge_state" { return "Resolve PR merge state before marking release ready." }
        default { return "Inspect check details and rerun readiness." }
    }
}

$manifests = @("flow-kit", "trellis")
foreach ($name in $manifests) {
    $checkName = "adapter_${name}_baseline"
    $timer = Start-ReadinessStep -Name $checkName
    $manifestPath = Join-Path $RepoRoot ("adapters\external\" + $name + ".yaml")
    $content = if (Test-Path -LiteralPath $manifestPath) { Get-Content -LiteralPath $manifestPath -Raw -Encoding UTF8 } else { "" }
    $baselineOk = ($content -match '(?m)^pinned_ref:\s*[0-9a-f]{40}\s*$') -and
        ($content -match '(?m)^last_audited_ref:\s*[0-9a-f]{40}\s*$') -and
        ($content -notmatch 'manual-audit-required')
    $durationMs = Complete-ReadinessStep -Name $checkName -Ok $baselineOk -Timer $timer
    Add-ReadinessCheck -Name $checkName -Ok $baselineOk -Summary $manifestPath -DurationMs $durationMs
}


$timer = Start-ReadinessStep -Name "hook_source_hash"
$hookNames = @("forge-pretool-guard.ps1", "forge-session-audit.ps1", "forge-hook-common.psm1")
$hookDetails = @()
$hookHashOk = $true
foreach ($hookName in $hookNames) {
    $sourceHook = Join-Path $RepoRoot ("hooks\" + $hookName)
    $fixtureHook = Join-Path $RepoRoot (".claude\hooks\" + $hookName)
    $sourceHash = if (Test-Path -LiteralPath $sourceHook) { (Get-FileHash -LiteralPath $sourceHook -Algorithm SHA256).Hash.ToLowerInvariant() } else { $null }
    $fixtureHash = if (Test-Path -LiteralPath $fixtureHook) { (Get-FileHash -LiteralPath $fixtureHook -Algorithm SHA256).Hash.ToLowerInvariant() } else { $null }
    $matches = ($sourceHash -and $fixtureHash -and $sourceHash -eq $fixtureHash)
    if (-not $matches) { $hookHashOk = $false }
    $hookDetails += [ordered]@{ name=$hookName; source_exists=[bool]$sourceHash; fixture_exists=[bool]$fixtureHash; matches_source=[bool]$matches }
}
$durationMs = Complete-ReadinessStep -Name "hook_source_hash" -Ok $hookHashOk -Timer $timer
Add-ReadinessCheck -Name "hook_source_hash" -Ok $hookHashOk -Summary "hooks/ vs .claude/hooks fixture hashes" -Details @($hookDetails) -DurationMs $durationMs

$timer = Start-ReadinessStep -Name "quick_health"
$healthMode = if ($Full) { "Quick" } else { "Lite" }
$health = Invoke-ProcessJson -Arguments @("-NoLogo", "-NoProfile", "-ExecutionPolicy", "Bypass", "-File", (Join-Path $ScriptDir "Invoke-ForgeHealth.ps1"), "-Mode", $healthMode, "-RepoPath", $RepoRoot, "-Json") -TimeoutSeconds 90
$healthOk = ($health.exit_code -eq 0 -and $health.json -and [bool]$health.json.ok)
$warningCount = if ($health.json -and $health.json.ContainsKey("warnings")) { @($health.json.warnings).Count } else { 0 }
$durationMs = Complete-ReadinessStep -Name "quick_health" -Ok $healthOk -Timer $timer
Add-ReadinessCheck -Name "quick_health" -Ok $healthOk -Summary "mode=$healthMode warnings=$warningCount" -Details $health.json -DurationMs $durationMs

if (-not $SkipSmoke) {
    $timer = Start-ReadinessStep -Name "smoke"
    $smokeArgs = @("-NoLogo", "-NoProfile", "-ExecutionPolicy", "Bypass", "-File", (Join-Path $ScriptDir "forge-smoke.ps1"), "-NoLog", "-SkipReleaseReadiness")
    if (-not $Full) { $smokeArgs += @("-Quick", "-Minimal", "-NoExternalRefCompare") }
    $smoke = Invoke-ProcessJson -Arguments $smokeArgs -TimeoutSeconds 120
    $smokeOk = ($smoke.exit_code -eq 0)
    $durationMs = Complete-ReadinessStep -Name "smoke" -Ok $smokeOk -Timer $timer
    $smokeSummaryLines = @(
        $smoke.output -split "`r?`n" | Where-Object {
            $_ -match '^forge_smoke_mode=' -or
            $_ -match '^(adapter_kernel_smoke|hook_gate|m1_gate|highrisk_gate|l4_downgrade_gate|adapter_contract|docs_health|release_readiness)_(passed|failed|skipped)='
        }
    )
    Add-ReadinessCheck -Name "smoke" -Ok $smokeOk -Summary (($smokeSummaryLines | Select-Object -First 16) -join "; ") -Details $smoke.output -DurationMs $durationMs
} else {
    Write-ReadinessProgress -Message "skip smoke"
    Add-ReadinessCheck -Name "smoke" -Ok $true -Severity "warning" -Summary "skipped" -DurationMs 0
}

$timer = Start-ReadinessStep -Name "diff_check"
$diffCheck = Invoke-Git -Arguments @("diff", "--check")
$diffSummary = if ($diffCheck.exit_code -eq 0) { "" } else { $diffCheck.output }
$diffOk = ($diffCheck.exit_code -eq 0)
$durationMs = Complete-ReadinessStep -Name "diff_check" -Ok $diffOk -Timer $timer
Add-ReadinessCheck -Name "diff_check" -Ok $diffOk -Summary $diffSummary -Details $diffCheck.output -DurationMs $durationMs

$timer = Start-ReadinessStep -Name "worktree_status"
$status = Invoke-Git -Arguments @("status", "--porcelain=v1")
$statusOk = ($status.exit_code -eq 0 -and [string]::IsNullOrWhiteSpace($status.output))
$durationMs = Complete-ReadinessStep -Name "worktree_status" -Ok $statusOk -Severity "warning" -Timer $timer
$statusSummary = ""
if (-not $statusOk) {
    $changedFiles = @($status.output -split "`r?`n" | Where-Object { -not [string]::IsNullOrWhiteSpace($_) } | ForEach-Object { $_.Substring([Math]::Min(3, $_.Length)).Trim() } | Select-Object -First 8)
    $statusSummary = "uncommitted changes in forge source repo"
    if ($changedFiles.Count -gt 0) { $statusSummary += ": " + ($changedFiles -join ", ") }
}
Add-ReadinessCheck -Name "worktree_status" -Ok $statusOk -Severity "warning" -Summary $statusSummary -Details $status.output -DurationMs $durationMs

if (-not [string]::IsNullOrWhiteSpace($PrNumber)) {
    $timer = Start-ReadinessStep -Name "pr_checks_present"
    $prOutput = & gh pr view $PrNumber --json number,state,isDraft,mergeStateStatus,statusCheckRollup,reviewDecision 2>&1
    $prExit = $LASTEXITCODE
    $pr = $null
    try { $pr = $prOutput | ConvertFrom-Json -AsHashtable } catch {}
    $checksCount = if ($pr -and $pr.ContainsKey("statusCheckRollup")) { @($pr.statusCheckRollup).Count } else { 0 }
    $checksOk = $prExit -eq 0 -and $pr -and ($checksCount -gt 0 -or $AllowMissingPrChecks)
    $checksSummary = if ($AllowMissingPrChecks -and $checksCount -eq 0) { "status_checks=0 allow_missing=true" } else { "status_checks=$checksCount" }
    $durationMs = Complete-ReadinessStep -Name "pr_checks_present" -Ok $checksOk -Severity "warning" -Timer $timer
    Add-ReadinessCheck -Name "pr_checks_present" -Ok $checksOk -Severity "warning" -Summary $checksSummary -Details $pr -DurationMs $durationMs
    $timer = Start-ReadinessStep -Name "pr_merge_state"
    $prClean = $prExit -eq 0 -and $pr -and [string]$pr.state -eq "OPEN" -and [string]$pr.mergeStateStatus -eq "CLEAN"
    $durationMs = Complete-ReadinessStep -Name "pr_merge_state" -Ok $prClean -Timer $timer
    Add-ReadinessCheck -Name "pr_merge_state" -Ok $prClean -Summary "state=$($pr.state) merge=$($pr.mergeStateStatus)" -Details $pr -DurationMs $durationMs
}

$errors = @($checks | Where-Object { -not $_.ok -and $_.severity -eq "error" })
$warnings = @($checks | Where-Object { -not $_.ok -and $_.severity -eq "warning" })
$strictWarningsFail = [bool]($Strict -or $Full)
$result = [ordered]@{
    ok = ($errors.Count -eq 0 -and (-not $strictWarningsFail -or $warnings.Count -eq 0))
    repo = $RepoRoot
    checked_at = (Get-Date).ToString("o")
    checks = @($checks)
    failed = @($errors | ForEach-Object { $_.name })
    warnings = @($warnings | ForEach-Object { $_.name })
    strict_warnings_fail = $strictWarningsFail
}

if ($Json) {
    $result | ConvertTo-Json -Depth 12
} else {
    if ($result.ok) { "Forge release readiness: PASS" } else { "Forge release readiness: FAIL" }
    "Repo: $RepoRoot"
    "Checked: $($result.checked_at)"
    "Summary: checks=$(@($checks).Count) failed=$(@($result.failed).Count) warnings=$(@($result.warnings).Count)"
    ""
    "Checks:"
    foreach ($check in $checks) {
        $label = if ($check.ok) { "PASS" } elseif ($check.severity -eq "warning") { "WARN" } else { "FAIL" }
        $line = "- $($check.name): $label"
        if (-not [string]::IsNullOrWhiteSpace($check.summary)) { $line += " -- $($check.summary)" }
        $line
    }
    $actionable = @($checks | Where-Object { -not $_.ok })
    if ($actionable.Count -gt 0) {
        ""
        "Next:"
        foreach ($check in $actionable) {
            "- $($check.name): $(Get-ReadinessFixHint -Name $check.name)"
        }
    }
}

if (-not $result.ok) { exit 1 }
