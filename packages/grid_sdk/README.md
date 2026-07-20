# grid_sdk

The **public authoring surface of the grid** — "the grid" as concrete code
(GLOSSARY R9). This is the package a station author lists in their `pubspec.yaml`.
It sits **over** the private `grid_engine`: consumers **compose** the SDK's
composition types and drive them with `runGrid`; they **never import
`grid_engine`** or subclass its sealed Seeds (ADR-0008 Decision 2 — *compose,
never subclass*). One import authors a station: the barrel re-exports the
`genesis_tree` vocabulary (`Seed` / `StatelessSeed` / `Nest` / `TreeContext` /
keys), the `state_notifier` types a `GridDelegate` IS, and the narrow **named**
engine seam a *runner* needs when assembling (`SessionResolver`,
`CapabilityRegistry`, `Circuit`, the wedge-state types) — never `grid_engine`
wholesale.

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
IS the configuration.** The shape, real:

```dart
import 'package:grid_sdk/grid_sdk.dart';

class SpaceStationDelegate extends GridDelegate {
  SpaceStationDelegate({required this.gridHome, required this.wiring});

  /// The grid's home (absolute) — its state store lives under `<gridHome>/.grid/`.
  final String gridHome;

  /// The work-axis values `buildStationWork` assembled off-tree.
  final StationWorkWiring wiring;

  @override
  Seed build(TreeContext context, GridConfiguration configuration) {
    return RawAssetGrid(
      root: gridHome,
      assets: [
        Station(
          name: 'space',
          assets: [
            Nest(
              children: [StationWork(wiring: wiring)],
              child: Substations(
                substations: [
                  // A RELATIVE root resolves against the grid home at build.
                  Substation('the_grid', '../the_grid', prefix: 'tg',
                      assets: [const SubstationWork()]),
                  Substation('genesis', '../genesis',
                      assets: [const SubstationWork()]),
                ],
              ),
            ),
          ],
        ),
      ],
    );
  }
}
```

The full model — the canonical tree, `runGrid` / `GridDelegate`, the asset
scopes, the closed questions — lives in
**[`docs/CONFIG-MODEL.md`](../../docs/CONFIG-MODEL.md)**
(the ratified v3 model). The build breakdown is
**[`docs/GRID-SDK-BUILD-ORDER.md`](../../docs/GRID-SDK-BUILD-ORDER.md)**.

## The surface

Four layers, matching the barrel's sections (`lib/grid_sdk.dart` documents
each).

### Composition Seeds — pure, offline

A station authored as a tree:
`RawAssetGrid(root, assets)` → `Station(name, root?, assets)` →
`Substations(substations)` → `Substation(name, root, prefix?, assets)`.

- **`RawAssetGrid`** roots the grid at an **absolute** `root` (the grid's home:
  its state store lives under `<root>/.grid/`; the grid has no work store) and
  provides it ambiently as `GridRoot`.
- **`Station`** — the machine. `root` is optional and defaults to the ambient
  `GridRoot`; a `Station` with neither refuses loud.
- **`Substations`** — the `MultiChildSeed` fan-out; children are literal,
  composed (a seed whose `build` returns a `Substation`), or conditional
  (`if (kDebug) Substation(...)`).
- **`Substation`** — a project: a name and **ONE root**, absolute or
  **grid-root-relative** (resolved against the ambient `GridRoot` at build).
  `prefix` is a **separate identity axis** defaulting to `name` (`the_grid`
  mints `tg-…`); its work store lives at `<root>/.beads/`. Each carries an
  intrinsic `ValueKey('substation:<name>')` so siblings reconcile by NAME,
  never by position.

Asset slots are `List<Seed>` (Q7); group stacks with `Nest`. Validation lives
in the types — an empty or cwd-relative root, or a missing enclosing scope,
refuses LOUD at build (an authoring error, never a default). The scope values
(`GridRoot` / `StationScope` / `SubstationScope`) ride `InheritedSeed`s and are
read with `<Scope>.of(context)` (loud when absent) or `.maybeOf(context)`.

### `runGrid` + `GridDelegate` + `GridConfiguration`

`runGrid(delegate)` mounts *configuration provision → the master build* and
returns a `GridHandle`. The delegate is **held by `runGrid`** — it never rides
the tree, so its `.state` cannot be snapshotted (ADR-0008 D-H); only its
emitted `GridConfiguration` is ambient, read with
`GridConfiguration.of(context)` (subscribing — a re-emission re-composes the
dependent subtree).

- **`GridDelegate`** — the observable (`StateNotifier<GridConfiguration>`);
  the lifecycle rails (`didLaunch` pre-tree — a throw aborts the launch;
  `initGrid` post-mount async, unawaited; `onReady`; `onTeardown` — post-mount
  failures are captured, attributed, and surfaced loud as `GridHookError`s);
  and the master `build(context, configuration) → Seed`. The default build
  returns `RawAssetGrid(root: root, assets: assets)`; the base `root` getter
  **throws** — there is no default root (v3 §0).
- **`GridConfiguration`** — a thin freezed value carrying an opaque `settings`
  map (Q6: no domain/aspect machinery until a real consumer earns it).
