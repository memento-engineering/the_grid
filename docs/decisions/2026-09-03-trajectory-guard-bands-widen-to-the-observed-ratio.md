---
status: accepted
date: 2026-09-03
decision-makers: [governor, agent]
consulted: []
informed: [nico]
register:
  spec: 1
  slug: trajectory-guard-bands-widen-to-the-observed-ratio
  surfaces:
    - "packages/grid_trajectory/test/support/guard_budget.dart"
    - "packages/grid_trajectory/test/calibration/guard_budget_test.dart"
    - "packages/grid_trajectory/test/integration/stage1_fold_measurement_test.dart"
  obsoletes: []
  updates: ["trajectory-guard-pins-use-the-median-of-five-probes"]
  obsoleted-by: null
  updated-by: []
  bead: tg-shry
  legacy-id: null
---

# The trajectory guard's shared-runner bands widen to 0.30x drain and 2.50x tail, and every W6 failure prints its observed ratio

## Context and Problem Statement

`the_grid#trajectory-guard-pins-use-the-median-of-five-probes` re-shaped the W6
calibration to five interleaved probes aggregated by median, then banded the
result at 0.60x the calibrated drain bound and 1.60x the calibrated tail bound.
Its own closing constraint set the acceptance evidence: ten consecutive green
runs of the guard job on `main`, and "a failure inside that window reopens the
numbers rather than the design". The window did not survive the merge.

After that entry merged as the_grid#298 at 23:33Z on 2026-09-03, the CI job
"Trajectory guards (dolt) — Stage-0 seven + Stage-1" failed on the next three
pull requests. PR #297's run 33818055118, rerun at 23:37Z, reported `Expected:
a value greater than 120.77294685990339, Actual: 120.69804320618569` — short by
0.075 appends/s. PRs #296 and #299 failed the same job on their first
post-#298 reruns.

The floor sat ON the observation. 120.69804320618569 against a 201.288/s
calibrated bound is a drain/bound ratio of 0.5996, and the band demanded 0.60.
The cause is a baseline mismatch: 0.60 and 1.60 were read off receipts measured
against the ROUND-1 baseline — one bare probe per append, where the observed
ratios were 22.5 against 28 (0.80) and 106.65 against 119.27 (0.89) — and then
applied to a DIFFERENT distribution, the median of five bare probes, whose
ratio to the sustained drain is 0.60. A margin is only meaningful against the
distribution it was measured on.

## Decision Outcome

The bands widen, and the guard records the ratio it was judged by.

The drain tolerance becomes 0.30x the calibrated throughput bound — half the
observed shared-runner ratio — and the tail tolerance becomes 2.50x the
calibrated latency bound. Effective shared-runner ceilings become 13.33x a bare
round trip for the mean append and 12.5x the machine tail for the p99. The
guard exists to catch a multiple-x regression of the fold path, not ten percent
of runner swing, and it keeps that job: on the round-4 receipt itself a 2x fold
slowdown — 60.349 appends/s against a 60.386/s floor — still fails.

Every W6 failure now carries its own receipt. The drain leg prints
`drain/probe-rate`, the raw machine-independent reading whose reciprocal is the
fold's cost in bare round trips, and `drain/calibrated-bound`, the number this
tolerance is literally set against; the tail leg prints `p99/probe-latency` and
`p99/calibrated-bound` on the same terms. Both messages state expected and
actual alongside them, and both are built by pure functions —
`drainFailureMessage` and `tailFailureMessage` in
`packages/grid_trajectory/test/support/guard_budget.dart` — so the receipt is
asserted offline without a dolt server. A green run prints the same four
ratios. The next re-tune therefore reads its margin off the distribution the
band is applied to, which is the mistake this entry exists to end.

Everything else in the updated entry is carried UNCHANGED and stays in force:
five interleaved probes of 104 trips each, one before the storm, three between
its quarters and one after; the median of the five as the aggregate on BOTH
sides; `kFoldMeanCostRatio` 4.0 and `kFoldTailCostRatio` 5.0, still immovable
without remeasurement per
`the_grid#trajectory-guard-pins-are-runner-relative`; the tight absolute pins
on a developer machine where `TRAJ_GUARD_SHARED_RUNNER` is unset; and a loud
refusal on an unknown posture or a non-positive calibration unit.

`the_grid#stage0-guards-gate-prs` is unamended. Both W6 assertions STAY in the
pull-request and merge-group job, nothing is tagged out of it, and moving them
to a nightly workflow stays rejected — this entry changes the numbers, not
where they run.

### Consequences

* Good, because the floor no longer sits on the observed shared-runner ratio:
  the round-4 receipt clears it by 2.0x instead of missing it by 0.075
  appends/s, so a good change is no longer ejected from the merge queue.
* Good, because a failure now carries the two ratios a re-tune needs, measured
  on the distribution the band is applied to — the receipt that was missing
  when 0.60 was chosen.
* Bad, because the effective mean ceiling widens from 6.67x to 13.33x a bare
  round trip: against the slowest measured base a fold regression must reach
  roughly 8.6x before a shared runner reddens. The developer-machine absolutes
  — drain above 28.0 appends/s and p99 below 250 ms — remain the tight gate.
* Bad, because the W6 failure wording now lives in the test-support budget
  rather than at the assertion, so a reader of the integration test must open
  `guard_budget.dart` to see it.
* Constraint: the acceptance evidence is unchanged in kind — ten consecutive
  green runs of the guard job on `main`. A failure inside that window reopens
  the numbers again, and the observed ratio the guard now prints is the receipt
  to reopen them with.
