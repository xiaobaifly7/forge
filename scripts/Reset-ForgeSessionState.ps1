[CmdletBinding(SupportsShouldProcess=$true)]
param(
    [string]$RepoPath = ".",
    [int]$TtlHours = 24,
    [switch]$Force,
    [switch]$Json,
    [switch]$Drill
)

$ErrorActionPreference = "Stop"
$ScriptDir = Split-Path -Parent $PSCommandPath

function Resolve-RepoRoot {
    param([string]$Path)
    try {
        $gitRoot = git -C $Path rev-parse --show-toplevel 2>$null
        if ($LASTEXITCODE -eq 0 -and $gitRoot) { return (Resolve-Path $gitRoot).Path }
    } catch {}
    return (Resolve-Path $Path).Path
}

function Read-JsonHashtable {
    param([string]$Path)
    if (-not (Test-Path -LiteralPath $Path)) { return $null }
    return Get-Content -Raw -LiteralPath $Path -Encoding UTF8 | ConvertFrom-Json -AsHashtable
}

function Test-MapKey {
    param($Map, [string]$Key)
    if (-not $Map) { return $false }
    if ($Map -is [System.Collections.IDictionary]) { return $Map.Contains($Key) }
    return [bool]($Map.PSObject.Properties.Name -contains $Key)
}

function Is-ExpiredValue {
    param([string]$Value)
    if ([string]::IsNullOrWhiteSpace($Value)) { return $true }
    try { return ([datetime]::Parse($Value) -lt (Get-Date)) } catch { return $true }
}

$repoRoot = Resolve-RepoRoot -Path $RepoPath
$claudeDir = Join-Path $repoRoot '.claude'
$statePath = Join-Path $claudeDir 'forge-session-state.json'
$lockPath = Join-Path $claudeDir 'forge-session.lock.json'
$state = Read-JsonHashtable -Path $statePath
$lock = Read-JsonHashtable -Path $lockPath
$now = Get-Date
$newExpiry = $now.AddHours($TtlHours).ToString('o')
$stateExpired = $true
$lockExpired = $true
if ($state -and (Test-MapKey $state 'expires_at')) { $stateExpired = Is-ExpiredValue ([string]$state.expires_at) }
if ($lock -and (Test-MapKey $lock 'expires_at')) { $lockExpired = Is-ExpiredValue ([string]$lock.expires_at) }
$needsReset = ($Force -or -not $state -or -not $lock -or $stateExpired -or $lockExpired)
$archive = $null
$actions = @()

if ($needsReset) {
    $stamp = Get-Date -Format 'yyyyMMdd-HHmmss'
    $archive = Join-Path $claudeDir "backups\forge-session-reset-$stamp"
    if ($PSCmdlet.ShouldProcess($repoRoot, "Archive and refresh Forge session state")) {
        New-Item -ItemType Directory -Force -Path $archive | Out-Null
        foreach ($path in @($statePath, $lockPath)) {
            if (Test-Path -LiteralPath $path) {
                Copy-Item -LiteralPath $path -Destination (Join-Path $archive (Split-Path $path -Leaf)) -Force
            }
        }
        if (-not $state) {
            $state = [ordered]@{
                schema_version = 1
                mode = 'full'
                execution = 'guided-full'
                phase = 'M1'
                question_pending = $false
                user_confirmed_next_phase = $true
                artifact_path = ''
                session_id = [guid]::NewGuid().ToString()
                is_drill = [bool]$Drill
                owner = 'claude-code'
                created_at = $now.ToString('o')
                last_pipeline_marker = if ($Drill) { '[PIPELINE] Forge session reset (drill)' } else { '[PIPELINE] Forge session reset' }
            }
            $actions += 'created_state'
        } else {
            $actions += 'refreshed_state'
        }
        if (-not (Test-MapKey $state 'session_id') -or [string]::IsNullOrWhiteSpace([string]$state.session_id)) { $state['session_id'] = [guid]::NewGuid().ToString() }
        if (-not (Test-MapKey $state 'phase') -or [string]::IsNullOrWhiteSpace([string]$state.phase)) { $state['phase'] = 'M1' }
        if (-not (Test-MapKey $state 'owner') -or [string]::IsNullOrWhiteSpace([string]$state.owner)) { $state['owner'] = 'claude-code' }
        if (-not (Test-MapKey $state 'created_at') -or [string]::IsNullOrWhiteSpace([string]$state.created_at)) { $state['created_at'] = $now.ToString('o') }
        $state['updated_at'] = $now.ToString('o')
        $state['expires_at'] = $newExpiry
        if (-not (Test-MapKey $state 'last_pipeline_marker')) { $state['last_pipeline_marker'] = '[PIPELINE] Forge session reset' }

        $lock = [ordered]@{
            schema_version = 1
            session_id = [string]$state.session_id
            owner = [string]$state.owner
            phase = [string]$state.phase
            created_at = if ((Test-MapKey $state 'created_at')) { [string]$state.created_at } else { $now.ToString('o') }
            updated_at = $now.ToString('o')
            expires_at = $newExpiry
        }
        $actions += 'refreshed_lock'
        New-Item -ItemType Directory -Force -Path $claudeDir | Out-Null
        $state | ConvertTo-Json -Depth 12 | Set-Content -LiteralPath $statePath -Encoding UTF8
        $lock | ConvertTo-Json -Depth 12 | Set-Content -LiteralPath $lockPath -Encoding UTF8
    }
} else {
    $actions += 'no_change_needed'
}

$result = [ordered]@{
    ok = $true
    repo = $repoRoot
    state_path = $statePath
    lock_path = $lockPath
    archive = $archive
    actions = @($actions)
    force = [bool]$Force
    ttl_hours = $TtlHours
    state_was_expired = $stateExpired
    lock_was_expired = $lockExpired
    expires_at = if ($needsReset) { $newExpiry } elseif ($state -and (Test-MapKey $state 'expires_at')) { [string]$state.expires_at } else { '' }
    validation_commands = @(
        ('pwsh -NoLogo -NoProfile -ExecutionPolicy Bypass -File ''{0}'' -RepoPath ''{1}'' -Latest -Json' -f (Join-Path $ScriptDir 'Test-ForgeM1Compliance.ps1'), $repoRoot),
        ('pwsh -NoLogo -NoProfile -ExecutionPolicy Bypass -File ''{0}\.claude\hooks\forge-session-audit.ps1'' -RepoPath ''{0}'' -Event Stop -Mode fail-close' -f $repoRoot)
    )
}

if ($Json) { $result | ConvertTo-Json -Depth 10 }
else {
    Write-Output "forge_session_reset=ok"
    Write-Output "actions=$(@($actions) -join ',')"
    Write-Output "expires_at=$($result.expires_at)"
    if ($archive) { Write-Output "archive=$archive" }
}
exit 0
