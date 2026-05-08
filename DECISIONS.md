# toolMemoMati — Decisiones de Diseño

> Registro de decisiones resueltas. Cada entrada tiene: contexto, opciones evaluadas, decisión tomada, motivo y consecuencias de implementación.

---

## DEC-001 — Scope de SQLite-RAG: por proyecto

**Estado:** RESUELTO  
**Fecha:** 2026-05-06  
**Impacta:** §3, §7, §9 del PLAN.md

### Contexto

SQLite-RAG puede almacenar datos en un archivo `.sqlite` por proyecto o en una base global (`~/.claude/memory.db`) usando un campo `scope = "project"` para aislar datos.

### Opciones evaluadas

| Opción | Ventaja | Desventaja |
|--------|---------|------------|
| **A — Por proyecto** (`memory/business-rules.sqlite`) | Portable, aislado, fácil de copiar con el repo, backup natural | Cada proyecto tiene su propia BD, sin reutilización cross-proyecto |
| B — Global con scope | Un solo lugar, más simple de administrar | Acoplado a la máquina, no viaja con el repo, backup complejo |

### Decisión

**Opción A — por proyecto.**

### Paths definidos

```
{proyecto}/
└── memory/
    ├── business-rules.sqlite              ← BD SQLite del proyecto (no versionar)
    └── business-rules/
        └── rules.export.jsonl             ← export versionable (sí versionar)
```

### Consecuencias de implementación

- `check-mcps.ps1` debe verificar que SQLite-RAG puede apuntar a una ruta custom por proyecto.
- `memory-framework-install.ps1` debe pasar `--db-path memory/business-rules.sqlite` al configurar el MCP en `.mcp.json`.
- `.gitignore` del proyecto destino debe incluir `memory/business-rules.sqlite`.
- `memory/business-rules/rules.export.jsonl` sí debe commitearse — es la fuente versionable legible por humanos.
- El script `export-rules.ps1` exporta desde `.sqlite` → `.jsonl` antes de cada commit relevante.

---

## DEC-002 — CLAUDE.md: inyección marcada, nunca sobreescribir

**Estado:** RESUELTO  
**Fecha:** 2026-05-06  
**Impacta:** §7 del PLAN.md

### Contexto

El instalador necesita escribir una sección en `CLAUDE.md` del proyecto destino con el protocolo de memorias. El riesgo es destruir configuración custom preexistente.

### Opciones evaluadas

| Opción | Ventaja | Desventaja |
|--------|---------|------------|
| A — Sobreescribir con template | Simple | Destruye configuración custom del proyecto |
| B — No tocar si ya existe | Seguro | El protocolo de memorias nunca queda configurado |
| **C — Inyectar sección marcada** | Seguro + funcional | Requiere parsear el archivo para detectar marcadores |

### Decisión

**Opción C — inyección con marcadores HTML.**

### Comportamiento del instalador

```
SI CLAUDE.md no existe:
  → Crear desde templates/CLAUDE.md.template (contiene solo la sección del framework)

SI CLAUDE.md existe Y no contiene <!-- MEMORY-FRAMEWORK:START -->:
  → Agregar al final del archivo:

    <!-- MEMORY-FRAMEWORK:START -->
    ## Protocolo de Memorias — toolMemoMati

    [contenido del protocolo]

    <!-- MEMORY-FRAMEWORK:END -->

SI CLAUDE.md existe Y YA contiene <!-- MEMORY-FRAMEWORK:START -->:
  → Reemplazar solo el bloque entre marcadores (no tocar nada fuera)
  → Informar al usuario: "Sección de memorias actualizada (resto del archivo sin cambios)"
```

### Formato de la sección inyectada

```markdown
<!-- MEMORY-FRAMEWORK:START -->
## Protocolo de Memorias — toolMemoMati

### Jerarquía de autoridad
código > tests > docs vigente > SQLite-RAG > Engram > chat

### Sistemas activos
| Sistema | MCP | Almacena en |
|---------|-----|-------------|
| Serena | serena | `.serena/memories/` |
| SQLite-RAG | sqlite-rag | `memory/business-rules.sqlite` |
| Engram | engram | `memory/session-log/`, `memory/decisions/` |

### Niveles de autorización
| Riesgo | Ejemplos | Acción |
|--------|----------|--------|
| Bajo | resumen sesión, bug menor | automático |
| Medio | decisión técnica, convención nueva | confirmar antes de guardar |
| Alto | regla de negocio, eliminar memoria | confirmar SIEMPRE |

### Comandos
- `/memory-bootstrap` — inicializar framework en proyecto nuevo
- `/memory-audit` — auditar memorias (genera reporte, no borra)
<!-- MEMORY-FRAMEWORK:END -->
```

### Consecuencias de implementación

- `memory-framework-install.ps1` debe:
  1. Leer el CLAUDE.md existente completo.
  2. Detectar si contiene la cadena `<!-- MEMORY-FRAMEWORK:START -->`.
  3. Si no: append al final.
  4. Si sí: regex-replace solo el bloque entre marcadores.
- Los marcadores son HTML comments — no rompen ningún parser de Markdown.
- La sección inyectada es la única parte que el instalador puede tocar en CLAUDE.md.

---

## DEC-003 — memory-auditor: script portable + adapters por agente

**Estado:** RESUELTO  
**Fecha:** 2026-05-06  
**Impacta:** §6 del PLAN.md

### Contexto

