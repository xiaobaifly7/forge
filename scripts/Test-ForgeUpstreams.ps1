[CmdletBinding()]
param(
    [switch]$Fetch,
    [switch]$Json
)
$ErrorActionPreference = "Stop"
$vendorRoot = Join-Path $env:USERPROFILE ".claude\vendors\forge-upstreams"
$repos = [ordered]@{
    'bmad-method' = Join-Path $vendorRoot 'bmad-method'
    'compound-engineering' = Join-Path $vendorRoot 'compound-engineering'
    'gsd-2' = Join-Path $vendorRoot 'gsd-2'
    'gstack' = Join-Path $vendorRoot 'gstack'
}
$issues = [System.Collections.Generic.List[string]]::new()
function Add-Issue { param([string]$Code) if(-not $issues.Contains($Code)){[void]$issues.Add($Code)} }
$results=@()
foreach($name in $repos.Keys){
    $path=$repos[$name]
    if(-not(Test-Path -LiteralPath $path)){ Add-Issue "upstream_missing:$name"; continue }
    if($Fetch){ & rtk git -C $path fetch --prune origin | Out-Null }
    $remote=(& rtk git -C $path remote get-url origin 2>$null | Select-Object -First 1)
    $head=(& rtk git -C $path rev-parse --short HEAD 2>$null | Select-Object -First 1)
    $origin=(& rtk git -C $path rev-parse --short origin/main 2>$null | Select-Object -First 1)
    $counts=(& rtk git -C $path rev-list --left-right --count HEAD...origin/main 2>$null | Select-Object -First 1)
    $ahead=0; $behind=0
    if($counts -match '^(\d+)\s+(\d+)$'){ $ahead=[int]$matches[1]; $behind=[int]$matches[2] }
    $status=@(& rtk git -C $path status --short 2>$null)
    $dirty=@($status | Where-Object { $_ -and $_.Trim() -and $_.Trim() -ne 'ok' })
    if($ahead -ne 0){ Add-Issue "upstream_ahead:${name}:$ahead" }
    if($behind -ne 0){ Add-Issue "upstream_behind:${name}:$behind" }
    if($name -ne 'gstack' -and $dirty.Count -gt 0){ Add-Issue "unexpected_dirty:${name}" }
    $results += [ordered]@{ name=$name; path=$path; remote=$remote; head=$head; origin_main=$origin; ahead=$ahead; behind=$behind; dirty_count=$dirty.Count; dirty=@($dirty) }
}
$result=[ordered]@{ ok=($issues.Count -eq 0); fetched=[bool]$Fetch; checked_at=(Get-Date).ToString('o'); repos=@($results); issues=@($issues) }
if($Json){ $result | ConvertTo-Json -Depth 12 } else { if($result.ok){'forge_upstreams=ok'}else{'forge_upstreams=fail'}; foreach($i in $issues){"issue=$i"} }
if(-not $result.ok){ exit 1 }
