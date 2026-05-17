[CmdletBinding()]
param(
    [ValidateSet('list','add','remove')]
    [string]$Action = 'list',
    [string]$RepoPath = '',
    [string]$Name = '',
    [string]$RegistryPath = (Join-Path $env:USERPROFILE '.claude\forge-projects.json'),
    [switch]$Json
)

$ErrorActionPreference = 'Stop'
function Resolve-RepoRoot {
    param([string]$Path)
    try {
        $gitRoot = git -C $Path rev-parse --show-toplevel 2>$null
        if ($LASTEXITCODE -eq 0 -and $gitRoot) { return (Resolve-Path $gitRoot).Path }
    } catch {}
    return (Resolve-Path -LiteralPath $Path).Path
}
function Read-Registry {
    param([string]$Path)
    if (Test-Path -LiteralPath $Path) { return (Get-Content -LiteralPath $Path -Raw -Encoding UTF8 | ConvertFrom-Json -AsHashtable) }
    return [ordered]@{ schema_version=1; updated_at=(Get-Date).ToString('o'); projects=@() }
}
function Write-Registry {
    param([string]$Path, [hashtable]$Registry)
    $dir = Split-Path -Parent $Path
    if (-not (Test-Path -LiteralPath $dir)) { New-Item -ItemType Directory -Force -Path $dir | Out-Null }
    $Registry.updated_at = (Get-Date).ToString('o')
    $Registry | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $Path -Encoding UTF8
}

$registry = Read-Registry -Path $RegistryPath
$projects = @($registry.projects)
if ($Action -eq 'add') {
    if ([string]::IsNullOrWhiteSpace($RepoPath)) { throw 'Missing -RepoPath for projects add.' }
    $repo = Resolve-RepoRoot -Path $RepoPath
    $projectName = if ([string]::IsNullOrWhiteSpace($Name)) { Split-Path -Leaf $repo } else { $Name }
    $existing = @($projects | Where-Object { [string]$_.path -ieq $repo -or [string]$_.name -eq $projectName })
    if ($existing.Count -gt 0) {
        foreach ($item in $projects) {
            if ([string]$item.path -ieq $repo -or [string]$item.name -eq $projectName) {
                $item.name = $projectName
                $item.path = $repo
                $item.enabled = $true
            }
        }
    } else {
        $projects += [ordered]@{ name=$projectName; path=$repo; enabled=$true }
    }
    $registry.projects = @($projects)
    Write-Registry -Path $RegistryPath -Registry $registry
} elseif ($Action -eq 'remove') {
    if ([string]::IsNullOrWhiteSpace($RepoPath) -and [string]::IsNullOrWhiteSpace($Name)) { throw 'Missing -RepoPath or -Name for projects remove.' }
    $repo = if ($RepoPath) { Resolve-RepoRoot -Path $RepoPath } else { '' }
    $registry.projects = @($projects | Where-Object { -not (($repo -and [string]$_.path -ieq $repo) -or ($Name -and [string]$_.name -eq $Name)) })
    Write-Registry -Path $RegistryPath -Registry $registry
}

$result = [ordered]@{ ok=$true; action=$Action; registry_path=$RegistryPath; count=@($registry.projects).Count; projects=@($registry.projects) }
if ($Json) { $result | ConvertTo-Json -Depth 8 }
else {
    Write-Output "forge_projects_action=$Action"
    Write-Output "registry_path=$RegistryPath"
    foreach ($project in @($registry.projects)) { Write-Output "project=$($project.name) enabled=$($project.enabled) path=$($project.path)" }
}
exit 0
