[CmdletBinding()]
param(
    [ValidateSet('Quick','Offline','Live','Full')][string]$Mode = 'Offline',
    [string]$RepoPath = ".",
    [int]$LiveMaxAgeHours = 24,
    [string]$LiveRouteLogPath = "$env:USERPROFILE\.claude\logs\forge-smoke.jsonl",
    [string]$RequiredClaudeVersion = "2.1.128",
    [switch]$FetchUpstreams,
    [int]$CheckTimeoutSeconds = 30,
    [switch]$Json
)
$ErrorActionPreference = "Continue"
$ScriptDir = Split-Path -Parent $PSCommandPath
$ClaudeRoot = Split-Path -Parent $ScriptDir
$checks=@()

function Get-OutputSummary {
    param([string]$Output)
    if ([string]::IsNullOrWhiteSpace($Output)) { return '' }
    $trimmed = $Output.Trim()
    if ($trimmed.StartsWith('{') -or $trimmed.StartsWith('[')) {
        try {
            $parsed = $trimmed | ConvertFrom-Json
            $parts = @()
            foreach ($name in @('ok', 'status', 'classification', 'requires_adapter_update')) {
                if ($parsed.PSObject.Properties.Name -contains $name) {
                    $parts += "$name=$($parsed.$name)"
                }
            }
            if ($parsed.PSObject.Properties.Name -contains 'issues') {
                $issueCount = @($parsed.issues).Count
                $parts += "issues=$issueCount"
            }
            if ($parts.Count -gt 0) { return ($parts -join ' ') }
        } catch {}
    }
    return (($trimmed -split "`r?`n") | Where-Object { -not [string]::IsNullOrWhiteSpace($_) } | Select-Object -First 1)
}

function Add-CheckResult {
    param([string]$Name,[bool]$Required,[string]$Command,[int]$ExitCode,[string]$Output,[datetime]$Started)
    $summary = Get-OutputSummary -Output $Output
    $ok = ($ExitCode -eq 0)
    $severity = if ($ok) { "pass" } elseif ($Required) { "error" } else { "warning" }
    $script:checks += [ordered]@{
        name=$Name
        required=$Required
        severity=$severity
        command=$Command
        exit_code=$ExitCode
        ok=$ok
        duration_ms=[int]((Get-Date)-$Started).TotalMilliseconds
        summary=$summary
        output=$Output
    }
}

function Add-InlineCheck {
    param([string]$Name,[scriptblock]$Script,[bool]$Required=$true)
    $started=Get-Date
    $exit=0
    $output=''
    try {
        $result = & $Script
        $output = @($result) -join "`n"
    } catch {
        $exit=1
        $output=$_.Exception.Message
    }
    Add-CheckResult -Name $Name -Required $Required -Command '<inline>' -ExitCode $exit -Output $output -Started $started
}

function Add-ProcessCheck {
    param([string]$Name,[string[]]$Arguments,[bool]$Required=$true,[int]$TimeoutSeconds=$CheckTimeoutSeconds)
    $started=Get-Date
    $exe = 'pwsh.exe'
    $stdout = [System.IO.Path]::GetTempFileName()
    $stderr = [System.IO.Path]::GetTempFileName()
    $command = "$exe " + (($Arguments | ForEach-Object { if($_ -match '[\s''"]'){ '"' + ($_ -replace '"','\"') + '"' } else { $_ } }) -join ' ')
    $exit=124
    $output=''
    try {
        $p = Start-Process -FilePath $exe -ArgumentList $Arguments -NoNewWindow -PassThru -RedirectStandardOutput $stdout -RedirectStandardError $stderr
        if (-not $p.WaitForExit([Math]::Max(1,$TimeoutSeconds) * 1000)) {
            try { $p.Kill($true) } catch { try { $p.Kill() } catch {} }
            $exit=124
            $output="timeout_after_seconds=$TimeoutSeconds"
        } else {
            $exit=$p.ExitCode
            $outText = if(Test-Path -LiteralPath $stdout){ Get-Content -LiteralPath $stdout -Raw -ErrorAction SilentlyContinue } else { '' }
            $errText = if(Test-Path -LiteralPath $stderr){ Get-Content -LiteralPath $stderr -Raw -ErrorAction SilentlyContinue } else { '' }
            $output = @($outText,$errText | Where-Object { -not [string]::IsNullOrWhiteSpace($_) }) -join "`n"
        }
    } catch {
        $exit=1
        $output=$_.Exception.Message
    } finally {
        Remove-Item -LiteralPath $stdout,$stderr -Force -ErrorAction SilentlyContinue
    }
    Add-CheckResult -Name $Name -Required $Required -Command $command -ExitCode $exit -Output $output -Started $started
}

