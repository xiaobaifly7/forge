[CmdletBinding()]
param(
    [string]$LogPath = "$env:USERPROFILE\.claude\logs\forge-drift-audit-fallback.jsonl",
    [int]$MaxBytes = 5242880,
    [int]$Keep = 10,
    [switch]$Json
)

$ErrorActionPreference = "Stop"
$actions = @()
$rotatedTo = $null
$exists = Test-Path -LiteralPath $LogPath
$lengthBefore = 0
if ($exists) { $lengthBefore = (Get-Item -LiteralPath $LogPath).Length }

if ($exists -and $lengthBefore -gt $MaxBytes) {
    $stamp = Get-Date -Format 'yyyyMMdd-HHmmss'
    $rotatedTo = "$LogPath.$stamp.bak"
    Move-Item -LiteralPath $LogPath -Destination $rotatedTo -Force
    New-Item -ItemType File -Path $LogPath -Force | Out-Null
    $actions += 'rotated'
} elseif (-not $exists) {
    $dir = Split-Path -Parent $LogPath
    if (-not (Test-Path -LiteralPath $dir)) { New-Item -ItemType Directory -Force -Path $dir | Out-Null }
    New-Item -ItemType File -Path $LogPath -Force | Out-Null
    $actions += 'created'
} else {
    $actions += 'no_rotation_needed'
}

$pattern = (Split-Path -Leaf $LogPath) + '.*.bak'
$dir = Split-Path -Parent $LogPath
$archives = @(Get-ChildItem -LiteralPath $dir -Filter $pattern -File -ErrorAction SilentlyContinue | Sort-Object LastWriteTime -Descending)
$removed = @()
if ($archives.Count -gt $Keep) {
    foreach ($old in $archives[$Keep..($archives.Count-1)]) {
        Remove-Item -LiteralPath $old.FullName -Force
        $removed += $old.FullName
    }
    if ($removed.Count -gt 0) { $actions += 'pruned_old_archives' }
}

$lengthAfter = if (Test-Path -LiteralPath $LogPath) { (Get-Item -LiteralPath $LogPath).Length } else { 0 }
$result = [ordered]@{
    ok = $true
    log_path = $LogPath
    max_bytes = $MaxBytes
    keep = $Keep
    length_before = $lengthBefore
    length_after = $lengthAfter
    rotated_to = $rotatedTo
    removed = @($removed)
    actions = @($actions)
}
if ($Json) { $result | ConvertTo-Json -Depth 8 }
else {
    Write-Output 'forge_audit_log_rotation=ok'
    Write-Output "actions=$(@($actions) -join ',')"
    Write-Output "length_before=$lengthBefore"
    Write-Output "length_after=$lengthAfter"
    if ($rotatedTo) { Write-Output "rotated_to=$rotatedTo" }
}
exit 0
