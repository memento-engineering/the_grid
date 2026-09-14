---
status: accepted
date: 2026-09-14
decision-makers:
  - "nico"
consulted:
  - "governor"
informed: []
register:
  spec: 1
  slug: stage-2-starts-before-the-g1-cut
  surfaces:
    - "packages/grid_trajectory/lib/src/**"
    - "packages/grid_engine/lib/src/seeds/work_list.dart"
  obsoletes: []
  updates:
    - stage-2-requires-g1-cut
  obsoleted-by: null
  updated-by: []
  bead: tg-qmhd
  legacy-id: null
---

# Stage 2 starts before the G1 cut

## Context and Problem Statement

`stage-2-requires-g1-cut` ruled that trajectory Stage 2 — the pour and its successors, `molecule.poured` and
`step.superseded` replacing bead creates (`tg-ersi`, eight P1 chunks) — requires the completed G1
cut. The G1 cut (`lunar_station-bzt`) is itself gated on the §W2.5 soak certificate
(`lunar_station-2i9`). On 2026-09-14 the soak ran five live boots on lunar. Every blocker it
hit — the unbounded terminal-gate sweep (`tg-gxp6`), the abandoned-mint reservation leak
(`tg-b46m`), the p2-miss gauge against the open-retired shape (`tg-af76`), the external-close
obligation starving on retired heads (`tg-nxov`), the orphan gate after a route retry (`tg-ak7l`)
— was a defect in the interim, bead-backed lifecycle machinery that Stage 2 and Stage 3 exist to
delete. The ordering had become circular: the certificate was blocked by the code the
certificate exists to retire, and Stage 2 had not started a month after the migration began.

## Decision Outcome

Stage 2 may begin before the G1 cut lands. `tg-ersi.2` is unblocked from its epic container and
stamped; the remaining chunks follow in their own order. The G1 certificate keeps its meaning as
the shadow-window evidence for the dual-read cut and continues to be driven to PASS, but it no
longer gates the pour retirement. Ruled by Nico in his words: "whatever moves this shit forward."
The stopgaps landed during the soak stay, each with a removal bead blocked on the stage that
makes it removable (`tg-6u0f`, `tg-62mf`, `tg-lnyx`).

### Consequences

* Good, because the critical path stops waiting on defects in the machinery it retires, and the
  removal beads give every stopgap a defined end.
* Bad, because Stage 2 lands on a station whose G1 posture is not yet certified; the certificate
  and Stage 2 must not contradict each other, and the soak counters have to be re-baselined once
  the pour is gone.
