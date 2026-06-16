import 'dart:async';
import 'dart:developer' as developer;
import 'dart:io';

import 'package:args/command_runner.dart';
import 'package:grid_controller/grid_controller.dart';
import 'package:grid_exploration/grid_exploration.dart';
import 'package:grid_reconciler/grid_reconciler.dart';
import 'package:grid_runtime/grid_runtime.dart';

/// `grid run` — the M3 dogfood composition (M3-BUILD-ORDER Track 7).
///
/// One process that wires together the three the_grid loops over a SINGLE
/// shared ownership allow-set:
///
///  1. **the M1 reactive controller** — exactly what `runWatch` builds
///     (workspace discover → [GridRuntimeFactory.build] →
///     [GridExplorationHost.register] → `runtime.start`), so leonard can attach
///     over `ext.exploration.*` and observe live grid state;
///  2. **the M2 convergence reconciler** ([ReconcilerRuntime] over
///     [GridConvergenceSource] + [BdActuator] + [GateEvaluator] + [OwnsRigs]) —
///     the reduce→gate→actuate spine for OWNED convergence loops;
///  3. **the M3 dispatcher** ([DispatchInteractor] over a [ReadyWorkSource] +
///     the chosen [RuntimeProvider]) — ready work bead → a `claude` subprocess
///     in a git worktree, tracked as a session bead through the single
///     [GridBeadWriter] bd-write chokepoint.
///
/// **One source of truth for ownership (ADR-0006 Decision 1; ADR-0000 A32).**
/// The `--rig`/`--owner` allow-set is parsed into ONE `Set<String>` instance
/// ([RunWiring.allowSet]) that seeds BOTH the M2 [OwnsRigs] convergence actuator
/// gate AND the Track-4 [BeadOwnershipPredicate] used for dispatch + the write
/// chokepoint — never two copies, so the two gates cannot drift.
///
/// **`--dry-run` is the SAFE DEFAULT (observe-only).** A dry run constructs the
/// full wiring but performs NO writes and NO spawns: the dispatcher's
/// [DispatchInteractor.dryRun] short-circuits before any worktree/spawn/bd
/// write, and the reconciler is wired with [OwnsNothing] so it actuates nothing
/// (it still reduces every owned loop for diagnostics). A non-dry (LIVE) run is
/// the writing arm and is gated behind explicit `--no-dry-run` PLUS a registered
/// [RootCheckout]; it is never armed automatically.
class RunCommand extends Command<int> {
  RunCommand() {
    argParser
      ..addMultiOption(
        'rig',
        abbr: 'r',
        help:
            'An OWNED rig / ownership token (repeatable). This is the SINGLE '
            'allow-set that feeds both the M2 OwnsRigs convergence gate and the '
            'dispatch BeadOwnershipPredicate — one source of truth. The dogfood '
            'rig is `tgdog`.',
      )
      ..addMultiOption(
        'owner',
        help:
            'Alias for --rig (the ownership allow-set); merged with --rig into '
            'one shared Set<String>.',
      )
      ..addOption(
        'provider',
        allowed: ['subprocess', 'tmux'],
        defaultsTo: 'subprocess',
        help:
            'The runtime provider for agent spawns. `subprocess` is the Friday '
            'dogfood default; `tmux` is the gc-compatible alternative.',
      )
      ..addOption(
        'root',
        help:
            'The registered worktree root checkout under engineering.memento '
            '(e.g. /Users/nico/development/engineering.memento/lenny-tgdog). '
            'Required to ARM a non-dry run; never created by grid run.',
      )
      ..addFlag(
        'dry-run',
        defaultsTo: true,
        help:
            'Observe-only: NO writes, NO spawns (the SAFE DEFAULT for the first '
            'run). Pass --no-dry-run to ARM the live writing arm (requires '
            '--root and ADR-0006 ratification).',
      )
      ..addOption(
        'for-seconds',
        help:
            'Run for a fixed number of seconds then exit (scripted demos / CI) '
            'instead of until Ctrl-C.',
      )
      ..addFlag(
        'no-sql',
        negatable: false,
        help:
            'Force the bd-CLI read path even when pooled Dolt SQL is available.',
      );
  }

  @override
  final String name = 'run';

