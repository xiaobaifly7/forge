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
    if (Test-Path -LiteralPath (Join-Path $resolved ".trellis")) {
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

function Test-JsonlReferences {
    param(
        [string]$RepoRoot,
        [string]$TaskDir,
        [string]$FileName,
        [System.Collections.Generic.List[string]]$Issues
    )

    $path = Join-Path $TaskDir $FileName
    if (-not (Test-Path -LiteralPath $path)) { return @() }

    $missing = @()
    $lineNumber = 0
    foreach ($line in Get-Content -LiteralPath $path -Encoding UTF8) {
        $lineNumber += 1
        if ([string]::IsNullOrWhiteSpace($line)) { continue }
        try {
            $entry = $line | ConvertFrom-Json
        } catch {
            Add-Issue $Issues ("trellis_invalid_jsonl_" + $FileName.Replace(".", "_") + "_line_$lineNumber")
            continue
        }
        if ($entry.PSObject.Properties.Name -contains "_example") { continue }
        if (-not ($entry.PSObject.Properties.Name -contains "file")) { continue }
        $rel = [string]$entry.file
        if ([string]::IsNullOrWhiteSpace($rel)) { continue }
        if (-not (Test-Path -LiteralPath (Join-Path $RepoRoot $rel))) {
            $missing += $rel
            Add-Issue $Issues ("trellis_missing_context_" + ($rel -replace '[^A-Za-z0-9]+', '_').Trim('_').ToLowerInvariant())
        }
    }
    return @($missing)
}

$repoRoot = Resolve-RepoRoot -Path $RepoPath
$issues = [System.Collections.Generic.List[string]]::new()

$required = @(
    ".trellis\workflow.md",
    ".trellis\config.yaml",
    ".trellis\spec",
    ".trellis\tasks",
    ".trellis\workspace"
)

$detected = Test-RelativePath $repoRoot ".trellis"
$missing = @()
$tasks = @()
$missingContext = @()

if ($detected) {
    foreach ($rel in $required) {
        if (-not (Test-RelativePath $repoRoot $rel)) {
            $missing += $rel
            Add-Issue $issues ("trellis_missing_" + ($rel -replace '[^A-Za-z0-9]+', '_').Trim('_').ToLowerInvariant())
        }
    }

    $tasksRoot = Join-Path $repoRoot ".trellis\tasks"
    if (Test-Path -LiteralPath $tasksRoot) {
        foreach ($taskDir in Get-ChildItem -LiteralPath $tasksRoot -Directory) {
            if ($taskDir.Name -eq "archive") { continue }
            $taskMissing = @()
            foreach ($file in @("task.json", "prd.md", "implement.jsonl", "check.jsonl")) {
                if (-not (Test-Path -LiteralPath (Join-Path $taskDir.FullName $file))) {
                    $taskMissing += $file
                    Add-Issue $issues ("trellis_task_missing_" + $taskDir.Name + "_" + $file.Replace(".", "_"))
                }
            }
            $missingContext += Test-JsonlReferences -RepoRoot $repoRoot -TaskDir $taskDir.FullName -FileName "implement.jsonl" -Issues $issues
            $missingContext += Test-JsonlReferences -RepoRoot $repoRoot -TaskDir $taskDir.FullName -FileName "check.jsonl" -Issues $issues
            $tasks += [ordered]@{
                name = $taskDir.Name
                path = $taskDir.FullName
                missing_files = @($taskMissing)
            }
        }
    }
}

$runtimePresent = Test-RelativePath $repoRoot ".trellis\.runtime\sessions"
$status = "inactive"
if ($detected -and $issues.Count -eq 0) { $status = "compatible" }
elseif ($detected) { $status = "mapping_update_required" }

$result = [ordered]@{
    ok = ($issues.Count -eq 0)
    adapter = "trellis"
    mode = $Mode
    target_ref = $TargetRef
    repo_root = $repoRoot
    detected = [bool]$detected
    status = $status
    runtime_sessions_present = [bool]$runtimePresent
    required_paths = @($required)
    missing_paths = @($missing)
    tasks = @($tasks)
    missing_context = @($missingContext)
    issues = @($issues)
}

if ($Json) {
    $result | ConvertTo-Json -Depth 12
} else {
    if ($result.ok) { Write-Output "forge_trellis_adapter=ok" } else { Write-Output "forge_trellis_adapter=fail" }
    Write-Output "status=$($result.status)"
    Write-Output "detected=$($result.detected)"
    foreach ($issue in $issues) { Write-Output "issue=$issue" }
}

if (-not $result.ok) { exit 1 }
exit 0
