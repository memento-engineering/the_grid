/// The station-runner library pieces (ADR-0008 Decision 2, amended 2026-07-02 —
/// the composition inversion).
///
/// **The asset's runner IS `main()`** — the framework owns no run command and
/// calls nobody back. An asset composes its station by calling these pieces in
/// order, inheriting the arming/gating discipline by calling through (never by
/// subclassing — ADR-0008 D1):
///
/// ```dart
/// // an asset's main()/command body:
/// final args = StationArgs.from(argResults);       // addStationFlags(parser)
/// StationSources? sources;                         // held for refusal cleanup
/// try {
///   validateArming(args);                          // throws StationRefusal
///   final ws = discoverWorkspaces(
///     workspacePath: args.workspacePath,
///     stateWorkspacePath: args.stateWorkspacePath);
///   sources = await buildControllers(
///     work: ws.work, state: ws.state, noSql: args.noSql);
///   final live = await buildLiveWiring(args: args, sources: sources);
///   final services = ServiceBundle(sourceControl: /* the asset's own */);
///   final wiring = composeStation(
///     work: sources.work, state: sources.state,
///     stationServices: live.stationServices, substations: [...],
///     git: live.git, workRoot: live.workRoot, groups: live.groups,
///     freshnessBarrier: live.freshnessBarrier,
///     resolver: myResolver, registry: myRegistry, services: services,
///     wrapRoot: (root) => /* mount the asset's ambient config values */ root);
///   return driveStation(wiring: wiring, sources: sources, ...);
/// } on StationRefusal catch (refusal) {
///   await sources?.shutdown();   // a live Dolt pool would outlive the refusal
///   stderr.writeln(refusal.message);
///   return refusal.code;
/// }
/// ```
///
/// [composeStation] stays **pure composition** (no process, no socket, no bead
/// write); `start` ordering is pinned in [TreeRunWiring.start] (barrier →
/// restart → mount). `--dry-run` stays the SAFE DEFAULT — dry-ness lives in the
/// seams ([buildLiveWiring] wires a recording no-op transport + a no-op bd
/// runner + an inert git service), never in a dispatcher short-circuit.
library;

import 'dart:async';
import 'dart:developer' as developer;
import 'dart:io';

import 'package:args/args.dart';
import 'package:genesis_tree/genesis_tree.dart';
import 'package:grid_controller/grid_controller.dart';
import 'package:grid_engine/grid_engine.dart';
import 'package:grid_exploration/grid_exploration.dart';
import 'package:grid_runtime/grid_runtime.dart';

import 'run_command.dart' show RuntimeProviderKind;
import 'runtime_snapshot_source.dart';
import 'station_control.dart';
import 'station_lock.dart';

// ---------------------------------------------------------------------------
// Refusals + the standard station flags
// ---------------------------------------------------------------------------

/// A composition-time refusal (bad arming, missing workspace) — the runner
/// prints [message] and exits with [code]. Thrown by [validateArming] /
/// [discoverWorkspaces] so every asset runner inherits the fail-closed gates by
/// calling through.
class StationRefusal implements Exception {
  /// Creates the refusal with its user-facing [message] and exit [code].
  const StationRefusal(this.message, {this.code = 64});

  /// The user-facing refusal text.
  final String message;

  /// The process exit code (64 = usage, 1 = environment).
  final int code;

  @override
  String toString() => message;
}

/// Adds the STANDARD station flags to an asset command's [parser] — composition,
/// not inheritance (a runner adds these next to its own asset flags).
void addStationFlags(ArgParser parser) {
  parser
    ..addMultiOption(
      'substation',
      abbr: 'r',
      help:
          'An OWNED substation / ownership token (repeatable) — the SINGLE '
          'allow-set feeding both the ownership gate and the dispatch '
          'predicate. The dogfood substation is `tgdog`.',
    )
    ..addMultiOption(
      'owner',
      help: 'Alias for --substation; merged into one shared allow-set.',
    )
    ..addOption(
      'provider',
      allowed: ['subprocess', 'tmux'],
      defaultsTo: 'subprocess',
      help: 'The runtime provider for agent spawns.',
    )
    ..addOption(
      'root',
      help:
          'The registered worktree root checkout. Required to ARM a non-dry '
          'run; never created by the runner.',
    )
    ..addOption(
      'head',
      help:
          'ASSIGN the base branch per-bead worktrees cut from, overriding the '
          'probed origin/HEAD. Omit to probe.',
    )
    ..addOption(
      'workspace',
      abbr: 'w',
      help:
          'The beads workspace to read ready work from (a dir at or above a '
          '`.beads/`). Defaults to discovery from the cwd; read-only under '
          '--dry-run.',
    )
    ..addOption(
      'state-workspace',
      help:
          'A SEPARATE the_grid-owned beads workspace for its own session/'
          'lifecycle beads (A36/A37), so the --workspace source stays '
          'read-only. Omit to write sessions into --workspace.',
    )
    ..addOption(
      'state-substation',
      defaultsTo: 'tgdog',
      help:
          "the_grid's OWNED session partition (the --state-workspace prefix), "
          'unioned into the allow-set. Only used with --state-workspace.',
    )
    ..addMultiOption(
      'bead',
      abbr: 'b',
      help:
          'A specific work-bead id to drive (repeatable) — the blessed '
          'drive-list layered on the allow-set (ADR-0006). REQUIRED for a live '
          '(--no-dry-run) arm; in --dry-run omit to observe every owned bead.',
    )
    ..addFlag(
      'dry-run',
      defaultsTo: true,
      help:
          'Observe-only: NO writes, NO spawns (the SAFE DEFAULT). Pass '
          '--no-dry-run to ARM the live writing arm (requires --root).',
    )
    ..addFlag(
      'land',
      defaultsTo: false,
      negatable: false,
      help:
          'ARM the land step (ADR-0006 D3): on step-complete, commit → push → '
          'open a PR (never auto-merges). OPT-IN, OFF by default; requires '
          '--no-dry-run.',
    )
    ..addOption(
      'for-seconds',
      help: 'Run for a fixed number of seconds then exit (scripted / CI).',
    )
    ..addFlag(
      'no-sql',
      negatable: false,
      help:
          'Force the bd-CLI read path even when pooled Dolt SQL is available.',
    )
    ..addOption(
      'control-port',
      defaultsTo: '0',
      help:
          'The StationControl loopback port (RS-4; resident mode only). '
          '0 = ephemeral (default).',
    );
}

