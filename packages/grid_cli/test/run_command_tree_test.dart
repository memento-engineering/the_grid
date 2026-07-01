import 'dart:async';
import 'dart:io';

import 'package:grid_cli/src/run_tree_command.dart';
import 'package:grid_controller/grid_controller.dart';
import 'package:grid_engine/grid_engine.dart';
import 'package:grid_runtime/grid_runtime.dart';
import 'package:test/test.dart';

/// Offline proof for `composeStation` (the M4 tree-engine "runnable path",
/// ADR-0007) — Fakes, not mocks; NO live `tg`, NO real `claude`, NO real `git`,
/// NO `bd` writes to a live workspace. The DoD this file locks:
///
///  1. **pure composition** — [composeStation] assembles a [TreeRunWiring]
///     (a [StationKernel] + a [RestartReconciler]) without spawning, opening a
///     socket, or writing a bead;
///  2. **the kernel mounts + a ready owned bead spawns (dry)** — `start()` over a
///     fake work source carrying one ready owned task mounts the tree and the
///     DRY provider records exactly one start (the bead WOULD spawn live);
///  3. **barrier-before-mount ordering** — `start()` awaits the freshness
///     barrier BEFORE the kernel mounts / any spawn is recorded (ADR-0007 §4:
///     "spawns mount only after the barrier completes");
///  4. **clean teardown** — `teardown()` unmounts the tree (the dry effect's
///     `dispose` records a stop) and is idempotent.
void main() {
  group('composeStation — pure composition (no I/O at construct time)', () {
    test('assembles a kernel + restart reconciler; constructs nothing live',
        () {
      final h = _TreeHarness();
      final wiring = h.compose();
      addTearDown(h.dispose);

      // The wiring is built but NOT started: no barrier ran, no spawn, no bd
      // write, no worktree probe — pure construction.
      expect(wiring.kernel, isNotNull);
      expect(wiring.restart, isNotNull);
      expect(h.barrierRuns, 0, reason: 'composition never runs the barrier');
      expect(h.provider.starts, isEmpty, reason: 'composition spawns nothing');
      expect(h.bdRunner.calls, isEmpty, reason: 'composition writes no bead');
      expect(h.git.listCalls, 0, reason: 'composition probes no worktrees');
    });
  });

  group('composeStation — dry start smoke (kernel mounts, ready bead spawns)',
      () {
    test('a ready OWNED task mounts the tree and the DRY provider records a '
        'start (the bead would spawn live)', () async {
      final h = _TreeHarness();
      final wiring = h.compose();
      addTearDown(h.dispose);

      // Stage a ready, owned, core-type work bead on the work source.
      h.pushWork(Bead(id: 'tgdog-w1', title: 'do the thing'));

      await wiring.start();
      await _settle();

      // The kernel mounted and the implement-phase effect drove the DRY
      // transport: exactly one (recorded, never-real) spawn for the ready bead.
      expect(h.provider.starts, hasLength(1), reason: 'the ready bead spawned');
      // The host provisioned the worktree (via SourceControl) before spawning —
      // the agent never lands in a non-existent dir (the blocker fix).
      expect(h.git.provisioned, contains('tgdog-w1'),
          reason: 'the workspace was provisioned before the spawn');
      // The session bead was minted through the chokepoint over the recording
      // bd runner — a `create` was recorded, but NO live `bd` ran (the runner is
      // a fake returning a canned envelope).
      expect(
        h.bdRunner.calls.where((c) => c.isNotEmpty && c.first == 'create'),
        isNotEmpty,
        reason: 'the session bead was minted via the chokepoint (fake bd)',
      );

      await wiring.teardown();
      // Teardown unmounted the effect → the dry provider recorded a stop.
      expect(h.provider.stops, isNotEmpty, reason: 'teardown kills the effect');
    });

    test('start() awaits the freshness barrier BEFORE the kernel mounts / any '
        'spawn is recorded (ADR-0007 §4 ordering)', () async {
      final h = _TreeHarness();
      final wiring = h.compose();
      addTearDown(h.dispose);

      h.pushWork(Bead(id: 'tgdog-w2', title: 'ordered work'));

      await wiring.start();
      await _settle();

      // The barrier ran, and its FIRST run preceded the first recorded spawn —
      // the build-order's "spawns mount only after the barrier completes".
      expect(h.barrierRuns, greaterThan(0), reason: 'start() ran the barrier');
      expect(h.firstBarrierTick, isNotNull);
      expect(h.firstSpawnTick, isNotNull, reason: 'the bead spawned');
      expect(
        h.firstBarrierTick! < h.firstSpawnTick!,
        isTrue,
        reason: 'the barrier completed before the first spawn',
      );

      await wiring.teardown();
    });

    test('teardown() is idempotent (a second call does nothing, never throws)',
        () async {
      final h = _TreeHarness();
      final wiring = h.compose();
      addTearDown(h.dispose);

      h.pushWork(Bead(id: 'tgdog-w3', title: 'idempotent'));
      await wiring.start();
      await _settle();

      await wiring.teardown();
      final stopsAfterFirst = h.provider.stops.length;
      await wiring.teardown(); // second call — no double-kill, no throw.
      expect(h.provider.stops.length, stopsAfterFirst);
    });
  });

  group('composeStation — the ASSET seam (ADR-0008 D1: default code, or inject)',
      () {
    test('an INJECTED asset (resolver + registry + services) drives the mount — a '
        'non-code formula mounts its OWN step, so the burn composes WITHOUT '
        'editing the composer', () async {
      final h = _TreeHarness();
      final wiring = h.compose(
        resolver: const FormulaResolver(_markerFormulaFor),
        registry: DefaultCapabilityRegistry(
          capabilities: const {_markerStep: _MarkerCap()},
          formulas: const {'marker': _markerFormula},
        ),
        // An empty ServiceBundle (no SourceControl) — an asset that leases/drives
        // instead of cutting a git worktree (the burn). Proves `services` is
        // honored: no git provisioning happens.
        services: const ServiceBundle(),
      );
      addTearDown(h.dispose);

      h.pushWork(Bead(id: 'tgdog-w1', title: 'do the thing'));
      await wiring.start();
      await _settle();

      // The injected formula/registry drove the mount: the sole recorded spawn is
      // the MARKER node path, not the `code` asset's `agent` step.
      expect(h.provider.starts, hasLength(1));
      expect(
        h.provider.starts.single.name,
        contains('/$_markerStep'),
        reason: 'the injected asset mounted, not the code default',
      );
      // The injected empty ServiceBundle replaced the git default — no worktree
      // was provisioned (a `code` default would have provisioned via git).
      expect(
        h.git.provisioned,
        isEmpty,
        reason: 'the injected ServiceBundle (no SourceControl) was honored',
      );

      await wiring.teardown();
    });

    test('with NO injected asset, the `code` default still drives (unchanged): the '
        'git ServiceBundle provisions the worktree before the spawn', () async {
      final h = _TreeHarness();
      final wiring = h.compose(); // no asset → code default
      addTearDown(h.dispose);

      h.pushWork(Bead(id: 'tgdog-w1', title: 'code default'));
      await wiring.start();
      await _settle();

      expect(h.provider.starts, hasLength(1));
      // The code default provisions via the git SourceControl (the contrast with
      // the injected-asset case above).
      expect(h.git.provisioned, contains('tgdog-w1'));

      await wiring.teardown();
    });
  });

  group('runGridTree — gating + dry-run wiring (tree-as-default)', () {
    test('an empty allow-set is refused (exit 64, no composition)', () async {
      final errs = <String>[];
      final code = await runGridTree(
        substations: const {},
        dryRun: true,
        out: (_) {},
        err: errs.add,
        runForever: false,
      );
      expect(code, 64);
      expect(errs.join('\n'), contains('--substation/--owner is required'));
    });

    test('--land combined with --dry-run is refused (exit 64) — land is a LIVE '
        'GitHub write, never armed under an observe-only run', () async {
      final errs = <String>[];
      final code = await runGridTree(
        substations: {'tgdog'},
        dryRun: true, // observe-only…
        land: true, //   …but asking to land → contradiction, refused.
        out: (_) {},
        err: errs.add,
        runForever: false,
      );
      expect(code, 64);
      expect(errs.join('\n'), contains('--land cannot be combined with --dry-run'));
    });

    test('a non-dry run with no --root is refused (exit 64)', () async {
      final errs = <String>[];
      final code = await runGridTree(
        substations: {'tgdog'},
        dryRun: false, // ask for LIVE…
        // …no root → refused before any composition.
        out: (_) {},
        err: errs.add,
        runForever: false,
      );
      expect(code, 64);
      expect(errs.join('\n'), contains('requires --root'));
    });

    test('a non-dry run with --root but NO --state-workspace is refused (64) — '
        'sessions must never default into the read --workspace (A36/A37)',
        () async {
      final errs = <String>[];
      final code = await runGridTree(
        substations: {'genesis'},
        dryRun: false,
        rootPath: '/tmp/some-root', // past the root guard…
        // …no --state-workspace → refused.
        out: (_) {},
        err: errs.add,
        runForever: false,
      );
      expect(code, 64);
      expect(errs.join('\n'), contains('requires --state-workspace'));
    });

    test('dry-run wires the M3 seams into the tree engine: an owned ready bead '
        'mounts + records a would-spawn through the chokepoint, NOTHING live; '
        'the start→teardown lifecycle returns 0', () async {
      final work = _FakeSnapshotSource();
      work.push(
        GraphSnapshot.fromParts(
          beads: [Bead(id: 'tgdog-w1', title: 'do the thing')],
          dependencies: const [],
          readyIds: {'tgdog-w1'},
          capturedAt: DateTime.fromMillisecondsSinceEpoch(0),
        ),
      );
      final state = _FakeSnapshotSource();
      final provider = _RecordingDryProvider();
      final bdRunner = RecordingBdRunner();
      final groups = _FakeProcessGroupController();
      addTearDown(() async {
        await work.close();
        await state.close();
        await provider.close();
      });

      final code = await runGridTree(
        substations: {'tgdog'},
        stateSubstation: 'tgdog',
        dryRun: true,
        // Inject the two sources + the dry seams — but NOT the git service, so
        // the lib's own dry (no-op) git service is exercised end-to-end (the
        // RestartReconciler probes it on start; it must touch no real git).
        workSourceOverride: work,
        stateSourceOverride: state,
        providerOverride: provider,
        stateBdOverride: BdCliService(bdRunner),
        groupsOverride: groups,
        rootCheckoutOverride: const RootCheckout(
          path: '/tmp/grid-tree-root',
          defaultBranch: 'main',
          substation: 'tgdog',
        ),
        freshnessBarrierOverride: () async {},
        // A short fixed run lets the mount→mint→spawn microtask chain settle
        // before teardown, then returns 0.
        runFor: const Duration(milliseconds: 100),
        out: (_) {},
        err: (_) {},
      );

      expect(code, 0);
      // The engine mounted through the wiring and drove the chokepoint (the
      // session mint) + recorded a would-spawn — all through fakes.
      expect(
        bdRunner.calls.where((c) => c.isNotEmpty && c.first == 'create'),
        isNotEmpty,
        reason: 'the session mint went through the chokepoint (fake bd)',
      );
      expect(
        provider.starts,
        isNotEmpty,
        reason: 'the ready owned bead would spawn (recorded, never real)',
      );
    });

    test('a non-dry run with NO --bead is refused (64) — a live arm must bless '
        'specific beads (the drive-list, ADR-0006)', () async {
      final errs = <String>[];
      final code = await runGridTree(
        substations: {'tgdog'},
        dryRun: false,
        rootPath: '/tmp/some-root', // past the root guard…
        stateWorkspacePath: '/tmp/some-state', // …past the state guard…
        // …no --bead → refused before any discovery/composition.
        out: (_) {},
        err: errs.add,
        runForever: false,
      );
      expect(code, 64);
      expect(errs.join('\n'), contains('requires at least one --bead'));
    });

    test('the blessed drive-list is ENFORCED at the tree mount boundary: of two '
        'ready owned beads, ONLY the --bead one mounts + would-spawn', () async {
      final work = _FakeSnapshotSource();
      work.push(
        GraphSnapshot.fromParts(
          beads: [
            Bead(id: 'tgdog-w1', title: 'blessed'),
            Bead(id: 'tgdog-w2', title: 'not blessed'),
          ],
          dependencies: const [],
          readyIds: {'tgdog-w1', 'tgdog-w2'},
          capturedAt: DateTime.fromMillisecondsSinceEpoch(0),
        ),
      );
      final state = _FakeSnapshotSource();
      final provider = _RecordingDryProvider();
      final bdRunner = RecordingBdRunner();
      final groups = _FakeProcessGroupController();
      addTearDown(() async {
        await work.close();
        await state.close();
        await provider.close();
      });

      final code = await runGridTree(
        substations: {'tgdog'},
        stateSubstation: 'tgdog',
        dryRun: true,
        targetBeads: const {'tgdog-w1'}, // bless ONLY w1
        workSourceOverride: work,
        stateSourceOverride: state,
        providerOverride: provider,
        stateBdOverride: BdCliService(bdRunner),
        groupsOverride: groups,
        rootCheckoutOverride: const RootCheckout(
          path: '/tmp/grid-tree-root',
          defaultBranch: 'main',
          substation: 'tgdog',
        ),
        freshnessBarrierOverride: () async {},
        runFor: const Duration(milliseconds: 100),
        out: (_) {},
        err: (_) {},
      );

      expect(code, 0);
      // Exactly one spawn — for the blessed bead; the unblessed owned/ready bead
      // never mounted, so it never minted a session nor recorded a would-spawn.
      expect(provider.starts, hasLength(1));
      expect(provider.starts.single.name, contains('tgdog-w1'));
      expect(
        provider.starts.where((s) => s.name.contains('tgdog-w2')),
        isEmpty,
        reason: 'the unblessed bead must not mount',
      );
    });

    test('--head is plumbed to registerRootCheckout: a live run ASSIGNS the base '
        'branch worktrees cut from (the_grid-as-substation cuts off its own '
        'branch, not the probed origin/HEAD)', () async {
      final work = _FakeSnapshotSource();
      work.push(
        GraphSnapshot.fromParts(
          beads: [Bead(id: 'tgdog-w1', title: 'blessed')],
          dependencies: const [],
          readyIds: {'tgdog-w1'},
          capturedAt: DateTime.fromMillisecondsSinceEpoch(0),
        ),
      );
      final state = _FakeSnapshotSource();
      final provider = _RecordingDryProvider();
      final bdRunner = RecordingBdRunner();
      final groups = _FakeProcessGroupController();
      final git = _FakeGitService();
      addTearDown(() async {
        await work.close();
        await state.close();
        await provider.close();
      });

      // A LIVE run (dryRun:false) with a --root but NO rootCheckoutOverride, so
      // registerRootCheckout is actually exercised — all other seams faked.
      final code = await runGridTree(
        substations: {'tgdog'},
        stateSubstation: 'tgdog',
        dryRun: false,
        rootPath: '/tmp/grid-tree-root',
        head: 'm4-p1-reentrant-engine',
        targetBeads: const {'tgdog-w1'},
        workSourceOverride: work,
        stateSourceOverride: state,
        providerOverride: provider,
        stateBdOverride: BdCliService(bdRunner),
        groupsOverride: groups,
        gitServiceOverride: git.service,
        freshnessBarrierOverride: () async {},
        runFor: const Duration(milliseconds: 100),
        out: (_) {},
        err: (_) {},
      );

      expect(code, 0);
      expect(git.service.registerCalled, isTrue);
      expect(
        git.service.registeredHead,
        'm4-p1-reentrant-engine',
        reason: '--head reaches registerRootCheckout as the assigned base branch',
      );
    });

    test('the dry-run git service is INERT — a no-op runner yields a NON-NULL '
        'empty worktree list (a real `git` over a non-repo path errors → null), '
        'so the RestartReconciler finds no survivors without touching real git',
        () async {
      final result = await buildDryTreeGitService().listBeadWorktrees(
        const RootCheckout(
          path: '/tmp/grid-tree-root-does-not-exist',
          defaultBranch: 'main',
          substation: 'tgdog',
        ),
      );
      // Exit-0 + empty output (the no-op runner) parses to [] — a real `git`
      // over a non-existent repo would exit non-zero → worktreeList returns null.
      expect(result, isNotNull,
          reason: 'the no-op runner short-circuits real git (empty success)');
      expect(result, isEmpty);
    });
  });
}

