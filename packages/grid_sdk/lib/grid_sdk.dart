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
export 'package:grid_engine/src/seeds/provider.dart'
    show
        Provider,
        ProviderCreate,
        ProviderDispose,
        ProviderScope,
        ProviderTreeContext;

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

// ── Asset declarations (tg-1w3m) ────────────────────────────────────────────
// The dependency-neutral asset declaration contract every producer and
// consumer sits above: asset packs in power_station and elsewhere, station
// composition, and generic CLI surfaces. It lives HERE because no package in
// the_grid may import power_station to understand an asset registry
// (ADR-0002 Decision 1: consumers import the public SDK, never grid_engine).
//   GridAssetDefinition  · ONE logical asset — a const, keyed, INERT Seed
//                          whose reconciliation key IS its AssetKey, so one
//                          generated instance inhabits both a registry and a
//                          `Substation`'s `assets` List<Seed>.
//   GridAssetPackDefinition / GridAssetRegistry · the validated collections;
//                          duplicate AssetKey / AssetArtifactKey refuses LOUD
//                          at construction.
//   AssetKey / AssetArtifactKey · logical and delivery-leg identity, authored
//                          independently (the claude and agents legs of one
//                          skill share an AssetKey and nothing else).
//   AssetKind / AssetAudience / AssetVisibility / AssetSelector · the closed
//                          vocabularies; a selector is DECLARED here and
//                          evaluated above — this package does no discovery,
//                          no YAML parsing, no root probing, no selector I/O,
//                          and no materialization.
export 'src/assets/asset_declaration.dart';
export 'src/assets/asset_identity.dart';
export 'src/assets/asset_registry.dart';

// ── runGrid + GridDelegate + GridConfiguration (Track C — tg-tv3) ────────────
// The entry point + lifecycle rails: `await runGrid(delegate)` runs
// `didLaunch → boot → mount`, returning a `GridHandle`; `initGrid → onReady`
// follows as an unawaited kickoff. The delegate is held by
// `runGrid` — it never rides the tree, so its `.state` can't be snapshotted
// (ADR-0008 D-H); only its emitted `GridConfiguration` is ambient.
//   GridDelegate      · the observable `StateNotifier<GridConfiguration>`; the
//                       lifecycle rails (`didLaunch` / awaited `boot` pre-tree /
//                       `initGrid` post-mount async / `onReady` / `onTeardown`,
//                       failures
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
// The dev-mode reassemble affordance: `GridHandle.hotReload` / `hotRestart`
// return a `ReassembleReport`; a JIT station wires them into
// `grid_exploration`'s `ReassembleTool`. No `dart:developer` here — the wire
// lives in the package that owns the namespace.
export 'src/run/reassemble.dart';
export 'src/run/run_grid.dart';
// The station composition contract's supporting types (tg-at3r — the old
// grid_cli ResidentGridDelegate contract folded into GridDelegate): the
// vended status view (StationView), the staleness postures, the arming
// refusal (StationRefusal), and the appended-substation identity
// (SubstationConfig) the arming policy folds over.
export 'src/run/staleness_posture.dart';
export 'src/run/station_refusal.dart';
export 'src/run/station_view.dart';
export 'src/run/substation_config.dart';

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

// ── The trajectory harness (Stage 1 — tg-zfek, stage1-wiring §1) ────────────
// The fenced transition service's station-side owner, built by
// `assembleStationWork` beside the state writer and lifecycled by
// `StationWorkRuntime` (up after the sources, down before them — never
// blocking either). `TrajectoryConfig` is the one new assembly parameter; a
// runner surfaces it as `--trajectory`/`--no-trajectory` (a space_station
// edit, stage1-wiring §1.1).
export 'package:grid_trajectory/grid_trajectory.dart'
    show
        TrajectoryProvenance,
        TrajectoryRecord,
        TrajectoryTick,
        TrajectoryTickFixpoint,
        TrajectoryTickPass;
