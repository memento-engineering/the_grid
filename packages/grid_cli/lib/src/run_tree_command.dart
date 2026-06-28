/// `grid run --tree` composition — wires the M4 tree engine (ADR-0007: the
/// running grid IS `genesis_tree`) from INJECTABLE seams, exactly as
/// [composeRun] wires the M2/M3 spine, so the dry-run smoke drives the whole
/// assembly with fakes (no live `tg`, no real `claude`, no real `git`).
///
/// **Pure composition.** [composeRunTree] constructs no process, opens no
/// socket, and writes no bead — it builds the [StationKernel] + the
/// [RestartReconciler] and hands back a [TreeRunWiring]. *Starting* is
/// [TreeRunWiring.start]'s job; with a dry [EffectContext.provider] (a recording
/// no-op transport) and the land ops left null, `start()` is inert beyond the
/// in-memory tree mount + the (recorded) spawn.
///
/// The live `grid run --tree` COMMAND — one that actually spawns `claude` and
/// touches a real workspace + state store + root checkout — is the human gate
/// (the M3 precedent): not built here.
library;

import 'dart:async';
import 'dart:developer' as developer;
import 'dart:io';

import 'package:genesis_tree/genesis_tree.dart';
import 'package:grid_controller/grid_controller.dart';
import 'package:grid_engine/grid_engine.dart';
import 'package:grid_exploration/grid_exploration.dart';
import 'package:grid_runtime/grid_runtime.dart';

import 'run_command.dart' show RuntimeProviderKind;
import 'runtime_snapshot_source.dart';

/// The resolved tree-engine wiring — built by [composeRunTree] from the
/// injectable seams, started/torn down by the caller. A value-ish holder so a
/// test can assert the composition WITHOUT running a live loop.
class TreeRunWiring {
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

  /// Brings the tree up in the build-order's pinned ordering (ADR-0007 §4 /
  /// M4-P0-BUILD-ORDER Track D): the freshness barrier completes, THEN the
  /// restart reconciler reconciles the survivors, THEN — and only then — the
  /// kernel mounts and spawns. "Spawns mount only after the barrier completes."
  Future<void> start() async {
    await _freshnessBarrier();
    await restart.reconcile();
    kernel.start();
  }

  /// Tears down the tree (unmounting every effect → kill) + the join bridge.
  Future<void> teardown() async => kernel.dispose();
}

