[CmdletBinding()]
param(
    [Parameter(Position = 0)]
    [ValidateSet("doctor", "task", "verify", "smoke", "install", "sync-all", "version", "help")]
    [string]$Command = "help",

    [Parameter(Position = 1)]
    [string]$Subcommand = "",

    [string]$RepoPath = ".",
    [string]$Title = "",
    [string]$Name = "",
    [string]$PrNumber = "",
    [switch]$Json,
    [switch]$SkipSmoke,
    [switch]$Apply,
    [string[]]$SearchRoot = @(),
    [Parameter(ValueFromRemainingArguments = $true)]
    [string[]]$RemainingArgs
)

$ErrorActionPreference = "Stop"
$ScriptDir = Split-Path -Parent $PSCommandPath
$RepoRoot = Split-Path -Parent $ScriptDir

function Show-ForgeHelp {
    Write-Output "Forge CLI"
    Write-Output ""
    Write-Output "Usage:"
    Write-Output "  forge doctor [-RepoPath .] [-Json]"
    Write-Output "  forge task new -Title `"Fix bug`" [-Name task-slug] [-RepoPath .] [-Json]"
    Write-Output "  forge verify [-RepoPath .] [-PrNumber 1] [-SkipSmoke] [-Json]"
    Write-Output "  forge smoke [-RepoPath .]"
    Write-Output "  forge install -RepoPath <repo>"
    Write-Output "  forge sync-all [-RepoPath <repo>] [-SearchRoot <dir>] [-Apply] [-Json]"
    Write-Output "  forge version"
}

function Invoke-ForgeScript {
    param(
        [string]$Name,
        [string[]]$Arguments
    )
    & pwsh -NoLogo -NoProfile -ExecutionPolicy Bypass -File (Join-Path $ScriptDir $Name) @Arguments
    exit $LASTEXITCODE
}

switch ($Command) {
    "doctor" {
        $args = @("-Mode", "Quick", "-RepoPath", $RepoPath)
        if ($Json) { $args += "-Json" }
        Invoke-ForgeScript -Name "Invoke-ForgeHealth.ps1" -Arguments $args
    }
    "task" {
        if ($Subcommand -ne "new") {
            throw "Unsupported task command. Use: forge task new -Title `"Fix bug`""
        }
        if ([string]::IsNullOrWhiteSpace($Title)) {
            throw "Missing -Title for forge task new."
        }
        $taskName = $Name
        if ([string]::IsNullOrWhiteSpace($taskName)) {
            $slug = $Title.ToLowerInvariant() -replace '[^a-z0-9]+', '-'
            $slug = $slug.Trim('-')
            if ([string]::IsNullOrWhiteSpace($slug)) {
                $bytes = [System.Text.Encoding]::UTF8.GetBytes($Title)
                $hash = [System.BitConverter]::ToString([System.Security.Cryptography.SHA256]::HashData($bytes)).Replace('-', '').Substring(0, 8).ToLowerInvariant()
                $slug = "task-$hash"
            }
            $taskName = $slug
        }
        $args = @("-RepoPath", $RepoPath, "-Name", $taskName, "-Title", $Title)
        if ($Json) { $args += "-Json" }
        Invoke-ForgeScript -Name "New-ForgeTask.ps1" -Arguments $args
    }
    "verify" {
        $args = @("-RepoPath", $RepoPath)
        if (-not [string]::IsNullOrWhiteSpace($PrNumber)) { $args += @("-PrNumber", $PrNumber) }
        if ($SkipSmoke) { $args += "-SkipSmoke" }
        if ($Json) { $args += "-Json" }
        Invoke-ForgeScript -Name "Test-ForgeReleaseReadiness.ps1" -Arguments $args
    }
    "smoke" {
        Invoke-ForgeScript -Name "forge-smoke.ps1" -Arguments @("-NoLog", "-SkipReleaseReadiness")
    }
    "install" {
        Invoke-ForgeScript -Name "Install-ForgeLocal.ps1" -Arguments @("-RepoPath", $RepoPath)
    }
    "sync-all" {
        $args = @()
        if (-not [string]::IsNullOrWhiteSpace($RepoPath)) { $args += @("-RepoPath", $RepoPath) }
        foreach ($root in @($SearchRoot)) { if (-not [string]::IsNullOrWhiteSpace($root)) { $args += @("-SearchRoot", $root) } }
        if ($Apply) { $args += "-Apply" }
        if ($Json) { $args += "-Json" }
        Invoke-ForgeScript -Name "Sync-ForgeProjects.ps1" -Arguments $args
    }
    "version" {
        Write-Output "forge_repo=$RepoRoot"
        Write-Output "forge_installed_script=$PSCommandPath"
        try {
            $sha = & git -C $RepoRoot rev-parse --short HEAD 2>$null
            if ($LASTEXITCODE -eq 0 -and $sha) { Write-Output "forge_commit=$sha" }
        } catch {}
        $sourcePath = Join-Path $env:USERPROFILE ".claude\forge-source.txt"
        if (Test-Path -LiteralPath $sourcePath) {
            Get-Content -LiteralPath $sourcePath -Encoding UTF8
        }
    }
    default {
        Show-ForgeHelp
    }
}
