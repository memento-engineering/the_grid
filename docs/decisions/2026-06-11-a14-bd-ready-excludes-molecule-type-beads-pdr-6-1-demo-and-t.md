---
status: accepted
date: 2026-06-11
decision-makers: ["agent"]
consulted: []
informed: []
register:
  spec: 1
  slug: a14-bd-ready-excludes-molecule-type-beads-pdr-6-1-demo-and-t
  surfaces:
    - "packages/**"
  obsoletes: []
  updates: []
  obsoleted-by: null
  updated-by: []
  bead: null
  legacy-id: "A14"
---
## A14 (2026-06-11) — `bd ready` excludes molecule-type beads; PDR §6.1 demo and the ≤500ms target

**Decision:** the two-terminal acceptance demo (PDR §6.1) asserts `ReadySetChanged` against a **task/step** create, not a `molecule` create; and the ≤500ms latency budget is understood as the **pooled-SQL** path's target, with the bd-CLI fallback measured separately (~0.6–0.8s, embedded mode).
**Why:** observed live (bd 1.0.5, hermetic `bd init`): `bd ready` excludes `molecule`-type beads — molecules are containers; only their claimable steps enter the ready set. So `bd create -t molecule` fires `BeadCreated` only, with **no** `ReadySetChanged` (the M1 live demo and the integration test both confirm this). PDR §6.1's literal "molecule → BeadCreated + ReadySetChanged" is therefore inaccurate. Separately, the embedded-mode CLI read path is bd-spawn-dominated (~70–140ms × 2 per refresh + 150ms quiet + watcher latency), consistently ~0.6–0.8s — within the integration suite's generous 2s budget but above §6.1's 500ms, which the SQL path (≈1–5ms reads) targets. Latency is printed per event so the claim stays quantitative either way.
**Affects (if promoted):** PDR §6.1 (reword the demo to a task/step; note the SQL-vs-CLI latency split + retire the molecule→ready assumption). Code: `packages/grid_controller/test/integration/reactive_lifecycle_test.dart` already uses a task for the ready-set assertion.
**Status:** pending.