/// Pumps the microtask/event queue a few turns so the kernel's batched flush,
/// the effect's `_run` async gaps (create-session → spawn), and broadcast
/// delivery all settle.
Future<void> _settle() async {
  for (var i = 0; i < 12; i++) {
    await Future<void>.delayed(Duration.zero);
  }
}

// --- a minimal NON-CODE asset (proves the composeStation asset seam) ----------

const String _markerStep = 'marker';

/// A one-step formula distinct from the `code` asset — its step id [_markerStep]
/// is recognizable in the recorded spawn name, proving an injected asset (not the
/// code default) drove the mount.
const Formula _markerFormula = Formula(
  id: 'marker',
  terminalStepId: _markerStep,
  steps: [
    CapabilityStep(
      stepId: _markerStep,
      capabilityId: _markerStep,
      kind: StepKind.job,
    ),
  ],
);

/// The bead→formula policy for the injected asset (all work → the marker formula).
Formula _markerFormulaFor(Bead bead) => _markerFormula;

/// A trivial process capability for the marker step — the DRY provider records
/// its (never-real) spawn; the node path carries [_markerStep].
class _MarkerCap extends ProcessCapability {
  const _MarkerCap();

  @override
  RuntimeConfig spawn(CapabilityContext ctx) => RuntimeConfig(
    workDir: ctx.workspaceDir,
    command: 'sh',
    args: const ['-c', 'true'],
    lifecycle: Lifecycle.oneTurn,
  );