/// The parsed standard station inputs — a plain value an asset runner builds
/// from its [ArgResults] (or constructs directly in a test).
class StationArgs {
  /// Creates the parsed inputs.
  const StationArgs({
    required this.substations,
    this.provider = RuntimeProviderKind.subprocess,
    this.rootPath,
    this.head,
    this.workspacePath,
    this.stateWorkspacePath,
    this.stateSubstation,
    this.targetBeads = const {},
    this.dryRun = true,
    this.land = false,
    this.noSql = false,
    this.runFor,
    this.resident = false,
    this.controlPort = 0,
  });

  /// Parses the standard flags added by [addStationFlags].
  factory StationArgs.from(ArgResults args) {
    final seconds = args.option('for-seconds');
    return StationArgs(
      substations: <String>{
        ...args.multiOption('substation'),
        ...args.multiOption('owner'),
      }..removeWhere((r) => r.trim().isEmpty),
      provider: RuntimeProviderKind.parse(args.option('provider')),
      rootPath: args.option('root'),
      head: args.option('head'),
      workspacePath: args.option('workspace'),
      stateWorkspacePath: args.option('state-workspace'),
      stateSubstation: args.option('state-workspace') == null
          ? null
          : args.option('state-substation'),
      targetBeads: <String>{...args.multiOption('bead')}
        ..removeWhere((b) => b.trim().isEmpty),
      dryRun: args.flag('dry-run'),
      land: args.flag('land'),
      noSql: args.flag('no-sql'),
      runFor: seconds == null ? null : Duration(seconds: int.parse(seconds)),
      controlPort: int.parse(args.option('control-port')!),
    );
  }

  /// The ownership allow-set (work substations).
  final Set<String> substations;

  /// The runtime provider kind for agent spawns.
  final RuntimeProviderKind provider;

  /// The registered worktree root checkout (required to arm a live run).
  final String? rootPath;

  /// The assigned base branch worktrees cut from (null ⇒ probe origin/HEAD).
  final String? head;

  /// The work workspace to read from (null ⇒ discover from cwd).
  final String? workspacePath;

  /// The_grid-owned state workspace (A36/A37); null ⇒ no split store.
  final String? stateWorkspacePath;

  /// The owned session partition within the state workspace.
  final String? stateSubstation;

  /// The blessed drive-list (ADR-0006) — required non-empty for a live arm.
  final Set<String> targetBeads;

  /// Observe-only (the SAFE DEFAULT).
  final bool dryRun;

  /// Whether the land step is armed (live only).
  final bool land;

  /// Force the bd-CLI read path.
  final bool noSql;

  /// Run for a fixed duration then exit (null ⇒ run forever).
  final Duration? runFor;

  /// Resident all-ready arming (RS-3, `docs/SCRATCH-resident-station.md` D-R4):
  /// the ready frontier of the owned substation IS the drive set — no
  /// `--bead`, ever (a drive-list is a trigger surface under resident arming;
  /// Nico's ruling). NOT parsed by [StationArgs.from]/[addStationFlags] — the
  /// `run` verb's flag surface is untouched; the composed resident verb
  /// (space_station's `up`, RS-5b) constructs [StationArgs] with this set
  /// directly.
  final bool resident;

  /// The `StationControl` loopback port (RS-4, D-C2) — `0` = ephemeral
  /// (default). Only consulted when [resident] is true; a non-resident
  /// (`run`) arm never binds the control surface.
  final int controlPort;
}

