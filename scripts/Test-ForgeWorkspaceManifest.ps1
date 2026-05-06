[CmdletBinding()]
param(
    [string]$RepoPath = "F:\develop\codex\playgrounds",
    [string]$ManifestPath = "",
    [switch]$Update,
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
function Get-Sha256 {
    param([string]$Path)
    if (-not (Test-Path -LiteralPath $Path)) { return $null }
    return (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash.ToLowerInvariant()
}

$repoRoot = Resolve-RepoRoot -Path $RepoPath
if (-not $ManifestPath) { $ManifestPath = Join-Path $repoRoot '.claude\forge-workspace-manifest.json' }
$relativePaths = @(
    '.claude\settings.json',
    '.claude\hooks\forge-pretool-guard.ps1',
    '.claude\hooks\forge-session-audit.ps1',
    '.claude\hooks\forge-hook-common.psm1',
    '.claude\hooks\tests\forge-hook.Tests.ps1',
    '.claude\workflow-policy.md',
    '.claude\project-profile.json',
    '.claude\forge-session-state.json',
    '.claude\forge-session.lock.json',
    '.claude\forge-routing.jsonl',
    'C:\Users\Administrator\.claude\scripts\forge-smoke.ps1',
    'C:\Users\Administrator\.claude\scripts\Test-ForgeDocsHealth.ps1',
    'C:\Users\Administrator\.claude\scripts\Test-ForgeM1Compliance.ps1',
    'C:\Users\Administrator\.claude\scripts\Test-ForgeLiveRouteFreshness.ps1',
    'C:\Users\Administrator\.claude\scripts\Reset-ForgeSessionState.ps1',
    'C:\Users\Administrator\.claude\scripts\Rotate-ForgeAuditLogs.ps1',
    'C:\Users\Administrator\.claude\scripts\Test-ForgeWorkspaceManifest.ps1',
    'C:\Users\Administrator\.claude\skills\forge\evals\evals.json',
    'C:\Users\Administrator\.claude\docs\forge-protocols.md',
    'C:\Users\Administrator\.claude\docs\forge-schema-versions.md',
    'C:\Users\Administrator\.claude\docs\hook-architecture.md'
)

$current = @()
foreach ($rel in $relativePaths) {
    $full = if ([System.IO.Path]::IsPathRooted($rel)) { $rel } else { Join-Path $repoRoot $rel }
    $exists = Test-Path -LiteralPath $full
    $current += [ordered]@{
        path = $rel
        full_path = $full
        exists = $exists
        sha256 = if ($exists) { Get-Sha256 $full } else { $null }
        length = if ($exists) { (Get-Item -LiteralPath $full).Length } else { $null }
    }
}

$issues = [System.Collections.Generic.List[string]]::new()
$changed = @()
if ($Update -or -not (Test-Path -LiteralPath $ManifestPath)) {
    $dir = Split-Path -Parent $ManifestPath
    if (-not (Test-Path -LiteralPath $dir)) { New-Item -ItemType Directory -Force -Path $dir | Out-Null }
    $manifest = [ordered]@{
        schema_version = 1
        repo = $repoRoot
        generated_at = (Get-Date).ToString('o')
        entries = @($current)
    }
    $manifest | ConvertTo-Json -Depth 12 | Set-Content -LiteralPath $ManifestPath -Encoding UTF8
    $action = if ($Update) { 'updated_manifest' } else { 'created_manifest' }
} else {
    $manifest = Get-Content -Raw -LiteralPath $ManifestPath -Encoding UTF8 | ConvertFrom-Json -AsHashtable
    $expectedByPath = @{}
    foreach ($entry in @($manifest.entries)) { $expectedByPath[[string]$entry.path] = $entry }
    foreach ($entry in $current) {
        if (-not $expectedByPath.ContainsKey([string]$entry.path)) {
            [void]$issues.Add("manifest_missing_entry:$($entry.path)")
            continue
        }
        $expected = $expectedByPath[[string]$entry.path]
        if ([bool]$expected.exists -ne [bool]$entry.exists) { $changed += [ordered]@{ path=$entry.path; issue='exists_changed'; expected=$expected.exists; actual=$entry.exists } }
        elseif ($entry.exists -and [string]$expected.sha256 -ne [string]$entry.sha256) { $changed += [ordered]@{ path=$entry.path; issue='hash_changed'; expected=$expected.sha256; actual=$entry.sha256 } }
    }
    foreach ($c in $changed) { [void]$issues.Add("$($c.issue):$($c.path)") }
    $action = 'checked_manifest'
}

$result = [ordered]@{
    ok = ($issues.Count -eq 0)
    action = $action
    repo = $repoRoot
    manifest_path = $ManifestPath
    checked_count = $current.Count
    changed = @($changed)
    issues = @($issues)
}
if ($Json) { $result | ConvertTo-Json -Depth 12 }
else {
    if ($result.ok) { Write-Output 'forge_workspace_manifest=ok' } else { Write-Output 'forge_workspace_manifest=fail' }
    Write-Output "action=$action"
    Write-Output "checked_count=$($current.Count)"
    foreach ($issue in $issues) { Write-Output "issue=$issue" }
}
if (-not $result.ok) { exit 1 }
exit 0