- **`GridHandle`** — `await teardown()` (onTeardown → unmount → the orphan
  sweep; idempotent), plus the dev-mode reassemble affordances: `hotReload()`
  re-runs the master build on the SAME delegate (after the VM's
  `reloadSources`); `hotRestart()` re-runs the `runGrid(delegateFactory:)` and
  re-composes on a FRESH delegate. Both return a `ReassembleReport`; both
  ADOPT every live node via keyed reconcile (nothing unmounts, no running
  agent is killed); a handle launched without a factory refuses `hotRestart`
  LOUD.
- **`runGrid`'s seams** — `onFlushed` (fires after every completed flush),
  `orphanSweep` (runs at the end of teardown), `onError` (the post-mount
  refusal sink; rethrow-to-zone by default).

### Stores at roots + substation init

A store lives at a root, uniformly (Q5a):

- **`GridStateStore`** — the grid's state store at `<grid.root>/.grid/.beads/`;
  the station lock colocates at `<grid.root>/.grid/station.lock`.
- **`SubstationWorkStore`** — a substation's work store at `<root>/.beads/`.
- **`StoreLocator`** — expects a store **exactly at its root**: no walk-up;
  absence is a LOUD `StoreRefusal` (a boot refusal the operator fixes, never a
  condition the framework papers over).
- **`SubstationInitializer`** — seeds a new substation's store at its root and
  yields a `SubstationInitResult` whose `.toSeed()` mounts it in the tree; the
  documented process is
  [`docs/SUBSTATION-INIT.md`](../../docs/SUBSTATION-INIT.md).

### The work binding

The runGrid→engine bridge: the engine's work subtree mounts **inside** the
composition tree, fed by runner-assembled off-tree machinery.

- **`StationWork(wiring:)`** — the station-scoped asset providing the engine's
  ambient work-axis stack (notifier / services / resolver / registry /
  process-lease vendor) to everything below; mounted ABOVE the `Substations`
  fan-out.
- **`SubstationWork()`** — the per-substation work seat: derives the engine's
  config from the ambient `SubstationScope` (ownership = {name, prefix},
  BOTH identity axes) and mounts the engine's `WorkList`. **Unarmed** — no
  `StationWork` above — it mounts nothing: the authored tree stands, drives no
  work. Knobs: `resident` (default `true` — a resident station's ready
  frontier IS the drive set; there is no drive-list), `maxConcurrentWork` (the
  per-substation override), `driveList` (the blessed-bead gate for a
  NON-resident arm). *(tg-eli, 2026-07-19: `circuitMintMode` /
  `CircuitMintMode` no longer exist — molecule is the only circuit engine,
  unconditionally; there is no mint-mode knob or flat-cursor opt-out.)*
- **`buildStationWork(...)`** — assembles the off-tree machinery over REAL
  stores at their roots (controllers → join bridge → bd write chokepoint →
  restart reconciler → driver). Required: `stateStore`, `substations` (a
  `SubstationWorkSpec` per project — name / ONE root / prefix), `resolver`
  (the bead→work-Seed seam; an asset pack supplies it), and `dryRun`. Store
  binding is exact-at-root, fail-closed (LOUD `StoreRefusal`, never a
  walk-up); the {name, prefix} identity tokens must be disjoint across
  substations (ownership matches EITHER axis). `dryRun` selects the inert
  seams as ONE posture — a recording no-op bd chokepoint, a would-spawn
  transport, an inert git service; live wires the real bd / subprocess /
  `git`+`gh` services.
- **`StationWorkRuntime`** — the runner-held lifecycle around `runGrid`, plus
  the readable status values (`wedge`, `latest`, `lastRestartReport`).

The pinned ordering (ADR-0007 §4):

```dart
final work = await buildStationWork(
  stateStore: GridStateStore.forGridRoot(gridHome),
  substations: [
    SubstationWorkSpec(name: 'the_grid', root: '$home/the_grid', prefix: 'tg'),
    SubstationWorkSpec(name: 'genesis', root: '$home/genesis'),
  ],
  resolver: resolver,   // the bead→work-Seed seam (an asset pack supplies it)
  registry: registry,   // the reentrant capability/circuit registry
  dryRun: true,         // ONE dry/live posture; live wires the real services
);
await work.start();     // controllers → freshness → restart-reconcile → bridge
final grid = runGrid(
  SpaceStationDelegate(gridHome: gridHome, wiring: work.wiring),
  onFlushed: work.afterFlush,      // the driver's post-flush re-scans
  orphanSweep: work.sweepOrphans,  // the teardown-vs-spawn reap
);
// ... resident ...
await grid.teardown();  // unmount → effects kill → SWEEP (await it)
await work.shutdown();  // driver + bridge + controllers down
```

## Status

The authoring surface is **shipped**: Track B (the composition Seeds,
`tg-vrz`), Track C (`runGrid` + `GridDelegate` + `GridConfiguration`,
`tg-tv3`), Track D (stores at roots + substation init, `tg-y1b`), and Track J0
(the work binding, `tg-yl8`) have all landed. The barrel (`lib/grid_sdk.dart`)
maps the surface section by section; the track breakdown is
[`docs/GRID-SDK-BUILD-ORDER.md`](../../docs/GRID-SDK-BUILD-ORDER.md).

## House conventions

Dart `^3.11`, pub workspace + melos, `publish_to: none`, `resolution: workspace`.
Lints are inherited from the workspace-root `analysis_options.yaml`
(strict-casts / -inference / -raw-types + the shared house rules). **freezed**
sealed unions + `json_serializable` for value types; **Fakes, not mocks**; pure
logic tested before IO.
