[CmdletBinding()]
param(
    [string]$RepoPath = ".",
    [string]$Title = "",
    [ValidateSet('quick','build','fix','full','ship','full-auto')][string]$Mode = 'quick',
    [switch]$Json
)

$ErrorActionPreference = "Stop"
$ScriptDir = Split-Path -Parent $PSCommandPath
$Repo = (Resolve-Path -LiteralPath $RepoPath).Path

function Invoke-GitLines {
    param([string[]]$Arguments)
    try {
        return @(& git -C $Repo @Arguments 2>$null | ForEach-Object { [string]$_ })
    } catch {
        return @()
    }
}

$status = @(Invoke-GitLines -Arguments @('status','--short'))
$numstat = @(Invoke-GitLines -Arguments @('diff','--numstat'))
$stagedNumstat = @(Invoke-GitLines -Arguments @('diff','--cached','--numstat'))
$nameOnly = @(Invoke-GitLines -Arguments @('diff','--name-only'))
$stagedNameOnly = @(Invoke-GitLines -Arguments @('diff','--cached','--name-only'))
$changedFiles = @($nameOnly + $stagedNameOnly | Where-Object { $_ } | Select-Object -Unique)
$hasDiff = ($status.Count -gt 0 -or $changedFiles.Count -gt 0)

$prompt = if ([string]::IsNullOrWhiteSpace($Title)) {
    "Review current changes in $Repo"
} else {
    $Title
}

$planJson = & pwsh -NoLogo -NoProfile -ExecutionPolicy Bypass -File (Join-Path $ScriptDir 'Resolve-ForgeReviewPlan.ps1') -RepoPath $Repo -Prompt $prompt -Mode $Mode -Json
$plan = $planJson | ConvertFrom-Json

$reviewPrompt = [ordered]@{
    title = $prompt
    repo = $Repo
    mode = $Mode
    level = $plan.level
    high_risk = $plan.high_risk
    has_diff = $hasDiff
    status = $status
    unstaged_numstat = $numstat
    staged_numstat = $stagedNumstat
    changed_files = $changedFiles
    instructions = @(
        'Review current repository changes.',
        'Prioritize correctness, security, data integrity, test gaps, and regression risk.',
        'Return blocking issues first. If no blockers, say so explicitly.',
        'Use Forge level and steps as the review contract.'
    )
    forge_steps = $plan.steps
}

$result = [ordered]@{
    ok = $true
    repo = $Repo
    has_diff = $hasDiff
    changed_file_count = $changedFiles.Count
    mode = $Mode
    level = $plan.level
    high_risk = $plan.high_risk
    review_prompt = ($reviewPrompt | ConvertTo-Json -Depth 8)
    plan = $plan
}

if ($Json) {
    $result | ConvertTo-Json -Depth 10
    exit 0
}

Write-Output "Forge review-current"
Write-Output "Repo: $Repo"
Write-Output "Diff: has_diff=$hasDiff changed_files=$($changedFiles.Count)"
Write-Output "Route: level=$($plan.level) mode=$Mode high_risk=$($plan.high_risk)"
Write-Output "Steps: $(@($plan.steps | ForEach-Object { $_.name }) -join ', ')"
Write-Output ""
Write-Output "--- review prompt ---"
Write-Output $result.review_prompt
