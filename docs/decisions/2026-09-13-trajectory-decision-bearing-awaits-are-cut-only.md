---
status: accepted
date: 2026-09-13
decision-makers: ["Nico Spencer"]
consulted: []
informed: []
register:
  spec: 1
  slug: trajectory-decision-bearing-awaits-are-cut-only
  surfaces:
    - "packages/grid_sdk/lib/src/trajectory/trajectory_harness.dart"
    - "packages/grid_sdk/test/trajectory/trajectory_harness_test.dart"
    - "packages/grid_runtime/lib/src/trajectory/station_trajectory_recorder.dart"
    - "packages/grid_engine/lib/src/circuit/capability_host.dart"
    - "packages/grid_engine/lib/src/circuit/session_scope.dart"
  obsoletes: []
  updates:
    - "wave-2-entry-criteria-rulings"
    - "trajectory-queue-deadline-follows-writer-progress"
  obsoleted-by: null
  updated-by: []
  bead: tg-f0fn
  legacy-id: null
---

# Trajectory decision-bearing append awaits are cut-only

## Context and Problem Statement

The five decision-bearing recorder methods — `stepRunning`, `stepRearmed`,
`sessionCompleted`, `sessionEscalated`, and `sessionVoided` — return the
trajectory append disposition to their engine callers. The one-tick
acknowledgement deadline intentionally bounds only queue residence. Once the
single writer dequeues a request, the appender's sealed outcome owns its
disposition, so a hung in-flight append could hold those engine paths in both
trajectory disciplines.

The shadow discipline promised to leave incumbent control-flow latency
unchanged. The acknowledgement policy therefore belongs in the harness that
already owns the decision-bearing set, not as five discipline branches in the
engine.

## Decision Outcome

**Option A is accepted.** Under `TrajectoryDiscipline.cut`, the five
decision-bearing recorder methods await the existing acknowledgement. A
`Dropped` or `Suppressed` disposition takes the existing trajectory admission
breaker. Under `TrajectoryDiscipline.shadow`, the harness enqueues the same
decision-classified request through the single-writer queue and immediately
releases the caller: accepted enqueue posture returns `Acked`, while a
non-accepting posture returns `Suppressed`.

The request remains `decisionBearing: true` under shadow. Existing loss
counters and mirror-compromise behavior therefore remain unchanged even
though shadow no longer waits for the append to settle. Shadow creates no
acknowledgement completer or deadline; its control-flow latency is the same
fire-and-forget posture that preceded the decision-bearing awaits.

The discipline switch is resolved once inside
`packages/grid_sdk/lib/src/trajectory/trajectory_harness.dart`. Neither
`capability_host.dart` nor `session_scope.dart` receives the discipline or
branches on it; each engine site keeps one recorder call and its existing
await/breaker handling. Wave-2 W2-A composes this harness policy.

`appendAcked`, `_drainQueue`, `_onAckDeadline`, `_appendOne`, and `_settle`
remain unchanged. The one-tick deadline retains its queue-residence meaning,
and `Dropped` is not redefined.

**Option B is rejected** because an in-flight expiry would change engine
semantics by redefining what `Dropped` means.

**Option C is rejected** because accepting the exposure would let a hung Dolt
append stall every affected engine hot path during the live shadow soak.

### Consequences

* Good, because cut keeps the acknowledgement-backed breaker exactly as
  designed.
* Good, because shadow retains decision-bearing loss accounting without
  paying trajectory append latency on engine control flow.
* Bad, because a cut station still waits without an additional in-flight
  bound once the appender has accepted a decision-bearing request.