/// The arming/gating checks (ADR-0006 / A36/A37 / RS-3 D-R4) — every runner
/// inherits them by calling through. Throws a [StationRefusal] (exit 64) on a
/// bad arming.
///
/// [rootInjected]/[stateInjected] let an offline test that injects its own
/// root/state seams pass the live gates without real paths.
///
/// The drive-list requirement is MODE-AWARE (the one deliberate branch — every
/// other check applies identically to both modes): the non-resident (`run`,
/// transitional scaffolding until RS-8) arm still requires ≥1 `--bead`, byte-
/// identical to before RS-3; a [StationArgs.resident] arm takes the OPPOSITE
/// stance — the ready frontier of the owned substation IS the drive set, so a
/// `--bead` is refused LOUD (a drive-list is a trigger surface under resident
/// arming — Nico's ruling), in EITHER dry-run or live.
void validateArming(
  StationArgs args, {
  bool rootInjected = false,
  bool stateInjected = false,
}) {
  if (args.substations.isEmpty) {
    throw const StationRefusal(
      'grid run: at least one --substation/--owner is required (the ownership '
      'allow-set; the dogfood rig is `tgdog`).',
    );
  }
  if (args.land && args.dryRun) {
    throw const StationRefusal(
      'grid run: --land cannot be combined with --dry-run. Land is a LIVE '
      'GitHub write (commit → push → PR); a dry run touches nothing. Re-run '
      'with --no-dry-run to arm land, or drop --land to observe only.',
    );
  }
  if (!args.dryRun && args.rootPath == null && !rootInjected) {
    throw const StationRefusal(
      'grid run: a non-dry (live) run requires --root (the registered worktree '
      'root under engineering.memento). Re-run with --dry-run (the default) to '
      'observe only, or pass --root to ARM the writing arm.',
    );
  }
  if (!args.dryRun && args.stateWorkspacePath == null && !stateInjected) {
    throw const StationRefusal(
      'grid run: a non-dry (live) run requires --state-workspace — the_grid '
      'writes its session/lifecycle beads there and must NEVER default them into '
      'the read --workspace (A36/A37). Pass --state-workspace (+ '
      '--state-substation), or use --dry-run.',
    );
  }
  if (args.resident) {
    if (args.targetBeads.isNotEmpty) {
      throw const StationRefusal(
        'grid run: a resident station takes no drive-list — the ready '
        'frontier of the owned substation IS the drive set (RS-3, D-R4). A '
        '--bead is a trigger surface under resident arming; bless a bead by '
        'making it ready in the store, not with --bead.',
      );
    }
  } else if (!args.dryRun && args.targetBeads.isEmpty) {
    throw const StationRefusal(
      'grid run: a non-dry (live) run requires at least one --bead — the '
      'blessed drive-list (ADR-0006). The_grid mounts an agent ONLY for beads '
      'explicitly blessed for a live arm; re-run with --bead <id> (repeatable), '
      'or use --dry-run to observe all owned work.',
    );
  }
}

// ---------------------------------------------------------------------------
// discoverWorkspaces → buildControllers
// ---------------------------------------------------------------------------

/// Discovers the work (and optional state) beads workspaces. Throws a
/// [StationRefusal] (exit 1) when a named workspace cannot be found.
({BeadsWorkspace work, BeadsWorkspace? state}) discoverWorkspaces({
  String? workspacePath,
  String? stateWorkspacePath,
}) {
  final work = BeadsWorkspace.discover(start: workspacePath);
  if (work == null) {
    throw StationRefusal(
      'grid run: no .beads/ workspace found from '
      '${workspacePath ?? Directory.current.path}',
      code: 1,
    );
  }
  BeadsWorkspace? state;
  if (stateWorkspacePath != null) {
    state = BeadsWorkspace.discover(start: stateWorkspacePath);
    if (state == null) {
      throw StationRefusal(
        'grid run: no .beads/ state workspace found from $stateWorkspacePath '
        '(--state-workspace)',
        code: 1,
      );
    }
  }
  return (work: work, state: state);
}

/// The observed inputs a composed station runs over: the two [SnapshotSource]s,
/// the exploration host (leonard attach), and the controller lifecycle. A test
/// constructs one directly over fakes; [buildControllers] builds the live one.
class StationSources {
  /// Bundles the [work]/[state] sources and lifecycle hooks. All hooks default
  /// to no-ops (the offline-test shape).
  StationSources({
    required this.work,
    this.state = const EmptySnapshotSource(),
    this.host,
    this.readPathName = 'injected',
    this.stateWorkspace,
    Future<void> Function()? start,
    Future<void> Function()? shutdown,
    Future<void> Function()? requery,
  }) : _start = start,
       _shutdown = shutdown,
       _requery = requery;

  /// The read-only work axis.
  final SnapshotSource work;

  /// The_grid's own state axis (sessions); empty when no split store.
  final SnapshotSource state;

  /// The exploration host (a stock leonard attaches over `ext.exploration.*`);
  /// null offline.
  final GridExplorationHost? host;

  /// The active read path (`sql`/`bdCli`/`injected`) — banner info.
  final String readPathName;

  /// The state beads workspace (the live chokepoint's bd runner cwd); null in
  /// dry-run / offline.
  final BeadsWorkspace? stateWorkspace;

  final Future<void> Function()? _start;
  final Future<void> Function()? _shutdown;
  final Future<void> Function()? _requery;

  /// Starts the controllers + registers the exploration host.
  Future<void> start() async {
    await _start?.call();
    host?.register();
  }

