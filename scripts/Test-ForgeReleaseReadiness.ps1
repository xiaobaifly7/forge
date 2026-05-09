[CmdletBinding()]
param(
    [string]$RepoPath = ".",
    [string]$PrNumber = "",
    [switch]$AllowMissingPrChecks,
    [switch]$SkipSmoke,
    [switch]$Json
)

$ErrorActionPreference = "Continue"
$ScriptDir = Split-Path -Parent $PSCommandPath
$RepoRoot = (Resolve-Path -LiteralPath $RepoPath).Path
$checks = @()

function Add-ReadinessCheck {
    param(
        [string]$Name,
        [bool]$Ok,
        [string]$Severity = "error",
        [string]$Summary = "",
        [object]$Details = $null
    )
    $script:checks += [ordered]@{
        name = $Name
        ok = $Ok
        severity = if ($Ok) { "pass" } else { $Severity }
        summary = $Summary
        details = $Details
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
        "smoke" { return "Run forge-smoke.ps1 -NoLog and fix the first failed smoke layer." }
        "diff_check" { return "Run git diff --check and remove whitespace/conflict-marker errors." }
        "worktree_status" { return "Commit, stash, or intentionally document the remaining worktree changes." }
        "pr_checks_present" { return "Wait for GitHub checks or rerun with -AllowMissingPrChecks only for local pre-push." }
        "pr_merge_state" { return "Resolve PR merge state before marking release ready." }
        default { return "Inspect check details and rerun readiness." }
    }
}

$manifests = @("flow-kit", "trellis")
foreach ($name in $manifests) {
    $manifestPath = Join-Path $RepoRoot ("adapters\external\" + $name + ".yaml")
    $content = if (Test-Path -LiteralPath $manifestPath) { Get-Content -LiteralPath $manifestPath -Raw -Encoding UTF8 } else { "" }
    $baselineOk = ($content -match '(?m)^pinned_ref:\s*[0-9a-f]{40}\s*$') -and
        ($content -match '(?m)^last_audited_ref:\s*[0-9a-f]{40}\s*$') -and
        ($content -notmatch 'manual-audit-required')
    Add-ReadinessCheck -Name "adapter_${name}_baseline" -Ok $baselineOk -Summary $manifestPath
}

$health = Invoke-ProcessJson -Arguments @("-NoLogo", "-NoProfile", "-ExecutionPolicy", "Bypass", "-File", (Join-Path $ScriptDir "Invoke-ForgeHealth.ps1"), "-Mode", "Quick", "-RepoPath", $RepoRoot, "-Json") -TimeoutSeconds 90
$healthOk = ($health.exit_code -eq 0 -and $health.json -and [bool]$health.json.ok)
$warningCount = if ($health.json -and $health.json.ContainsKey("warnings")) { @($health.json.warnings).Count } else { 0 }
Add-ReadinessCheck -Name "quick_health" -Ok $healthOk -Summary "warnings=$warningCount" -Details $health.json

if (-not $SkipSmoke) {
    $smoke = Invoke-ProcessJson -Arguments @("-NoLogo", "-NoProfile", "-ExecutionPolicy", "Bypass", "-File", (Join-Path $ScriptDir "forge-smoke.ps1"), "-NoLog") -TimeoutSeconds 120
    Add-ReadinessCheck -Name "smoke" -Ok ($smoke.exit_code -eq 0) -Summary (($smoke.output -split "`r?`n" | Where-Object { $_ -match '_failed=0$|_passed=' } | Select-Object -Last 8) -join "; ") -Details $smoke.output
} else {
    Add-ReadinessCheck -Name "smoke" -Ok $true -Severity "warning" -Summary "skipped"
}

$diffCheck = Invoke-Git -Arguments @("diff", "--check")
$diffSummary = if ($diffCheck.exit_code -eq 0) { "" } else { $diffCheck.output }
Add-ReadinessCheck -Name "diff_check" -Ok ($diffCheck.exit_code -eq 0) -Summary $diffSummary -Details $diffCheck.output

$status = Invoke-Git -Arguments @("status", "--porcelain=v1")
Add-ReadinessCheck -Name "worktree_status" -Ok ($status.exit_code -eq 0 -and [string]::IsNullOrWhiteSpace($status.output)) -Severity "warning" -Summary $status.output -Details $status.output

if (-not [string]::IsNullOrWhiteSpace($PrNumber)) {
    $prOutput = & gh pr view $PrNumber --json number,state,isDraft,mergeStateStatus,statusCheckRollup,reviewDecision 2>&1
    $prExit = $LASTEXITCODE
    $pr = $null
    try { $pr = $prOutput | ConvertFrom-Json -AsHashtable } catch {}
    $checksCount = if ($pr -and $pr.ContainsKey("statusCheckRollup")) { @($pr.statusCheckRollup).Count } else { 0 }
    $checksOk = $prExit -eq 0 -and $pr -and ($checksCount -gt 0 -or $AllowMissingPrChecks)
    $checksSummary = if ($AllowMissingPrChecks -and $checksCount -eq 0) { "status_checks=0 allow_missing=true" } else { "status_checks=$checksCount" }
    Add-ReadinessCheck -Name "pr_checks_present" -Ok $checksOk -Severity "warning" -Summary $checksSummary -Details $pr
    $prClean = $prExit -eq 0 -and $pr -and [string]$pr.state -eq "OPEN" -and [string]$pr.mergeStateStatus -eq "CLEAN"
    Add-ReadinessCheck -Name "pr_merge_state" -Ok $prClean -Summary "state=$($pr.state) merge=$($pr.mergeStateStatus)" -Details $pr
}

$errors = @($checks | Where-Object { -not $_.ok -and $_.severity -eq "error" })
$warnings = @($checks | Where-Object { -not $_.ok -and $_.severity -eq "warning" })
$result = [ordered]@{
    ok = ($errors.Count -eq 0)
    repo = $RepoRoot
    checked_at = (Get-Date).ToString("o")
    checks = @($checks)
    failed = @($errors | ForEach-Object { $_.name })
    warnings = @($warnings | ForEach-Object { $_.name })
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
