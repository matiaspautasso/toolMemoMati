# Persistent Memory Framework for AI Coding Agents

> Portable memory installer for Claude Code, Cursor, and AI-assisted development workflows using Serena MCP, SQLite-RAG, Engram, and memory auditing scripts.

---

## Engineering Highlights

- Built a portable persistent memory framework for AI-assisted software development.
- Integrated multiple memory layers: code intelligence, structured business rules, and session history.
- Designed a clear conflict-resolution model where current code is always treated as the source of truth.
- Created a PowerShell installer to bootstrap the memory framework into any target project.
- Added a standalone memory auditor to detect stale, duplicated, or contradicted memory entries.
- Defined explicit authorization rules: what the AI can save automatically and what requires user approval.
- Created reusable workflows for Claude Code, Cursor, Copilot, and MCP-based development environments.

---

## Architecture

The framework is organized into four main layers:

| Layer | Tool | Purpose |
|-------|------|---------|
| Code Intelligence | Serena MCP | Reads symbols, references, files, and project structure |
| Structured Knowledge | SQLite-RAG MCP | Stores verified business rules, invariants, and facts with confidence scores |
| Session Memory | Engram MCP | Preserves session history, architectural decisions, and bug fixes |
| Memory Audit | PowerShell auditor | Scans memories, detects stale entries, and generates cleanup reports |

Each layer has a distinct responsibility. The framework defines what goes where, how conflicts are resolved, and what requires explicit user authorization before being saved.

---

## What You Get

Once installed in a project, your AI agent will:

- Remember architectural decisions and why they were made — across sessions, without re-explaining.
- Retain verified business rules and never re-introduce contradicted assumptions.
- Track bug root causes so the same mistake is not repeated.
- Know the project structure, modules, and conventions from the first message of each session.
- Run periodic memory audits to surface outdated or contradictory information.
- Respect an explicit authorization model — critical information is never saved without your approval.

---

## Use Cases

- Add persistent memory to a Claude Code or Cursor project.
- Prevent AI agents from losing project context between sessions.
- Store verified business rules and technical decisions in a structured, auditable format.
- Detect and clean up outdated or contradictory memories.
- Keep project knowledge synchronized with the current codebase.
- Standardize memory behavior across multiple repositories.

---

## Demo

```powershell
git clone https://github.com/matiaspautasso/toolMemoMati
cd toolMemoMati

.\install\memory-framework-install.ps1 -ProjectPath "C:\path\to\your\project" -DryRun
```

Expected output:

```
Analyzing target project...
Checking MCP availability (Serena, SQLite-RAG, Engram)...
Checking memory framework files...
Preparing .mcp.json configuration...
Preparing CLAUDE.md memory protocol (markers preserved)...
Preparing memory/ folder structure...
Dry run completed. No files were written.
```

Remove `-DryRun` to apply.

---

## Safety Model

- **Current code always wins** over saved memory — no stale rule can override what exists in the codebase.
- **Business rules require explicit approval** before being stored — the AI always asks first.
- **Memory audit reports never delete files automatically** — they propose changes and wait for authorization.
- **Installer supports dry-run mode** — see exactly what would change before writing anything.
- **Conflicting memories are flagged**, not silently overwritten — the audit report shows the contradiction and recommends a resolution.

---

## What Gets Installed

```
your-project/
├── .mcp.json                    ← 3 MCPs configured (Serena + SQLite-RAG + Engram)
├── CLAUDE.md                    ← memory protocol injected (existing content preserved)
├── .claude/
│   └── skills/
│       └── memory-bootstrap.md  ← /memory-bootstrap skill
└── memory/
    ├── business-rules/          ← RULE-*.md + rules.export.jsonl
    ├── decisions/               ← DEC-*.md
    ├── bugfixes/                ← BUG-*.md
    ├── session-log/             ← monthly session summaries
    └── audits/                  ← memory-audit-YYYY-MM-DD.md reports
```

CLAUDE.md injection uses HTML comment markers — the installer never overwrites existing content, only manages its own block:

```
<!-- MEMORY-FRAMEWORK:START -->
...memory protocol...
<!-- MEMORY-FRAMEWORK:END -->
```

---

## Memory Commands

| Command | What it does |
|---------|-------------|
| `/memory-bootstrap` | Initialize memory systems in a new project |
| `/memory-audit` | Scan memories, detect stale entries, generate a report (never deletes without approval) |
| `.\memory-auditor\scripts\memory-audit.ps1` | Standalone audit script — works without AI |

---

## How to Install

### Option A — Ask your AI agent

Open the target project in Claude Code and say:

> "Use the toolMemoMati framework to set up persistent memory in this project. Clone https://github.com/matiaspautasso/toolMemoMati and run `install/memory-framework-install.ps1 -ProjectPath .` from within it."

Once installed, ask your agent:

> "Run /memory-bootstrap to initialize the memory systems for this project."

### Option B — Run the installer manually

```powershell
git clone https://github.com/matiaspautasso/toolMemoMati
cd toolMemoMati

# Dry run first (no changes)
.\install\memory-framework-install.ps1 -ProjectPath "C:\path\to\your\project" -DryRun

# Apply
.\install\memory-framework-install.ps1 -ProjectPath "C:\path\to\your\project"
```

---

## Dependencies

| Dependency | Role | Install |
|------------|------|---------|
| Serena MCP | Code intelligence | `pip install serena` |
| SQLite-RAG MCP | Business rules store | Configure in `.mcp.json` |
| Engram MCP | Session memory | Configure in `.mcp.json` |
| Claude Code CLI | Runtime | `npm install -g @anthropic-ai/claude-code` |
| PowerShell 5.1+ | Installer | Pre-installed on Windows 10/11 |

---

## Why This Matters

This project demonstrates practical experience in:

- **AI workflow engineering** — building infrastructure that makes AI agents more reliable and context-aware.
- **MCP-based tooling** — integrating multiple Model Context Protocol servers into a unified system.
- **Developer automation** — PowerShell installers and scripts that bootstrap complex setups in seconds.
- **Persistent context design** — solving the stateless-session problem in AI-assisted development.
- **Knowledge management** — structured, versioned, and auditable memory for software projects.
- **Multi-environment support** — compatible with Claude Code, Cursor, Copilot, and generic MCP setups.

---

## Preview

![Architecture](assets/architecture.png)
![Memory audit output](assets/memory-audit-output.png)

---

## License

MIT
