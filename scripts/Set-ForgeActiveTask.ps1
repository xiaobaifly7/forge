param(
    [string]$RepoPath = ".",
    [Parameter(Mandatory = $true)][string]$SessionId,
    [Parameter(Mandatory = $true)][string]$TaskPath,
    [ValidateSet("change", "requirement", "design", "ui-design", "task", "dev", "test", "review", "integration")]
    [string]$Stage = "task",
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

function ConvertTo-ForgeRelativePath {
    param(
        [string]$RepoRoot,
        [string]$RelativePath,
        [string]$Label = "Path"
    )
    $normalized = $RelativePath -replace '/', '\'
    $candidate = if ([System.IO.Path]::IsPathRooted($normalized)) {
        [System.IO.Path]::GetFullPath($normalized)
    } else {
        [System.IO.Path]::GetFullPath((Join-Path $RepoRoot $normalized))
    }
    $forgeRoot = [System.IO.Path]::GetFullPath((Join-Path $RepoRoot ".forge")).TrimEnd('\', '/')
    $forgeRootPrefix = $forgeRoot + [System.IO.Path]::DirectorySeparatorChar
    if (-not $candidate.StartsWith($forgeRootPrefix, [System.StringComparison]::OrdinalIgnoreCase)) {
        throw "$Label must be under .forge\\: $RelativePath"
    }
    return ([System.IO.Path]::GetRelativePath($RepoRoot, $candidate) -replace '/', '\')
}

function ConvertTo-TaskRelativePath {
    param(
        [string]$RepoRoot,
        [string]$TaskPath
    )
    $relative = ConvertTo-ForgeRelativePath -RepoRoot $RepoRoot -RelativePath $TaskPath -Label "TaskPath"
    if ($relative -notmatch '^\.forge\\tasks\\') {
        throw "TaskPath must be under .forge\\tasks\\."
    }
    return $relative
}

$repoRoot = Resolve-RepoRoot -Path $RepoPath
$normalizedTaskPath = ConvertTo-TaskRelativePath -RepoRoot $repoRoot -TaskPath $TaskPath
$taskDir = Join-Path $repoRoot $normalizedTaskPath
if (-not (Test-Path -LiteralPath $taskDir)) {
    throw "TaskPath does not exist: $normalizedTaskPath"
}
if (-not (Test-Path -LiteralPath (Join-Path $taskDir "task.json"))) {
    throw "TaskPath missing task.json: $normalizedTaskPath"
}

$safeSessionId = $SessionId -replace '[^A-Za-z0-9_.-]', '_'
$sessionsDir = Join-Path $repoRoot ".forge\.runtime\sessions"
New-Item -ItemType Directory -Force -Path $sessionsDir | Out-Null
$sessionPath = Join-Path $sessionsDir ($safeSessionId + ".json")
$route = Get-RouteForStage $Stage

$payload = [ordered]@{
    task = $normalizedTaskPath
    stage = $Stage
    route = $route
    session_id = $safeSessionId
    updated_at = (Get-Date).ToString("o")
}

$payload | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $sessionPath -Encoding UTF8

$result = [ordered]@{
    ok = $true
    repo_root = $repoRoot
    session_id = $safeSessionId
    session_path = $sessionPath
    task_path = $normalizedTaskPath
    stage = $Stage
    route = $route
}

if ($Json) {
    $result | ConvertTo-Json -Depth 8
} else {
    Write-Output "forge_active_task=ok"
    Write-Output "session_path=$sessionPath"
    Write-Output "stage=$Stage"
    Write-Output "route=$route"
}

exit 0
