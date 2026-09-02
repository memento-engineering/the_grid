---
status: accepted
date: 2026-06-13
decision-makers: ["agent"]
consulted: []
informed: []
register:
  spec: 1
  slug: a17-track-a-convergence-domain-metadata-codec-the-shapes-the
  surfaces:
    - "packages/**"
  obsoletes: []
  updates: []
  obsoleted-by: null
  updated-by: []
  bead: null
  legacy-id: "A17"
---
## A17 (2026-06-13) — Track A convergence domain + metadata codec: the shapes the rest of M2 binds to

**Decision:** Track A (built, `packages/grid_reconciler`, 240 tests green) fixes these design shapes. **(1) Closed-set vs open-set typing follows gc's own consumption:** closed Dart enums where gc validates and errors on unknowns — `ConvergenceState` {creating, active, waiting_manual, waiting_trigger, terminated} (⚠ snake_case on the wire), `GateMode` {manual, condition, hybrid}, `GateOutcome` {pass, fail, timeout, error}, `GateTimeoutAction` {iterate, retry, manual, terminate}, `TriggerMode` {none(=`''`), event}; open extension-types-over-String where gc passes the value through unvalidated — `TerminalReason`, `WaitingReason`, `Verdict`. **(2) Total decode, never throws past the boundary:** `ConvergenceStateReading` {notAdopted | known(state) | unrecognized(raw)} — absent key *and* empty string both decode to `notAdopted` (gc's `""` adopt path, reconcile.go); any unknown non-empty value is `unrecognized` (a typed surface shadow mode must handle, not crash on). Each typed field is a `FieldReading<T>` {value | absent | malformed}; a codec-level `failures` getter aggregates malformed fields for shadow diagnostics without poisoning clean fields. The input map is held verbatim (`raw`) and `encode()` returns it, so `encode(decode(m)) == m` for ANY map by construction. **(3) Go scalar parity:** `GoDuration` (int64 ns; ports `time.ParseDuration`/`Duration.String` incl. both overflow guards) and `goAtoi`/`goDecodeInt`/`goEncodeInt`/`goEncodeBool`/`goDecodeBool` are byte-faithful to Go, pinned against **go1.26 actual output** (not self-round-tripped). **(4) Actions are data:** sealed `ReconcilerAction` carries semantic fields *and* exposes its gc write sequence as derived getters (`preWrites`/`activeWispWrite`/`commitWrites`/`terminalWrites`, `last_processed_wisp` always last — and in terminal paths *after* `CloseBead`, [[A19]]); the union extends ADR-0003's seven wire-named actions with carrier variants (`pourSpeculative`, `persistGateOutcome`, `repairIteration`, `failed`, `requeue`) that map wire→null. `ReducerEvent` {wispClosed, gateEvaluated(GateResult), operatorApprove/Iterate/Stop(postDrain), triggerPassed(nextIteration)} is the `reduce(state, event, snapshot)` input (Track G adapts `GraphEvent.beadClosed` → `wispClosed`). **(5) Projections + providers:** `Convergence`/`Wisp` over the snapshot reuse grid_controller's exported `ProjectionResult`; `Wisp.subtreeIds` is post-order (= burn order), `speculativeNodes` exposes the `gc.deferred_*` carriers, `findByIdempotencyKey` is a pure snapshot scan ([[A15]]); providers `convergencesProvider`/`convergencesByStateProvider`/`activeWispProvider` mirror ADR-0002 D2 (byState keyed by the *reading* so notAdopted/unrecognized form their own groups, never dropped).
**Why:** ADR-0003 + ADR-0002 D2 name the state machine, action vocabulary and projections but leave the decode boundary, the closed/open typing, the Go-scalar encodings, and the action payload shape to implementation. These are the contract Tracks B–H consume; an adversarial consumer-lens verifier (drafting Track B/E/G against the API) confirmed sufficiency after fixes. Extends A13's `ProjectionResult` pattern to the convergence domain.
**Affects (if promoted):** ADR-0002 D2 + ADR-0003 (the typed contract surface). Code: `packages/grid_reconciler/lib/src/{convergence,projections,providers}/`.
**Status:** **promoted → ADR-0002 Decision 2 (Nico, 2026-06-14)** — Track A decode-boundary/typing record + genesis cross-ref ([[A30]]: total-decode discipline matches genesis's stance, different layer, genesis not adopted).