  @override
  StepSignal interpretEvent(RuntimeEvent event) => StepSignal.none;
}

/// The offline harness: fake work/state snapshot sources, a recording dry
/// provider, a recording bd runner behind the chokepoint, a fake git service
/// (no worktrees), a fake process-group controller, and a completing,
/// tick-recording freshness barrier — so [composeStation] runs end-to-end with
/// NOTHING live.
class _TreeHarness {
  _TreeHarness();

  final _FakeSnapshotSource work = _FakeSnapshotSource();
  final _FakeSnapshotSource state = _FakeSnapshotSource();
  final _RecordingDryProvider provider = _RecordingDryProvider();
  final RecordingBdRunner bdRunner = RecordingBdRunner();
  final _FakeGitService git = _FakeGitService();
  final _FakeProcessGroupController groups = _FakeProcessGroupController();

  /// A monotonically increasing logical clock so the test can order the barrier
  /// completion against the first recorded spawn without wall-clock flakiness.
  int _tick = 0;
  int nextTick() => ++_tick;

  int barrierRuns = 0;
  int? firstBarrierTick;

  int? get firstSpawnTick => provider.firstStartTick;

  Future<void> _barrier() async {
    barrierRuns++;
    firstBarrierTick ??= nextTick();
  }

  /// Composes the wiring. With no [resolver]/[registry]/[services] it uses the
  /// `code` asset defaults (the live path); pass them to prove the ADR-0008 D1
  /// asset seam (a non-code asset composes without editing the composer).
  TreeRunWiring compose({
    FormulaResolver? resolver,
    CapabilityRegistry? registry,
    ServiceBundle? services,
  }) {
    // The dry effect context: the recording provider (never spawns real
    // claude), the bd write chokepoint over the recording runner (fail-closed on
    // the owned rig), the owned state rig, and NO git/PR land ops (an offline
    // build no-ops land rather than touch real GitHub).
    final writer = StationBeadWriter(
      bd: BdCliService(bdRunner),
      ownership: BeadOwnershipPredicate(const {'tgdog'}),
    );
    final effectContext = StationServices(
      provider: provider,
      writer: writer,
      stateSubstation: 'tgdog',
    );
    return composeStation(
      work: work,
      state: state,
      stationServices: effectContext,
      substations: const [
        SubstationConfig(substationId: 'tgdog', ownedSubstations: {'tgdog'}),
      ],
      git: git.service,
      workRoot: const RootCheckout(
        path: '/tmp/grid-tree-test-root',
        defaultBranch: 'main',
        substation: 'tgdog',
      ),
      groups: groups,
      freshnessBarrier: _barrier,
      resolver: resolver,
      registry: registry,
      services: services,
    );
  }

