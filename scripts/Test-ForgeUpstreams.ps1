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

function Invoke-GitLines {
    param(
        [string]$Path,
        [string[]]$Arguments
    )
    $output = @(& rtk git -C $Path @Arguments 2>&1)
    return [ordered]@{
        exit_code = $LASTEXITCODE
        output = @($output | ForEach-Object { [string]$_ })
    }
}

$results=@()
foreach($name in $repos.Keys){
    $path=$repos[$name]
    if(-not(Test-Path -LiteralPath $path)){ Add-Issue "upstream_missing:$name"; continue }
    $fetchError = ""
    if($Fetch){
        $fetch = Invoke-GitLines -Path $path -Arguments @('fetch','--prune','origin')
        if($fetch.exit_code -ne 0){
            $fetchError = (($fetch.output | Where-Object { $_ -and $_.Trim() -and $_.Trim() -ne 'ok' }) -join "`n").Trim()
            Add-Issue "fetch_failed:${name}"
        }
    }
    $remote=(& rtk git -C $path remote get-url origin 2>$null | Select-Object -First 1)
    $branch=(& rtk git -C $path branch --show-current 2>$null | Select-Object -First 1)
    $head=(& rtk git -C $path rev-parse --short HEAD 2>$null | Select-Object -First 1)
    $headFull=(& rtk git -C $path rev-parse HEAD 2>$null | Select-Object -First 1)
    $origin=(& rtk git -C $path rev-parse --short origin/main 2>$null | Select-Object -First 1)
    $originFull=(& rtk git -C $path rev-parse origin/main 2>$null | Select-Object -First 1)
    $counts=(& rtk git -C $path rev-list --left-right --count HEAD...origin/main 2>$null | Select-Object -First 1)
    $ahead=0; $behind=0
    if($counts -match '^(\d+)\s+(\d+)$'){ $ahead=[int]$matches[1]; $behind=[int]$matches[2] }
    $status=@(& rtk git -C $path status --short 2>$null)
    $dirty=@($status | Where-Object { $_ -and $_.Trim() -and $_.Trim() -ne 'ok' })
    if($ahead -ne 0){ Add-Issue "upstream_ahead:${name}:$ahead" }
    if($behind -ne 0){ Add-Issue "upstream_behind:${name}:$behind" }
    if($name -ne 'gstack' -and $dirty.Count -gt 0){ Add-Issue "unexpected_dirty:${name}" }
    $results += [ordered]@{
        name=$name
        path=$path
        remote=$remote
        branch=$branch
        head=$head
        head_full=$headFull
        origin_main=$origin
        origin_main_full=$originFull
        ahead=$ahead
        behind=$behind
        is_current=($behind -eq 0 -and $ahead -eq 0)
        dirty_count=$dirty.Count
        dirty=@($dirty)
        fetch_error=$fetchError
    }
}
$result=[ordered]@{ ok=($issues.Count -eq 0); fetched=[bool]$Fetch; checked_at=(Get-Date).ToString('o'); repos=@($results); issues=@($issues) }
if($Json){ $result | ConvertTo-Json -Depth 12 } else { if($result.ok){'forge_upstreams=ok'}else{'forge_upstreams=fail'}; foreach($i in $issues){"issue=$i"} }
if(-not $result.ok){ exit 1 }
