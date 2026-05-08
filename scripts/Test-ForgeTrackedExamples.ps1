param(
    [string]$RepoPath = ".",
    [switch]$Json
)

$ErrorActionPreference = "Stop"

function Resolve-RepoRoot {
    param([string]$Path)
    $resolved = (Resolve-Path -LiteralPath $Path).Path
    try {
        $gitRoot = git -C $resolved rev-parse --show-toplevel 2>$null
        if ($LASTEXITCODE -eq 0 -and $gitRoot) { return (Resolve-Path -LiteralPath $gitRoot).Path }
    } catch {}
    return $resolved
}

$repoRoot = Resolve-RepoRoot -Path $RepoPath
$required = @(
    "evals/forge-smoke.evals.json",
    "examples/trellis-project/.trellis/tasks/05-07-example-task/implement.jsonl",
    "examples/trellis-project/.trellis/tasks/05-07-example-task/check.jsonl",
    "examples/task-kernel-project/.forge/tasks/05-07-example-task/implement.jsonl",
    "examples/task-kernel-project/.forge/tasks/05-07-example-task/check.jsonl"
)

$tracked = @(git -C $repoRoot ls-files -- $required)
if ($LASTEXITCODE -ne 0) { throw "git ls-files failed" }
$trackedSet = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
foreach ($item in $tracked) {
    if (-not [string]::IsNullOrWhiteSpace($item)) { [void]$trackedSet.Add(($item -replace '\\', '/')) }
}

$missing = [System.Collections.Generic.List[string]]::new()
foreach ($path in $required) {
    if (-not $trackedSet.Contains($path)) { [void]$missing.Add($path) }
}

$result = [ordered]@{
    ok = ($missing.Count -eq 0)
    repo_root = $repoRoot
    required = @($required)
    missing = @($missing)
}

if ($Json) {
    $result | ConvertTo-Json -Depth 8
} else {
    if ($result.ok) { Write-Output "forge_tracked_examples=ok" } else { Write-Output "forge_tracked_examples=fail" }
    foreach ($path in $missing) { Write-Output "missing=$path" }
}

if (-not $result.ok) { exit 1 }
exit 0
