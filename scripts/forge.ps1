[CmdletBinding()]
param(
    [Parameter(Position = 0)]
    [ValidateSet("doctor", "task", "verify", "smoke", "install", "sync-all", "projects", "workflows", "version", "help")]
    [string]$Command = "help",

    [Parameter(Position = 1)]
    [string]$Subcommand = "",

    [string]$RepoPath = ".",
    [string]$Title = "",
    [string]$Name = "",
    [string]$PrNumber = "",
    [switch]$Json,
    [switch]$SkipSmoke,
    [switch]$Full,
    [switch]$Quick,
    [switch]$FixDrift,
    [switch]$Apply,
    [string]$RegistryPath = "",
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
    Write-Output "  forge verify [-RepoPath .] [-PrNumber 1] [-SkipSmoke] [-Full] [-Json]"
    Write-Output "  forge smoke [-RepoPath .] [-Quick]"
    Write-Output "  forge install -RepoPath <repo>"
    Write-Output "  forge sync-all [-RepoPath <repo>] [-SearchRoot <dir>] [-RegistryPath <file>] [-Apply] [-Json]"
    Write-Output "  forge workflows [-RepoPath .] [-Json]"
    Write-Output "  forge version [-FixDrift]"
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
        if ($Full) { $args += "-Full" }
        if ($Json) { $args += "-Json" }
        Invoke-ForgeScript -Name "Test-ForgeReleaseReadiness.ps1" -Arguments $args
    }
    "smoke" {
        $args = @("-NoLog", "-SkipReleaseReadiness")
        if ($Quick) { $args += "-Quick" }
        Invoke-ForgeScript -Name "forge-smoke.ps1" -Arguments $args
    }
    "install" {
        Invoke-ForgeScript -Name "Install-ForgeLocal.ps1" -Arguments @("-RepoPath", $RepoPath)
    }
    "sync-all" {
        $args = @()
        if (-not [string]::IsNullOrWhiteSpace($RepoPath) -and $RepoPath -ne ".") { $args += @("-RepoPath", $RepoPath) }
        foreach ($root in @($SearchRoot)) { if (-not [string]::IsNullOrWhiteSpace($root)) { $args += @("-SearchRoot", $root) } }
        if (-not [string]::IsNullOrWhiteSpace($RegistryPath)) { $args += @("-RegistryPath", $RegistryPath) }
        if ($Apply) { $args += "-Apply" }
        if ($Json) { $args += "-Json" }
        Invoke-ForgeScript -Name "Sync-ForgeProjects.ps1" -Arguments $args
    }
    "projects" {
        $args = @($Subcommand)
        if (-not [string]::IsNullOrWhiteSpace($RepoPath) -and $RepoPath -ne ".") { $args += @("-RepoPath", $RepoPath) }
        if (-not [string]::IsNullOrWhiteSpace($Name)) { $args += @("-Name", $Name) }
        if (-not [string]::IsNullOrWhiteSpace($RegistryPath)) { $args += @("-RegistryPath", $RegistryPath) }
        if ($Json) { $args += "-Json" }
        Invoke-ForgeScript -Name "Manage-ForgeProjects.ps1" -Arguments $args
    }
    "workflows" {
        $args = @("-RepoPath", $RepoPath)
        if ($Json) { $args += "-Json" }
        Invoke-ForgeScript -Name "Test-ForgeWorkflowEntrypoints.ps1" -Arguments $args
    }
    "version" {
        Write-Output "forge_repo=$RepoRoot"
        Write-Output "forge_installed_script=$PSCommandPath"
        $versionPath = Join-Path $RepoRoot "version.json"
        $sourceInfo = @{}
        if (-not (Test-Path -LiteralPath $versionPath)) {
            $sourcePathCandidates = @(
                (Join-Path $env:USERPROFILE ".claude\forge-source.txt"),
                (Join-Path $env:USERPROFILE ".codex\forge-source.txt")
            )
            foreach ($sourcePathForVersion in $sourcePathCandidates) {
                if (-not (Test-Path -LiteralPath $sourcePathForVersion)) { continue }
                foreach ($line in Get-Content -LiteralPath $sourcePathForVersion -Encoding UTF8) {
                    if ($line -match '^forge_source_repo=(.+)$') {
                        $candidateVersionPath = Join-Path $Matches[1] "version.json"
                        if (Test-Path -LiteralPath $candidateVersionPath) { $versionPath = $candidateVersionPath; break }
                    }
                }
                if (Test-Path -LiteralPath $versionPath) { break }
            }
        }
        if (Test-Path -LiteralPath $versionPath) {
            try {
                $versionInfo = Get-Content -LiteralPath $versionPath -Raw -Encoding UTF8 | ConvertFrom-Json
                Write-Output "forge_version=$($versionInfo.version)"
                Write-Output "forge_channel=$($versionInfo.channel)"
            } catch {}
        }
        try {
            $sha = & git -C $RepoRoot rev-parse --short HEAD 2>$null
            if ($LASTEXITCODE -eq 0 -and $sha) { Write-Output "forge_commit=$sha" }
        } catch {}
        $sourcePath = @(Join-Path $env:USERPROFILE ".claude\forge-source.txt"; Join-Path $env:USERPROFILE ".codex\forge-source.txt") | Where-Object { Test-Path -LiteralPath $_ } | Select-Object -First 1
        if (Test-Path -LiteralPath $sourcePath) {
            foreach ($line in Get-Content -LiteralPath $sourcePath -Encoding UTF8) {
                Write-Output $line
                if ($line -match '^([^=]+)=(.*)$') {
                    $sourceInfo[$Matches[1]] = $Matches[2]
                }
            }
        }
        if ($sourceInfo.ContainsKey("forge_source_repo")) {
            $sourceRepo = $sourceInfo["forge_source_repo"]
            try {
                $sourceHead = & git -C $sourceRepo rev-parse --short HEAD 2>$null
                if ($LASTEXITCODE -eq 0 -and $sourceHead) {
                    Write-Output "forge_source_current_commit=$sourceHead"
                    if ($sourceInfo.ContainsKey("forge_source_commit")) {
                        $drift = ([string]$sourceInfo["forge_source_commit"] -ne [string]$sourceHead)
                        Write-Output "forge_source_drift=$($drift.ToString().ToLowerInvariant())"
                        if ($drift) {
                            Write-Output "forge_source_drift_hint=run forge install -RepoPath `"$sourceRepo`""
                            if ($FixDrift) {
                                $installScript = Join-Path $sourceRepo "scripts\Install-ForgeLocal.ps1"
                                if (Test-Path -LiteralPath $installScript) {
                                    Write-Output "forge_source_drift_fix=installing"
                                    & pwsh -NoLogo -NoProfile -ExecutionPolicy Bypass -File $installScript -RepoPath $sourceRepo
                                    exit $LASTEXITCODE
                                } else {
                                    Write-Output "forge_source_drift_fix=missing_install_script"
                                }
                            }
                        } elseif ($FixDrift) {
                            Write-Output "forge_source_drift_fix=not_needed"
                        }
                    }
                }
            } catch {}
        }
    }
    default {
        Show-ForgeHelp
    }
}
