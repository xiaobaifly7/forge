[CmdletBinding()]
param(
    [string[]]$RepoPath = @(),
    [string[]]$SearchRoot = @(),
    [string]$ClaudeRoot = (Join-Path $env:USERPROFILE ".claude"),
    [string]$BinDir = (Join-Path $env:USERPROFILE ".local\bin"),
    [switch]$Apply,
    [switch]$Json
)

$ErrorActionPreference = "Stop"
$ScriptDir = Split-Path -Parent $PSCommandPath
$ForgeRoot = Split-Path -Parent $ScriptDir
$sourceInfoPath = Join-Path $ClaudeRoot "forge-source.txt"
if (Test-Path -LiteralPath $sourceInfoPath) {
    foreach ($line in Get-Content -LiteralPath $sourceInfoPath -Encoding UTF8) {
        if ($line -match '^forge_source_repo=(.+)$' -and (Test-Path -LiteralPath $Matches[1])) {
            $ForgeRoot = (Resolve-Path -LiteralPath $Matches[1]).Path
            break
        }
    }
}
$ScriptDir = Join-Path $ForgeRoot "scripts"
$InstallScript = Join-Path $ScriptDir "Install-ForgeLocal.ps1"
$HookNames = @("forge-pretool-guard.ps1", "forge-session-audit.ps1", "forge-hook-common.psm1")

function Resolve-RepoRoot {
    param([string]$Path)
    try {
        $gitRoot = git -C $Path rev-parse --show-toplevel 2>$null
        if ($LASTEXITCODE -eq 0 -and $gitRoot) { return (Resolve-Path $gitRoot).Path }
    } catch {}
    return (Resolve-Path -LiteralPath $Path).Path
}

