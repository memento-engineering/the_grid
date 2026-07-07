# grid_sdk

The **public authoring surface of the grid** — "the grid" as concrete code
(GLOSSARY R9). This is the package a station author lists in their `pubspec.yaml`.
It sits **over** the private `grid_engine`: consumers **compose** the SDK's
composition types and drive them with `runGrid`; they **never import
`grid_engine`** or subclass its sealed Seeds (ADR-0008 Decision 2 — *compose,
never subclass*).

## Code as config

Just as the org went Dart-first before TOML, the grid goes **code-first before
configuration**. A station is not *configured* by a value the framework
interprets — it is **built**, as a tree, in Dart, by its author. Plain language
features *are* the configuration language:

- an `if (kDebug)` mounts a substation,
- a `for` fans out the substations,
- a watched value re-composes the tree.

`GridConfiguration` stays thin and subordinate — plausibly nothing more than the
result of TOML loading, provided *into* the tree like any other value. **The tree
IS the configuration.**

```dart
// The shape (pseudo — the types land in Track B):
RawAssetGrid(
  root: '/path/to/space_station',
  assets: [ /* config providers, federation discovery, harnesses */ ],
  // → Station(name, assets: [ ... → Substations([ Substation(name, root, assets) ]) ])
);
```

The full model — the canonical tree, `runGrid` / `GridDelegate`, the asset
scopes, the closed questions — lives in
**[`docs/SCRATCH-station-config-model.md`](../../docs/SCRATCH-station-config-model.md)**
(the ratified v3 model). The build breakdown is
**[`docs/GRID-SDK-BUILD-ORDER.md`](../../docs/GRID-SDK-BUILD-ORDER.md)**.

## Status — Track A (skeleton)

This commit **births the package**: the workspace member, the house-set pubspec
(freezed always — the tg-irs boundary), the lints, and the barrel with a
**structured-but-empty export skeleton**. No composition types yet — those are
Track B (`tg-vrz`). The barrel's commented sections map the surface the later
tracks fill in:

- **Track B** — the composition Seeds (`RawAssetGrid` / `Station` / `Substations`
  / `Substation`), pure and offline.
- **Track C** — `runGrid` + `GridDelegate` + the thin `GridConfiguration`.

## House conventions

Dart `^3.11`, pub workspace + melos, `publish_to: none`, `resolution: workspace`.
Lints are inherited from the workspace-root `analysis_options.yaml`
(strict-casts / -inference / -raw-types + the shared house rules). **freezed**
sealed unions + `json_serializable` for value types; **Fakes, not mocks**; pure
logic tested before IO.
