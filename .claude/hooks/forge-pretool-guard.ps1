param(
    [string]$RepoPath = "."
)

$ErrorActionPreference = "Stop"

[ordered]@{
    ok = $true
    mode = "repo_contract_stub"
    hook = "forge-pretool-guard"
    repo_path = $RepoPath
    note = "Repo-local compatibility stub. Live hook implementation remains in hooks/forge-pretool-guard.ps1."
} | ConvertTo-Json -Depth 4

exit 0