  /// Shuts the controllers down (after the tree tears down).
  Future<void> shutdown() async {
    await host?.dispose();
    await _shutdown?.call();
  }

  /// A completed re-query of both runtimes — the freshness-barrier half
  /// (ADR-0007 §4). A no-op over injected sources.
  Future<void> requery() async => _requery?.call();
}

/// Builds the LIVE controllers over the discovered workspaces (the M1 work axis
/// + the split A36/A37 state axis), adapts both to [SnapshotSource], and wires
/// the exploration host so a stock leonard can attach.
Future<StationSources> buildControllers({
  required BeadsWorkspace work,
  BeadsWorkspace? state,
  bool noSql = false,
}) async {
  final bundle = await GridRuntimeFactory.build(
    workspace: work,
    preferSql: !noSql,
  );
  final workController = bundle.runtime;
  final readPathName = bundle.readPath.name;
  final host = GridExplorationHost(
    workController,
    plugin: GridControllerPlugin(workController, readPath: () => readPathName),
  );

  GridControllerRuntime? stateController;
  Future<void> Function()? shutdownState;
  SnapshotSource stateSource = const EmptySnapshotSource();
  if (state != null) {
    final stateBundle = await GridRuntimeFactory.build(
      workspace: state,
      preferSql: !noSql,
    );
    stateController = stateBundle.runtime;
    shutdownState = stateBundle.shutdown;
    stateSource = RuntimeSnapshotSource(stateController);
  }

  final sc = stateController;
  return StationSources(
    work: RuntimeSnapshotSource(workController),
    state: stateSource,
    host: host,
    readPathName: readPathName,
    stateWorkspace: state,
    start: () async {
      await workController.start();
      if (sc != null) await sc.start();
    },
    shutdown: () async {
      if (shutdownState != null) await shutdownState();
      await bundle.shutdown();
    },
    requery: () async {
      await Future.wait(<Future<void>>[
        workController.requery(),
        if (sc != null) sc.requery(),
      ]);
    },
  );
}

// ---------------------------------------------------------------------------
// buildLiveWiring — the generic machine wiring (asset-agnostic)
// ---------------------------------------------------------------------------

/// The generic (asset-agnostic) machine wiring for one run: the station-level
/// services, the git execution machinery + registered root the asset lifts into
/// its own `SourceControl`, the process-group controller, the freshness
/// barrier, and the armed-or-null land ops. The asset builds its
/// [ServiceBundle] FROM these — the framework constructs no asset service.
class StationWiring {
  /// Bundles the resolved wiring.
  const StationWiring({
    required this.stationServices,
    required this.git,
    required this.workRoot,
    required this.groups,
    required this.freshnessBarrier,
    this.gitOps,
    this.prOpener,
  });

  /// The station-level ambient services (transport + chokepoint + state rig).
  final StationServices stationServices;

  /// The shared git execution machinery (worktree alloc/list/reap) the
  /// substation leases (ADR-0008 D5) — inert in dry-run.
  final StationGitService git;

  /// The registered root checkout (synthetic, empty-path in dry-run).
  final RootCheckout workRoot;

  /// The process-group controller (the orphan-kill seam — REAL even offline so
  /// its `pgid <= 1` guard is exercised).
  final ProcessGroupController groups;

  /// The completed-re-query freshness barrier (ADR-0007 §4).
  final Future<void> Function() freshnessBarrier;

  /// Land ops — non-null ONLY when `--land` armed a live run (ADR-0006 D3).
  final GitOps? gitOps;

  /// The PR opener — non-null ONLY when `--land` armed a live run.
  final PrOpener? prOpener;
}

