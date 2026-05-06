param(
    [string]$RepoPath = ".",
    [ValidateSet("1A", "1B", "1C", "2", "3", "4")]
    [string]$Phase = "1A",
    [switch]$QuestionPending,
    [string]$ArtifactPath = "",
    [string]$SessionId = "",
    [int]$ExpiresHours = 24
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

$repoRoot = Resolve-RepoRoot -Path $RepoPath
$claudeDir = Join-Path $repoRoot ".claude"
$artifactDir = Join-Path $claudeDir "forge\artifacts"
New-Item -ItemType Directory -Force -Path $artifactDir | Out-Null

if ([string]::IsNullOrWhiteSpace($SessionId)) {
    $SessionId = [guid]::NewGuid().ToString()
}

$now = Get-Date
$statePath = Join-Path $claudeDir "forge-session-state.json"
$marker = if ($Phase -eq "1A") { "[PIPELINE] 阶段 1A 开始 → brainstorming/research" } else { "[PIPELINE] 阶段 $Phase 开始" }
$state = [ordered]@{
    schema_version = 1
    mode = "full"
    execution = "guided-full"
    phase = $Phase
    question_pending = [bool]$QuestionPending
    user_confirmed_next_phase = $false
    artifact_path = $ArtifactPath
    session_id = $SessionId
    owner = "claude-code"
    created_at = $now.ToString("o")
    updated_at = $now.ToString("o")
    expires_at = $now.AddHours($ExpiresHours).ToString("o")
    last_pipeline_marker = $marker
}
$state | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $statePath -Encoding UTF8

$lockPath = Join-Path $claudeDir "forge-session.lock.json"
$lock = [ordered]@{
    schema_version = 1
    session_id = $SessionId
    owner = "claude-code"
    phase = $Phase
    created_at = $state.created_at
    updated_at = $state.updated_at
    expires_at = $state.expires_at
}
$lock | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $lockPath -Encoding UTF8

Write-Output "forge_guided_full_state=$statePath"
Write-Output "forge_session_lock=$lockPath"
Write-Output "forge_artifact_dir=$artifactDir"
Write-Output "forge_session_id=$SessionId"
