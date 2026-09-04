---
status: accepted
date: 2026-09-03
decision-makers:
  - "Nico Spencer"
consulted: []
informed: []
register:
  spec: 1
  slug: grid-block-packages-publish-dart-asset-definitions
  surfaces:
    - "packages/grid_sdk/lib/src/assets/**"
  obsoletes: []
  updates:
    - "adr-0008-authoring-sdk-and-reentrant-engine"
  obsoleted-by: null
  updated-by: []
  bead: tg-nk0n
  legacy-id: null
---

# A package carrying a `grid:` block publishes generated Dart asset definitions

## Context and Problem Statement

ADR-0008 Decision 2's 2026-06-28 amendment adopted the Dart "Packaged AI
Assets" format and, in doing so, blessed "**AI-only packages with no Dart
code**" as participating packs. The station-generated asset registry needs a
compiled, typed contract: a pack whose assets exist only as loose files cannot
be keyed, indexed, or mounted without a parallel runtime representation beside
`List<Seed>`. Which packages participate had to be settled before the contract
could be written.

## Decision Outcome

A package that carries a top-level `grid:` block participates in the compiled
registry and therefore publishes generated Dart definitions —
`GridAssetDefinition` values vended through a `GridAssetPackDefinition`. A
package without a `grid:` block participates in neither the registry nor this
contract.

This updates ONLY ADR-0008 Decision 2's clause blessing AI-only, no-Dart
packages as participating packs. The rest of Decision 2 stands unchanged: the
public SDK surface, the private `grid_engine`, the `*_grid_assets` pack
pattern, and "consumers compose, never subclass".

### Consequences

* Good, because identity, duplication, and composition are checked by the Dart
  type system and at registry construction rather than by a runtime file scan.
* Good, because `grid_sdk` can own the contract with no consumer importing
  `power_station` to understand an asset registry.
* Bad, because a pure-file pack must gain a `grid:` block and a generated Dart
  library before it can join a station's registry.