/// Builds the generic machine wiring from the validated [args] + [sources].
/// Dry-ness lives HERE, in the seams: dry-run wires a recording no-op transport
/// (no real `claude`), a no-op bd runner (no real `bd`), an inert git service
/// (no real `git`), and a synthetic root — the tree then runs end-to-end
/// touching nothing live. The optional overrides are the offline-test seams.
Future<StationWiring> buildLiveWiring({
  required StationArgs args,
  required StationSources sources,
  void Function(String)? onRefusal,
  BdCliService? stateBdOverride,
  RuntimeProvider? providerOverride,
  StationGitService? gitServiceOverride,
  ProcessGroupController? groupsOverride,
  RootCheckout? rootCheckoutOverride,
  Future<void> Function()? freshnessBarrierOverride,
}) async {
  // THE single ownership allow-set: the work substations + the_grid's own state
  // partition (so the chokepoint owns the session beads it mints — A32/A36).
  final stateSubstation = args.stateSubstation;
  final allowSet = Set<String>.unmodifiable(<String>{
    ...args.substations,
    if (stateSubstation != null && stateSubstation.isNotEmpty) stateSubstation,
  });

  // The bd write chokepoint: dry-run (or no state store) → a no-op recording
  // runner; live → the real ProcessBdRunner over the_grid's OWN state store.
  // The chokepoint re-checks ownership fail-closed either way.
  final stateWs = sources.stateWorkspace;
  final BdCliService bd =
      stateBdOverride ??
      (args.dryRun || stateWs == null
          ? BdCliService(NoOpBdRunner())
          : BdCliService(ProcessBdRunner(workspaceRoot: stateWs.root)));
  final writer = StationBeadWriter(
    bd: bd,
    ownership: BeadOwnershipPredicate(allowSet),
    onRefusal: onRefusal ?? (m) => stdout.writeln(m),
  );

  // The runtime transport.
  final RuntimeProvider runtimeProvider =
      providerOverride ??
      (args.dryRun ? DryRunProvider() : _buildTreeProvider(args.provider));

  // The worktree git service + the registered root. Dry-run gets an INERT
  // service (no real `git` — the restart probe parses an empty worktree set).
  final git =
      gitServiceOverride ??
      (args.dryRun ? buildDryTreeGitService() : _buildTreeGitService());
  final RootCheckout root;
  if (rootCheckoutOverride != null) {
    root = rootCheckoutOverride;
  } else if (!args.dryRun && args.rootPath != null) {
    try {
      root = await git.registerRootCheckout(
        path: args.rootPath!,
        substation: args.substations.first,
        // Assign-head: cut per-bead worktrees off this branch (e.g. the_grid's
        // own feature branch) instead of the probed origin/HEAD. Null ⇒ probe.
        head: args.head,
      );
    } on Object catch (e) {
      throw StationRefusal(
        'grid run: could not register root checkout "${args.rootPath}": $e',
        code: 1,
      );
    }
  } else {
    // Dry-run synthetic root (nothing is provisioned under it).
    root = RootCheckout(
      path: '',
      defaultBranch: 'main',
      substation: args.substations.first,
    );
  }

  // Land ops are wired ONLY when --land armed a live run (ADR-0006 D3); they
  // flow into the ASSET's SourceControl, never through the station services.
  // Null ⇒ `canLand` false ⇒ land no-ops (the commit-only posture).
  final bool armLand = args.land && !args.dryRun;
  final gitOps = armLand ? GitOps(SystemGitRunner()) : null;
  final prOpener = armLand ? GhPrOpener(ghRunner) : null;

  // Station-level ambient only (ADR-0009 D2): transport + chokepoint + state
  // rig. The workspace/branch layout is the per-substation SourceControl's.
  final stationServices = StationServices(
    provider: runtimeProvider,
    writer: writer,
    stateSubstation: (stateSubstation != null && stateSubstation.isNotEmpty)
        ? stateSubstation
        : args.substations.first,
  );

  return StationWiring(
    stationServices: stationServices,
    git: git,
    workRoot: root,
    groups: groupsOverride ?? SystemProcessGroupController(),
    freshnessBarrier: freshnessBarrierOverride ?? sources.requery,
    gitOps: gitOps,
    prOpener: prOpener,
  );
}

// ---------------------------------------------------------------------------
// composeStation — pure composition (unchanged shape, + the wrapRoot hook)
// ---------------------------------------------------------------------------

/// The resolved tree-engine wiring — built by [composeStation] from the
/// injectable seams, started/torn down by the caller. A value-ish holder so a
/// test can assert the composition WITHOUT running a live loop.
class TreeRunWiring {
  /// Wraps the composed [kernel] + [restart] under the pinned start ordering.
  TreeRunWiring({
    required this.kernel,
    required this.restart,
    required Future<void> Function() freshnessBarrier,
  }) : _freshnessBarrier = freshnessBarrier;

  /// The composed M4 kernel — the running tree. Not mounted until [start].
  final StationKernel kernel;

  /// The Track-D restart respawn-or-skip reconciler, run once BEFORE the kernel
  /// mounts (so survivors are reconciled before the tree blindly respawns).
  final RestartReconciler restart;

  final Future<void> Function() _freshnessBarrier;

  /// Brings the tree up in the pinned ordering (ADR-0007 §4): the freshness
  /// barrier completes, THEN the restart reconciler reconciles the survivors,
  /// THEN — and only then — the kernel mounts and spawns.
  Future<void> start() async {
    await _freshnessBarrier();
    await restart.reconcile();
    kernel.start();
  }

  /// Tears down the tree (unmounting every effect → kill) + the join bridge.
  Future<void> teardown() async => kernel.dispose();
}

