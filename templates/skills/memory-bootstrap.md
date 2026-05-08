---
name: memory-bootstrap
description: Initialize the toolMemoMati memory framework in a new project. Verifies MCPs, bootstraps Serena, populates initial facts, and creates the first Engram entry.
triggers:
  - /memory-bootstrap
---

# /memory-bootstrap

When this skill is invoked, execute the following steps in order. Stop and report if any step fails.

## Step 1 — Verify MCPs

Check that the three required MCPs are active in this session:
- `serena` — code intelligence
- `sqlite-rag` — business rules store
- `engram` — session memory

If any is missing, tell the user which one and how to add it to `.mcp.json`.

## Step 2 — Read project context

Read `CLAUDE.md` (and `.claude/CLAUDE.md` if it exists) to extract:
- Project name and stack (language, framework, main dependencies)
- Main modules or domains
- Key commands (build, test, lint)

If no `CLAUDE.md` exists, ask the user for a one-paragraph project description.

## Step 3 — Bootstrap Serena

Using the Serena MCP, create or update these memory entries:

```
project_overview      ← project name, stack, purpose (1-2 sentences)
suggested_commands    ← build / test / lint / run commands
code_style_conventions ← naming conventions, file structure patterns observed
architecture/modules  ← main modules and their responsibility
```

Run Serena's onboarding if it hasn't been done yet.

## Step 4 — Initialize SQLite-RAG

Using the SQLite-RAG MCP, create a seed entry:

```yaml
id: RULE-META-001
tipo: regla-negocio
modulo: meta
titulo: Memory framework initialized
descripcion: This project uses toolMemoMati for persistent AI memory.
confidence: 1.0
estado: vigente
fecha_creacion: {{TODAY}}
fecha_actualizacion: {{TODAY}}
autorizado_por: usuario
```

## Step 5 — Create Engram project-init entry

Using the Engram MCP (`mem_save`):

```
title: "Project memory initialized — {{PROJECT_NAME}}"
type: decision
content:
  What: toolMemoMati memory framework installed and bootstrapped
  Why: Persistent context across Claude Code sessions
  Where: .mcp.json, CLAUDE.md, .claude/skills/, memory/
  Learned: Three-layer memory system active: Serena (code), SQLite-RAG (rules), Engram (history)
```

## Step 6 — Report

Print a summary:

```
✓ Serena bootstrapped — project_overview, suggested_commands, modules
✓ SQLite-RAG initialized — RULE-META-001 seed entry created
✓ Engram initialized — project-init entry saved

Memory systems ready. Next steps:
  - Add business rules to memory/business-rules/ as RULE-{MODULE}-{NNN}.md
  - Run /memory-audit periodically to keep memories clean
  - Session summaries are saved automatically at end of each session
```
