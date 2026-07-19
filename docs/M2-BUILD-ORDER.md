# M2 build order — dependency-ordered tracks

Orchestration breakdown of **ADR-0003** (Accepted — the ratified M2 spec). M2 ports
gc's **work-convergence** state machine into a new `grid_reconciler` package that consumes
`grid_controller`'s `GraphEvent` stream + `GraphSnapshot` (M1) and actuates through bd.
Tracks run in parallel where inputs allow; ⊣ marks a hard dependency. AI decisions made
en route: ADR-0000 amendments, never silent. Conventions: CLAUDE.md. Source spec on disk:
`~/development/gastownhall/gascity/internal/convergence/` (~4.1k LOC non-test, 21 test
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

- **Track A — convergence domain + metadata codec** ✅ **DONE** (2026-06-13, 240 tests; design
  pinned in ADR-0000 **A17–A19**) *(pure; the contract everything binds to)*:
  `ConvergenceState {creating, active, waiting_manual, waiting_trigger, terminated}` (⚠ snake_case
  wire) with a total-decode `ConvergenceStateReading {notAdopted | known | unrecognized}`;
  the typed `convergence.*` metadata codec — **31 keys, not 16** (A18 corrects the count; the
  build order's original list omitted `pending_next_wisp` + 14 others, several invariant-load-
  bearing; source `metadata.go:12-44`), each field a `FieldReading {value|absent|malformed}`,
  unknown keys preserved verbatim so `encode(decode(m))==m` (A13 pattern); `GateMode`/`GateOutcome`/
  `GateTimeoutAction`/`TriggerMode` closed enums, `TerminalReason`/`WaitingReason`/`Verdict` open
  extension types (gc passes them through unvalidated); Go-scalar parity (`GoDuration`, `goAtoi`…)
  pinned to go1.26 output. Sealed `ReconcilerAction` (the 7 ADR-0003 wire actions + carrier
  variants `pourSpeculative`/`persistGateOutcome`/`repairIteration`/`failed`/`requeue`) — every
  action is data, exposing its gc ordered-write sequence as derived getters; `ReducerEvent` is the
  `reduce()` input. `Convergence`/`Wisp` projections over the snapshot (reusing grid_controller's
  `ProjectionResult`; `Wisp.subtreeIds` post-order = burn order, `speculativeNodes`,
  `findByIdempotencyKey`) + providers (ADR-0002 D2: `convergencesProvider`,
  `convergencesByStateProvider` keyed by the *reading*, `activeWispProvider`).
- **Track B — the pure state machine** ✅ **DONE** (2026-06-13, ~110 tests; design ADR-0000 **A22**)
  ⊣ A: `ConvergenceReducer.reduce(Convergence, ReducerEvent, GraphSnapshot) → ReduceResult` (ordered
  action list + `primary` getter), switch-matched + exhaustive, **ported from the Go** (handler.go
  9-step + operator/trigger handlers) per A19 not the incomplete table. Gate eval is a **two-reduce
  phase split** (fresh: `[pourSpeculative, evaluateGate]` → Track D runs it → re-enter via
  `gateEvaluated` → `persistGateOutcome` + transition; replay skips phase 1; manual short-circuits
  in one reduce). `RetryHandler` + trigger-gated CREATE are the create/actuator surface, NOT reduce
  transitions (A22). **Preserves all 7 invariants verbatim** (Track A's ordered-write getters encode
  invariant 2 incl. `last_processed_wisp` after `CloseBead` on terminal paths). Pure (no I/O/clock),
  exhaustively unit-tested against the transliterated conformance inventories.
- **Track C — recovery / full-reconcile pass** ✅ **DONE** (2026-06-13, 49 tests; design ADR-0000
  **A25**) ⊣ A, B: `ConvergenceRecovery.reconcile(snapshot) → RecoveryReport`, a **pure** port of
  `reconcile.go` recovery paths (state `""`→adopt/pour wisp 1 · `creating`→terminate ·
  `terminated`-but-open→close+re-emit · `waitingManual`→re-emit hold + repair markers ·
  `waitingTrigger`→no-op unless terminal · `active`→recover/replay/pour). Recovery effects are a
  separate `RecoveryAction` union; the two replay paths **reuse `ConvergenceReducer`** (A22).
  Idempotent = fixpoint-of-writes (the genuine manual hold re-emits every pass by design). Runs at
  startup + as a low-frequency backstop. (Live-store-failure error paths deferred to Track G — A25.)
- **Track D — gate execution** ✅ **DONE** (2026-06-13, ~105 tests; design ADR-0000 **A23**)
  ⊣ A: `GateRunnerService` over an injectable `ProcessRunner` seam (fake in unit tests, real
  subprocess in integration-tagged) returning a closed `ProcessRunOutcome`; gc's env contract
  verbatim (`GC_BEAD_ID, GC_ITERATION, GC_WISP_ID, GC_AGENT_VERDICT, GC_ARTIFACT_DIR, GC_CITY_RUNTIME_DIR,
  GC_CONTROL_DISPATCHER_TRACE_DEFAULT`, durations, paths); outcome by exit code (0=pass / non-zero=fail /
  deadline=timeout / pre-exec=error), parent-cancel via `CancellationToken`; timeout actions
  `iterate`/`retry`(≤3)/`manual`/`terminate`; bounded stdout/stderr capture; **symlink/traversal
  containment** ported + escape-tested (A23 — the trusted-roots guard is built but wired by Track E/G
  at the exec call site). Agent-verdict channel is read, not reinterpreted.
- **Track E — actuator** ✅ **DONE** (2026-06-13, ~235 tests, passed both adversarial lenses with
  no fix round; design ADR-0000 **A26**) ⊣ A, B, grid_controller: the_grid's **only writer** —
  `Actuator` seam (+ `BdActuator`/`FakeActuator`) executing a `ReduceResult`'s ordered writes (A17
  getters). **Not via `bd batch`** (A16) — sequenced calls ordered by the write-ordering invariant:
  metadata via `bd update --metadata` (merges; works on closed beads), **burn** via `bd delete`
  subtree in natural post-order (NOT close — only *speculative* wisps burn; a stopped active wisp is
  *closed*, A26), **pour** via `bd cook --mode=runtime` + `bd create --graph` **PERSISTENT — no
  `--ephemeral`** (A15), idempotency pre-checked by a **live** `DoltQueryService` SELECT probe
  (`JSON_EXTRACT(metadata,'$.idempotency_key')`, not `bd show`) immediately before pour (A17).
  Extended grid_controller's `BdCliService` (`update(--metadata)`, `applyGraph`, `delete`, `cook`)
  + `GraphApplyPlan`. Step-8 bus events deferred to Track G's exec site. Seam fakes in tests; no
  live writes (ADR-0003 D4/D6).