/// Assembles the M4 tree-engine [TreeRunWiring] from injectable seams — PURE
/// composition (no process, no socket, no bead write).
///
/// The ASSET seam (ADR-0008 D1): [resolver] + [registry] are REQUIRED — the
/// framework carries NO asset default. [services] is the asset's
/// per-substation collaborators (built by the asset itself from a
/// [StationWiring] — the composition inversion, 2026-07-02); [wrapRoot] is the
/// asset's provider hook (its `main()` mounts station-default config values —
/// `InheritedSeed<AgentConfig>`-style — as ancestors of everything).
TreeRunWiring composeStation({
  required SnapshotSource work,
  required SnapshotSource state,
  required StationServices stationServices,
  required List<SubstationConfig> substations,
  required StationGitService git,
  required RootCheckout workRoot,
  required ProcessGroupController groups,
  required Future<void> Function() freshnessBarrier,
  required CircuitResolver resolver,
  required CapabilityRegistry registry,
  ServiceBundle services = const ServiceBundle(),
  Seed Function(Seed root)? wrapRoot,
}) {
  final bridge = StationJoinBridge(work: work, state: state);

  // One config scope per substation, keyed by id so an add/remove mounts /
  // unmounts exactly that scope. The asset [services] are provided AT THE SCOPE
  // (ADR-0008 D5: source control is a per-substation responsibility).
  final substationScopes = substations
      .map(
        (config) => SubstationScope(
          configNotifier: SubstationConfigNotifier(config),
          services: services,
          key: ValueKey('scope.${config.substationId}'),
        ),
      )
      .toList(growable: false);

  // Track D — bind the engine's narrow worktree seams to the injected git
  // service so the engine never names the concrete VCS service (ADR-0007 §1).
  final restart = RestartReconciler(
    listWorktrees: git.listBeadWorktrees,
    reapWorktree: git.reap,
    workRoot: workRoot,
    groups: groups,
    freshnessBarrier: freshnessBarrier,
    stateSnapshot: () => state.current ?? emptyGraphSnapshot(),
  );

  final kernel = StationKernel(
    bridge: bridge,
    stationServices: stationServices,
    resolver: resolver,
    substations: substationScopes,
    registry: registry,
    wrapRoot: wrapRoot,
  );

  return TreeRunWiring(
    kernel: kernel,
    restart: restart,
    freshnessBarrier: freshnessBarrier,
  );
}

// ---------------------------------------------------------------------------
// driveStation — banner + pinned start ordering + run loop + teardown
// ---------------------------------------------------------------------------

/// The default resident-station termination binding (D-R2,
/// `docs/SCRATCH-resident-station.md`, ratified 2026-07-02): SIGINT, SIGTERM,
/// and SIGHUP merged into ONE stream. A supervised resident station
/// (`launchctl stop`, plain `kill`) sends SIGTERM — it joins SIGINT on the
/// SAME graceful path; SIGHUP is treated as terminate (no reload semantics
/// yet — not earned).
///
/// Single-subscription: the underlying [ProcessSignal.watch] subscriptions
/// attach on listen and detach on cancel, so a drained station's VM can exit.
Stream<ProcessSignal> terminationSignals() {
  final watched = <StreamSubscription<ProcessSignal>>[];
  late final StreamController<ProcessSignal> controller;
  controller = StreamController<ProcessSignal>(
    onListen: () {
      for (final signal in const [
        ProcessSignal.sigint,
        ProcessSignal.sigterm,
        ProcessSignal.sighup,
      ]) {
        watched.add(signal.watch().listen(controller.add));
      }
    },
    onCancel: () async {
      for (final subscription in watched) {
        await subscription.cancel();
      }
      watched.clear();
    },
  );
  return controller.stream;
}

