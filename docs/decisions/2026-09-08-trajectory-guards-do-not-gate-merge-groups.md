---
status: accepted
date: 2026-09-08
decision-makers: ["governor"]
consulted: []
informed: []
register:
  spec: 1
  slug: trajectory-guards-do-not-gate-merge-groups
  surfaces:
    - ".github/workflows/ci.yml"
  obsoletes: []
  updates:
    - "trajectory-guard-pins-are-runner-relative"
    - "trajectory-guard-pins-use-the-median-of-five-probes"
    - "trajectory-guard-bands-widen-to-the-observed-ratio"
  obsoleted-by: null
  updated-by: []
  bead: tg-d2bk
  legacy-id: null
---

# Trajectory guards do not gate merge groups

## Context and Problem Statement

On 2026-09-08 the trajectory job was the only failing job in three of the last
twelve `merge_group` runs of CI: 34197865773, 34195578780, and 34193196939,
all between 06:05Z and 07:09Z. Every failure was the same W6 p99 tail leg while
the remaining suite passed.

Run 34197865773 passed 35 tests and failed one. Its drain was 63.1 appends/s
against a 34.7 floor; mean was 15.86 ms, p50 7.82 ms, and p90 11.79 ms. Only
p99 failed: 270.02 ms against a calibrated 247.6 ms ceiling, an observed
p99/calibrated-bound ratio of 2.7260 against the 2.50 `tg-shry` tolerance.

The Main ruleset, id 19591943, requires exactly "analyze + test (Dart
packages)" and "analyze + test (Flutter packages)". The trajectory job is not
required, but its failure in a merge-group workflow still ejects the pull
request and clears auto-merge. The earlier receipts were PR #313, a four-line
pubspec floor bump, and PR #314, a documentation-only decision entry, so the
landing failures were not evidence of a trajectory regression.

## Considered Options

* Exclude the trajectory job from `merge_group`, keep it on pull requests and
  pushes to main, and add an unattended schedule.
* Keep the job in `merge_group` but gate only on mean and p90.
* Widen the W6 p99 tolerance beyond 2.50 again.

## Decision Outcome

The first option is taken. The CI workflow retains its `merge_group` trigger
because the two required analyze-and-test jobs must run for queued merge
groups. The `trajectory-guards` job alone carries
`if: ${{ github.event_name != 'merge_group' }}`, so it does not run for that event.

The job continues to run and fail closed on every pull request, every push to
`main`, and the daily scheduled run on the default branch. Its measurements,
including the W6 p99 reading, remain printed. The Stage-1 measurement test,
`guard_budget.dart`, every acceptance assertion, every calibration ratio, and
the 2.50 tail tolerance remain unchanged. The trajectory job is not added to
the Main ruleset's required checks.

This entry updates only event placement in
`the_grid#trajectory-guard-pins-are-runner-relative`,
`the_grid#trajectory-guard-pins-use-the-median-of-five-probes`, and
`the_grid#trajectory-guard-bands-widen-to-the-observed-ratio`. Their
runner-relative calibration, five-probe aggregation, failure receipts, and
0.30 drain / 2.50 tail bands remain binding wherever the job runs.

### Consequences

* Good, because shared-runner p99 noise remains visible on pull requests and
  unattended main runs without ejecting unrelated changes from the merge
  queue.
* Good, because the queue remains gated by the two checks the Main ruleset
  requires and will not hang waiting for absent workflow runs.
* Bad, because a trajectory-only regression first observed on a merge group
  does not block that landing through this job; pull-request and scheduled
  failures remain the detection and follow-up signals.
* Constraint: removing or weakening the W6 tail assertion, changing its
  tolerance, or making the scheduled or pull-request runs skip it requires a
  separate decision.

## Review log

* 2026-09-08 — option A accepted by **governor** at intake.
