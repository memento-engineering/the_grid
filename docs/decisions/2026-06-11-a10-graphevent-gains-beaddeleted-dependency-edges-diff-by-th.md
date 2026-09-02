---
status: accepted
date: 2026-06-11
decision-makers: ["agent"]
consulted: []
informed: []
register:
  spec: 1
  slug: a10-graphevent-gains-beaddeleted-dependency-edges-diff-by-th
  surfaces:
    - "packages/**"
  obsoletes: []
  updates: []
  obsoleted-by: null
  updated-by: []
  bead: null
  legacy-id: "A10"
---
## A10 (2026-06-11) — `GraphEvent` gains `BeadDeleted`; dependency edges diff by the (issue,dependsOn,type) triple

**Decision:** Add a `BeadDeleted(Bead)` variant to the ratified `GraphEvent` union, and key dependency add/remove detection by the triple `(issueId, dependsOnId, type)` (`BeadDependency.edgeKey`).
**Why:** (a) ADR-0001 Decision 5 enumerated the event set without a delete variant, but a hard `bd delete` removes a bead from the snapshot — silently dropping it would violate the "diff is authoritative, no missed change class" invariant (PDR Risk row). `BeadDeleted` keeps the diff complete and the union exhaustively switchable. (b) The upstream `dependencies` PK is the *pair* `(issue_id, depends_on_id)`, but keying the diff by the full triple makes a dependency **type change** surface as remove+add (complete) rather than being missed; the known small gap is that a metadata-only edit on an unchanged triple is not surfaced (no `DependencyUpdated` event in M1 — low value, documented).
**Affects (if promoted):** ADR-0001 Decision 5 event list (+`BeadDeleted`). Code: `packages/grid_controller/lib/src/diff/graph_event.dart`, `diff_snapshots.dart`, `models/bead_dependency.dart`.
**Status:** pending.

