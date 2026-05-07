param(
    [string]$RepoPath = ".",
    [ValidateSet("frontend", "backend", "security", "testing", "review", "debugging", "conventions", "guides")]
    [string]$Category = "guides",
    [Parameter(Mandatory = $true)][string]$Title,
    [Parameter(Mandatory = $true)][string]$Summary,
    [string]$TaskPath = "",
    [string]$Prevention = "",
    [string]$Source = "",
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

function Convert-ToSlug {
    param([string]$Value)
    $slug = $Value.ToLowerInvariant() -replace '[^a-z0-9]+', '-'
    $slug = $slug.Trim('-')
    if ([string]::IsNullOrWhiteSpace($slug)) {
        $bytes = [System.Text.Encoding]::UTF8.GetBytes($Value)
        $hash = [System.BitConverter]::ToString([System.Security.Cryptography.SHA256]::HashData($bytes)).Replace('-', '').Substring(0, 8).ToLowerInvariant()
        $slug = "finding-$hash"
    }
    return $slug
}

$repoRoot = Resolve-RepoRoot -Path $RepoPath
$categoryDir = Join-Path $repoRoot (".forge\spec\" + $Category)
New-Item -ItemType Directory -Force -Path $categoryDir | Out-Null

$date = Get-Date -Format "yyyy-MM-dd"
$slug = Convert-ToSlug $Title
$findingPath = Join-Path $categoryDir ($date + "-" + $slug + ".md")
$historyDir = Join-Path $categoryDir ".history"
$preventionText = if ([string]::IsNullOrWhiteSpace($Prevention)) { "TODO: define prevention mechanism." } else { $Prevention }
$sourceText = if ([string]::IsNullOrWhiteSpace($Source)) { "manual" } else { $Source }
$taskText = if ([string]::IsNullOrWhiteSpace($TaskPath)) { "none" } else { $TaskPath }

$content = @"
# $Title

## Summary

$Summary

## Prevention

$preventionText

## Metadata

- category: $Category
- task: $taskText
- source: $sourceText
- created_at: $(Get-Date -Format o)
"@

if (Test-Path -LiteralPath $findingPath) {
    New-Item -ItemType Directory -Force -Path $historyDir | Out-Null
    $revision = Get-Date -Format "HHmmss"
    $historyPath = Join-Path $historyDir ($date + "-" + $slug + "-" + $revision + ".md")
    Copy-Item -LiteralPath $findingPath -Destination $historyPath -Force
}
Set-Content -LiteralPath $findingPath -Encoding UTF8 -Value $content

$indexPath = Join-Path $categoryDir "index.md"
if (-not (Test-Path -LiteralPath $indexPath)) {
    Set-Content -LiteralPath $indexPath -Encoding UTF8 -Value "# $Category Spec`n"
}
$relativeFinding = ".forge/spec/$Category/" + (Split-Path $findingPath -Leaf)
$indexLine = "- [$Title]($relativeFinding): $Summary"
$existingIndex = Get-Content -LiteralPath $indexPath -Raw -Encoding UTF8
if ($existingIndex -notmatch [regex]::Escape($relativeFinding)) {
    Add-Content -LiteralPath $indexPath -Encoding UTF8 -Value $indexLine
}

$result = [ordered]@{
    ok = $true
    repo_root = $repoRoot
    category = $Category
    finding_path = $findingPath
    index_path = $indexPath
    history_dir = $historyDir
}

if ($Json) { $result | ConvertTo-Json -Depth 8 }
else {
    Write-Output "forge_spec_finding=ok"
    Write-Output "category=$Category"
    Write-Output "finding_path=$findingPath"
}

exit 0
