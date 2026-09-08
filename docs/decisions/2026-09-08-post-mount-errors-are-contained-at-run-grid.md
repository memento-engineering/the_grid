---
status: accepted
date: 2026-09-08
decision-makers:
  - "Nico Spencer"
  - "specify agent"
consulted: []
informed: []
register:
  spec: 1
  slug: post-mount-errors-are-contained-at-run-grid
  surfaces:
    - "packages/grid_sdk/lib/src/run/run_grid.dart"
    - "packages/grid_sdk/lib/src/run/grid_delegate.dart"
    - "packages/grid_cli/lib/src/up_command.dart"
    - "packages/grid_cli/lib/src/diagnostics_reporter.dart"
  obsoletes: []
  updates:
    - a45-grid-sdk-track-c-the-rungrid-griddelegate-rail-shape-the
  obsoleted-by: null
  updated-by: []
  bead: tg-y2c2
  legacy-id: null
---

# Post-mount errors are contained at `runGrid`

## Context and Problem Statement

`runGrid` is the one production boot seam shared by station shells, but its
default post-mount error sink forwarded failures to
`Zone.current.handleUncaughtError`. The mounted tree itself had no root error
zone. A timer, microtask, or detached future that escaped a narrower owner
therefore reached the process root, terminated the resident, left its lock
stale, and paused every live round until an operator intervened.

The engine already applies this containment posture around individual
capability hooks through `runCapabilityGuarded`, and `SessionScope` owns its
session-level failures and flares. Neither boundary contains an error born
elsewhere in the mounted station tree. Putting a third boundary in a shell
would also split the boot contract between stations and leave other `runGrid`
consumers exposed.

## Decision Outcome

Only pre-tree `didLaunch`/`boot` and synchronous first-mount failures abort
`runGrid`; uncaught asynchronous errors born in the mounted tree's zone are
named, reported, and contained without teardown.

`runGrid` forks one guarded zone after `boot` succeeds and creates the owner,
handle, first mount and flush, post-flush rails, and detached kickoff inside
it. Scheduling owned by the live handle re-enters that zone. Its uncaught
handler preserves the original error and stack in the existing
`GridHookError` channel, adds any node-path or step identity carried by the
originating zone, and reports the named `station.uncaughtError` record exactly
once. The default sink prints that name and flat record without rethrowing, so
containment does not depend on a station supplying an `onError` callback.

The outer boundary extends `runCapabilityGuarded` one ring outward. It does
not replace per-capability containment or `SessionScope`'s per-session
containment and flare vocabulary. A composing shell may adapt
`GridHookError.name` and `GridHookError.data` to its existing `flare(String,
Map<String, String>)` transport; the SDK does not learn a transport.

A contained error never unmounts the tree, evicts a session, or disposes
mounted work. Mounted work unmounts only on a positive terminal or an explicit
grid teardown. Synchronous first-mount failure retains the existing owner and
bus cleanup and still reaches the caller.

### Consequences

- Good, because a library's detached asynchronous failure becomes a named,
  stack-bearing flare while the resident and its mounted work remain live.
- Good, because every current and future shell receives containment at the
  shared SDK seam without adding a shell-specific guard.
- Bad, because the default reporter is textual until a shell elects to route
  `GridHookError.name` and `data` to a structured flare transport.
