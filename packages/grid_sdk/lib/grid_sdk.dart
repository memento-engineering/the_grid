/// The public authoring surface of the grid — **"the grid" as concrete code**
/// (GLOSSARY R9). A station is *authored as a Seed*: consumers **compose** this
/// SDK's composition types and drive them with `runGrid`; they never import the
/// private `grid_engine` (ADR-0008 Decision 2 — *compose, never subclass*).
///
/// ## The thesis: code as config
///
/// Just as the org went Dart-first before TOML, the grid goes **code-first
/// before configuration**. A station is not *configured* by a value the
/// framework interprets — it is **built**, as a tree, in Dart, by its author.
/// Plain language features *are* the configuration language: an `if` mounts a
/// substation, a `for` fans out, a watched value re-composes. `GridConfiguration`
/// stays thin and subordinate; the tree IS the configuration.
///
/// See `docs/SCRATCH-station-config-model.md` (the ratified model, v3) and
/// `docs/GRID-SDK-BUILD-ORDER.md` (the track breakdown).
///
/// ---
///
/// **Tracks B + C + D fill the authoring layer in** (composition Seeds +
/// `runGrid`/`GridDelegate` + stores-at-roots + the substation init flow).
/// The remaining commented sections map the later tracks.
library;

// The tree vocabulary a station author needs (Seed / StatelessSeed / Nest /
// TreeContext / keys) comes WITH the SDK — one import authors a station.
export 'package:genesis_tree/genesis_tree.dart';

// The observable a `GridDelegate` IS. Re-exported so `addListener` / its
// callback + remover types are usable from the one SDK import (a station author
// never imports `state_notifier` directly).
export 'package:state_notifier/state_notifier.dart'
    show ErrorListener, Listener, RemoveListener, StateNotifier;

// ── Composition Seeds (Track B — tg-vrz) ────────────────────────────────────
// The pure, offline composition layer — a station authored as a tree:
//   RawAssetGrid(root, assets)   · the raw root; the grid's state store lives
//                                  under `<root>/.grid/` (the grid has no
//                                  work store).
//   Station(root?, name, assets) · the machine; `root` defaults to grid.root.
//   Substations(substations)     · the MultiChildSeed fan-out over the
//                                  station's projects.
//   Substation(name, root, assets) · a project; ONE root, work store at
//                                  `<root>/.beads/`.
// Asset slots are `List<Seed>` (Q7); validation lives in the types — an
// invalid composition refuses LOUD at build (an authoring error, never a
// default). Scope values (GridRoot / StationScope / SubstationScope) ride
// InheritedSeeds and are read with `<Scope>.of(context)`.
export 'src/composition/composition.dart' hide AssetFanOut;
export 'src/composition/scopes.dart';

// ── runGrid + GridDelegate + GridConfiguration (Track C — tg-tv3) ────────────
// The entry point + lifecycle rails: `runGrid(delegate)` mounts *delegate
// provision → configuration provision → build*, returning a `GridHandle`.
//   GridDelegate      · the observable `StateNotifier<GridConfiguration>`; the
//                       lifecycle rails (`didLaunch` pre-tree / `initGrid`
//                       post-mount async / `onReady` / `onTeardown`, failures
//                       captured + attributed + loud as a `GridHookError`); and
//                       the master `build(context, configuration)` returning
//                       the §2 station tree (default: the `RawAssetGrid` root).
//   GridConfiguration · a thin, plain value provided into the tree (Q6: no
//                       domain/aspect machinery until something real earns it);
//                       a watched value that re-composes on emission.
// No framework service/source layers — that split DIED in v3; assets mount at
// scope in the composition tree (Track B).
export 'src/run/configuration.dart';
export 'src/run/grid_delegate.dart';
export 'src/run/run_grid.dart';

// ── Stores at roots + substation init (Track D — tg-y1b) ────────────────────
// A store lives at a root, uniformly (Q5a):
//   GridStateStore    · the grid's state store under `<grid.root>/.grid/`
//                       (the station lock colocates); read from a `GridRoot`
//                       via `gridRoot.stateStore`.
//   SubstationWorkStore · a substation's work store at `<root>/.beads/`;
//                       read from a `SubstationScope` via `scope.workStore`.
//   StoreLocator      · discovers a work store EXACTLY at `<root>/.beads` (no
//                       walk-up — the ambience fossil); a substation whose root
//                       has no store is a LOUD `StoreRefusal` (boot refusal).
// The substation initialization flow (Q-mig), first-class as code + a documented
// process (`docs/SUBSTATION-INIT.md`):
//   SubstationInitializer · seed a new substation's store at its root, adopt its
//                       prefix (`bd init --prefix <name>`), yield a
//                       SubstationInitResult whose `.toSeed()` mounts it in the
//                       tree. Seams (BeadStoreSeeder / DirectoryProbe) injected —
//                       pure + offline.
// A37 (restated, no pseudo-substation): sessions/cursors write ONLY to the grid
// state store, through the chokepoint — never a substation work store (a work
// source is read-only). The state store is NOT a substation: distinct type,
// distinct location (under `.grid/`), never in the `Substations` fan-out.
export 'src/stores/stores.dart';
export 'src/stores/substation_init.dart';

