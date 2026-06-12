# M2 build order — dependency-ordered tracks

Orchestration breakdown of **ADR-0003** (Accepted — the ratified M2 spec). M2 ports
gc's **work-convergence** state machine into a new `grid_reconciler` package that consumes
`grid_controller`'s `GraphEvent` stream + `GraphSnapshot` (M1) and actuates through bd.
Tracks run in parallel where inputs allow; ⊣ marks a hard dependency. AI decisions made
en route: ADR-0000 amendments, never silent. Conventions: CLAUDE.md. Source spec on disk:
`~/development/com.gastownhall/gascity/internal/convergence/` (~4.1k LOC non-test, 21 test
files = the conformance oracle, ADR-0003 D7).

**Scope (ADR-0003 D1):** work convergence ONLY. Topology/session reconciliation is M3/M4.

## Track 0 — serial preconditions

1. **`grid_reconciler` scaffold**: pubspec (depends on `grid_controller`, freezed/riverpod/
   test), add to the root pub workspace + melos. Green: `melos bootstrap` + `dart analyze`.
2. **Wisp-pour verb spike** (ADR-0003 D4) — ✅ **RESOLVED** (2026-06-12, ADR-0000 **A15/A16**;
   artifact `packages/grid_reconciler/tool/wisp_pour_spike.sh`). The pour IS offline-reproducible
   and atomic via **`bd cook <formula> --mode=runtime` (resolve) → `bd create --graph <plan>
   --ephemeral` (pour)**, the plan's root node carrying `parent_id`→convergence bead +
   `metadata.idempotency_key = converge:{beadID}:iter:{N}` (the faithful CLI analog of gc's
   in-process `molecule.Cook`; `bd mol wisp` is rejected — no parent/key/file surface).
   **Idempotency is the_grid's own job** (`FindByIdempotencyKey` = scan the root's children for
   the key metadata over the snapshot — no bd primitive). **A16 caveat:** `bd batch` cannot carry
   `metadata` or `mol wisp` (allowed update keys: status/priority/title/assignee), so transition
   metadata uses `bd update --metadata`; crash-safety rests on the write-ordering + idempotency
   invariants, not batch atomicity. **Touches ratified ADR-0003 D4** → pending in ADR-0000, not
   silently edited into D4.

## Parallel tracks (after Track 0.1)

- **Track A — convergence domain + metadata codec** *(pure; the contract everything binds to)*:
  freezed `ConvergenceState {creating, active, waitingManual, waitingTrigger, terminated}`;
  the typed `convergence.*` metadata codec (16 keys — `state, iteration, max_iterations,
  formula, target, gate_mode, gate_condition, gate_timeout, gate_timeout_action, active_wisp,
  last_processed_wisp, agent_verdict, agent_verdict_wisp, gate_outcome, gate_exit_code,
  gate_outcome_wisp`; source `metadata.go`), preserving unknown keys in a raw map (A13
  pattern); `GateMode {manual, condition, hybrid}`; `GateOutcome {pass, fail, timeout, error}`;
  sealed `ReconcilerAction {iterate, approved, noConvergence, waitingManual, waitingTrigger,
  stopped, skipped}` — every action is data. `Convergence`/`Wisp` projections over `(bead,
  metadata, deps)` (ADR-0002 D2: `convergencesProvider`, `convergencesByStateProvider`,
  `activeWispProvider`).
