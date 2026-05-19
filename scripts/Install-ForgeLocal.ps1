param(
  [Parameter(Mandatory=$true)]
  [string]$RepoPath,

  [string]$ClaudeRoot = (Join-Path $env:USERPROFILE ".claude"),
  [string]$CodexRoot = (Join-Path $env:USERPROFILE ".codex"),
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

function Install-ForgeUserRoot {
  param(
    [Parameter(Mandatory=$true)][string]$UserRoot,
    [Parameter(Mandatory=$true)][string]$RepoRoot
  )

  Copy-ForgeTree -Source (Join-Path $RepoRoot "commands") -Destination (Join-Path $UserRoot "commands")
  Copy-ForgeTree -Source (Join-Path $RepoRoot "skills") -Destination (Join-Path $UserRoot "skills")
  Copy-ForgeTree -Source (Join-Path $RepoRoot "docs") -Destination (Join-Path $UserRoot "docs")
  Copy-ForgeTree -Source (Join-Path $RepoRoot "scripts") -Destination (Join-Path $UserRoot "scripts")
}

$repoRoot = Split-Path -Parent $PSScriptRoot
$sourceInfoCandidates = @(
  (Join-Path $ClaudeRoot "forge-source.txt"),
  (Join-Path $CodexRoot "forge-source.txt")
)
if (($repoRoot -ieq $ClaudeRoot -or $repoRoot -ieq $CodexRoot)) {
  foreach ($sourceInfoPath in $sourceInfoCandidates) {
    if (-not (Test-Path -LiteralPath $sourceInfoPath)) { continue }
    foreach ($line in Get-Content -LiteralPath $sourceInfoPath -Encoding UTF8) {
      if ($line -match '^forge_source_repo=(.+)$' -and (Test-Path -LiteralPath $Matches[1])) {
        $repoRoot = (Resolve-Path -LiteralPath $Matches[1]).Path
        break
      }
    }
    if (-not ($repoRoot -ieq $ClaudeRoot -or $repoRoot -ieq $CodexRoot)) { break }
  }
}

$resolvedRepoPath = (Resolve-Path -LiteralPath $RepoPath).Path
$projectClaude = Join-Path $resolvedRepoPath ".claude"

Install-ForgeUserRoot -UserRoot $ClaudeRoot -RepoRoot $repoRoot
Install-ForgeUserRoot -UserRoot $CodexRoot -RepoRoot $repoRoot

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
Set-Content -LiteralPath (Join-Path $CodexRoot "forge-source.txt") -Encoding UTF8 -Value $sourceInfo

Write-Output "forge_install=ok"
Write-Output "claude_root=$ClaudeRoot"
Write-Output "codex_root=$CodexRoot"
Write-Output "repo_path=$resolvedRepoPath"
if (-not $installProjectHooks) { Write-Output "project_hooks=skipped_source_repo" }
Write-Output "forge_cmd=$shimPath"
if ($commit) { Write-Output "forge_source_commit=$commit" }
