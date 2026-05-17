param(
  [Parameter(Mandatory=$true)]
  [string]$RepoPath,

  [string]$ClaudeRoot = (Join-Path $env:USERPROFILE ".claude"),
  [string]$BinDir = (Join-Path $env:USERPROFILE ".local\bin")
)

$ErrorActionPreference = "Stop"

function Copy-ForgeTree {
  param(
    [Parameter(Mandatory=$true)][string]$Source,
    [Parameter(Mandatory=$true)][string]$Destination
  )

  if (-not (Test-Path -LiteralPath $Source)) {
    throw "Missing source: $Source"
  }

  New-Item -ItemType Directory -Force -Path $Destination | Out-Null
  Copy-Item -Path (Join-Path $Source "*") -Destination $Destination -Recurse -Force
}

$repoRoot = Split-Path -Parent $PSScriptRoot
$resolvedRepoPath = (Resolve-Path -LiteralPath $RepoPath).Path
$projectClaude = Join-Path $resolvedRepoPath ".claude"

Copy-ForgeTree -Source (Join-Path $repoRoot "commands") -Destination (Join-Path $ClaudeRoot "commands")
Copy-ForgeTree -Source (Join-Path $repoRoot "skills") -Destination (Join-Path $ClaudeRoot "skills")
Copy-ForgeTree -Source (Join-Path $repoRoot "docs") -Destination (Join-Path $ClaudeRoot "docs")
Copy-ForgeTree -Source (Join-Path $repoRoot "scripts") -Destination (Join-Path $ClaudeRoot "scripts")
$installProjectHooks = -not ([System.IO.Path]::GetFullPath($resolvedRepoPath).TrimEnd('\', '/') -ieq [System.IO.Path]::GetFullPath($repoRoot).TrimEnd('\', '/'))
if ($installProjectHooks) {
  Copy-ForgeTree -Source (Join-Path $repoRoot "hooks") -Destination (Join-Path $projectClaude "hooks")
}

New-Item -ItemType Directory -Force -Path $BinDir | Out-Null
$shimPath = Join-Path $BinDir "forge.cmd"
$targetScript = Join-Path $ClaudeRoot "scripts\forge.ps1"
Set-Content -LiteralPath $shimPath -Encoding ASCII -Value @(
  "@echo off",
  "pwsh -NoLogo -NoProfile -ExecutionPolicy Bypass -File `"$targetScript`" %*"
)

$commit = ""
try {
  $commit = (& git -C $repoRoot rev-parse --short HEAD 2>$null)
  if ($LASTEXITCODE -ne 0) { $commit = "" }
} catch { $commit = "" }
$sourceInfo = @(
  "forge_source_repo=$repoRoot",
  "forge_source_commit=$commit",
  "forge_installed_at=$((Get-Date).ToString('o'))"
)
Set-Content -LiteralPath (Join-Path $ClaudeRoot "forge-source.txt") -Encoding UTF8 -Value $sourceInfo

Write-Output "forge_install=ok"
Write-Output "claude_root=$ClaudeRoot"
Write-Output "repo_path=$resolvedRepoPath"
if (-not $installProjectHooks) { Write-Output "project_hooks=skipped_source_repo" }
Write-Output "forge_cmd=$shimPath"
if ($commit) { Write-Output "forge_source_commit=$commit" }
