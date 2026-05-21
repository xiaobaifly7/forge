[CmdletBinding()]
param(
    [string]$RepoPath = ".",
    [int]$LiveMaxAgeHours = 24,
    [switch]$Json
)

$ErrorActionPreference = "Stop"
$ScriptDir = Split-Path -Parent $PSCommandPath
$Repo = (Resolve-Path -LiteralPath $RepoPath).Path

function Invoke-Capture {
    param([string[]]$Arguments)
    $output = & pwsh -NoLogo -NoProfile -ExecutionPolicy Bypass -File (Join-Path $ScriptDir 'forge.ps1') @Arguments 2>&1
    return [ordered]@{
        exit_code = $LASTEXITCODE
        output = @($output | ForEach-Object { [string]$_ })
    }
}

function Get-LineValue {
    param([string[]]$Lines, [string]$Key)
    $prefix = "$Key="
    foreach ($line in @($Lines)) {
        if ($line.StartsWith($prefix, [System.StringComparison]::OrdinalIgnoreCase)) {
            return $line.Substring($prefix.Length)
        }
    }
    return ""
}

function Get-GitState {
    param([string]$Path)
    $branch = ""
    $commit = ""
    $dirtyCount = 0
    $dirtySample = @()
    try { $branch = [string](& git -C $Path branch --show-current 2>$null) } catch {}
    try { $commit = [string](& git -C $Path rev-parse --short HEAD 2>$null) } catch {}
    try {
        $status = @(& git -C $Path status --short 2>$null | Where-Object { $_ -and $_.Trim() })
        $dirtyCount = $status.Count
        $dirtySample = @($status | Select-Object -First 12)
    } catch {}
    return [ordered]@{
        branch = $branch.Trim()
        commit = $commit.Trim()
        dirty_count = $dirtyCount
        dirty_sample = $dirtySample
    }
}

$version = Invoke-Capture -Arguments @('version')
$doctor = Invoke-Capture -Arguments @('doctor', '-RepoPath', $Repo, '-Json')
$verify = Invoke-Capture -Arguments @('verify', '-RepoPath', $Repo, '-SkipSmoke', '-Json')
$sync = Invoke-Capture -Arguments @('sync-all', '-RepoPath', $Repo, '-Json')
$workflows = Invoke-Capture -Arguments @('workflows', '-RepoPath', $Repo, '-Json')

$doctorObj = $null
$verifyObj = $null
$syncObj = $null
$workflowsObj = $null
try { $doctorObj = ($doctor.output -join "`n") | ConvertFrom-Json } catch {}
try { $verifyObj = ($verify.output -join "`n") | ConvertFrom-Json } catch {}
try { $syncObj = ($sync.output -join "`n") | ConvertFrom-Json } catch {}
try { $workflowsObj = ($workflows.output -join "`n") | ConvertFrom-Json } catch {}

$versionLines = @($version.output)
$sourceRepo = Get-LineValue -Lines $versionLines -Key 'forge_source_repo'
$installedCommit = Get-LineValue -Lines $versionLines -Key 'forge_source_commit'
$currentCommit = Get-LineValue -Lines $versionLines -Key 'forge_source_current_commit'
$sourceDrift = Get-LineValue -Lines $versionLines -Key 'forge_source_drift'

$doctorOk = ($doctor.exit_code -eq 0 -and $doctorObj -and [bool]$doctorObj.ok)
$verifyOk = ($verify.exit_code -eq 0 -and $verifyObj -and [bool]$verifyObj.ok)
$syncOk = ($sync.exit_code -eq 0 -and $syncObj -and [bool]$syncObj.ok)
$workflowsOk = ($workflows.exit_code -eq 0 -and $workflowsObj -and [bool]$workflowsObj.ok)
$globalOk = ($version.exit_code -eq 0 -and $sourceDrift -eq 'false')

$next = @()
if (-not $globalOk) { $next += 'run forge version -FixDrift' }
if (-not $syncOk -or ($syncObj -and $syncObj.repos | Where-Object { $_.needs_sync })) {
    if ($syncObj -and $syncObj.global_script_matches_source -eq $false) {
        $next += 'run forge install -RepoPath <source-repo> or forge version -FixDrift'
    } else {
        $next += 'run forge sync-all -RepoPath <repo> -Apply'
    }
}
if (-not $doctorOk) { $next += 'run forge doctor -RepoPath <repo> -Json and inspect failed checks' }
if (-not $verifyOk) { $next += 'run forge verify -RepoPath <repo> -SkipSmoke -Json and inspect failed checks' }
if ($next.Count -eq 0) { $next += 'none' }

$result = [ordered]@{
    ok = [bool]($globalOk -and $doctorOk -and $verifyOk -and $syncOk -and $workflowsOk)
    repo = $Repo
    git = Get-GitState -Path $Repo
    global = [ordered]@{
        ok = [bool]$globalOk
        source_repo = $sourceRepo
        installed_source_commit = $installedCommit
        source_current_commit = $currentCommit
        source_drift = $sourceDrift
    }
    project = [ordered]@{
        doctor_ok = [bool]$doctorOk
        verify_ok = [bool]$verifyOk
        sync_ok = [bool]$syncOk
        workflows_ok = [bool]$workflowsOk
        doctor_summary = if ($doctorObj) { $doctorObj.summary } else { "unavailable" }
        verify_summary = if ($verifyObj) { $verifyObj.summary } else { "unavailable" }
    }
    next_action = $next
    checks = [ordered]@{
        doctor_exit = $doctor.exit_code
        verify_exit = $verify.exit_code
        sync_exit = $sync.exit_code
        workflows_exit = $workflows.exit_code
    }
}

if ($Json) {
    $result | ConvertTo-Json -Depth 8
    exit ($(if ($result.ok) { 0 } else { 1 }))
}

Write-Output "Forge status: $(if ($result.ok) { 'PASS' } else { 'ATTENTION' })"
Write-Output "Repo: $Repo"
Write-Output "Git: branch=$($result.git.branch) commit=$($result.git.commit) dirty=$($result.git.dirty_count)"
Write-Output "Global: drift=$($result.global.source_drift) source=$($result.global.source_repo)"
Write-Output "Project: doctor=$($result.project.doctor_ok) verify=$($result.project.verify_ok) sync=$($result.project.sync_ok) workflows=$($result.project.workflows_ok)"
Write-Output "Next: $($next -join '; ')"
exit ($(if ($result.ok) { 0 } else { 1 }))
