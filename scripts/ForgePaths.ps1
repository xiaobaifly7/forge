function Get-ForgeClaudeRoot {
    param([string]$ClaudeRoot)
    if (-not [string]::IsNullOrWhiteSpace($ClaudeRoot)) {
        return $ClaudeRoot
    }
    return (Join-Path $env:USERPROFILE ".claude")
}

function Get-ForgeScriptsRoot {
    param([string]$ClaudeRoot)
    $root = Get-ForgeClaudeRoot -ClaudeRoot $ClaudeRoot
    return (Join-Path $root "scripts")
}

function Get-ForgeScriptPath {
    param(
        [Parameter(Mandatory=$true)][string]$Name,
        [string]$ClaudeRoot
    )
    return (Join-Path (Get-ForgeScriptsRoot -ClaudeRoot $ClaudeRoot) $Name)
}
