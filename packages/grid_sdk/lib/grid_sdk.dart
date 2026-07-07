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
/// **Track B fills the composition layer in.** The remaining sections are
/// the map for the later tracks.
library;

// The tree vocabulary a station author needs (Seed / StatelessSeed / Nest /
// TreeContext / keys) comes WITH the SDK — one import authors a station.
export 'package:genesis_tree/genesis_tree.dart';

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

// ── runGrid + GridDelegate (Track C) ────────────────────────────────────────
// The entry point + lifecycle rails: `runGrid(GridDelegate)`, the observable
// `StateNotifier<GridConfiguration>`, the lifecycle hooks (`didLaunch` /
// `initGrid` / `onReady` / `onTeardown`), and the master `build(ctx, conf)`
// returning the canonical station tree. NOT YET exported.

// ── Configuration (Track C) ─────────────────────────────────────────────────
// `GridConfiguration` — a thin, plain value provided into the tree (Q6: no
// domain/aspect machinery until something real demands it). NOT YET exported.
