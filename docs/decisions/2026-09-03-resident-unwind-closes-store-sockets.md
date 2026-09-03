---
status: accepted
date: 2026-09-03
decision-makers: [agent]
consulted: []
informed: []
register:
  spec: 1
  slug: resident-unwind-closes-store-sockets
  surfaces:
    - "packages/grid_cli/lib/src/up_command.dart"
    - "packages/grid_sdk/lib/src/work/store_connection.dart"
    - "packages/grid_sdk/lib/src/run/grid_delegate.dart"
    - "packages/beads_dart/lib/src/reactivity/grid_runtime_factory.dart"
  obsoletes: []
  updates: []
  obsoleted-by: null
  updated-by: []
  bead: tg-46q1
  legacy-id: null
---

# The resident shell closes the station's store sockets; the delegate vends the handles

## Context and Problem Statement

Two consecutive residents reached the shutdown fixpoint, released
`station.lock`, and never exited. `lsof` showed two to three established
sockets to the state store's `bd db-proxy-child`, which runs
`--idle-timeout -1ns` and so never reaps them either. An open socket with a
pending read keeps the Dart isolate alive after `main()` unwinds.

The pools are `DoltQueryService` instances opened by `GridRuntimeFactory.build`
and closed by `assembleStationWork`'s `sourcesShutdown`, reachable only through
`StationWorkRuntime.shutdown()`, whose only resident-side caller is the
delegate's `dispose()`. `GridDelegate` is a `StateNotifier`: `dispose()` is
synchronous and `void`, so the async close can only be fired and dropped.

## Decision Outcome

The delegate vends its open store connections (`GridDelegate.openStores`, a
`List<StoreConnection>` ordered state-store-first), and the resident shell
closes them as a settle step in its unwind — after `grid.teardown()`, before
`stationLock.release`, each bounded by `kStoreCloseTimeout` (2 s) so a
half-open socket cannot hold the unwind, and counted into the shutdown
narrative (`store connections closed: N/M`).

`sourcesShutdown` is unchanged and still closes the same pools;
`DoltQueryService.close()` is idempotent, so this is one close awaited at the
one locus that can await it, not a second closing mechanism.

Rejected: an async teardown rail on `GridDelegate` awaited by `runGrid`. It
would change `runGrid`'s teardown contract for every consumer to fix a socket
close, where the vend follows the contract the shell already reads the delegate
through (`stationView`, `sweepOrphans`).

### Consequences

- A station that opens stores outside `assembleStationWork` must override
  `openStores` or keep leaking; the default is empty and silent by design
  (absence is a rendered posture, docs/STYLE.md rule 3).
- The hot-restart path still retires a delegate without closing its stores;
  that is a separate leak with its own receipt.
- ADR-0014 D-R2's graceful order is preserved: the lock release stays last.
