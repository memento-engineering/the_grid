// The teardown-vs-spawn window: an agent spawned moments before `down`
// survived the graceful teardown (pid alive after the lock released).
// `RestartReconciler.sweepOrphans` reconciles the transport + the persisted
// restart fence against ZERO-EXPECTED after the unmount and reaps the straggler
// LOUDLY. Fully offline (Fakes, not mocks): the REAL terminateGroup runs over a
// fake ProcessGroupController, so its `pgid <= 1`/own-group guard and its
// leader-pid liveness fence are genuinely exercised.
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

/// A fake process-group seam: records every signal, reports a fixed own-group id
/// (so the own-group guard is testable) and programmed per-pid liveness. The
/// REAL [terminateGroup] runs over this.
class _FakeGroups implements ProcessGroupController {
  _FakeGroups({this.ownGroupId = 999, Set<int> alivePids = const {}})
    : _alive = {...alivePids};

  final int ownGroupId;
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
  int currentGroupId() => ownGroupId;
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
  RuntimeCapabilities get capabilities => RuntimeCapabilities.subprocess;
}

/// The worktree seams: the teardown pass touches NEITHER (it reconciles the
/// transport + the cursors), so both refuse loudly if the sweep ever calls them.
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

/// A STATE-store session bead carrying a per-node cursor (the restart fence).
Bead _session({
  required String id,
  required Map<String, NodeCursor> cursor,
  bool closed = false,
}) {
  final meta = <String, dynamic>{'rig': 'tgstate', 'work_bead': 'tg-gpg'};
  cursor.forEach((path, node) => meta.addAll(nodeCursorMetadata(path, node)));
  return Bead(
    id: id,
    issueType: IssueType.session,
    status: closed ? BeadStatus.closed : BeadStatus.open,
    metadata: meta,
  );
}

/// A running node holding a live process group.
Map<String, NodeCursor> _running({required int pgid, required int pid}) => {
  'tg-gpg/agent': NodeCursor(
    state: StepState.running,
    pgid: pgid,
    pid: pid,
    token: 'tok',
  ),
};

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

    test('the FENCE half reaps a live group the transport no longer holds',
        () async {
      final provider = FakeRuntimeProvider();
      addTearDown(provider.close);
      final groups = _FakeGroups(alivePids: {77});
      final log = <String>[];

      final report =
          await _reconciler(
            groups: groups,
            state: _state([
              _session(id: _sessionId, cursor: _running(pgid: 4242, pid: 77)),
            ]),
          ).sweepOrphans(
            transport: provider,
            sessionPrefix: _prefix,
            onOrphan: log.add,
            pollInterval: const Duration(milliseconds: 5),
          );

      expect(report.terminatedGroups.single.pgid, 4242);
      expect(
        report.terminatedGroups.single.result,
        GroupTerminateResult.exitedOnTerm,
      );
      expect(groups.signals.first, (4242, ProcessSignal.sigterm));
      expect(log.join('\n'), contains('ALIVE after the unmount'));
    });

    test('the liveness fence holds: a DEAD leader pid is never signalled',
        () async {
      final provider = FakeRuntimeProvider();
      addTearDown(provider.close);
      final groups = _FakeGroups(); // nothing alive
      final log = <String>[];

      final report =
          await _reconciler(
            groups: groups,
            state: _state([
              _session(id: _sessionId, cursor: _running(pgid: 4242, pid: 77)),
            ]),
          ).sweepOrphans(
            transport: provider,
            sessionPrefix: _prefix,
            onOrphan: log.add,
            pollInterval: const Duration(milliseconds: 5),
          );

      expect(groups.signals, isEmpty);
      expect(report.isClean, isTrue);
      expect(log, isEmpty);
    });

    test('the terminateGroup guard is NEVER bypassed: pgid 1 is refused, LOUD, '
        'once', () async {
      final provider = FakeRuntimeProvider();
      addTearDown(provider.close);
      final groups = _FakeGroups(alivePids: {77});
      final log = <String>[];

      final report =
          await _reconciler(
            groups: groups,
            state: _state([
              _session(id: _sessionId, cursor: _running(pgid: 1, pid: 77)),
            ]),
          ).sweepOrphans(
            transport: provider,
            sessionPrefix: _prefix,
            onOrphan: log.add,
            pollInterval: const Duration(milliseconds: 5),
          );

      expect(groups.signals, isEmpty, reason: 'the guard sent NO signal');
      expect(report.terminatedGroups, isEmpty);
      expect(report.settled, isTrue, reason: 'a refusal never spins the loop');
      expect(log.where((l) => l.contains('REFUSED')), hasLength(1));
    });

    test('the guard\'s other arm: the SUPERVISOR\'S OWN group is never '
        'signalled (that would kill the_grid itself)', () async {
      final provider = FakeRuntimeProvider();
      addTearDown(provider.close);
      final groups = _FakeGroups(ownGroupId: 4242, alivePids: {77});
      final log = <String>[];

      final report =
          await _reconciler(
            groups: groups,
            state: _state([
              // A recycled pgid that now names OUR OWN process group.
              _session(id: _sessionId, cursor: _running(pgid: 4242, pid: 77)),
            ]),
          ).sweepOrphans(
            transport: provider,
            sessionPrefix: _prefix,
            onOrphan: log.add,
            pollInterval: const Duration(milliseconds: 5),
          );

      expect(groups.signals, isEmpty);
      expect(report.terminatedGroups, isEmpty);
      expect(log.where((l) => l.contains('REFUSED')), hasLength(1));
    });

    test('kills are SCOPED: a session bead outside the owned prefix is never '
        'touched', () async {
      final provider = FakeRuntimeProvider();
      addTearDown(provider.close);
      final groups = _FakeGroups(alivePids: {77});
      final log = <String>[];

      final report =
          await _reconciler(
            groups: groups,
            state: _state([
              // A foreign partition's session (a live gc's, say) — NOT ours.
              _session(id: 'gc-9', cursor: _running(pgid: 4242, pid: 77)),
            ]),
          ).sweepOrphans(
            transport: provider,
            sessionPrefix: _prefix,
            onOrphan: log.add,
            pollInterval: const Duration(milliseconds: 5),
          );

      expect(groups.signals, isEmpty);
      expect(report.isClean, isTrue);
      expect(log, isEmpty);
    });

    test('a TERMINAL session is not a fence target (the boot reconcile owns its '
        'leftovers)', () async {
      final provider = FakeRuntimeProvider();
      addTearDown(provider.close);
      final groups = _FakeGroups(alivePids: {77});

      final report =
          await _reconciler(
            groups: groups,
            state: _state([
              _session(
                id: _sessionId,
                cursor: _running(pgid: 4242, pid: 77),
                closed: true,
              ),
            ]),
          ).sweepOrphans(
            transport: provider,
            sessionPrefix: _prefix,
            onOrphan: (_) {},
            pollInterval: const Duration(milliseconds: 5),
          );

      expect(groups.signals, isEmpty);
      expect(report.isClean, isTrue);
    });

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