El auditor de memorias necesita poder ejecutarse en distintos entornos: Claude Code, Codex, Cursor, o directamente como prompt en cualquier IA. Diseñarlo como agente Claude Code puro lo acopla a un entorno específico.

### Opciones evaluadas

| Opción | Ventaja | Desventaja |
|--------|---------|------------|
| A — Agente Claude Code | Acceso a MCP tools, más inteligente | Solo funciona con Claude Code activo |
| B — Script standalone | Portable, sin dependencia de IA | Menos contexto semántico disponible |
| **C — Script core + adapters** | Portable por defecto, agnóstico de IA, extensible | Más estructura inicial |

### Decisión

**Opción C — Script core + capa de adapters.**

El script es la fuente de verdad portable. Los adapters son "traductores" que convierten la salida del script en instrucciones para cada IA.

### Arquitectura definida

```
memory-auditor/
├── core/
│   └── audit-engine.md          ← spec del motor de auditoría (agnóstico de IA)
│                                   Define: qué analiza, cómo clasifica, qué reporta
├── adapters/
│   ├── claude-code-agent.md     ← adapter para Claude Code (usa MCP tools)
│   ├── codex-agent.md           ← adapter para GitHub Copilot / Codex
│   ├── cursor-agent.md          ← adapter para Cursor
│   └── generic-agent.md         ← adapter genérico (cualquier IA que lea un prompt)
└── scripts/
    └── memory-audit.ps1         ← implementación standalone (PowerShell)
                                    No depende de ninguna IA
```

### Flujo de funcionamiento

```
1. memory-audit.ps1 corre de forma autónoma:
   - Lee memory/business-rules/*.md
   - Lee memory/decisions/*.md
   - Lee memory/bugfixes/*.md
   - Hace grep del código para verificar referencias
   - Clasifica cada entrada: vigente | dudosa | obsoleta | reemplazada
   - Genera memory/audits/audit-YYYY-MM-DD.md

2. memory-audit.ps1 detecta el entorno disponible:
   - Busca .claude/ → genera/actualiza adapters/claude-code-agent.md
   - Busca .cursor/ → genera/actualiza adapters/cursor-agent.md
   - No detecta nada → genera memory-auditor.prompt.md (prompt genérico)

3. El adapter le dice a la IA:
   "Existe un reporte de auditoría en memory/audits/audit-YYYY-MM-DD.md.
    Léelo y ejecuta las acciones propuestas con autorización del usuario."

4. La IA aplica los cambios respetando el protocolo de autorización (§5 del PLAN)
```

### Detección de entorno en el script

```powershell
# Dentro de memory-audit.ps1
function Get-DetectedEnvironment {
    if (Test-Path ".claude") { return "claude-code" }
    if (Test-Path ".cursor")  { return "cursor" }
    if (Test-Path ".codex")   { return "codex" }
    return "generic"
}
```

### Trigger del auditor

```
Manual:    /memory-audit (skill en Claude Code) o ejecutar memory-audit.ps1 directamente
Automático: cada 10 sesiones (contador en memory/.audit-counter)
            antes de PR grande (hook en CI o pre-push git hook)
```

### Por qué cada 10 sesiones y no más frecuente

Auditar en cada sesión genera ruido y costo innecesario. Las memorias no cambian tan rápido. Cada 10 sesiones garantiza que las obsoletas se detecten antes de que acumulen demasiado.

El contador se persiste en `memory/.audit-counter` (archivo con un número entero, no versionar).

### Consecuencias de implementación

- `memory-audit.ps1` es un script PowerShell puro — sin dependencia de Claude, Serena ni MCPs.
- Puede correr en CI/CD para detectar reglas obsoletas antes de merge.
- El adapter `generic-agent.md` contiene un prompt autosuficiente que cualquier IA puede ejecutar si se le pasa manualmente.
- Los adapters se regeneran con cada corrida del script (son outputs, no se editan a mano).
- El `core/audit-engine.md` sí se edita a mano — es la spec de qué constituye una memoria obsoleta.

---

## DEC-004 — Frecuencia del auditor automático

**Estado:** RESUELTO  
**Fecha:** 2026-05-06  
**Impacta:** §6 del PLAN.md

### Decisión

Dos triggers automáticos + trigger manual siempre disponible:

| Trigger | Cuándo | Cómo |
|---------|--------|------|
| Manual | Cuando el usuario lo pide | `/memory-audit` o ejecutar `memory-audit.ps1` |
| Por sesiones | Cada 10 sesiones completadas | Contador en `memory/.audit-counter` |
| Pre-PR | Antes de un PR grande | Hook git `pre-push` o paso en CI |

### Contador de sesiones

```
memory/.audit-counter    ← número entero, se incrementa en cada mem_session_summary
                           cuando llega a 10: se resetea a 0 y dispara auditoría
                           no versionar en Git
```

### Motivo

Evitar ruido, costo innecesario y cambios no solicitados. El auditor es una herramienta de mantenimiento, no de monitoreo continuo.

---

## Resumen ejecutivo de decisiones

| # | Decisión | Elegida |
|---|----------|---------|
| DEC-001 | Scope SQLite-RAG | Por proyecto (`memory/business-rules.sqlite`) |
| DEC-002 | CLAUDE.md handling | Inyección marcada con `<!-- MEMORY-FRAMEWORK:START/END -->` |
| DEC-003 | Arquitectura auditor | Script standalone core + adapters por agente |
| DEC-004 | Frecuencia auditor | Manual + cada 10 sesiones + pre-PR |