/// Assembles the M4 tree-engine [TreeRunWiring] from injectable seams.
///
/// Mirrors [composeRun]'s injectable-seam style so the dry-run smoke drives the
/// whole composition with fakes: the [work]/[state] [SnapshotSource]s (fakes in
/// a test; [RuntimeSnapshotSource] over the real controllers in the live arm),
/// the [effectContext] (a dry provider + the bd write chokepoint; land ops left
/// null for an offline build), the per-rig [substations] config, the [git] service +
/// [workRoot] (the Track-D worktree seam), the [groups] process-group
/// controller (the orphan-kill seam — kept REAL so its `pgid <= 1` guard is
/// exercised), and the [freshnessBarrier] (a completed re-query of the read +
/// state runtimes).
///
/// Construction only: it builds
///  - a [StationJoinBridge] over [work] + [state] (the lone subscription, A39),
///  - a [FormulaResolver] rooting the `code` formula per coding bead + the
///    [buildCodeRegistry] capability set,
///  - the [SubstationScope]s (one per [SubstationConfig], keyed by rig id so a rig add/remove
///    mounts/unmounts exactly that scope), each provided the git [ServiceBundle]
///    (lifted from the injected provisioner + land ops; land null ⇒ land no-ops,
///    an offline build) AT THE SCOPE (ADR-0008 D5: source control is per-substation),
///  - a [RestartReconciler] binding the engine's narrow worktree seams to the
///    injected [git] service's `listBeadWorktrees`/`reap` (the engine never
///    names the concrete VCS service — ADR-0007 §1), reading the post-barrier
///    OWNED session cursors from [state]'s `current` snapshot, and
///  - the [StationKernel] over the bridge + context + resolver + scopes.
///
/// Nothing is started; [TreeRunWiring.start] drives the barrier → restart →
/// mount ordering.
TreeRunWiring composeRunTree({
  required SnapshotSource work,
  required SnapshotSource state,
  required EffectContext effectContext,
  required List<SubstationConfig> substations,
  required StationGitService git,
  required RootCheckout workRoot,
  required ProcessGroupController groups,
  required Future<void> Function() freshnessBarrier,
}) {
  final bridge = StationJoinBridge(work: work, state: state);
  // The live work path (ADR-0008 D4): the reentrant FormulaResolver roots the
  // `code` formula (agent → verify → land as Capabilities) per coding bead at
  // the EffectResolver seam. The registry supplies the capability set + the
  // formula; the ServiceBundle lifts the injected git/PR ops into the land
  // capability's SourceControl (null ⇒ land no-ops — an offline build never
  // touches real git/GitHub).
  const resolver = FormulaResolver(_codeFormulaFor);
  final registry = buildCodeRegistry();
  // ALWAYS provide a git SourceControl: it owns WORKSPACE PROVISIONING (the host
  // cuts the per-bead worktree off `git`/`workRoot` before the agent spawns) —
  // needed even when LAND is deferred. Land stays optional: gitOps/prOpener null
  // ⇒ `canLand` is false ⇒ the land capability no-ops (the early-arm commit-only
  // posture). In a dry-run `git` is the INERT dry service, so provisioning is a
  // no-op too.
  final services = ServiceBundle(
    sourceControl: GitSourceControl(
      gitOps: effectContext.gitOps,
      prOpener: effectContext.prOpener,
      provisioner: git,
      root: workRoot,
    ),
  );

  // One config scope per rig, keyed by rig id so a rig add/remove mounts /
  // unmounts exactly that scope (the Grid reconciles its scope children by key).
  // The git [services] are provided AT THE SCOPE (ADR-0008 D5: source control is
  // a per-substation responsibility), so a CapabilityHost resolves its own
  // substation's SourceControl. P1 composes a single root checkout (one work
  // substation), so the one bundle is attached to the scope; a multi-substation
  // build with distinct roots would build one bundle per config here.
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
  // The state-store cursor read happens AFTER the barrier; an absent baseline
  // (state.current == null before the first emission) projects no cursors —
  // every survivor is then respawn-pending, never wrongly skipped.
  final restart = RestartReconciler(
    listWorktrees: git.listBeadWorktrees,
    reapWorktree: git.reap,
    workRoot: workRoot,
    groups: groups,
    freshnessBarrier: freshnessBarrier,
    stateSnapshot: () => state.current ?? _emptySnapshot(),
  );

  final kernel = StationKernel(
    bridge: bridge,
    effectContext: effectContext,
    resolver: resolver,
    substations: substationScopes,
    registry: registry,
  );

  return TreeRunWiring(
    kernel: kernel,
    restart: restart,
    freshnessBarrier: freshnessBarrier,
  );
}

/// The bead→root-formula policy for the live path: all coding work roots the
/// `code` formula (P1 — one formula; the Burn bead's formula arrives with
/// `butane_grid_assets`). A top-level tear-off so [FormulaResolver] stays const.
Formula _codeFormulaFor(Bead bead) => kCodeFormula;