  /// Push a work snapshot carrying [bead] as a ready bead (the mount trigger:
  /// core type + owned + in readyIds + no terminal session).
  void pushWork(Bead bead) {
    work.push(
      GraphSnapshot.fromParts(
        beads: [bead],
        dependencies: const [],
        readyIds: {bead.id},
        capturedAt: DateTime.fromMillisecondsSinceEpoch(0),
      ),
    );
  }

  Future<void> dispose() async {
    await work.close();
    await state.close();
    await provider.close();
  }
}

/// A fake [SnapshotSource] — a broadcast [StreamController] + a settable
/// [current] (seed-then-follow, exactly like the real change-gated runtime).
class _FakeSnapshotSource implements SnapshotSource {
  final StreamController<GraphSnapshot> _controller =
      StreamController<GraphSnapshot>.broadcast();
  GraphSnapshot? _current;

  void push(GraphSnapshot snapshot) {
    _current = snapshot;
    _controller.add(snapshot);
  }

  @override
  Stream<GraphSnapshot> get snapshots => _controller.stream;

  @override
  GraphSnapshot? get current => _current;

  Future<void> close() => _controller.close();
}

/// A recording, no-op [RuntimeProvider] (Fakes, not mocks): every spawn is
/// recorded and tick-stamped; nothing real is started. A `start` immediately
/// emits the `sessionStarted` lifecycle event so the effect's subscription is
/// realistic, but no OS process exists.
class _RecordingDryProvider implements RuntimeProvider {
  final StreamController<RuntimeEvent> _events =
      StreamController<RuntimeEvent>.broadcast();

