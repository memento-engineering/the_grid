---
status: accepted
date: 2026-09-03
decision-makers: [governor, agent]
consulted: []
informed: [nico]
register:
  spec: 1
  slug: trajectory-guard-pins-use-the-median-of-five-probes
  surfaces:
    - ".github/workflows/ci.yml"
    - "packages/grid_trajectory/test/**"
  obsoletes: []
  updates: ["trajectory-guard-pins-are-runner-relative"]
  obsoleted-by: null
  updated-by: []
  bead: tg-2zao
  legacy-id: null
---

# The trajectory guard calibrates from the median of five interleaved probes, banded at 0.60x drain and 1.60x tail

## Context and Problem Statement

`the_grid#trajectory-guard-pins-are-runner-relative` replaced the W6 guard's
absolute wall-clock pins with a calibrated bound: one bare INSERT + SELECT
round trip interleaved after every Stage-1 append, the pooled median for the
drain floor, the pooled p99 for the fold tail. On the shared runner that bound
still ejected good changes. PR #292's own run 33777666093 measured 106.65
appends/s against a 119.27/s calibrated bound, and PR #293's run 33778914681
measured 109.51 against 120.60 — twice, rerun included. A single interleaved
probe inherits the runner's minute-to-minute swing, so a pooled percentile over
one unlucky window moves the bound as far as it moves the measurement, and
every the_grid pull request queued behind it.

## Decision Outcome

The calibration is sampled and aggregated differently, and the bands gain an
explicit tolerance. The probe operation is unchanged — the same plain
single-row INSERT + SELECT against the same dolt the guarded path uses.

FIVE interleaved probes per run, each a loop of 104 back-to-back round trips:
one before the storm, three between its quarters, one after. Five times 104 is
the 520 trips the per-append calibration already spent, so the sampling costs
the hermetic database nothing new.

The MEDIAN of the five is the aggregate on BOTH sides. Each probe contributes
its central trip and its slowest trip; the machine-speed unit is the median of
the five central trips and the machine-tail unit is the median of the five
slowest trips. The pooled-percentile leg of the updated entry is retired: with
five samples a single stalled window is outvoted rather than promoted into the
bound. The tail is still sampled as a TAIL, because it must be — on run
33767416244 the fold p99 was 297.775 ms against a ~2.1 ms median round trip, a
142x ratio no fixed constant spanning a developer machine and a shared runner
can hold, while the same runner's baseline tail tracked it and the tail leg
passed on the very run whose drain leg failed.

The bands are tolerances on the CALIBRATED BOUND, not on the raw probe rate.
The guarded drain must clear 0.60 times the calibrated throughput bound, and
the fold tail must stay under 1.60 times the calibrated latency bound. The
receipts that chose them are measured-against-bound ratios: 22.5 against 28
(0.80), 106.65 against 119.27 (0.89), and 297.8 ms against 250 ms (1.19). Both
bands cover every swing observed on 2026-09-03 with headroom, and a genuine 2x
slowdown of the fold design still fails. Read against the raw probe rate
instead, a 0.60 floor would have demanded 286 appends/s of a runner that
delivered 106.65 — the failure this entry exists to end.

The measured cost ratios of the updated entry, 4.0 for the mean and 5.0 for
the tail, are therefore carried UNCHANGED. That entry's Consequences make them
immovable without remeasurement, and the probe operation they describe did not
change; only its schedule and aggregation did. Effective ceilings become 6.67x
a bare round trip for the mean and 8.0x the machine tail for the p99.

What the updated entry KEEPS, in force and unamended: interleaving is still
required, so scheduler stalls land on both distributions and a pre-run-only or
post-run-only probe still does not calibrate the same tail; the tight absolute
acceptance pins, drain above 28.0 appends/s and p99 below 250 ms, still apply
on a developer machine where `TRAJ_GUARD_SHARED_RUNNER` is unset; an unknown
posture or a non-positive calibration unit still refuses loudly; and
`the_grid#stage0-guards-gate-prs` is unamended — both assertions STAY in the
pull-request and merge-group job, nothing is tagged out of it, and the
nightly-only option is withdrawn.

### Consequences

* Good, because one unlucky scheduling window can no longer set the bound: it
  is outvoted by four other probes on both the speed and the tail unit.
* Good, because the calibration costs the same 520 round trips the per-append
  probe already spent, in five bursts rather than 520 interruptions.
* Bad, because the effective mean ceiling widens from 4.0x to 6.67x a bare
  round trip, so a fold regression below 1.7x now passes on a shared runner;
  the developer-machine absolutes remain the tight gate.
* Bad, because the aggregate is defined at exactly five probes and refuses any
  other count, so changing the interleave points is a deliberate edit to
  `BaselineCalibration` rather than a free parameter.
* Constraint: ten consecutive green runs of the guard job on `main` are the
  acceptance evidence for these bands; a failure inside that window reopens the
  numbers rather than the design.
