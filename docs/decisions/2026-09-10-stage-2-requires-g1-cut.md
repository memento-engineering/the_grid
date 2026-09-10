---
status: accepted
date: 2026-09-10
decision-makers: ["Codex (specify architect)"]
consulted: []
informed: []
register:
  spec: 1
  slug: stage-2-requires-g1-cut
  surfaces:
    - "docs/design/trajectory/stage2-wiring.md"
  obsoletes: []
  updates: []
  obsoleted-by: null
  updated-by: []
  bead: tg-yxjq
  legacy-id: null
---

# Stage 2 requires the completed G1 cut

## Context and Problem Statement

`trajectory-schema.md` §9 orders the coherent migration groups G1 and then G2.
G2 replaces step and molecule bead creates with `molecule.poured` and
`step.superseded`, then retires and reaps those graph bead carriers at a
quiesced boundary. G1 shadow still uses those carriers as live authority and
allows counted legacy fallback, so starting G2 during that window would make
the authority boundary ambiguous and invalidate G2's projection-only
frontier/status proof.

The wave-2 appendix in `cut-wiring.md` is explicitly unratified and
design-incomplete, so its sketches do not decide this gate. The later accepted
entries `the_grid#wave-2-flip-scope-soak-and-kill-date` and
`the_grid#wave-2-entry-criteria-rulings` do decide what constitutes a completed
G1 cut: one `TrajectoryDiscipline.cut` resolution implies `dualRead: primary`
on both axes and `mode: required`, and the certificate requires three clean
boots with zero legacy fallback and zero unexplained divergence.

## Considered Options

* Require the completed G1 cut before any G2 work or non-off G2 posture.
* Permit G2 shadow while G1 remains in shadow.

## Decision Outcome

Require the completed G1 cut before Stage 2 begins. No G2 implementation bead
mounts and no G2 posture becomes non-off until G1 resolves to cut with
`mode: required`, primary reads on both axes, three clean boots, zero legacy
fallback, and zero unexplained divergence. A missing or inconsistent
certificate refuses boot by name; it never enables G2 partially.

This entry cites but does not update or obsolete
`the_grid#wave-2-flip-scope-soak-and-kill-date` or
`the_grid#wave-2-entry-criteria-rulings`.

### Consequences

* Good, because G1 and G2 cross one authority boundary at a time and G2's
  projection-only proof cannot erase an oracle G1 still needs.
* Bad, because all Stage 2 implementation waits for the completed G1
  certificate, even where an individual G2 shadow emitter could otherwise be
  built earlier.
