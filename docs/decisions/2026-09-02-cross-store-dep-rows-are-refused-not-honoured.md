---
status: accepted
date: 2026-09-02
decision-makers: ["nico", "agent"]
consulted: []
informed: []
register:
  spec: 1
  slug: cross-store-dep-rows-are-refused-not-honoured
  surfaces:
    - "packages/grid_engine/lib/src/bridge/federated_snapshot_source.dart"
    - "packages/grid_engine/lib/src/bridge/block_guard.dart"
    - "packages/grid_sdk/lib/src/work/work_assembly.dart"
  obsoletes: []
  updates:
    - "a44-federated-work-sources-staleness-scope-member-removal-vs"
    - "a55-where-the-state-store-s-link-set-enters-the-pipeline-and"
  obsoleted-by: null
  updated-by: []
  bead: tg-mspw
  legacy-id: null
---

# Cross-store dependency rows are refused loudly, not honoured

## Context and Problem Statement

A44 built the federated union's cross-store block over raw `bd dep` rows, then
Nico reversed the WIRING the same day: "`bd doctor --fix` classifies raw
cross-store bead-id edges as orphaned dependencies and silently removes them —
that gotcha is unacceptable." tg-hof7 (closed 2026-08-01) then made link beads
in the station's own state store THE cross-store edge.

The implementation was never reconciled with either ruling. The union
classified ownership with `_sources.keys`, which holds substation NAMES, while
production ids carry PREFIXES — the axis ADR-0006 Decision 1 ratified as
ownership's primary one. Both endpoints of every real row resolved to null,
null != null is false, and no edge was ever constructed. The guard was
therefore INERT, not merely leaky — and the fail-closed LOUD path it documents
was unreachable, because it is reached only through an edge that is never
built. tg-y4fd's context names this as "an inert cross-store dependency guard".

## Considered Options

* **A — repair the classification so dep rows block.** Pass both identity
  axes and let a cross-store row hold work out.
* **B — block the path off, loudly.** Classify on both axes, but use the
  classification only to REFUSE: report the row and author no edge.
* **C — leave it inert.** No change.

## Decision Outcome

**Option B** (Nico, recorded in tg-mspw's `RE-SCOPED BY RULING` note: "the
dependency-row cross-store path is BLOCKED OFF for now, not made to work").

* Option A resurrects a mechanism tg-hof7 Q1 rejected, as a SECOND edge source
  beside link beads, and re-exposes the `bd doctor --fix` severance A44's
  reversal called unacceptable.
* Option C keeps a documented loudness guarantee that nothing backs.

Concretely: `FederatedSnapshotSource` receives each member's NAME and PREFIX
and classifies with `BeadOwnershipPredicate.ownedPrefixOf` over both — the
predicate ADR-0006 Decision 1 established, applied at a second call site
rather than re-implemented. A blocking dependency row whose endpoints do not
resolve to the same armed member is reported once through
`onUnresolvedExternalDep` — naming both ids, the armed roster, the `grid link`
verb and tg-xh5d — while authoring no blocking edge. Same-store rows keep bd's
native ready semantics. An OPEN `type=link` bead remains the ONLY cross-store
blocking edge.

### Consequences

* Good, because the loudness guarantee becomes real — an operator who writes a
  cross-store `bd dep add` learns immediately that it blocks nothing, and is
  told the verb that does.
* Good, because there is one blocking mechanism, one enforcement
  (`applyBlockGuard`), one edge source.
* Bad, because a cross-store dep row remains unenforced until tg-xh5d, which
  will amend tg-hof7's Q1 when it lands. Until then the operator must author a
  link bead.

### What this updates

* **A44** — its cross-store guard clause ("the guard only re-applies the block
  for a target in a DIFFERENT store") no longer describes the code: the union
  refuses such rows instead of blocking on them. A44's same-store skip stands.
* **A55** (Pending) — its parenthetical about the union's dep-row source is
  superseded on the dep-row half only. A55's load-bearing choices — the JOIN as
  the link seam, a malformed link BLOCKS fail-closed, the unwired seeded-type
  refusal — are untouched and this bead does not depend on A55's promotion.
* **Not amended, APPLIED:** ADR-0006 Decision 1 / A32 (ownership axis =
  issue-id prefix primary + optional `metadata.rig`). This entry extends that
  axis to federation membership classification, which had drifted to name-only.
