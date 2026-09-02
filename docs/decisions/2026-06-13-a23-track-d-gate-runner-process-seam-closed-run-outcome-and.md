---
status: accepted
date: 2026-06-13
decision-makers: ["agent"]
consulted: []
informed: []
register:
  spec: 1
  slug: a23-track-d-gate-runner-process-seam-closed-run-outcome-and
  surfaces:
    - "packages/**"
  obsoletes: []
  updates: []
  obsoleted-by: null
  updated-by: []
  bead: null
  legacy-id: "A23"
---
## A23 (2026-06-13) — Track D gate runner: process seam, closed run-outcome, and the env-contract deltas

**Decision:** Track D (built, `lib/src/gates/`, ~105 tests) is `GateRunnerService` over an injectable **`ProcessRunner` seam** (real `dart:io` impl + fake for tests, mirroring grid_controller's `BdRunner`) returning a closed **`ProcessRunOutcome` {exited, deadline, parentCancelled, launchFailure}** (rather than re-deriving outcome from platform error strings); parent cancellation is an explicit `CancellationToken` standing in for Go's `context.Context`, classified before deadline. Env-contract deltas from a literal gc reading: emits `GC_CITY_RUNTIME_DIR` as the canonical default `<cityPath>/.gc/runtime` and **`GC_CONTROL_DISPATCHER_TRACE_DEFAULT`**, but does **not** port gc's `TrustedAmbientCityRuntimeDir` override / `normalizeRuntimeDir` coercion (runtime.go:194-205 — a gc-runtime concern the_grid doesn't own). Tool-dir resolution (`bd`/`gc`/`dolt`/`jq`) is behind a `LookPathDir` seam (default walks real PATH; tests inject), not a hardcoded binary list. The **containment** guard (`pathWithin`/`samePath`/`resolveTrustedConditionPath`/`ralphCheckTrustedAbsoluteRoots`, symlink-resolving) is ported into `condition_path.dart` and tested against escape vectors, but **left unwired** into a live call site — per gates-exec.md §2 the convergence handler execs the *stored* gate path; the ralph two-root trusted-absolute path is a different caller wired in Track E/G when the exec site lands. `GateResult` consumed unchanged.
**Why:** ADR-0003 D3 + gates-exec.md fix the contract but not the Dart seam shape or the precise env var set; building it surfaced two gc env vars the spec under-described (a security lens flagged the dropped trace var + an unported trusted-roots boundary; both fixed). The unwired guard is deliberate — wiring needs the exec call site that Track E/G own.
**Affects (if promoted):** ADR-0003 D3 (the env var set + the seam/outcome model). Code: `packages/grid_reconciler/lib/src/gates/`.
**Status:** **promoted → ADR-0003 Decision 8 (Nico, 2026-06-14)**.

