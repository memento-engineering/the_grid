---
status: accepted
date: 2026-09-03
decision-makers:
  - "the_grid specify seat (tg-1w3m)"
consulted:
  - "Nico Spencer"
informed: []
register:
  spec: 1
  slug: asset-definitions-are-const-collections-are-validated
  surfaces:
    - "packages/grid_sdk/lib/src/assets/**"
  obsoletes: []
  updates: []
  obsoleted-by: null
  updated-by: []
  bead: tg-dgxn
  legacy-id: null
---

# `GridAssetDefinition` is `const`; the asset collections are validated

## Context and Problem Statement

`tg-1w3m` asks for const-constructible values AND for duplicate `AssetKey` /
`AssetArtifactKey` refusal "loudly before a partial registry is exposed". A
Dart `const` constructor cannot run a duplicate scan — the scan is not a
constant expression, so a `const` invocation would fail to compile for VALID
input too. One of the two properties had to move.

## Decision Outcome

`GridAssetDefinition` stays `const`: that is the load-bearing half, because one
generated `static const` instance must inhabit both a `GridAssetRegistry` and a
`Substation`'s `assets` `List<Seed>` with no inflater between them.

The COLLECTIONS — `GridAssetPackDefinition` and `GridAssetRegistry` — are
built through validating factories that throw `ArgumentError` on a duplicate
`AssetKey`, a duplicate `AssetArtifactKey`, or an asset vended by a foreign
package, before any field is exposed. They hold `List.unmodifiable` /
`Map.unmodifiable` views, so they are deeply immutable but not `const`.

`GridAssetDefinition` is additionally declared `final class`, so a pack emits
INSTANCES and cannot declare a subclass-per-pack — making ADR-0008 Decision 2's
"consumers compose, never subclass" unrepresentable rather than guarded, per
`the_grid#adr-0013-state-holding-value-types` Decision 3.

### Consequences

* Good, because the loud refusal is guaranteed at the only construction path;
  there is no second, unchecked entry point to bypass it.
* Good, because the value a generator emits per asset stays `const`, so the
  compiler canonicalizes its identity.
* Bad, because a station cannot declare its whole registry as one `const`
  expression; it builds the registry at composition time.
