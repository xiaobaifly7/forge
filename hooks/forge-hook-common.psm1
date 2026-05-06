#requires -Version 7.0
# Forge hook 共享 module
# - UTF-8 stdin 解析
# - repo / 脚本路径解析
# - state / routing 流式读取
# - metrics 写入
# 被 forge-pretool-guard.ps1 与 forge-session-audit.ps1 共用

$Script:ForgeHookCommonVersion = '1.0.0'

function Read-StdinUtf8 {
    # 强制 UTF-8 解码 stdin payload，避免 Windows GBK 默认导致 JSON 解析失败。
    try {
        $stream = [Console]::OpenStandardInput()
        $reader = [System.IO.StreamReader]::new($stream, [System.Text.UTF8Encoding]::new($false))
        return $reader.ReadToEnd()
    } catch {
        return ''
    }
}

function ConvertFrom-StdinPayload {
    param([string]$Raw)
    if ([string]::IsNullOrWhiteSpace($Raw)) { return @{} }
    try {
        return $Raw | ConvertFrom-Json -AsHashtable -Depth 50
    } catch {
        Write-FallbackLog -Code 'stdin_parse_failed' -Detail $_.Exception.Message
        return @{}
    }
}

function Resolve-RepoRoot {
    param(
        [string]$Path,
        [hashtable]$Payload
    )
    if (-not [string]::IsNullOrWhiteSpace($Path) -and (Test-Path -LiteralPath $Path)) {
        try {
            $gitRoot = git -C $Path rev-parse --show-toplevel 2>$null
            if ($LASTEXITCODE -eq 0 -and $gitRoot) { return (Resolve-Path $gitRoot).Path }
        } catch {}
        return (Resolve-Path $Path).Path
    }
    if ($Payload -and $Payload.ContainsKey('cwd') -and $Payload['cwd']) {
        $cwd = [string]$Payload['cwd']
        if (Test-Path -LiteralPath $cwd) {
            try {
                $gitRoot = git -C $cwd rev-parse --show-toplevel 2>$null
                if ($LASTEXITCODE -eq 0 -and $gitRoot) { return (Resolve-Path $gitRoot).Path }
            } catch {}
            return (Resolve-Path $cwd).Path
        }
    }
    return (Resolve-Path '.').Path
}

function Get-ClaudeScriptPath {
    param([string]$Name)
    $repoScripts = Join-Path (Split-Path -Parent $PSScriptRoot) 'scripts'
    $repoCandidate = Join-Path $repoScripts $Name
    if (Test-Path -LiteralPath $repoCandidate) { return $repoCandidate }

    $userScripts = Join-Path $env:USERPROFILE '.claude\scripts'
    return (Join-Path $userScripts $Name)
}

function Get-PayloadField {
    param(
        [hashtable]$Payload,
        [string[]]$Keys
    )
    foreach ($key in $Keys) {
        if ($Payload.ContainsKey($key) -and $null -ne $Payload[$key] -and $Payload[$key] -ne '') {
            return $Payload[$key]
        }
    }
    return $null
}

function Get-ToolName {
    param([hashtable]$Payload)
    return [string](Get-PayloadField -Payload $Payload -Keys @('tool_name','toolName','name'))
}

function Get-ToolInput {
    param([hashtable]$Payload)
    foreach ($key in @('tool_input','toolInput','input')) {
        if ($Payload.ContainsKey($key) -and $Payload[$key] -is [hashtable]) {
            return $Payload[$key]
        }
    }
    return @{}
}

function Get-TargetPath {
    param([hashtable]$ToolInput)
    return [string](Get-PayloadField -Payload $ToolInput -Keys @('file_path','path','notebook_path'))
}

function Get-BashCommand {
    param([hashtable]$ToolInput)
    return [string](Get-PayloadField -Payload $ToolInput -Keys @('command','cmd'))
}

function Test-BashWritesFile {
    param([string]$Command)
    if ([string]::IsNullOrWhiteSpace($Command)) { return $false }
    $patterns = @(
        '\bSet-Content\b', '\bOut-File\b', '\bAdd-Content\b',
        '\bNew-Item\b.*-ItemType\s+File', '\bRemove-Item\b',
        '\becho\b.*\s>\s*\S', '\bcat\b.*\s>\s*\S', '\bprintf\b.*\s>\s*\S',
        '>>\s*\S+', '\btee\b\s', '\bcp\b\s', '\bmv\b\s', '\brm\b\s'
    )
    foreach ($p in $patterns) { if ($Command -match $p) { return $true } }
    return $false
}

