param(
    [string]$RepoPath = ".",
    [string]$TaskGroup = "",
    [string]$CandidateText = "",
    [switch]$Json,
    [switch]$Latest,
    [switch]$AllOpenGroups
)

$ErrorActionPreference = "Stop"

if (-not $TaskGroup -and -not $Latest -and -not $AllOpenGroups) {
    throw "Missing TaskGroup. Provide -TaskGroup, -Latest, or -AllOpenGroups."
}
if (($Latest -and $AllOpenGroups) -or ($TaskGroup -and ($Latest -or $AllOpenGroups))) {
    throw "Use exactly one target selector: -TaskGroup, -Latest, or -AllOpenGroups."
}
if ($CandidateText -and -not $TaskGroup) {
    throw "-CandidateText can only be used with -TaskGroup."
}

function Resolve-RepoRoot {
    param([string]$Path)
    try {
        $gitRoot = git -C $Path rev-parse --show-toplevel 2>$null
        if ($LASTEXITCODE -eq 0 -and $gitRoot) { return (Resolve-Path $gitRoot).Path }
    } catch {}
    return (Resolve-Path $Path).Path
}

function Add-Issue {
    param([System.Collections.Generic.List[string]]$Issues, [string]$Code)
    if (-not $Issues.Contains($Code)) { [void]$Issues.Add($Code) }
}

function Is-ProvidedOrSkipped {
    param([string]$Value)
    return (-not [string]::IsNullOrWhiteSpace($Value))
}

function Is-SkipRef {
    param([string]$Value)
    return ([string]$Value).StartsWith("skip:")
}

function Test-ForgePathLikeRef {
    param([string]$Value)
    if ([string]::IsNullOrWhiteSpace($Value) -or (Is-SkipRef $Value)) { return $false }
    # Inline evidence refs such as typecheck:pass, unit:pass, planned:unit, artifact:planned
    # are valid evidence summaries, not filesystem paths. Only path-like refs are checked.
    if ($Value -match "^[A-Za-z][A-Za-z0-9+.-]*:") {
        if (-not [System.IO.Path]::IsPathRooted($Value)) { return $false }
    }
    if ([System.IO.Path]::IsPathRooted($Value)) { return $true }
    return ($Value -match "[\\/]" -or $Value -match "^\.")
}

function Resolve-RepoRefPath {
    param([string]$RepoRoot, [string]$Value)
    if (-not (Test-ForgePathLikeRef $Value)) { return $null }
    if ([System.IO.Path]::IsPathRooted($Value)) { return $Value }
    return (Join-Path $RepoRoot $Value)
}

function Read-RoutingEvents {
    param([string]$RoutingPath)
    $events = @()
    if (-not (Test-Path -LiteralPath $RoutingPath)) { return $events }
    foreach ($line in Get-Content -LiteralPath $RoutingPath -Encoding UTF8) {
        if ([string]::IsNullOrWhiteSpace($line)) { continue }
        try {
            $item = $line | ConvertFrom-Json -AsHashtable
            if ([string]$item.pipeline_phase -eq "M1" -and -not [string]::IsNullOrWhiteSpace([string]$item.task_group)) {
                $events += $item
            }
        } catch {}
    }
    return $events
}

function Resolve-TargetGroups {
    param([object[]]$Events, [string]$TaskGroup, [bool]$Latest, [bool]$AllOpenGroups)
    if ($TaskGroup) { return @($TaskGroup) }
    if ($Events.Count -lt 1) { return @() }
    if ($Latest) { return @([string]$Events[-1].task_group) }

    $started = @{}
    $completed = @{}
    foreach ($event in $Events) {
        $group = [string]$event.task_group
        if ([string]$event.group_status -eq "started") { $started[$group] = $true }
        if ([string]$event.group_status -eq "completed") { $completed[$group] = $true }
    }
    $open = @()
    foreach ($group in $started.Keys) {
        if (-not $completed.ContainsKey($group)) { $open += $group }
    }
    return @($open | Sort-Object)
}