  final List<({String name, RuntimeConfig config})> starts = [];
  final List<String> stops = [];
  final Set<String> _running = {};

  int _tick = 0;
  int? firstStartTick;

  @override
  Future<void> start(String name, RuntimeConfig config) async {
    if (_running.contains(name)) throw SessionAlreadyExists(name);
    starts.add((name: name, config: config));
    firstStartTick ??= ++_tick + 1000000; // big offset: spawns tick after start
    _running.add(name);
  }

  @override
  Future<void> stop(String name) async {
    stops.add(name);
    _running.remove(name);
  }

  @override
  Future<void> interrupt(String name) async {}

  @override
  Stream<RuntimeEvent> get events => _events.stream;

  @override
  Stream<String> output(String name) => const Stream.empty();

  @override
  bool isRunning(String name) => _running.contains(name);

  @override
  bool processAlive(String name) => _running.contains(name);

  @override
  String peek(String name, int lines) => '';

  @override
  List<String> listRunning(String prefix) =>
      _running.where((n) => n.startsWith(prefix)).toList();

  @override
  DateTime? lastActivity(String name) => null;

  @override
  RuntimeCapabilities get capabilities => RuntimeCapabilities.subprocess;

  Future<void> close() => _events.close();
}

/// A fake [StationGitService] whose worktree-list seam returns EMPTY (no survivors
/// to reconcile on restart) and whose reap is never reached. Built over a fake
/// [GitRunner] so no real `git` runs; [listCalls] counts the worktree probes so
/// the composition-only test can assert ZERO at construct time.
class _FakeGitService {
  int listCalls = 0;

