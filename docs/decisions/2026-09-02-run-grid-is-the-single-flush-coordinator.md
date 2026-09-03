---
status: accepted
date: 2026-09-02
decision-makers: [agent]
consulted: []
informed: []
register:
  spec: 1
  slug: run-grid-is-the-single-flush-coordinator
  surfaces:
    - "packages/grid_sdk/lib/src/run/run_grid.dart"
    - "packages/grid_sdk/lib/src/work/station_work.dart"
    - "packages/grid_engine/lib/grid_engine.dart"
    - "packages/grid_engine/lib/src/kernel/station_driver.dart"
    - "packages/grid_engine/lib/src/seeds/substation_scope.dart"
  obsoletes: []
  updates:
    - a43-the-concurrency-governor-where-the-station-default-lives
    - adr-0012-observability
    - adr-0008-authoring-sdk-and-reentrant-engine
  obsoleted-by: null
  updated-by: []
  bead: tg-um8k
  legacy-id: null
---

# `runGrid` is the station's one flush coordinator; `StationKernel` is deleted

## Context and Problem Statement

Three recorded decisions name `StationKernel` as a running component. A43
states "Every REAL run composes one (`buildLiveWiring` → `composeStation` →
`StationKernel`), so this is not a live-arm gap". ADR-0012 Decision 2's
transport seam states "`StationKernel` retains the root `Branch` and calls
`projector.afterFlush(root)` in the flush microtask". ADR-0008 Decision 5's
implementation note states "the P0/M4-P1 code provides the `ServiceBundle` at
the station root (`StationKernel.mountRoot`); the per-`SubstationScope`
re-homing is the pending refactor executing this amendment".

None is true. Verified 2026-09-02: `StationKernel(` is constructed nowhere
outside its own constructor declaration; the production path is
`grid_cli/lib/src/up_command.dart:201` defaulting to `defaultRunMountedGrid`,
which calls `runGrid` (`grid_sdk/lib/src/run/run_grid.dart`). A45 already
recorded the true shape — "`runGrid` owns the `TreeOwner` + a
coalesced-microtask flush loop (mirroring `StationKernel`)" — but the older
statements were never corrected, and the first audit of this bug counted the
dead kernel as a scheduling authority.

The cost was not cosmetic. The tg-60n flush guard — the finally-scoped
post-flush rail, the bounded re-arm of a stranded dirty set, the failure
counter — was built inside the kernel, so production never got it: a throwing
rebuild in `runGrid` skipped `onFlushed` (the rail carrying
`WedgeMonitor.poll`, the only stall alarm) and stranded the dirty set behind
`TreeOwner`'s empty→non-empty edge trigger.

## Decision Outcome

`runGrid` is the single production flush coordinator, and it now carries the
guard: `onFlushed` runs in a `finally`, a failed pass re-arms a bounded retry
(5 consecutive failures, then the station ripens into a visible wedge), and
waiters are completed or refused only for the generation the pass applied.
`StationKernel` is deleted in the same change — no delegation shim and no
second flush loop, because two flush loops drift.

The three updated decisions are unchanged in SUBSTANCE and corrected in
ATTRIBUTION:

* **A43's concurrency governor** still binds wherever `StationServices` is
  ambient, which every real run composes through `buildLiveWiring` →
  `StationWork`.
* **ADR-0012's transport seam** is still an optional, null-by-default,
  zero-cost seam whose owner retains the root `Branch` and calls
  `projector.afterFlush(root)` in the flush microtask — that owner is
  `GridHandle`, inside `runGrid`.
* **ADR-0008 D5's per-`SubstationScope` `ServiceBundle` re-homing** is
  ALREADY LANDED, not pending: `SubstationScope` provides
  `Provider<ServiceBundle>.value(seed.services)`
  (`packages/grid_engine/lib/src/seeds/substation_scope.dart:108`), the SDK's
  work seat derives from the nearest one via `context.watch<ServiceBundle>()`
  → `ServiceBundle.derive`
  (`packages/grid_sdk/lib/src/work/station_work.dart:185,202`), and the
  kernel's own code recorded that it does NOT provide the bundle ("The
  `ServiceBundle` is NOT provided here — it is a per-substation
  responsibility provided by each `SubstationScope` … (ADR-0008 D5)",
  `station_kernel.dart:195-197`). Only the note's symbol pointer and its
  "pending" tense were stale; deleting the kernel removes no provision and in
  fact removes the last text pointing the bundle at a station root.

### Consequences

* Good, because the station's stall alarm keeps sampling through a broken tick,
  which is the one scenario it exists for.
* Good, because the register no longer describes a component that does not run,
  nor a refactor that already shipped.
* Bad, because the kernel's tests had to be re-homed (onto `StationDriver`, the
  `StationWork` seat, and `runGrid`) rather than simply kept.

## Not this

Whether the `TreeProjector` should run at all on a flush with no diagnostics
consumer is NOT decided here — that is sibling bead `tg-e47b`. The projector
call keeps its exact position inside the pass's `try`, where `StationKernel`
had it: a failed flush leaves a half-rebuilt tree the projection must not
publish.
