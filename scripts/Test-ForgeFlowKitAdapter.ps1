param(
    [string]$RepoPath = ".",
    [ValidateSet("Audit", "Staging", "Apply")]
    [string]$Mode = "Audit",
    [string]$TargetRef = "",
    [switch]$Json
)

$ErrorActionPreference = "Stop"

function Resolve-RepoRoot {
    param([string]$Path)
    $resolved = (Resolve-Path $Path).Path
    if (Test-Path -LiteralPath (Join-Path $resolved "flow-kit\GO.md")) {
        return $resolved
    }
    try {
        $gitRoot = git -C $Path rev-parse --show-toplevel 2>$null
        if ($LASTEXITCODE -eq 0 -and $gitRoot) { return (Resolve-Path $gitRoot).Path }
    } catch {}
    return $resolved
}

function Add-Issue {
    param([System.Collections.Generic.List[string]]$Issues, [string]$Code)
    if (-not $Issues.Contains($Code)) { [void]$Issues.Add($Code) }
}

function Test-RelativePath {
    param([string]$Root, [string]$RelativePath)
    return (Test-Path -LiteralPath (Join-Path $Root $RelativePath))
}

$repoRoot = Resolve-RepoRoot -Path $RepoPath
$issues = [System.Collections.Generic.List[string]]::new()

$stagePrompts = @(
    "flow-kit\prompts\0-change.md",
    "flow-kit\prompts\1-requirement.md",
    "flow-kit\prompts\2-design.md",
    "flow-kit\prompts\2a-ui-design.md",
    "flow-kit\prompts\3-task.md",
    "flow-kit\prompts\4-dev.md",
    "flow-kit\prompts\5-test.md",
    "flow-kit\prompts\6-review.md",
    "flow-kit\prompts\7-integration.md"
)

$templates = @(
    "flow-kit\templates\TASK.md",
    "flow-kit\templates\STATE.md",
    "flow-kit\templates\LESSONS.md"
)

$required = @("flow-kit\GO.md") + $stagePrompts + $templates
$detected = Test-RelativePath $repoRoot "flow-kit\GO.md"
$missing = @()

if ($detected) {
    foreach ($rel in $required) {
        if (-not (Test-RelativePath $repoRoot $rel)) {
            $missing += $rel
            Add-Issue $issues ("flowkit_missing_" + ($rel -replace '[^A-Za-z0-9]+', '_').Trim('_').ToLowerInvariant())
        }
    }
}

$stageMapping = @(
    [ordered]@{ stage = "0-change"; route = "scope" },
    [ordered]@{ stage = "1-requirement"; route = "requirement" },
    [ordered]@{ stage = "2-design"; route = "design" },
    [ordered]@{ stage = "2a-ui-design"; route = "ui-design" },
    [ordered]@{ stage = "3-task"; route = "planning" },
    [ordered]@{ stage = "4-dev"; route = "implementation" },
    [ordered]@{ stage = "5-test"; route = "verification" },
    [ordered]@{ stage = "6-review"; route = "review" },
    [ordered]@{ stage = "7-integration"; route = "integration" }
)

$status = "inactive"
if ($detected -and $issues.Count -eq 0) { $status = "compatible" }
elseif ($detected) { $status = "mapping_update_required" }

$result = [ordered]@{
    ok = ($issues.Count -eq 0)
    adapter = "flow-kit"
    mode = $Mode
    target_ref = $TargetRef
    repo_root = $repoRoot
    detected = [bool]$detected
    status = $status
    required_paths = @($required)
    missing_paths = @($missing)
    stage_mapping = @($stageMapping)
    issues = @($issues)
}

if ($Json) {
    $result | ConvertTo-Json -Depth 12
} else {
    if ($result.ok) { Write-Output "forge_flowkit_adapter=ok" } else { Write-Output "forge_flowkit_adapter=fail" }
    Write-Output "status=$($result.status)"
    Write-Output "detected=$($result.detected)"
    foreach ($issue in $issues) { Write-Output "issue=$issue" }
}

if (-not $result.ok) { exit 1 }
exit 0
