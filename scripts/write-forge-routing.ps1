param(
    [string]$RepoPath = ".",
    [Parameter(Mandatory=$true)][ValidateSet('quick','full','full-auto','build','fix','ship')][string]$Mode,
    [ValidateSet('L0','L1','L2','L3','L4')][string]$Level = 'L2',
    [ValidateSet('disabled','audit_only','local_routing','full')][string]$AdoptionMode = 'local_routing',
    [string]$Execution = "",
    [ValidateSet('low','medium','high')][string]$Risk = "medium",
    [ValidateSet('low','medium','high')][string]$Cost = "medium",
    [ValidateSet('none','single_file','module','cross_module','global')][string]$WriteScope = "none",
    [string[]]$Reason = @(),
    [string]$Prompt = "",
    [string]$PipelinePhase = "",
    [string]$TaskGroup = "",
    [string]$GroupStatus = "",
    [string]$TodoRef = "",
    [string]$TddRef = "",
    [string]$TestRef = "",
    [string]$HighRisk = "",
    [string]$VerificationRef = "",
    [string]$ArtifactRef = "",
    [string]$CommitSha = "",
    [string]$LearningsRef = "",
    [string]$NextPhase = "",
    [ValidateSet('','L0','L1','L2','L3','L4')][string]$ProjectLevel = "",
    [ValidateSet('','quick','build','fix','full','full-auto','ship')][string]$BatchProtocol = "",
    [string]$DowngradeReason = "",
    [string]$ParentPlanRef = "",
    [string]$WorkflowRefs = "",
    [switch]$GstackEnabled,
    [switch]$BmadLocal,
    [string]$InheritedFrom = "",
    [ValidateSet("","light","normal","heavy")][string]$ExecutionScope = "",
    [ValidateSet("","L0","L1","L2","L3","L4")][string]$ParentLevel = "",
    [string]$BmadRoot = "",
    [ValidateSet("","requirements","architecture","stories","acceptance","M1")][string]$BmadPhase = ""
)

$ErrorActionPreference = "Stop"
if ($GroupStatus -and $GroupStatus -notin @('started','completed','blocked','skipped')) {
    throw "Invalid GroupStatus '$GroupStatus'. Expected started, completed, blocked, or skipped."
}
$effectiveProjectLevel = if ([string]::IsNullOrWhiteSpace($ProjectLevel)) { $Level } else { $ProjectLevel }
$effectiveParentLevel = if ([string]::IsNullOrWhiteSpace($ParentLevel)) { $effectiveProjectLevel } else { $ParentLevel }
$effectiveBatchProtocol = $BatchProtocol
if ($effectiveParentLevel -eq 'L4') {
    if ($Level -ne 'L4' -or $effectiveProjectLevel -ne 'L4') {
        throw "ParentLevel=L4 routing must keep Level=L4 and ProjectLevel=L4. Use -ExecutionScope light instead of downgrading."
    }
    if ([string]::IsNullOrWhiteSpace($InheritedFrom)) {
        throw "ParentLevel=L4 routing requires -InheritedFrom."
    }
    if ([string]::IsNullOrWhiteSpace($ExecutionScope)) {
        throw "ParentLevel=L4 routing requires -ExecutionScope light|normal|heavy."
    }
}
if ($PipelinePhase -eq 'M1' -and $effectiveProjectLevel -eq 'L4') {
    if ([string]::IsNullOrWhiteSpace($effectiveBatchProtocol)) {
        throw "ProjectLevel=L4 M1 routing requires -BatchProtocol."
    }
    if ($effectiveBatchProtocol -notin @('full','full-auto','ship')) {
        if ([string]::IsNullOrWhiteSpace($DowngradeReason)) {
            throw "ProjectLevel=L4 with BatchProtocol=$effectiveBatchProtocol requires -DowngradeReason."
        }
        if ([string]::IsNullOrWhiteSpace($ParentPlanRef)) {
            throw "ProjectLevel=L4 with BatchProtocol=$effectiveBatchProtocol requires -ParentPlanRef."
        }
    }
}

function Resolve-RepoRoot {
    param([string]$Path)
    try {
        $gitRoot = git -C $Path rev-parse --show-toplevel 2>$null
        if ($LASTEXITCODE -eq 0 -and $gitRoot) { return (Resolve-Path $gitRoot).Path }
    } catch {}
    return (Resolve-Path $Path).Path
}

$repoRoot = Resolve-RepoRoot -Path $RepoPath
$localClaude = Join-Path $repoRoot ".claude"
New-Item -ItemType Directory -Force -Path $localClaude | Out-Null
$logPath = Join-Path $localClaude "forge-routing.jsonl"
$promptHash = ""
if ($Prompt) {
    $promptHash = [System.BitConverter]::ToString([System.Security.Cryptography.SHA256]::HashData([System.Text.Encoding]::UTF8.GetBytes($Prompt))).Replace('-', '').ToLowerInvariant()
}
$item = [ordered]@{
    time = (Get-Date).ToString("o")
    repo = $repoRoot
    level = $Level
    mode = $Mode
    execution = $Execution
    adoption_mode = $AdoptionMode
    risk = $Risk
    cost = $Cost
    write_scope = $WriteScope
    reason = @($Reason)
    pipeline_phase = $PipelinePhase
    task_group = $TaskGroup
    group_status = $GroupStatus
    todo_ref = $TodoRef
    tdd_ref = $TddRef
    test_ref = $TestRef
    high_risk = $HighRisk
    verification_ref = $VerificationRef
    artifact_ref = $ArtifactRef
    commit_sha = $CommitSha
    learnings_ref = $LearningsRef
    next_phase = $NextPhase
    project_level = $effectiveProjectLevel
    parent_level = $effectiveParentLevel
    inherited_from = $InheritedFrom
    execution_scope = $ExecutionScope
    bmad_root = $BmadRoot
    bmad_phase = $BmadPhase
    batch_protocol = $effectiveBatchProtocol
    downgrade_reason = $DowngradeReason
    parent_plan_ref = $ParentPlanRef
    workflow_refs = $WorkflowRefs
    profile = ".claude/project-profile.json"
    policy = ".claude/workflow-policy.md"
    bmad_local = [bool]$BmadLocal
    gstack_enabled = [bool]$GstackEnabled
    prompt_sha256 = $promptHash
}
$item | ConvertTo-Json -Depth 6 -Compress | Add-Content -LiteralPath $logPath -Encoding utf8
Write-Output "forge_routing_log=$logPath"

