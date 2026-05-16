[CmdletBinding()]
param(
    [string]$GstackPath = "$env:USERPROFILE\.claude\vendors\forge-upstreams\gstack",
    [string]$PatchDir = "",
    [switch]$Json
)

$ErrorActionPreference = "Stop"

if (-not (Test-Path -LiteralPath $GstackPath)) {
    throw "Missing gstack vendor path: $GstackPath"
}

if ([string]::IsNullOrWhiteSpace($PatchDir)) {
    $PatchDir = Join-Path $GstackPath ".local-patches"
}

New-Item -ItemType Directory -Path $PatchDir -Force | Out-Null

$patchPath = Join-Path $PatchDir "gstack-local-text.patch"
$binaryPath = Join-Path $PatchDir "gstack-local-binary.json"
$statusPath = Join-Path $PatchDir "gstack-local-status.txt"

$diff = & rtk git -C $GstackPath diff -- . 2>&1
$diffText = (@($diff) | Where-Object { [string]$_ -ne "ok" } | ForEach-Object { [string]$_ }) -join "`n"
Set-Content -LiteralPath $patchPath -Value $diffText -Encoding UTF8

$status = & rtk git -C $GstackPath status --short --branch 2>&1
$statusText = (@($status) | Where-Object { [string]$_ -ne "ok" } | ForEach-Object { [string]$_ }) -join "`n"
Set-Content -LiteralPath $statusPath -Value $statusText -Encoding UTF8

$binaryRel = "bin/gstack-global-discover.exe"
$binaryFull = Join-Path $GstackPath $binaryRel
$binary = [ordered]@{
    path = $binaryRel
    exists = (Test-Path -LiteralPath $binaryFull)
    length = $null
    sha256 = $null
}
if ($binary.exists) {
    $item = Get-Item -LiteralPath $binaryFull
    $binary.length = $item.Length
    $binary.sha256 = (Get-FileHash -LiteralPath $binaryFull -Algorithm SHA256).Hash
}
$binary | ConvertTo-Json -Depth 4 | Set-Content -LiteralPath $binaryPath -Encoding UTF8

$result = [ordered]@{
    ok = $true
    gstack_path = (Resolve-Path -LiteralPath $GstackPath).Path
    patch_dir = (Resolve-Path -LiteralPath $PatchDir).Path
    patch_path = $patchPath
    patch_bytes = (Get-Item -LiteralPath $patchPath).Length
    meta_path = $binaryPath
    status_path = $statusPath
    binary = $binary
}

if ($Json) {
    $result | ConvertTo-Json -Depth 8
} else {
    "gstack_local_patches_exported=ok"
    "patch_path=$patchPath"
    "status_path=$statusPath"
    "binary_sha256=$($binary.sha256)"
}