function Test-JsonFile {
    param([string]$Path)
    if(-not (Test-Path -LiteralPath $Path)){ throw "missing: $Path" }
    Get-Content -LiteralPath $Path -Raw | ConvertFrom-Json | Out-Null
    "ok: $Path"
}

$claudeCommand = Get-Command claude -ErrorAction SilentlyContinue
$claudeVersion = if ($claudeCommand) { (& $claudeCommand.Source --version 2>$null | Select-Object -First 1) } else { 'not-found' }
$repoClaude = Join-Path $RepoPath '.claude'
$settingsPath = Join-Path $repoClaude 'settings.json'
$statePath = Join-Path $repoClaude 'forge-session-state.json'
if(-not (Test-Path -LiteralPath $statePath)){ $statePath = Join-Path $repoClaude 'forge-session.lock.json' }
$guardPath = Join-Path $repoClaude 'hooks\forge-pretool-guard.ps1'
$auditPath = Join-Path $repoClaude 'hooks\forge-session-audit.ps1'

if($Mode -eq 'Quick'){
    Add-InlineCheck 'settings_json' { Test-JsonFile $settingsPath }
    Add-InlineCheck 'session_state_json' { Test-JsonFile $statePath }
    Add-InlineCheck 'pretool_guard_exists' { if(-not (Test-Path -LiteralPath $guardPath)){ throw "missing: $guardPath" }; "ok: $guardPath" }
    Add-InlineCheck 'session_audit_exists' { if(-not (Test-Path -LiteralPath $auditPath)){ throw "missing: $auditPath" }; "ok: $auditPath" }
    Add-ProcessCheck 'm1_open_groups' @('-NoLogo','-NoProfile','-ExecutionPolicy','Bypass','-File',(Join-Path $ScriptDir 'Test-ForgeM1Compliance.ps1'),'-RepoPath',$RepoPath,'-AllOpenGroups','-Json') -TimeoutSeconds $CheckTimeoutSeconds -Required $false
    Add-ProcessCheck 'task_kernel_audit' @('-NoLogo','-NoProfile','-ExecutionPolicy','Bypass','-File',(Join-Path $ScriptDir 'Test-ForgeTaskKernel.ps1'),'-RepoPath',$RepoPath,'-Json') -TimeoutSeconds $CheckTimeoutSeconds -Required $false
    Add-ProcessCheck 'external_adapters_audit' @('-NoLogo','-NoProfile','-ExecutionPolicy','Bypass','-File',(Join-Path $ScriptDir 'Test-ForgeExternalAdapter.ps1'),'-Name','all','-RepoPath',$RepoPath,'-Json') -TimeoutSeconds $CheckTimeoutSeconds -Required $false
    Add-ProcessCheck 'stage_engine_audit' @('-NoLogo','-NoProfile','-ExecutionPolicy','Bypass','-File',(Join-Path $ScriptDir 'Resolve-ForgeStage.ps1'),'-RepoPath',$RepoPath,'-Stage','task','-Json') -TimeoutSeconds $CheckTimeoutSeconds -Required $false
    Add-ProcessCheck 'external_ref_compare_audit' @('-NoLogo','-NoProfile','-ExecutionPolicy','Bypass','-File',(Join-Path $ScriptDir 'Compare-ForgeExternalAdapterRef.ps1'),'-Name','flow-kit','-RepoPath',$RepoPath,'-Json') -TimeoutSeconds $CheckTimeoutSeconds -Required $false
} else {
    Add-ProcessCheck 'docs_health' @('-NoLogo','-NoProfile','-ExecutionPolicy','Bypass','-File',(Join-Path $ScriptDir 'Test-ForgeDocsHealth.ps1'),'-ClaudeRoot',$ClaudeRoot,'-Json')
    Add-InlineCheck 'session_state' { Test-JsonFile $statePath }
    Add-ProcessCheck 'task_kernel_audit' @('-NoLogo','-NoProfile','-ExecutionPolicy','Bypass','-File',(Join-Path $ScriptDir 'Test-ForgeTaskKernel.ps1'),'-RepoPath',$RepoPath,'-Json') -TimeoutSeconds $CheckTimeoutSeconds -Required $false
    Add-ProcessCheck 'external_adapters_audit' @('-NoLogo','-NoProfile','-ExecutionPolicy','Bypass','-File',(Join-Path $ScriptDir 'Test-ForgeExternalAdapter.ps1'),'-Name','all','-RepoPath',$RepoPath,'-Json') -TimeoutSeconds $CheckTimeoutSeconds -Required $false
    Add-ProcessCheck 'stage_engine_audit' @('-NoLogo','-NoProfile','-ExecutionPolicy','Bypass','-File',(Join-Path $ScriptDir 'Resolve-ForgeStage.ps1'),'-RepoPath',$RepoPath,'-Stage','task','-Json') -TimeoutSeconds $CheckTimeoutSeconds -Required $false
    Add-ProcessCheck 'external_ref_compare_audit' @('-NoLogo','-NoProfile','-ExecutionPolicy','Bypass','-File',(Join-Path $ScriptDir 'Compare-ForgeExternalAdapterRef.ps1'),'-Name','flow-kit','-RepoPath',$RepoPath,'-Json') -TimeoutSeconds $CheckTimeoutSeconds -Required $false
    Add-ProcessCheck 'live_freshness' @('-NoLogo','-NoProfile','-ExecutionPolicy','Bypass','-File',(Join-Path $ScriptDir 'Test-ForgeLiveRouteFreshness.ps1'),'-LogPath',$LiveRouteLogPath,'-MaxAgeHours',[string]$LiveMaxAgeHours,'-RequiredClaudeVersion',$RequiredClaudeVersion,'-Json')
    Add-ProcessCheck 'workspace_manifest' @('-NoLogo','-NoProfile','-ExecutionPolicy','Bypass','-File',(Join-Path $ScriptDir 'Test-ForgeWorkspaceManifest.ps1'),'-RepoPath',$RepoPath,'-Json')
    Add-ProcessCheck 'audit_rotation' @('-NoLogo','-NoProfile','-ExecutionPolicy','Bypass','-File',(Join-Path $ScriptDir 'Rotate-ForgeAuditLogs.ps1'),'-Json')
    $upArgs=@('-NoLogo','-NoProfile','-ExecutionPolicy','Bypass','-File',(Join-Path $ScriptDir 'Test-ForgeUpstreams.ps1'),'-Json')
    if($FetchUpstreams){ $upArgs += '-Fetch' }
    Add-ProcessCheck 'upstreams' $upArgs
    Add-ProcessCheck 'gstack_patches' @('-NoLogo','-NoProfile','-ExecutionPolicy','Bypass','-File',(Join-Path $ScriptDir 'Test-GstackLocalPatches.ps1'),'-Json')
    Add-ProcessCheck 'm1_latest' @('-NoLogo','-NoProfile','-ExecutionPolicy','Bypass','-File',(Join-Path $ScriptDir 'Test-ForgeM1Compliance.ps1'),'-RepoPath',$RepoPath,'-Latest','-Json')
    if($Mode -eq 'Full' -or $Mode -eq 'Offline'){
        Add-ProcessCheck 'offline_smoke' @('-NoLogo','-NoProfile','-ExecutionPolicy','Bypass','-File',(Join-Path $ScriptDir 'forge-smoke.ps1'),'-NoLog') -TimeoutSeconds ([Math]::Max($CheckTimeoutSeconds,60))
    }
    if($Mode -eq 'Live' -or $Mode -eq 'Full'){
        Add-ProcessCheck 'live_route' @('-NoLogo','-NoProfile','-ExecutionPolicy','Bypass','-File',(Join-Path $ScriptDir 'forge-smoke.ps1'),'-LiveClaudeRoute','-LiveRouteTimeoutSeconds','120') -TimeoutSeconds ([Math]::Max($CheckTimeoutSeconds,150))
    }
}

