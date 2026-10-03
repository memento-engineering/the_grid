---
status: accepted
date: 2026-10-03
decision-makers:
  - "governor (station seat)"
consulted: []
informed:
  - "nico"
register:
  spec: 1
  slug: retirement-acknowledgements-fence-successor-mints
  surfaces:
    - "packages/grid_engine/lib/src/circuit/session_scope.dart"
    - "packages/grid_engine/lib/src/kernel/station_admission_authority.dart"
    - "packages/grid_runtime/lib/src/trajectory/station_trajectory_recorder.dart"
    - "packages/grid_sdk/lib/src/trajectory/attempt_liveness_recovery.dart"
    - "packages/grid_sdk/lib/src/trajectory/trajectory_harness.dart"
  obsoletes: []
  updates:
    - "trajectory-decision-bearing-awaits-are-cut-only"
  obsoleted-by: null
  updated-by: []
  bead: tg-1uat
  legacy-id: null
---

# Retirement acknowledgements fence successor mints

## Context and Problem Statement

A replacement session could be minted while its predecessor's durable attempt
still appeared live. The successor then entered the linked-session frontier but
never dispatched its first step. Rework, void, abandonment, and liveness-loss
retirements reached the trajectory through different call-site hooks, leaving an
unreserved window in which admission could create the replacement before the
retirement record was acknowledged.

Rework has an additional fold constraint: an `AttemptRoundRetired` record bumps
the round but deliberately leaves the P1 head open. Adding an `AttemptTerminal`
to make ordering convenient would violate `wave-2-entry-criteria-rulings` Q9 and
`the-soak-clean-row-honours-the-open-retired-shape`.

## Decision Outcome

`StationAdmissionAuthority` owns one retirement fence per work bead and
retirement identity. It installs the fence synchronously before the first
legacy-writer await, including when no reservation exists. Repeated retirement
calls with the same identity share the future; a different identity chains
behind any pending fence. `createSessionAttempt` atomically consumes the
completed fence before it reads linked sessions, so a successor cannot outrun
any predecessor retirement already in progress.

The fence guards only successor creation. The legacy bead close releases
capacity and notifies listeners immediately, before the trajectory
acknowledgement settles. An acknowledgement error removes the matching fence
so a later fenced tick reruns the retirement. A successful fence remains until
successor creation consumes that exact retirement.

Each retirement awaits the record that path already emits. Rework awaits only
`AttemptRoundRetired`; void, molecule-pour abandonment, post-create
abandonment, and liveness loss await their existing lost `AttemptTerminal` via
`sessionVoided`. No path adds a second record merely to create a fence, and the
call-site `beforeAttemptRelease` hook is removed.

`StationTrajectoryRecorder.roundRetiredAcked` is the sixth decision-bearing
recorder method. It shares record derivation and round-cache advancement with
the enqueue-only `roundRetired`. Under cut it waits through the existing
harness acknowledgement policy; under shadow it enqueues and returns
immediately. This updates
`trajectory-decision-bearing-awaits-are-cut-only` without adding an engine-side
discipline branch.

The existing queue deadline remains governed by
`trajectory-queue-deadline-follows-writer-progress`: it bounds queue residence
only, cancels at dequeue, and does not become an in-flight timeout.
`reason-columns-are-bounded-at-derivation` applies unchanged because both
round-retirement methods share the same existing record derivation and add no
new reason column. `terminal-provenance-word-is-reconstructed` does not bind
this change because no reconstructed terminal or provenance word is added or
changed.

### Consequences

* Good, because every durable predecessor-retirement path closes the same
  admission race by construction.
* Good, because rework preserves the accepted open-retired P1 fold shape.
* Good, because a slow trajectory sink cannot retain an admission slot.
* Bad, because a work bead with a pending retirement acknowledgement cannot
  mint a replacement until that acknowledgement settles or fails loudly.