// The P1 MIRROR (the trajectory cut, wave 1 / C1): the harness's in-memory
// fold read surface, implementing the ENGINE's `TrajectoryHeadSnapshot` seam
// over `grid_trajectory`'s row types. Exported so a status surface can read
// the snapshot; nothing consumes it for DECISIONS until C2/C3.
export 'src/trajectory/session_head_mirror.dart';
// The P2 MIRROR (C4) — the same surface for the step axis, implementing the
// engine's `TrajectoryStepSnapshot` seam and its `byP2SessionId` index.
export 'src/trajectory/step_cursor_mirror.dart';
export 'src/trajectory/trajectory_config.dart';
export 'src/trajectory/trajectory_harness.dart';

// ── Station command extension ───────────────────────────────────────────────
// The SDK supplies the typed extension seam and the implementation a running
// station dispatches to; the station composes it, while its control-surface
// adapter owns wire envelopes. (tg-at3r sweep: formerly
// `ResidentGridCommandHandler` / `ResidentWorkCommandStore`.)
export 'src/command/command_operation.dart';
export 'src/command/station_command_handler.dart';
export 'src/command/work_bead_keys.dart';
export 'src/command/bead_board.dart';
export 'src/command/bead_round.dart';

// ── The work binding (Track J0 — tg-yl8) ────────────────────────────────────
// The runGrid→engine bridge: the engine's work subtree mounts INSIDE the
// composition tree ("each child `Substation` establishes its `WorkList`",
// v3 §3), fed by runner-assembled off-tree machinery.
//   StationWork(wiring)   · the station-scoped asset providing the engine's
//                           ambient work-axis stack (notifier / services /
//                           resolver / registry) — mounted ABOVE the
//                           `Substations` fan-out.
//   SubstationWork()      · the per-substation work seat (replaces H2's
//                           placeholder leaf): derives the engine config from
//                           the ambient `SubstationScope` (ownership =
//                           {name, prefix} — BOTH identity axes) and mounts
//                           the `WorkList`. Unarmed (no `StationWork` above)
//                           it mounts nothing — the authored tree stands.
//   assembleStationWork(...) · assembles the off-tree machinery over REAL stores
//                           at their roots (controllers → join bridge →
//                           chokepoint → restart reconciler → driver), one
//                           dry/live posture, exact-at-root store binding
//                           (LOUD StoreRefusal, never a walk-up).
//   StationWorkRuntime    · the runner-held lifecycle: `await start()` (the
//                           pinned ordering: freshness → restart-reconcile →
//                           bridge) BEFORE `runGrid`; `afterFlush` rides
//                           `runGrid(onFlushed:)`; `shutdown()` AFTER
//                           `grid.teardown()`.
export 'src/work/store_connection.dart';
export 'src/work/station_work.dart';
export 'src/work/work_assembly.dart';
// The narrow engine seam a RUNNER names when assembling (ADR-0008 D2 —
// consumers still never import grid_engine): the bead→circuit resolver + the
// registry/resolver types `assembleStationWork` accepts. An asset pack (e.g.
// grid_assets' code circuit) supplies the values.
// The wedge signal (tg-jwh) rides here too: a runner reads `work.wedge` for its
// status view, and passes an `ExplorationTransport` to `assembleStationWork` when it
// adapts a sink for the `station.wedged` flare. `WedgeMonitor` itself is NOT
// exported — the driver owns it; a runner only ever READS the state.
export 'package:grid_engine/grid_engine.dart'
    show
        CapabilityRegistry,
        CacheTokenTotals,
        Circuit,
        CircuitResolver,
        ExplorationTransport,
        FalseFMetrics,
        Flowing,
        JoinedSnapshot,
        LandedDeliveryTotals,
        LedgerGrade,
        LedgerNodeMetrics,
        LedgerSessionMetrics,
        MetricsDecodeIssue,
        OrphanSweepReport,
        ResultMetricFields,
        ResultTransport,
        TreeProjector,
        RestartReconciler,
        RestartReport,
        WorkTerminalSettlementReport,
        SessionLedgerMetricsProjection,
        SessionResolver,
        Stalling,
        SweptGroup,
        WedgeSample,
        WedgeState,
        Wedged,
        ZombieReap,
        kDefaultWedgePollInterval,
        kDefaultWedgeThreshold,
        kNotWedged,
        projectSessionLedgerMetrics;
