---
status: accepted
date: 2026-09-05
decision-makers: [nico, governor]
consulted: [external-architecture-auditor]
informed: []
register:
  spec: 1
  slug: wave-2-flip-scope-soak-and-kill-date
  surfaces:
    - "docs/design/trajectory/cut-wiring.md"
    - "docs/design/trajectory/trajectory-schema.md"
  obsoletes: []
  updates: [trajectory-ledger-split]
  obsoleted-by: null
  updated-by: [wave-2-entry-criteria-rulings]
  bead: tg-whf6
  legacy-id: null
---

# The wave-2 flip is narrow, soaks on target seats, keeps bd as a terminal input, and dies on 2026-10-02 without a certified soak

## Context and Problem Statement

The trajectories migration was named the top architectural priority on
2026-09-05 (the independent grid stack audit, F6/F7, and the owner
independently). The cut-wiring design (r5) parks the flip in a gated appendix
marked design-incomplete, behind three gate items. The wave-2 entry worksheet
(lunar_station `docs/trajectory-spike/07-wave2-entry-worksheet.md`) verified
every entry criterion against `main @ 3617066` and measured the facts the
rulings rest on:

* the dual-read soak is not running: `GRID_DUAL_READ` defaults to `off` and is
  exported nowhere; observe ran on boot epochs 5–10 (2026-09-01) only, and
  `primary` has never booted, so gate item 1 is not accruing;
* 51% of `step.transition` records (`complete` + `failed`, 9,640 of 18,796) sit
  on the KEPT-writes collision sites in `capability_host.dart`, where retiring
  the write also retires the restart count, the cooldown, and the `grid.result.*`
  keys the rework cap reads;
* 267 of 521 sessions are closed in bd with no `attempt.terminal` in the log,
  with zero harness drops — the legacy close paths never emit.

The station cannot drive this work on itself: every stage cut is a quiesced
boundary (schema §9) and the appendix is a design round. The owner took the
station down for 1:1 work and asked for the rulings to be recorded.

## Decision Outcome

Four rulings, numbered as in the worksheet's docket.

**Q1 — the soak re-arms on target seats after the comparator fix.** Boot with
`GRID_DUAL_READ=observe`, then `primary`, on the lenny and butane seats only;
never on the_grid. The comparator's cause labelling (tg-ilug) is fixed first.
The evidence is the `dual-read-round-summary` notes in the log, and the cut
signal is the schema's own: the legacy fallback count reaching zero, with zero
unexplained divergences, across three clean boots that between them cover the
named shapes (rework, void, escalation, gate-park and re-arm, one deliberate
bounce). The shapes may be driven deliberately; the soak is a checklist, not a
wait.

**Q5 — wave 2 is narrow.** The flip retires only the `running`, `pending`, and
`gated` step writes. The `complete` and `failed` writes stay KEPT until Stage
2/4, so the restart count, the cooldown, and the result keys keep their bd
carrier. This is an exception to §9's cuts-whole rule and is recorded as one;
the KEPT table names exactly this set.

**Q6 — bd remains an input to terminal truth under cut.** The terminal append
becomes acked, and a tick obligation reconciles "session bead closed, P1 open"
into an `attempt.terminal` with `provenance=inferred`. The reap and the
worktree barrier read P1 only once that input is complete.

**Q12 — the kill date is 2026-10-02.** It is a deadline on the whole, not a
soak length: the emitter fixes and the r6 design may land early, and the soak
ends the moment its count criterion is met. If that date passes without a
certified soak, wave 2 re-scopes to keeping the bd ledger with retention (the
audit's F6 fallback) and the comparator is deleted rather than maintained.

### Consequences

* Good, because the narrow set is the one the evidence can certify, and it
  makes wave 2 a read-side change plus three write sites.
* Good, because a dated fallback ends the open-ended shadow window that both
  the audit and the owner named as the failure mode.
* Bad, because narrow wins only about half of the step-write churn; the
  `complete`/`failed` half waits for Stage 2/4.
* Bad, because keeping bd as a terminal input means one more bd read on the
  tick and a `provenance=inferred` class the fold must carry honestly.

### Confirmation

A boot summary with `mode=primary`, `fallbacks=0`, `unexplained_divergences=0`
on three consecutive boots, read from the trajectory log, is the soak
certificate. The r6 design must name the narrow set in its KEPT table and cite
this entry.