$failed=@($checks | Where-Object { -not $_.ok -and $_.required })
$warnings=@($checks | Where-Object { -not $_.ok -and -not $_.required })
$result=[ordered]@{ ok=($failed.Count -eq 0); mode=$Mode; repo=$RepoPath; checked_at=(Get-Date).ToString('o'); claude_version=$claudeVersion; live_route_log_path=$LiveRouteLogPath; checks=@($checks); failed=@($failed | ForEach-Object {$_.name}); warnings=@($warnings | ForEach-Object {$_.name}) }
if($Json){ $result | ConvertTo-Json -Depth 12 }
else {
    if($result.ok){'Forge health: PASS'}else{'Forge health: FAIL'}
    "Mode: $Mode"
    "Repo: $RepoPath"
    "Summary: checks=$(@($checks).Count) failed=$(@($result.failed).Count) warnings=$(@($result.warnings).Count)"
    ''
    'Checks:'
    foreach($c in $checks){
        $label = if($c.ok){'PASS'}elseif($c.severity -eq 'warning'){'WARN'}else{'FAIL'}
        $line = "- $($c.name): $label exit=$($c.exit_code) duration_ms=$($c.duration_ms)"
        if(-not [string]::IsNullOrWhiteSpace($c.summary)){ $line += " -- $($c.summary)" }
        $line
    }
    $actionable = @($checks | Where-Object { -not $_.ok })
    if($actionable.Count -gt 0){
        ''
        'Next:'
        foreach($c in $actionable){
            if($c.required){"- $($c.name): fix this required check before continuing."}
            else{"- $($c.name): warning only; review before release."}
        }
    }
}
if(-not $result.ok){ exit 1 }