/// Runs the M4 TREE ENGINE as `grid run` (tree-as-default — ADR-0007 + M5
/// DECISIONS D1): the live orchestrator that wires the M3 live seams into
/// [composeRunTree], mirroring [runGrid]. It discovers the work workspace, builds
/// the M1 controller (work axis) + a state controller (the split A36/A37 store),
/// adapts both to [SnapshotSource] via [RuntimeSnapshotSource], registers the
/// exploration host (leonard attach), builds the live [EffectContext], composes
/// the tree, and drives the barrier → restart → mount ordering.
///
/// **`--dry-run` is the SAFE DEFAULT (observe-only — touch NOTHING live).**
/// Because the tree engine always acts on mount (no dispatcher short-circuit to
/// gate, unlike M3), dry-ness moves to the seams: a no-op recording provider (no
/// real `claude`) + a no-op bd write seam (no real `bd` to any store) + null land
/// ops. The read controllers still read the real workspace (read-only). A LIVE
/// run (`--no-dry-run` + `--root` + `--state-workspace`) wires the real
/// [SubprocessProvider] + the chokepoint over the state store + the worktree git
/// service. [head] assigns the base branch worktrees cut from (the_grid-as-
/// substation cuts off its own feature branch, not the probed `origin/HEAD`).
/// The first live arm is the human gate.
///
/// Live-arm prerequisites NOW wired: the `--bead` blessed drive-list flows into
/// `SubstationConfig.driveList` and is ENFORCED at the `WorkList` mount boundary
/// (a live run refuses an empty drive-list); the agent's rich full-bead prompt
/// now lives in the `code` extension's `AgentCapability` (`buildAgentPrompt`).
/// Still a human follow-up: land→PR (gitOps/prOpener left null, so the `land`
/// capability no-ops). The first live arm remains the human gate.
///
/// The seams are injectable so an offline test drives the whole composition with
/// fakes (inject [workSourceOverride]/[stateSourceOverride] + the dry seams) — no
/// live `tg`, no real `claude`, no real `git`.
Future<int> runGridTree({
  required Set<String> substations,
  RuntimeProviderKind provider = RuntimeProviderKind.subprocess,
  String? rootPath,
  String? head,
  String? workspacePath,
  String? stateWorkspacePath,
  String? stateSubstation,
  Set<String> targetBeads = const {},
  bool dryRun = true,
  bool noSql = false,
  void Function(String)? out,
  void Function(String)? err,
  bool runForever = true,
  Duration? runFor,
  // --- offline-test overrides (inject the two sources + the dry seams) ---
  SnapshotSource? workSourceOverride,
  SnapshotSource? stateSourceOverride,
  RuntimeProvider? providerOverride,
  BdCliService? stateBdOverride,
  StationGitService? gitServiceOverride,
  ProcessGroupController? groupsOverride,
  RootCheckout? rootCheckoutOverride,
  Future<void> Function()? freshnessBarrierOverride,
}) async {
  final void Function(String) write = out ?? (m) => stdout.writeln(m);
  final void Function(String) writeErr = err ?? (m) => stderr.writeln(m);
  final bool testMode = workSourceOverride != null;

  // --- gating (mirror runGrid's safe-default arming) ---
  if (substations.isEmpty) {
    writeErr(
      'grid run: at least one --substation/--owner is required (the ownership '
      'allow-set; the dogfood rig is `tgdog`).',
    );
    return 64;
  }
  if (!dryRun && rootPath == null && rootCheckoutOverride == null) {
    writeErr(
      'grid run: a non-dry (live) run requires --root (the registered worktree '
      'root under engineering.memento). Re-run with --dry-run (the default) to '
      'observe only, or pass --root to ARM the writing arm.',
    );
    return 64;
  }
  if (!dryRun && stateWorkspacePath == null && stateSourceOverride == null) {
    writeErr(
      'grid run: a non-dry (live) run requires --state-workspace — the_grid '
      'writes its session/lifecycle beads there and must NEVER default them into '
      'the read --workspace (A36/A37). Pass --state-workspace (+ '
      '--state-substation), or use --dry-run.',
    );
    return 64;
  }
  if (!dryRun && targetBeads.isEmpty) {
    writeErr(
      'grid run: a non-dry (live) run requires at least one --bead — the '
      'blessed drive-list (ADR-0006). The_grid mounts an agent ONLY for beads '
      'explicitly blessed for a live arm; re-run with --bead <id> (repeatable), '
      'or use --dry-run to observe all owned work.',
    );
    return 64;
  }

  // THE single ownership allow-set: the work substations + the_grid's own state
  // partition (so the chokepoint owns the session beads it mints — A32/A36).
  final allowSet = Set<String>.unmodifiable(<String>{
    ...substations,
    if (stateSubstation != null && stateSubstation.isNotEmpty) stateSubstation,
  });

  // --- the work + state snapshot sources (+ the controllers/host in live) ---
  GridControllerRuntime? workController;
  GridControllerRuntime? stateController;
  Future<void> Function()? shutdownWork;
  Future<void> Function()? shutdownState;
  GridExplorationHost? host;
  BeadsWorkspace? stateWs;
  String readPathName = 'injected';
  late final SnapshotSource workSource;
  late final SnapshotSource stateSource;

  if (testMode) {
    workSource = workSourceOverride;
    stateSource = stateSourceOverride ?? const _EmptySnapshotSource();
  } else {
    final workspace = BeadsWorkspace.discover(start: workspacePath);
    if (workspace == null) {
      writeErr(
        'grid run: no .beads/ workspace found from '
        '${workspacePath ?? Directory.current.path}',
      );
      return 1;
    }
    final bundle = await GridRuntimeFactory.build(
      workspace: workspace,
      preferSql: !noSql,
    );
    workController = bundle.runtime;
    shutdownWork = bundle.shutdown;
    readPathName = bundle.readPath.name;
    workSource = RuntimeSnapshotSource(workController);
    host = GridExplorationHost(
      workController,
      plugin: GridControllerPlugin(workController, readPath: () => readPathName),
    );

    if (stateWorkspacePath != null) {
      stateWs = BeadsWorkspace.discover(start: stateWorkspacePath);
      if (stateWs == null) {
        writeErr(
          'grid run: no .beads/ state workspace found from $stateWorkspacePath '
          '(--state-workspace)',
        );
        await shutdownWork();
        return 1;
      }
      final stateBundle = await GridRuntimeFactory.build(
        workspace: stateWs,
        preferSql: !noSql,
      );
      stateController = stateBundle.runtime;
      shutdownState = stateBundle.shutdown;
      stateSource = RuntimeSnapshotSource(stateController);
    } else {
      // Dry-run with no split store: no session axis to observe.
      stateSource = const _EmptySnapshotSource();
    }
  }

  // --- the bd write chokepoint ---------------------------------------------
  // Dry-run (or no state store) → a no-op recording runner (no real `bd`). Live
  // → the real ProcessBdRunner over the_grid's OWN state store. The chokepoint
  // re-checks ownership fail-closed against the shared allow-set either way.
  final BdCliService bd =
      stateBdOverride ??
      (dryRun || stateWs == null
          ? BdCliService(_NoOpBdRunner())
          : BdCliService(ProcessBdRunner(workspaceRoot: stateWs.root)));
  final writer = StationBeadWriter(
    bd: bd,
    ownership: BeadOwnershipPredicate(allowSet),
    onRefusal: write,
  );

  // --- the runtime transport ------------------------------------------------
  final RuntimeProvider runtimeProvider =
      providerOverride ??
      (dryRun ? _DryRunProvider() : _buildTreeProvider(provider));

  // --- the worktree git service + the registered root -----------------------
  // Dry-run gets an INERT git service (a no-op runner): the RestartReconciler
  // always probes `listBeadWorktrees` on start, so the dry service must touch no
  // real `git` — its empty worktree list makes the reconcile a no-op (no probe
  // side effect, no orphan kill, no reap). Live builds the real service.
  final git =
      gitServiceOverride ??
      (dryRun ? buildDryTreeGitService() : _buildTreeGitService());
  final RootCheckout root;
  if (rootCheckoutOverride != null) {
    root = rootCheckoutOverride;
  } else if (!dryRun && rootPath != null) {
    try {
      root = await git.registerRootCheckout(
        path: rootPath,
        substation: substations.first,
        // Assign-head: cut per-bead worktrees off this branch (e.g. the_grid's
        // own feature branch) instead of the probed origin/HEAD. Null ⇒ probe.
        head: head,
      );
    } on Object catch (e) {
      writeErr('grid run: could not register root checkout "$rootPath": $e');
      if (shutdownWork != null) await shutdownWork();
      if (shutdownState != null) await shutdownState();
      return 1;
    }
  } else {
    // Dry-run synthetic root (nothing is provisioned under it).
    root = RootCheckout(path: '', defaultBranch: 'main', substation: substations.first);
  }

  // --- the live EffectContext ----------------------------------------------
  // Land ops (gitOps/prOpener) stay NULL — land is a deliberate human follow-up
  // for the early arms (the working agreement is commit-only, no push/PR), so
  // the land capability no-ops rather than touching real GitHub.
  final effectContext = EffectContext(
    provider: runtimeProvider,
    writer: writer,
    stateSubstation: (stateSubstation != null && stateSubstation.isNotEmpty)
        ? stateSubstation
        : substations.first,
    worktreeRoot: root.path.isEmpty ? null : root.path,
    workSubstation: substations.first,
    baseBranch: root.defaultBranch,
  );

  // One scope owning the work substations (the WorkList ownership predicate);
  // the state substation is the chokepoint's, not a work axis. The blessed-bead
  // drive-list (ADR-0006) flows in as config — WorkList mounts ONLY these beads
  // when non-empty (a live run guarantees it; dry-run may leave it empty to
  // observe all owned work).
  final substationConfigs = <SubstationConfig>[
    SubstationConfig(
      substationId: substations.first,
      ownedSubstations: substations,
      driveList: targetBeads,
    ),
  ];

  final groups = groupsOverride ?? SystemProcessGroupController();

  // The freshness barrier: a completed re-query of both runtimes before the
  // restart reconciler + kernel mount (ADR-0007 §4). In test mode (injected
  // sources, no controllers) it is the override or a completed no-op.
  final Future<void> Function() barrier =
      freshnessBarrierOverride ??
      () async {
        await Future.wait(<Future<void>>[
          if (workController != null) workController.requery(),
          if (stateController != null) stateController.requery(),
        ]);
      };

  final wiring = composeRunTree(
    work: workSource,
    state: stateSource,
    effectContext: effectContext,
    substations: substationConfigs,
    git: git,
    workRoot: root,
    groups: groups,
    freshnessBarrier: barrier,
  );

  // --- banner ---------------------------------------------------------------
  write('grid run --tree — the M4 tree engine');
  write(
    'mode: ${dryRun ? 'DRY-RUN (observe-only: no real spawns/writes)' : 'LIVE'}  '
    '·  provider: ${dryRun ? 'dry' : provider.name}  ·  substations: '
    '{${substations.join(', ')}}  ·  read path: $readPathName',
  );
  if (root.path.isNotEmpty) {
    write('root checkout: ${root.path} (default ${root.defaultBranch})');
  }
  if (stateWs != null) {
    write(
      'state store: $stateWorkspacePath  ·  session substation: $stateSubstation',
    );
  }
  if (targetBeads.isNotEmpty) {
    write(
      'drive-list (blessed beads): {${targetBeads.join(', ')}} '
      '(ENFORCED at the WorkList mount boundary — only these beads mount)',
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

  // --- start: controllers → host → barrier → restart → mount ---------------
  if (workController != null) await workController.start();
  if (stateController != null) await stateController.start();
  host?.register();
  await wiring.start();

  Future<void> shutdown() async {
    await wiring.teardown();
    await host?.dispose();
    if (shutdownState != null) await shutdownState();
    if (shutdownWork != null) await shutdownWork();
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

/// The live transport for the tree path (the tmux arm rides Track 1's standalone
/// package; subprocess-first, like M3).
RuntimeProvider _buildTreeProvider(RuntimeProviderKind kind) => switch (kind) {
  RuntimeProviderKind.subprocess => SubprocessProvider(),
  // The tmux adapter is off the critical path (M3 ships subprocess-first); until
  // it lands, the subprocess provider is the only built provider.
  RuntimeProviderKind.tmux => SubprocessProvider(),
};

/// The worktree git service (worktree alloc/list/reap + the land PR opener) over
/// the real `git`/`gh` binaries. Built lazily; the offline suite injects a fake.
StationGitService _buildTreeGitService() => StationGitService(
  runner: SystemGitRunner(),
  prOpener: GhPrOpener(_ghRunner),
);

/// The INERT git service for `--dry-run` — a no-op [GitRunner] (every `git`
/// invocation returns an empty success) so `listBeadWorktrees` parses an empty
/// worktree set WITHOUT executing a real `git`, the reconcile finds no survivors
/// (no kill, no reap), and `provisionWorktree` is overridden to touch NO
/// filesystem (it would otherwise `mkdir` the worktree dir). The dry run touches
/// nothing live. Exposed for the inertness regression test.
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
Future<GitRunResult> _ghRunner(String workDir, List<String> args) async {
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
class _EmptySnapshotSource implements SnapshotSource {
  const _EmptySnapshotSource();

  @override
  Stream<GraphSnapshot> get snapshots => const Stream<GraphSnapshot>.empty();

  @override
  GraphSnapshot? get current => null;
}

/// The DRY-RUN transport: records every would-be spawn, starts no real process,
/// emits no lifecycle events (the mounted tree idles inert). `--dry-run` touches
/// nothing live.
class _DryRunProvider implements RuntimeProvider {
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
class _NoOpBdRunner implements BdRunner {
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
GraphSnapshot _emptySnapshot() => GraphSnapshot.fromParts(
  beads: const [],
  dependencies: const [],
  readyIds: const [],
  capturedAt: DateTime.fromMillisecondsSinceEpoch(0),
);
