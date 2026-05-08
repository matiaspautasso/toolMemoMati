#Requires -Version 5.1
<#
.SYNOPSIS
    Standalone memory auditor — no AI dependency required.
.DESCRIPTION
    Scans memory/business-rules/, memory/decisions/, and memory/bugfixes/.
    Classifies each entry as vigente/dudosa/obsoleta/reemplazada.
    Detects contradictions between entries in the same module.
    Generates a Markdown report in memory/audits/.
    Detects the active AI environment and updates the corresponding adapter.
    NEVER deletes or modifies memory files — only reports and proposes.
.PARAMETER ProjectPath
    Root of the project to audit. Defaults to current directory.
.PARAMETER NoAdapters
    Skip adapter generation (report only).
.PARAMETER ObsoletaDays
    Days since last update before an entry is classified obsoleta. Default: 30.
.PARAMETER DudosaDays
    Days since last update before an entry is classified dudosa. Default: 90.
.EXAMPLE
    .\memory-audit.ps1
    .\memory-audit.ps1 -ProjectPath "C:\Projects\myapp" -ObsoletaDays 60
#>
param(
    [string]$ProjectPath  = ".",
    [switch]$NoAdapters,
    [int]$ObsoletaDays    = 30,
    [int]$DudosaDays      = 90
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$ProjectPath = (Resolve-Path $ProjectPath).Path
$MemoryDir   = Join-Path $ProjectPath "memory"
$AuditsDir   = Join-Path $MemoryDir "audits"
$Today       = Get-Date
$ReportDate  = $Today.ToString("yyyy-MM-dd")
$ReportPath  = Join-Path $AuditsDir "audit-$ReportDate.md"
$AdaptersDir = Join-Path $PSScriptRoot "..\adapters"
$CounterPath = Join-Path $MemoryDir ".audit-counter"

if (-not (Test-Path $MemoryDir)) {
    Write-Error "memory/ not found at $MemoryDir. Run memory-framework-install.ps1 first."
    exit 1
}
New-Item -ItemType Directory -Path $AuditsDir -Force | Out-Null

# ── Helpers ───────────────────────────────────────────────────────────────────

function Get-YamlValue {
    param([string]$Yaml, [string]$Key)
    if ($Yaml -match "(?m)^$Key\s*:\s*(.+)$") { return $matches[1].Trim().Trim('"').Trim("'") }
    return ""
}

function Get-YamlList {
    param([string]$Content, [string]$Key)
    $items = @()
    if ($Content -match "(?s)${Key}:\s*\n((?:[ \t]+-[^\n]+\n?)+)") {
        $items = $matches[1] -split "`n" |
            Where-Object { $_ -match "^\s+-\s+" } |
            ForEach-Object { ($_ -replace "^\s+-\s+", "").Trim() }
    }
    return $items
}

function Read-MemoryFile {
    param([string]$FilePath)
    $content = Get-Content $FilePath -Raw
    if ($content -notmatch "(?s)^---\s*\n(.*?)\n---") { return $null }
    $yaml = $matches[1]

    $fechaStr = Get-YamlValue $yaml "fecha_actualizacion"
    if (-not $fechaStr) { $fechaStr = Get-YamlValue $yaml "fecha" }
    $fecha = if ($fechaStr) { [datetime]::ParseExact($fechaStr, "yyyy-MM-dd", $null) } else { $null }

    return [PSCustomObject]@{
        FilePath   = $FilePath
        FileName   = Split-Path $FilePath -Leaf
        Id         = Get-YamlValue $yaml "id"
        Tipo       = Get-YamlValue $yaml "tipo"
        Modulo     = Get-YamlValue $yaml "modulo"
        Titulo     = Get-YamlValue $yaml "titulo"
        Estado     = Get-YamlValue $yaml "estado"
        Confidence = try { [double](Get-YamlValue $yaml "confidence") } catch { 0.0 }
        ReemplazadaPor = Get-YamlValue $yaml "reemplazada_por"
        Impacto    = Get-YamlList $content "impacto"
        Archivos   = Get-YamlList $content "archivos"
        Fecha      = $fecha
        DaysOld    = if ($fecha) { ($Today - $fecha).Days } else { 999 }
        Yaml       = $yaml
    }
}

function Test-CodeReference {
    param([string]$Symbol, [string]$ProjectPath)
    if ([string]::IsNullOrWhiteSpace($Symbol)) { return $false }
    # Strip file-path suffixes like → func() for grep
    $clean = ($Symbol -replace "\s*→.*$", "").Trim()
    try {
        $hits = & git -C $ProjectPath grep -r -l --count $clean 2>$null
        return ($hits | Measure-Object).Count -gt 0
    } catch {
        # Fallback: use Select-String
        $hits = Get-ChildItem $ProjectPath -Recurse -File -ErrorAction SilentlyContinue |
            Where-Object { $_.Extension -in @(".ts",".js",".py",".cs",".go",".java",".rb",".php") } |
            Select-String -Pattern ([regex]::Escape($clean)) -ErrorAction SilentlyContinue
        return ($hits | Measure-Object).Count -gt 0
    }
}

function Get-Environment {
    if (Test-Path (Join-Path $ProjectPath ".claude")) { return "claude-code" }
    if (Test-Path (Join-Path $ProjectPath ".cursor"))  { return "cursor"      }
    if (Test-Path (Join-Path $ProjectPath ".codex"))   { return "codex"       }
    return "generic"
}

# ── Load all memory files ─────────────────────────────────────────────────────

$allEntries = [System.Collections.Generic.List[PSCustomObject]]::new()

$typeDirs = @(
    @{ Dir = "business-rules"; Pattern = "RULE-*.md" },
    @{ Dir = "decisions";      Pattern = "DEC-*.md"  },
    @{ Dir = "bugfixes";       Pattern = "BUG-*.md"  }
)

foreach ($td in $typeDirs) {
    $dir = Join-Path $MemoryDir $td.Dir
    if (-not (Test-Path $dir)) { continue }
    Get-ChildItem -Path $dir -Filter $td.Pattern | ForEach-Object {
        $entry = Read-MemoryFile -FilePath $_.FullName
        if ($entry -and $entry.Id) { $allEntries.Add($entry) }
    }
}

Write-Host "Loaded $($allEntries.Count) memory entries" -ForegroundColor Cyan

# ── Classify each entry ───────────────────────────────────────────────────────

$classified = [System.Collections.Generic.List[PSCustomObject]]::new()

foreach ($entry in $allEntries) {
    $audit = [PSCustomObject]@{
        Entry          = $entry
        AuditState     = $entry.Estado
        Evidence       = @()
        MissingRefs    = @()
        Reason         = ""
    }

    # Already marked reemplazada/obsoleta — keep as-is
    if ($entry.Estado -in @("reemplazada","obsoleta")) {
        $audit.Reason = "Already marked $($entry.Estado)"
        $classified.Add($audit)
        continue
    }

    # Check reemplazada_por
    if ($entry.ReemplazadaPor -and $entry.ReemplazadaPor -ne "null") {
        $audit.AuditState = "reemplazada"
        $audit.Reason     = "reemplazada_por = $($entry.ReemplazadaPor)"
        $classified.Add($audit)
        continue
    }

    # Resolve impacto symbols (combine impacto + archivos)
    $symbols = @($entry.Impacto) + @($entry.Archivos) | Where-Object { $_ }

    if ($symbols.Count -gt 0) {
        $hits    = 0
        $missing = @()
        foreach ($sym in $symbols) {
            if (Test-CodeReference -Symbol $sym -ProjectPath $ProjectPath) {
                $hits++
                $audit.Evidence += $sym
            } else {
                $missing += $sym
                $audit.MissingRefs += $sym
            }
        }

        if ($hits -eq 0 -and $entry.DaysOld -ge $ObsoletaDays) {
            $audit.AuditState = "obsoleta"
            $audit.Reason     = "0/$($symbols.Count) symbols found in codebase, $($entry.DaysOld)d old"
        } elseif ($hits -lt $symbols.Count -or $entry.DaysOld -ge $DudosaDays) {
            $audit.AuditState = "dudosa"
            $audit.Reason     = "$hits/$($symbols.Count) symbols found, $($entry.DaysOld)d old"
        } else {
            $audit.Reason = "$hits/$($symbols.Count) symbols verified"
        }
    } else {
        # No symbols to verify — classify by age only
        if ($entry.DaysOld -ge $ObsoletaDays) {
            $audit.AuditState = "dudosa"
            $audit.Reason     = "No impacto symbols to verify, $($entry.DaysOld)d since last update"
        } else {
            $audit.Reason = "No symbols to verify (accepted)"
        }
    }

    $classified.Add($audit)
}

# ── Detect contradictions ─────────────────────────────────────────────────────

$contradictions = [System.Collections.Generic.List[PSCustomObject]]::new()
$grouped = $classified | Group-Object { $_.Entry.Modulo }

foreach ($group in $grouped) {
    $items = @($group.Group)
    for ($i = 0; $i -lt $items.Count; $i++) {
        for ($j = $i + 1; $j -lt $items.Count; $j++) {
            $a = $items[$i].Entry
            $b = $items[$j].Entry
            if ($a.Estado -in @("obsoleta","reemplazada") -or $b.Estado -in @("obsoleta","reemplazada")) { continue }

            # Simple word-overlap similarity on titulo
            $wordsA = ($a.Titulo -replace "[^\w\s]","").ToLower() -split "\s+"
            $wordsB = ($b.Titulo -replace "[^\w\s]","").ToLower() -split "\s+"
            $union  = (@($wordsA) + @($wordsB) | Sort-Object -Unique).Count
            $inter  = ($wordsA | Where-Object { $wordsB -contains $_ }).Count
            $sim    = if ($union -gt 0) { $inter / $union } else { 0 }

            if ($sim -ge 0.7) {
                $winner = if ($a.Confidence -ge $b.Confidence) { $a.Id } else { $b.Id }
                $contradictions.Add([PSCustomObject]@{
                    EntryA      = $a
                    EntryB      = $b
                    Similarity  = [math]::Round($sim, 2)
                    Proposed    = "Keep $winner (higher confidence / more recent)"
                })
            }
        }
    }
}

# ── Build report ──────────────────────────────────────────────────────────────

$vigentes    = @($classified | Where-Object { $_.AuditState -eq "vigente" })
$dudosas     = @($classified | Where-Object { $_.AuditState -eq "dudosa" })
$obsoletas   = @($classified | Where-Object { $_.AuditState -eq "obsoleta" })
$reemplazadas = @($classified | Where-Object { $_.AuditState -eq "reemplazada" })

$reportLines = [System.Collections.Generic.List[string]]::new()
$reportLines.Add("# Memory Audit Report — $ReportDate")
$reportLines.Add("")
$reportLines.Add("## Summary")
$reportLines.Add("")
$reportLines.Add("| State | Count |")
$reportLines.Add("|-------|-------|")
$reportLines.Add("| vigente | $($vigentes.Count) |")
$reportLines.Add("| dudosa | $($dudosas.Count) |")
$reportLines.Add("| obsoleta | $($obsoletas.Count) |")
$reportLines.Add("| reemplazada | $($reemplazadas.Count) |")
$reportLines.Add("| **Total** | **$($classified.Count)** |")
$reportLines.Add("| Contradictions | $($contradictions.Count) |")
$reportLines.Add("")

if ($obsoletas.Count -gt 0) {
    $reportLines.Add("## Obsoletas — proposed for removal (requires HIGH authorization)")
    $reportLines.Add("")
    foreach ($item in $obsoletas) {
        $reportLines.Add("### $($item.Entry.Id) — $($item.Entry.Titulo)")
        $reportLines.Add("- **Reason**: $($item.Reason)")
        $reportLines.Add("- **File**: $($item.Entry.FileName)")
        if ($item.MissingRefs.Count -gt 0) {
            $reportLines.Add("- **Missing refs**: $($item.MissingRefs -join ', ')")
        }
        $reportLines.Add("- **Proposed action**: Mark as `obsoleta` → delete with user authorization")
        $reportLines.Add("")
    }
}

if ($dudosas.Count -gt 0) {
    $reportLines.Add("## Dudosas — review recommended (requires MEDIUM authorization)")
    $reportLines.Add("")
    foreach ($item in $dudosas) {
        $reportLines.Add("### $($item.Entry.Id) — $($item.Entry.Titulo)")
        $reportLines.Add("- **Reason**: $($item.Reason)")
        $reportLines.Add("- **File**: $($item.Entry.FileName)")
        if ($item.MissingRefs.Count -gt 0) {
            $reportLines.Add("- **Missing refs**: $($item.MissingRefs -join ', ')")
        }
        $reportLines.Add("- **Proposed action**: Review and update `estado` to `vigente` or `obsoleta`")
        $reportLines.Add("")
    }
}

if ($contradictions.Count -gt 0) {
    $reportLines.Add("## Contradictions — unification required (requires MEDIUM authorization)")
    $reportLines.Add("")
    foreach ($c in $contradictions) {
        $reportLines.Add("### $($c.EntryA.Id) vs $($c.EntryB.Id) (similarity: $($c.Similarity))")
        $reportLines.Add("- **Module**: $($c.EntryA.Modulo)")
        $reportLines.Add("- **A**: $($c.EntryA.Titulo)")
        $reportLines.Add("- **B**: $($c.EntryB.Titulo)")
        $reportLines.Add("- **Proposed**: $($c.Proposed)")
        $reportLines.Add("")
    }
}

if ($vigentes.Count -gt 0) {
    $reportLines.Add("## Vigentes ($($vigentes.Count) entries — no action needed)")
    $reportLines.Add("")
    foreach ($item in $vigentes) {
        $reportLines.Add("- $($item.Entry.Id) — $($item.Entry.Titulo) ($($item.Reason))")
    }
}

Set-Content -Path $ReportPath -Value ($reportLines -join "`n") -Encoding UTF8
Write-Host "Report saved: $ReportPath" -ForegroundColor Green

# ── Update audit counter ──────────────────────────────────────────────────────

$count = 0
if (Test-Path $CounterPath) {
    $count = [int](Get-Content $CounterPath -Raw -ErrorAction SilentlyContinue)
}
Set-Content -Path $CounterPath -Value ($count + 1).ToString() -Encoding UTF8

# ── Generate adapters ─────────────────────────────────────────────────────────

if (-not $NoAdapters) {
    $env        = Get-Environment
    $reportRef  = "memory/audits/audit-$ReportDate.md"
    $summary    = "Total: $($classified.Count) | obsoletas: $($obsoletas.Count) | dudosas: $($dudosas.Count) | contradictions: $($contradictions.Count)"

    $adapterContent = @"
# Memory Audit Adapter — $env
> Generated by memory-audit.ps1 on $ReportDate. Do not edit manually.

## Audit summary
$summary

## Report location
``$reportRef``

## Instructions

An audit report exists at ``$reportRef``. Read it and execute the proposed changes
following the authorization protocol:

| Action | Risk | Required |
|--------|------|----------|
| Mark entry as dudosa | Low | Automatic |
| Mark entry as obsoleta | Medium | Show proposal → wait for confirmation |
| Delete entry | High | Always confirm — describe full impact |
| Resolve contradiction | Medium | Show resolution → wait for confirmation |

Steps:
1. Read the report at ``$reportRef``
2. For each **Obsoleta** entry: propose to user (HIGH risk — always ask)
3. For each **Dudosa** entry: show entry details and propose review (MEDIUM risk)
4. For each **Contradiction**: show both entries, apply authority hierarchy, propose resolution
5. After each approved change: update the memory file's ``estado`` field and ``fecha_actualizacion``
6. Never delete a file — only update ``estado`` to ``obsoleta`` until user explicitly approves deletion

Authority hierarchy (when resolving contradictions):
``code > passing tests > active docs > SQLite-RAG (confidence ≥ 0.8) > Engram > chat``
"@

    $adapterMap = @{
        "claude-code" = "claude-code-agent.md"
        "cursor"      = "cursor-agent.md"
        "codex"       = "codex-agent.md"
        "generic"     = "generic-agent.md"
    }

    $adapterFile = Join-Path $AdaptersDir $adapterMap[$env]
    New-Item -ItemType Directory -Path $AdaptersDir -Force | Out-Null
    Set-Content -Path $adapterFile -Value $adapterContent -Encoding UTF8
    Write-Host "Adapter updated: $adapterFile ($env)" -ForegroundColor Cyan
}

# ── Final output ──────────────────────────────────────────────────────────────

Write-Host ""
Write-Host "=== Audit Complete ===" -ForegroundColor Green
Write-Host "  vigentes:      $($vigentes.Count)"
Write-Host "  dudosas:       $($dudosas.Count)"  -ForegroundColor $(if ($dudosas.Count -gt 0) { "Yellow" } else { "White" })
Write-Host "  obsoletas:     $($obsoletas.Count)" -ForegroundColor $(if ($obsoletas.Count -gt 0) { "Red" } else { "White" })
Write-Host "  contradictions: $($contradictions.Count)" -ForegroundColor $(if ($contradictions.Count -gt 0) { "Yellow" } else { "White" })