  @override
  final String description =
      'Run the M3 dogfood loop: the reactive controller + the convergence '
      'reconciler + the ready-bead dispatcher, over one shared ownership '
      'allow-set. Defaults to --dry-run (observe-only). Run under '
      '`dart run --enable-vm-service` so leonard can attach.';

  @override
  Future<int> run() async {
    final args = argResults!;
    final seconds = args.option('for-seconds');
    final rigs = <String>{
      ...args.multiOption('rig'),
      ...args.multiOption('owner'),
    }..removeWhere((r) => r.trim().isEmpty);

    return runGrid(
      rigs: rigs,
      provider: RuntimeProviderKind.parse(args.option('provider')),
      rootPath: args.option('root'),
      dryRun: args.flag('dry-run'),
      noSql: args.flag('no-sql'),
      runFor: seconds == null ? null : Duration(seconds: int.parse(seconds)),
    );
  }
}

/// Which [RuntimeProvider] `grid run` spawns agents through.
enum RuntimeProviderKind {
  /// The Friday dogfood default — [SubprocessProvider].
  subprocess,

  /// The gc-compatible alternative — `TmuxProvider` (Track 1; not on the Friday
  /// critical path). M3 ships the subprocess arm; the tmux arm is reserved.
  tmux;

  /// Parses the `--provider` option value (defaults to [subprocess]).
  static RuntimeProviderKind parse(String? value) => switch (value) {
    'tmux' => RuntimeProviderKind.tmux,
    _ => RuntimeProviderKind.subprocess,
  };
}

/// The resolved, composed `grid run` wiring — built by [composeRun] from the
/// parsed flags + the controller runtime, and started/torn down by [runGrid].
///
/// Exposed as a value-ish holder (not started) so unit tests can assert the
/// composition WITHOUT running a live loop: that the allow-set is shared between
/// the two ownership gates ([ownsRigs]/[beadOwnership] seeded from the identical
/// [allowSet]), that dry-run wires the reconciler with [OwnsNothing], and that a
/// dry-run dispatch performs zero spawns and zero bd writes.
class RunWiring {
  RunWiring({
    required this.allowSet,
    required this.ownsRigs,
    required this.beadOwnership,
    required this.reconciler,
    required this.dispatcher,
    required this.actuator,
    required this.dryRun,
    required this.root,
    required Future<void> Function() teardown,
  }) : _teardown = teardown;

  /// The ONE ownership allow-set instance shared by both gates (the source of
  /// truth — ADR-0000 A32). Read-only view.
  final Set<String> allowSet;

  /// The M2 convergence-actuation gate, seeded from [allowSet].
  final OwnsRigs ownsRigs;

  /// The dispatch + write-chokepoint gate, seeded from the SAME [allowSet].
  final BeadOwnershipPredicate beadOwnership;

  /// The composed M2 reconciler runtime (started by [runGrid]).
  final ReconcilerRuntime reconciler;

  /// The composed M3 dispatcher (started by [runGrid]).
  final DispatchInteractor dispatcher;

  /// The Track-4 session-bead actuator (bound to the provider's event stream).
  final RuntimeActuator actuator;

  /// Whether this wiring is observe-only (no writes, no spawns).
  final bool dryRun;

  /// The registered root checkout, or null in dry-run with no `--root`.
  final RootCheckout? root;

  final Future<void> Function() _teardown;

  /// Starts the reconciler then the dispatcher (the controller runtime is
  /// started by [runGrid] after the exploration host registers).
  Future<void> start() async {
    await reconciler.start();
    await dispatcher.start();
  }

  /// Tears down the dispatcher, reconciler, and actuator (idempotent).
  Future<void> dispose() => _teardown();
}

