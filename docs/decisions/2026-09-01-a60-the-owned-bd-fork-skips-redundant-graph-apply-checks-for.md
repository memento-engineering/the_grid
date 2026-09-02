---
status: accepted
date: 2026-09-01
decision-makers: ["agent"]
consulted: []
informed: []
register:
  spec: 1
  slug: a60-the-owned-bd-fork-skips-redundant-graph-apply-checks-for
  surfaces:
    - "packages/**"
  obsoletes: []
  updates: []
  obsoleted-by: null
  updated-by: []
  bead: null
  legacy-id: "A60"
---
## A60 (2026-09-01) — the owned bd fork skips redundant graph-apply checks for plan-local parents (tg-igv2)

**Decision (AI; pending Nico promotion).** The owned `nicholasspencer/beads` fork selects `grid-v1.0.5-graph-apply-parent-cycle-skip.1`, based on `f9fe4ef2a6d3d90b52f1b62df15a5b2c0833c82b`, for the surgical graph-apply parent dependency patch. A `ParentKey` dependency uses `DependencyAddOptions{SkipCycleCheck:true}` because `validateGraphApplyLocalCycles` already validates the plan-local edge; a `ParentID` dependency retains the storage cycle check.

**Compatibility policy.** D-BD1 remains “No pin. Two compatibility rails”: `packages/beads_dart/bd_compatibility.yaml` keeps floor `v1.0.5`, the main and release rails are unchanged, and the fork ref is a named local exception only. The resolved commit SHA, executable, envelope environment, exact commands, and shape findings are recorded in `fixtures/upstream/2026-09-01-bd-grid-v1.0.5-graph-apply-parent-cycle-skip.1/README.md`.

**Shape finding.** Envelope `schema_version` remains 1, no migration is added, and the patch changes no JSON model. The complete fixture set is captured wholesale and prior fixture directories remain untouched.

**Not this.** No timeout increase, dependency-table pruning, terminal-bead deletion, cross-process lock, admission gate, upstream issue, or upstream pull request is introduced.

**Status:** Pending — Nico promotes or rejects.
