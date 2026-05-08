# toolMemoMati — Plan de Implementación

> Sistema de contexto persistente para Claude Code.
> Objetivo: útil, verificable, fácil de mantener, sin memorias obsoletas.

---

## 1. Principios fundacionales

### 1.1 Jerarquía de autoridad (conflict resolution)

Cuando dos memorias se contradicen, gana la fuente más alta:

```
1. Código actual (lo que existe en el repo)
2. Tests que pasan (comportamiento verificado)
3. Documentación funcional vigente
4. SQLite-RAG (reglas de negocio con confidence ≥ 0.8)
5. Engram (historial de decisiones y sesiones)
6. Chat anterior (contexto de conversación)
```

Ningún agente puede elevar una memoria a jerarquía superior sin pasar por el protocolo de autorización (§3).

### 1.2 Principio de soft-delete

**Nunca borrar directamente.** Toda eliminación sigue este flujo:

```
marcar como obsoleta → agregar reemplazo → registrar fecha + motivo → proponer al usuario → borrar solo con autorización explícita
```

---

## 2. Arquitectura de componentes

```
toolMemoMati/
├── PLAN.md                          ← este archivo
├── README.md                        ← guía de uso (fase 2)
│
├── install/
│   ├── memory-framework-install.ps1 ← instalador principal (Windows)
│   ├── memory-framework-install.sh  ← instalador alternativo (bash/WSL)
│   └── check-mcps.ps1               ← verifica MCPs disponibles
│
├── templates/
│   ├── mcp.json.template            ← plantilla .mcp.json con los 3 MCPs
│   ├── CLAUDE.md.template           ← plantilla CLAUDE.md con protocolo de sesión
│   └── skills/
│       └── memory-bootstrap.md      ← skill de inicialización
│
├── memory-auditor/
│   ├── core/
│   │   └── audit-engine.md          ← spec del motor (agnóstico de IA)
│   ├── adapters/
│   │   ├── claude-code-agent.md     ← adapter Claude Code
│   │   ├── codex-agent.md           ← adapter GitHub Copilot / Codex
│   │   ├── cursor-agent.md          ← adapter Cursor
│   │   └── generic-agent.md         ← prompt genérico (cualquier IA)
│   └── scripts/
│       └── memory-audit.ps1         ← script standalone (no depende de IA)
│
├── schemas/
│   ├── business-rule.schema.json    ← formato canónico: regla de negocio
│   ├── technical-decision.schema.json
│   └── bugfix.schema.json
│
├── scripts/
│   ├── export-rules.ps1             ← exporta SQLite-RAG → .jsonl
│   └── validate-memories.ps1        ← valida formato de memorias existentes
│
└── docs/
    ├── authority-hierarchy.md       ← explicación detallada de jerarquía
    ├── authorization-protocol.md    ← niveles de riesgo y flujo de aprobación
    └── memory-map.md                ← qué va en cada sistema
```

---

## 3. Mapa de sistemas de memoria

### 3.1 Responsabilidad por sistema

| Sistema | MCP | Usa para | Almacena en |
|---------|-----|----------|-------------|
| **Serena** | `serena` MCP | Leer código, símbolos, referencias, editar código | `.serena/memories/` |
| **SQLite-RAG** | `sqlite-rag` MCP | Reglas de negocio, invariantes, facts verificables, decisiones estables | `memory/business-rules.sqlite` + export `.jsonl` |
| **Engram** | `engram` MCP | Historial, sesiones, decisiones evolutivas, bugs, contexto temporal | `memory/session-log/`, `memory/decisions/`, `memory/bugfixes/` |
| **CLAUDE.md / Auto-memory** | nativo Claude Code | Comandos principales, estructura, convenciones, reglas operativas | `CLAUDE.md`, `.claude/CLAUDE.md`, `~/.claude/CLAUDE.md` |

### 3.2 Árbol de decisión: ¿dónde guardo esto?

