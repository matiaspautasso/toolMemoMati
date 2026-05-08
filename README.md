# toolMemoMati

> Persistent memory framework installer for AI-assisted development.

---

## English

**toolMemoMati** is a memory framework installer for AI-assisted development. It sets up a persistent, structured memory system inside any project so that your AI agent (Claude Code, Cursor, Copilot, etc.) never loses context between sessions.

It installs and wires together three memory layers:

| Layer | Purpose |
|-------|---------|
| **Serena MCP** | Code intelligence — reads symbols, references, structure |
| **SQLite-RAG MCP** | Business rules and verified facts with confidence scores |
| **Engram MCP** | Session history, architectural decisions, bug fixes |

Each layer has a clear responsibility. The framework defines which information goes where, how conflicts are resolved (current code always wins), and what requires explicit authorization before saving (business rules always ask first).

It also installs a **memory auditor** — a standalone PowerShell script that scans your memory files, detects stale or contradicted entries, and proposes cleanup without touching anything until you approve.

### How to install it by asking your AI agent

Open the target project in Claude Code (or your preferred AI IDE) and say:

> "Use the toolMemoMati framework to set up persistent memory in this project. Clone https://github.com/matiaspautasso/toolMemoMati and run `install/memory-framework-install.ps1 -ProjectPath .` from within it."

Once installed, ask your agent:

> "Run /memory-bootstrap to initialize the memory systems for this project."

---

## Español

**toolMemoMati** es un instalador de framework de memoria para desarrollo asistido por IA. Configura un sistema de memoria persistente y estructurado dentro de cualquier proyecto, para que tu agente de IA (Claude Code, Cursor, Copilot, etc.) nunca pierda contexto entre sesiones.

Instala y conecta tres capas de memoria:

| Capa | Función |
|------|---------|
| **Serena MCP** | Inteligencia de código — lee símbolos, referencias y estructura |
| **SQLite-RAG MCP** | Reglas de negocio e invariantes verificables con nivel de confianza |
| **Engram MCP** | Historial de sesiones, decisiones técnicas y bug fixes |

Cada capa tiene una responsabilidad clara. El framework define qué información va a dónde, cómo se resuelven los conflictos (el código actual siempre gana) y qué requiere autorización explícita antes de guardar (las reglas de negocio siempre preguntan primero).

También instala un **auditor de memorias** — un script PowerShell standalone que escanea tus archivos de memoria, detecta entradas obsoletas o contradictorias, y propone limpieza sin tocar nada hasta que apruebes.

### Cómo instalarlo pidiéndoselo a tu agente de IA

Abrí el proyecto destino en Claude Code (o tu IDE de IA preferido) y decile:

> "Usá el framework toolMemoMati para configurar memoria persistente en este proyecto. Clona https://github.com/matiaspautasso/toolMemoMati y ejecutá `install/memory-framework-install.ps1 -ProjectPath .` desde ahí."

Una vez instalado, pedile a tu agente:

> "Ejecutá /memory-bootstrap para inicializar los sistemas de memoria de este proyecto."

---

## Manual Installation

```powershell
# Clone the framework
git clone https://github.com/matiaspautasso/toolMemoMati

# Install into your project
cd toolMemoMati
.\install\memory-framework-install.ps1 -ProjectPath "C:\path\to\your\project"

# Dry run first (see what would happen without making changes)
.\install\memory-framework-install.ps1 -ProjectPath "C:\path\to\your\project" -DryRun
```

## What gets installed in the target project

```
your-project/
├── .mcp.json                    ← 3 MCPs configured (Serena + SQLite-RAG + Engram)
├── CLAUDE.md                    ← memory protocol injected (markers preserved)
├── .claude/skills/
│   └── memory-bootstrap.md     ← /memory-bootstrap skill
└── memory/
    ├── business-rules/          ← RULE-*.md + rules.export.jsonl
    ├── decisions/               ← DEC-*.md
    ├── bugfixes/                ← BUG-*.md
    ├── session-log/             ← monthly session summaries
    └── audits/                  ← memory-audit-YYYY-MM-DD.md reports
```

## Memory commands

| Command | What it does |
|---------|-------------|
| `/memory-bootstrap` | Initialize memory systems in a new project |
| `/memory-audit` | Scan memories, detect stale entries, generate report (never deletes without approval) |
| `.\memory-auditor\scripts\memory-audit.ps1` | Same as above, standalone (no AI needed) |

## Dependencies

| Dependency | Role | Install |
|------------|------|---------|
| Serena MCP | Code intelligence | `pip install serena` |
| SQLite-RAG MCP | Business rules store | Configure in `.mcp.json` |
| Engram MCP | Session memory | Configure in `.mcp.json` |
| Claude Code CLI | Runtime | `npm install -g @anthropic-ai/claude-code` |
| PowerShell 5.1+ | Installer (Windows) | Pre-installed on Windows 10/11 |

## License

MIT
