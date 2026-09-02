---
status: accepted
date: 2026-06-13
decision-makers: ["agent"]
consulted: []
informed: []
register:
  spec: 1
  slug: a27-track-g-runtime-shadow-mode-the-composition-the-freshnes
  surfaces:
    - "packages/**"
  obsoletes: []
  updates: []
  obsoleted-by: null
  updated-by: []
  bead: null
  legacy-id: "A27"
---
## A27 (2026-06-13) — Track G runtime + shadow mode: the composition, the freshness overlay, the structural shadow boundary, and the recovery-actuation gap

**Decision:** Track G (built, `lib/src/runtime/`, +~36 offline + 3 lifecycle integration tests; one critical composition bug found by adversarial verify and fixed — below) is the reconciler runtime that runs the convergence machine. Shapes: **(1)** event ingestion → **per-bead serialized** processing via `PerBeadQueue` (invariant 7: same-bead events in arrival order, different beads concurrent, a slow gate on A never blocks B); `GraphEventAdapter` maps `BeadClosed`-on-active-wisp → `wispClosed`. **(2)** the reduce→gate→actuate cycle runs the A22 phase split (a fresh `EvaluateGateAction` → `GateEvaluator` (Track D) → re-enter `gateEvaluated` → actuate phase 2) and honors the A19 drain carrier. **(3) Write-through freshness overlay (A17):** each actuation's metadata writes (transition commits **plus** the `persistGateOutcome` replay markers and the iteration self-heal) are layered over the projected `Convergence` on every subsequent reduce, and a key is dropped only when a freshly-observed snapshot *agrees* (`reconcileWithSnapshot`; a cleared `''` agrees with empty/absent) — this is the first line of defense against the duplicate-pour race, the actuator's live probe (A26) the second. **(4)** Operator/trigger events on the **writing** path come from the runtime's own `submit()` command surface, **not** re-detected from our own metadata writes (no self-trigger loop); the heuristic `observedGcCommand` signatures are **shadow-only** diagnostics. **(5)** The **ownership partition gates the whole cycle** (checked at the top of `_runCycle`, before any gate subprocess or pour — defense-in-depth, re-checked in `_actuate`): a non-owned loop's events are reduced for diagnostics but never gate-run or actuated. **(6)** Periodic full reconcile: a startup pass + a single-flight low-frequency `Timer.periodic` backstop (default 30s ≈ gc patrol interval; `reconcile.go` has no time logic so cadence is free), with each replay plan **re-reduced inside the per-bead queue over the overlay** (not a stale snapshot-time plan). **(7) Shadow mode is *structurally* read-only:** `ShadowRuntime`'s constructor takes only a `ConvergenceSource` (reads) + adapter + an `onDivergence` callback — there is **no parameter** through which an `Actuator`/`BdCliService` could be passed; it holds only the pure reducer + recovery pass and returns would-be effects as data. (Verified by a paranoid adversarial lens across both rounds: no reachable write.) `ActuationResult.pourFailed` was added (additive) to thread `speculativePourErr` across the phase-split boundary.
**The bug (found + fixed):** `_executeReduceResult` checked `evaluateGate` before `requeue`; an operator-stop draining a wisp behind a *fresh* condition/hybrid gate returns `[pourSpeculative, evaluateGate, requeue(postDrain)]`, so the gate path ran but **dropped the requeue — the loop would never stop**. Fixed by routing on `requeue` first (`_runDrain` resolves the inner gate *and* re-enters the postDrain stop); regression-tested (`drain_and_recovery_test.dart`, the condition-gate variant the prior test omitted by using `gate_mode: manual`).
**KNOWN GAP (carried to M3 / Track-I follow-up):** the runtime bd-actuates only the **reducer-shaped replay** plans (`RecoveryOutcome.replayActions`, A22 reuse). The recovery-*specific* effects (`RecoveryAction`: adopt/pour-wisp-1, partial-creation terminate, terminated-but-open close, marker repair) carry their own ordered writes but are currently **surfaced as data, not bd-actuated** — a deliberate boundary (avoids inventing a second writer surface). Harmless for M2 (shadow is read-only; the recovery *pass* is conformance-tested in Track C; offline lifecycle is covered), but a **recovery actuator** that walks `RecoveryAction.*Writes` is required before the_grid drives a live owned rig (M3).
**Why:** ADR-0003 D2/D6 specify event-driven processing with the invariants + read-only shadow, but leave the freshness mechanism, the command-source split, where ownership is enforced, and recovery cadence to implementation. Three adversarial lenses ran (composition / shadow-safety / e2e); shadow-safety passed both rounds, composition surfaced the drain-ordering critical (fixed).
**Affects (if promoted):** ADR-0003 D2/D6 (the runtime composition + the shadow boundary + the recovery-actuation gap). `docs/M2-BUILD-ORDER.md` Track G + a new follow-up (recovery actuator, M3). Code: `packages/grid_reconciler/lib/src/runtime/`.
**Status:** **promoted → ADR-0003 Decision 8 + D6 (Nico, 2026-06-14)** — recovery-actuator gap carried to M3.

