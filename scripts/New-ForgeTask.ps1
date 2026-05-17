param(
    [string]$RepoPath = ".",
    [Parameter(Mandatory = $true)][string]$Name,
    [Parameter(Mandatory = $true)][string]$Title,
    [string]$Goal = "",
    [ValidateSet("change", "requirement", "design", "ui-design", "task", "dev", "test", "review", "integration")]
    [string]$Stage = "task",
    [ValidateSet("planning", "in_progress", "review", "completed")]
    [string]$Status = "planning",
    [ValidateSet("low", "normal", "high")]
    [string]$Priority = "normal",
    [string]$Owner = "developer",
    [string[]]$ImplementContext = @(),
    [string[]]$CheckContext = @(),
    [switch]$Force,
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

function Convert-ToSlug {
    param([string]$Value)
    $slug = $Value.ToLowerInvariant() -replace '[^a-z0-9]+', '-'
    $slug = $slug.Trim('-')
    if ([string]::IsNullOrWhiteSpace($slug)) {
        $bytes = [System.Text.Encoding]::UTF8.GetBytes($Value)
        $hash = [System.BitConverter]::ToString([System.Security.Cryptography.SHA256]::HashData($bytes)).Replace('-', '').Substring(0, 8).ToLowerInvariant()
        $slug = "task-$hash"
    }
    return $slug
}

function ConvertTo-ForgeRelativePath {
    param(
        [string]$RepoRoot,
        [string]$RelativePath
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
        throw "Context path must be under .forge\\: $RelativePath"
    }
    return ([System.IO.Path]::GetRelativePath($RepoRoot, $candidate) -replace '/', '\')
}

function Write-JsonlContext {
    param(
        [string]$Path,
        [string[]]$Entries,
        [string]$Reason
    )
    $lines = @()
    foreach ($entry in $Entries) {
        $rel = ConvertTo-ForgeRelativePath -RepoRoot $repoRoot -RelativePath $entry
        $lines += ([ordered]@{ file = $rel; reason = $Reason } | ConvertTo-Json -Compress)
    }
    if ($lines.Count -eq 0) {
        $lines += ([ordered]@{ _example = 'Fill with {"file":"<.forge/spec-or-research-path>","reason":"<why>"}. Keep context under .forge only.' } | ConvertTo-Json -Compress)
    }
    Set-Content -LiteralPath $Path -Encoding UTF8 -Value $lines
}

$repoRoot = Resolve-RepoRoot -Path $RepoPath
$slug = Convert-ToSlug $Name
$datePrefix = Get-Date -Format "MM-dd"
$taskName = "$datePrefix-$slug"
$relativeTaskPath = ".forge\tasks\$taskName"
$forgeRoot = Join-Path $repoRoot ".forge"
$taskRoot = Join-Path $forgeRoot "tasks"
$taskDir = Join-Path $taskRoot $taskName

if ((Test-Path -LiteralPath $taskDir) -and -not $Force) {
    throw "Task already exists: $taskName. Use -Force to overwrite generated files."
}

New-Item -ItemType Directory -Force -Path $taskDir | Out-Null
New-Item -ItemType Directory -Force -Path (Join-Path $taskDir "research") | Out-Null

$metadata = [ordered]@{
    name = $slug
    title = $Title
    status = $Status
    stage = $Stage
    priority = $Priority
    owner = $Owner
    branch = $null
    pr = $null
    parent = $null
    children = @()
    created_at = (Get-Date).ToString("o")
    updated_at = (Get-Date).ToString("o")
}

$goalText = if ([string]::IsNullOrWhiteSpace($Goal)) { "TODO: define goal." } else { $Goal }
$prd = @"
# $Title

## Goal

$goalText

## In Scope

- TODO

## Out of Scope

- TODO

## Acceptance Criteria

- TODO
"@

$info = @"
# Technical Design

## Approach

TODO

## Risks

- TODO

## Verification

- TODO
"@

$metadata | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath (Join-Path $taskDir "task.json") -Encoding UTF8
Set-Content -LiteralPath (Join-Path $taskDir "prd.md") -Encoding UTF8 -Value $prd
Set-Content -LiteralPath (Join-Path $taskDir "info.md") -Encoding UTF8 -Value $info
Write-JsonlContext -Path (Join-Path $taskDir "implement.jsonl") -Entries $ImplementContext -Reason "Implementation context selected during task creation."
Write-JsonlContext -Path (Join-Path $taskDir "check.jsonl") -Entries $CheckContext -Reason "Verification context selected during task creation."
Set-Content -LiteralPath (Join-Path $taskDir "research\notes.md") -Encoding UTF8 -Value "# Research Notes`n`nTODO`n"

$result = [ordered]@{
    ok = $true
    repo_root = $repoRoot
    task_name = $taskName
    task_path = $relativeTaskPath
    absolute_task_path = (Resolve-Path $taskDir).Path
    stage = $Stage
    status = $Status
}

if ($Json) {
    $result | ConvertTo-Json -Depth 8
} else {
    Write-Output "forge_task_created=ok"
    Write-Output "task_name=$taskName"
    Write-Output "task_path=$($result.task_path)"
}

exit 0
