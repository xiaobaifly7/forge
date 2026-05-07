param(
    [ValidateSet("flow-kit", "trellis")]
    [string]$Name,
    [string]$BaseRef = "",
    [string]$TargetRef = "",
    [string]$RepoPath = ".",
    [switch]$RecordBaseline,
    [switch]$Json
)

$ErrorActionPreference = "Stop"

function Read-Manifest {
    param([string]$Path)
    $map = [ordered]@{}
    if (-not (Test-Path -LiteralPath $Path)) { throw "manifest not found: $Path" }
    foreach ($line in Get-Content -LiteralPath $Path -Encoding UTF8) {
        if ($line -match '^([A-Za-z_]+):\s*(.+?)\s*$') {
            $map[$matches[1]] = $matches[2]
        }
    }
    return $map
}

function Set-ManifestValue {
    param(
        [string]$Path,
        [string]$Key,
        [string]$Value
    )
    $lines = @(Get-Content -LiteralPath $Path -Encoding UTF8)
    $updated = $false
    for ($i = 0; $i -lt $lines.Count; $i++) {
        if ($lines[$i] -match "^$([regex]::Escape($Key)):\s*") {
            $lines[$i] = "${Key}: $Value"
            $updated = $true
            break
        }
    }
    if (-not $updated) { $lines += "${Key}: $Value" }
    Set-Content -LiteralPath $Path -Encoding UTF8 -Value $lines
}

function Classify-TargetRef {
    param([string]$Value)
    if ([string]::IsNullOrWhiteSpace($Value)) { return "NO_IMPACT" }
    if ($Value -match '(?i)breaking|license|telemetry|hook|required-runtime|global-config') { return "BREAKING_CHANGE" }
    if ($Value -match '(?i)schema|stage|prompt|template|workflow|runtime|session|task-json|jsonl|go-md') { return "MAPPING_UPDATE_REQUIRED" }
    return "NO_IMPACT"
}

function Test-UsableRef {
    param([string]$Value)
    return (-not [string]::IsNullOrWhiteSpace($Value)) -and $Value -ne "manual-audit-required" -and $Value -ne "null"
}

function Invoke-Git {
    param(
        [string[]]$Arguments,
        [string]$WorkingDirectory = ""
    )
    $output = if ([string]::IsNullOrWhiteSpace($WorkingDirectory)) {
        & git @Arguments 2>&1
    } else {
        & git -C $WorkingDirectory @Arguments 2>&1
    }
    if ($LASTEXITCODE -ne 0) {
        throw "git $($Arguments -join ' ') failed: $($output -join "`n")"
    }
    return @($output)
}

function Resolve-RemoteRef {
    param(
        [string]$Upstream,
        [string]$Ref
    )
    if ($Ref -match '^[0-9a-fA-F]{40}$') { return $Ref.ToLowerInvariant() }
    $patterns = @($Ref)
    if ($Ref -notmatch '^refs/') {
        $patterns += "refs/heads/$Ref"
        $patterns += "refs/tags/$Ref"
    }
    foreach ($pattern in $patterns) {
        $lines = Invoke-Git -Arguments @("ls-remote", $Upstream, $pattern)
        foreach ($line in $lines) {
            if ($line -match '^([0-9a-fA-F]{40})\s+') { return $matches[1].ToLowerInvariant() }
        }
    }
    throw "Unable to resolve upstream ref '$Ref'"
}

function Get-UpstreamChangedFiles {
    param(
        [string]$Upstream,
        [string]$BaseSha,
        [string]$TargetSha
    )
    $tempRoot = Join-Path ([System.IO.Path]::GetTempPath()) ("forge-upstream-diff-" + [guid]::NewGuid().ToString("N"))
    New-Item -ItemType Directory -Force -Path $tempRoot | Out-Null
    try {
        Invoke-Git -WorkingDirectory $tempRoot -Arguments @("init", "-q") | Out-Null
        Invoke-Git -WorkingDirectory $tempRoot -Arguments @("remote", "add", "origin", $Upstream) | Out-Null
        Invoke-Git -WorkingDirectory $tempRoot -Arguments @("fetch", "--quiet", "--depth=1", "origin", $BaseSha) | Out-Null
        Invoke-Git -WorkingDirectory $tempRoot -Arguments @("fetch", "--quiet", "--depth=1", "origin", $TargetSha) | Out-Null
        $diff = Invoke-Git -WorkingDirectory $tempRoot -Arguments @("diff", "--name-status", $BaseSha, $TargetSha)
        $files = @()
        foreach ($line in $diff) {
            if ([string]::IsNullOrWhiteSpace($line)) { continue }
            $parts = $line -split "`t"
            $status = $parts[0]
            $path = if ($parts.Count -gt 2) { $parts[-1] } else { $parts[1] }
            $files += [ordered]@{ status = $status; path = $path }
        }
        return @($files)
    } finally {
        Remove-Item -Recurse -Force -LiteralPath $tempRoot -ErrorAction SilentlyContinue
    }
}