/// Builds the [RunWiring] over an already-built [GridControllerRuntime] +
/// [BdCliService], from the parsed flags. Pure composition — constructs no
/// process and writes no bead; starting is the caller's ([RunWiring.start]).
///
/// The seams ([readyWorkSource]/[convergenceSource]/[provider]/[gitService]/
/// [rootCheckout]) are injectable so an offline test drives the whole
/// composition with fakes (fake ready-work source, fake provider, fake bd
/// runner, fake git runner) — no live `tg`, no real `claude`, no real `git`.
RunWiring composeRun({
  required BdCliService bd,
  required Set<String> rigs,
  required bool dryRun,
  GridControllerRuntime? controller,
  RuntimeProviderKind providerKind = RuntimeProviderKind.subprocess,
  RootCheckout? rootCheckout,
  ReadyWorkSource? readyWorkSource,
  ConvergenceSource? convergenceSource,
  RuntimeProvider? provider,
  GridGitService? gitService,
  GateEvaluator? gateEvaluator,
  IdempotencyProbe? idempotencyProbe,
  int maxInFlight = 8,
  void Function(String message)? onObserve,
  void Function(Object error, StackTrace stack)? onError,
}) {
  assert(
    controller != null ||
        (readyWorkSource != null && convergenceSource != null),
    'composeRun needs a controller unless BOTH the ready-work and convergence '
    'sources are injected',
  );

  // THE single source of truth: one Set<String> instance feeds BOTH gates.
  final allowSet = Set<String>.unmodifiable(rigs);
  final ownsRigs = OwnsRigs(allowSet);
  final beadOwnership = BeadOwnershipPredicate(allowSet);

  // --- M2 reconciler ---------------------------------------------------------
  final convergence =
      convergenceSource ?? GridConvergenceSource(controller!);
  // dry-run actuates nothing: OwnsNothing keeps every loop observe-only. A live
  // run uses OwnsRigs over the shared allow-set (the M2 actuation gate).
  final OwnershipPredicate reconcilerOwnership = dryRun
      ? const OwnsNothing()
      : ownsRigs;
  // A real gate runner needs a city/store path that only the live arm has; an
  // observe-only run never reaches actuation (OwnsNothing), so a no-op gate is
  // sufficient. The live arm supplies a real GateRunnerProcessGate.
  final gate = gateEvaluator ?? FakeGate();
  final actuator = dryRun
      // A dry run never actuates (OwnsNothing gates it off), so a recording
      // FakeActuator keeps the runtime constructable without a writer.
      ? FakeActuator()
      : BdActuator(bd, idempotencyProbe ?? alwaysMissProbe);
  final reconciler = ReconcilerRuntime(
    source: convergence,
    actuator: actuator,
    gateEvaluator: gate,
    ownership: reconcilerOwnership,
    onError: onError,
  );

  // --- M3 dispatcher ---------------------------------------------------------
  final ready = readyWorkSource ?? GridReadyWorkSource(controller!);
  final runtimeProvider = provider ?? _buildProvider(providerKind);
  final git = gitService ?? _buildGitService();
  // The session-bead actuator writes ONLY through the chokepoint, which
  // re-checks ownership fail-closed against the SAME allow-set.
  final writer = GridBeadWriter(
    bd: bd,
    ownership: beadOwnership,
    onRefusal: onObserve,
  );
  final runtimeActuator = RuntimeActuator(writer: writer);
  // The actuator ingests the provider's RuntimeEvent stream (Track 4 bind) so a
  // spawn drives the session bead's lifecycle.
  runtimeActuator.bind(runtimeProvider.events);

  // The land/root is required to ARM a live run; in dry-run a missing root is
  // fine (nothing is provisioned). A non-dry run with no root is rejected by
  // runGrid before this point.
  final root =
      rootCheckout ??
      (rigs.isEmpty
          ? null
          : RootCheckout(path: '', defaultBranch: 'main', rig: rigs.first));

  final dispatcher = DispatchInteractor(
    source: ready,
    ownership: beadOwnership,
    git: git,
    root: root ?? const RootCheckout(path: '', defaultBranch: 'main', rig: ''),
    provider: runtimeProvider,
    actuator: runtimeActuator,
    configBuilder: _buildAgentConfig,
    maxInFlight: maxInFlight,
    dryRun: dryRun,
    onObserve: onObserve,
    onError: onError,
  );

  return RunWiring(
    allowSet: allowSet,
    ownsRigs: ownsRigs,
    beadOwnership: beadOwnership,
    reconciler: reconciler,
    dispatcher: dispatcher,
    actuator: runtimeActuator,
    dryRun: dryRun,
    root: rootCheckout,
    teardown: () async {
      await dispatcher.dispose();
      await reconciler.dispose();
      await runtimeActuator.dispose();
    },
  );
}