function Test-OneTaskGroup {
    param(
        [string]$RepoRoot,
        [string]$RoutingPath,
        [object[]]$AllEvents,
        [string]$Group,
        [string]$CandidateText
    )

    $issues = [System.Collections.Generic.List[string]]::new()

    if ($CandidateText) {
        $escaped = [regex]::Escape($Group)
        if ($CandidateText -notmatch "\[FORGE\]\s+phase=M1\s+group=$escaped") {
            Add-Issue $issues "missing_forge_m1_header"
        }
        if ($CandidateText -notmatch "\[PIPELINE\]\s+阶段\s+$escaped\s+完成") {
            Add-Issue $issues "missing_pipeline_m1_completion_marker"
        }
    }

    if (-not (Test-Path -LiteralPath $RoutingPath)) {
        Add-Issue $issues "missing_forge_routing_log"
    }

    $events = @($AllEvents | Where-Object { [string]$_.task_group -eq $Group })
    $started = @($events | Where-Object { [string]$_.group_status -eq "started" })
    $completed = @($events | Where-Object { [string]$_.group_status -eq "completed" })

    if ($started.Count -lt 1) { Add-Issue $issues "missing_m1_started_routing_event" }
    if ($completed.Count -lt 1) {
        Add-Issue $issues "missing_m1_completed_routing_event"
    } else {
        $latest = $completed[-1]
        foreach ($pair in @(
            @("todo_ref", "missing_todo_ref"),
            @("verification_ref", "missing_verification_ref"),
            @("artifact_ref", "missing_artifact_ref"),
            @("commit_sha", "missing_commit_sha_or_skip_reason"),
            @("learnings_ref", "missing_learnings_ref")
        )) {
            $field = $pair[0]
            $code = $pair[1]
            if (-not (Is-ProvidedOrSkipped ([string]$latest[$field]))) { Add-Issue $issues $code }
        }
        if (-not (Is-ProvidedOrSkipped ([string]$latest["next_phase"]))) {
            Add-Issue $issues "missing_next_phase"
        }

        $projectLevel = [string]$latest["project_level"]
        if ([string]::IsNullOrWhiteSpace($projectLevel)) { $projectLevel = [string]$latest["level"] }
        $batchProtocol = [string]$latest["batch_protocol"]
        if ($projectLevel -eq "L4") {
            if ([string]::IsNullOrWhiteSpace($batchProtocol)) {
                Add-Issue $issues "missing_l4_batch_protocol"
            } elseif ($batchProtocol -notin @("full", "full-auto", "ship")) {
                if (-not (Is-ProvidedOrSkipped ([string]$latest["downgrade_reason"]))) { Add-Issue $issues "missing_l4_downgrade_reason" }
                if (-not (Is-ProvidedOrSkipped ([string]$latest["parent_plan_ref"]))) { Add-Issue $issues "missing_l4_parent_plan_ref" }
            }
        }

        $highRisk = [string]$latest["high_risk"]
        $isHighRisk = -not [string]::IsNullOrWhiteSpace($highRisk)
        if ($isHighRisk) {
            $todoRef = [string]$latest["todo_ref"]
            $tddRef = [string]$latest["tdd_ref"]
            $testRef = [string]$latest["test_ref"]
            $verificationRef = [string]$latest["verification_ref"]
            if ($todoRef -notmatch "^TodoWrite:") { Add-Issue $issues "missing_todowrite_ref_for_high_risk" }
            if ([string]::IsNullOrWhiteSpace($tddRef)) { Add-Issue $issues "missing_tdd_ref_for_high_risk" }
            if ($tddRef -match "^skip:") { Add-Issue $issues "tdd_skipped_for_high_risk" }
            if ([string]::IsNullOrWhiteSpace($testRef)) { Add-Issue $issues "missing_test_ref_for_high_risk" }
            if ($testRef -match "^skip:") { Add-Issue $issues "test_skipped_for_high_risk" }
            if ($testRef -and $testRef -notmatch "(^|[;,: ])(unit|integration)([:; ,]|$)") { Add-Issue $issues "missing_unit_or_integration_test_ref_for_high_risk" }
            if ($verificationRef -match "^typecheck:pass$") { Add-Issue $issues "typecheck_only_for_high_risk" }
        }

        foreach ($pair in @(
            @("verification_ref", "missing_verification_file"),
            @("artifact_ref", "missing_artifact_file"),
            @("learnings_ref", "missing_learnings_file")
        )) {
            $field = $pair[0]
            $code = $pair[1]
            $value = [string]$latest[$field]
            $path = Resolve-RepoRefPath $RepoRoot $value
            if ($path -and -not (Test-Path -LiteralPath $path)) { Add-Issue $issues $code }
        }
    }

    return [ordered]@{
        ok = ($issues.Count -eq 0)
        task_group = $Group
        started_events = $started.Count
        completed_events = $completed.Count
        issues = @($issues)
    }
}

$repoRoot = Resolve-RepoRoot -Path $RepoPath
$routingPath = Join-Path $repoRoot ".claude\forge-routing.jsonl"
$allEvents = @(Read-RoutingEvents -RoutingPath $routingPath)
$groups = @(Resolve-TargetGroups -Events $allEvents -TaskGroup $TaskGroup -Latest ([bool]$Latest) -AllOpenGroups ([bool]$AllOpenGroups))

if ($groups.Count -lt 1) {
    $message = if ($AllOpenGroups) { "no_open_m1_task_groups" } elseif ($Latest) { "missing_m1_routing_events" } else { "missing_task_group" }
    $okWhenEmpty = [bool]$AllOpenGroups
    $result = [ordered]@{
        ok = $okWhenEmpty
        repo = $repoRoot
        selector = if ($Latest) { "latest" } elseif ($AllOpenGroups) { "all_open_groups" } else { "task_group" }
        routing = $routingPath
        checked_groups = @()
        group_results = @()
        issues = if ($okWhenEmpty) { @() } else { @($message) }
        note = $message
    }
} else {
    $groupResults = @()
    $allIssues = [System.Collections.Generic.List[string]]::new()
    foreach ($group in $groups) {
        $candidate = if ($TaskGroup) { $CandidateText } else { "" }
        $groupResult = Test-OneTaskGroup -RepoRoot $repoRoot -RoutingPath $routingPath -AllEvents $allEvents -Group $group -CandidateText $candidate
        $groupResults += $groupResult
        foreach ($issue in @($groupResult.issues)) { Add-Issue $allIssues ("$($group):$issue") }
    }
    $result = [ordered]@{
        ok = ($allIssues.Count -eq 0)
        repo = $repoRoot
        selector = if ($Latest) { "latest" } elseif ($AllOpenGroups) { "all_open_groups" } else { "task_group" }
        routing = $routingPath
        checked_groups = @($groups)
        group_results = @($groupResults)
        issues = @($allIssues)
    }
}

if ($Json) {
    $result | ConvertTo-Json -Depth 10
} else {
    if ($result.ok) { Write-Output "forge_m1_compliance=ok" }
    else {
        Write-Output "forge_m1_compliance=fail"
        foreach ($issue in @($result.issues)) { Write-Output "issue=$issue" }
    }
    Write-Output "selector=$($result.selector)"
    foreach ($group in @($result.checked_groups)) { Write-Output "task_group=$group" }
    Write-Output "routing=$routingPath"
}

if (-not $result.ok) { exit 1 }
exit 0
