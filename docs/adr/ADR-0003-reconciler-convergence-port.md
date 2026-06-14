# ADR-0003 — M2 reconciler: porting gc's convergence state machine

**Status:** Accepted 2026-06-11 (Nico)
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
| any (incl. `waitingTrigger`) | operator stop | — | terminated | `stopped` |
| creating | startup reconcile | — | terminated | partial-creation cleanup |
| creating | trigger-gated create | trigger set | waitingTrigger | entry hold — never enters `active` |
| active | wisp closed | pour/sling failure ∧ non-terminal | waitingManual | `waitingManual` (`waiting_reason=sling_failure`) |

**Corrections amended per ADR-0000 A19 (accepted 2026-06-14):** the table above is augmented from gc source — **Track B reduces from the Go (`handler.go`/`manual.go`/`trigger.go`/`create.go`), not from this table.** (a) A **trigger-gated create** goes straight to `waitingTrigger`, never through `active` (a create-path transition, not a `reduce()` one — `create.go`); like `RetryHandler`, **create/retry mint a new root and are outside the `reduce(state,event,snapshot)` scope** (they land with the M3 create surface). (b) A **pour/sling failure** on a non-terminal outcome transitions `active → waitingManual` with `waiting_reason=sling_failure`. (c) Operator **stop is valid from `waitingTrigger`**, and `StopHandler` first **drains** an already-closed-but-unprocessed active wisp through the full `HandleWispClosed` before deciding no-op vs force-close — modeled as `RequeueAction(OperatorStopEvent(postDrain: true))` re-entered behind the synthesized `wispClosed` pipeline. (d) gc **replays `gate_outcome` verbatim, unvalidated** (closed-at-write, open-at-replay) — the codec marks out-of-set outcomes malformed but keeps the raw string for byte-faithful event reconstruction.

Action vocabulary (sealed): `iterate`, `approved`, `noConvergence`, `waitingManual`, `waitingTrigger`, `stopped`, `skipped` (+ implementation carrier variants `pourSpeculative`/`persistGateOutcome`/`repairIteration`/`failed`/`requeue` that map wire→null — ADR-0000 A17/A22). Every action is data (freezed) executed by an actuator — the state machine itself is a pure function `(state, event, snapshot) → (state′, actions)`, switch-expression matched, exhaustiveness-checked.

### Invariants the port MUST preserve (gc's crash-safety contract)

1. **Monotonic dedup** — skip if wisp iteration ≤ `convergence.last_processed_wisp`'s iteration.
2. **Write ordering** — `last_processed_wisp` is written LAST in every transition (it IS the commit point); on **terminal** paths that means written **after `CloseBead`** (the close lands between the metadata writes and the final `last_processed_wisp` write — ADR-0000 A19); `gate_outcome_wisp` is written LAST in gate persistence (cached-outcome replay on crash). (Operator approve/stop skip the write when there is no prior wisp; operator iterate writes no dedup marker.)
3. **Idempotency keys** — wisps poured with `converge:{beadID}:iter:{N}`; re-pour returns the existing wisp.
4. **Iteration derivation** — iteration's source of truth is the count of closed child wisps, not the stored field (self-healing; repair on disagreement).
5. **Speculative pour before gate eval** — next wisp is poured at step 3b, before the gate runs; burned (subtree-deleted) if the outcome is terminal/manual; `pending_next_wisp` tracks it for recovery.
6. **Terminal irreversibility** — `terminated` + closed root is final; later events are `skipped`.
7. **Single writer per convergence bead** — serialized per-bead processing in the reconciler loop.

**Metadata schema (amended per ADR-0000 A18, accepted 2026-06-14):** the `convergence.*` namespace is **31 keys** (`metadata.go:12-44`), not the 16 an earlier draft listed — the omitted 15 include `pending_next_wisp` (invariant 5 above names it), the gate-replay companions (`gate_retry_count`/`gate_stdout`/`gate_stderr`/`gate_duration_ms`/`gate_truncated`), and the recovery-dispatch inputs (`terminal_reason`/`terminal_actor`/`waiting_reason`). All 31 are typed in Track A's codec; the `var.` prefix, `NormalizeVerdict`, and the eight `CloseReasons` are ported alongside.

### Recovery paths (startup + backstop, from `reconcile.go`)

state `""` → adopt or pour wisp 1 · `creating` → terminate (partial creation) · `terminated`-but-open → close + re-emit · `waitingManual` → re-emit hold, repair markers · `waitingTrigger` → no-op unless terminal · `active` → recover active wisp / replay closed wisp / pour next.

