param(
    [string]$RepoPath = ".",
    [switch]$Json
)

$ErrorActionPreference = "Stop"

function Resolve-RepoRoot {
    param([string]$Path)
    $resolved = (Resolve-Path $Path).Path
    if (Test-Path -LiteralPath (Join-Path $resolved ".forge")) {
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
            Add-Issue $Issues ("task_kernel_invalid_jsonl_" + $FileName.Replace(".", "_") + "_line_$lineNumber")
            continue
        }
        if (-not ($entry.PSObject.Properties.Name -contains "file")) { continue }
        $rel = [string]$entry.file
        if ([string]::IsNullOrWhiteSpace($rel)) { continue }
        if ($rel -notmatch '^\.forge[\\/]') {
            Add-Issue $Issues ("task_kernel_context_outside_forge_" + ($rel -replace '[^A-Za-z0-9]+', '_').Trim('_').ToLowerInvariant())
            continue
        }
        if (-not (Test-Path -LiteralPath (Join-Path $RepoRoot $rel))) {
            $missing += $rel
            Add-Issue $Issues ("task_kernel_missing_context_" + ($rel -replace '[^A-Za-z0-9]+', '_').Trim('_').ToLowerInvariant())
        }
    }
    return @($missing)
}

$repoRoot = Resolve-RepoRoot -Path $RepoPath
$issues = [System.Collections.Generic.List[string]]::new()

$requiredRootPaths = @(
    ".forge\tasks",
    ".forge\spec",
    ".forge\workspace"
)

$requiredSpecDirs = @(
    ".forge\spec\frontend",
    ".forge\spec\backend",
    ".forge\spec\security",
    ".forge\spec\testing",
    ".forge\spec\review",
    ".forge\spec\debugging",
    ".forge\spec\conventions",
    ".forge\spec\guides"
)

$detected = Test-RelativePath $repoRoot ".forge"
$missing = @()
$tasks = @()
$missingContext = @()

if ($detected) {
    foreach ($rel in ($requiredRootPaths + $requiredSpecDirs)) {
        if (-not (Test-RelativePath $repoRoot $rel)) {
            $missing += $rel
            Add-Issue $issues ("task_kernel_missing_" + ($rel -replace '[^A-Za-z0-9]+', '_').Trim('_').ToLowerInvariant())
        }
    }

    $tasksRoot = Join-Path $repoRoot ".forge\tasks"
    if (Test-Path -LiteralPath $tasksRoot) {
        foreach ($taskDir in Get-ChildItem -LiteralPath $tasksRoot -Directory) {
            if ($taskDir.Name -eq "archive") { continue }
            $taskMissing = @()
            foreach ($file in @("task.json", "prd.md", "info.md", "implement.jsonl", "check.jsonl")) {
                if (-not (Test-Path -LiteralPath (Join-Path $taskDir.FullName $file))) {
                    $taskMissing += $file
                    Add-Issue $issues ("task_kernel_task_missing_" + $taskDir.Name + "_" + $file.Replace(".", "_"))
                }
            }

            $metadata = $null
            $taskJsonPath = Join-Path $taskDir.FullName "task.json"
            if (Test-Path -LiteralPath $taskJsonPath) {
                try {
                    $metadata = Get-Content -Raw -LiteralPath $taskJsonPath -Encoding UTF8 | ConvertFrom-Json
                    foreach ($field in @("name", "status", "stage", "priority")) {
                        if (-not ($metadata.PSObject.Properties.Name -contains $field)) {
                            Add-Issue $issues ("task_kernel_task_json_missing_" + $taskDir.Name + "_" + $field)
                        }
                    }
                } catch {
                    Add-Issue $issues ("task_kernel_invalid_task_json_" + $taskDir.Name)
                }
            }

            $missingContext += Test-JsonlReferences -RepoRoot $repoRoot -TaskDir $taskDir.FullName -FileName "implement.jsonl" -Issues $issues
            $missingContext += Test-JsonlReferences -RepoRoot $repoRoot -TaskDir $taskDir.FullName -FileName "check.jsonl" -Issues $issues

            $tasks += [ordered]@{
                name = $taskDir.Name
                path = $taskDir.FullName
                status = $(if ($metadata) { $metadata.status } else { $null })
                stage = $(if ($metadata) { $metadata.stage } else { $null })
                missing_files = @($taskMissing)
            }
        }
    }
}

$runtimePresent = Test-RelativePath $repoRoot ".forge\.runtime\sessions"
$status = "inactive"
if ($detected -and $issues.Count -eq 0) { $status = "compatible" }
elseif ($detected) { $status = "invalid" }

$result = [ordered]@{
    ok = ($issues.Count -eq 0)
    kernel = "forge-task-kernel"
    repo_root = $repoRoot
    detected = [bool]$detected
    status = $status
    runtime_sessions_present = [bool]$runtimePresent
    required_paths = @($requiredRootPaths + $requiredSpecDirs)
    missing_paths = @($missing)
    tasks = @($tasks)
    missing_context = @($missingContext)
    issues = @($issues)
}

if ($Json) {
    $result | ConvertTo-Json -Depth 12
} else {
    if ($result.ok) { Write-Output "forge_task_kernel=ok" } else { Write-Output "forge_task_kernel=fail" }
    Write-Output "status=$($result.status)"
    Write-Output "detected=$($result.detected)"
    foreach ($issue in $issues) { Write-Output "issue=$issue" }
}

if (-not $result.ok) { exit 1 }
exit 0
