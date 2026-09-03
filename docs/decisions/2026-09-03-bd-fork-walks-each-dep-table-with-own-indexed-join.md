---
status: accepted
date: 2026-09-03
decision-makers: [agent]
consulted: []
informed: []
register:
  spec: 1
  slug: bd-fork-walks-each-dep-table-with-own-indexed-join
  surfaces:
    - "packages/beads_dart/bd_compatibility.yaml"
    - "packages/beads_dart/test/tool/compatibility_workflows_test.dart"
    - "fixtures/upstream/2026-09-03-bd-grid-head-a45199a-dep-cycle-indexed-recursion.1/**"
  obsoletes: []
  updates:
    - a60-the-owned-bd-fork-skips-redundant-graph-apply-checks-for
    - the-pour-gets-its-own-bd-deadline
    - day-one-window-names-the-tag-the-release-rail-waits-for
  obsoleted-by: null
  updated-by: []
  bead: tg-4gaz
  legacy-id: null
---

# The bd fork walks each dependency table with its own indexed join

## Context and Problem Statement

The fleet runs the Homebrew HEAD lineage at
`a45199a546f959044426b98716975c70b7c77a16`, while the earlier owned-fork patch
was based on bd 1.0.5 at `f9fe4ef2a6d3d90b52f1b62df15a5b2c0833c82b`.
On the fleet lineage, dependency cycle detection joined every recursive hop
against a derived union of `dependencies` and `wisp_dependencies`. Dolt could
not use an index on that derived table and re-materialized the full edge set on
each hop. The same defect also existed in the parent-child ancestry walk, which
runs twice for every blocking-edge insert.

At this lineage the previously named `wispCycleReachabilityQuery` site no
longer exists, and the domain/db `HasCycle` site delegates to
`issueops.WouldCreateSchedulingCycleInTx`. `isAncestorInTx` is a fourth site
with the same derived-union shape. Building from current upstream main would
also add unrelated store migrations beyond the commit already used by the
fleet.

## Considered Options

* Patch the earlier bd 1.0.5 fork lineage, which no fleet binary executes.
* Patch current upstream main, accepting unrelated migrations beyond the
  fleet's store lineage.
* Patch the exact commit used by the fleet and keep the fork ref a named local
  compatibility exception.

## Decision Outcome

Select `grid-head-a45199a-dep-cycle-indexed-recursion.1`, based on
`a45199a546f959044426b98716975c70b7c77a16`. Both cycle and ancestry recursive
CTEs use one recursive member per dependency table, with each member joining
its table directly on `issue_id`. No recursive hop joins a derived dependency
union.

`applyGraph` declares both of its dependency inserts cycle-validated. Its
whole-graph preflights and final `CycleThroughEdges` walk are the cycle
authority, and they execute in the same transaction, so a final rejection
rolls back the complete graph. Hierarchy validation remains enabled per edge
because there is no whole-graph hierarchy preflight.

The pour's client deadline, ready-work semantics, wisp table routing, and
`floor: v1.0.5` remain unchanged. The fork ref is a local exception; the main
and release compatibility rails remain in force. No issue, branch, tag, or
pull request is filed or pushed to `gastownhall/beads`. Installing the rebuilt
binary on the fleet remains Nico's step.

### Consequences

* Good, because deep cycle and ancestry walks use the indexed `issue_id` path
  instead of rescanning all stored blocking rows at every recursion hop.
* Good, because graph pours perform the whole-graph cycle check once while
  retaining per-edge hierarchy protection.
* Good, because the rebuilt binary stays schema-identical to the fleet's
  already-migrated stores and changes no JSON model or envelope version.
* Bad, because this deliberately departs from the bd 1.0.5 fork lineage named
  by the earlier timeout and redundant-parent-check decisions; both records
  must be read with this update.
* Bad, because publishing the local fork ref and installing its binary remain
  explicit human operations.