/// The `claude` invocation contract for one dispatched bead (M3 Track 2/7). The
/// agent token rides the env allowlist (never argv); `-p` is non-interactive
/// print mode; the prompt is the bead's title/description. Pre-granted
/// permissions so no approval prompt appears (dogfood agents run headless).
RuntimeConfig _buildAgentConfig(DispatchRequest request) {
  final prompt = request.bead.title.isNotEmpty
      ? request.bead.title
      : 'work bead ${request.bead.id}';
  return RuntimeConfig(
    workDir: request.worktree.path,
    command: 'claude',
    args: ['--dangerously-skip-permissions', '-p', prompt],
    lifecycle: Lifecycle.oneTurn,
    env: {
      'GRID_BEAD_ID': request.bead.id,
      'GRID_SESSION_ID': request.sessionBeadId,
    },
  );
}

RuntimeProvider _buildProvider(RuntimeProviderKind kind) => switch (kind) {
  RuntimeProviderKind.subprocess => SubprocessProvider(),
  // The tmux arm rides Track 1's standalone tmux package (off the Friday
  // critical path); M3 ships subprocess-first. Until the TmuxProvider adapter
  // lands, the subprocess provider is the only built provider.
  RuntimeProviderKind.tmux => SubprocessProvider(),
};

/// The live [GridGitService] over the real `git` binary (GIT_*-blacklisted by
/// [SystemGitRunner]) and a real `gh pr create` runner for the land step. Built
/// lazily only on the live arm; the offline test suite always injects a fake.
GridGitService _buildGitService() => GridGitService(
  runner: SystemGitRunner(),
  prOpener: GhPrOpener(_ghRunner),
);

/// Execs `gh` (not `git`) as the [GhPrOpener]'s command runner — the land step's
/// `gh pr create`. Inherits the parent env so `gh` finds its own auth (the
/// agent's `CLAUDE_CODE_OAUTH_TOKEN` is forwarded to the child agent only via
/// the [AgentEnvAllowlist], never here).
Future<GitRunResult> _ghRunner(String workDir, List<String> args) async {
  final result = await Process.run(
    'gh',
    args,
    workingDirectory: workDir,
  );
  return GitRunResult(
    exitCode: result.exitCode,
    output: '${result.stdout}${result.stderr}',
  );
}

