param(
    [string]$ClaudeRoot = "C:\Users\Administrator\.claude",
    [switch]$Json
)

$ErrorActionPreference = "Stop"

function Add-Issue {
    param([System.Collections.Generic.List[string]]$Issues, [string]$Code)
    if (-not $Issues.Contains($Code)) { [void]$Issues.Add($Code) }
}

function Read-Text {
    param([string]$Path)
    return Get-Content -Raw -LiteralPath $Path -Encoding UTF8
}

function Test-FrontMatter {
    param([string]$Path, [System.Collections.Generic.List[string]]$Issues, [string]$IssuePrefix)

    if (-not (Test-Path -LiteralPath $Path)) {
        Add-Issue $Issues "$IssuePrefix`_missing"
        return
    }

    $lines = Get-Content -LiteralPath $Path -Encoding UTF8
    if ($lines.Count -lt 3 -or $lines[0] -ne "---") {
        Add-Issue $Issues "$IssuePrefix`_frontmatter_missing_start"
        return
    }

    $end = -1
    for ($i = 1; $i -lt [Math]::Min($lines.Count, 40); $i++) {
        if ($lines[$i] -eq "---") {
            $end = $i
            break
        }
    }
    if ($end -lt 1) {
        Add-Issue $Issues "$IssuePrefix`_frontmatter_missing_end"
    }
}

function Test-Contains {
    param(
        [string]$Text,
        [string]$Pattern,
        [System.Collections.Generic.List[string]]$Issues,
        [string]$Code
    )
    if ($Text -notmatch $Pattern) { Add-Issue $Issues $Code }
}

function Test-NotContains {
    param(
        [string]$Text,
        [string]$Pattern,
        [System.Collections.Generic.List[string]]$Issues,
        [string]$Code
    )
    if ($Text -match $Pattern) { Add-Issue $Issues $Code }
}

$root = (Resolve-Path -LiteralPath $ClaudeRoot).Path
$issues = [System.Collections.Generic.List[string]]::new()

$paths = [ordered]@{
    forge_command = "commands\forge.md"
    forge_adopt_command = "commands\forge-adopt.md"
    gstack_toggle_command = "commands\gstack-toggle.md"
    forge_skill = "skills\forge\SKILL.md"
    protocols = "docs\forge-protocols.md"
    boundary = "docs\forge-workflow-boundary.md"
    schema_versions = "docs\forge-schema-versions.md"
}

$resolved = [ordered]@{}
foreach ($key in $paths.Keys) {
    $path = Join-Path $root $paths[$key]
    $resolved[$key] = $path
    if (-not (Test-Path -LiteralPath $path)) {
        Add-Issue $issues "$key`_missing"
    }
}

Test-FrontMatter -Path $resolved.forge_command -Issues $issues -IssuePrefix "forge_command"
Test-FrontMatter -Path $resolved.forge_adopt_command -Issues $issues -IssuePrefix "forge_adopt_command"
Test-FrontMatter -Path $resolved.forge_skill -Issues $issues -IssuePrefix "forge_skill"

$texts = @{}
foreach ($key in $resolved.Keys) {
    if (Test-Path -LiteralPath $resolved[$key]) {
        $texts[$key] = Read-Text $resolved[$key]
    } else {
        $texts[$key] = ""
    }
}

$coreText = @(
    $texts.forge_command,
    $texts.forge_adopt_command,
    $texts.forge_skill,
    $texts.protocols,
    $texts.boundary,
    $texts.schema_versions
) -join "`n"

Test-NotContains -Text $coreText -Pattern "/forge-init|/forge-bmad-init" -Issues $issues -Code "dead_forge_init_reference"

Test-Contains -Text $texts.forge_command -Pattern "路由入口|路由器" -Issues $issues -Code "forge_command_not_router"
Test-Contains -Text $texts.forge_command -Pattern "/forge-adopt" -Issues $issues -Code "forge_command_missing_adopt_pointer"
Test-NotContains -Text $texts.forge_command -Pattern "forge-project-precheck\.ps1|install-bmad-local\.ps1|init-project-profile\.ps1|write-forge-routing\.ps1" -Issues $issues -Code "forge_command_contains_adoption_script"

