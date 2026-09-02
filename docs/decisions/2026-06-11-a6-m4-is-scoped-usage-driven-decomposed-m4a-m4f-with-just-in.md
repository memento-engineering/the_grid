---
status: accepted
date: 2026-06-11
decision-makers: ["agent"]
consulted: []
informed: []
register:
  spec: 1
  slug: a6-m4-is-scoped-usage-driven-decomposed-m4a-m4f-with-just-in
  surfaces:
    - "packages/**"
  obsoletes: []
  updates: []
  obsoleted-by: null
  updated-by: []
  bead: null
  legacy-id: "A6"
---
## A6 (2026-06-11) — M4 is scoped usage-driven, decomposed M4a–M4f with just-in-time ADRs, adopted via the fs ladder

**Decision:** M4 is scoped by the measured surface of the live city (audited 2026-06-11: 12 gc command families, 13 agent templates, 35 orders, 33 formulas, 2 active rigs — full inventory in `docs/M4-SCOPING.md`), decomposed into M4a config / M4b topology reconciler / M4c orders / M4d sling+hooks / M4e patrol / M4f cutover, each getting its ADR (0005–0010) just-in-time as predecessors land. M4 acceptance = cutover of one real rig, not feature parity. fs adoption is per-milestone: M1 observe, M2 shadow, M3 drive-one-rig (dogfood: the_grid rig), M4f replace.
**Why:** One up-front M4 ADR would speculate against a target M1–M3 (and the upstream RFC) will move; the usage inventory makes the checklist finite and testable.
**Affects (if promoted):** PDR §5 (M4 row → sub-milestones + ladder reference), `docs/M4-SCOPING.md` status.
**Status:** promoted → PDR §5 + docs/M4-SCOPING.md ratified (2026-06-11). · **The M4a–M4f ADR-number reservations (0005–0010) are re-pointed by the M4 tree-engine pivot (ADR-0007, Accepted 2026-06-24)** — the reducer/actuator decomposition those numbers indexed is superseded; the numbers were explicitly provisional ("just-in-time"). New sequence: 0007 = tree engine, 0008 = gc-TOML import, 0009 = topology tree, 0010 = convergence-as-subtree; **ADR-0005 retired**. `docs/M4-SCOPING.md` carries a superseded banner. (Numbers only — A6's *scoping* method, the usage inventory, and the cutover-is-acceptance rule stand.)

