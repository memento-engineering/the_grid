---
status: accepted
date: 2026-07-21
decision-makers: ["agent"]
consulted: []
informed: []
register:
  spec: 1
  slug: a54-the-version-pin-becomes-a-shape-probe-how-support-bd-1-0
  surfaces:
    - "packages/**"
  obsoletes: []
  updates: []
  obsoleted-by: null
  updated-by: []
  bead: null
  legacy-id: "A54"
---
## A54 (2026-07-21) — the version pin becomes a SHAPE probe: how "support bd 1.0+" was implemented, and why `depends_on_external` is required (tg-sb9)

**Context.** Nico's directive (live session, 2026-07-21, ratified): "having to pin beads_dart against a particular version isn't ideal, we should support 1.0+ period." The directive itself is human-ratified and is not what this entry registers. What it registers is the MECHANISM, which the directive leaves to the implementer, and which touches a ratified clause.

**The ratified clause it refines.** ADR-0001 Decision 4: "**Schema-drift guard:** on connect, read the migrations version; unknown/newer ⇒ disable SQL reads, fall back to `BdCliService` reads, log loudly." Read literally, that clause is what broke: every org store moved to schema v53 under bd 1.1.0, `kTargetSchemaVersion = 50` rejected all of them, and the pooled SQL read path silently degraded to the CLI everywhere (5 hermetic differential tests failed with `schema_version 53 != expected 50`). The clause's INTENT — never read a store whose shape you cannot serve; fall back loudly — is preserved exactly; its MECHANISM is replaced.

**Decision (AI; `beads_dart` only).**
- The connect-time guard is now a SHAPE probe: one `information_schema.columns` SELECT (`DoltSchemaShape.probeSql`) over the six tables the read path touches, checked against a declared required table/column set. Missing anything ⇒ `BdSchemaDriftException.sqlShape` naming each gap ⇒ the existing CLI fallback. The migration version is still read (D4's "read the migrations version" survives) but is recorded for diagnostics only and never compared.
- The dependency-target expression is BUILT from the probed columns rather than hard-coded, per dependency table, in beads' own `DepTargetExpr` order. The same probed shape now also decides whether the wisp-family legs (`wisps`/`wisp_labels`/`wisp_dependencies`) appear in the snapshot, dependency, label and idempotency-probe statements at all, so a pre-0020 store reads correctly instead of hard-erroring on a missing table.
- **`depends_on_external` is a REQUIRED column, not an optional one.** A44's cross-store edges live there — a raw foreign bead id that the origin store's own `is_blocked` recompute never reads. A store without it cannot express a cross-store dependency, so the SQL path stands down to the CLI rather than reading a graph with those edges silently dropped — which is precisely the orphan interpretation bd 1.1's `bd doctor --fix` applies to raw cross-store bead-id deps. **Operator hazard, recorded here and in `packages/beads_dart/README.md`: never run `bd doctor --fix` on an org store without excluding cross-store edges.**
- The required BEAD column set deliberately excludes descriptive text columns (`title`, `description`, `notes`, …): they arrive via `SELECT *` and `beadFromRow` already collapses an absent one to `''`, so requiring them would refuse a store the read path can serve correctly. Only correctness-bearing columns are required.
- The wisp family stays OPTIONAL (absent before migrations 0020/0021/0035) but must be WHOLE when present, since the reads UNION it in.

**Why not a `bd version` probe.** The directive names either. A `bd --version` probe would tie the SQL path's safety to a CLI spawn and to bd's version→schema mapping staying monotone; the `information_schema` probe asks the store the only question that actually matters — "do you have the columns I am about to read?" — and is one SELECT on a connection already open.

**Verified, not assumed.** The v53 column set was probed read-only from the live `tg` store on 2026-07-21 (`issues`/`wisps` 54 columns each, `labels`/`wisp_labels` 2, `dependencies`/`wisp_dependencies` 10; `schema_migrations` MAX(version) = 53) and carries every column `dolt_row_mapper` and `ready_work_query` read — including all three split dependency-target columns, so the `COALESCE` expression is unchanged at v53. That capture is checked in as `test/support/schema_probe_rows.dart` and is what every fake connection answers the probe with. The ready-work predicate itself needed no change.

**Not this:** no fixture re-capture (`fixtures/upstream/2026-07-10-bd-1.0.5/` is a dated capture of real upstream bytes, i.e. provenance, and stays); no change to the repo-root `CLAUDE.md` upstream-source pin; no change to the bd CLI path, the envelope `schema_version == 1` assertion, or the ready-work predicate's clauses.

**Affects (if promoted):** ADR-0001 Decision 4's schema-drift-guard bullet (the "read the migrations version; unknown/newer ⇒ disable" mechanism becomes "probe the shape; missing required columns ⇒ disable"); ADR-0002's `beads_dart` row ("pinned against bd 1.0.5" ⇒ "supports bd >= 1.0.5"); `.claude/skills/grid-porting/SKILL.md`'s pinned-upstream table (beads-schema row, updated here). Code: `beads_dart` `lib/src/services/dolt_schema_shape.dart` (new), `lib/src/services/dolt_query_service.dart`, `lib/src/ready/ready_work_query.dart`, `lib/src/errors/bd_exception.dart`.

**Status:** Pending — Nico promotes or rejects.

