[CmdletBinding()]
param(
    [string]$GstackPath = "$env:USERPROFILE\.claude\vendors\forge-upstreams\gstack",
    [switch]$Json
)
$ErrorActionPreference = "Stop"
$issues=[System.Collections.Generic.List[string]]::new()
function Add-Issue { param([string]$Code) if(-not $issues.Contains($Code)){[void]$issues.Add($Code)} }
if(-not(Test-Path -LiteralPath $GstackPath)){ Add-Issue 'gstack_path_missing' }
$checks=@()
function Check-FileContains($Rel,$Pattern,$Code){
    $p=Join-Path $GstackPath $Rel
    $ok=(Test-Path -LiteralPath $p) -and ((Get-Content -Raw -LiteralPath $p -Encoding UTF8) -match $Pattern)
    if(-not $ok){ Add-Issue $Code }
    $script:checks += [ordered]@{ path=$Rel; pattern=$Pattern; ok=$ok }
}
if($issues.Count -eq 0){
    Check-FileContains 'autoplan/SKILL.md' '(?m)^voice-triggers:' 'missing_voice_triggers:autoplan'
    Check-FileContains 'cso/SKILL.md' '(?m)^voice-triggers:' 'missing_voice_triggers:cso'
    Check-FileContains 'make-pdf/SKILL.md' '(?m)^voice-triggers:' 'missing_voice_triggers:make-pdf'
    Check-FileContains 'scripts/skill-check.ts' "getHostConfig\('claude'\)" 'missing_claude_host_config_skip'
    Check-FileContains 'scripts/skill-check.ts' 'skipSkills' 'missing_skip_skills_logic'
    if(-not(Test-Path -LiteralPath (Join-Path $GstackPath 'bin/gstack-global-discover.exe'))){ Add-Issue 'missing_gstack_global_discover_exe' }
    if(-not(Test-Path -LiteralPath (Join-Path $GstackPath 'LOCAL-PATCHES.md'))){ Add-Issue 'missing_local_patches_manifest' }
    else{
        $manifest=Get-Content -Raw -LiteralPath (Join-Path $GstackPath 'LOCAL-PATCHES.md') -Encoding UTF8
        foreach($pat in @('voice-triggers','getHostConfig','gstack-global-discover.exe','Safe upstream update')){ if($manifest -notmatch [regex]::Escape($pat)){ Add-Issue "local_patches_missing:$pat" } }
    }
    $counts=(& rtk git -C $GstackPath rev-list --left-right --count HEAD...origin/main 2>$null | Select-Object -First 1)
    $ahead=0; $behind=0
    if($counts -match '^(\d+)\s+(\d+)$'){ $ahead=[int]$matches[1]; $behind=[int]$matches[2] }
    if($ahead -ne 0 -or $behind -ne 0){ Add-Issue "gstack_upstream_not_synced:$ahead/$behind" }
}
$result=[ordered]@{ ok=($issues.Count -eq 0); gstack_path=$GstackPath; checks=@($checks); issues=@($issues) }
if($Json){ $result | ConvertTo-Json -Depth 10 } else { if($result.ok){'gstack_local_patches=ok'}else{'gstack_local_patches=fail'}; foreach($i in $issues){"issue=$i"} }
if(-not $result.ok){ exit 1 }