```
¿Es estructura del código o convención de edición?
  └─ SÍ → Serena memory

¿Es una regla de negocio o invariante del sistema?
  └─ SÍ → SQLite-RAG (confidence ≥ 0.8) + export JSONL
         → si también es crítica: CLAUDE.md

¿Es una decisión técnica con contexto temporal (por qué se tomó)?
  └─ SÍ → Engram (mem_save, type: decision)

¿Es un bug fix con root cause?
  └─ SÍ → Engram (mem_save, type: bugfix)

¿Es un resumen de sesión?
  └─ SÍ → Engram (mem_session_summary)

¿Es un comando o convención de desarrollo?
  └─ SÍ → Serena (suggested_commands memory) + CLAUDE.md
```

### 3.3 Estrategia de versionado Git

```
✅ Versionar (commit al repo del proyecto):
  - CLAUDE.md
  - .claude/CLAUDE.md
  - memory/**/*.md
  - memory/business-rules/*.jsonl (exports)
  - .serena/memories/*.md

❌ No versionar (ignorar en .gitignore):
  - *.sqlite (cambia con frecuencia, binario)
  - memory/cache/
  - embeddings pesados
  - .serena/index/ (índice interno de Serena)
```

---

## 4. Formatos canónicos

### 4.1 Regla de negocio

```yaml
# Archivo: memory/business-rules/RULE-{MODULO}-{NNN}.md
id: RULE-VENTAS-001
tipo: regla-negocio
modulo: ventas
titulo: Venta requiere caja abierta
descripcion: >
  No se puede crear una venta si no existe una caja abierta
  para el día en curso. El sistema debe verificar estado de caja
  antes de procesar cualquier transacción de venta.
impacto:
  - ventas.service.ts → createVenta()
  - caja.service.ts → getCajaAbierta()
confidence: 1.0
estado: vigente          # vigente | dudosa | obsoleta | reemplazada
reemplazada_por: null
fecha_creacion: 2026-05-06
fecha_actualizacion: 2026-05-06
motivo_cambio: null
autorizado_por: usuario
```

### 4.2 Decisión técnica

```yaml
# Archivo: memory/decisions/DEC-{AREA}-{NNN}.md
id: DEC-DB-001
tipo: decision-tecnica
area: database
titulo: Compactar migraciones en una migración inicial
decision: >
  Consolidar todas las migraciones anteriores en una única
  migración inicial durante fase de desarrollo.
motivo: Proyecto en desarrollo, BD reiniciable. Simplifica mantenimiento.
alternativas_descartadas:
  - Mantener historial completo: descartado por overhead en onboarding
impacto: database/migrations/
riesgo: medio
estado: vigente
fecha: 2026-05-06
autorizado_por: usuario
```

### 4.3 Bug fix

```yaml
# Archivo: memory/bugfixes/BUG-{MODULO}-{NNN}.md
id: BUG-AUTH-001
tipo: bugfix
modulo: auth
titulo: Perfil no cargaba tras login correcto
problema: Login exitoso pero estado de perfil quedaba vacío.
causa_raiz: Estado auth no actualizado después de signIn() — faltaba fetchProfile().
fix: >
  Agregar fetchProfile() + setUser() antes de navigate() en
  el handler de login. Ver useAuth.ts:handleLogin().
archivos:
  - frontend/src/modules/auth/hooks/useAuth.ts
estado: resuelto
fecha: 2026-05-06
```

---

## 5. Protocolo de autorización

### 5.1 Niveles de riesgo

| Nivel | Acción | Comportamiento de Claude |
|-------|--------|--------------------------|
| **Bajo** | Resumen de sesión, comando útil, bug menor | Guarda automáticamente |
| **Medio** | Decisión técnica, cambio de arquitectura, convención nueva | Muestra qué va a guardar → espera confirmación |
| **Alto** | Regla de negocio, regla contable/stock/caja, eliminar memoria, cambiar jerarquía de autoridad | **Siempre pide confirmación explícita** — describe impacto antes de actuar |

### 5.2 Flujo de confirmación (nivel medio/alto)

```
Claude detecta acción de riesgo medio/alto
  ↓
Genera propuesta:
  - Qué memoria se va a crear/modificar/eliminar
  - Por qué
  - Qué sistemas impacta
  - Nivel de riesgo
  ↓
Presenta al usuario con opciones:
  [A] Aprobar  [R] Rechazar  [M] Modificar antes de guardar
  ↓
Solo ejecuta si el usuario responde A o M-confirmado
```

### 5.3 Memoria del protocolo en CLAUDE.md (snippet a inyectar)

