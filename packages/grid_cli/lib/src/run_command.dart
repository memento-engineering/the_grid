import 'dart:async';
import 'dart:developer' as developer;
import 'dart:io';

import 'package:args/command_runner.dart';
import 'package:grid_controller/grid_controller.dart';
import 'package:grid_exploration/grid_exploration.dart';
import 'package:grid_reconciler/grid_reconciler.dart';
import 'package:grid_runtime/grid_runtime.dart';
import 'package:meta/meta.dart';

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
      ..addOption(
        'workspace',
        abbr: 'w',
        help:
            'The beads workspace to read ready work from (a directory at or '
            'above a `.beads/`). Defaults to discovery from the cwd. The '
            'dogfood side-cars another repo by pointing this at it (e.g. '
            '/Users/nico/development/engineering.memento/genesis with '
            '--rig genesis). Read-only under --dry-run.',
      )
      ..addOption(
        'state-workspace',
        help:
            'A SEPARATE the_grid-owned beads workspace where the_grid writes its '
            'own session/lifecycle beads (A36 choice B), so the --workspace '
            'work source stays read-only and never adopts the_grid\'s `session` '
            'type. Omit to write session beads into --workspace itself.',
      )
      ..addOption(
        'state-rig',
        defaultsTo: 'tgdog',
        help:
            'the_grid\'s OWNED session partition (the prefix of the '
            '--state-workspace store). Unioned into the allow-set so the write '
            'chokepoint owns the session beads it mints. Only used with '
            '--state-workspace.',
      )
      ..addMultiOption(
        'bead',
        abbr: 'b',
        help:
            'A specific work-bead id to drive (repeatable) — the operational '
            'drive-list layered ON TOP of the ownership allow-set. When given, '
            'ONLY these (owned) beads dispatch; everything else is observed '
            'read-only. This is the "bless the specific work beads" gate (A35). '
            'Omit to drive every owned bead (the prefix scopes on its own).',
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
      workspacePath: args.option('workspace'),
      stateWorkspacePath: args.option('state-workspace'),
      // --state-rig only applies when a state workspace is given.
      stateRig: args.option('state-workspace') == null
          ? null
          : args.option('state-rig'),
      targetBeads: <String>{...args.multiOption('bead')}
        ..removeWhere((b) => b.trim().isEmpty),
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
  Set<String> driveList = const {},
  BdCliService? stateBd,
  String? stateRig,
  void Function(String message)? onObserve,
  void Function(Object error, StackTrace stack)? onError,
}) {
  assert(
    controller != null ||
        (readyWorkSource != null && convergenceSource != null),
    'composeRun needs a controller unless BOTH the ready-work and convergence '
    'sources are injected',
  );

  // THE single source of truth: one Set<String> instance feeds BOTH gates
  // (A32). The split-DB arm (A36 choice B) adds the_grid's own session
  // partition (`stateRig`, e.g. `tgdog`) so the write chokepoint owns the
  // session beads it mints into the SEPARATE state store, while dispatch still
  // owns the work rigs it reads. No work/convergence bead in the read workspace
  // carries the stateRig prefix, so widening the set never broadens
  // dispatch/actuation — it only authorizes the_grid's own lifecycle writes.
  final allowSet = Set<String>.unmodifiable(<String>{
    ...rigs,
    if (stateRig != null && stateRig.isNotEmpty) stateRig,
  });
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
  // re-checks ownership fail-closed against the SAME allow-set. In the split-DB
  // arm the writes target [stateBd] (the_grid's own state store), NOT the read
  // workspace's bd — genesis stays a pristine work source (A36 choice B).
  final writer = GridBeadWriter(
    bd: stateBd ?? bd,
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
    driveList: driveList,
    sessionRig: stateRig,
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
/// print mode; pre-granted permissions so no approval prompt appears (dogfood
/// agents run headless). The prompt carries the **full** bead (title +
/// description + design + acceptance criteria + notes) — a title-only prompt
/// starves the agent of the load-bearing instructions (A36 pre-flight) — plus a
/// **local-first working agreement**: commit on the throwaway branch, do NOT
/// push, do NOT open a PR. Landing (`GridGitService.land`) is a deliberate
/// human follow-up for the first live arms, so the loop produces inspectable
/// local commits with zero GitHub side effects.
RuntimeConfig _buildAgentConfig(DispatchRequest request) =>
    buildAgentConfig(request);

/// The prompt/command assembly, exposed for unit tests (the prompt is the live
/// dogfood contract). See [_buildAgentConfig] for the rationale.
@visibleForTesting
RuntimeConfig buildAgentConfig(DispatchRequest request) {
  final bead = request.bead;
  final title = bead.title.isNotEmpty ? bead.title : 'work bead ${bead.id}';
  final p = StringBuffer()
    ..writeln('# $title')
    ..writeln()
    ..writeln('Bead `${bead.id}` (rig `${request.rig}`).');
  void section(String heading, String body) {
    if (body.trim().isEmpty) return;
    p
      ..writeln()
      ..writeln('## $heading')
      ..writeln(body.trim());
  }

  section('Task', bead.description);
  section('Design', bead.design);
  section('Acceptance criteria', bead.acceptanceCriteria);
  section('Notes', bead.notes);
  p
    ..writeln()
    ..writeln('## Working agreement')
    ..writeln(
      '- Work ONLY inside this worktree (${request.worktree.path}); it is on '
      'branch `${request.worktree.branch}`, a throwaway branch the_grid '
      'provisioned for this bead.',
    )
    ..writeln('- Implement the task and COMMIT your work on that branch.')
    ..writeln(
      '- Do NOT push and do NOT open a pull request — leave the commit for '
      'human review.',
    )
    ..writeln(
      '- When committed, run `grid phase --advance` to mark this phase done, '
      'then exit. (This advances your OWN session cursor through the_grid\'s '
      'chokepoint-mediated shim — the durable-completion belt-and-suspenders of '
      'ADR-0007 §0.2 / A40. It is NOT a free-form `bd` call: do not write beads '
      'directly from the worktree.)',
    )
    ..writeln('- When the work is committed you are done; exit.');
  return RuntimeConfig(
    workDir: request.worktree.path,
    command: 'claude',
    args: ['--dangerously-skip-permissions', '-p', p.toString()],
    lifecycle: Lifecycle.oneTurn,
    env: {
      'GRID_BEAD_ID': bead.id,
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
  String? workspacePath,
  String? stateWorkspacePath,
  String? stateRig,
  Set<String> targetBeads = const {},
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

  // The_grid's own session/lifecycle beads must go to an EXPLICIT state store,
  // never silently default into the read --workspace — which, in the side-car
  // arm, is a pristine FOREIGN work source (A36/A37). A live run therefore
  // REQUIRES --state-workspace. (A review caught a live side-car that omitted
  // it writing `type=session` into genesis, blocked only by genesis's own
  // schema; this fail-closes that in the_grid instead of leaning on the
  // consumer store.) The single-DB self-owned arm passes its own store here.
  if (!dryRun && stateWorkspacePath == null) {
    writeErr(
      'grid run: a non-dry (live) run requires --state-workspace — the_grid '
      'writes its session/lifecycle beads there and must NEVER default them '
      'into the read --workspace. Pass --state-workspace (+ --state-rig), or '
      'use --dry-run.',
    );
    return 64;
  }

  final workspace =
      workspaceOverride ?? BeadsWorkspace.discover(start: workspacePath);
  if (workspace == null) {
    writeErr(
      'grid run: no .beads/ workspace found from '
      '${workspacePath ?? Directory.current.path}',
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

  // --- the split state store (A36 choice B) ----------------------------------
  // When --state-workspace is set, the_grid's OWN lifecycle/session beads are
  // written into a SEPARATE the_grid-owned store (e.g. the `tgdog` embedded DB)
  // instead of the read workspace — so a side-car'd work source (genesis) stays
  // a pristine, read-only backlog and never has to adopt the_grid's `session`
  // type. The session partition is `stateRig`, which must be in the allow-set
  // (composeRun unions it in) so the chokepoint owns the session beads it mints.
  BdCliService? stateBd;
  if (stateWorkspacePath != null) {
    if (stateRig == null || stateRig.trim().isEmpty) {
      writeErr(
        'grid run: --state-workspace requires --state-rig (the_grid\'s owned '
        'session partition, e.g. `tgdog`).',
      );
      await shutdownController();
      await host.dispose();
      return 64;
    }
    final stateWs = BeadsWorkspace.discover(start: stateWorkspacePath);
    if (stateWs == null) {
      writeErr(
        'grid run: no .beads/ state workspace found from $stateWorkspacePath '
        '(--state-workspace)',
      );
      await shutdownController();
      await host.dispose();
      return 1;
    }
    stateBd = BdCliService(ProcessBdRunner(workspaceRoot: stateWs.root));
  }

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
    driveList: targetBeads,
    stateBd: stateBd,
    stateRig: stateRig,
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
  if (stateBd != null) {
    write(
      'state store: $stateWorkspacePath  ·  session rig: $stateRig  '
      '(genesis read-only; sessions written here)',
    );
  }
  if (targetBeads.isNotEmpty) {
    write('drive-list (blessed beads): {${targetBeads.join(', ')}}');
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