Test-Contains -Text $texts.forge_adopt_command -Pattern "forge-project-precheck\.ps1" -Issues $issues -Code "forge_adopt_missing_precheck"
Test-Contains -Text $texts.forge_adopt_command -Pattern "init-project-profile\.ps1" -Issues $issues -Code "forge_adopt_missing_init"
Test-Contains -Text $texts.forge_adopt_command -Pattern "install-bmad-local\.ps1" -Issues $issues -Code "forge_adopt_missing_bmad_init"

Test-Contains -Text $texts.forge_skill -Pattern "forge-workflow-boundary\.md" -Issues $issues -Code "forge_skill_missing_boundary_reference"
Test-Contains -Text $texts.protocols -Pattern "边界真源|forge-workflow-boundary\.md" -Issues $issues -Code "protocols_missing_boundary_reference"
Test-Contains -Text $texts.protocols -Pattern "M1\s+仅在|L4.*full/guided-full" -Issues $issues -Code "protocols_missing_m1_l4_only"
Test-Contains -Text $texts.boundary -Pattern "Compound Engineering 白名单" -Issues $issues -Code "boundary_missing_ce_whitelist"
Test-Contains -Text $texts.boundary -Pattern "项目适配分层" -Issues $issues -Code "boundary_missing_project_tiers"
Test-Contains -Text $texts.schema_versions -Pattern "project-profile\.json.*\|\s*3" -Issues $issues -Code "schema_versions_missing_profile_v3"
Test-Contains -Text $texts.schema_versions -Pattern "forge-session-state\.json.*\|\s*1" -Issues $issues -Code "schema_versions_missing_session_v1"
Test-Contains -Text $texts.schema_versions -Pattern '"is_drill"\s*:\s*true|is_drill=true' -Issues $issues -Code "schema_versions_missing_drill_marker"