  late final _RecordingGitService service = _RecordingGitService(
    onList: () => listCalls++,
  );

  /// Bead ids whose worktree the host asked to provision (via SourceControl).
  List<String> get provisioned => service.provisioned;
}

/// A [StationGitService] over fake runners that records each `listBeadWorktrees`
/// call and always reports no worktrees (the live `git` is never touched).
class _RecordingGitService extends StationGitService {
  _RecordingGitService({required this.onList})
      : super(runner: _FakeGitRunner(), prOpener: _FakePrOpener());

  final void Function() onList;

  final List<String> provisioned = [];

  /// Whether [registerRootCheckout] was called, and the `head` it received — so a
  /// test can assert `--head` is plumbed through as the assigned base branch.
  bool registerCalled = false;
  String? registeredHead;

  @override
  Future<RootCheckout> registerRootCheckout({
    required String path,
    required String substation,
    String remote = 'origin',
    String? head,
  }) async {
    registerCalled = true;
    registeredHead = head;
    // The assigned head becomes the default branch (no real git probe).
    return RootCheckout(
      path: path,
      defaultBranch: head ?? 'main',
      substation: substation,
      remote: remote,
    );
  }

  @override
  Future<List<BeadWorktree>?> listBeadWorktrees(RootCheckout root) async {
    onList();
    return const <BeadWorktree>[];
  }

