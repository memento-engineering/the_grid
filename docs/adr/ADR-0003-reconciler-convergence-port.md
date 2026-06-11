# ADR-0003 — M2 reconciler: porting gc's convergence state machine

**Status:** Proposed
**Date:** 2026-06-11
**Deciders:** Nico Spencer
**Context:** M2 ports gc's work-convergence engine (`gascity/internal/convergence/`, ~11.5k LOC, of which ~3.8k is portable pure domain logic) into `grid_reconciler`, consuming `grid_controller`'s `GraphEvent` stream + `GraphSnapshot` and actuating through bd. Source spec assessed 2026-06-11 against gascity HEAD; key files: `handler.go` (9-step algorithm, lines 161–390), `reconcile.go` (recovery paths), `metadata.go` (schema), `gate.go`/`condition.go`/`hybrid.go` (gates), `manual.go`, `trigger.go`.

---

## Decision 1 — Scope: work convergence only; topology reconciliation is M3/M4

gc runs **two orthogonal reconcilers** each tick: session/topology reconciliation (desired agent/session counts from config — `cmd/gc/build_desired_state.go`) and work convergence (the per-bead iteration state machine). M2 ports **only convergence**. Topology reconciliation needs runtime providers to actuate and lands with M3/M4.

## Decision 2 — Event-driven, same invariants

gc detects wisp closure by polling each tick. `grid_reconciler` instead consumes `GraphEvent`s (`BeadClosed` on a convergence's active wisp, metadata changes for operator commands) — reactive, but the **transition semantics and crash-safety invariants are preserved verbatim**, because they are what make re-processing safe regardless of how closure is detected. A periodic full reconcile pass (startup + low-frequency backstop) replays gc's recovery paths over the snapshot.

### State machine (ported 1:1)

States (freezed enum): `creating`, `active`, `waitingManual`, `waitingTrigger`, `terminated`.

| From | Trigger | Condition | To | Action |
|---|---|---|---|---|
| active | wisp closed | gate=pass | terminated | `approved` |
| active | wisp closed | gate=fail ∧ iter<max | active | `iterate` (pour next) |
| active | wisp closed | timeout ∧ action=manual | waitingManual | `waitingManual` |
| active | wisp closed | timeout ∧ action=terminate | terminated | `noConvergence` |
| active | wisp closed | iter≥max ∧ gate≠pass | terminated | `noConvergence` |
| active | wisp closed | trigger enabled | waitingTrigger | `waitingTrigger` |
| active | wisp closed | gate_mode=manual | waitingManual | `waitingManual` |
| waitingManual | operator approve | — | terminated | `approved` |
| waitingManual | operator iterate | — | active | `iterate` |
| waitingTrigger | trigger condition passes | — | active | `iterate` |
| any | operator stop | — | terminated | `stopped` |
| creating | startup reconcile | — | terminated | partial-creation cleanup |

Action vocabulary (sealed): `iterate`, `approved`, `noConvergence`, `waitingManual`, `waitingTrigger`, `stopped`, `skipped`. Every action is data (freezed) executed by an actuator — the state machine itself is a pure function `(state, event, snapshot) → (state′, actions)`, switch-expression matched, exhaustiveness-checked.

### Invariants the port MUST preserve (gc's crash-safety contract)

1. **Monotonic dedup** — skip if wisp iteration ≤ `convergence.last_processed_wisp`'s iteration.
2. **Write ordering** — `last_processed_wisp` is written LAST in every transition (it IS the commit point); `gate_outcome_wisp` is written LAST in gate persistence (cached-outcome replay on crash).
3. **Idempotency keys** — wisps poured with `converge:{beadID}:iter:{N}`; re-pour returns the existing wisp.
4. **Iteration derivation** — iteration's source of truth is the count of closed child wisps, not the stored field (self-healing; repair on disagreement).
5. **Speculative pour before gate eval** — next wisp is poured at step 3b, before the gate runs; burned (subtree-deleted) if the outcome is terminal/manual; `pending_next_wisp` tracks it for recovery.
6. **Terminal irreversibility** — `terminated` + closed root is final; later events are `skipped`.
7. **Single writer per convergence bead** — serialized per-bead processing in the reconciler loop.

### Recovery paths (startup + backstop, from `reconcile.go`)

state `""` → adopt or pour wisp 1 · `creating` → terminate (partial creation) · `terminated`-but-open → close + re-emit · `waitingManual` → re-emit hold, repair markers · `waitingTrigger` → no-op unless terminal · `active` → recover active wisp / replay closed wisp / pour next.

## Decision 3 — Gates: same execution contract

Gate modes `manual` / `condition` / `hybrid` (hybrid = condition if present, else pass-to-manual). Conditions are **executable scripts** run via `Process` with gc's env contract preserved verbatim (`GC_BEAD_ID`, `GC_ITERATION`, `GC_WISP_ID`, `GC_AGENT_VERDICT`, `GC_ARTIFACT_DIR`, durations, paths…); outcome by exit code (0=pass, non-zero=fail, deadline=timeout, pre-exec=error); timeout actions `iterate`/`retry`(≤3)/`manual`/`terminate`; stdout/stderr captured and truncated into metadata. Path resolution keeps the traversal/symlink containment defenses. The agent-verdict channel (`convergence.agent_verdict` set by the injected `evaluate` step) is read, not reinterpreted.

## Decision 4 — Actuation through bd, batched

Reconciler actions execute via `grid_controller`'s mutation services. Multi-write transitions (metadata sets + close, burn + repoint) go through **`bd batch`** — one dolt transaction, one commit, atomic rollback, and exactly one dirty signal back into our own controller (no event storms from our own writes). Wisp pour uses bd's formula instantiation (`bd mol pour` / graph apply — exact verb pinned during M2 against the pinned bd version).

## Decision 5 — Ready-work SQL port, differential-tested

M2 ports `bd ready`'s predicate (`beads/internal/storage/issueops/ready_work.go`: status ∈ {open}, `is_blocked`=0 over {blocks, conditional-blocks, waits-for} edges with conditional-blocks' failure-keyword semantics, defer_until, ephemeral, sort policies) to run over the pooled Dolt connection — **gated by a differential test harness** that replays every integration scenario against both implementations and diffs results. `bd ready` remains the fallback and the oracle.

## Decision 6 — Conformance via gc's test suite

gc's convergence tests are the executable spec. M2's definition of done includes a conformance suite transliterated from: `handler_test.go` (9-step coverage), `reconcile_test.go` (recovery paths), `manual_test.go`, `trigger_test.go`, `gate_test.go`, `hybrid_test.go`.

---

## Alternatives considered

- **Redesign the state machine "properly reactive"** (drop speculative pour, markers) — rejected for M2: the invariants encode hard-won crash-safety; we change detection (events vs polling), not semantics. Semantic evolution goes through the upstream RFC doc (PDR deferred deliverable).
- **Gate conditions as Dart closures** — rejected: gates are user-authored scripts in packs; the subprocess contract is the compatibility surface.
- **Direct SQL writes for transition metadata** — rejected (ADR-0001 Decision 4): bypasses audit/hooks/commit semantics; `bd batch` gives us the atomicity we wanted from SQL anyway.