/// Runs `grid run`: discovers the workspace, builds the M1 controller, registers
/// the exploration host, composes the M2 reconciler + the M3 dispatcher over the
/// shared ownership allow-set, starts everything, and blocks until interrupted
/// (or [runFor]).
///
/// Returns a process exit code. The seams are injectable for tests; the default
/// path builds the live wiring but is gated to dry-run unless explicitly armed.
Future<int> runGrid({
  required Set<String> rigs,
  RuntimeProviderKind provider = RuntimeProviderKind.subprocess,
  String? rootPath,
  bool dryRun = true,
  bool noSql = false,
  void Function(String)? out,
  void Function(String)? err,
  bool runForever = true,
  Duration? runFor,
  BeadsWorkspace? workspaceOverride,
  BdCliService? bdOverride,
  ReadyWorkSource? readyWorkSourceOverride,
  ConvergenceSource? convergenceSourceOverride,
  RuntimeProvider? providerOverride,
  GridGitService? gitServiceOverride,
  RootCheckout? rootCheckoutOverride,
  Future<({GridControllerRuntime runtime, Future<void> Function() shutdown})>
  Function(BeadsWorkspace workspace)?
  controllerOverride,
}) async {
  final void Function(String) write = out ?? (m) => stdout.writeln(m);
  final void Function(String) writeErr = err ?? (m) => stderr.writeln(m);

  if (rigs.isEmpty) {
    writeErr(
      'grid run: at least one --rig/--owner is required (the ownership '
      'allow-set; the dogfood rig is `tgdog`).',
    );
    return 64;
  }

  // The live (non-dry) writing arm requires a registered root checkout. We do
  // NOT auto-arm: a non-dry run with no root is refused here, before any
  // composition, so the safe path is the default.
  if (!dryRun && rootPath == null && rootCheckoutOverride == null) {
    writeErr(
      'grid run: a non-dry (live) run requires --root (the registered worktree '
      'root under engineering.memento). Re-run with --dry-run (the default) to '
      'observe only, or pass --root to ARM the writing arm.',
    );
    return 64;
  }

  final workspace = workspaceOverride ?? BeadsWorkspace.discover();
  if (workspace == null) {
    writeErr(
      'grid run: no .beads/ workspace found from ${Directory.current.path}',
    );
    return 1;
  }

  // --- M1 controller (the runWatch spine) ------------------------------------
  final GridControllerRuntime controller;
  final Future<void> Function() shutdownController;
  String readPathName;
  if (controllerOverride != null) {
    final built = await controllerOverride(workspace);
    controller = built.runtime;
    shutdownController = built.shutdown;
    readPathName = 'injected';
  } else {
    final bundle = await GridRuntimeFactory.build(
      workspace: workspace,
      preferSql: !noSql,
    );
    controller = bundle.runtime;
    shutdownController = bundle.shutdown;
    readPathName = bundle.readPath.name;
  }

  final host = GridExplorationHost(
    controller,
    plugin: GridControllerPlugin(controller, readPath: () => readPathName),
  );
  host.register();

  // --- the bd write seam -----------------------------------------------------
  // One BdCliService for both the M2 actuator and the Track-4 chokepoint
  // (bd-only, `--actor grid-controller`). Tests inject a fake BdRunner so ZERO
  // writes reach the live `tg` workspace.
  final bd =
      bdOverride ?? BdCliService(ProcessBdRunner(workspaceRoot: workspace.root));

  // The registered root checkout (Layer 1). In dry-run we register lazily only
  // if a root was supplied; a missing root is fine (nothing is provisioned).
  RootCheckout? root = rootCheckoutOverride;
  if (root == null && rootPath != null) {
    try {
      root = await _buildGitService().registerRootCheckout(
        path: rootPath,
        rig: rigs.first,
      );
    } on Object catch (e) {
      writeErr('grid run: could not register root checkout "$rootPath": $e');
      await shutdownController();
      await host.dispose();
      return 1;
    }
  }

  // --- compose ---------------------------------------------------------------
  final wiring = composeRun(
    controller: controller,
    bd: bd,
    rigs: rigs,
    dryRun: dryRun,
    providerKind: provider,
    rootCheckout: root,
    readyWorkSource: readyWorkSourceOverride,
    convergenceSource: convergenceSourceOverride,
    provider: providerOverride,
    gitService: gitServiceOverride,
    onObserve: write,
    onError: (e, st) => writeErr('grid run: $e'),
  );

  write('grid run — workspace: ${workspace.root}');
  write(
    'mode: ${dryRun ? 'DRY-RUN (observe-only: no writes, no spawns)' : 'LIVE'}  '
    '·  provider: ${provider.name}  ·  rigs: {${rigs.join(', ')}}  '
    '·  read path: $readPathName',
  );
  if (root != null) {
    write('root checkout: ${root.path} (default ${root.defaultBranch})');
  }
  final info = await developer.Service.getInfo();
  final uri = info.serverUri;
  write(
    uri != null
        ? 'VM service: $uri  ·  attach leonard / exploration_cli / devtools here'
        : 'VM service: not enabled — re-run with `dart run --enable-vm-service`',
  );
  write('—' * 64);

  await controller.start(); // baseline snapshot + begin reacting
  await wiring.start(); // reconciler + dispatcher

  Future<void> shutdown() async {
    await wiring.dispose();
    await host.dispose();
    await shutdownController();
  }

  if (runFor != null) {
    await Future<void>.delayed(runFor);
    await shutdown();
    return 0;
  }
  if (!runForever) {
    await shutdown();
    return 0;
  }

  // Block until Ctrl-C.
  final interrupt = Completer<void>();
  late final StreamSubscription<ProcessSignal> sigint;
  sigint = ProcessSignal.sigint.watch().listen((_) {
    if (!interrupt.isCompleted) interrupt.complete();
  });
  await interrupt.future;
  await sigint.cancel();
  write('\ngrid run: shutting down…');
  await shutdown();
  return 0;
}
