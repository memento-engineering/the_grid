---
status: accepted
date: 2026-09-02
decision-makers: ["agent"]
consulted: []
informed: ["nico"]
register:
  spec: 1
  slug: dry-bd-seam-mints-under-the-owning-prefix
  surfaces:
    - "packages/grid_sdk/lib/src/work/work_assembly.dart"
    - "packages/grid_sdk/test/dry_bd_seam_ownership_test.dart"
  obsoletes: []
  updates: []
  obsoleted-by: null
  updated-by: []
  bead: tg-czsf
  legacy-id: null
---

# The dry bd seam mints under the owning partition's prefix, per seam

## Context and Problem Statement

`NoOpBdRunner` returned the fixed literal `dry-session` for every dry `create`.
That id carries no owned prefix, so the first chokepoint write that ASSERTED it
— `_assertOwned` on a `close`/`update`, and the molecule pour's parent check on
the session bead — refused fail-closed and printed an ADR-0006 violation ahead
of a new station's banner. ADR-0006 Decision 1 holds that a session bead's id
prefix is owned from birth; live that is true because `bd create` returns a
prefixed id, and the inert seam had no such relationship to any partition.

## Considered Options

* Exempt the dry writer from the ownership check.
* Mint every dry id under the STATE partition's prefix.
* Mint each dry id under the prefix of the seam's OWN partition.

## Decision Outcome

The third. The reporter ruled the exemption out — the check is the thing you
most want unchanged between dry and live — and that ruling stands: ADR-0006
Decision 2's "before **every** `create` / `update --metadata` / `close` /
`delete`, the chokepoint asserts the target bead's rig is in the shared
allow-set" applies to the dry posture verbatim. `NoOpBdRunner` takes a required
`substation` and mints `<substation>-dry-<n>`. The state chokepoint's seam is
given `stateSubstation` (the state store's `dolt_database`, per A37's split
store); each per-substation work seam is given that substation's own `prefix`,
because the predicate asserting those ids is
`BeadOwnershipPredicate({spec.name, spec.prefix})`, not the state allow-set —
one rule ("a seam mints under the owner that will assert it"), applied per seam.

This does not add a write discipline. `admission-authority-boundary` governs
`packages/grid_sdk/lib/src/work/**` and rules that "durable state changes ride a
fenced transition service rather than being minted independently by branches";
`NoOpBdRunner` is not such a mint site. It is a transport-layer `BdRunner` fake
that issues no `bd`, writes no durable state, is reachable only under
`dryRun: true`, and mints nothing on its own initiative — it echoes an id back
to the one chokepoint that called it. When the converging beads (tg-nidl and
its siblings) route the chokepoint's durable writes through the fenced
transition service, this seam's id shape follows that chokepoint unchanged; it
is not a second discipline to migrate.

Synthesizing `applyGraph`'s `data.ids` envelope is NOT part of this: a dry
molecule pour still fails as a `BdParseException`, loudly and never as an
ownership refusal. That gap is left named, not fixed.

## Review log

* 2026-09-02 — authored by **agent** (specify stage of tg-czsf); the
  no-exemption clause is the reporter's ruling on the filed issue (gh-235).
