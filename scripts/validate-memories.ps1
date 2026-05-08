#Requires -Version 5.1
<#
.SYNOPSIS
    Validates format of memory files against their JSON schemas.
.DESCRIPTION
    Checks all RULE-*.md, DEC-*.md, and BUG-*.md files in memory/ for:
    - Valid YAML frontmatter
    - Required fields present
    - ID pattern compliance
    - Valid estado values
    Prints a table with PASS/FAIL per file.
.PARAMETER ProjectPath
    Root of the project. Defaults to current directory.
.PARAMETER Type
    Filter by type: "rules", "decisions", "bugfixes", or "all" (default).
.EXAMPLE
    .\validate-memories.ps1
    .\validate-memories.ps1 -Type rules
#>
param(
    [string]$ProjectPath = ".",
    [ValidateSet("rules", "decisions", "bugfixes", "all")]
    [string]$Type = "all"
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$ProjectPath = (Resolve-Path $ProjectPath).Path
$memoryDir   = Join-Path $ProjectPath "memory"

if (-not (Test-Path $memoryDir)) {
    Write-Error "memory/ directory not found at $memoryDir"
    exit 1
}

# Validation specs per type
$specs = @{
    rules = @{
        Dir      = "business-rules"
        Pattern  = "RULE-*.md"
        IdRegex  = "^RULE-[A-Z]+-\d{3}$"
        Required = @("id","tipo","modulo","titulo","descripcion","confidence","estado","fecha_creacion","fecha_actualizacion","autorizado_por")
        TipoVal  = "regla-negocio"
        EstadoVals = @("vigente","dudosa","obsoleta","reemplazada")
    }
    decisions = @{
        Dir      = "decisions"
        Pattern  = "DEC-*.md"
        IdRegex  = "^DEC-[A-Z]+-\d{3}$"
        Required = @("id","tipo","area","titulo","decision","motivo","impacto","riesgo","estado","fecha","autorizado_por")
        TipoVal  = "decision-tecnica"
        EstadoVals = @("vigente","dudosa","obsoleta","reemplazada")
    }
    bugfixes = @{
        Dir      = "bugfixes"
        Pattern  = "BUG-*.md"
        IdRegex  = "^BUG-[A-Z]+-\d{3}$"
        Required = @("id","tipo","modulo","titulo","problema","causa_raiz","fix","archivos","estado","fecha")
        TipoVal  = "bugfix"
        EstadoVals = @("resuelto","regresion","parcial")
    }
}

function Get-YamlValue {
    param([string]$Yaml, [string]$Key)
    if ($Yaml -match "(?m)^$Key\s*:\s*(.+)$") { return $matches[1].Trim().Trim('"').Trim("'") }
    return $null
}

function Validate-File {
    param([string]$FilePath, [hashtable]$Spec)
    $errors = @()
    $content = Get-Content $FilePath -Raw

    if ($content -notmatch "(?s)^---\s*\n(.*?)\n---") {
        return @("No YAML frontmatter found")
    }
    $yaml = $matches[1]

    foreach ($field in $Spec.Required) {
        $val = Get-YamlValue $yaml $field
        if ([string]::IsNullOrWhiteSpace($val)) {
            $errors += "Missing required field: $field"
        }
    }

    $id = Get-YamlValue $yaml "id"
    if ($id -and $id -notmatch $Spec.IdRegex) {
        $errors += "ID '$id' does not match pattern $($Spec.IdRegex)"
    }

    $tipo = Get-YamlValue $yaml "tipo"
    if ($tipo -and $tipo -ne $Spec.TipoVal) {
        $errors += "tipo must be '$($Spec.TipoVal)', got '$tipo'"
    }

    $estado = Get-YamlValue $yaml "estado"
    if ($estado -and $estado -notin $Spec.EstadoVals) {
        $errors += "estado '$estado' not valid. Allowed: $($Spec.EstadoVals -join ', ')"
    }

    return $errors
}

$results  = [System.Collections.Generic.List[PSCustomObject]]::new()
$totalOk  = 0
$totalErr = 0

$typesToRun = if ($Type -eq "all") { $specs.Keys } else { @($Type) }

foreach ($typeName in $typesToRun) {
    $spec    = $specs[$typeName]
    $typeDir = Join-Path $memoryDir $spec.Dir
    if (-not (Test-Path $typeDir)) { continue }

    $files = Get-ChildItem -Path $typeDir -Filter $spec.Pattern
    foreach ($file in $files) {
        $errs = Validate-File -FilePath $file.FullName -Spec $spec
        $ok   = $errs.Count -eq 0
        if ($ok) { $totalOk++ } else { $totalErr++ }

        $results.Add([PSCustomObject]@{
            File   = $file.Name
            Type   = $typeName
            Status = if ($ok) { "PASS" } else { "FAIL" }
            Errors = if ($errs.Count -gt 0) { $errs -join " | " } else { "" }
        })
    }
}

$results | Format-Table File, Type, Status, Errors -AutoSize

Write-Host "Results: $totalOk passed, $totalErr failed" -ForegroundColor $(if ($totalErr -gt 0) { "Red" } else { "Green" })
if ($totalErr -gt 0) { exit 1 }
