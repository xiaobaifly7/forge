param(
  [Parameter(Mandatory=$true)]
  [string]$RepoPath,

  [string]$ClaudeRoot = (Join-Path $env:USERPROFILE ".claude")
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
  Copy-Item -LiteralPath (Join-Path $Source "*") -Destination $Destination -Recurse -Force
}

$repoRoot = Split-Path -Parent $PSScriptRoot
$projectClaude = Join-Path $RepoPath ".claude"

Copy-ForgeTree -Source (Join-Path $repoRoot "commands") -Destination (Join-Path $ClaudeRoot "commands")
Copy-ForgeTree -Source (Join-Path $repoRoot "skills") -Destination (Join-Path $ClaudeRoot "skills")
Copy-ForgeTree -Source (Join-Path $repoRoot "docs") -Destination (Join-Path $ClaudeRoot "docs")
Copy-ForgeTree -Source (Join-Path $repoRoot "scripts") -Destination (Join-Path $ClaudeRoot "scripts")
Copy-ForgeTree -Source (Join-Path $repoRoot "hooks") -Destination (Join-Path $projectClaude "hooks")

Write-Output "forge_install=ok"
Write-Output "claude_root=$ClaudeRoot"
Write-Output "repo_path=$RepoPath"