/// Drives a composed station: prints the banner, starts the controllers + the
/// exploration host, brings the tree up ([TreeRunWiring.start]: barrier →
/// restart → mount), then runs until [StationArgs.runFor] elapses, [runForever]
/// is false (scripted/test: start-then-teardown), or the FIRST termination
/// signal (SIGINT / SIGTERM / SIGHUP — D-R2; [signals] injects a fake stream
/// for tests, defaulting to [terminationSignals]). Returns the process exit
/// code.
///
/// When [sources] carry a state workspace, the STATION LOCK (RS-2, D-A1) is
/// acquired on it before `sources.start()` — ONE supervisor per station state
/// store; a live holder is a [StationRefusal] — and released on the graceful
/// shutdown path and on the start-throw unwind. [lock] injects the service
/// (fake pid probe) for offline tests.
///
/// Under [StationArgs.resident] arming, with a state workspace held, the
/// CONTROL SURFACE (RS-4, D-C2) binds right after the lock (so it always has
/// a lock file to advertise `controlUrl`/`token` through) and is disposed
/// BEFORE the lock releases, on both the graceful path and the start-throw
/// unwind. [controlStarter] injects the bind seam for offline tests.
Future<int> driveStation({
  required TreeRunWiring wiring,
  required StationSources sources,
  required StationArgs args,
  void Function(String)? out,
  bool runForever = true,
  Stream<ProcessSignal>? signals,
  StationLockService? lock,
  StationControlStarter? controlStarter,
}) async {
  final void Function(String) write = out ?? (m) => stdout.writeln(m);

  // --- banner ---------------------------------------------------------------
  write('grid run — the tree engine');
  write(
    'mode: ${args.dryRun ? 'DRY-RUN (observe-only: no real spawns/writes)' : 'LIVE'}  '
    '·  provider: ${args.dryRun ? 'dry' : args.provider.name}  ·  substations: '
    '{${args.substations.join(', ')}}  ·  read path: ${sources.readPathName}',
  );
  if (!args.dryRun) {
    write(
      args.land
          ? 'land: ARMED (on step-complete: commit → push → PR via gh; '
                'NEVER auto-merges)'
          : 'land: OFF (commit-only; landing is a human follow-up — pass '
                '--land to arm)',
    );
  }
  if (sources.stateWorkspace != null) {
    write(
      'state store: ${args.stateWorkspacePath}  ·  session substation: '
      '${args.stateSubstation}',
    );
  }
  if (args.targetBeads.isNotEmpty) {
    write(
      'drive-list (blessed beads): {${args.targetBeads.join(', ')}} '
      '(ENFORCED at the WorkList mount boundary — only these beads mount)',
    );
  } else if (args.resident) {
    write(
      'drive-list: the ready frontier (RESIDENT — RS-3/D-R4; every ready '
      'owned driveable bead mounts, no --bead)',
    );
  } else {
    write(
      'drive-list: none (observing ALL owned dispatchable work — dry-run only)',
    );
  }
  final info = await developer.Service.getInfo();
  final uri = info.serverUri;
  write(
    uri != null
        ? 'VM service: $uri  ·  attach leonard / exploration_cli / devtools here'
        : 'VM service: not enabled — re-run with `dart run --enable-vm-service`',
  );
  write('—' * 64);

  // --- the station lock (RS-2, D-A1): ONE supervisor per state store -------
  // Acquired after validateArming (the caller ran it), before
  // sources.start(). No state workspace (offline/dry with no split store) ⇒
  // no session store to guard ⇒ no lock.
  StationLockHandle? stationLock;
  StationControl? stationControl;
  final stateStore = sources.stateWorkspace;
  if (stateStore != null) {
    final bootTime = DateTime.now();
    stationLock = await (lock ?? StationLockService(log: write)).acquire(
      stateWorkspaceDir: stateStore.root,
      pid: pid,
      pgid: SystemProcessGroupController().currentGroupId(),
      now: bootTime,
    );

    // --- the control surface (RS-4, D-C2): resident mode only ---------------
    // Lock-advertised: bound right after the lock so it always has a lock
    // file to write `controlUrl`/`token` into. A non-resident (`run`) arm
    // never binds it — the drive-list flag surface stays untouched (D-R1).
    if (args.resident) {
      final token = mintControlToken();
      stationControl = await (controlStarter ?? StationControl.start)(
        port: args.controlPort,
        token: token,
        view: () => buildStationStatus(
          args: args,
          sources: sources,
          wiring: wiring,
          startedAt: bootTime,
        ),
      );
      await stationLock.updateControl(
        controlUrl: stationControl.url,
        token: token,
      );
      write(
        'control: ${stationControl.url}  ·  token: (see ${stationLock.path}, '
        '0600)',
      );
    }
  }

  // --- start: controllers → host → barrier → restart → mount ---------------
  try {
    await sources.start();
    await wiring.start();
  } on Object {
    // The start-throw unwind (parity with the refusal-catch
    // `sources?.shutdown()` example above): a lock left naming a dead boot
    // would wedge the next `up` behind a stale-steal. The control surface (if
    // bound) is disposed BEFORE the lock releases (RS-4 scope fence).
    await stationControl?.dispose();
    await stationLock?.release();
    rethrow;
  }

  Future<void> shutdown() async {
    await wiring.teardown();
    await sources.shutdown();
    // The control surface is disposed BEFORE the lock releases (RS-4 scope
    // fence) — a released lock naming a dead control endpoint would mislead
    // `space status`.
    await stationControl?.dispose();
    // Release LAST: the store stays guarded until the tree is torn down and
    // the controllers are drained.
    await stationLock?.release();
  }

  final runFor = args.runFor;
  if (runFor != null) {
    await Future<void>.delayed(runFor);
    await shutdown();
    return 0;
  }
  if (!runForever) {
    await shutdown();
    return 0;
  }

  // Park until the FIRST termination signal; the first completes the interrupt
  // exactly once, later ones are ignored with one loud line (shutdown is never
  // re-entered). The subscription stays live THROUGH shutdown — a repeat signal
  // during teardown is absorbed here instead of default-killing the half-drained
  // process — and is cancelled after, so the VM can exit.
  final interrupt = Completer<void>();
  final termination = (signals ?? terminationSignals()).listen((signal) {
    if (interrupt.isCompleted) {
      write('grid run: already shutting down — $signal ignored');
      return;
    }
    interrupt.complete();
  });
  await interrupt.future;
  write('\ngrid run: shutting down…');
  await shutdown();
  await termination.cancel();
  return 0;
}

// ---------------------------------------------------------------------------
// The dry/live seam impls
// ---------------------------------------------------------------------------

/// The live transport for the tree path (subprocess-first, like M3).
RuntimeProvider _buildTreeProvider(RuntimeProviderKind kind) => switch (kind) {
  RuntimeProviderKind.subprocess => SubprocessProvider(),
  // The tmux adapter is off the critical path; until it lands, the subprocess
  // provider is the only built provider.
  RuntimeProviderKind.tmux => SubprocessProvider(),
};

/// The worktree git service (worktree alloc/list/reap + the land PR opener) over
/// the real `git`/`gh` binaries. Built lazily; the offline suite injects a fake.
StationGitService _buildTreeGitService() => StationGitService(
  runner: SystemGitRunner(),
  prOpener: GhPrOpener(ghRunner),
);

