// The teardown-vs-spawn window: an agent spawned moments before `down`
// survived the graceful teardown. `RestartReconciler.sweepOrphans` reconciles
// the TRANSPORT against ZERO-EXPECTED after the unmount and reaps the
// straggler LOUDLY.
//
// The FENCE half (per-node `grid.cursor.*` pgid/pid fences on the own session
// beads) retired with the flat model (tg-eli phase 2): a session's process
// identity is the lease vendor's `grid.lease.*` breadcrumb, reconciled by the
// BOOT pass's molecule lease sweep — so `terminatedGroups` is always empty
// and a legacy cursor-bearing session bead is inert here (proven below).
// Fully offline (Fakes, not mocks).
import 'dart:async';
import 'dart:io';

import 'package:beads_dart/beads_dart.dart';
import 'package:grid_engine/grid_engine.dart';
import 'package:grid_engine/testing.dart';
import 'package:grid_runtime/grid_runtime.dart';
import 'package:test/test.dart';

const _prefix = 'tgstate-';
const _sessionId = 'tgstate-1';
const _agentName = '$_sessionId/tg-gpg/agent';

/// A fake process-group seam: records every signal + programmed per-pid
/// liveness — the sweep must NEVER signal now that the fence half is retired.
class _FakeGroups implements ProcessGroupController {
  _FakeGroups({Set<int> alivePids = const {}}) : _alive = {...alivePids};

  final Set<int> _alive;

  /// Every (pgid, signal) sent, in order.
  final List<(int, ProcessSignal)> signals = [];

  @override
  Future<int?> resolvePgid(int pid) async => null;

  @override
  bool processAlive(int pid) => _alive.contains(pid);

  @override
  bool signalGroup(int pgid, ProcessSignal signal) {
    signals.add((pgid, signal));
    _alive.clear(); // the group died
    return true;
  }

  @override
  int currentGroupId() => 999;
}

/// A transport that never lets go — proves the settle window is BOUNDED.
class _StubbornProvider implements RuntimeProvider {
  final List<String> stopped = [];

  @override
  List<String> listRunning(String prefix) => const [_agentName];

  @override
  Future<void> stop(String name) async => stopped.add(name);

  @override
  Future<void> start(String name, RuntimeConfig config) async {}
  @override
  Future<void> interrupt(String name) async {}
  @override
  Stream<RuntimeEvent> get events => const Stream<RuntimeEvent>.empty();
  @override
  Stream<String> output(String name) => const Stream<String>.empty();
  @override
  bool isRunning(String name) => true;
  @override
  bool processAlive(String name) => true;
  @override
  String peek(String name, int lines) => '';
  @override
  DateTime? lastActivity(String name) => null;
  @override
  RuntimeEvent? terminalOf(String name) => null;
  @override
  ({int pid, int? pgid})? identityOf(String name) => (pid: 4321, pgid: 4321);
  @override
  RuntimeCapabilities get capabilities => RuntimeCapabilities.subprocess;
}

/// The worktree seams: the teardown pass touches NEITHER (it reconciles the
/// transport only), so both refuse loudly if the sweep ever calls them.
Future<List<BeadWorktree>?> _noWorktrees(RootCheckout root) async =>
    throw StateError('sweepOrphans must not list worktrees');

Future<ReapOutcome> _noReap({
  required RootCheckout root,
  required BeadWorktree worktree,
}) async => throw StateError('sweepOrphans must not reap worktrees');

const _root = RootCheckout(
  path: '/root',
  defaultBranch: 'main',
  substation: 'proj',
);

GraphSnapshot _state(List<Bead> beads) => GraphSnapshot.fromParts(
  beads: beads,
  dependencies: const [],
  readyIds: const [],
  capturedAt: DateTime(2026, 7),
);

/// A HISTORICAL flat session bead still carrying the retired per-node
/// `grid.cursor.*` process fence (raw wire literals — the flat codec is
/// deleted). The sweep must treat it as INERT.
Bead _legacySession({required String id, required int pgid, required int pid}) =>
    Bead(
      id: id,
      issueType: IssueType.session,
      status: BeadStatus.open,
      metadata: <String, dynamic>{
        'rig': 'tgstate',
        'work_bead': 'tg-gpg',
        'grid.cursor.tg-gpg/agent.state': 'running',
        'grid.cursor.tg-gpg/agent.pgid': '$pgid',
        'grid.cursor.tg-gpg/agent.pid': '$pid',
        'grid.cursor.tg-gpg/agent.token': 'tok',
      },
    );

