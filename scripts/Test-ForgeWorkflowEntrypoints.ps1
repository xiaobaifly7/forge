[CmdletBinding()]
param(
    [string]$RepoPath = ".",
    [switch]$Json
)

$ErrorActionPreference = "Continue"
$RepoRoot = (Resolve-Path -LiteralPath $RepoPath).Path
$ClaudeRoot = Join-Path $env:USERPROFILE ".claude"
$CodexRoot = Join-Path $env:USERPROFILE ".codex"
$VendorRoot = Join-Path $ClaudeRoot "vendors\forge-upstreams"
$issues = [System.Collections.Generic.List[string]]::new()

function Add-Issue {
    param([string]$Code)
    if (-not $issues.Contains($Code)) { [void]$issues.Add($Code) }
}

function Test-AnyPath {
    param([string[]]$Paths)
    foreach ($path in @($Paths)) {
        if (-not [string]::IsNullOrWhiteSpace($path) -and (Test-Path -LiteralPath $path)) { return $true }
    }
    return $false
}

function Get-ExistingPaths {
    param([string[]]$Paths)
    $existing = @()
    foreach ($path in @($Paths)) {
        if (-not [string]::IsNullOrWhiteSpace($path) -and (Test-Path -LiteralPath $path)) {
            $existing += (Resolve-Path -LiteralPath $path).Path
        }
    }
    return @($existing)
}

function New-WorkflowResult {
    param(
        [string]$Name,
        [string]$Status,
        [string]$Policy,
        [string[]]$Evidence,
        [string]$Note = ""
    )
    [ordered]@{
        name = $Name
        status = $Status
        policy = $Policy
        evidence = @($Evidence)
        note = $Note
    }
}

$repoBmad = Join-Path $RepoRoot "_bmad"
$bmadStaging = Join-Path $ClaudeRoot "vendors\bmad-method-staging"
$bmadVendor = Join-Path $VendorRoot "bmad-method"
$bmadStatus = if (Test-Path -LiteralPath $repoBmad) { "active_repo_local" } elseif (Test-Path -LiteralPath $bmadStaging) { "staging_active" } elseif (Test-Path -LiteralPath $bmadVendor) { "vendor_only" } else { "missing" }
if ($bmadStatus -eq "missing") { Add-Issue "workflow_missing:bmad" }

$superpowersPaths = @(
    (Join-Path $CodexRoot "skills\using-superpowers"),
    (Join-Path $ClaudeRoot "skills\using-superpowers"),
    (Join-Path $ClaudeRoot "skills\brainstorming"),
    (Join-Path $ClaudeRoot "skills\verification-before-completion")
)
$superpowersStatus = if (Test-AnyPath $superpowersPaths) { "marketplace_active" } else { "missing" }
if ($superpowersStatus -eq "missing") { Add-Issue "workflow_missing:superpowers" }

$gstackActive = Join-Path $ClaudeRoot "skills\gstack"
$gstackDisabled = Join-Path $ClaudeRoot "skills\.gstack-disabled"
$gstackVendor = Join-Path $VendorRoot "gstack"
$gstackStatus = if (Test-Path -LiteralPath $gstackActive) { "active_global_skill" } elseif (Test-Path -LiteralPath $gstackDisabled) { "disabled_available" } elseif (Test-Path -LiteralPath $gstackVendor) { "vendor_only" } else { "missing" }
if ($gstackStatus -eq "missing") { Add-Issue "workflow_missing:gstack" }

$compoundGlobal = Get-ChildItem -LiteralPath (Join-Path $ClaudeRoot "skills") -Force -ErrorAction SilentlyContinue | Where-Object { $_.Name -match '^(ce-|compound)' } | Select-Object -First 1
$compoundVendor = Join-Path $VendorRoot "compound-engineering"
$compoundStatus = if ($compoundGlobal) { "active_global_skill" } elseif (Test-Path -LiteralPath $compoundVendor) { "vendor_only_manual_approval" } else { "optional_not_installed" }

$gsdGlobal = Get-ChildItem -LiteralPath (Join-Path $ClaudeRoot "skills") -Force -ErrorAction SilentlyContinue | Where-Object { $_.Name -match '^(gsd|gsd-2)' } | Select-Object -First 1
$gsdVendor = Join-Path $VendorRoot "gsd-2"
$gsdStatus = if ($gsdGlobal) { "active_global_skill" } elseif (Test-Path -LiteralPath $gsdVendor) { "vendor_only_manual_approval" } else { "optional_not_installed" }

$results = @(
    (New-WorkflowResult -Name "bmad" -Status $bmadStatus -Policy "staging_first" -Evidence (Get-ExistingPaths @($repoBmad, $bmadStaging, $bmadVendor)) -Note "L3/L4/full planning source"),
    (New-WorkflowResult -Name "superpowers" -Status $superpowersStatus -Policy "marketplace_managed" -Evidence (Get-ExistingPaths $superpowersPaths) -Note "execution, TDD, debugging, verification"),
    (New-WorkflowResult -Name "gstack" -Status $gstackStatus -Policy "gate_only_manual_toggle" -Evidence (Get-ExistingPaths @($gstackActive, $gstackDisabled, $gstackVendor)) -Note "review, QA, ship, canary, benchmark gate"),
    (New-WorkflowResult -Name "compound" -Status $compoundStatus -Policy "manual_approval" -Evidence (Get-ExistingPaths @($(if($compoundGlobal){$compoundGlobal.FullName}else{$null}), $compoundVendor)) -Note "optional high-value learnings and selected ce-* commands; install only after manual approval"),
    (New-WorkflowResult -Name "gsd" -Status $gsdStatus -Policy "manual_approval" -Evidence (Get-ExistingPaths @($(if($gsdGlobal){$gsdGlobal.FullName}else{$null}), $gsdVendor)) -Note "optional state handoff and next actions; install only after manual approval")
)

$blocking = @($results | Where-Object { $_.status -eq "missing" -and $_.name -in @("bmad", "superpowers") })
$result = [ordered]@{
    ok = ($blocking.Count -eq 0)
    repo = $RepoRoot
    checked_at = (Get-Date).ToString("o")
    workflows = @($results)
    issues = @($issues)
}

if ($Json) {
    $result | ConvertTo-Json -Depth 10
} else {
    if ($result.ok) { "forge_workflow_entrypoints=ok" } else { "forge_workflow_entrypoints=fail" }
    foreach ($workflow in $results) {
        "workflow=$($workflow.name) status=$($workflow.status) policy=$($workflow.policy)"
    }
    foreach ($issue in $issues) { "issue=$issue" }
}

if (-not $result.ok) { exit 1 }
