param(
    [string]$RepoPath = ".",
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

function Test-PathRelative {
    param([string]$Root, [string]$RelativePath)
    return (Test-Path -LiteralPath (Join-Path $Root $RelativePath))
}

function Read-OptionalText {
    param([string]$Path)
    if (Test-Path -LiteralPath $Path) {
        return (Get-Content -Raw -LiteralPath $Path -Encoding UTF8).Trim()
    }
    return ""
}

function Get-TrellisStatus {
    param([string]$RepoRoot, [System.Collections.Generic.List[string]]$Issues)

    $root = Join-Path $RepoRoot ".trellis"
    $present = Test-Path -LiteralPath $root
    $required = @(
        ".trellis\spec",
        ".trellis\tasks",
        ".trellis\workspace",
        ".trellis\workflow.md",
        ".trellis\scripts\task.py",
        ".trellis\scripts\get_context.py"
    )
    $missing = @()
    if ($present) {
        foreach ($rel in $required) {
            if (-not (Test-PathRelative $RepoRoot $rel)) { $missing += $rel }
        }
        foreach ($rel in $missing) {
            Add-Issue $Issues ("trellis_missing_" + ($rel -replace '[^A-Za-z0-9]+', '_').Trim('_').ToLowerInvariant())
        }
    }

    $version = ""
    if ($present) { $version = Read-OptionalText (Join-Path $root ".version") }

    return [ordered]@{
        present = $present
        version = $version
        mode = if ($present) { "adapter_read_only" } else { "not_installed" }
        required_paths = $required
        missing_paths = $missing
        mapped_events = @(
            "task_created",
            "planning_ready",
            "implementation_started",
            "check_completed",
            "finish_requested",
            "lesson_promoted"
        )
    }
}

function Get-CodeStableStatus {
    param([string]$RepoRoot)

    $knownDirs = @(
        "cs",
        "cs-req",
        "cs-arch",
        "cs-roadmap",
        "cs-feat",
        "cs-issue",
        "cs-audit",
        "cs-learn",
        "cs-note",
        "cs-refactor",
        "cs-guide"
    )
    $presentDirs = @()
    foreach ($dir in $knownDirs) {
        if (Test-Path -LiteralPath (Join-Path $RepoRoot $dir)) { $presentDirs += $dir }
    }
    $present = $presentDirs.Count -gt 0

    return [ordered]@{
        present = $present
        mode = if ($present) { "taxonomy_read_only" } else { "not_installed" }
        detected_dirs = $presentDirs
        mapped_assets = @(
            "requirement",
            "architecture",
            "roadmap",
            "feature",
            "issue",
            "audit",
            "learning",
            "note"
        )
    }
}

$repoRoot = Resolve-RepoRoot -Path $RepoPath
$issues = [System.Collections.Generic.List[string]]::new()

$forgeRequired = @(
    ".claude\project-profile.json",
    ".claude\workflow-policy.md",
    ".claude\settings.json",
    ".claude\hooks\forge-pretool-guard.ps1",
    ".claude\hooks\forge-session-audit.ps1",
    ".claude\forge\adapter-contract.md"
)
foreach ($rel in $forgeRequired) {
    if (-not (Test-PathRelative $repoRoot $rel)) {
        Add-Issue $issues ("forge_missing_" + ($rel -replace '[^A-Za-z0-9]+', '_').Trim('_').ToLowerInvariant())
    }
}

$trellis = Get-TrellisStatus -RepoRoot $repoRoot -Issues $issues
$codeStable = Get-CodeStableStatus -RepoRoot $repoRoot

$result = [ordered]@{
    ok = ($issues.Count -eq 0)
    repo = $repoRoot
    contract = ".claude/forge/adapter-contract.md"
    ownership = [ordered]@{
        forge_core = "authoritative_governance"
        trellis = "optional_external_task_spec_workspace_shell"
        codestable = "optional_external_lifecycle_taxonomy"
        adapters = "read_only_translation_layer"
    }
    trellis = $trellis
    codestable = $codeStable
    issues = @($issues)
}

if ($Json) {
    $result | ConvertTo-Json -Depth 10
} else {
    if ($result.ok) { Write-Output "forge_adapter_compatibility=ok" }
    else {
        Write-Output "forge_adapter_compatibility=fail"
        foreach ($issue in $issues) { Write-Output "issue=$issue" }
    }
    Write-Output "contract=$($result.contract)"
    Write-Output "trellis_mode=$($trellis.mode)"
    Write-Output "codestable_mode=$($codeStable.mode)"
}

if (-not $result.ok) { exit 1 }
exit 0