function Get-Sha256OrNull {
    param([string]$Path)
    if (-not (Test-Path -LiteralPath $Path)) { return $null }
    return (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash.ToLowerInvariant()
}

function Test-ProjectHasForge {
    param([string]$RepoRoot)
    return (Test-Path -LiteralPath (Join-Path $RepoRoot ".claude\project-profile.json")) -or
        (Test-Path -LiteralPath (Join-Path $RepoRoot ".claude\workflow-policy.md")) -or
        (Test-Path -LiteralPath (Join-Path $RepoRoot ".claude\hooks\forge-hook-common.psm1"))
}

function Add-RepoCandidate {
    param([System.Collections.Generic.List[string]]$Items, [string]$Path)
    if ([string]::IsNullOrWhiteSpace($Path) -or -not (Test-Path -LiteralPath $Path)) { return }
    $resolved = Resolve-RepoRoot -Path $Path
    if (-not $Items.Contains($resolved)) { [void]$Items.Add($resolved) }
}

$candidates = [System.Collections.Generic.List[string]]::new()
foreach ($path in @($RepoPath)) { Add-RepoCandidate -Items $candidates -Path $path }
foreach ($root in @($SearchRoot)) {
    if ([string]::IsNullOrWhiteSpace($root) -or -not (Test-Path -LiteralPath $root)) { continue }
    foreach ($gitDir in Get-ChildItem -LiteralPath $root -Directory -Recurse -Force -ErrorAction SilentlyContinue | Where-Object { $_.Name -eq ".git" }) {
        $repo = Split-Path -Parent $gitDir.FullName
        if (Test-ProjectHasForge -RepoRoot $repo) { Add-RepoCandidate -Items $candidates -Path $repo }
    }
}

if ($candidates.Count -lt 1) {
    foreach ($fallback in @($ForgeRoot, "D:\develop\code\energy", "F:\develop\codex\playgrounds")) {
        if ((Test-Path -LiteralPath $fallback) -and (Test-ProjectHasForge -RepoRoot $fallback)) { Add-RepoCandidate -Items $candidates -Path $fallback }
    }
}

$sourceCommit = ""
try { $sourceCommit = (& git -C $ForgeRoot rev-parse --short HEAD 2>$null).Trim() } catch {}
$globalScript = Join-Path $ClaudeRoot "scripts\forge.ps1"
$globalScriptOk = ((Get-Sha256OrNull (Join-Path $ScriptDir "forge.ps1")) -eq (Get-Sha256OrNull $globalScript))

$results = @()
foreach ($repo in @($candidates)) {
    $hookResults = @()
    $needsSync = -not $globalScriptOk
    foreach ($name in $HookNames) {
        $src = Join-Path $ForgeRoot ("hooks\" + $name)
        $dst = Join-Path $repo (".claude\hooks\" + $name)
        $srcHash = Get-Sha256OrNull $src
        $dstHash = Get-Sha256OrNull $dst
        $matches = ($srcHash -and $dstHash -and $srcHash -eq $dstHash)
        if (-not $matches -and -not ([System.IO.Path]::GetFullPath($repo).TrimEnd('\','/') -ieq [System.IO.Path]::GetFullPath($ForgeRoot).TrimEnd('\','/'))) { $needsSync = $true }
        $hookResults += [ordered]@{ name=$name; exists=[bool]$dstHash; matches_source=[bool]$matches }
    }

    $installExit = $null
    $installOutput = @()
    if ($Apply -and $needsSync) {
        $installOutput = @(& pwsh -NoLogo -NoProfile -ExecutionPolicy Bypass -File $InstallScript -RepoPath $repo -ClaudeRoot $ClaudeRoot -BinDir $BinDir 2>&1)
        $installExit = $LASTEXITCODE
        $hookResults = @()
        foreach ($name in $HookNames) {
            $src = Join-Path $ForgeRoot ("hooks\" + $name)
            $dst = Join-Path $repo (".claude\hooks\" + $name)
            $srcHash = Get-Sha256OrNull $src
            $dstHash = Get-Sha256OrNull $dst
            $hookResults += [ordered]@{ name=$name; exists=[bool]$dstHash; matches_source=[bool]($srcHash -and $dstHash -and $srcHash -eq $dstHash) }
        }
    }

    $results += [ordered]@{
        repo = $repo
        is_source_repo = ([System.IO.Path]::GetFullPath($repo).TrimEnd('\','/') -ieq [System.IO.Path]::GetFullPath($ForgeRoot).TrimEnd('\','/'))
        needs_sync = [bool]$needsSync
        hooks = @($hookResults)
        install_exit = $installExit
        install_output = @($installOutput | ForEach-Object { [string]$_ })
    }
}

$afterGlobalOk = ((Get-Sha256OrNull (Join-Path $ScriptDir "forge.ps1")) -eq (Get-Sha256OrNull $globalScript))
$remaining = @($results | Where-Object { @($_.hooks | Where-Object { -not $_.matches_source -and -not $_.exists }).Count -gt 0 })
$result = [ordered]@{
    ok = ($remaining.Count -eq 0 -and $afterGlobalOk)
    action = if ($Apply) { "sync" } else { "audit" }
    forge_root = $ForgeRoot
    source_commit = $sourceCommit
    claude_root = $ClaudeRoot
    global_script_matches_source = [bool]$afterGlobalOk
    repo_count = $results.Count
    repos = @($results)
}

if ($Json) { $result | ConvertTo-Json -Depth 10 }
else {
    Write-Output "forge_sync_action=$($result.action)"
    Write-Output "forge_source_commit=$sourceCommit"
    Write-Output "global_script_matches_source=$($result.global_script_matches_source)"
    foreach ($repoResult in @($results)) {
        $hookSummary = (@($repoResult.hooks) | ForEach-Object { "$($_.name):$($_.matches_source)" }) -join ","
        Write-Output "repo=$($repoResult.repo) needs_sync=$($repoResult.needs_sync) install_exit=$($repoResult.install_exit) hooks=$hookSummary"
    }
}
if (-not $result.ok) { exit 1 }
exit 0

