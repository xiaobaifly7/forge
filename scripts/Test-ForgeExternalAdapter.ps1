param(
    [ValidateSet("flow-kit", "trellis", "all")]
    [string]$Name = "all",
    [string]$RepoPath = ".",
    [ValidateSet("Audit", "Staging", "Apply")]
    [string]$Mode = "Audit",
    [string]$TargetRef = "",
    [switch]$Json
)

$ErrorActionPreference = "Stop"

function Get-PowerShellExecutable {
    $pwsh = Get-Command pwsh -ErrorAction SilentlyContinue
    if ($pwsh) { return $pwsh.Source }
    $windowsPowerShell = Get-Command powershell -ErrorAction SilentlyContinue
    if ($windowsPowerShell) { return $windowsPowerShell.Source }
    throw "No PowerShell executable found."
}

function Read-ExternalManifest {
    param([string]$AdapterName, [string]$RepoRoot)

    $path = Join-Path $RepoRoot ("adapters\external\" + $AdapterName + ".yaml")
    $manifest = [ordered]@{
        exists = (Test-Path -LiteralPath $path)
        path = $path
        upstream = $null
        pinned_ref = $null
        last_audited_ref = $null
        status = $null
        mode = $null
        absorbed_as = $null
        license = $null
    }

    if (-not $manifest.exists) { return $manifest }

    foreach ($line in Get-Content -LiteralPath $path -Encoding UTF8) {
        if ($line -match '^([A-Za-z_]+):\s*(.+?)\s*$') {
            $key = $matches[1]
            $value = $matches[2]
            if ($manifest.Contains($key)) { $manifest[$key] = $value }
        }
    }
    return $manifest
}

function Invoke-AdapterAudit {
    param(
        [string]$AdapterName,
        [string]$RepoPath,
        [string]$Mode,
        [string]$TargetRef,
        [string]$ScriptDir,
        [string]$ForgeRoot,
        [string]$PowerShellExe
    )

    $scriptMap = @{
        'flow-kit' = 'Test-ForgeFlowKitAdapter.ps1'
        'trellis' = 'Test-ForgeTrellisAdapter.ps1'
    }
    $scriptPath = Join-Path $ScriptDir $scriptMap[$AdapterName]
    $manifest = Read-ExternalManifest -AdapterName $AdapterName -RepoRoot $ForgeRoot

    if (-not (Test-Path -LiteralPath $scriptPath)) {
        return [ordered]@{
            name = $AdapterName
            ok = $false
            exit_code = 127
            manifest = $manifest
            result = $null
            issues = @("external_adapter_script_missing:$AdapterName")
        }
    }

    $args = @(
        '-NoProfile',
        '-ExecutionPolicy', 'Bypass',
        '-File', $scriptPath,
        '-RepoPath', $RepoPath,
        '-Mode', $Mode,
        '-Json'
    )
    if (-not [string]::IsNullOrWhiteSpace($TargetRef)) {
        $args += @('-TargetRef', $TargetRef)
    }

    $output = @(& $PowerShellExe @args 2>&1)
    $exitCode = $LASTEXITCODE
    $text = ($output | Out-String).Trim()
    $parsed = $null
    $issues = @()

    if (-not [string]::IsNullOrWhiteSpace($text)) {
        try {
            $parsed = $text | ConvertFrom-Json
            if ($parsed.issues) { $issues = @($parsed.issues) }
        } catch {
            $issues = @("external_adapter_json_parse_failed:$AdapterName")
        }
    }

    return [ordered]@{
        name = $AdapterName
        ok = ($exitCode -eq 0)
        exit_code = $exitCode
        manifest = $manifest
        result = $parsed
        raw_output = $(if ($parsed) { $null } else { $text })
        issues = @($issues)
    }
}

$scriptDir = Split-Path -Parent $PSCommandPath
$forgeRoot = Split-Path -Parent $scriptDir
$psExe = Get-PowerShellExecutable
$adapterNames = if ($Name -eq "all") { @("flow-kit", "trellis") } else { @($Name) }

$adapterResults = @()
$issues = [System.Collections.Generic.List[string]]::new()

foreach ($adapterName in $adapterNames) {
    $audit = Invoke-AdapterAudit -AdapterName $adapterName -RepoPath $RepoPath -Mode $Mode -TargetRef $TargetRef -ScriptDir $scriptDir -ForgeRoot $forgeRoot -PowerShellExe $psExe
    $adapterResults += $audit
    if (-not $audit.ok) {
        if (-not $issues.Contains("external_adapter_failed:$adapterName")) { [void]$issues.Add("external_adapter_failed:$adapterName") }
    }
    foreach ($issue in @($audit.issues)) {
        if (-not $issues.Contains($issue)) { [void]$issues.Add($issue) }
    }
}

$result = [ordered]@{
    ok = ($issues.Count -eq 0)
    mode = $Mode
    target_ref = $TargetRef
    repo_path = (Resolve-Path $RepoPath).Path
    adapters = @($adapterResults)
    issues = @($issues)
}

if ($Json) {
    $result | ConvertTo-Json -Depth 20
} else {
    if ($result.ok) { Write-Output "forge_external_adapters=ok" } else { Write-Output "forge_external_adapters=fail" }
    foreach ($adapter in $adapterResults) {
        $status = if ($adapter.result) { $adapter.result.status } else { "unknown" }
        Write-Output "adapter=$($adapter.name) status=$status exit_code=$($adapter.exit_code)"
    }
    foreach ($issue in $issues) { Write-Output "issue=$issue" }
}

if (-not $result.ok) { exit 1 }
exit 0
