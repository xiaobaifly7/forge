param(
    [string]$RepoPath = ".",
    [Parameter(Mandatory = $true)][string]$TaskPath,
    [ValidateSet("implement", "check", "both", "list")]
    [string]$Target = "implement",
    [string]$File = "",
    [string]$Reason = "",
    [switch]$Remove,
    [switch]$Json
)

$ErrorActionPreference = "Stop"

function Resolve-RepoRoot {
    param([string]$Path)
    $resolved = (Resolve-Path $Path).Path
    if (Test-Path -LiteralPath (Join-Path $resolved ".forge")) { return $resolved }
    try {
        $gitRoot = git -C $Path rev-parse --show-toplevel 2>$null
        if ($LASTEXITCODE -eq 0 -and $gitRoot) { return (Resolve-Path $gitRoot).Path }
    } catch {}
    return $resolved
}

function ConvertTo-ForgeRelativePath {
    param(
        [string]$RepoRoot,
        [string]$RelativePath,
        [string]$Label = "Context path"
    )
    $normalized = $RelativePath -replace '/', '\'
    $candidate = if ([System.IO.Path]::IsPathRooted($normalized)) {
        [System.IO.Path]::GetFullPath($normalized)
    } else {
        [System.IO.Path]::GetFullPath((Join-Path $RepoRoot $normalized))
    }
    $forgeRoot = [System.IO.Path]::GetFullPath((Join-Path $RepoRoot ".forge")).TrimEnd('\', '/')
    $forgeRootPrefix = $forgeRoot + [System.IO.Path]::DirectorySeparatorChar
    if (-not $candidate.StartsWith($forgeRootPrefix, [System.StringComparison]::OrdinalIgnoreCase)) {
        throw "$Label must be under .forge\\: $RelativePath"
    }
    return ([System.IO.Path]::GetRelativePath($RepoRoot, $candidate) -replace '/', '\')
}

function ConvertTo-TaskRelativePath {
    param(
        [string]$RepoRoot,
        [string]$TaskPath
    )
    $relative = ConvertTo-ForgeRelativePath -RepoRoot $RepoRoot -RelativePath $TaskPath -Label "TaskPath"
    if ($relative -notmatch '^\.forge\\tasks\\') {
        throw "TaskPath must be under .forge\\tasks\\."
    }
    return $relative
}

function Read-ContextFile {
    param([string]$Path)
    $entries = @()
    if (-not (Test-Path -LiteralPath $Path)) { return @($entries) }
    foreach ($line in Get-Content -LiteralPath $Path -Encoding UTF8) {
        if ([string]::IsNullOrWhiteSpace($line)) { continue }
        try {
            $entry = $line | ConvertFrom-Json
            if ($entry.PSObject.Properties.Name -contains "_example") { continue }
            if ($entry.PSObject.Properties.Name -contains "file") { $entries += $entry }
        } catch {
            throw "Invalid JSONL in $Path"
        }
    }
    return @($entries)
}

function Write-ContextFile {
    param([string]$Path, [object[]]$Entries)
    $lines = @()
    foreach ($entry in $Entries) {
        $lines += ([ordered]@{ file = [string]$entry.file; reason = [string]$entry.reason } | ConvertTo-Json -Compress)
    }
    if ($lines.Count -eq 0) {
        $lines += ([ordered]@{ _example = 'Fill with {"file":"<.forge/spec-or-research-path>","reason":"<why>"}. Keep context under .forge only.' } | ConvertTo-Json -Compress)
    }
    Set-Content -LiteralPath $Path -Encoding UTF8 -Value $lines
}

function Update-OneTarget {
    param(
        [string]$TaskDir,
        [string]$TargetName,
        [string]$ContextFile,
        [string]$ReasonText,
        [bool]$RemoveEntry
    )
    $path = Join-Path $TaskDir ($TargetName + ".jsonl")
    $entries = @(Read-ContextFile -Path $path)
    $before = $entries.Count

    if ($RemoveEntry) {
        $entries = @($entries | Where-Object { (([string]$_.file) -replace '/', '\') -ne $ContextFile })
    } else {
        $exists = @($entries | Where-Object { (([string]$_.file) -replace '/', '\') -eq $ContextFile }).Count -gt 0
        if (-not $exists) {
            $entries += [pscustomobject]@{ file = $ContextFile; reason = $ReasonText }
        }
    }

    Write-ContextFile -Path $path -Entries $entries
    return [ordered]@{ target = $TargetName; path = $path; before = $before; after = $entries.Count }
}

$repoRoot = Resolve-RepoRoot -Path $RepoPath
$normalizedTaskPath = ConvertTo-TaskRelativePath -RepoRoot $repoRoot -TaskPath $TaskPath
$taskDir = Join-Path $repoRoot $normalizedTaskPath
if (-not (Test-Path -LiteralPath $taskDir)) { throw "TaskPath does not exist: $normalizedTaskPath" }

$results = @()
if ($Target -eq "list") {
    foreach ($targetName in @("implement", "check")) {
        $path = Join-Path $taskDir ($targetName + ".jsonl")
        $entries = @(Read-ContextFile -Path $path)
        $results += [ordered]@{ target = $targetName; path = $path; entries = @($entries) }
    }
} else {
    if ([string]::IsNullOrWhiteSpace($File)) { throw "-File is required unless -Target list is used." }
    if ([string]::IsNullOrWhiteSpace($Reason) -and -not $Remove) { throw "-Reason is required when adding context." }
    $contextFile = ConvertTo-ForgeRelativePath -RepoRoot $repoRoot -RelativePath $File
    if (-not (Test-Path -LiteralPath (Join-Path $repoRoot $contextFile))) {
        throw "Context file does not exist: $contextFile"
    }
    $targets = if ($Target -eq "both") { @("implement", "check") } else { @($Target) }
    foreach ($targetName in $targets) {
        $results += Update-OneTarget -TaskDir $taskDir -TargetName $targetName -ContextFile $contextFile -ReasonText $Reason -RemoveEntry ([bool]$Remove)
    }
}

$result = [ordered]@{
    ok = $true
    repo_root = $repoRoot
    task_path = $normalizedTaskPath
    operation = $(if ($Target -eq "list") { "list" } elseif ($Remove) { "remove" } else { "add" })
    results = @($results)
}

if ($Json) { $result | ConvertTo-Json -Depth 12 }
else {
    Write-Output "forge_task_context=ok"
    Write-Output "operation=$($result.operation)"
    foreach ($item in $results) {
        if ($Target -eq "list") { Write-Output "target=$($item.target) entries=$(@($item.entries).Count)" }
        else { Write-Output "target=$($item.target) before=$($item.before) after=$($item.after)" }
    }
}

exit 0