RestartReconciler _reconciler({
  required ProcessGroupController groups,
  GraphSnapshot? state,
}) => RestartReconciler(
  listWorktrees: _noWorktrees,
  reapWorktree: _noReap,
  workRoot: _root,
  groups: groups,
  freshnessBarrier: () async {},
  stateSnapshot: () => state ?? _state(const []),
);

void main() {
  group('sweepOrphans — the teardown-vs-spawn window', () {
    test('a spawn that LANDS mid-sweep is reaped, and reported LOUD', () async {
      final provider = FakeRuntimeProvider()..startGate = Completer<void>();
      addTearDown(provider.close);
      final log = <String>[];

      // THE WINDOW: the spawn is in flight (the host's fire-and-forget `stop`
      // already ran against a transport that does not yet hold the name).
      unawaited(
        provider.start(
          _agentName,
          const RuntimeConfig(workDir: '/tmp', command: 'sh'),
        ),
      );
      expect(
        provider.listRunning(_prefix),
        isEmpty,
        reason: 'the window: the transport does not hold it yet',
      );

      // Teardown ends with the sweep; the spawn LANDS while it re-passes.
      final swept = _reconciler(groups: _FakeGroups()).sweepOrphans(
        transport: provider,
        sessionPrefix: _prefix,
        onOrphan: log.add,
        pollInterval: const Duration(milliseconds: 5),
        settleWindow: const Duration(seconds: 2),
      );
      provider.startGate!.complete();
      final report = await swept;

      expect(report.stoppedSessions, [_agentName]);
      expect(provider.stopped, contains(_agentName));
      expect(
        provider.listRunning(_prefix),
        isEmpty,
        reason: 'zero-expected: nothing survives the sweep',
      );
      expect(report.settled, isTrue);
      expect(log.join('\n'), contains('SURVIVED the unmount'));
    });

    test(
      'EXISTING-STORE SAFETY: a legacy flat session bead with a live-pid '
      'grid.cursor.* fence is INERT — no crash, no signal, no '
      'terminatedGroups (the fence half retired, tg-eli phase 2)',
      () async {
        final provider = FakeRuntimeProvider();
        addTearDown(provider.close);
        final groups = _FakeGroups(alivePids: {77});
        final log = <String>[];

        final report =
            await _reconciler(
              groups: groups,
              state: _state([
                _legacySession(id: _sessionId, pgid: 4242, pid: 77),
              ]),
            ).sweepOrphans(
              transport: provider,
              sessionPrefix: _prefix,
              onOrphan: log.add,
              pollInterval: const Duration(milliseconds: 5),
            );

        expect(groups.signals, isEmpty);
        expect(report.terminatedGroups, isEmpty);
        expect(report.isClean, isTrue);
        expect(log, isEmpty);
      },
    );

    test('a clean teardown reaps nothing and logs NOTHING', () async {
      final provider = FakeRuntimeProvider();
      addTearDown(provider.close);
      final log = <String>[];

      final report = await _reconciler(groups: _FakeGroups()).sweepOrphans(
        transport: provider,
        sessionPrefix: _prefix,
        onOrphan: log.add,
        pollInterval: const Duration(milliseconds: 5),
      );

      expect(report.isClean, isTrue);
      expect(report.settled, isTrue);
      expect(log, isEmpty, reason: 'a clean sweep is silent');
    });

    test('the sweep is BOUNDED: a settle window that closes is reported LOUD, '
        'never a silent give-up', () async {
      final provider = _StubbornProvider();
      final log = <String>[];

      final report = await _reconciler(groups: _FakeGroups()).sweepOrphans(
        transport: provider,
        sessionPrefix: _prefix,
        onOrphan: log.add,
        pollInterval: const Duration(milliseconds: 5),
        settleWindow: const Duration(milliseconds: 30),
      );

      expect(report.settled, isFalse);
      expect(provider.stopped, isNotEmpty, reason: 'it kept trying');
      expect(log.join('\n'), contains('settle window'));
    });
  });
}
