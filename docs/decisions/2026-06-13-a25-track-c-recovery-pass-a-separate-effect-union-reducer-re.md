---
status: accepted
date: 2026-06-13
decision-makers: ["agent"]
consulted: []
informed: []
register:
  spec: 1
  slug: a25-track-c-recovery-pass-a-separate-effect-union-reducer-re
  surfaces:
    - "packages/**"
  obsoletes: []
  updates: []
  obsoleted-by: null
  updated-by: []
  bead: null
  legacy-id: "A25"
---
## A25 (2026-06-13) — Track C recovery pass: a separate effect union, reducer reuse for replay, and "idempotent" = fixpoint-of-writes (not no-op)

**Decision:** Track C (built, `lib/src/recovery/`, 49 tests) is `ConvergenceRecovery.reconcile(GraphSnapshot) → RecoveryReport` — gc's `Reconciler` (reconcile.go) ported as a **pure** pass. Shapes: **(1)** recovery effects are a **separate** plain-value sealed union `RecoveryAction` (adopt-wisp-1 / pour-wisp-1 / partial-creation terminate / terminated-but-open close+re-emit / manual-hold re-emit + marker repair / recovered-active-pointer write), each with its ordered-write getters — **not** Track A's `ReconcilerAction`, which has no variant for these recovery-only effects. **(2)** The two replay paths — Path 1a closed-adopt (reconcile.go:159-168) and Path 4 closed-unprocessed (455-464), which gc handles by calling `HandleWispClosed` — **reuse `ConvergenceReducer`** (A22): the pass builds a synthetic `ReducerEvent.wispClosed`, reduces it over the snapshot, and carries the resulting transition plan on `RecoveryOutcome.replayActions`. No duplication of the 9-step. **(3)** `RecoveryOutcome.error` is reserved for the **snapshot-derivable** failure only — gc's `unknown convergence state` (reconcile.go:101-106). gc's other `ReconcileDetail.Error` cases are **live-store** failures (GetMetadata/GetBead/PourWisp, reconcile.go:65-68/402-408); a pure pass cannot raise those, so they are deferred to **Track G's actuation seam** (a real GetBead failure → `no_action` + error + no mutation is a Track-G contract, flagged for that brief). **(4)** The `unexpected-status` default branch (reconcile.go:466-470) **is** reachable and ported, *because* `BeadStatus` is an open extension-type ([[A9]]) — a wisp can carry a status outside {open, in_progress, closed}, unlike a sealed enum. **(5)** "Idempotent on re-run" means **fixpoint-of-writes** (no duplicate pour/close/repair), **not** strict single-pass no-op: the genuine `waiting_manual` hold **re-emits its hold event every pass by design** (lost-event recovery via a stable event id + downstream dedup, recovery.md §7.2). **(6)** `cumulativeDuration` uses raw `closedAt` (reconcile.go:674-676 requires *both* timestamps non-zero) — deliberately unlike the reducer's `effectiveClosedAt` fallback (trap 16).
**Why:** reconcile.go's recovery is gc's crash-safety backstop; the port spec leaves the effect-vs-reducer boundary, the error surface for a pure pass, and the precise idempotency semantics to implementation. Verified by a fidelity lens (re-derived all paths from the Go, constructed post-first-pass snapshots to confirm second-pass fixpoint) + a conformance-coverage lens against `conformance-reconcile-tests.md`.
**Affects (if promoted):** ADR-0003 D2 (recovery paths: the effect union, reducer reuse, the pure-vs-live error split). Code: `packages/grid_reconciler/lib/src/recovery/`.
**Status:** **promoted → ADR-0003 Decision 8 (Nico, 2026-06-14)**.

