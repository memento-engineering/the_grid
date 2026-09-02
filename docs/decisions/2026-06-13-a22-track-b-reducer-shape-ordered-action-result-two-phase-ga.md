---
status: accepted
date: 2026-06-13
decision-makers: ["agent"]
consulted: []
informed: []
register:
  spec: 1
  slug: a22-track-b-reducer-shape-ordered-action-result-two-phase-ga
  surfaces:
    - "packages/**"
  obsoletes: []
  updates: []
  obsoleted-by: null
  updated-by: []
  bead: null
  legacy-id: "A22"
---
## A22 (2026-06-13) — Track B reducer shape: ordered-action result, two-phase gate split, and what is *not* a reduce() transition

**Decision:** Track B (built, `lib/src/reducer/`, ~110 tests) is `ConvergenceReducer.reduce(Convergence, ReducerEvent, GraphSnapshot) → ReduceResult` — pure, total, exhaustive over `ReducerEvent` + `ConvergenceStateReading`, no I/O, no clock. Shapes: **(1)** `ReduceResult` is a plain immutable wrapper over an **ordered** `List<ReconcilerAction>` (order is the contract: `repairIteration` → `pourSpeculative` → (`evaluateGate` | `persistGateOutcome` + transition) → `requeue`) plus a `primary` getter (= `actions.last`, gc's `HandlerResult` analog); no new freezed/wire types. **(2) Gate evaluation is a two-reduce phase split:** a *fresh* condition/hybrid-with-condition gate returns phase 1 = `[pourSpeculative, evaluateGate]` with **no transition**; Track D runs the gate; the outcome re-enters as `ReducerEvent.gateEvaluated(GateResult, pouredSpeculativeWispId, pourFailed)` and phase 2 emits `persistGateOutcome` + the transition. The **replay** branch (a persisted `gate_outcome` already present) skips phase 1 entirely. **(3) Fresh-gate manual short-circuit:** `gate_mode=manual` (or hybrid-with-no-condition) transitions to `waiting_manual` in **one** reduce with no gate eval and no speculative pour (handler.go:301-316); replay never short-circuits. **(4) Out of reducer scope** (no `ReducerEvent`, they mint a new root): `RetryHandler` (retry.go R1-R9) and **trigger-gated CREATE** (create.go — A19 item (a)); both belong to the create/actuator surface. The reducer never *creates* a loop; only the trigger-gated wisp-close hold and `triggerPassed` advance are in it. **(5)** Stop recovery ports `recoverCurrentActiveWisp` (manual.go:447-518): a dangling `active_wisp` = metadata pointer non-empty AND the dangling-safe projection resolves it to null. **(6)** Stale-pending self-heal rides the transition action (`clearStalePending: true`) rather than a standalone write; `validPendingNextWisp` keys staleness on the projected wisp (missing / wrong-parent / wrong-key-but-ours / closed, handler.go:935-945).
**Why:** ADR-0003 D2 + the handler-9step port spec leave the result shape, the gate async-boundary, and the scope cut (what's a transition vs a creation) to implementation. The phase split is forced by Track D running gates as subprocesses (the reducer can't block). Verified by an adversarial fidelity lens + a conformance-coverage lens against the transliterated gc test inventories; the verifier's one critical (stop missing `recoverCurrentActiveWisp`; `_hasStalePending` missing the wrong-key case) was fixed.
**Affects (if promoted):** ADR-0003 D2 (the reduce contract + the create/retry scope cut). Code: `packages/grid_reconciler/lib/src/reducer/`.
**Status:** **promoted → ADR-0003 Decision 8 (Nico, 2026-06-14)**.