function Resolve-TargetFullPath {
    param(
        [string]$RepoRoot,
        [string]$TargetPath
    )
    if ([string]::IsNullOrWhiteSpace($TargetPath)) { return '' }
    try {
        if ([System.IO.Path]::IsPathFullyQualified($TargetPath)) {
            return [System.IO.Path]::GetFullPath($TargetPath)
        }
        return [System.IO.Path]::GetFullPath((Join-Path $RepoRoot $TargetPath))
    } catch {
        return ''
    }
}

function Test-IsRepoForgeStatePath {
    param(
        [string]$RepoRoot,
        [string]$TargetPath
    )
    if ([string]::IsNullOrWhiteSpace($TargetPath)) { return $false }
    try {
        $full = Resolve-TargetFullPath -RepoRoot $RepoRoot -TargetPath $TargetPath
        if ([string]::IsNullOrWhiteSpace($full)) { return $false }
        $repo = [System.IO.Path]::GetFullPath($RepoRoot).TrimEnd('\','/')
        $forgeDir = [System.IO.Path]::GetFullPath((Join-Path $repo '.claude\forge')).TrimEnd('\','/')
        $claudeDir = [System.IO.Path]::GetFullPath((Join-Path $repo '.claude')).TrimEnd('\','/')
        if ($full.StartsWith($forgeDir + [System.IO.Path]::DirectorySeparatorChar, [System.StringComparison]::OrdinalIgnoreCase)) {
            return $true
        }
        foreach ($name in @('forge-session-state.json','forge-session.lock.json','forge-routing.jsonl','forge-drift-audit.jsonl','forge-workspace-manifest.json')) {
            $allowed = [System.IO.Path]::GetFullPath((Join-Path $claudeDir $name))
            if ($full.Equals($allowed, [System.StringComparison]::OrdinalIgnoreCase)) { return $true }
        }
        return $false
    } catch {
        return $false
    }
}

function Test-IsProjectWritePath {
    param(
        [string]$RepoRoot,
        [string]$TargetPath
    )
    try {
        $full = Resolve-TargetFullPath -RepoRoot $RepoRoot -TargetPath $TargetPath
        if ([string]::IsNullOrWhiteSpace($full)) { return $true }
        $repo = [System.IO.Path]::GetFullPath($RepoRoot).TrimEnd('\','/')
        if (-not $full.StartsWith($repo + [System.IO.Path]::DirectorySeparatorChar, [System.StringComparison]::OrdinalIgnoreCase)) {
            return $false
        }
        return -not (Test-IsRepoForgeStatePath -RepoRoot $RepoRoot -TargetPath $TargetPath)
    } catch {
        return $true
    }
}

function Read-SessionState {
    param([string]$RepoRoot)
    $statePath = Join-Path $RepoRoot '.claude\forge-session-state.json'
    if (-not (Test-Path -LiteralPath $statePath)) { return $null }
    try {
        return Get-Content -Raw -LiteralPath $statePath -Encoding UTF8 | ConvertFrom-Json -AsHashtable
    } catch {
        Write-FallbackLog -Code 'state_parse_failed' -Detail $_.Exception.Message -Repo $RepoRoot
        return $null
    }
}

function Test-StateSchemaSupported {
    param([hashtable]$State)
    if (-not $State) { return $false }
    if (-not $State.ContainsKey('schema_version')) { return $true }
    return ([int]$State['schema_version'] -eq 1)
}

function Get-StateValue {
    param(
        [hashtable]$State,
        [string]$Name,
        [string]$Default = ''
    )
    if ($State -and $State.ContainsKey($Name) -and $null -ne $State[$Name]) {
        return [string]$State[$Name]
    }
    return $Default
}

function Read-M1RoutingItems {
    param(
        [string]$Path,
        [int]$TailLimit = 0
    )
    if (-not (Test-Path -LiteralPath $Path)) { return @() }
    $items = [System.Collections.Generic.List[hashtable]]::new()
    try {
        foreach ($line in [System.IO.File]::ReadLines($Path, [System.Text.Encoding]::UTF8)) {
            if ([string]::IsNullOrWhiteSpace($line)) { continue }
            try {
                $item = $line | ConvertFrom-Json -AsHashtable
                if ([string]$item.pipeline_phase -eq 'M1') {
                    [void]$items.Add($item)
                    if ($TailLimit -gt 0 -and $items.Count -gt $TailLimit) {
                        $items.RemoveAt(0)
                    }
                }
            } catch {}
        }
    } catch {
        return @()
    }
    return @($items)
}

function Write-FallbackLog {
    param(
        [string]$Code,
        [string]$Detail,
        [string]$Repo = ''
    )
    $candidates = @(
        (Join-Path $env:USERPROFILE '.claude\logs\forge-hook-fallback.jsonl'),
        (Join-Path $env:TEMP 'forge-hook-fallback.jsonl')
    )
    $record = [ordered]@{
        time = (Get-Date).ToString('o')
        code = $Code
        detail = $Detail
        repo = $Repo
        pid = $PID
    }
    $line = $record | ConvertTo-Json -Compress -Depth 6
    foreach ($p in $candidates) {
        try {
            $dir = Split-Path -Parent $p
            if (-not (Test-Path -LiteralPath $dir)) { New-Item -ItemType Directory -Force -Path $dir | Out-Null }
            $line | Add-Content -LiteralPath $p -Encoding UTF8 -ErrorAction Stop
            return
        } catch {}
    }
}

function Write-HookMetrics {
    param(
        [string]$Hook,
        [string]$Event,
        [string]$Tool,
        [string]$Verdict,
        [int]$DurationMs,
        [hashtable]$Extra = @{}
    )
    $metricsPath = Join-Path $env:USERPROFILE '.claude\logs\forge-hook-metrics.jsonl'
    $record = [ordered]@{
        time = (Get-Date).ToString('o')
        hook = $Hook
        event = $Event
        tool = $Tool
        verdict = $Verdict
        duration_ms = $DurationMs
    }
    foreach ($k in $Extra.Keys) { $record[$k] = $Extra[$k] }
    $line = $record | ConvertTo-Json -Compress -Depth 6
    try {
        $dir = Split-Path -Parent $metricsPath
        if (-not (Test-Path -LiteralPath $dir)) { New-Item -ItemType Directory -Force -Path $dir | Out-Null }
        $line | Add-Content -LiteralPath $metricsPath -Encoding UTF8 -ErrorAction Stop
    } catch {}
}

function Write-VerboseTrace {
    param(
        [string]$Hook,
        [string]$Message,
        [hashtable]$Extra = @{}
    )
    if (-not $env:FORGE_HOOK_VERBOSE -or $env:FORGE_HOOK_VERBOSE -eq '0') { return }
    $tracePath = Join-Path $env:USERPROFILE '.claude\logs\forge-hook-trace.jsonl'
    $record = [ordered]@{
        time = (Get-Date).ToString('o')
        hook = $Hook
        msg = $Message
    }
    foreach ($k in $Extra.Keys) { $record[$k] = $Extra[$k] }
    try {
        $line = $record | ConvertTo-Json -Compress -Depth 6
        $dir = Split-Path -Parent $tracePath
        if (-not (Test-Path -LiteralPath $dir)) { New-Item -ItemType Directory -Force -Path $dir | Out-Null }
        $line | Add-Content -LiteralPath $tracePath -Encoding UTF8 -ErrorAction Stop
    } catch {}
}

Export-ModuleMember -Function @(
    'Read-StdinUtf8',
    'ConvertFrom-StdinPayload',
    'Resolve-RepoRoot',
    'Get-ClaudeScriptPath',
    'Get-PayloadField',
    'Get-ToolName',
    'Get-ToolInput',
    'Get-TargetPath',
    'Get-BashCommand',
    'Test-BashWritesFile',
    'Resolve-TargetFullPath',
    'Test-IsRepoForgeStatePath',
    'Test-IsProjectWritePath',
    'Read-SessionState',
    'Test-StateSchemaSupported',
    'Get-StateValue',
    'Read-M1RoutingItems',
    'Write-FallbackLog',
    'Write-HookMetrics',
    'Write-VerboseTrace'
)
