---
status: accepted
date: 2026-09-09
decision-makers: ["nico"]
consulted: []
informed: []
register:
  spec: 1
  slug: trajectory-queue-deadline-follows-writer-progress
  surfaces:
    - "packages/grid_sdk/lib/src/trajectory/trajectory_harness.dart"
    - "packages/grid_sdk/test/trajectory/trajectory_harness_test.dart"
  obsoletes: []
  updates: []
  obsoleted-by: null
  updated-by: []
  bead: tg-for1
  legacy-id: null
---

# The trajectory queue deadline follows writer progress

## Context and Problem Statement

A decision-bearing trajectory append currently has a one-tick queue-residence
deadline. Boot reconciliation and ordinary critic fan-out can build a deep
queue while the sole appender continues committing records, so residence time
misclassifies a healthy draining writer as stalled. The resulting `Dropped`
disposition compromises the dual read for the epoch under shadow and halts
fresh admission under cut.

The queue deadline must continue to detect a stalled writer and must never
permit an acknowledged request to wait without a bound. The in-flight append
has a separate bound tracked by `tg-f0fn`.

## Decision Outcome

An acknowledged trajectory request may be dropped by the queue deadline only
when the single writer pump has completed no queued request for one full
`TrajectoryConfig.tickInterval` while that request remains queued, or when
that request reaches a total queue residence of 60 tick intervals.

`TrajectoryHarness.appendAcked` records the request's queue-entry instant from
the existing injected clock and arms the existing injected one-shot timer for
one tick interval. Dequeue still cancels that queue timer before `_appendOne`
begins. Immediately after each `_appendOne` future completes, `_drainQueue`
records writer progress from the injected clock; every completed sealed
outcome and every thrown outcome mapped by `_appendOne` counts as pump progress
because the writer finished processing that queue entry.

When `_onAckDeadline` runs for an unsettled entry that is still queued, total
residence is checked first. Residence greater than or equal to 60 tick
intervals drops the entry. Below that cap, a writer-progress stamp strictly
less than one tick interval old re-arms the entry for one full tick interval.
A missing stamp or a stamp at least one full tick interval old drops the entry.
Both drop branches retain the existing `append acknowledgement deadline`
reason and flow through `_drop`, so counters, mirror compromise, admission
halt, and `trajectory.appendDropped` remain unchanged.

The 60-tick cap is a fixed safety invariant, not a new operator configuration.
The existing queue bound and `TrajectoryAppendResult` contract are unchanged,
fire-and-forget requests gain no acknowledgement timer, and `_settle` remains
the only first-write-wins completion seam.

## Boundaries

This decision changes only time spent queued. Once a request is dequeued, its
queue timer is canceled and the appender's sealed outcome continues to own its
disposition. Bounding an append already in flight remains the separate
`tg-f0fn` decision.

## Alternatives Considered

Submitting reconciled terminal records through the fire-and-forget surface was
rejected because it can silently lose outcomes that the trajectory exists to
record. An unbounded series of progress-based re-arms was rejected because a
pathological producer could otherwise keep an acknowledged request queued
forever.

## Consequences

Healthy boot and review bursts may occupy more than one tick interval without
losing decision records while the single writer keeps completing entries. A
writer with no completion for one full tick still produces the same loss
posture, and a continuously progressing flood becomes visible no later than
the fixed 60-tick residence cap.