Test-Contains -Text $texts.protocols -Pattern "Mode fail-close|fail-close" -Issues $issues -Code "protocols_missing_fail_close"
Test-Contains -Text $texts.protocols -Pattern "LiveClaudeRoute" -Issues $issues -Code "protocols_missing_live_route"
Test-Contains -Text $texts.protocols -Pattern "Resolve-ForgeExecutionMode\.ps1" -Issues $issues -Code "protocols_missing_execution_router"
Test-Contains -Text $texts.protocols -Pattern "execution=<guided-full\|auto\|audit-only\|full-auto>" -Issues $issues -Code "protocols_missing_execution_output_contract"
Test-Contains -Text $texts.forge_skill -Pattern "显式.*guide.*auto|Resolve-ForgeExecutionMode" -Issues $issues -Code "forge_skill_missing_execution_router_rule"
Test-Contains -Text $texts.protocols -Pattern "Test-ForgeLiveRouteFreshness\.ps1" -Issues $issues -Code "protocols_missing_live_freshness_script"
Test-Contains -Text $texts.protocols -Pattern "Reset-ForgeSessionState\.ps1" -Issues $issues -Code "protocols_missing_reset_session_script"
Test-Contains -Text $texts.protocols -Pattern "Rotate-ForgeAuditLogs\.ps1" -Issues $issues -Code "protocols_missing_rotate_audit_script"
Test-Contains -Text $texts.protocols -Pattern "Test-ForgeWorkspaceManifest\.ps1" -Issues $issues -Code "protocols_missing_workspace_manifest_script"
Test-Contains -Text $texts.protocols -Pattern "LOCAL-PATCHES\.md" -Issues $issues -Code "protocols_missing_gstack_local_patches"
Test-Contains -Text $texts.protocols -Pattern "Invoke-ForgeHealth\.ps1" -Issues $issues -Code "protocols_missing_forge_health_script"
Test-Contains -Text $texts.protocols -Pattern "Test-ForgeUpstreams\.ps1" -Issues $issues -Code "protocols_missing_upstreams_script"
Test-Contains -Text $texts.protocols -Pattern "Test-GstackLocalPatches\.ps1" -Issues $issues -Code "protocols_missing_gstack_patches_script"
Test-Contains -Text $texts.protocols -Pattern "Export-GstackLocalPatches\.ps1" -Issues $issues -Code "protocols_missing_gstack_export_script"
Test-Contains -Text $texts.protocols -Pattern "Invoke-ForgeHealth\.ps1 -Mode Offline|日常入口收敛" -Issues $issues -Code "protocols_missing_single_health_entrypoint"
Test-Contains -Text $texts.protocols -Pattern "settings_gate_total|settings_gate_failed" -Issues $issues -Code "protocols_missing_settings_gate_docs"
Test-Contains -Text $texts.protocols -Pattern "quick/fix/build/full/ship" -Issues $issues -Code "protocols_missing_live_route_coverage"
Test-Contains -Text $texts.protocols -Pattern "真实调用 Claude Code|产生成本|默认 smoke 不运行 live route" -Issues $issues -Code "protocols_missing_live_route_cost_warning"
Test-Contains -Text $texts.protocols -Pattern "AllOpenGroups" -Issues $issues -Code "protocols_missing_all_open_groups"
Test-Contains -Text $texts.schema_versions -Pattern "effective_severity" -Issues $issues -Code "schema_versions_missing_audit_severity"
Test-Contains -Text $texts.schema_versions -Pattern "Execution router result|guided-full.*auto.*audit-only.*full-auto" -Issues $issues -Code "schema_versions_missing_execution_router_shape"
Test-Contains -Text $texts.schema_versions -Pattern "forge-drift-audit-fallback\.jsonl" -Issues $issues -Code "schema_versions_missing_audit_fallback"
Test-Contains -Text $texts.schema_versions -Pattern "original_path.*write_errors.*record|write_errors\[\].*record" -Issues $issues -Code "schema_versions_missing_audit_fallback_shape"
Test-Contains -Text $texts.protocols -Pattern "forge-drift-audit-fallback\.jsonl|fallback" -Issues $issues -Code "protocols_missing_audit_fallback"
Test-Contains -Text $texts.schema_versions -Pattern "AllOpenGroups" -Issues $issues -Code "schema_versions_missing_all_open_groups"
Test-Contains -Text $texts.schema_versions -Pattern "max_age_hours.*required_modes.*covered_modes|mode_results" -Issues $issues -Code "schema_versions_missing_live_freshness_shape"
Test-Contains -Text $texts.schema_versions -Pattern "archive.*actions.*state_was_expired|validation_commands" -Issues $issues -Code "schema_versions_missing_reset_session_shape"
Test-Contains -Text $texts.schema_versions -Pattern "manifest_path.*checked_count.*changed|forge-workspace-manifest\.json" -Issues $issues -Code "schema_versions_missing_workspace_manifest_shape"
Test-Contains -Text $texts.schema_versions -Pattern "length_before.*length_after.*rotated_to|removed\[\].*actions" -Issues $issues -Code "schema_versions_missing_audit_rotation_shape"
Test-Contains -Text $texts.schema_versions -Pattern "checks\[\].*failed|duration_ms" -Issues $issues -Code "schema_versions_missing_forge_health_shape"
Test-Contains -Text $texts.schema_versions -Pattern "ahead.*behind.*dirty_count|origin_main" -Issues $issues -Code "schema_versions_missing_upstreams_shape"
Test-Contains -Text $texts.schema_versions -Pattern "getHostConfig\('claude'\).*skipSkills|gstack-global-discover\.exe" -Issues $issues -Code "schema_versions_missing_gstack_patches_shape"
Test-Contains -Text $texts.schema_versions -Pattern "patch_path.*patch_bytes.*binary\.sha256|gstack-local-text\.patch" -Issues $issues -Code "schema_versions_missing_gstack_export_shape"
Test-Contains -Text $texts.boundary -Pattern "项目适配分层" -Issues $issues -Code "boundary_missing_project_tiers"

$result = [ordered]@{
    ok = ($issues.Count -eq 0)
    claude_root = $root
    checked_files = $resolved
    issues = @($issues)
}

if ($Json) {
    $result | ConvertTo-Json -Depth 8
} else {
    if ($result.ok) {
        Write-Output "forge_docs_health=ok"
    } else {
        Write-Output "forge_docs_health=fail"
        foreach ($issue in $issues) { Write-Output "issue=$issue" }
    }
}

if (-not $result.ok) { exit 1 }
exit 0