## Decision 3 — Gates: same execution contract

Gate modes `manual` / `condition` / `hybrid` (hybrid = condition if present, else pass-to-manual). Conditions are **executable scripts** run via `Process` with gc's env contract preserved verbatim (`GC_BEAD_ID`, `GC_ITERATION`, `GC_WISP_ID`, `GC_AGENT_VERDICT`, `GC_ARTIFACT_DIR`, durations, paths…); outcome by exit code (0=pass, non-zero=fail, deadline=timeout, pre-exec=error); timeout actions `iterate`/`retry`(≤3)/`manual`/`terminate`; stdout/stderr captured and truncated into metadata. Path resolution keeps the traversal/symlink containment defenses. The agent-verdict channel (`convergence.agent_verdict` set by the injected `evaluate` step) is read, not reinterpreted.

## Decision 4 — Actuation through bd, batched

Reconciler actions execute via `grid_controller`'s mutation services. **Amended per ADR-0000 A16 (accepted 2026-06-14):** `bd batch` (bd 1.0.5) carries **no `metadata`, no `delete`, no `mol`/`--graph`** — only `close`/`update <status|priority|title|assignee>`/`create`/`dep`. So convergence transitions are **per-bead sequenced calls** ordered by the write-ordering invariant (Decision 2 inv. 2): metadata via `bd update --metadata <json>` (merges; works on closed beads), burn via `bd delete` post-order subtree (never close — only speculative wisps), close via `bd close`. A transition is typically 2–4 spawns — **not** per-key (all keys changing on one bead go in one `--metadata` object). **Crash-safety rests on the write-ordering + idempotency invariants, not on batch atomicity** (exactly gc's machinery, which already assumes writes are not one atomic unit). Raw SQL writes stay excluded (ADR-0001 D4: bd writes carry validation/audit/**gc-hook**/commit semantics the coexisting gc reconciler depends on; gc itself writes convergence metadata through bd). `bd batch` is retained only for incidental `close`+`dep` groupings. Re-examine if a future bd adds a batch metadata verb — it would restore the single-dirty-signal property (a candidate upstream beads ask).

