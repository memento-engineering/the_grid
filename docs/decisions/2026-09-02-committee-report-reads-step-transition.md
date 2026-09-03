---
status: accepted
date: 2026-09-02
decision-makers:
  - "specify"
consulted: []
informed: ["nico"]
register:
  spec: 1
  slug: committee-report-reads-step-transition
  surfaces:
    - "packages/grid_trajectory/lib/src/cli/committee_report.dart"
    - "packages/grid_trajectory/lib/src/cli/committee_report_render.dart"
    - "packages/grid_trajectory/lib/src/codec/records/verification_records.dart"
  obsoletes: []
  updates: []
  obsoleted-by: null
  updated-by: []
  bead: tg-0ol2
  legacy-id: null
---

# The committee report reads step.transition; the dedicated verify.* writers stay deferred

## Context and Problem Statement

`traj committee-report` folds `verify.verdict.recorded`,
`verify.usage.telemetry`, `verify.route.verdict` and `gate.opened`/`gate.closed`.
No writer emits any of them: 20794 records across 13 boot epochs carry fifteen
record types, all from the attempt, step and worktree families, so every window
printed an empty lane table and $0.00. The same facts already ride
`step.transition` — a completed step's `result` map carries the lane grade, the
round and the run cost, and a gated step's `failure_reason` carries the park
reason.

## Decision Outcome

The FOLD reads `step.transition`; the write side is not touched. A dedicated
record always wins over a step-derived observation, which always wins over a
`--telemetry-root` `.usage.json` sample, and `CommitteeReport.sources` reports
the count from each source so a wired future writer is distinguishable from the
adapter. The existing dedicated-family paths stay in place, correct, for that
writer. `VerdictTransport.stepTransition` marks a derived verdict and is refused
at construction by `VerifyVerdictRecorded`, so a DERIVED value can never reach
the wire.

### Consequences

* Good, because the report works on all thirteen epochs already logged, and the
  governor stops hand-folding cost through SQL.
* Good, because it keeps `grid_trajectory` a leaf: the step-result key
  vocabulary is re-expressed, never imported from `grid_engine`.
* Bad, because the fold now knows the code asset's committee result-key schema,
  which the_grid does not own — a rename there silently empties the report until
  `StepResultKeys` follows it.
