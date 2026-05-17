[CmdletBinding()]
param(
    [string]$LogPath = "$env:USERPROFILE\.claude\logs\forge-drift-audit-fallback.jsonl",
    [string[]]$ExtraLogPath = @(),
    [string[]]$RepoPath = @(),
    [switch]$SkipCreate,
    [int]$MaxBytes = 5242880,
    [int]$Keep = 10,
    [switch]$Json
)

$ErrorActionPreference = "Stop"
function Add-LogTarget {
    param([System.Collections.Generic.List[string]]$Items, [string]$Path)
    if ([string]::IsNullOrWhiteSpace($Path)) { return }
    $full = $Path
    try {
        $parent = Split-Path -Parent $Path
        if ($parent -and (Test-Path -LiteralPath $parent)) { $full = [System.IO.Path]::GetFullPath($Path) }
    } catch {}
    if (-not $Items.Contains($full)) { [void]$Items.Add($full) }
}
function Add-RepoLogs {
    param([System.Collections.Generic.List[string]]$Items, [string]$Repo)
    if ([string]::IsNullOrWhiteSpace($Repo) -or -not (Test-Path -LiteralPath $Repo)) { return }
    try {
        $gitRoot = git -C $Repo rev-parse --show-toplevel 2>$null
        if ($LASTEXITCODE -eq 0 -and $gitRoot) { $Repo = (Resolve-Path $gitRoot).Path }
    } catch { $Repo = (Resolve-Path -LiteralPath $Repo).Path }
    Add-LogTarget -Items $Items -Path (Join-Path $Repo ".claude\forge-drift-audit.jsonl")
    Add-LogTarget -Items $Items -Path (Join-Path $Repo ".claude\forge-routing.jsonl")
}
function Rotate-OneLog {
    param([string]$Path)
    $actions = @()
    $rotatedTo = $null
    $exists = Test-Path -LiteralPath $Path
    $lengthBefore = 0
    if ($exists) { $lengthBefore = (Get-Item -LiteralPath $Path).Length }
    if ($exists -and $lengthBefore -gt $MaxBytes) {
        $stamp = Get-Date -Format 'yyyyMMdd-HHmmss'
        $rotatedTo = "$Path.$stamp.bak"
        Move-Item -LiteralPath $Path -Destination $rotatedTo -Force
        New-Item -ItemType File -Path $Path -Force | Out-Null
        $actions += 'rotated'
    } elseif (-not $exists) {
        if ($SkipCreate) {
            $actions += 'missing_skipped'
        } else {
            $dir = Split-Path -Parent $Path
            if (-not (Test-Path -LiteralPath $dir)) { New-Item -ItemType Directory -Force -Path $dir | Out-Null }
            New-Item -ItemType File -Path $Path -Force | Out-Null
            $actions += 'created'
        }
    } else { $actions += 'no_rotation_needed' }
    $pattern = (Split-Path -Leaf $Path) + '.*.bak'
    $dir = Split-Path -Parent $Path
    $archives = @(Get-ChildItem -LiteralPath $dir -Filter $pattern -File -ErrorAction SilentlyContinue | Sort-Object LastWriteTime -Descending)
    $removed = @()
    if ($archives.Count -gt $Keep) {
        foreach ($old in $archives[$Keep..($archives.Count-1)]) {
            Remove-Item -LiteralPath $old.FullName -Force
            $removed += $old.FullName
        }
        if ($removed.Count -gt 0) { $actions += 'pruned_old_archives' }
    }
    $lengthAfter = if (Test-Path -LiteralPath $Path) { (Get-Item -LiteralPath $Path).Length } else { 0 }
    return [ordered]@{ ok=$true; log_path=$Path; length_before=$lengthBefore; length_after=$lengthAfter; rotated_to=$rotatedTo; removed=@($removed); actions=@($actions) }
}

$targets = [System.Collections.Generic.List[string]]::new()
Add-LogTarget -Items $targets -Path $LogPath
foreach ($path in @($ExtraLogPath)) { Add-LogTarget -Items $targets -Path $path }
foreach ($repo in @($RepoPath)) { Add-RepoLogs -Items $targets -Repo $repo }
$results = @()
foreach ($target in @($targets)) { $results += Rotate-OneLog -Path $target }
$result = [ordered]@{ ok=$true; max_bytes=$MaxBytes; keep=$Keep; target_count=$results.Count; results=@($results) }
if ($Json) { $result | ConvertTo-Json -Depth 8 }
else {
    Write-Output 'forge_audit_log_rotation=ok'
    foreach ($item in @($results)) { Write-Output "log=$($item.log_path) actions=$(@($item.actions) -join ',') length_before=$($item.length_before) length_after=$($item.length_after)" }
}
exit 0