**Wisp pour amended per ADR-0000 A15 (accepted 2026-06-14):** a convergence wisp is poured **PERSISTENT** — `bd cook <formula> --mode=runtime` (resolve) then `bd create --graph <plan> --ephemeral`-OMITTED (one transaction; the plan's root carries `parent_id`→the convergence bead + `metadata.idempotency_key = converge:{beadID}:iter:{N}`). gc's convergence iterations are **not** ephemeral despite the name "wisp" — `molecule.Cook → store.Create` sets no Ephemeral flag, so they are committed `issues` beads (confirmed against a real captured subgraph, ADR-0000 A29). `bd mol wisp` is rejected (no parent/key/file surface). **Idempotency is the_grid's own responsibility**, not a bd primitive: a live `findWispByIdempotencyKey` SELECT (over the parent-child edge, `JSON_EXTRACT(metadata,'$.idempotency_key')`) immediately before the pour, backed by a snapshot-scan fast path.

## Decision 5 — Ready-work SQL port, differential-tested

M2 ports `bd ready`'s predicate (`beads/internal/storage/issueops/ready_work.go`: status ∈ {open}, `is_blocked`=0 over {blocks, conditional-blocks, waits-for} edges, defer_until, ephemeral, molecule-type exclusion, sort policies) to run over the pooled Dolt connection — **gated by a differential test harness** that replays every integration scenario against both implementations and diffs results. `bd ready` remains the fallback and the oracle.

**Amended per ADR-0000 A24 (accepted 2026-06-14):** `bd ready` applies **no conditional-blocks failure-keyword semantics** — `beads/internal/storage/issueops/blocked.go:29` treats `conditional-blocks` identically to `blocks`/`waits-for` (`type IN (…)`, no `close_reason` branch), and `IsFailureClose` has zero non-test call sites; the keyword logic is dormant in bd 1.0.5. The SQL port matches (the keyword set is carried as inert, documented data). Molecule-type beads are excluded (ADR-0000 A14). Re-examine if a future bd activates the keyword path. The differential harness is three-half (hermetic `bd init` oracle witnesses · hermetic `dolt sql-server` SQL-port vs `bd ready` · live read-only over `tg`, self-skipping without `GC_DOLT_PASSWORD`).

## Decision 6 — Operating mode: coexistence partition *(promoted from ADR-0000 A7, 2026-06-11)*

While gc and the_grid both run, the_grid owns a bead/rig set **disjoint** from gc's reconciler — partitioned by rig and/or an ownership marker — because gc's convergence handler assumes a single writer per bead (invariant 7); two reconcilers on one convergence bead corrupts state for both. M2 shadow mode (computing transitions against live traffic and diffing them against gc's) is strictly read-only. The fs adoption ladder (`docs/M4-SCOPING.md`) sequences write authority accordingly: observe (M1) → shadow (M2) → drive one owned rig (M3) → cutover per rig (M4f). *(Cross-reference: shadow's "fresh-read every cycle, no cached refs, a reject leaves state untouched" discipline independently mirrors genesis's `staleUnmounted`/A8 stance — confirming the shared canon; the mechanism stays grid-local. ADR-0000 A27/A30.)*

## Decision 7 — Conformance via gc's test suite

gc's convergence tests are the executable spec. M2's definition of done includes a conformance suite transliterated from: `handler_test.go` (9-step coverage), `reconcile_test.go` (recovery paths), `manual_test.go`, `trigger_test.go`, `gate_test.go`, `hybrid_test.go`. **(Met — ADR-0000 A28: all 21 gc `*_test.go` must-cases covered faithfully + an end-to-end runtime conformance layer; report `packages/grid_reconciler/doc/port/conformance-report.md`.)**

## Decision 8 — M2 implementation record *(promoted from ADR-0000 A22/A23/A25/A26/A27, 2026-06-14)*

The M2 build (branch `m2-reconciler`, ~590 offline + integration tests, conformance-green) refined Decisions 2–6 into these implemented shapes:

- **Reducer (A22 → D2):** `ConvergenceReducer.reduce(Convergence, ReducerEvent, GraphSnapshot) → ReduceResult` (ordered action list + `primary`). Gate evaluation is a **two-reduce phase split** (fresh: `[pourSpeculative, evaluateGate]` → Track D runs the gate → re-enter via `gateEvaluated` → `persistGateOutcome` + transition; replay skips phase 1; manual short-circuits in one reduce). `RetryHandler` + trigger-gated CREATE mint a new root and are **out of `reduce()` scope** (the create/actuator surface, M3).
- **Recovery (A25 → D2):** recovery effects are a separate `RecoveryAction` union; the two replay paths reuse the reducer; `RecoveryOutcome.error` is reserved for the snapshot-derivable unknown-state failure only (gc's live-store errors are the Track-G actuation seam's contract); "idempotent" = **fixpoint-of-writes** (the genuine manual hold re-emits every pass by design).
- **Gate runner (A23 → D3):** a `ProcessRunner` seam returning a closed `ProcessRunOutcome`; parent-cancel via `CancellationToken`; env-contract deltas (emits `GC_CITY_RUNTIME_DIR` default + `GC_CONTROL_DISPATCHER_TRACE_DEFAULT`; drops gc's `TrustedAmbientCityRuntimeDir` override); the symlink/traversal containment guard is ported + escape-tested, wired at the exec call site by Track E/G.
- **Actuator (A26 → D4):** the `Actuator` seam (the only writer) executes a `ReduceResult`'s ordered writes; bd surface = `update --metadata` / `applyGraph` (persistent) / `cook` / `delete`; the live idempotency probe is a `DoltQueryService` SELECT (`JSON_EXTRACT`), **not** `bd show`; **burn = `bd delete` natural post-order, only speculative wisps** — a stopped active wisp is *closed*, not burned.
- **Runtime + shadow (A27 → D2/D6):** per-bead **serialized** processing (inv. 7) → reduce → gate → actuate, with a **write-through overlay** (A17 freshness) and the operator-stop drain re-entered as `OperatorStopEvent(postDrain: true)`. **Shadow mode is structurally read-only** (the `ShadowRuntime` constructor takes no writer; D6). *Known gap (M3):* the runtime actuates only reducer-shaped replay plans; recovery-specific `RecoveryAction` effects are surfaced as data, awaiting a **recovery actuator**.

(Codec validated against real gc bytes — ADR-0000 A29; genesis is silent at this layer — A30.)

---

## Alternatives considered

- **Redesign the state machine "properly reactive"** (drop speculative pour, markers) — rejected for M2: the invariants encode hard-won crash-safety; we change detection (events vs polling), not semantics. Semantic evolution goes through the upstream RFC doc (PDR deferred deliverable).
- **Gate conditions as Dart closures** — rejected: gates are user-authored scripts in packs; the subprocess contract is the compatibility surface.
- **Direct SQL writes for transition metadata** — rejected (ADR-0001 Decision 4): bypasses audit/hooks/commit semantics; `bd batch` gives us the atomicity we wanted from SQL anyway.
