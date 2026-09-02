---
status: accepted
date: 2026-06-11
decision-makers: ["agent"]
consulted: []
informed: []
register:
  spec: 1
  slug: a7-coexistence-partition-rule
  surfaces:
    - "packages/**"
  obsoletes: []
  updates: []
  obsoleted-by: null
  updated-by: []
  bead: null
  legacy-id: "A7"
---
## A7 (2026-06-11) — Coexistence partition rule

**Decision:** While gc and the_grid both run, the_grid owns a bead/rig set **disjoint** from gc's reconciler — partitioned by rig and/or ownership marker; M2 shadow mode is strictly read-only.
**Why:** gc's convergence handler assumes a single writer per bead (ADR-0003 invariant 7); two reconcilers on one convergence bead corrupts state for both.
**Affects (if promoted):** ADR-0003 (operating-mode section), M2/M3 acceptance criteria, M4-SCOPING.
**Status:** promoted → ADR-0003 Decision 6 (2026-06-11).

