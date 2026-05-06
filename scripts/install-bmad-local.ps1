param(
    [string]$RepoPath = ".",
    [ValidateSet("install", "update", "quick-update")]
    [string]$Action = "install",
    [switch]$SkipProfileInit,
    [switch]$RefreshProjectClaude,
    [string]$BmadVersion = "6.3.0",
    [string]$PythonPath = ""
)

$ErrorActionPreference = "Stop"

function Resolve-RepoRoot {
    param([string]$Path)

    try {
        $gitRoot = git -C $Path rev-parse --show-toplevel 2>$null
        if ($LASTEXITCODE -eq 0 -and $gitRoot) {
            return (Resolve-Path $gitRoot).Path
        }
    } catch {
    }

    return (Resolve-Path $Path).Path
}

function Format-Bool {
    param([bool]$Value)
    if ($Value) { return "true" }
    return "false"
}

$repoRoot = Resolve-RepoRoot -Path $RepoPath
if ([string]::IsNullOrWhiteSpace($BmadVersion)) {
    $BmadVersion = "6.3.0"
}
$bmadPackage = "bmad-method@$BmadVersion"

$env:PY_PYTHON = "3.11"
if (-not [string]::IsNullOrWhiteSpace($PythonPath)) {
    $env:PYTHON = $PythonPath
    $env:UV_PYTHON = $PythonPath
}

$args = @(
    "-y",
    $bmadPackage,
    "install",
    "--directory", $repoRoot,
    "--tools", "claude-code",
    "--action", $Action,
    "--communication-language", "Chinese",
    "--document-output-language", "Chinese",
    "--yes"
)

& npx @args
if ($LASTEXITCODE -ne 0) {
    throw "BMAD local install failed with exit code $LASTEXITCODE"
}

if (-not $SkipProfileInit) {
    $profileArgs = @(
        "-NoLogo",
        "-NoProfile",
        "-ExecutionPolicy", "Bypass",
        "-File", (Join-Path $PSScriptRoot "init-project-profile.ps1"),
        "-RepoPath", $repoRoot
    )
    if ($RefreshProjectClaude) {
        $profileArgs += "-RefreshProjectClaude"
    }
    & pwsh @profileArgs
    if ($LASTEXITCODE -ne 0) {
        throw "Project profile initialization failed with exit code $LASTEXITCODE"
    }
}

$bmadRoot = Join-Path $repoRoot "_bmad"
$bmadSkillsRoot = Join-Path $repoRoot ".claude\skills"
$profilePath = Join-Path $repoRoot ".claude\project-profile.json"
$policyPath = Join-Path $repoRoot ".claude\workflow-policy.md"
$bmadLockPath = Join-Path (Join-Path $repoRoot ".claude") "bmad-version.lock"
New-Item -ItemType Directory -Force -Path (Split-Path -Parent $bmadLockPath) | Out-Null
$bmadLock = [ordered]@{
    package = "bmad-method"
    version = $BmadVersion
    resolved_package = $bmadPackage
    action = $Action
    installed_at = (Get-Date).ToString("o")
    repo_root = $repoRoot
}
$bmadLock | ConvertTo-Json -Depth 4 | Set-Content -Path $bmadLockPath -Encoding utf8

$preferSubagents = $false
$executionPreference = "best_path_first"
$requiredSidecar = "when_parallelizable"
if (Test-Path $profilePath) {
    try {
        $profile = Get-Content -Raw $profilePath | ConvertFrom-Json -AsHashTable
        if ($profile.ContainsKey("prefer_subagents")) {
            $preferSubagents = [bool]$profile["prefer_subagents"]
        }
        if ($profile.ContainsKey("execution_preference")) {
            $executionConfig = $profile["execution_preference"]
            if ($executionConfig -and $executionConfig.ContainsKey("default_execution")) {
                $executionPreference = [string]$executionConfig["default_execution"]
            }
            if ($executionConfig -and $executionConfig.ContainsKey("sidecar_scope")) {
                $requiredSidecar = [string]$executionConfig["sidecar_scope"]
            }
        }
    } catch {
    }
}

$skillCount = 0
if (Test-Path $bmadSkillsRoot) {
    $skillCount = @(
        Get-ChildItem -Path $bmadSkillsRoot -Directory -ErrorAction SilentlyContinue |
        Where-Object { $_.Name -like "bmad-*" }
    ).Count
}

Write-Output "repo_root=$repoRoot"
Write-Output "bmad_root=$bmadRoot"
Write-Output "bmad_skills=$skillCount"
Write-Output "profile=$profilePath"
Write-Output "policy=$policyPath"
Write-Output "bmad_lock=$bmadLockPath"
Write-Output "bmad_package=$bmadPackage"
Write-Output "project_claude=$(Join-Path $repoRoot 'CLAUDE.md')"
Write-Output "prefer_subagents=$(Format-Bool $preferSubagents)"
Write-Output "execution_preference=$executionPreference"
Write-Output "required_sidecar=$requiredSidecar"

