---
status: accepted
date: 2026-09-07
decision-makers:
  - "Nico Spencer"
consulted: []
informed: []
register:
  spec: 1
  slug: beads-dart-generated-json-and-published-names-stay-stable
  surfaces:
    - "packages/beads_dart/**"
    - "packages/grid_exploration/lib/**"
  obsoletes: []
  updates:
    - adr-0002-package-topology-and-domain-projections
  obsoleted-by: null
  updated-by: []
  bead: tg-dbd
  legacy-id: null
---

# `beads_dart` uses generated JSON and keeps published API names stable

## Context and Problem Statement

ADR-0002's 2026-07-05 package-topology amendment describes `beads_dart` as using “hand-coded value types (no freezed — the 2026-07-04 boundary ruling)” and tracks beads-native symbol renames as `tg-cxw`. The released tree contradicts both premises. As of 2026-09-07, `packages/beads_dart/lib` contains six `.freezed.dart` files and three `.g.dart` files, the package declares `freezed` and `json_serializable`, and published tags include `beads_dart-v0.2.0-rc.9` and later. External readers may already parse the generated JSON keys, while the Dart names covered by `tg-cxw` are already published exports.

## Decision Outcome

The ADR-0002 clause is amended to read:

> - **`grid_controller` → `beads_dart`** (D-A6/D-A7, rename applied 2026-07-03; amended by Nico's 2026-09-07 rulings): the framework-free beads client — Streams for observations, Futures for acts, and `freezed` value types with `json_serializable` codecs. The set of keys serialized by `json_serializable` is a released wire contract and changes only with a breaking package version; hand-coding is not required. Riverpod remains absent, bd compatibility follows D-BD1, and the published API names tracked by `tg-cxw` stay as named: `GridControllerRuntime` and `GridRuntimeFactory` remain exported from `packages/beads_dart/lib/beads_dart.dart` lines 88–89, while `GridControllerPlugin` remains exported from `packages/grid_exploration/lib/grid_exploration.dart` line 13.

Nico's 2026-09-07 serialization ruling reverses the 2026-07-04 boundary ruling: `beads_dart` uses `freezed` plus `json_serializable`, and hand-coding its value types is not required.

The set of keys serialized by `json_serializable` is a released wire contract and changes only with a breaking package version.

Nico's separate 2026-09-07 API ruling closes `tg-cxw` without a rename. Both published halves remain as named: `GridControllerRuntime` and `GridRuntimeFactory` are exported at `packages/beads_dart/lib/beads_dart.dart` lines 88–89, and `GridControllerPlugin` is exported at `packages/grid_exploration/lib/grid_exploration.dart` line 13.

### Consequences

* Good, because ADR alignment now grades `beads_dart` changes against the released implementation instead of a superseded hand-coding rule.
* Good, because external readers can rely on the generated serialized key set and existing Dart exports until a breaking package version explicitly migrates them.
* Bad, because a source-compatible model or annotation edit that changes a generated key now requires a breaking version and migration treatment.
* Bad, because the legacy `GridController*` names remain in the public API despite the package rename.
