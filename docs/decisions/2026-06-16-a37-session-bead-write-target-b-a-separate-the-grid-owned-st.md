---
status: accepted
date: 2026-06-16
decision-makers: ["agent"]
consulted: []
informed: []
register:
  spec: 1
  slug: a37-session-bead-write-target-b-a-separate-the-grid-owned-st
  surfaces:
    - "packages/**"
  obsoletes: []
  updates: []
  obsoleted-by: null
  updated-by: []
  bead: null
  legacy-id: "A37"
---
## A37 (2026-06-16) — session-bead write-target = **B** (a separate the_grid-owned state DB); genesis stays a pristine work source

**Decision (Nico, 2026-06-16):** the A36 open sub-decision is resolved to **option B** — the_grid's own `type=session` lifecycle beads are written to a **separate the_grid-owned beads store**, NOT into genesis. This was forced concrete by the first live arm: genesis validates issue types and **rejected `type=session`** (`invalid issue type: session`) — `session` is gc's runtime-lifecycle vocabulary the_grid deliberately adopted (ADR-0006 D1, "gc's session-bead analog"), and a distinct infra type matters so the_grid's own bookkeeping stays **out of its ready-work read path** (`bd ready`/`bd list` exclude session/agent/rig/role). Imposing that type on genesis (option A) would leak the_grid's control-plane schema into a consumer's backlog; **B keeps the type — and the session beads — in the_grid's own store** (the A21 "grid-private state stays separate" principle), reused by arm #2 (lenny) and every future rig.
**What was built (offline-green; `grid_cli`+`grid_runtime`, 143 tests, analyze clean):**
- A the_grid-owned state DB at **`engineering.memento/tgdog`** (embedded dolt `tgdog`, issue-prefix `tgdog`, `session` registered via `bd config set types.custom`).
- **`grid run --state-workspace <path>` + `--state-rig <rig>`** (default `tgdog`): session/lifecycle writes target the state store's `BdCliService`; the controller still **reads** ready work from `--workspace` (genesis). `composeRun` **unions** `stateRig` into the single shared allow-set (A32 invariant preserved — `{genesis, tgdog}` feeds both gates; no genesis/convergence bead carries the `tgdog` prefix, so the union never broadens dispatch/actuation).
- **Session-rig decoupling** in `DispatchInteractor` (`sessionRig`): a `genesis` work bead mints its session into the `tgdog` partition (`metadata.rig=tgdog`, `work_bead=genesis-q8h`), owned by the chokepoint by prefix across its whole lifecycle.
- **Robustness fix (real bug the arm exposed):** a single failed `bd create` was propagating out of `start()` and **crashing the whole controller** (process exit 255). Now report-and-continue (`_reportError`, never rethrow) — one bead's failure is a logged skip.
- **Prompt enrichment:** the agent prompt was **title-only**; now carries the full bead (description/design/criteria/notes) + a **local-first** working agreement (commit on the throwaway branch, do NOT push, do NOT open a PR — `land()` is a deliberate human follow-up). Test-locked.
- A real **`genesis-grid`** clone (from the GitHub URL) registered as the Layer-1 root for per-bead worktrees.
**Affects:** **ADR-0006** Decision 1/3 + the ratified-inputs block (arm #1: read `genesis`, write sessions to the `tgdog` state store; root checkout `genesis-grid`; allow-set `{genesis, tgdog}`; local-first, no auto-PR). Supersedes A36's option-(a) lean. genesis footprint: **none** (pristine work source).
**Status:** **Nico's decision (B), 2026-06-16** — built + offline-green; the first live arm executed (see the live-run result once it lands). The `land()`/PR step stays a deliberate human follow-up.

