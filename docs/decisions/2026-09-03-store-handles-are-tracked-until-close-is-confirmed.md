---
status: accepted
date: 2026-09-03
decision-makers: [agent]
consulted: []
informed: []
register:
  spec: 1
  slug: store-handles-are-tracked-until-close-is-confirmed
  surfaces:
    - "packages/grid_sdk/lib/src/trajectory/trajectory_harness.dart"
    - "packages/grid_sdk/lib/src/work/store_connection.dart"
    - "packages/beads_dart/lib/src/services/dolt_query_service.dart"
  obsoletes: []
  updates: [resident-unwind-closes-store-sockets]
  obsoleted-by: null
  updated-by: []
  bead: tg-xvbv
  legacy-id: null
---

# A store handle is tracked until its close is confirmed, and the trajectory's sockets ride the same vend

## Context and Problem Statement

After the resident shell learned to close the delegate's vended store
connections, residents still hung: five to eight established sockets to the
state server survived the lock release, depending on load. Both owners of a
state-server socket dropped handles they could not close: the trajectory
harness swallowed a corpse's refused close and abandoned its live session on a
close timeout, and `DoltQueryService` removed a not-connected connection from
its pool while `close()` drained only the pool. The state store's
`bd db-proxy-child` runs with idle reaping disabled, so nothing else closes
those handles.

## Decision Outcome

An owner of a store socket keeps a ledger of every handle it opened and removes
a handle only on a confirmed close; a refused or timed-out close leaves the
handle tracked for a later, bounded retry. `DoltQueryService.close()` drains
that ledger rather than the pool. `TrajectoryHarness.closeOpenSessions()`
drains the harness's ledger, is called by its own `shutdown()`, and is vended to
the resident shell as `TrajectoryStoreConnection`. The harness's sockets
therefore ride the single closing locus this entry updates, ordered directly
after the state store because both connect to the same server. No second
closing step is added to the shell's unwind.

### Consequences

- Every state-server socket the resident opens is reachable from the one locus
  that can await its close, and a close that fails is retried instead of lost.
- A station whose shell awaits `StationWorkRuntime.shutdown()` rather than
  reading `openStores` is covered by the same code.
- A permanently unclosable handle remains tracked and is retried on every
  close pass; the owners' existing best-effort close contracts still suppress
  an individual socket-close error.