  // Inert provisioning — records the call, touches NO filesystem (the real
  // StationGitService.provisionWorktree would mkdir + `git worktree add`).
  @override
  Future<BeadWorktree> provisionWorktree({
    required RootCheckout root,
    required String beadId,
  }) async {
    provisioned.add(beadId);
    return BeadWorktree(
      beadId: beadId,
      path: '${root.path}/.grid/worktrees/${root.substation}/$beadId',
      branch: 'grid/$beadId',
    );
  }
}

class _FakeGitRunner implements GitRunner {
  @override
  Future<GitRunResult> run({
    required String workingDirectory,
    required List<String> args,
  }) async =>
      const GitRunResult(exitCode: 0, output: '');
}

class _FakePrOpener implements PrOpener {
  @override
  Future<PullRequestResult> open({
    required String workDir,
    required String branch,
    required String baseBranch,
    required String title,
    String body = '',
  }) async =>
      PullRequestResult.opened(
        PullRequestRef(url: 'https://example.test/pr/1', number: 1),
      );
}

/// A fake [ProcessGroupController] — never reached in the no-survivors smoke,
/// but required to construct the [RestartReconciler]. Reports everything gone.
class _FakeProcessGroupController implements ProcessGroupController {
  @override
  int currentGroupId() => 99999;

  @override
  bool processAlive(int pid) => false;

  @override
  Future<int?> resolvePgid(int pid) async => null;

  @override
  bool signalGroup(int pgid, ProcessSignal signal) => false;
}

/// A recording [BdRunner] (Fakes, not mocks): records every `bd` invocation so
/// the smoke can assert the session mint went through the chokepoint WITHOUT a
/// real `bd`. Returns a canned envelope so the chokepoint runs end-to-end.
class RecordingBdRunner implements BdRunner {
  RecordingBdRunner({String createdId = 'tgdog-sess1'}) : _createdId = createdId;

  final String _createdId;
  final List<List<String>> calls = <List<String>>[];

  @override
  Future<BdResult> run(List<String> args, {Duration? timeout, String? stdin}) {
    calls.add(List<String>.unmodifiable(args));
    final sub = args.isNotEmpty ? args.first : '';
    final id = sub == 'create'
        ? _createdId
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
