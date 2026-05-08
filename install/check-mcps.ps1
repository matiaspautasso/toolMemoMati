#Requires -Version 5.1
<#
.SYNOPSIS
    Verifies availability of the 3 MCPs required by toolMemoMati.
.DESCRIPTION
    Checks Serena, SQLite-RAG, and Engram are configured in the current
    Claude Code environment. Exits with code 1 if any critical MCP is missing.
.PARAMETER Quiet
    Suppress output (still exits with code 1 on failure).
#>
param(
    [switch]$Quiet
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$McpNames = @(
    @{ Name = "serena";     Description = "Code intelligence + structural memories" },
    @{ Name = "sqlite-rag"; Description = "Business rules and verified facts"        },
    @{ Name = "engram";     Description = "Session history and decisions"             }
)

function Find-McpConfig {
    param([string]$McpName)

    $searchPaths = @(
        (Join-Path $env:USERPROFILE ".claude\settings.json"),
        (Join-Path $env:USERPROFILE ".claude\settings.local.json"),
        (Join-Path (Get-Location) ".mcp.json"),
        (Join-Path (Get-Location) ".claude\settings.json")
    )

    foreach ($path in $searchPaths) {
        if (Test-Path $path) {
            $content = Get-Content $path -Raw -ErrorAction SilentlyContinue
            if ($content -and $content -match [regex]::Escape($McpName)) {
                return $path
            }
        }
    }
    return $null
}

$results  = @()
$anyMissing = $false

foreach ($mcp in $McpNames) {
    $source = Find-McpConfig -McpName $mcp.Name
    $ok     = $null -ne $source

    if (-not $ok) { $anyMissing = $true }

    $results += [PSCustomObject]@{
        MCP         = $mcp.Name
        Status      = if ($ok) { "OK" } else { "MISSING" }
        Source      = if ($ok) { $source } else { "—" }
        Description = $mcp.Description
        Action      = if (-not $ok) { "Add to .mcp.json — see templates/mcp.json.template" } else { "" }
    }
}

if (-not $Quiet) {
    Write-Host "`n=== MCP Availability Check ===" -ForegroundColor Cyan
    $results | Format-Table MCP, Status, Source, Action -AutoSize

    if ($anyMissing) {
        $missing = ($results | Where-Object { $_.Status -eq "MISSING" } | ForEach-Object { $_.MCP }) -join ", "
        Write-Host "Missing: $missing" -ForegroundColor Red
        Write-Host "Copy templates/mcp.json.template to .mcp.json and fill in the server paths." -ForegroundColor Yellow
    } else {
        Write-Host "All MCPs are configured." -ForegroundColor Green
    }
}

if ($anyMissing) { exit 1 }
