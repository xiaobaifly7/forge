param(
    [string]$RepoPath = ".",
    [string]$Event = "manual"
)

$ErrorActionPreference = "Stop"

[ordered]@{
    ok = $true
    mode = "repo_contract_stub"
    hook = "forge-session-audit"
    event = $Event
    repo_path = $RepoPath
    note = "Repo-local compatibility stub. Live hook implementation remains in hooks/forge-session-audit.ps1."
} | ConvertTo-Json -Depth 4

exit 0
