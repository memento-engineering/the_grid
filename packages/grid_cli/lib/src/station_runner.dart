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
///   // ONE ServiceBundle per substation (tg-7gm), each built from ITS OWN
///   // registered root (`live.roots`, keyed by registration NAME — a name
///   // equal to a substation id is that substation's default):
///   final services = {
///     for (final e in live.roots.entries)
///       e.key: ServiceBundle(sourceControl: /* the asset's own, over e.value */),
///   };
///   final wiring = composeStation(
///     work: sources.work, state: sources.state,
///     stationServices: live.stationServices, substations: [...],
///     git: live.git, workRoot: live.workRoot, groups: live.groups,
///     freshnessBarrier: live.freshnessBarrier,
///     // Adopt-across-restart (ADR-0009 D4) is ALL-OR-NOTHING: `--adopt`
///     // arms BOTH halves off ONE ProcessGroupController — the reconciler's
///     // `live.adoptProof` (leave a proven survivor running, pre-mount) and
///     // `live.stationServices.liveness` (reattach it at mount). Thread the
///     // proof through as-is; never wire one half alone (it double-runs).
///     adoptProof: live.adoptProof,
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
import 'package:beads_dart/beads_dart.dart';
import 'package:grid_engine/grid_engine.dart';
import 'package:grid_exploration/grid_exploration.dart';
import 'package:grid_runtime/grid_runtime.dart';

import 'runtime_snapshot_source.dart';
import 'station_control.dart';
import 'station_lock.dart';

// ---------------------------------------------------------------------------
// RuntimeProviderKind
// ---------------------------------------------------------------------------

/// Which [RuntimeProvider] a composed station spawns agents through.
enum RuntimeProviderKind {
  /// The Friday dogfood default — [SubprocessProvider].
  subprocess,

  /// The gc-compatible alternative — `TmuxProvider` (Track 1; not on the
  /// Friday critical path). The subprocess arm ships; the tmux arm is
  /// reserved.
  tmux;