```markdown
## Protocolo de autorización de memorias

| Riesgo | Ejemplos | Acción requerida |
|--------|----------|-----------------|
| Bajo | resumen sesión, comando, bug menor | automático |
| Medio | decisión técnica, nueva convención | confirmar antes de guardar |
| Alto | regla de negocio, eliminar memoria | confirmar SIEMPRE — describir impacto |

Jerarquía de autoridad: código > tests > docs vigente > SQLite-RAG > Engram > chat.
```

---

## 6. Auditor de memorias — arquitectura script + adapters

> Decisión resuelta: DEC-003 + DEC-004. Ver DECISIONS.md para razonamiento completo.

### 6.1 Principio de diseño

El script `memory-audit.ps1` es la **fuente portable** — corre sin depender de ninguna IA.
Los adapters son capas delgadas que traducen su output en instrucciones para cada entorno.

```
memory-audit.ps1 (standalone)
  ↓ genera reporte
memory/audits/audit-YYYY-MM-DD.md
  ↓ adapter lee el reporte y lo convierte en instrucciones para la IA activa
adapters/{claude-code|codex|cursor|generic}-agent.md
```

### 6.2 Estructura

```
memory-auditor/
├── core/
│   └── audit-engine.md     ← spec de qué constituye una memoria obsoleta/dudosa.
│                              Editado a mano. Agnóstico de IA.
├── adapters/               ← GENERADOS por el script, no editar a mano
│   ├── claude-code-agent.md
│   ├── codex-agent.md
│   ├── cursor-agent.md
│   └── generic-agent.md    ← fallback: prompt autosuficiente para cualquier IA
└── scripts/
    └── memory-audit.ps1    ← implementación standalone
```

### 6.3 Flujo del script

```
1. Leer memory/business-rules/*.md, memory/decisions/*.md, memory/bugfixes/*.md
2. Para cada entrada:
   a. grep en el codebase para verificar referencias del símbolo/archivo citado
   b. clasificar: vigente | dudosa | obsoleta | reemplazada
   c. detectar contradicciones entre sistemas (misma regla, valores distintos)
3. Generar reporte: memory/audits/audit-YYYY-MM-DD.md
4. Detectar entorno:
   - Existe .claude/ → actualizar adapters/claude-code-agent.md
   - Existe .cursor/ → actualizar adapters/cursor-agent.md
   - Sin detección   → generar memory-auditor.prompt.md (prompt genérico)
5. NO ejecutar cambios — solo reportar y esperar que la IA actúe con autorización del usuario
```

### 6.4 Detección de entorno (lógica del script)

```powershell
function Get-DetectedEnvironment {
    if (Test-Path ".claude") { return "claude-code" }
    if (Test-Path ".cursor")  { return "cursor" }
    if (Test-Path ".codex")   { return "codex" }
    return "generic"
}
```

### 6.5 Formato del reporte generado

```markdown
# Memory Audit Report — 2026-05-06

## Resumen
- Total memorias analizadas: 47
- Vigentes: 38
- Dudosas: 6
- Obsoletas: 3
- Contradicciones detectadas: 2

## Obsoletas (propuesta de eliminación — requiere autorización ALTA)
### RULE-VENTAS-003
- Motivo: checkStock() eliminada en commit a3050ca
- Evidencia: grep en codebase — 0 referencias
- Propuesta: marcar como obsoleta → eliminar con autorización

## Contradicciones (propuesta de unificación — requiere autorización MEDIA)
### Engram vs SQLite-RAG: módulo caja
- Engram: "caja cierra automáticamente a las 23:59"
- SQLite-RAG: "caja debe cerrarse manualmente"
- Código actual: no hay cierre automático → SQLite-RAG gana por jerarquía
- Propuesta: actualizar Engram, marcar entrada vieja como reemplazada
```

### 6.6 Triggers

| Trigger | Cuándo | Cómo |
|---------|--------|------|
| Manual | Cuando el usuario lo pide | `/memory-audit` o `.\memory-audit.ps1` |
| Por sesiones | Cada 10 sesiones completadas | Contador en `memory/.audit-counter` (no versionar) |
| Pre-PR | Antes de merge grande | Hook `pre-push` o paso en CI |