- **Track F — ready-work SQL port + differential harness** ✅ **DONE** (2026-06-13, +26 offline +
  hermetic differential green; design + correction ADR-0000 **A24**) ⊣ grid_controller
  (DoltQueryService): ported `issueops/ready_work.go`'s predicate (status∈{open}, `is_blocked`=0 over
  {blocks, conditional-blocks, waits-for}, `defer_until`, ephemeral, molecule-exclusion A14, sort
  policy) to SQL over the pool via a `runReadTransaction` (START TRANSACTION READ ONLY) seam.
  ⚠ **A24 correction:** `bd ready` applies **NO conditional-blocks failure-keyword semantics** —
  `blocked.go:29` treats conditional-blocks identically to blocks (`IsFailureClose` has zero
  non-test call sites); the keyword set is ported as inert data. **Three-half differential** (D5):
  hermetic `bd init` oracle witnesses (everywhere) · hermetic `dolt sql-server` SQL-port==`bd ready`
  on seeded fixtures · live read-only over `tg`, self-skipping without `GC_DOLT_PASSWORD` and never
  seeding the gc-managed server (partition rule). `bd ready` stays the oracle + fallback.
- **Track G — reconciler runtime + shadow mode** ✅ **DONE** (2026-06-13, +~36 offline + 3 lifecycle
  integration tests; design ADR-0000 **A27**; one critical drain-ordering bug found by adversarial
  verify + fixed/regression-tested) ⊣ B, C, D, E: wires the `GraphEvent` stream →
  per-bead **serialized** processing (invariant 7) → state machine (B) → actuator (E) + the
  periodic full reconcile (C); Riverpod providers for convergence projections. ⚠ **Known gap (A27):**
  the runtime actuates only the reducer-shaped *replay* plans; recovery-specific effects
  (adopt/pour-wisp-1, partial-creation terminate, marker repair) are surfaced as data — a **recovery
  actuator** is the M3 follow-up (harmless for M2: shadow is read-only, recovery pass is Track-C
  conformance-tested). **Freshness (A17):**
  events are evaluated against a **write-through post-actuation overlay**, never the raw snapshot
  (else a stale snapshot re-fires `triggerPassed` → duplicate pour); the operator-stop **drain**
  is re-enqueued as `OperatorStopEvent(postDrain: true)` behind the synthesized `wispClosed`
  pipeline (A19). **Dirty signal (A21):** `SELECT @@<db>_working` already flips on dolt-ignored
  wisp writes, so the SQL probe alone catches gc's cross-workspace wisp closes (the file-watcher
  cannot) — no wisp-specific augmentation needed; treat it as sufficient-not-necessary (structural
  diff is authority). **Shadow mode (ADR-0003 D6, strictly read-only):** compute every transition
  gc would make, diff against what gc actually did, report divergence — no writes. gc's convergence
  wisps are persistent `issues` beads (A15 correction), so shadow reads them directly. Coexistence
  partition enforced (disjoint bead/rig set; ownership marker).
