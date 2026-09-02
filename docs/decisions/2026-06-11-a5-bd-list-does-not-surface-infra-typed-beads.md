---
status: accepted
date: 2026-06-11
decision-makers: ["agent"]
consulted: []
informed: []
register:
  spec: 1
  slug: a5-bd-list-does-not-surface-infra-typed-beads
  surfaces:
    - "packages/**"
  obsoletes: []
  updates: []
  obsoleted-by: null
  updated-by: []
  bead: null
  legacy-id: "A5"
---
## A5 (2026-06-11) — `bd list` does not surface infra-typed beads

**Decision (observation + handling):** treat `bd list` as unsuitable for infra domains regardless of `--all`; domain sampling and the CLI-fallback snapshot read use `bd export --include-infra` exclusively (already ADR-0001's fallback read; this closes the loophole of ever composing snapshots from `bd list`).
**Why:** `bd list --json --all --type agent/rig/role` returned empty envelopes in HQ while `--type message/session/molecule` returned data; export is the documented carrier of infra records.
**Affects (if promoted):** ADR-0001 Decision 4 amendment wording; `BdCliService.list` documentation.
**Status:** promoted → ADR-0001 Decision 4 (2026-06-11).

