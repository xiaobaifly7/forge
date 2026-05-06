param(
    [string]$RepoPath = ".",
    [switch]$RefreshProjectClaude
)

$ErrorActionPreference = "Stop"

function Resolve-RepoRoot {
    param([string]$Path)

    try {
        $gitRoot = git -C $Path rev-parse --show-toplevel 2>$null
        if ($LASTEXITCODE -eq 0 -and $gitRoot) {
            return (Resolve-Path $gitRoot).Path
        }
    } catch {
    }

    return (Resolve-Path $Path).Path
}

function Test-BlobPattern {
    param(
        [string]$Blob,
        [string]$Pattern
    )

    return [bool]($Blob -match $Pattern)
}

function Format-Bool {
    param([bool]$Value)
    if ($Value) { return "true" }
    return "false"
}

function Get-RelativeEvidence {
    param(
        [object[]]$Items,
        [string]$Root,
        [int]$Limit = 12
    )

    $evidence = New-Object System.Collections.Generic.List[string]
    foreach ($item in @($Items | Select-Object -First $Limit)) {
        $full = [string]$item.FullName
        if (-not $full) { $full = [string]$item }
        if ($full.StartsWith($Root, [System.StringComparison]::OrdinalIgnoreCase)) {
            $rel = $full.Substring($Root.Length).TrimStart('\', '/')
            if ($rel) { $evidence.Add($rel) }
        } elseif ($full) {
            $evidence.Add($full)
        }
    }
    return @($evidence | Select-Object -Unique)
}

function Get-RepoRelativePath {
    param(
        [string]$Root,
        [string]$FullPath
    )

    $rootFull = [System.IO.Path]::GetFullPath($Root)
    $pathFull = [System.IO.Path]::GetFullPath($FullPath)
    if ($pathFull.StartsWith($rootFull, [System.StringComparison]::OrdinalIgnoreCase)) {
        $relative = $pathFull.Substring($rootFull.Length).TrimStart('\', '/')
        if ([string]::IsNullOrWhiteSpace($relative)) {
            return "."
        }
        return ($relative -replace '\\', '/')
    }

    return ($pathFull -replace '\\', '/')
}

function Get-PathEvidence {
    param(
        [System.IO.FileSystemInfo[]]$Items,
        [string]$Pattern,
        [string]$RepoRoot,
        [int]$Limit = 8
    )

    $result = New-Object System.Collections.Generic.List[string]
    foreach ($item in $Items) {
        if ($item.FullName -notmatch $Pattern) {
            continue
        }

        $relativePath = Get-RepoRelativePath -Root $RepoRoot -FullPath $item.FullName
        if (-not $result.Contains($relativePath)) {
            $result.Add($relativePath)
        }

        if ($result.Count -ge $Limit) {
            break
        }
    }

    return @($result)
}

function Add-EvidenceItems {
    param(
        [System.Collections.Generic.List[string]]$Target,
        [string[]]$Items
    )

    foreach ($item in @($Items)) {
        if ([string]::IsNullOrWhiteSpace($item)) {
            continue
        }
        if (-not $Target.Contains($item)) {
            $Target.Add($item)
        }
    }
}

function Format-EvidenceMarkdown {
    param([string[]]$Items)

    $normalized = @($Items | Where-Object { -not [string]::IsNullOrWhiteSpace($_) } | Select-Object -Unique)
    if ($normalized.Count -eq 0) {
        return "- none"
    }

    return "- " + ($normalized -join "`n- ")
}

function Add-IgnoreEntry {
    param(
        [string]$GitignorePath,
        [string[]]$Entries
    )

    $existing = @()
    if (Test-Path $GitignorePath) {
        $existing = Get-Content -Path $GitignorePath
    }

    $pending = New-Object System.Collections.Generic.List[string]
    foreach ($entry in $Entries) {
        if (-not ($existing -contains $entry)) {
            $pending.Add($entry)
        }
    }

    if ($pending.Count -eq 0) {
        return
    }

    $newContent = New-Object System.Collections.Generic.List[string]
    foreach ($line in $existing) {
        $newContent.Add($line)
    }

    if ($newContent.Count -gt 0 -and $newContent[$newContent.Count - 1] -ne "") {
        $newContent.Add("")
    }

    foreach ($entry in $pending) {
        $newContent.Add($entry)
    }

    Set-Content -Path $GitignorePath -Value $newContent -Encoding utf8
}

$repoRoot = Resolve-RepoRoot -Path $RepoPath
$repoName = Split-Path -Path $repoRoot -Leaf
$localClaudeDir = Join-Path $repoRoot ".claude"
$profilePath = Join-Path $localClaudeDir "project-profile.json"
$policyPath = Join-Path $localClaudeDir "workflow-policy.md"
$projectClaudePath = Join-Path $repoRoot "CLAUDE.md"
$gitignorePath = Join-Path $repoRoot ".gitignore"
$templatePath = "$env:USERPROFILE\.claude\docs\workflow-policy-template.md"
$projectClaudeTemplatePath = "$env:USERPROFILE\.claude\docs\project-claude-template.md"

New-Item -ItemType Directory -Force -Path $localClaudeDir | Out-Null

function Get-RepoItemsFast {
    param(
        [string]$Root,
        [int]$MaxDepth = 2
    )

    $skipNames = @(
        ".git", ".claude", "_bmad", "{output_folder}", "node_modules", "dist", "build", "coverage",
        ".next", ".nuxt", ".turbo", "vendor", "target", ".venv", "venv", "__pycache__",
        "bin", "obj", "out", "release", "debug", "output", "tmp", ".tmp", "_inspect", ".codex-projects", ".omx", ".pytest_cache", ".playwright-mcp"
    )
    $skip = New-Object 'System.Collections.Generic.HashSet[string]' ([System.StringComparer]::OrdinalIgnoreCase)
    foreach ($name in $skipNames) { [void]$skip.Add($name) }

    $items = New-Object System.Collections.Generic.List[System.IO.FileSystemInfo]
    $queue = New-Object System.Collections.Generic.Queue[object]
    $queue.Enqueue([pscustomobject]@{ Path = $Root; Depth = 0 })

    while ($queue.Count -gt 0) {
        $current = $queue.Dequeue()
        $children = @()
        try {
            $children = Get-ChildItem -LiteralPath $current.Path -Force -ErrorAction SilentlyContinue
        } catch {
            continue
        }

        foreach ($child in $children) {
            if ($child.PSIsContainer -and $skip.Contains($child.Name)) {
                continue
            }
            $items.Add($child)
            if ($child.PSIsContainer -and $current.Depth -lt $MaxDepth) {
                $queue.Enqueue([pscustomobject]@{ Path = $child.FullName; Depth = $current.Depth + 1 })
            }
        }
    }

    return @($items)
}

$allItems = Get-RepoItemsFast -Root $repoRoot -MaxDepth 2

$files = @($allItems | Where-Object { -not $_.PSIsContainer })
$pathsBlob = ($allItems.FullName -join "`n")

$workspaceMarkers = @(
    "pnpm-workspace.yaml",
    "turbo.json",
    "lerna.json",
    "nx.json",
    "rush.json"
)

$isWorkspaceMarked = $false
foreach ($marker in $workspaceMarkers) {
    if (Test-Path (Join-Path $repoRoot $marker)) {
        $isWorkspaceMarked = $true
        break
    }
}

$packageJsonFiles = @($files | Where-Object { $_.Name -eq "package.json" })
$isMonorepo = $isWorkspaceMarked -or ($packageJsonFiles.Count -gt 1)

$stacks = New-Object System.Collections.Generic.List[string]
if ($packageJsonFiles.Count -gt 0) {
    if (((Test-Path (Join-Path $repoRoot "tsconfig.json"))) -or
        ((@($files | Where-Object { $_.Name -like "tsconfig*.json" }).Count -gt 0))) {
        $stacks.Add("typescript")
    } else {
        $stacks.Add("javascript")
    }
}

if (((Test-Path (Join-Path $repoRoot "pyproject.toml"))) -or
    ((Test-Path (Join-Path $repoRoot "requirements.txt"))) -or
    ((Test-Path (Join-Path $repoRoot "setup.py")))) {
    $stacks.Add("python")
}

if (Test-Path (Join-Path $repoRoot "Cargo.toml")) {
    $stacks.Add("rust")
}

if (Test-Path (Join-Path $repoRoot "go.mod")) {
    $stacks.Add("go")
}

if (@($files | Where-Object { $_.Extension -eq ".csproj" -or $_.Extension -eq ".sln" }).Count -gt 0) {
    $stacks.Add("csharp")
}

if (((Test-Path (Join-Path $repoRoot "pom.xml"))) -or
    ((Test-Path (Join-Path $repoRoot "build.gradle"))) -or
    ((Test-Path (Join-Path $repoRoot "build.gradle.kts")))) {
    $stacks.Add("java")
}

if ($stacks.Count -eq 0) {
    $stacks.Add("unknown")
}

$hasPluginMarkers = (Test-Path (Join-Path $repoRoot ".claude-plugin")) -or
    (Test-Path (Join-Path $repoRoot ".cursor-plugin")) -or
    (Test-Path (Join-Path $repoRoot ".codex-plugin"))

$packageJson = $null
$packageJsonPath = Join-Path $repoRoot "package.json"
if (Test-Path $packageJsonPath) {
    try {
        $packageJson = Get-Content -Raw $packageJsonPath | ConvertFrom-Json -AsHashTable
    } catch {
        $packageJson = $null
    }
}

$hasCliMarkers = $false
if ($packageJson -and $packageJson.ContainsKey("bin")) {
    $hasCliMarkers = $true
}
if (Test-Path (Join-Path $repoRoot "bin")) {
    $hasCliMarkers = $true
}

$hasServiceMarkers = Test-BlobPattern -Blob $pathsBlob -Pattern '(?i)(\\|/)(api|server|service)(\\|/|$)'

$repoType = "app"
if ($isMonorepo) {
    $repoType = "monorepo"
} elseif ($hasPluginMarkers) {
    $repoType = "plugin"
} elseif ($hasCliMarkers) {
    $repoType = "cli"
} elseif ($hasServiceMarkers) {
    $repoType = "service"
}

$sharedSurface = $isMonorepo -or (Test-BlobPattern -Blob $pathsBlob -Pattern '(?i)(\\|/)(packages|libs|shared|common|sdk|platform|core|types)(\\|/|$)')
$hasPersistence = Test-BlobPattern -Blob $pathsBlob -Pattern '(?i)(\\|/)(db|database|migrations|migration|prisma|schema|schemas)(\\|/|$)'
$hasPublicContracts = Test-BlobPattern -Blob $pathsBlob -Pattern '(?i)(\\|/)(openapi|swagger|proto|protobuf|contracts|graphql)(\\|/|$)'
$hasSecuritySurface = Test-BlobPattern -Blob $pathsBlob -Pattern '(?i)(\\|/)(auth|oauth|rbac|permission|permissions|acl|security|payment|billing)(\\|/|$)'
$hasReleasePipeline = (Test-Path (Join-Path $repoRoot ".github\workflows")) -or
    (Test-BlobPattern -Blob $pathsBlob -Pattern '(?i)(dockerfile|docker-compose|terraform|terragrunt|helm|k8s|kubernetes|deploy|release)')

$hasTests = (Test-BlobPattern -Blob $pathsBlob -Pattern '(?i)(\\|/)(tests|test|e2e|spec|__tests__)(\\|/|$)') -or
    (@($files | Where-Object { $_.Name -match '\.(test|spec)\.' }).Count -gt 0)
$hasCi = (Test-Path (Join-Path $repoRoot ".github\workflows")) -or
    (Test-Path (Join-Path $repoRoot "azure-pipelines.yml")) -or
    (Test-Path (Join-Path $repoRoot ".gitlab-ci.yml"))
$hasLintOrTypecheck = (Test-Path (Join-Path $repoRoot "tsconfig.json")) -or
    (Test-Path (Join-Path $repoRoot "pyrightconfig.json")) -or
    (Test-Path (Join-Path $repoRoot "mypy.ini")) -or
    (Test-Path (Join-Path $repoRoot ".eslintrc")) -or
    (Test-Path (Join-Path $repoRoot ".eslintrc.js")) -or
    (Test-Path (Join-Path $repoRoot "ruff.toml"))

$testMaturity = "low"
if ($hasTests -and $hasCi -and $hasLintOrTypecheck) {
    $testMaturity = "high"
} elseif ($hasTests -or $hasCi) {
    $testMaturity = "medium"
}

$riskScore = 0
if ($sharedSurface) { $riskScore += 2 }
if ($hasPersistence) { $riskScore += 2 }
if ($hasPublicContracts) { $riskScore += 2 }
if ($hasSecuritySurface) { $riskScore += 2 }
if ($hasReleasePipeline) { $riskScore += 1 }
if ($isMonorepo) { $riskScore += 1 }
if ($testMaturity -eq "low") { $riskScore += 1 }

$riskLevel = "low"
if ($riskScore -ge 5) {
    $riskLevel = "high"
} elseif ($riskScore -ge 2) {
    $riskLevel = "medium"
}

$defaultMinMode = "build"
if ($riskLevel -eq "high" -or $isMonorepo) {
    $defaultMinMode = "full"
}

$defaultRouteLevel = "L2"
if ($riskLevel -eq "low" -and -not $sharedSurface -and -not $hasPersistence -and -not $hasSecuritySurface) {
    $defaultRouteLevel = "L1"
}
if ($riskLevel -eq "high" -or $sharedSurface -or $hasPersistence -or $hasSecuritySurface -or $hasPublicContracts) {
    $defaultRouteLevel = "L3"
}
if ($isMonorepo -and $riskLevel -eq "high" -and ($hasPersistence -or $hasSecuritySurface -or $hasPublicContracts)) {
    $defaultRouteLevel = "L4"
}


$preferSubagents = $false
$executionPreference = "best_path_first"
$requiredSidecar = "when_parallelizable"

$forgeAdoptionMode = "local_routing"
$forgeAdoptionReason = "standard project: use Forge v2 routing without forcing full workflow"
if ($repoRoot -match '(?i)obsidian|study') {
    $forgeAdoptionMode = "audit_only"
    $forgeAdoptionReason = "knowledge vault: prefer audit/knowledge workflow over full engineering chain"
} elseif ($repoRoot -match '(?i)remote-ai|cloudflared|service') {
    $forgeAdoptionMode = "audit_only"
    $forgeAdoptionReason = "runtime/service directory: avoid workflow takeover without explicit approval"
}

$hardTriggers = New-Object System.Collections.Generic.List[string]
if ($sharedSurface) { $hardTriggers.Add("shared_contract") }
if ($hasPersistence) { $hardTriggers.Add("persistence") }
if ($hasPublicContracts) { $hardTriggers.Add("public_contract") }
if ($hasSecuritySurface) { $hardTriggers.Add("security_auth") }
if ($hasReleasePipeline) { $hardTriggers.Add("release_pipeline") }

$sharedSurfaceEvidence = New-Object System.Collections.Generic.List[string]
if ($isMonorepo) {
    foreach ($marker in $workspaceMarkers) {
        $markerPath = Join-Path $repoRoot $marker
        if (Test-Path $markerPath) {
            $sharedSurfaceEvidence.Add((Get-RepoRelativePath -Root $repoRoot -FullPath $markerPath))
        }
    }
}
Add-EvidenceItems -Target $sharedSurfaceEvidence -Items (Get-PathEvidence -Items $allItems -Pattern '(?i)(\\|/)(packages|libs|shared|common|sdk|platform|core|types)(\\|/|$)' -RepoRoot $repoRoot -Limit 10)

$persistenceEvidence = Get-PathEvidence -Items $allItems -Pattern '(?i)(\\|/)(db|database|migrations|migration|prisma|schema|schemas)(\\|/|$)' -RepoRoot $repoRoot -Limit 10
$publicContractsEvidence = Get-PathEvidence -Items $allItems -Pattern '(?i)(\\|/)(openapi|swagger|proto|protobuf|contracts|graphql)(\\|/|$)' -RepoRoot $repoRoot -Limit 10
$securitySurfaceEvidence = Get-PathEvidence -Items $allItems -Pattern '(?i)(\\|/)(auth|oauth|rbac|permission|permissions|acl|security|payment|billing)(\\|/|$)' -RepoRoot $repoRoot -Limit 10

$releasePipelineEvidence = New-Object System.Collections.Generic.List[string]
$githubWorkflowsPath = Join-Path $repoRoot ".github\workflows"
if (Test-Path $githubWorkflowsPath) {
    $releasePipelineEvidence.Add((Get-RepoRelativePath -Root $repoRoot -FullPath $githubWorkflowsPath))
}
Add-EvidenceItems -Target $releasePipelineEvidence -Items (Get-PathEvidence -Items $allItems -Pattern '(?i)(dockerfile|docker-compose|terraform|terragrunt|helm|k8s|kubernetes|deploy|release)' -RepoRoot $repoRoot -Limit 10)

$packageScriptsEvidence = New-Object System.Collections.Generic.List[string]
$testCommandsEvidence = New-Object System.Collections.Generic.List[string]
$candidateTestScriptNames = New-Object System.Collections.Generic.List[string]
if ($packageJson -and $packageJson.ContainsKey("scripts") -and ($packageJson["scripts"] -is [System.Collections.IDictionary])) {
    $scriptsTable = $packageJson["scripts"]
    foreach ($scriptName in ($scriptsTable.Keys | Sort-Object)) {
        $scriptValue = [string]$scriptsTable[$scriptName]
        if ($scriptValue.Length -gt 120) {
            $scriptValue = $scriptValue.Substring(0, 117) + "..."
        }
        $packageScriptsEvidence.Add("$scriptName => $scriptValue")

        if ($scriptName -match '^(test($|:)|spec($|:)|e2e($|:)|lint($|:)|typecheck($|:)|check($|:)|ci($|:))') {
            $candidateTestScriptNames.Add([string]$scriptName)
        }
    }
}

foreach ($scriptName in ($candidateTestScriptNames | Select-Object -Unique)) {
    $testCommandsEvidence.Add("npm run $scriptName")
}

if ($packageJsonFiles.Count -gt 0 -and $testCommandsEvidence.Count -eq 0) {
    if ($hasTests) {
        $testCommandsEvidence.Add("npm test")
    }
}
if (Test-Path (Join-Path $repoRoot "pyproject.toml")) {
    $testCommandsEvidence.Add("pytest")
}
if (Test-Path (Join-Path $repoRoot "Cargo.toml")) {
    $testCommandsEvidence.Add("cargo test")
}
if (Test-Path (Join-Path $repoRoot "go.mod")) {
    $testCommandsEvidence.Add("go test ./...")
}
if (@($files | Where-Object { $_.Extension -eq ".csproj" -or $_.Extension -eq ".sln" }).Count -gt 0) {
    $testCommandsEvidence.Add("dotnet test")
}
if (Test-Path (Join-Path $repoRoot "pom.xml")) {
    $testCommandsEvidence.Add("mvn test")
}
if ((Test-Path (Join-Path $repoRoot "build.gradle")) -or (Test-Path (Join-Path $repoRoot "build.gradle.kts"))) {
    $testCommandsEvidence.Add("./gradlew test")
}

$profile = [ordered]@{
    schema_version = 2
    generated_at = (Get-Date).ToString("o")
    repo_root = $repoRoot
    repo_name = $repoName
    repo_type = $repoType
    stacks = @($stacks | Select-Object -Unique)
    risk_level = $riskLevel
    shared_surface = $sharedSurface
    has_persistence = $hasPersistence
    has_public_contracts = $hasPublicContracts
    has_release_pipeline = $hasReleasePipeline
    has_security_surface = $hasSecuritySurface
    evidence = [ordered]@{
        shared_surface = @($sharedSurfaceEvidence | Select-Object -Unique)
        persistence = @($persistenceEvidence | Select-Object -Unique)
        public_contracts = @($publicContractsEvidence | Select-Object -Unique)
        security_surface = @($securitySurfaceEvidence | Select-Object -Unique)
        release_pipeline = @($releasePipelineEvidence | Select-Object -Unique)
        test_commands = @($testCommandsEvidence | Select-Object -Unique)
        package_scripts = @($packageScriptsEvidence | Select-Object -Unique)
    }
    test_maturity = $testMaturity
    default_min_mode = $defaultMinMode
    default_route_level = $defaultRouteLevel
    default_full_execution = "guided-full"
    full_auto_requires_explicit_user_request = $true
    forge_adoption = [ordered]@{
        mode = $forgeAdoptionMode
        reason = $forgeAdoptionReason
        allowed_modes = @("disabled", "audit_only", "local_routing", "full")
    }
    active_update_policy = [ordered]@{
        gstack = "manual_approval"
        compound = "manual_approval"
        gsd2 = "manual_approval"
        bmad = "staging_first"
        superpowers = "marketplace_managed"
    }
    project_upgrade_checklist = @(
        "check_existing_CLAUDE_md",
        "check_existing_bmad",
        "check_existing_project_profile",
        "classify_production_service_security_risk",
        "confirm_repo_local_state_allowed",
        "decide_audit_only_or_local_routing_or_full"
    )
    prefer_subagents = $preferSubagents
    execution_preference = [ordered]@{
        default_execution = $executionPreference
        require_sidecar = $false
        sidecar_scope = $requiredSidecar
    }
    hard_triggers = @($hardTriggers | Select-Object -Unique)
    routing_rules = [ordered]@{
        user_override = "always"
        first_decision = "L0-L4"
        then_map_to_protocol = "quick/build/fix/full/ship"
        uncertain = "escalate"
        downgrade = "forbidden"
        full_auto = "explicit_user_request_only"
    }
    route_levels = [ordered]@{
        L0 = "read_only_direct_no_state_write"
        L1 = "direct_minimal_change_targeted_verify"
        L2 = "superpowers_discipline_build_or_fix"
        L3 = "bmad_superpowers_gstack_gsd"
        L4 = "bmad_gsd2_superpowers_gstack_compound"
    }
    module_boundaries = [ordered]@{
        forge = "thin_router_only"
        bmad = "planning_architecture_story_acceptance"
        superpowers = "execution_tdd_debug_verification"
        gstack = "gate_only"
        gsd2 = "state_machine_for_L4"
        compound = "high_value_learnings_only"
    }
}

$profile | ConvertTo-Json -Depth 8 | Set-Content -Path $profilePath -Encoding utf8

$template = Get-Content -Raw -Path $templatePath
$hardTriggersMarkdown = "- none"
if ($hardTriggers.Count -gt 0) {
    $hardTriggersMarkdown = "- " + (($hardTriggers | Select-Object -Unique) -join "`n- ")
}

$replacements = [ordered]@{
    "{{REPO_NAME}}" = $repoName
    "{{GENERATED_AT}}" = (Get-Date).ToString("yyyy-MM-dd HH:mm:ss zzz")
    "{{REPO_TYPE}}" = $repoType
    "{{STACKS}}" = (($stacks | Select-Object -Unique) -join ", ")
    "{{RISK_LEVEL}}" = $riskLevel
    "{{SHARED_SURFACE}}" = (Format-Bool $sharedSurface)
    "{{HAS_PERSISTENCE}}" = (Format-Bool $hasPersistence)
    "{{HAS_PUBLIC_CONTRACTS}}" = (Format-Bool $hasPublicContracts)
    "{{HAS_RELEASE_PIPELINE}}" = (Format-Bool $hasReleasePipeline)
    "{{HAS_SECURITY_SURFACE}}" = (Format-Bool $hasSecuritySurface)
    "{{TEST_MATURITY}}" = $testMaturity
    "{{DEFAULT_MIN_MODE}}" = $defaultMinMode
    "{{PREFER_SUBAGENTS}}" = (Format-Bool $preferSubagents)
    "{{EXECUTION_PREFERENCE}}" = $executionPreference
    "{{REQUIRED_SIDECAR}}" = $requiredSidecar
    "{{HARD_TRIGGERS}}" = $hardTriggersMarkdown
    "{{EVIDENCE_SHARED_SURFACE}}" = (Format-EvidenceMarkdown -Items @($profile.evidence.shared_surface))
    "{{EVIDENCE_PERSISTENCE}}" = (Format-EvidenceMarkdown -Items @($profile.evidence.persistence))
    "{{EVIDENCE_PUBLIC_CONTRACTS}}" = (Format-EvidenceMarkdown -Items @($profile.evidence.public_contracts))
    "{{EVIDENCE_SECURITY_SURFACE}}" = (Format-EvidenceMarkdown -Items @($profile.evidence.security_surface))
    "{{EVIDENCE_RELEASE_PIPELINE}}" = (Format-EvidenceMarkdown -Items @($profile.evidence.release_pipeline))
    "{{EVIDENCE_TEST_COMMANDS}}" = (Format-EvidenceMarkdown -Items @($profile.evidence.test_commands))
    "{{EVIDENCE_PACKAGE_SCRIPTS}}" = (Format-EvidenceMarkdown -Items @($profile.evidence.package_scripts))
}

$policyContent = $template
foreach ($entry in $replacements.GetEnumerator()) {
    $policyContent = $policyContent.Replace($entry.Key, [string]$entry.Value)
}

Set-Content -Path $policyPath -Value $policyContent -Encoding utf8

$fullTriggerBullets = New-Object System.Collections.Generic.List[string]
if ($hasPersistence) { $fullTriggerBullets.Add("- 持久化 / 数据库 / Redis / SQLite / schema") }
if ($hasSecuritySurface) { $fullTriggerBullets.Add("- 私钥 / 助记词 / 签名 / Fernet / 认证 / 安全") }
if ($hasPublicContracts) { $fullTriggerBullets.Add("- 共享契约 / 公共类型 / API / protocol") }
if ($isMonorepo -or $sharedSurface) { $fullTriggerBullets.Add("- 跨模块 / 共享层 / 多包改动") }
if ($hasReleasePipeline) { $fullTriggerBullets.Add("- 发布链路 / 部署 / 交付前关键改动") }
if ($fullTriggerBullets.Count -eq 0) {
    $fullTriggerBullets.Add("- 新能力接入")
    $fullTriggerBullets.Add("- 高不确定性任务")
}
$fullTriggerMarkdown = ($fullTriggerBullets | Select-Object -Unique) -join "`n"

$writeProjectClaude = $RefreshProjectClaude -or -not (Test-Path $projectClaudePath)
if ($writeProjectClaude) {
    $projectTemplate = Get-Content -Raw -Path $projectClaudeTemplatePath
    $projectReplacements = [ordered]@{
        "{{REPO_NAME}}" = $repoName
        "{{REPO_ROOT}}" = $repoRoot
        "{{REPO_TYPE}}" = $repoType
        "{{STACKS}}" = (($stacks | Select-Object -Unique) -join ", ")
        "{{RISK_LEVEL}}" = $riskLevel
        "{{DEFAULT_MIN_MODE}}" = $defaultMinMode
        "{{HAS_PERSISTENCE}}" = (Format-Bool $hasPersistence)
        "{{HAS_SECURITY_SURFACE}}" = (Format-Bool $hasSecuritySurface)
        "{{HAS_PUBLIC_CONTRACTS}}" = (Format-Bool $hasPublicContracts)
        "{{HAS_RELEASE_PIPELINE}}" = (Format-Bool $hasReleasePipeline)
        "{{FULL_TRIGGER_BULLETS}}" = $fullTriggerMarkdown
    }
    $projectClaudeContent = $projectTemplate
    foreach ($entry in $projectReplacements.GetEnumerator()) {
        $projectClaudeContent = $projectClaudeContent.Replace($entry.Key, [string]$entry.Value)
    }
    Set-Content -Path $projectClaudePath -Value $projectClaudeContent -Encoding utf8
}

Add-IgnoreEntry -GitignorePath $gitignorePath -Entries @(
    ".claude/project-profile.json",
    ".claude/workflow-policy.md"
)

Write-Output "repo_root=$repoRoot"
Write-Output "profile=$profilePath"
Write-Output "policy=$policyPath"
Write-Output "project_claude=$projectClaudePath"
Write-Output "project_claude_action=$(if($writeProjectClaude){'written'}else{'kept-existing'})"
Write-Output "repo_type=$repoType"
Write-Output "stacks=$((($stacks | Select-Object -Unique) -join ','))"
Write-Output "risk_level=$riskLevel"
Write-Output "default_min_mode=$defaultMinMode"
Write-Output "default_route_level=$defaultRouteLevel"
Write-Output "default_full_execution=guided-full"
Write-Output "forge_adoption=$forgeAdoptionMode"
Write-Output "prefer_subagents=$(Format-Bool $preferSubagents)"
Write-Output "execution_preference=$executionPreference"
Write-Output "required_sidecar=$requiredSidecar"
Write-Output "hard_triggers=$((($hardTriggers | Select-Object -Unique) -join ','))"
Write-Output "evidence_keys=$((($profile.evidence.Keys) -join ','))"
