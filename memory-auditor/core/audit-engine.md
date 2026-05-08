# Memory Audit Engine — Spec

> This file defines what constitutes an obsolete, stale, or contradicted memory.
> Edit this file manually to tune audit sensitivity.
> The script `memory-audit.ps1` reads this spec and applies the rules.

---

## 1. Classification rules

Each memory file is classified into one of four states:

| State | Meaning |
|-------|---------|
| `vigente` | Active and verified — code references exist |
| `dudosa` | Questionable — code references partially missing or file is old |
| `obsoleta` | Dead — no code references found anywhere in the repo |
| `reemplazada` | Superseded — another entry explicitly replaces this one |

---

## 2. Obsolescence criteria

A memory entry is classified as **obsoleta** when ALL of the following are true:

- `estado` is currently `vigente` or `dudosa`
- The `impacto` list is non-empty
- **Zero** code references found via grep for ALL symbols/paths in `impacto`
- The entry is older than **30 days** (based on `fecha_actualizacion`)

A memory entry is classified as **dudosa** when:

- `estado` is `vigente`
- The `impacto` list is non-empty
- **Some but not all** symbols in `impacto` return grep hits
- OR the entry is older than **90 days** with no update

A memory entry is classified as **reemplazada** when:

- Another entry has the same `modulo` and `titulo` (normalized) with a later `fecha_actualizacion`
- OR the `reemplazada_por` field is non-null

---

## 3. Contradiction detection

A contradiction is flagged when two entries in the same module describe the same concept with conflicting facts.

Detection heuristic:
1. Group entries by `modulo`
2. Within each module, compare `titulo` fields (normalized: lowercase, no punctuation)
3. If two entries have similarity score > 0.8 (word overlap) AND different `estado` or conflicting `descripcion` keywords → flag as contradiction
4. Apply authority hierarchy to propose resolution:
   - Current code wins over all memory
   - SQLite-RAG (confidence ≥ 0.8) wins over Engram entries
   - More recent `fecha_actualizacion` wins over older

---

## 4. Thresholds (configurable)

| Parameter | Default | Description |
|-----------|---------|-------------|
| `obsoleta_days` | 30 | Days since last update before `vigente` → `obsoleta` |
| `dudosa_days` | 90 | Days since last update before `vigente` → `dudosa` |
| `min_confidence` | 0.8 | SQLite-RAG entries below this are treated as unverified |
| `similarity_threshold` | 0.8 | Word overlap ratio to flag title contradictions |

---

## 5. Audit report sections

The report `memory/audits/audit-YYYY-MM-DD.md` must include:

1. **Summary table** — total analyzed, counts per state
2. **Obsoletas** — list with: entry ID, reason, evidence (grep count), proposed action
3. **Dudosas** — list with: entry ID, reason, which symbols are missing
4. **Contradicciones** — list with: pair of entries, conflict description, resolution proposal
5. **Vigentes** — count only (no detail needed)

---

## 6. Authorization levels for proposed actions

| Action | Risk level | Required |
|--------|-----------|----------|
| Mark as `dudosa` | Low | Automatic (no user approval needed) |
| Mark as `obsoleta` | Medium | Show proposal → wait for confirmation |
| Delete entry | High | Always confirm — describe full impact |
| Resolve contradiction | Medium | Show resolution → wait for confirmation |
| Change `reemplazada_por` | Medium | Show proposal → wait for confirmation |
