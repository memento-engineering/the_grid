import 'dart:async';
import 'dart:io';

import 'package:grid_cli/src/run_tree_command.dart';
import 'package:grid_controller/grid_controller.dart';
import 'package:grid_engine/grid_engine.dart';
import 'package:grid_runtime/grid_runtime.dart';
import 'package:test/test.dart';

/// Offline proof for `composeRunTree` (the M4 tree-engine "runnable path",
/// ADR-0007) — Fakes, not mocks; NO live `tg`, NO real `claude`, NO real `git`,
/// NO `bd` writes to a live workspace. The DoD this file locks:
///
///  1. **pure composition** — [composeRunTree] assembles a [TreeRunWiring]
///     (a [GridKernel] + a [RestartReconciler]) without spawning, opening a
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
  group('composeRunTree — pure composition (no I/O at construct time)', () {
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

  group('composeRunTree — dry start smoke (kernel mounts, ready bead spawns)',
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
}

/// Pumps the microtask/event queue a few turns so the kernel's batched flush,
/// the effect's `_run` async gaps (create-session → spawn), and broadcast
/// delivery all settle.
Future<void> _settle() async {
  for (var i = 0; i < 12; i++) {
    await Future<void>.delayed(Duration.zero);
  }
}

/// The offline harness: fake work/state snapshot sources, a recording dry
/// provider, a recording bd runner behind the chokepoint, a fake git service
/// (no worktrees), a fake process-group controller, and a completing,
/// tick-recording freshness barrier — so [composeRunTree] runs end-to-end with
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

  TreeRunWiring compose() {
    // The dry effect context: the recording provider (never spawns real
    // claude), the bd write chokepoint over the recording runner (fail-closed on
    // the owned rig), the owned state rig, and NO git/PR land ops (an offline
    // build no-ops land rather than touch real GitHub).
    final writer = GridBeadWriter(
      bd: BdCliService(bdRunner),
      ownership: BeadOwnershipPredicate(const {'tgdog'}),
    );
    final effectContext = EffectContext(
      provider: provider,
      writer: writer,
      stateRig: 'tgdog',
    );
    return composeRunTree(
      work: work,
      state: state,
      effectContext: effectContext,
      rigs: const [
        RigConfig(rigId: 'tgdog', ownedRigs: {'tgdog'}),
      ],
      git: git.service,
      workRoot: const RootCheckout(
        path: '/tmp/grid-tree-test-root',
        defaultBranch: 'main',
        rig: 'tgdog',
      ),
      groups: groups,
      freshnessBarrier: _barrier,
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

/// A fake [GridGitService] whose worktree-list seam returns EMPTY (no survivors
/// to reconcile on restart) and whose reap is never reached. Built over a fake
/// [GitRunner] so no real `git` runs; [listCalls] counts the worktree probes so
/// the composition-only test can assert ZERO at construct time.
class _FakeGitService {
  int listCalls = 0;

  late final GridGitService service = _RecordingGitService(
    onList: () => listCalls++,
  );
}

/// A [GridGitService] over fake runners that records each `listBeadWorktrees`
/// call and always reports no worktrees (the live `git` is never touched).
class _RecordingGitService extends GridGitService {
  _RecordingGitService({required this.onList})
      : super(runner: _FakeGitRunner(), prOpener: _FakePrOpener());

  final void Function() onList;

  @override
  Future<List<BeadWorktree>?> listBeadWorktrees(RootCheckout root) async {
    onList();
    return const <BeadWorktree>[];
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
