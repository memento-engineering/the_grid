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
/// **Track A (this commit) births the package with an intentionally empty
/// export skeleton.** The surface fills in across later tracks; the sections
/// below are the map, not yet the exports.
library;

// ── Composition Seeds (Track B — tg-vrz) ────────────────────────────────────
// The pure, offline composition layer — a station authored as a tree:
//   RawAssetGrid(root, assets)   · the raw root; the grid's state store lives
//                                  at `root`.
//   Station(root?, name, assets) · the machine; `root` defaults to grid.root.
//   Substations(substations)     · the MultiChildSeed fan-out; each child
//                                  establishes its WorkList.
//   Substation(name, root, assets) · a project; ONE root, work store at it.
// Asset slots are `List<Seed>` / `Seed`; validation lives in the types (an
// invalid composition cannot be constructed). NOT YET exported.

// ── runGrid + GridDelegate (Track C) ────────────────────────────────────────
// The entry point + lifecycle rails: `runGrid(GridDelegate)`, the observable
// `StateNotifier<GridConfiguration>`, the lifecycle hooks (`didLaunch` /
// `initGrid` / `onReady` / `onTeardown`), and the master `build(ctx, conf)`
// returning the canonical station tree. NOT YET exported.

// ── Configuration (Track C) ─────────────────────────────────────────────────
// `GridConfiguration` — a thin, plain value provided into the tree (Q6: no
// domain/aspect machinery until something real demands it). NOT YET exported.
