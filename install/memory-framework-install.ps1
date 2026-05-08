#Requires -Version 5.1
<#
.SYNOPSIS
    Installs the toolMemoMati memory framework into a target project.
.DESCRIPTION
    Sets up Serena + SQLite-RAG + Engram memory systems in any project.
    Generates .mcp.json, injects memory protocol into CLAUDE.md (never overwrites),
    creates the memory/ directory structure, and installs the /memory-bootstrap skill.
.PARAMETER ProjectPath
    Absolute or relative path to the target project directory.
.PARAMETER ProjectName
    Project name. Auto-detected from package.json or folder name if omitted.
.PARAMETER SkipMcpCheck
    Skip MCP availability verification (use when MCPs are configured globally).
.PARAMETER DryRun
    Show what would be done without making any changes.
.EXAMPLE
    .\memory-framework-install.ps1 -ProjectPath "C:\Projects\myapp"
    .\memory-framework-install.ps1 -ProjectPath "." -DryRun
#>
param(
    [Parameter(Mandatory = $true)]
    [string]$ProjectPath,

    [string]$ProjectName = "",

    [switch]$SkipMcpCheck,

    [switch]$DryRun
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$ScriptDir    = Split-Path -Parent $MyInvocation.MyCommand.Path
$TemplatesDir = Resolve-Path (Join-Path $ScriptDir "..\templates")
$StartMarker  = "<!-- MEMORY-FRAMEWORK:START -->"
$EndMarker    = "<!-- MEMORY-FRAMEWORK:END -->"

# ── Helpers ───────────────────────────────────────────────────────────────────

function Write-Step  { param([string]$t) Write-Host "`n→ $t" -ForegroundColor Cyan }
function Write-Ok    { param([string]$t) Write-Host "  ✓ $t" -ForegroundColor Green }
function Write-Skip  { param([string]$t) Write-Host "  ~ $t (skipped)" -ForegroundColor DarkYellow }
function Write-Dry   { param([string]$t) Write-Host "  [DRY] $t" -ForegroundColor Magenta }
function Write-Fail  { param([string]$t) Write-Error "  ✗ $t" }

function Invoke-Action {
    param([string]$Description, [scriptblock]$Action)
    if ($DryRun) { Write-Dry $Description } else { & $Action }
}

# ── Step 1: Verify ProjectPath ────────────────────────────────────────────────

Write-Step "Verifying project path"
if (-not (Test-Path $ProjectPath)) {
    Write-Fail "ProjectPath '$ProjectPath' does not exist."
    exit 1
}
$ProjectPath = (Resolve-Path $ProjectPath).Path
Write-Ok "Project path: $ProjectPath"

# ── Step 2: Auto-detect ProjectName ──────────────────────────────────────────

Write-Step "Detecting project name"
if (-not $ProjectName) {
    $pkgJson = Join-Path $ProjectPath "package.json"
    if (Test-Path $pkgJson) {
        $pkg = Get-Content $pkgJson -Raw | ConvertFrom-Json
        if ($pkg.name) { $ProjectName = $pkg.name }
    }
    if (-not $ProjectName) {
        $ProjectName = Split-Path $ProjectPath -Leaf
    }
}
Write-Ok "Project: $ProjectName"

# ── Step 3: Check MCPs ────────────────────────────────────────────────────────

Write-Step "Checking MCP availability"
if ($SkipMcpCheck) {
    Write-Skip "MCP check (-SkipMcpCheck)"
} else {
    $checkScript = Join-Path $ScriptDir "check-mcps.ps1"
    & $checkScript -Quiet
    if ($LASTEXITCODE -ne 0) {
        Write-Host ""
        Write-Host "  Some MCPs are not configured. Options:" -ForegroundColor Yellow
        Write-Host "    1. Add them to .mcp.json (see templates/mcp.json.template)"
        Write-Host "    2. Re-run with -SkipMcpCheck to proceed anyway"
        exit 1
    }
    Write-Ok "All MCPs configured"
}

# ── Step 4: Generate .mcp.json ────────────────────────────────────────────────

Write-Step "Generating .mcp.json"
$mcpTarget = Join-Path $ProjectPath ".mcp.json"

Invoke-Action ".mcp.json → $mcpTarget" {
    if (Test-Path $mcpTarget) {
        Write-Skip ".mcp.json already exists — not overwriting. Verify it includes serena, sqlite-rag, engram."
    } else {
        $template = Get-Content (Join-Path $TemplatesDir "mcp.json.template") -Raw
        Set-Content -Path $mcpTarget -Value $template -Encoding UTF8
        Write-Ok "Created .mcp.json (customize {{SQLITE_RAG_PATH}} and {{ENGRAM_PATH}} placeholders)"
    }
}

# ── Step 5: Create .claude/skills/ ───────────────────────────────────────────

Write-Step "Setting up .claude/skills/"
$claudeDir = Join-Path $ProjectPath ".claude"
$skillsDir = Join-Path $claudeDir "skills"

Invoke-Action ".claude/skills/ → $skillsDir" {
    New-Item -ItemType Directory -Path $skillsDir -Force | Out-Null
    Write-Ok ".claude/skills/ ready"
}

# ── Step 6: Install /memory-bootstrap skill ───────────────────────────────────

Write-Step "Installing /memory-bootstrap skill"
$skillSrc = Join-Path $TemplatesDir "skills\memory-bootstrap.md"
$skillDst = Join-Path $skillsDir "memory-bootstrap.md"

Invoke-Action "memory-bootstrap.md → $skillDst" {
    Copy-Item $skillSrc $skillDst -Force
    Write-Ok "Installed /memory-bootstrap"
}

# ── Step 7: Inject CLAUDE.md section ─────────────────────────────────────────

Write-Step "Configuring CLAUDE.md"
$claudeMdPath  = Join-Path $ProjectPath "CLAUDE.md"
$sectionContent = Get-Content (Join-Path $TemplatesDir "CLAUDE.md.template") -Raw

Invoke-Action "CLAUDE.md injection → $claudeMdPath" {
    if (-not (Test-Path $claudeMdPath)) {
        # Case a: no file — create from template
        Set-Content -Path $claudeMdPath -Value $sectionContent -Encoding UTF8
        Write-Ok "Created CLAUDE.md from template"
    } else {
        $existing = Get-Content $claudeMdPath -Raw
        if ($existing -notmatch [regex]::Escape($StartMarker)) {
            # Case b: exists, no markers — append
            $newContent = $existing.TrimEnd() + "`n`n" + $sectionContent
            Set-Content -Path $claudeMdPath -Value $newContent -Encoding UTF8
            Write-Ok "Appended memory protocol to existing CLAUDE.md"
        } else {
            # Case c: markers exist — replace block only
            $pattern    = [regex]::Escape($StartMarker) + "[\s\S]*?" + [regex]::Escape($EndMarker)
            $replacement = $sectionContent.Trim()
            $newContent  = [regex]::Replace($existing, $pattern, $replacement)
            Set-Content -Path $claudeMdPath -Value $newContent -Encoding UTF8
            Write-Ok "Updated memory protocol section in CLAUDE.md (rest of file unchanged)"
        }
    }
}

# ── Step 8: Create memory/ structure ─────────────────────────────────────────

Write-Step "Creating memory/ directory structure"
$memDirs = @(
    "memory\business-rules",
    "memory\decisions",
    "memory\bugfixes",
    "memory\session-log",
    "memory\audits"
)

Invoke-Action "memory/ → $ProjectPath" {
    foreach ($dir in $memDirs) {
        New-Item -ItemType Directory -Path (Join-Path $ProjectPath $dir) -Force | Out-Null
    }
    # Audit counter starts at 0
    Set-Content -Path (Join-Path $ProjectPath "memory\.audit-counter") -Value "0" -Encoding UTF8
    Write-Ok "Created memory/ structure ($($memDirs.Count) directories)"
}

# ── Step 9: Update .gitignore ─────────────────────────────────────────────────

Write-Step "Updating .gitignore"
$gitignorePath = Join-Path $ProjectPath ".gitignore"
$requiredEntries = @(
    "memory/business-rules.sqlite",
    "memory/.audit-counter",
    "memory/cache/"
)

Invoke-Action ".gitignore → $gitignorePath" {
    if (Test-Path $gitignorePath) {
        $current = Get-Content $gitignorePath -Raw
        $toAdd   = $requiredEntries | Where-Object { $current -notmatch [regex]::Escape($_) }
        if ($toAdd.Count -gt 0) {
            $block = "`n# toolMemoMati — runtime files (do not commit)`n" + ($toAdd -join "`n") + "`n"
            Add-Content -Path $gitignorePath -Value $block -Encoding UTF8
            Write-Ok "Added $($toAdd.Count) entr$(if($toAdd.Count -eq 1){'y'}else{'ies'}) to .gitignore"
        } else {
            Write-Skip ".gitignore already contains all required entries"
        }
    } else {
        $content = "# toolMemoMati — runtime files (do not commit)`n" + ($requiredEntries -join "`n") + "`n"
        Set-Content -Path $gitignorePath -Value $content -Encoding UTF8
        Write-Ok "Created .gitignore"
    }
}

# ── Step 10: Summary ──────────────────────────────────────────────────────────

$prefix = if ($DryRun) { "[DRY RUN] " } else { "" }

Write-Host "`n$($prefix)=== Installation Complete ===" -ForegroundColor Green
Write-Host "  Project : $ProjectName"
Write-Host "  Path    : $ProjectPath"
Write-Host ""
Write-Host "Next steps:" -ForegroundColor Yellow
Write-Host "  1. Edit .mcp.json — replace {{SQLITE_RAG_PATH}} and {{ENGRAM_PATH}} with actual server paths"
Write-Host "  2. Open the project in Claude Code"
Write-Host "  3. Run /memory-bootstrap to initialize Serena, SQLite-RAG, and Engram"
Write-Host "  4. Run memory-audit.ps1 every 10 sessions (or /memory-audit in Claude Code)"
