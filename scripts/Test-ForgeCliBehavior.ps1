[CmdletBinding()]
param(
    [string]$RepoPath = ".",
    [switch]$SkipFull
)

$ErrorActionPreference = "Stop"
$ScriptDir = Split-Path -Parent $PSCommandPath
$RepoRoot = (Resolve-Path -LiteralPath $RepoPath).Path
$Forge = Join-Path $ScriptDir "forge.ps1"
$failures = @()

function Invoke-Cli {
    param([string[]]$Arguments)
    $output = & pwsh -NoLogo -NoProfile -ExecutionPolicy Bypass -File $Forge @Arguments 2>&1
    return [ordered]@{
        exit_code = $LASTEXITCODE
        output = (@($output) | ForEach-Object { [string]$_ }) -join "`n"
    }
}

function Assert-Behavior {
    param(
        [string]$Name,
        [bool]$Ok,
        [string]$Details = ""
    )
    if ($Ok) {
        Write-Output "PASS $Name"
    } else {
        Write-Output "FAIL $Name -- $Details"
        $script:failures += $Name
    }
}

$version = Invoke-Cli -Arguments @("version", "-FixDrift")
Assert-Behavior -Name "version_fix_drift" -Ok ($version.exit_code -eq 0 -and $version.output -match "forge_source_drift=false" -and $version.output -match "forge_source_drift_fix=not_needed") -Details $version.output


$statusJson = Invoke-Cli -Arguments @("status", "-RepoPath", $RepoRoot, "-Json")
$statusParsed = $null
try { $statusParsed = $statusJson.output | ConvertFrom-Json } catch {}
Assert-Behavior -Name "status_json_is_clean" -Ok ($statusParsed -and $statusParsed.project.doctor_ok -and $statusParsed.project.verify_ok) -Details $statusJson.output

$reviewCurrentJson = Invoke-Cli -Arguments @("review-current", "-RepoPath", $RepoRoot, "-Json")
$reviewCurrentParsed = $null
try { $reviewCurrentParsed = $reviewCurrentJson.output | ConvertFrom-Json } catch {}
Assert-Behavior -Name "review_current_json_shape" -Ok ($reviewCurrentJson.exit_code -eq 0 -and $reviewCurrentParsed -and $reviewCurrentParsed.review_prompt -and $reviewCurrentParsed.plan.steps.Count -ge 1) -Details $reviewCurrentJson.output
$verifyJson = Invoke-Cli -Arguments @("verify", "-RepoPath", $RepoRoot, "-SkipSmoke", "-Json")
$parsed = $null
try { $parsed = $verifyJson.output | ConvertFrom-Json } catch {}
Assert-Behavior -Name "verify_json_is_clean" -Ok ($verifyJson.exit_code -eq 0 -and $parsed -and [bool]$parsed.ok) -Details $verifyJson.output

$verifyQuick = Invoke-Cli -Arguments @("verify", "-RepoPath", $RepoRoot)
Assert-Behavior -Name "verify_default_minimal_quick" -Ok ($verifyQuick.exit_code -eq 0 -and $verifyQuick.output -match "forge_smoke_mode=minimal" -and $verifyQuick.output -match "hook_gate_skipped=1") -Details $verifyQuick.output

$smokeQuick = Invoke-Cli -Arguments @("smoke", "-Quick")
Assert-Behavior -Name "smoke_quick_extended" -Ok ($smokeQuick.exit_code -eq 0 -and $smokeQuick.output -match "forge_smoke_mode=quick" -and $smokeQuick.output -match "m1_gate_skipped=1") -Details $smokeQuick.output

if (-not $SkipFull) {
    $verifyFull = Invoke-Cli -Arguments @("verify", "-RepoPath", $RepoRoot, "-Full")
    Assert-Behavior -Name "verify_full_smoke" -Ok ($verifyFull.exit_code -eq 0 -and $verifyFull.output -match "forge_smoke_mode=full" -and $verifyFull.output -match "m1_gate_passed=") -Details $verifyFull.output
}

if ($failures.Count -gt 0) {
    Write-Output "forge_cli_behavior=failed count=$($failures.Count)"
    exit 1
}

Write-Output "forge_cli_behavior=passed"
exit 0
