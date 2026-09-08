---
status: accepted
date: 2026-09-08
decision-makers: ["governor"]
consulted: []
informed: []
register:
  spec: 1
  slug: advisory-pre-boot-maintenance-exception
  surfaces:
    - "packages/grid_sdk/lib/src/run/run_grid.dart"
    - "packages/grid_sdk/lib/src/run/grid_delegate.dart"
  obsoletes: []
  updates:
    - "post-mount-errors-are-contained-at-run-grid"
  obsoleted-by: null
  updated-by: []
  bead: null
  legacy-id: null
---

# Advisory pre-boot maintenance never aborts boot

## Context and Problem Statement

State-store collection must finish before delegate boot can open the Dolt
server. That puts maintenance before the guarded zone established by
`post-mount-errors-are-contained-at-run-grid`, where the default post-mount
error sink cannot contain a failure. Moving collection after boot would race
the live server and recreate the manual stop-and-collect procedure this seam
retires.

## Considered Options

* Move maintenance after boot into the existing guarded zone.
* Send pre-boot maintenance failures to the post-mount default error sink.
* Give this one advisory pre-boot step a bespoke non-fatal reporting path.

## Decision Outcome

The third option is taken. When `GridDelegate.maintainsStateStoreOnBoot` is
true, `runGrid` awaits advisory state-store maintenance after `didLaunch` and
before `boot`, before anything can open the store server. A failure becomes a
`GridHookError` attributed to `maintenance` and goes exactly once to a
caller-supplied `onError`; when `onError` is absent, `runGrid` writes exactly
one attributed summary line to stderr. The failure never enters the post-boot
guarded-zone handler and never aborts boot.

This is the one deliberate exception to the pre-tree-is-fatal rule.
`didLaunch`, `boot`, and synchronous first-mount failures remain terminal.
Every post-mount containment statement in
`post-mount-errors-are-contained-at-run-grid` remains unchanged and in force.

### Consequences

* Good, because every station using `runGrid` receives one pre-boot
  maintenance owner without racing an open state-store server.
* Good, because advisory collection failures remain loud while the station
  continues to boot.
* Bad, because this pre-tree hook needs a reporting branch distinct from the
  guarded post-mount error boundary.