El contador se incrementa en cada `mem_session_summary`. Al llegar a 10 se resetea y dispara la auditoría.

---

## 7. Script de instalación — Especificación

### 7.1 Archivo: `install/memory-framework-install.ps1`

```powershell
# Parámetros
param(
    [Parameter(Mandatory=$true)]
    [string]$ProjectPath,          # ruta del proyecto destino

    [string]$ProjectName = "",     # nombre del proyecto (auto-detectado si no se da)

    [switch]$SkipMcpCheck,         # omitir verificación de MCPs
    [switch]$DryRun                # mostrar qué haría sin ejecutar
)

# Pasos:
# 1. Verificar que $ProjectPath existe
# 2. Auto-detectar $ProjectName desde package.json o carpeta
# 3. check-mcps.ps1 — verificar Serena, SQLite-RAG, Engram disponibles en PATH/config
# 4. Generar .mcp.json desde templates/mcp.json.template
#    → SQLite-RAG debe configurarse con --db-path apuntando a memory/business-rules.sqlite
# 5. Crear .claude/ si no existe
# 6. Generar .claude/skills/memory-bootstrap.md desde templates/skills/
# 7. CLAUDE.md — regla DEC-002 (NUNCA sobreescribir):
#    a. Si NO existe: crear desde templates/CLAUDE.md.template
#    b. Si existe Y NO contiene <!-- MEMORY-FRAMEWORK:START -->:
#       → Append al final del archivo con la sección marcada
#    c. Si existe Y YA contiene <!-- MEMORY-FRAMEWORK:START -->:
#       → Reemplazar SOLO el bloque entre marcadores
#       → Informar: "Sección actualizada (resto del archivo sin cambios)"
#    Los marcadores garantizan que el instalador solo toca su propia sección.
# 8. Crear estructura memory/ en el proyecto destino:
#    → memory/business-rules/   (RULE-*.md + rules.export.jsonl)
#    → memory/decisions/        (DEC-*.md)
#    → memory/bugfixes/         (BUG-*.md)
#    → memory/session-log/      (resúmenes Engram)
#    → memory/audits/           (reportes del auditor)
#    → memory/.audit-counter    (contador de sesiones, no versionar)
#    → NO crear memory/business-rules.sqlite (lo crea SQLite-RAG MCP al primera escritura)
# 9. Agregar entradas a .gitignore del proyecto destino (si existe):
#    → memory/business-rules.sqlite
#    → memory/.audit-counter
#    → memory/cache/
# 10. Mostrar resumen de lo instalado + próximos pasos
```

### 7.2 Archivo: `install/check-mcps.ps1`

```powershell
# Verifica disponibilidad de los 3 MCPs
# Para cada MCP: intenta leer su configuración o hacer una llamada de test
# Retorna tabla: MCP | Estado | Versión | Acción requerida
# Falla con código de salida != 0 si algún MCP crítico no está disponible
```

### 7.3 Estructura generada en el proyecto destino

```
{proyecto}/
├── .mcp.json                          ← 3 MCPs configurados
│                                        SQLite-RAG apunta a memory/business-rules.sqlite
├── .gitignore                         ← entradas agregadas (no sobreescrito):
│                                        memory/business-rules.sqlite
│                                        memory/.audit-counter
├── CLAUDE.md                          ← sección inyectada entre marcadores:
│                                        <!-- MEMORY-FRAMEWORK:START -->
│                                        <!-- MEMORY-FRAMEWORK:END -->
├── .claude/
│   └── skills/
│       └── memory-bootstrap.md        ← skill /memory-bootstrap
└── memory/
    ├── business-rules/
    │   ├── RULE-*.md                  ← reglas de negocio (formato DEC-001)
    │   └── rules.export.jsonl         ← export versionable de SQLite-RAG
    ├── business-rules.sqlite          ← BD SQLite (NO versionar — binario)
    ├── decisions/                     ← DEC-*.md
    ├── bugfixes/                      ← BUG-*.md
    ├── session-log/
    │   └── YYYY-MM/                   ← agrupado por mes
    ├── audits/                        ← reportes memory-audit-YYYY-MM-DD.md
    └── .audit-counter                 ← contador sesiones (NO versionar)
```

---

## 8. Skill de bootstrap — Especificación

