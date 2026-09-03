---
status: accepted
date: 2026-09-03
decision-makers: [agent]
consulted: []
informed: [nico]
register:
  spec: 1
  slug: trajectory-guard-pins-are-runner-relative
  surfaces:
    - ".github/workflows/ci.yml"
    - "packages/grid_trajectory/test/**"
  obsoletes: []
  updates: []
  obsoleted-by: null
  updated-by: []
  bead: tg-1pzo
  legacy-id: null
---

# The trajectory guard's wall-clock pins are runner-relative on shared CI

## Context and Problem Statement

The Stage-1 trajectory guard asserts W6's sustained drain rate and p99
writer-loop transaction time over a dolt-backed integration path. Fixed
wall-clock thresholds made those assertions measure shared GitHub runner load
as much as fold behavior. On 2026-09-03, PR #285 first failed W6 at 22.5
appends/s and then passed and merged. PR #290 changed grid_runtime process
supervision rather than grid_trajectory, but run 33767416244 failed the fold
pin at 297.775 ms, and its failed-job rerun then failed W6 at 26.658 appends/s.
Main's run 33766648792 at 14:26Z passed both against the same code. Each
failure removed a good change from the merge queue and required a manual
rerun and re-arm.

The guard remains an acceptance criterion. The problem is to preserve its
ability to detect fold regressions without treating transient host speed as a
regression in the change under test.

## Considered Options

* Calibrate in-process against a bare database round trip and assert the fold
  cost relative to that same-runner unit.
* Keep an absolute band supplied by the CI workflow and periodically retune it
  from recent main runs.
* Tag the timing assertions `perf`, exclude them from PR and merge-group runs,
  and run them nightly.

## Decision Outcome

Shared CI uses the first option. The guard interleaves one bare INSERT + SELECT
round trip after every Stage-1 append on the same dolt connection. The median
baseline round trip defines the machine-speed unit for the drain floor, and
the baseline p99 defines the machine-tail unit for the fold p99 ceiling. The
fold must sustain at least one quarter of the baseline operation rate and its
p99 must remain below five times the baseline tail.

Six measurements against dolt 2.2.2, including one run 1.8 times slower than
the others, placed mean append cost at 1.26–1.55 times the baseline median and
append p99 at 1.18–1.70 times the baseline p99. The chosen ceilings of 4.0 and
5.0 leave runner-noise headroom while still rejecting an order-of-magnitude
fold regression. Interleaving is required so scheduler stalls affect both
distributions; a pre- or post-run-only probe does not calibrate the same tail.

The CI workflow identifies its host as shared. With that posture, neither W6
assertion uses a fixed wall-clock threshold. On a developer machine the
posture is unset and the tight absolute acceptance pins remain in force:
drain greater than 28.0 appends/s and p99 below 250 ms. An unknown posture or
a non-positive calibration unit refuses loudly.

`the_grid#stage0-guards-gate-prs` is unchanged and is not amended. Every
trajectory guard still runs on every PR and merge group, missing dolt still
fails closed, and no assertion is skipped or moved to a nightly workflow.

### Consequences

* Good: shared-runner speed changes scale both W6 timing budgets without
  clearing a real fold-cost regression.
* Good: developer runs retain the original absolute acceptance criteria.
* Cost: the guard performs one extra INSERT + SELECT pair per append and keeps
  a scratch calibration table in its hermetic trajectory database.
* Constraint: the relative ceilings describe fold cost against the current
  dolt round-trip shape; material changes to that baseline operation require
  remeasurement before changing either ratio.

## Review log

* 2026-09-03 — authored by **agent**; recorded accepted and binding on write.