/// The INERT git service for `--dry-run` — a no-op [GitRunner] (every `git`
/// invocation returns an empty success) so `listBeadWorktrees` parses an empty
/// worktree set WITHOUT executing a real `git`, the reconcile finds no survivors
/// (no kill, no reap), and `provisionWorktree` is overridden to touch NO
/// filesystem. The dry run touches nothing live. Exposed for the inertness
/// regression test.
StationGitService buildDryTreeGitService() => _DryStationGitService();

/// The dry-run [StationGitService]: inherits the no-op-runner worktree probe and
/// overrides [provisionWorktree] so a dry run materializes NO worktree (no
/// `mkdir`, no `git worktree add`) — it returns a synthetic descriptor the host
/// ignores. Live provisioning uses the real `StationGitService`.
class _DryStationGitService extends StationGitService {
  _DryStationGitService()
    : super(runner: _DryGitRunner(), prOpener: _DryPrOpener());

  @override
  Future<BeadWorktree> provisionWorktree({
    required RootCheckout root,
    required String beadId,
  }) async => BeadWorktree(
    beadId: beadId,
    path: '${root.path}/.grid/worktrees/${root.substation}/$beadId',
    branch: 'grid/$beadId',
  );
}

/// Execs `gh` for the land PR opener (inherits the parent env so `gh` finds its
/// own auth). Not reached on the early arms (land stays a human follow-up).
Future<GitRunResult> ghRunner(String workDir, List<String> args) async {
  final result = await Process.run('gh', args, workingDirectory: workDir);
  return GitRunResult(
    exitCode: result.exitCode,
    output: '${result.stdout}${result.stderr}',
  );
}

/// A no-op [GitRunner] — every invocation is an empty success; no real `git`
/// runs. The dry-run worktree probe parses this as "no worktrees".
class _DryGitRunner implements GitRunner {
  @override
  Future<GitRunResult> run({
    required String workingDirectory,
    required List<String> args,
  }) async => const GitRunResult(exitCode: 0, output: '');
}

/// A no-op [PrOpener] — never reached in dry-run (land ops are null), but the
/// git service requires one; it opens nothing.
class _DryPrOpener implements PrOpener {
  @override
  Future<PullRequestResult> open({
    required String workDir,
    required String branch,
    required String baseBranch,
    required String title,
    String body = '',
  }) async => PullRequestResult.failed(const PrOpenFailure('dry-run: no PR'));
}

/// An always-empty [SnapshotSource] — the state axis when there is no split
/// state store (a dry run with no `--state-workspace`): no sessions to join.
class EmptySnapshotSource implements SnapshotSource {
  /// Const-constructible.
  const EmptySnapshotSource();

  @override
  Stream<GraphSnapshot> get snapshots => const Stream<GraphSnapshot>.empty();

  @override
  GraphSnapshot? get current => null;
}

/// The DRY-RUN transport: records every would-be spawn, starts no real process,
/// emits no lifecycle events (the mounted tree idles inert). `--dry-run` touches
/// nothing live.
class DryRunProvider implements RuntimeProvider {
  final StreamController<RuntimeEvent> _events =
      StreamController<RuntimeEvent>.broadcast();
  final Set<String> _running = <String>{};

  /// Every (would-be) spawn name, in call order (for the dry-run report).
  final List<String> wouldSpawn = <String>[];

  @override
  Future<void> start(String name, RuntimeConfig config) async {
    if (_running.contains(name)) throw SessionAlreadyExists(name);
    wouldSpawn.add(name);
    _running.add(name);
  }

  @override
  Future<void> stop(String name) async => _running.remove(name);

  @override
  Future<void> interrupt(String name) async {}

  @override
  Stream<RuntimeEvent> get events => _events.stream;

  @override
  Stream<String> output(String name) => const Stream<String>.empty();

  @override
  bool isRunning(String name) => _running.contains(name);

  @override
  bool processAlive(String name) => _running.contains(name);

  @override
  String peek(String name, int lines) => '';

  @override
  List<String> listRunning(String prefix) =>
      _running.where((n) => n.startsWith(prefix)).toList(growable: false);

  @override
  DateTime? lastActivity(String name) => null;

  @override
  RuntimeCapabilities get capabilities => RuntimeCapabilities.subprocess;
}

/// The DRY-RUN bd seam: returns a canned envelope so the engine's session mint
/// runs end-to-end, but issues no real `bd` and touches no store.
class NoOpBdRunner implements BdRunner {
  @override
  Future<BdResult> run(List<String> args, {Duration? timeout, String? stdin}) {
    final sub = args.isNotEmpty ? args.first : '';
    final id = sub == 'create'
        ? 'dry-session'
        : (args.length >= 2 ? args[1] : '');
    return Future<BdResult>.value(
      BdResult(
        exitCode: 0,
        stdout: '{"schema_version":1,"data":{"id":"$id"}}',
        stderr: '',
      ),
    );
  }
}

/// An empty [GraphSnapshot] — the fail-safe the restart reconciler projects
/// cursors from when the state store has no baseline yet (no sessions ⇒ every
/// survivor respawn-pending, never wrongly skipped).
GraphSnapshot emptyGraphSnapshot() => GraphSnapshot.fromParts(
  beads: const [],
  dependencies: const [],
  readyIds: const [],
  capturedAt: DateTime.fromMillisecondsSinceEpoch(0),
);