  /// Parses the `--provider` option value (defaults to [subprocess]).
  static RuntimeProviderKind parse(String? value) => switch (value) {
    'tmux' => RuntimeProviderKind.tmux,
    _ => RuntimeProviderKind.subprocess,
  };
}

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
///
/// **Mirror-drift note (tg-7gm r2):** `space_station`'s `up` command
/// hand-mirrors this flag surface (its OWN `ArgParser`, not a call through
/// here — it lives in a sibling repo this worktree cannot reach), most
/// recently missing this function's `--root` grammar change (bare →
/// repeatable `<name>=<path>[@head]`). Bringing that mirror back in sync is
/// deliberately its OWN bead — not attempted here.
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
    ..addMultiOption(
      'root',
      help:
          'A registered worktree root checkout (repeatable, tg-7gm): '
          '`--root <name>=<path>[@head]` registers <path> under <name> — a '
          'name equal to an owned --substation becomes that substation\'s '
          'DEFAULT root; any OTHER name is an EXTRA root a bead opts into via '
          'its `metadata.grid.root` (e.g. a `tg` bead building `power_station` '
          'names `--root power_station=<path>` + `grid.root: power_station`). '
          'Bare `--root <path>` (no `=`) is the single-root shorthand — '
          'back-compatible: registers under the first --substation. At least '
          'one is required to ARM a non-dry run; never created by the runner.',
    )
    ..addOption(
      'head',
      help:
          'ASSIGN the base branch per-bead worktrees cut from for any --root '
          'entry that does not carry its own @head, overriding the probed '
          'origin/HEAD. Omit to probe.',
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
    ..addFlag(
      'adopt',
      negatable: false,
      help:
          'ARM adopt-across-restart (ADR-0009 D4): the restart reconciler '
          'LEAVES a proven survivor running and the Host REATTACHES it at '
          'mount — BOTH halves wired from one ProcessGroupController, or '
          'neither (all-or-nothing; one alone double-runs). LIVE only; '
          'refused with --dry-run.',
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

/// One named root registration (tg-7gm, `docs/SCRATCH-grid-alignment.md` §6
/// amendment): the checkout [path] plus an optional per-root [head] override
/// (`--root <name>=<path>@<head>`). A root registered under a NAME equal to an
/// owned `--substation` becomes that substation's DEFAULT root; any OTHER name
/// is an EXTRA root a bead opts into via `metadata.grid.root`.
class RootSpec {
  /// Creates a root registration for [path], optionally pinning [head].
  const RootSpec({required this.path, this.head});

  /// The registered worktree root checkout path.
  final String path;

  /// The per-root ASSIGNED head (from `@head`); null falls back to the global
  /// `--head` (if any), else probed from `origin/HEAD` at registration.
  final String? head;

  /// Parses one `--root` value: `<name>=<path>[@head]`, or a bare `<path>`
  /// (the single-root shorthand — registered under [defaultName]). Throws
  /// [FormatException] on a malformed registration (an explicit empty name,
  /// or an empty path).
  static MapEntry<String, RootSpec> parse(
    String raw, {
    required String defaultName,
  }) {
    final eq = raw.indexOf('=');
    if (eq < 0) {
      if (raw.trim().isEmpty) {
        throw FormatException('grid run: malformed --root "$raw" — empty path');
      }
      return MapEntry(defaultName, RootSpec(path: raw));
    }
    final name = raw.substring(0, eq);
    final rest = raw.substring(eq + 1);
    if (name.trim().isEmpty) {
      throw FormatException(
        'grid run: malformed --root "$raw" — empty name before "="',
      );
    }
    if (rest.trim().isEmpty) {
      throw FormatException(
        'grid run: malformed --root "$raw" — empty path after "="',
      );
    }
    final at = rest.lastIndexOf('@');
    final path = at < 0 ? rest : rest.substring(0, at);
    final head = at < 0 ? null : rest.substring(at + 1);
    return MapEntry(
      name,
      RootSpec(path: path, head: (head == null || head.isEmpty) ? null : head),
    );
  }

  @override
  bool operator ==(Object other) =>
      other is RootSpec && other.path == path && other.head == head;

  @override
  int get hashCode => Object.hash(path, head);

  @override
  String toString() => 'RootSpec($path${head != null ? '@$head' : ''})';
}

/// The parsed standard station inputs — a plain value an asset runner builds
/// from its [ArgResults] (or constructs directly in a test).
class StationArgs {
  /// Creates the parsed inputs.
  const StationArgs({
    required this.substations,
    this.provider = RuntimeProviderKind.subprocess,
    Map<String, RootSpec> roots = const <String, RootSpec>{},
    @Deprecated(
      'Reinstated ONLY as a back-compat alias (tg-7gm rework r2) so a caller '
      'still constructing `StationArgs(rootPath: ...)` (e.g. '
      "space_station's `up_command`) compiles unchanged until it migrates. "
      'Use `roots` (`--root <name>=<path>`) for new code — see the [roots] '
      'getter doc for the fold.',
    )
    String? rootPath,
    this.head,
    this.workspacePath,
    this.stateWorkspacePath,
    this.stateSubstation,
    this.targetBeads = const {},
    this.dryRun = true,
    this.land = false,
    this.adopt = false,
    this.noSql = false,
    this.runFor,
    this.resident = false,
    this.controlPort = 0,
  }) : _roots = roots,
       _rootPath = rootPath;

  /// Parses the standard flags added by [addStationFlags]. Throws
  /// [FormatException] on a malformed/duplicate `--root` registration (the
  /// same class of error `int.parse` below already raises for a malformed
  /// `--control-port`/`--for-seconds`).
  factory StationArgs.from(ArgResults args) {
    final seconds = args.option('for-seconds');
    final substations = <String>{
      ...args.multiOption('substation'),
      ...args.multiOption('owner'),
    }..removeWhere((r) => r.trim().isEmpty);
    final roots = <String, RootSpec>{};
    for (final raw in args.multiOption('root')) {
      if (raw.trim().isEmpty) continue;
      final entry = RootSpec.parse(
        raw,
        defaultName: substations.isNotEmpty ? substations.first : '',
      );
      if (roots.containsKey(entry.key)) {
        throw FormatException(
          'grid run: --root "$raw" registers name "${entry.key}" more than once',
        );
      }
      roots[entry.key] = entry.value;
    }
    return StationArgs(
      substations: substations,
      provider: RuntimeProviderKind.parse(args.option('provider')),
      roots: roots,
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
      adopt: args.flag('adopt'),
      noSql: args.flag('no-sql'),
      runFor: seconds == null ? null : Duration(seconds: int.parse(seconds)),
      controlPort: int.parse(args.option('control-port')!),
    );
  }

  /// The ownership allow-set (work substations).
  final Set<String> substations;

  /// The runtime provider kind for agent spawns.
  final RuntimeProviderKind provider;

  final Map<String, RootSpec> _roots;
  final String? _rootPath;

  /// The registered worktree roots (tg-7gm), keyed by registration NAME — a
  /// name equal to an owned substation is that substation's DEFAULT root; any
  /// other name is an EXTRA root a bead opts into via `metadata.grid.root`.
  /// At least one entry is required to arm a live run.
  ///
  /// Folds the deprecated [rootPath] alias in under the FIRST substation's
  /// name (or `''` when [substations] is empty) — but only when non-null AND
  /// no explicit `roots` entry already claims that name (an explicit
  /// registration always wins). This reproduces the pre-tg-7gm single-root
  /// shape exactly, so a caller still constructing `StationArgs(rootPath:
  /// ...)` behaves as it did before the multi-root rework.
  Map<String, RootSpec> get roots {
    final legacy = _rootPath;
    if (legacy == null) return _roots;
    final name = substations.isNotEmpty ? substations.first : '';
    if (_roots.containsKey(name)) return _roots;
    return {..._roots, name: RootSpec(path: legacy)};
  }

  /// DEPRECATED (tg-7gm rework r2) — the single legacy root path, reinstated
  /// only as a back-compat alias over [roots] (see its doc for the fold).
  @Deprecated('Use `roots` (`--root <name>=<path>`).')
  String? get rootPath => _rootPath;

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

  /// Whether adopt-across-restart is armed (ADR-0009 D4, live only) — BOTH
  /// halves (the reconciler's `AdoptProof` + the Host's `AllocationLiveness`)
  /// or neither; see [buildLiveWiring].
  final bool adopt;

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
  if (args.adopt && args.dryRun) {
    throw const StationRefusal(
      'grid run: --adopt cannot be combined with --dry-run. Adopt reattaches '
      'REAL surviving processes across a controller restart (ADR-0009 D4); a '
      'dry run touches nothing. Re-run with --no-dry-run to arm adopt, or '
      'drop --adopt to observe only.',
    );
  }
  if (!args.dryRun && args.roots.isEmpty && !rootInjected) {
    throw const StationRefusal(
      'grid run: a non-dry (live) run requires --root (at least one '
      'registered worktree root under engineering.memento; repeatable — '
      'tg-7gm). Re-run with --dry-run (the default) to observe only, or pass '
      '--root to ARM the writing arm. Which OWNED substations actually need '
      'one is a MOUNT-BOUNDARY concern (a LOUD per-bead skip), not this gate.',
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
    required this.roots,
    required this.groups,
    required this.freshnessBarrier,
    this.gitOps,
    this.prOpener,
    this.adoptProof,
  });

  /// The station-level ambient services (transport + chokepoint + state rig).
  final StationServices stationServices;

  /// The shared git execution machinery (worktree alloc/list/reap) the
  /// substation leases (ADR-0008 D5) — inert in dry-run.
  final StationGitService git;

  /// THE single-root consumer's registered root (`RestartReconciler` — D-M6
  /// restart fan-out over N roots is a deferred follow-up): [roots] entry for
  /// `args.substations.first`, falling back to whichever root registered,
  /// falling back to a dry-run synthetic when none did.
  final RootCheckout workRoot;

  /// EVERY registered root, keyed by its registration NAME (tg-7gm) — EMPTY
  /// when no `--root` was wired (dry-run's unconstrained default; matches
  /// [StationArgs.roots] being empty). The asset builds ONE [ServiceBundle]
  /// per substation from this map (its own name's entry is that substation's
  /// default; any OTHER entry is an extra root a bead opts into via
  /// `metadata.grid.root`) and threads this map's key SET into each
  /// `SubstationConfig.registeredRoots` so `WorkList`'s mount-boundary gate
  /// can validate a bead's selection.
  final Map<String, RootCheckout> roots;

  /// The process-group controller (the orphan-kill seam — REAL even offline so
  /// its `pgid <= 1` guard is exercised).
  final ProcessGroupController groups;

  /// The completed-re-query freshness barrier (ADR-0007 §4).
  final Future<void> Function() freshnessBarrier;

  /// Land ops — non-null ONLY when `--land` armed a live run (ADR-0006 D3).
  final GitOps? gitOps;

  /// The PR opener — non-null ONLY when `--land` armed a live run.
  final PrOpener? prOpener;

  /// The reconciler adopt half (ADR-0009 D4) — non-null ONLY when `--adopt`
  /// armed a live run, and then ALWAYS built off the SAME [groups] controller
  /// as [stationServices]' `liveness` (the Host adopt half): all-or-nothing,
  /// wiring one half alone double-runs. The asset's runner threads this into
  /// `composeStation(adoptProof:)` as-is.
  final AdoptProof? adoptProof;
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
  Map<String, RootCheckout>? rootsOverride,
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

  // The worktree git service + EVERY registered root (tg-7gm). Dry-run gets
  // an INERT service (no real `git` — the restart probe parses an empty
  // worktree set).
  final git =
      gitServiceOverride ??
      (args.dryRun ? buildDryTreeGitService() : _buildTreeGitService());
  final Map<String, RootCheckout> roots;
  if (rootsOverride != null) {
    roots = rootsOverride;
  } else if (args.roots.isEmpty) {
    // No --root at all: UNCONSTRAINED (a live run is already refused upstream
    // by validateArming; this is dry-run's ordinary shape). An EMPTY map here
    // means an EMPTY `SubstationConfig.registeredRoots` — the WorkList
    // mount-boundary gate stays inert, matching pre-multi-root behavior.
    roots = const {};
  } else {
    final registered = <String, RootCheckout>{};
    for (final entry in args.roots.entries) {
      if (args.dryRun) {
        // A dry-run with EXPLICIT --root flags still exercises the per-bead
        // matching logic (WorkList's gate) — SYNTHETIC, so nothing real git
        // touches (dry-run touches nothing live).
        registered[entry.key] = RootCheckout(
          path: '',
          defaultBranch: 'main',
          substation: entry.key,
        );
        continue;
      }
      try {
        registered[entry.key] = await git.registerRootCheckout(
          path: entry.value.path,
          substation: entry.key,
          // Assign-head: cut per-bead worktrees off this branch (e.g. the_grid's
          // own feature branch) instead of the probed origin/HEAD. A per-root
          // `@head` wins; null falls back to the global `--head`; both null ⇒
          // probe.
          head: entry.value.head ?? args.head,
        );
      } on Object catch (e) {
        throw StationRefusal(
          'grid run: could not register root "${entry.key}"='
          '"${entry.value.path}": $e',
          code: 1,
        );
      }
    }
    roots = registered;
  }

  // THE single-root consumer's root (RestartReconciler, D-M6 restart fan-out
  // deferred): the DEFAULT for `args.substations.first`, falling back to
  // whichever root registered, falling back to a dry-run synthetic when none
  // did — independent of whether [roots] itself stays empty (unconstrained).
  final RootCheckout root =
      (args.substations.isNotEmpty ? roots[args.substations.first] : null) ??
      (roots.isNotEmpty ? roots.values.first : null) ??
      RootCheckout(
        path: '',
        defaultBranch: 'main',
        substation: args.substations.isNotEmpty ? args.substations.first : '',
      );

  // Land ops are wired ONLY when --land armed a live run (ADR-0006 D3); they
  // flow into the ASSET's SourceControl, never through the station services.
  // Null ⇒ `canLand` false ⇒ land no-ops (the commit-only posture).
  final bool armLand = args.land && !args.dryRun;
  final gitOps = armLand ? GitOps(SystemGitRunner()) : null;
  final prOpener = armLand ? GhPrOpener(ghRunner) : null;

  // Adopt-across-restart (ADR-0009 D4) — TWO cooperating halves, co-wired
  // ALL-OR-NOTHING off the SAME [groups] controller: the reconciler's
  // [AdoptProof] LEAVES a proven survivor running (pre-mount), and the Host's
  // [AllocationLiveness] REATTACHES it at mount (via `StationServices.liveness`).
  // Arming one half alone double-runs (the reconciler leaves a survivor AND the
  // Host, unable to prove liveness, spawns fresh) — see the
  // `AllocationContext.liveness` doc. Unarmed (the default), BOTH stay at their
  // offline never-adopt defaults. Live-only: `validateArming` refuses
  // --adopt + --dry-run; mirroring the `armLand` guard keeps this fail-closed
  // even for a caller that skipped validation.
  final groups = groupsOverride ?? const SystemProcessGroupController();
  final bool armAdopt = args.adopt && !args.dryRun;
  final AllocationLiveness? liveness = armAdopt
      ? (fence) => _fenceAlive(groups, pgid: fence.pgid, pid: fence.pid)
      : null;
  final AdoptProof? adoptProof = armAdopt
      ? (worktree, session, nodePath, node) async =>
            _fenceAlive(groups, pgid: node.pgid, pid: node.pid)
      : null;

  // Station-level ambient only (ADR-0009 D2): transport + chokepoint + state
  // rig. The workspace/branch layout is the per-substation SourceControl's.
  final stationServices = StationServices(
    provider: runtimeProvider,
    writer: writer,
    stateSubstation: (stateSubstation != null && stateSubstation.isNotEmpty)
        ? stateSubstation
        : args.substations.first,
    liveness: liveness,
  );

  return StationWiring(
    stationServices: stationServices,
    git: git,
    workRoot: root,
    roots: roots,
    groups: groups,
    freshnessBarrier: freshnessBarrierOverride ?? sources.requery,
    gitOps: gitOps,
    prOpener: prOpener,
    adoptProof: adoptProof,
  );
}

/// The engine pgid/pid-alive probe BOTH adopt halves share (ADR-0009 D4): true
/// iff the prior identity is COMPLETE — a recorded [pgid] AND leader [pid] (see
/// `AdoptFence`) — and the leader pid still names a live process
/// ([ProcessGroupController.processAlive], the same liveness subject the
/// guarded `terminateGroup` polls). A partial identity fails closed
/// (no-adopt-on-faith: an unprovable survivor is killed-and-respawned, never
/// left to leak). The domain half — token echoed over the effect's own
/// endpoint — stays the capability's `proveFreshness`, run by the Host at
/// mount on top of this engine half.
bool _fenceAlive(ProcessGroupController groups, {int? pgid, int? pid}) =>
    pgid != null && pid != null && groups.processAlive(pid);

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
/// [StationWiring] — the composition inversion, 2026-07-02), KEYED BY
/// [SubstationConfig.substationId] — tg-7gm: each substation gets ITS OWN
/// bundle (a missing entry defaults to an empty [ServiceBundle], exactly the
/// prior single-bundle default), so two substations run against isolated
/// source control instead of one shared instance. [wrapRoot] is the asset's
/// provider hook (its `main()` mounts station-default config values —
/// `InheritedSeed<AgentConfig>`-style — as ancestors of everything).
///
/// [adoptProof] is a composition PASSTHROUGH into the [RestartReconciler]
/// (null ⇒ its never-adopt default). It is one half of the ALL-OR-NOTHING
/// adopt-across-restart pair (ADR-0009 D4) — thread `StationWiring.adoptProof`
/// through together with the [stationServices]' `liveness` half, or neither
/// (`--adopt` in [buildLiveWiring] arms both off one controller).
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
  Map<String, ServiceBundle> services = const {},
  Seed Function(Seed root)? wrapRoot,
  AdoptProof? adoptProof,
}) {
  final bridge = StationJoinBridge(work: work, state: state);

  // One config scope per substation, keyed by id so an add/remove mounts /
  // unmounts exactly that scope. The asset's OWN bundle is provided AT THE
  // SCOPE (ADR-0008 D5: source control is a per-substation responsibility;
  // tg-7gm: no longer ONE bundle shared across every scope).
  final substationScopes = substations
      .map(
        (config) => SubstationScope(
          configNotifier: SubstationConfigNotifier(config),
          services: services[config.substationId] ?? const ServiceBundle(),
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
    adoptProof: adoptProof,
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
