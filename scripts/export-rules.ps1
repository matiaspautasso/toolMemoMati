#Requires -Version 5.1
<#
.SYNOPSIS
    Exports SQLite-RAG business rules to a versionable JSONL file.
.DESCRIPTION
    Reads all RULE-*.md files from memory/business-rules/ and generates
    memory/business-rules/rules.export.jsonl — one JSON object per line.
    Run before significant commits so the versionable export stays current.
.PARAMETER ProjectPath
    Root of the project. Defaults to current directory.
.PARAMETER OutputPath
    Output JSONL file. Defaults to memory/business-rules/rules.export.jsonl.
.EXAMPLE
    .\export-rules.ps1
    .\export-rules.ps1 -ProjectPath "C:\Projects\myapp"
#>
param(
    [string]$ProjectPath = ".",
    [string]$OutputPath  = ""
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$ProjectPath = (Resolve-Path $ProjectPath).Path
if (-not $OutputPath) {
    $OutputPath = Join-Path $ProjectPath "memory\business-rules\rules.export.jsonl"
}

$rulesDir = Join-Path $ProjectPath "memory\business-rules"
if (-not (Test-Path $rulesDir)) {
    Write-Error "Directory not found: $rulesDir. Run memory-framework-install.ps1 first."
    exit 1
}

function Get-FrontMatterValue {
    param([string]$Yaml, [string]$Key)
    if ($Yaml -match "(?m)^$Key\s*:\s*(.+)$") {
        return $matches[1].Trim().Trim('"').Trim("'")
    }
    return $null
}

function Parse-FrontMatter {
    param([string]$FilePath)
    $content = Get-Content $FilePath -Raw
    if ($content -notmatch "(?s)^---\s*\n(.*?)\n---") { return $null }
    $yaml = $matches[1]

    # Parse impacto array (multi-line yaml list)
    $impacto = @()
    if ($content -match "(?s)impacto:\s*\n((?:\s+-[^\n]+\n?)+)") {
        $impacto = $matches[1] -split "`n" |
            Where-Object { $_ -match "^\s+-\s+" } |
            ForEach-Object { ($_ -replace "^\s+-\s+", "").Trim() }
    }

    return [ordered]@{
        id                  = Get-FrontMatterValue $yaml "id"
        tipo                = Get-FrontMatterValue $yaml "tipo"
        modulo              = Get-FrontMatterValue $yaml "modulo"
        titulo              = Get-FrontMatterValue $yaml "titulo"
        confidence          = [double](Get-FrontMatterValue $yaml "confidence" ?? "0")
        estado              = Get-FrontMatterValue $yaml "estado"
        reemplazada_por     = Get-FrontMatterValue $yaml "reemplazada_por"
        fecha_creacion      = Get-FrontMatterValue $yaml "fecha_creacion"
        fecha_actualizacion = Get-FrontMatterValue $yaml "fecha_actualizacion"
        autorizado_por      = Get-FrontMatterValue $yaml "autorizado_por"
        impacto             = $impacto
        _source_file        = Split-Path $FilePath -Leaf
    }
}

$ruleFiles = Get-ChildItem -Path $rulesDir -Filter "RULE-*.md" | Sort-Object Name
$exported  = 0
$skipped   = 0
$lines     = [System.Collections.Generic.List[string]]::new()

foreach ($file in $ruleFiles) {
    $parsed = Parse-FrontMatter -FilePath $file.FullName
    if ($null -eq $parsed -or $null -eq $parsed.id) {
        Write-Warning "Skipping $($file.Name) — no valid frontmatter found"
        $skipped++
        continue
    }
    $lines.Add(($parsed | ConvertTo-Json -Compress))
    $exported++
}

Set-Content -Path $OutputPath -Value ($lines -join "`n") -Encoding UTF8
Write-Host "Exported $exported rules to $OutputPath" -ForegroundColor Green
if ($skipped -gt 0) {
    Write-Host "Skipped $skipped files (invalid frontmatter)" -ForegroundColor Yellow
}
