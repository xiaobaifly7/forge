param(
    [string]$RepoPath = ".",
    [string]$SessionId = "",
    [ValidateSet("", "change", "requirement", "design", "ui-design", "task", "dev", "test", "review", "integration", "0-change", "1-requirement", "2-design", "2a-ui-design", "3-task", "4-dev", "5-test", "6-review", "7-integration")]
    [string]$Stage = "",
    [switch]$Json
)

$ErrorActionPreference = "Stop"

function Resolve-RepoRoot {
    param([string]$Path)
    $resolved = (Resolve-Path $Path).Path
    if (Test-Path -LiteralPath (Join-Path $resolved ".forge")) { return $resolved }
    try {
        $gitRoot = git -C $Path rev-parse --show-toplevel 2>$null
        if ($LASTEXITCODE -eq 0 -and $gitRoot) { return (Resolve-Path $gitRoot).Path }
    } catch {}
    return $resolved
}

function Convert-StageAlias {
    param([string]$Value)
    switch ($Value) {
        "0-change" { return "change" }
        "1-requirement" { return "requirement" }
        "2-design" { return "design" }
        "2a-ui-design" { return "ui-design" }
        "3-task" { return "task" }
        "4-dev" { return "dev" }
        "5-test" { return "test" }
        "6-review" { return "review" }
        "7-integration" { return "integration" }
        default { return $Value }
    }
}

function Get-RouteForStage {
    param([string]$Value)
    switch ($Value) {
        "change" { return "scope" }
        "requirement" { return "requirement" }
        "design" { return "design" }
        "ui-design" { return "ui-design" }
        "task" { return "planning" }
        "dev" { return "implementation" }
        "test" { return "verification" }
        "review" { return "review" }
        "integration" { return "integration" }
        default { return "unknown" }
    }
}

function Read-JsonFile {
    param([string]$Path)
    if (-not (Test-Path -LiteralPath $Path)) { return $null }
    return Get-Content -Raw -LiteralPath $Path -Encoding UTF8 | ConvertFrom-Json
}

$repoRoot = Resolve-RepoRoot -Path $RepoPath
$source = "none"
$taskPath = ""
$resolvedStage = ""
$sessionPath = ""

if (-not [string]::IsNullOrWhiteSpace($Stage)) {
    $resolvedStage = Convert-StageAlias $Stage
    $source = "explicit"
}

if ([string]::IsNullOrWhiteSpace($resolvedStage) -and -not [string]::IsNullOrWhiteSpace($SessionId)) {
    $safeSessionId = $SessionId -replace '[^A-Za-z0-9_.-]', '_'
    $sessionPath = Join-Path $repoRoot (".forge\.runtime\sessions\" + $safeSessionId + ".json")
    $session = Read-JsonFile -Path $sessionPath
    if ($session) {
        if ($session.PSObject.Properties.Name -contains "stage") {
            $resolvedStage = Convert-StageAlias ([string]$session.stage)
            $source = "session"
        }
        if ($session.PSObject.Properties.Name -contains "task") {
            $taskPath = [string]$session.task
        }
    }
}

if ([string]::IsNullOrWhiteSpace($resolvedStage) -and -not [string]::IsNullOrWhiteSpace($taskPath)) {
    $taskJson = Join-Path $repoRoot (Join-Path $taskPath "task.json")
    $task = Read-JsonFile -Path $taskJson
    if ($task -and ($task.PSObject.Properties.Name -contains "stage")) {
        $resolvedStage = Convert-StageAlias ([string]$task.stage)
        $source = "task"
    }
}

$route = Get-RouteForStage $resolvedStage
$ok = (-not [string]::IsNullOrWhiteSpace($resolvedStage) -and $route -ne "unknown")
$issues = @()
if (-not $ok) { $issues = @("stage_unresolved") }
$result = [ordered]@{
    ok = $ok
    repo_root = $repoRoot
    session_id = $SessionId
    session_path = $sessionPath
    task_path = $taskPath
    source = $source
    stage = $resolvedStage
    route = $route
    issues = @($issues)
}

if ($Json) {
    $result | ConvertTo-Json -Depth 8
} else {
    if ($result.ok) { Write-Output "forge_stage=ok" } else { Write-Output "forge_stage=fail" }
    Write-Output "stage=$($result.stage)"
    Write-Output "route=$($result.route)"
    Write-Output "source=$($result.source)"
    foreach ($issue in $result.issues) { Write-Output "issue=$issue" }
}

if (-not $result.ok) { exit 1 }
exit 0