- **Track B — the pure state machine** ⊣ A: `reduce(state, event, snapshot) → (state′,
  List<ReconcilerAction>)`, switch-matched + exhaustive (ports `handler.go` lines 161–390,
  the 9-step algorithm + ADR-0003's transition table). **Preserves all 7 invariants verbatim**:
  monotonic dedup (skip iter ≤ `last_processed_wisp`), write-ordering (`last_processed_wisp`
  written LAST = commit point; `gate_outcome_wisp` last in gate persistence), idempotency keys,
  iteration-from-closed-wisp-count (self-healing), speculative pour before gate eval
  (`pending_next_wisp`), terminal irreversibility, single-writer. Pure → exhaustively unit-tested.
- **Track C — recovery / full-reconcile pass** ⊣ A, B: ports `reconcile.go` recovery paths
  (state `""`→adopt/pour wisp 1 · `creating`→terminate · `terminated`-but-open→close+re-emit ·
  `waitingManual`→re-emit hold + repair markers · `waitingTrigger`→no-op unless terminal ·
  `active`→recover/replay/pour). Runs at startup + as a low-frequency backstop over the snapshot.
- **Track D — gate execution** ⊣ A: subprocess gate runner (`gate.go`/`condition.go`/`hybrid.go`)
  with gc's env contract verbatim (`GC_BEAD_ID, GC_ITERATION, GC_WISP_ID, GC_AGENT_VERDICT,
  GC_ARTIFACT_DIR`, durations, paths); outcome by exit code (0=pass / non-zero=fail /
  deadline=timeout / pre-exec=error); timeout actions `iterate`/`retry`(≤3)/`manual`/`terminate`;
  stdout/stderr capture + truncate into metadata; path traversal/symlink containment defenses.
  Agent-verdict channel is read, not reinterpreted.
- **Track E — actuator** ⊣ A, B, grid_controller: executes `ReconcilerAction`s via
  `BdCliService.batch` — multi-write transitions (metadata sets + close, burn + repoint) as ONE
  `bd batch` (one commit, atomic, one dirty signal back into our own controller). Wisp pour via
  the Track-0.2 verb. The `Actuator` interface is the seam (fake in tests; ADR-0003 D4).
- **Track F — ready-work SQL port + differential harness** ⊣ grid_controller (DoltQueryService):
  port `issueops/ready_work.go`'s predicate (status∈{open}, `is_blocked`=0 over
  {blocks, conditional-blocks, waits-for} with conditional-blocks failure-keyword semantics,
  `defer_until`, ephemeral, sort policy) to SQL over the pool; a **differential harness** replays
  every scenario against both the SQL port and `bd ready` and diffs (ADR-0003 D5). `bd ready`
  stays the oracle + fallback. Live half self-skips without `GC_DOLT_PASSWORD`.
- **Track G — reconciler runtime + shadow mode** ⊣ B, C, D, E: wires the `GraphEvent` stream →
  per-bead **serialized** processing (invariant 7) → state machine (B) → actuator (E) + the
  periodic full reconcile (C); Riverpod providers for convergence projections. **Shadow mode
  (ADR-0003 D6, strictly read-only):** compute every transition gc would make, diff against what
  gc actually did, report divergence — no writes. Coexistence partition enforced (disjoint
  bead/rig set; ownership marker).
- **Track H — conformance suite** ⊣ B, C, D: transliterate gc's convergence tests into Dart —
  `handler_test.go` (9-step), `reconcile_test.go` (recovery), `manual_test.go`, `trigger_test.go`,
  `gate_test.go`, `hybrid_test.go`. The executable spec (ADR-0003 D7).
- **Track I — convergence fixture capture** *(just-in-time; DATA GAP)*: capture a real
  `convergence + gate + wisp + molecule + step + needs` subgraph and pin it (folds in A13's
  molecule/step gap). Validates the Track-A metadata codec against reality. **Blocked on live
  convergence activity** — the live city currently holds ZERO convergence/gate/wisp beads
  (export histogram = session/task/bug), so until a convergence runs, A's codec is validated
  synthetically + against the Go tests only. Source for synthetic fixtures: gc's own test
  fixtures under `convergence/*_test.go`.

## Dependency spine

`0 → A → {B, D, F} → {C, E} → G → H` · I just-in-time.

## Definition of done (ADR-0003 + PDR §5 M2 row)

1. State machine + recovery **conformance-green** against the transliterated gc suite (D7, H).
2. Ready-work SQL **differential-equal** to `bd ready` across all scenarios (D5, F).
3. Gate subprocess contract verified — env, exit-code→outcome, timeout actions, containment (D).
4. **Shadow mode** runs read-only against live convergence traffic and reports divergence vs gc
   (D2/D6) — the live half gated on convergence activity + `GC_DOLT_PASSWORD` (degrades like M1
   criteria 2/4; mechanism + replay-against-fixtures testable offline now).
5. Coexistence partition respected: disjoint bead set, shadow never writes (D6).
6. Every en-route AI decision sits in ADR-0000 as pending.

## Known gaps carried in (do not let these block the pure core)

- **No pinned convergence fixture** (Track I) — build B/C/D/H against gc's Go tests now; pin a real
  subgraph when a convergence runs.
- **Shadow acceptance** needs live convergence traffic (none today) + dolt creds.
- ~~**bd pour verb** (Track 0.2) may not be offline-reproducible~~ — **resolved** (A15): it is, via
  `cook`+`create --graph`. The `Actuator` seam stays for testability (fake in unit tests), not for an
  offline gap. Track E must extend `grid_controller`'s `BdCliService` with a `--metadata` update path,
  a `--graph --ephemeral` pour path, and a `cook --mode=runtime` resolve (A16 "Affects: code").
