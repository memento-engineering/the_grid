# the_grid

A Dart-native reactive orchestrator that will replace Gas City (`gc`). The long bet:
**apps are built in Flutter, Lenny debugs apps, Lenny files bugs into the grid — the grid
builds everything.**

## Read first, in order

1. `docs/PDR.md` — vision, goals, milestones, acceptance criteria, constraints, **the gate (§9)**
2. `docs/adr/ADR-0000-ai-decision-register.md` — **process-critical, see below**
3. `docs/adr/ADR-0001…0004` — ratified technical decisions (foundations, packages/projections, reconciler, runtime/tmux)
4. `docs/M1-BUILD-ORDER.md` — dependency-ordered work breakdown
5. `docs/M4-SCOPING.md` — usage-driven M4 decomposition + fs adoption ladder (proposal, ADR-0000 A6)
6. The `predictable-flutter` skill (installed at `.claude/skills/predictable-flutter/`) — the architecture all code follows

## Process rules (non-negotiable)

- **The gate: OPEN as of 2026-06-11** (ADR-0001–0004 Accepted, ADR-0000 A1–A7 promoted, PDR §9 empty). The rule persists for new scope: doc before code; Nico ratifies explicitly.
- **ADR-0000 rule:** any decision made by AI goes into ADR-0000 as an amendment and stays there until Nico promotes it or shoots it down. Never write AI decisions directly into ADR-0001+ or silently change ratified docs to match your conclusions.
- Brainstorm → PDR → ADR → zero open questions → code. New scope gets a doc before it gets code.
- Fixtures are version-pinned (`fixtures/upstream/<date>-bd-<version>/`); re-capture via the porting skill's procedure, never edit by hand.

## Conventions

- Dart `^3.11.0`, pub workspace + melos (scripts: `bootstrap`, `test`, `analyze`, `format`), lints cloned from lenny (strict-casts/inference/raw-types, `prefer_single_quotes`, `unawaited_futures`, …).
- **freezed** sealed unions + `json_serializable` codecs; consume with exhaustive `switch` expressions. `build_runner` via melos.
- **Riverpod 3** `Notifier`/`AsyncNotifier` (never `StateNotifier`); streams via `StreamProvider`; derived state via `select`.
- predictable-flutter layering: Services (stateless I/O) → Repositories (own one source, emit state) → Interactors/Selectors/Transformers → View. Reference types carry classifiers (`BdCliService`); value types are plain (`Bead`).
- Tests use **Fakes, not mocks**; pure logic (diff, projections, transitions) is tested before any IO is wired.
- APIs: **Futures for acts, Streams for observations.**

## bd / beads rules

- Always `BD_JSON_ENVELOPE=1`; assert `schema_version == 1`. Errors arrive **enveloped on stdout** with exit ≠ 0 (ADR-0001 Decision 4).
- Mutations: bd CLI only, `--actor grid-controller`. **Never SQL writes. Never touch `.beads/hooks/` (gc owns them).**
- Grouped mutations: `bd batch` (one transaction, one DOLT_COMMIT). Bulk reads: `bd export --include-infra` / `bd query` / multi-id `bd show`. **Never spawn bd per issue in a loop.**
- **Never call `bd show` from a re-query/controller path** — it writes `.beads/last-touched` and self-triggers the watcher.
- `bd list` does not surface infra-typed beads (agent/rig/role) — use export for those (ADR-0001 Decision 4).
- **Coexistence safety (ADR-0003 Decision 6):** gc's convergence handler assumes a single writer per bead. Never reconcile or mutate beads gc's reconciler owns; any shadow/conformance experiment against live convergence traffic is strictly read-only.

## Environment facts

- Dolt **server mode**: db `tg` at `127.0.0.1:34947`; local `.beads/dolt/` is empty. Creds `GC_DOLT_USER`/`GC_DOLT_PASSWORD`; `GT_ROOT=/Users/nico/gascity` (from `.beads/.env`). Server reaps idle connections at **30s** — pools must reconnect; keep ≤2 pooled connections.
- Cross-workspace writes into `tg` are routine (`.beads/routes.jsonl`) — `SELECT @@tg_working` (~1ms) is the authoritative change probe.
- gc keeps running during M1–M3; the_grid coexists (reads + bd-mediated writes only).
- Pinned upstream: **bd 1.0.5 (f9fe4ef2a)**. Sources on disk: gascity `~/development/com.gastownhall/gascity`, beads `~/development/com.gastownhall/beads`, lenny `~/development/com.nicospencer/lenny`, predictable-flutter `~/development/com.nicospencer/predictable-flutter`.
- Lenny M0 prerequisite (`ext.exploration.*` rename → `exploration_contract` extraction) is tracked as lenny beads `lenny-wisp-41rdl` → `lenny-wisp-9h557`; the_grid consumes `exploration_contract` as a **path dependency** during development. Only `grid_exploration` is blocked on it.

## Packages (ADR-0002)

`grid_controller` (sdk) · `grid_cli` (mgmt) · `grid_exploration` (lenny plugin) · `grid_devtools` (DevTools, only Flutter pkg, exploration-protocol-only) · `grid_reconciler` (M2) · `grid_runtime` (M3) · `tmux` (standalone general-purpose client, zero grid deps).