### Archivo: `templates/skills/memory-bootstrap.md`

Cuando se invoca `/memory-bootstrap` en un proyecto nuevo, el skill:

```
1. Verifica que los 3 MCPs están activos
2. Activa Serena + corre onboarding (si no fue hecho)
3. Lee CLAUDE.md del proyecto para extraer stack, módulos, comandos
4. Popula Serena memories: project_overview, suggested_commands,
   code_style_conventions, task_completion_checklist, architecture/modules
5. Crea entradas iniciales en SQLite-RAG con los hechos arquitecturales base
6. Crea primera entrada en Engram: mem_save tipo "project-init"
7. Genera memory/business-rules/ vacío con README explicando el formato
8. Informa al usuario: "Framework de memoria inicializado — próximos pasos: [lista]"
```

---

## 9. Exportación y mantenimiento

### 9.1 Export SQLite-RAG → JSONL

```powershell
# scripts/export-rules.ps1
# Lee todas las entradas de SQLite-RAG con scope "project"
# Exporta a memory/business-rules/rules.export.jsonl
# Formato: una regla por línea (JSONL)
# Ejecutar: antes de cada commit grande / al final de sprint
```

### 9.2 Rotación de session-log

```
memory/session-log/
  YYYY-MM/              ← agrupar por mes
    YYYY-MM-DD-HH-MM.md
```

Archivar sesiones de más de 90 días en `memory/archive/`.

---

## 10. Plan de implementación por fases

### Fase 1 — Fundamentos (prioridad alta)
- [ ] `install/check-mcps.ps1`
- [ ] `templates/mcp.json.template`
- [ ] `templates/CLAUDE.md.template` (sección protocolo de memorias)
- [ ] `install/memory-framework-install.ps1` (versión mínima: pasos 1-6)
- [ ] `schemas/business-rule.schema.json`
- [ ] `schemas/technical-decision.schema.json`
- [ ] `schemas/bugfix.schema.json`

### Fase 2 — Bootstrap y skill
- [ ] `templates/skills/memory-bootstrap.md`
- [ ] `agents/memory-auditor-agent.md` (definición)
- [ ] `scripts/export-rules.ps1`
- [ ] `README.md` (guía de uso)

### Fase 3 — Auditoría y mantenimiento
- [ ] Implementar lógica completa del `memory-auditor-agent`
- [ ] `scripts/validate-memories.ps1`
- [ ] Integrar auditoría automática post-sesión (hook en Claude Code settings)
- [ ] `docs/` completa

### Fase 4 — Hardening
- [ ] Tests del script de instalación (casos edge: proyecto con .mcp.json existente, sin CLAUDE.md, etc.)
- [ ] Soporte para `.sh` (bash/WSL)
- [ ] Documentación de upgrade (cuando sale nueva versión del framework)

---

## 11. Dependencias externas

| Dependencia | Rol | Instalación |
|-------------|-----|-------------|
| Serena MCP | Code intelligence + memorias estructurales | `pip install serena` (o según docs) |
| SQLite-RAG MCP | Reglas de negocio verificables | Configurar en `.mcp.json` |
| Engram MCP | Historial y decisiones cross-sesión | Configurar en `.mcp.json` |
| Claude Code CLI | Runtime | `npm install -g @anthropic-ai/claude-code` |
| PowerShell 5.1+ | Instalador (Windows) | Preinstalado en Windows 10/11 |

---

## 12. Decisiones de diseño

> Todas resueltas. Ver **DECISIONS.md** para razonamiento completo, opciones evaluadas y consecuencias de implementación.

| ID | Decisión | Resuelta |
|----|----------|----------|
| DEC-001 | Scope SQLite-RAG | ✅ Por proyecto — `memory/business-rules.sqlite` + export `.jsonl` |
| DEC-002 | Manejo de CLAUDE.md | ✅ Inyección marcada — nunca sobreescribir, solo bloque entre `<!-- MEMORY-FRAMEWORK:START/END -->` |
| DEC-003 | Arquitectura del auditor | ✅ Script standalone `memory-audit.ps1` + adapters generados por entorno detectado |
| DEC-004 | Frecuencia del auditor | ✅ Manual (`/memory-audit`) + cada 10 sesiones (contador) + pre-PR (hook) |
