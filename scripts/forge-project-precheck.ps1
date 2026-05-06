param(
    [string]$RepoPath = ".",
    [string]$RegistryPath = "$env:USERPROFILE\.claude\forge-projects.json",
    [switch]$Json
)

$ErrorActionPreference = "Stop"

function Resolve-RepoRootSafe {
    param([string]$Path)
    try {
        $gitRoot = git -C $Path rev-parse --show-toplevel 2>$null
        if ($LASTEXITCODE -eq 0 -and $gitRoot) { return (Resolve-Path $gitRoot).Path }
    } catch {}
    return (Resolve-Path $Path).Path
}

function Normalize-PathKey {
    param([string]$Path)
    return ([System.IO.Path]::GetFullPath($Path).TrimEnd('\','/') -replace '/', '\').ToLowerInvariant()
}

function Get-ModeLabel {
    param([string]$Mode)
    switch ($Mode) {
        'disabled' { return '不接入 Forge' }
        'audit_only' { return '只读审计模式' }
        'local_routing' { return '可使用 Forge 轻量路由' }
        'full' { return '允许完整 Forge 流程' }
        default { return '未登记，默认只读' }
    }
}

function Get-LevelLabel {
    param([string]$Level)
    switch ($Level) {
        'L0' { return 'L0 只读检查' }
        'L1' { return 'L1 小任务模式' }
        'L2' { return 'L2 普通修复/功能模式' }
        'L3' { return 'L3 高风险 guided-full 模式' }
        'L4' { return 'L4 长期项目 stateful 模式' }
        default { return '不建议进入 Forge' }
    }
}

$registryExists = Test-Path -LiteralPath $RegistryPath

$repoRoot = Resolve-RepoRootSafe -Path $RepoPath
$repoKey = Normalize-PathKey -Path $repoRoot
$registry = @{ projects = @() }
if ($registryExists) {
    try {
        $registry = Get-Content -Raw -LiteralPath $RegistryPath | ConvertFrom-Json -AsHashtable
    } catch {
        $registry = @{ projects = @() }
    }
}
$match = $null
foreach ($project in @($registry.projects)) {
    $projectKey = Normalize-PathKey -Path ([string]$project.path)
    if ($repoKey -eq $projectKey -or $repoKey.StartsWith($projectKey + '')) {
        if (-not $match -or $projectKey.Length -gt (Normalize-PathKey -Path ([string]$match.path)).Length) { $match = $project }
    }
}

$profilePath = Join-Path $repoRoot ".claude\project-profile.json"
$profile = $null
if (Test-Path -LiteralPath $profilePath) {
    try { $profile = Get-Content -Raw -LiteralPath $profilePath | ConvertFrom-Json -AsHashtable } catch {}
}

if ($match) {
    $adoption = [string]$match.adoption
    $risk = [string]$match.risk
    $status = [string]$match.status
    $next = [string]$match.recommended_next
    $source = "registry"
} elseif ($profile) {
    $adoption = [string]$profile.forge_adoption.mode
    if (-not $adoption) { $adoption = "local_routing" }
    $risk = [string]$profile.risk_level
    $status = "profile_only"
    $next = "如果这是常用 Claude Code 项目，建议加入 forge-projects.json 矩阵。"
    $source = "profile"
} else {
    $adoption = "audit_only"
    $risk = "unknown"
    $status = "unregistered"
    $next = "先只读审计；不要初始化或写入，除非你明确授权。"
    $source = "fallback"
}

$allowedWrite = $adoption -in @("local_routing", "full")
$fullAllowed = $adoption -eq "full"
$recommendedLevel = "L0"
switch ($adoption) {
    "disabled" { $recommendedLevel = "none" }
    "audit_only" { $recommendedLevel = "L0" }
    "local_routing" { if ($profile -and $profile.default_route_level) { $recommendedLevel = [string]$profile.default_route_level } else { $recommendedLevel = "L1" } }
    "full" { if ($profile -and $profile.default_route_level) { $recommendedLevel = [string]$profile.default_route_level } else { $recommendedLevel = "L3" } }
}

$result = [ordered]@{
    time = (Get-Date).ToString("o")
    repo = $repoRoot
    source = $source
    adoption = $adoption
    adoption_label = Get-ModeLabel $adoption
    risk = $risk
    status = $status
    recommended_level = $recommendedLevel
    recommended_level_label = Get-LevelLabel $recommendedLevel
    write_allowed = $allowedWrite
    full_chain_allowed = $fullAllowed
    next = $next
    registry = if ($registryExists) { $RegistryPath } else { $null }
    registry_exists = [bool]$registryExists
    profile = if (Test-Path -LiteralPath $profilePath) { $profilePath } else { $null }
}

if ($Json) { $result | ConvertTo-Json -Depth 8; exit 0 }

$writeText = if ($allowedWrite) { '允许' } else { '默认不允许' }
$fullText = if ($fullAllowed) { '允许，但仍默认 guided-full' } else { '暂不建议' }
Write-Output "📋 Forge 检查结果"
Write-Output ""
Write-Output "项目：$repoRoot"
Write-Output "当前模式：$($result.adoption_label)"
Write-Output "风险等级：$risk"
Write-Output "项目状态：$status"
Write-Output "推荐等级：$($result.recommended_level_label)"
Write-Output "是否允许改文件：$writeText"
Write-Output "是否允许完整重流程：$fullText"
Write-Output ""
Write-Output "下一步建议：$next"
if (-not $registryExists) {
    Write-Output "Registry：未找到，已降级使用项目画像或只读 fallback。"
}
Write-Output ""
if ($adoption -eq 'audit_only') {
    Write-Output "你现在可以这样说："
    Write-Output "“只读审计这个项目，不要改文件，告诉我风险和建议。”"
    Write-Output ""
    Write-Output "如果确实要改，请明确说："
    Write-Output "“我授权你对这个项目写入修改，先备份再改。”"
} elseif ($adoption -eq 'local_routing') {
    Write-Output "你现在可以这样说："
    Write-Output "“按 Forge 路由来处理这个任务，改完验证。”"
    Write-Output ""
    Write-Output "如果涉及部署/发布/安全："
    Write-Output "“这是高风险任务，按 L3 guided-full 走。”"
} elseif ($adoption -eq 'full') {
    Write-Output "你现在可以这样说："
    Write-Output "“按 Forge full guided-full 走，先规划再执行。”"
} else {
    Write-Output "建议先只读检查，不要接管项目。"
}