- **Track H — conformance suite** ✅ **DONE** (2026-06-13; design ADR-0000 **A28**; report
  `doc/port/conformance-report.md`) ⊣ B, C, D: audited all **21 gc `*_test.go` (165 funcs)** against
  source — every must-priority case already covered faithfully by the per-component suites
  (reducer/recovery/gates/literals), **zero must-gaps, zero real bugs**; added 5 **end-to-end**
  lifecycle conformance tests through the real `ReconcilerRuntime` (the layer units can't provide).
  The coverage report is the DoD-criterion-1 artifact. n-a classes documented (create/retry → M3;
  live-store-I/O → Track-G seam; gate-internals → Track D suite). The executable spec (ADR-0003 D7).
- **Track I — convergence fixture capture** ◐ **codec half DONE** (2026-06-13; ADR-0000 **A29**)
  *(decoupled — the "blocked on a live convergence" framing conflated two halves)*:
  **(a) codec fidelity ✅** — captured **real gc-produced** convergence metadata across 6 states by
  driving gc's *actual* writer through `cmd/gc`'s test seam (`MemStore` + fake provider, **no
  supervisor/agents/live city** — `gc start` is machine-wide, avoided; gascity compiles with
  `icu4c@78` CGO flags), bd-export round-tripped, pinned at
  `fixtures/upstream/2026-06-11-bd-1.0.5/convergence/`. The codec decodes all 6 **total + clean,
  byte-for-byte round-trip, no lib change** — the fixtures *confirm* Track A. A shadow **replay
  harness** + AGREE/DIVERGE goldens validate the divergence mechanism offline (and surfaced a real
  manual-loop divergence — the D6 signal). **(b) live shadow ◐** — diffing against *live* gc traffic
  still needs a convergence running on a the_grid-owned disjoint rig (gc writes, the_grid reads):
  **M3 dogfood**, needs Nico + creds + ADR-0006. Folds in A13's molecule/step gap (the captured
  subgraph carries the real molecule→step→needs shape).

## Dependency spine

`0 → A → {B, D, F} → {C, E} → G → H` · I just-in-time.

## Definition of done (ADR-0003 + PDR §5 M2 row) — STATUS 2026-06-13

1. ✅ State machine + recovery **conformance-green** against the transliterated gc suite (D7, H) —
   all 21 gc `*_test.go` must-cases covered faithfully + e2e; report `doc/port/conformance-report.md` (A28).
2. ✅ Ready-work SQL **differential-equal** to `bd ready` across all scenarios (D5, F) — three-half
   harness (hermetic oracle + hermetic `dolt sql-server` SQL-port + live, A24); live half self-skips.
3. ✅ Gate subprocess contract verified — env, exit-code→outcome, timeout actions, containment (D, A23).
4. ◐ **Shadow mode** is built, **structurally read-only** (A27), and its divergence **mechanism is now
   validated offline against REAL gc bytes** — the Track-I capture + replay harness/goldens, which even
   surfaced a genuine manual-loop divergence (A29). The codec is confirmed total+clean vs reality. The
   remaining **live** half (diff against *live* gc convergence traffic) is **M3 dogfood** — needs gc
   running a convergence on a the_grid-owned disjoint rig + `GC_DOLT_PASSWORD` (degrades like M1 2/4).
5. ✅ Coexistence partition respected: ownership gates the whole cycle, shadow constructs no writer (D6, A27).
6. ✅ Every en-route AI decision sits in ADR-0000 as pending (A15–A29).

**Carried to M3 (do not block M2 acceptance):** a **recovery actuator** (the runtime actuates only
reducer-shaped replay plans; recovery-specific effects are surfaced as data — A27); the **Track I live
shadow** run (codec fidelity ✅ A29; the live-traffic diff lights up when gc drives one owned-rig convergence).

## Known gaps carried in (do not let these block the pure core)

- **No pinned convergence fixture** (Track I) — build B/C/D/H against gc's Go tests now; pin a real
  subgraph when a convergence runs.
- **Shadow acceptance** needs live convergence traffic (none today) + dolt creds.
- ~~**bd pour verb** (Track 0.2) may not be offline-reproducible~~ — **resolved** (A15): it is, via
  `cook`+`create --graph`. The `Actuator` seam stays for testability (fake in unit tests), not for an
  offline gap. Track E must extend `grid_controller`'s `BdCliService` with a `--metadata` update path,
  a `--graph --ephemeral` pour path, and a `cook --mode=runtime` resolve (A16 "Affects: code").
