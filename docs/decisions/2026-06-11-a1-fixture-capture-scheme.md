---
status: accepted
date: 2026-06-11
decision-makers: ["agent"]
consulted: []
informed: []
register:
  spec: 1
  slug: a1-fixture-capture-scheme
  surfaces:
    - "packages/**"
  obsoletes: []
  updates: []
  obsoleted-by: null
  updated-by: []
  bead: null
  legacy-id: "A1"
---
## A1 (2026-06-11) — Fixture capture scheme

**Decision:** Pinned upstream fixtures live at `fixtures/upstream/<date>-bd-<version>/`, captured with `BD_JSON_ENVELOPE=1`. the_grid contributes the empty-workspace cases (`tg-list-all-empty`, `tg-ready-empty`) plus `statuses`/`types` (the 13 custom types); the city HQ contributes per-domain samples extracted from `bd export --include-infra` JSONL (not from `bd list`) and a 25-line raw export sample; one error fixture captures the failure shape.
**Why:** PDR §6.7 and ADR-0001 Decision 7 require version-pinned fixtures; the HQ export is 24MB so wholesale check-in is wrong; per-domain extraction keeps fixtures small and representative.
**Affects:** test layout in `grid_controller`; the porting skill's re-capture procedure.
**Status:** promoted → ADR-0001 Decision 7 (2026-06-11).

