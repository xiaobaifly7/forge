[CmdletBinding()]
param(
    [switch]$Apply,
    [switch]$Json
)

$ErrorActionPreference = 'Stop'
$vendorRoot = Join-Path $env:USERPROFILE '.claude\vendors\forge-upstreams'
$repoRoot = Split-Path -Parent $PSScriptRoot
$repos = [ordered]@{
    'bmad-method' = Join-Path $vendorRoot 'bmad-method'
    'compound-engineering' = Join-Path $vendorRoot 'compound-engineering'
    'gsd-2' = Join-Path $vendorRoot 'gsd-2'
    'gstack' = Join-Path $vendorRoot 'gstack'
}
$issues = [System.Collections.Generic.List[string]]::new()
function Add-Issue { param([string]$Code) if (-not $issues.Contains($Code)) { [void]$issues.Add($Code) } }
function Git-One { param([string]$Path,[string[]]$Arguments) (& git -C $Path @Arguments 2>&1 | Select-Object -First 1) }
function Invoke-GitCapture {
    param([string]$Path,[string[]]$Arguments)
    $output = @(& git -C $Path @Arguments 2>&1 | ForEach-Object { [string]$_ })
    return [ordered]@{ exit_code = $LASTEXITCODE; output = $output }
}

$results = @()
foreach ($name in $repos.Keys) {
    $path = $repos[$name]
    if (-not (Test-Path -LiteralPath $path)) {
        Add-Issue "missing:$name"
        $results += [ordered]@{ name=$name; path=$path; exists=$false; action='missing' }
        continue
    }
    $fetch = Invoke-GitCapture -Path $path -Arguments @('fetch','--prune','origin')
    if ($fetch.exit_code -ne 0) { Add-Issue "fetch_failed:$name" }
    $counts = Git-One -Path $path -Arguments @('rev-list','--left-right','--count','HEAD...origin/main')
    $ahead = 0; $behind = 0
    if ($counts -match '^(\d+)\s+(\d+)$') { $ahead=[int]$Matches[1]; $behind=[int]$Matches[2] }
    $status = Invoke-GitCapture -Path $path -Arguments @('status','--short')
    $dirty = @($status.output | Where-Object { $_ -and $_.Trim() -and $_.Trim() -ne 'ok' })
    $headBefore = Git-One -Path $path -Arguments @('rev-parse','--short','HEAD')
    $origin = Git-One -Path $path -Arguments @('rev-parse','--short','origin/main')
    $action = 'current'
    $updated = $false
    $blocked = @()
    if ($dirty.Count -gt 0) { $blocked += 'dirty'; Add-Issue "dirty:$name" }
    if ($ahead -gt 0) { $blocked += 'ahead'; Add-Issue "ahead:${name}:$ahead" }
    if ($name -eq 'gstack' -and (Test-Path -LiteralPath (Join-Path $path 'LOCAL-PATCHES.md'))) { $blocked += 'gstack_patch_review'; Add-Issue 'gstack_requires_patch_review' }
    if ($behind -gt 0 -and $blocked.Count -lt 1) {
        if ($Apply) {
            $pull = Invoke-GitCapture -Path $path -Arguments @('pull','--ff-only')
            if ($pull.exit_code -eq 0) { $action='updated'; $updated=$true } else { $action='update_failed'; Add-Issue "update_failed:$name" }
        } else {
            $action='would_update'
        }
    } elseif ($blocked.Count -gt 0) {
        $action='blocked'
    }
    $headAfter = Git-One -Path $path -Arguments @('rev-parse','--short','HEAD')
    $results += [ordered]@{
        name=$name; path=$path; exists=$true; action=$action; updated=$updated;
        ahead=$ahead; behind=$behind; dirty_count=$dirty.Count; blocked=@($blocked);
        head_before=$headBefore; head_after=$headAfter; origin_main=$origin
    }
}

$workflow = $null; $doctor = $null; $verify = $null
if ($Apply -and $issues.Count -eq 0) {
    $workflow = (& pwsh -NoLogo -NoProfile -ExecutionPolicy Bypass -File (Join-Path $repoRoot 'scripts\Test-ForgeWorkflowEntrypoints.ps1') -RepoPath $repoRoot -Json | ConvertFrom-Json)
    $doctor = (& pwsh -NoLogo -NoProfile -ExecutionPolicy Bypass -File (Join-Path $repoRoot 'scripts\Invoke-ForgeHealth.ps1') -Mode Quick -RepoPath $repoRoot -Json | ConvertFrom-Json)
    $verify = (& pwsh -NoLogo -NoProfile -ExecutionPolicy Bypass -File (Join-Path $repoRoot 'scripts\Test-ForgeReleaseReadiness.ps1') -RepoPath $repoRoot -Full -Json | ConvertFrom-Json)
    if (-not $workflow.ok) { Add-Issue 'workflow_failed' }
    if (-not $doctor.ok) { Add-Issue 'doctor_failed' }
    if (-not $verify.ok) { Add-Issue 'verify_failed' }
}

$result = [ordered]@{
    ok = ($issues.Count -eq 0)
    action = if ($Apply) { 'apply' } else { 'audit' }
    checked_at = (Get-Date).ToString('o')
    repos = @($results)
    workflow_ok = if ($workflow) { [bool]$workflow.ok } else { $null }
    doctor_ok = if ($doctor) { [bool]$doctor.ok } else { $null }
    verify_ok = if ($verify) { [bool]$verify.ok } else { $null }
    issues = @($issues)
}
if ($Json) { $result | ConvertTo-Json -Depth 12 } else {
    "forge_update_frameworks=$($result.action)"
    foreach ($r in $results) { "$($r.name) action=$($r.action) behind=$($r.behind) ahead=$($r.ahead) dirty=$($r.dirty_count)" }
    foreach ($i in $issues) { "issue=$i" }
}
if (-not $result.ok) { exit 1 }