function Classify-ChangedFiles {
    param([object[]]$ChangedFiles)
    if ($ChangedFiles.Count -eq 0) { return "NO_IMPACT" }
    foreach ($file in $ChangedFiles) {
        $path = [string]$file.path
        if ($path -match '(?i)(^|/)(license|copying)(\.|$)' -or
            $path -match '(?i)(hook|telemetry|analytics|global-config|settings|\.claude|\.codex)' -or
            $path -match '(?i)(package\.json|pyproject\.toml|requirements\.txt|setup\.py|go\.mod)$') {
            return "BREAKING_CHANGE"
        }
    }
    foreach ($file in $ChangedFiles) {
        $path = [string]$file.path
        if ($path -match '(?i)(go\.md|workflow|stage|prompt|template|task\.json|prd\.md|info\.md|jsonl|\.trellis|spec|tasks|workspace)') {
            return "MAPPING_UPDATE_REQUIRED"
        }
    }
    return "NO_IMPACT"
}

$scriptDir = Split-Path -Parent $PSCommandPath
$forgeRoot = Split-Path -Parent $scriptDir
$manifestPath = Join-Path $forgeRoot ("adapters\external\" + $Name + ".yaml")
$manifest = Read-Manifest -Path $manifestPath
$effectiveBase = if (Test-UsableRef $BaseRef) { $BaseRef } elseif (Test-UsableRef ([string]$manifest.last_audited_ref)) { [string]$manifest.last_audited_ref } else { [string]$manifest.pinned_ref }
$effectiveTarget = if (Test-UsableRef $TargetRef) { $TargetRef } else { "HEAD" }
$diffAvailable = $false
$changedFiles = @()
$baseSha = ""
$targetSha = ""
$analysisType = "heuristic_target_ref_classifier"
$note = "Heuristic classifier. Review upstream diff before applying changes."
if (Test-UsableRef $effectiveBase) {
    $baseSha = Resolve-RemoteRef -Upstream ([string]$manifest.upstream) -Ref $effectiveBase
    $targetSha = Resolve-RemoteRef -Upstream ([string]$manifest.upstream) -Ref $effectiveTarget
    $changedFiles = @(Get-UpstreamChangedFiles -Upstream ([string]$manifest.upstream) -BaseSha $baseSha -TargetSha $targetSha)
    $classification = Classify-ChangedFiles -ChangedFiles $changedFiles
    $diffAvailable = $true
    $analysisType = "upstream_ref_diff"
    $note = "Read-only upstream diff. Review changed files before applying changes."
} else {
    $classification = "BASELINE_REQUIRED"
}
$requiresApply = ($classification -ne "NO_IMPACT")
$baselineRecorded = $false
if ($RecordBaseline) {
    if (-not $diffAvailable) { throw "Cannot record baseline without an upstream diff. Provide -BaseRef or set a real last_audited_ref first." }
    if ($classification -eq "BREAKING_CHANGE") { throw "Refusing to record BREAKING_CHANGE as audited baseline." }
    Set-ManifestValue -Path $manifestPath -Key "last_audited_ref" -Value $targetSha
    Set-ManifestValue -Path $manifestPath -Key "last_audited" -Value (Get-Date -Format o)
    $baselineRecorded = $true
}

$result = [ordered]@{
    ok = $true
    adapter = $Name
    repo_path = (Resolve-Path $RepoPath).Path
    manifest_path = $manifestPath
    upstream = $manifest.upstream
    pinned_ref = $manifest.pinned_ref
    base_ref = $effectiveBase
    base_sha = $baseSha
    target_ref = $effectiveTarget
    target_sha = $targetSha
    diff_available = $diffAvailable
    changed_files = @($changedFiles)
    analysis_type = $analysisType
    classification = $classification
    requires_adapter_update = $requiresApply
    baseline_recorded = $baselineRecorded
    note = $note
}

if ($Json) { $result | ConvertTo-Json -Depth 8 }
else {
    Write-Output "forge_external_adapter_compare=ok"
    Write-Output "adapter=$Name"
    Write-Output "analysis_type=$analysisType"
    Write-Output "classification=$classification"
    Write-Output "diff_available=$diffAvailable"
    Write-Output "changed_files=$(@($changedFiles).Count)"
    Write-Output "requires_adapter_update=$requiresApply"
    Write-Output "baseline_recorded=$baselineRecorded"
}

exit 0
