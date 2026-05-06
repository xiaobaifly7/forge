param(
    [string]$RepoPath = ".",
    [string]$CandidateText = "",
    [switch]$Json
)

$ErrorActionPreference = "Stop"

function Resolve-RepoRoot {
    param([string]$Path)
    try {
        $gitRoot = git -C $Path rev-parse --show-toplevel 2>$null
        if ($LASTEXITCODE -eq 0 -and $gitRoot) { return (Resolve-Path $gitRoot).Path }
    } catch {}
    return (Resolve-Path $Path).Path
}

function Add-Issue {
    param([System.Collections.Generic.List[string]]$Issues, [string]$Code)
    if (-not $Issues.Contains($Code)) { [void]$Issues.Add($Code) }
}

$repoRoot = Resolve-RepoRoot -Path $RepoPath
$statePath = Join-Path $repoRoot ".claude\forge-session-state.json"
$lockPath = Join-Path $repoRoot ".claude\forge-session.lock.json"
$issues = [System.Collections.Generic.List[string]]::new()
$state = $null
$lock = $null

if (-not (Test-Path -LiteralPath $statePath)) {
    Add-Issue $issues "missing_state_file"
} else {
    try {
        $state = Get-Content -Raw -LiteralPath $statePath -Encoding UTF8 | ConvertFrom-Json -AsHashtable
    } catch {
        Add-Issue $issues "invalid_state_json"
    }
}

if (Test-Path -LiteralPath $lockPath) {
    try {
        $lock = Get-Content -Raw -LiteralPath $lockPath -Encoding UTF8 | ConvertFrom-Json -AsHashtable
    } catch {
        Add-Issue $issues "invalid_lock_json"
    }
}

$phase = if ($state -and $state.ContainsKey("phase")) { [string]$state.phase } else { "" }
$execution = if ($state -and $state.ContainsKey("execution")) { [string]$state.execution } else { "" }
$schemaVersion = if ($state -and $state.ContainsKey("schema_version")) { [int]$state.schema_version } else { 0 }
$questionPending = if ($state -and $state.ContainsKey("question_pending")) { [bool]$state.question_pending } else { $false }
$userConfirmedNextPhase = if ($state -and $state.ContainsKey("user_confirmed_next_phase")) { [bool]$state.user_confirmed_next_phase } else { $false }
$artifactPath = if ($state -and $state.ContainsKey("artifact_path")) { [string]$state.artifact_path } else { "" }
$sessionId = if ($state -and $state.ContainsKey("session_id")) { [string]$state.session_id } else { "" }
$expiresAt = if ($state -and $state.ContainsKey("expires_at")) { [string]$state.expires_at } else { "" }
$isDrill = if ($state -and $state.ContainsKey("is_drill")) { [bool]$state.is_drill } else { $false }

if ($state) {
    if ($schemaVersion -lt 1) { Add-Issue $issues "missing_or_old_schema_version" }
    if ($execution -ne "guided-full") { Add-Issue $issues "not_guided_full_state" }
    if (-not $phase) { Add-Issue $issues "missing_phase" }
    if (-not $sessionId) { Add-Issue $issues "missing_session_id" }
    if (-not $expiresAt) {
        Add-Issue $issues "missing_expires_at"
    } else {
        try {
            if ([datetime]::Parse($expiresAt) -lt (Get-Date)) {
                if ($isDrill) {
                    Add-Issue $issues "drill_state_expired"
                } else {
                    Add-Issue $issues "state_expired"
                }
            }
        } catch {
            Add-Issue $issues "invalid_expires_at"
        }
    }
}

if ($state -and $lock) {
    $lockSessionId = if ($lock.ContainsKey("session_id")) { [string]$lock.session_id } else { "" }
    $lockPhase = if ($lock.ContainsKey("phase")) { [string]$lock.phase } else { "" }
    $lockExpiresAt = if ($lock.ContainsKey("expires_at")) { [string]$lock.expires_at } else { "" }
    if (-not $lockSessionId) { Add-Issue $issues "missing_lock_session_id" }
    if (-not $lockPhase) { Add-Issue $issues "missing_lock_phase" }
    if ($sessionId -and $lockSessionId -and $sessionId -ne $lockSessionId) { Add-Issue $issues "state_lock_session_mismatch" }
    if ($phase -and $lockPhase -and $phase -ne $lockPhase) { Add-Issue $issues "state_lock_phase_mismatch" }
    if (-not $lockExpiresAt) {
        Add-Issue $issues "missing_lock_expires_at"
    } else {
        try {
            if ([datetime]::Parse($lockExpiresAt) -lt (Get-Date)) { Add-Issue $issues "lock_expired" }
        } catch {
            Add-Issue $issues "invalid_lock_expires_at"
        }
    }
}

if ($CandidateText) {
    $questionCount = ([regex]::Matches($CandidateText, "[？?]")).Count
    if ($phase -eq "1A" -and $questionCount -gt 1) {
        Add-Issue $issues "phase_1a_multi_question"
    }
    if ($phase -eq "1A" -and $questionPending -and $CandidateText -match "进入\s*1B|架构|architecture|技术栈|数据库|部署|实现细节") {
        Add-Issue $issues "phase_1a_rush_to_architecture"
    }
    if ($CandidateText -notmatch "\[PIPELINE\]") {
        Add-Issue $issues "missing_pipeline_marker"
    }
    if ($phase -eq "1A" -and $CandidateText -match "阶段\s*1B|进入\s*1B|architecture|架构") {
        if (-not $userConfirmedNextPhase) { Add-Issue $issues "next_phase_without_user_confirmation" }
    }
    if ($phase -and $CandidateText -match "阶段\s*([0-9A-Z]+)\s*完成") {
        $candidatePhase = $Matches[1]
        if ($candidatePhase -ne $phase) { Add-Issue $issues "candidate_phase_mismatch_state" }
    }
    if ($phase -eq "1A" -and $CandidateText -match "阶段\s*1A\s*完成|1A\s*完成") {
        if (-not $artifactPath) {
            Add-Issue $issues "phase_1a_complete_without_artifact_path"
        } else {
            $resolvedArtifact = if ([System.IO.Path]::IsPathRooted($artifactPath)) { $artifactPath } else { Join-Path $repoRoot $artifactPath }
            if (-not (Test-Path -LiteralPath $resolvedArtifact)) {
                Add-Issue $issues "phase_1a_artifact_missing_on_disk"
            } else {
                try {
                    if ((Get-Item -LiteralPath $resolvedArtifact).Length -le 0) {
                        Add-Issue $issues "phase_1a_artifact_empty"
                    }
                } catch {
                    Add-Issue $issues "phase_1a_artifact_unreadable"
                }
            }
        }
    }
}

$result = [ordered]@{
    ok = ($issues.Count -eq 0)
    repo = $repoRoot
    state = $statePath
    lock = $lockPath
    schema_version = $schemaVersion
    phase = $phase
    execution = $execution
    question_pending = $questionPending
    user_confirmed_next_phase = $userConfirmedNextPhase
    artifact_path = $artifactPath
    session_id = $sessionId
    is_drill = $isDrill
    expires_at = $expiresAt
    issues = @($issues)
}

if ($Json) {
    $result | ConvertTo-Json -Depth 8
} else {
    if ($result.ok) {
        Write-Output "forge_guided_full_gate=ok"
    } else {
        Write-Output "forge_guided_full_gate=fail"
        foreach ($issue in $issues) { Write-Output "issue=$issue" }
    }
    Write-Output "state=$statePath"
}

if (-not $result.ok) { exit 1 }
exit 0
