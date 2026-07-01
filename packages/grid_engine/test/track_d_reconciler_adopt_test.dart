// Track D (ADR-0009 D4) — the RestartReconciler generalizes respawn-or-skip to
// respawn-or-ADOPT (+ reattach-a-detached-survivor on one path) + the orphan
// sweep. The composer-supplied AdoptProof is the domain freshness half; the
// engine stays opinion-free. FULLY offline: FakeGit + a fake ProcessGroupController
// (the REAL guarded terminateGroup runs over it) + synthetic state beads.
//
// The existing respawn-or-skip contract (restart_reconciler_test.dart) is
// preserved unchanged (default proof = never adopt); this file exercises ONLY
// the new adopt + sweep behavior.
import 'dart:io';

import 'package:grid_controller/grid_controller.dart';
import 'package:grid_engine/grid_engine.dart';
import 'package:grid_runtime/grid_runtime.dart';
import 'package:test/test.dart';

class _FakeGit {
  _FakeGit({required this.worktrees, required this.log});
  final List<BeadWorktree>? worktrees;
  final List<String> log;
  final List<String> reaped = [];

  Future<List<BeadWorktree>?> listWorktrees(RootCheckout root) async {
    log.add('list');
    return worktrees;
  }

  Future<ReapOutcome> reapWorktree({
    required RootCheckout root,
    required BeadWorktree worktree,
  }) async {
    reaped.add(worktree.beadId);
    return ReapOutcome.removed();
  }
}

/// Clears ONLY the signalled group's leader pid, so independent groups terminate
/// independently.
class _Groups implements ProcessGroupController {
  _Groups({required Map<int, int> pgidToLeader, Set<int> alivePids = const {}})
    : _pgidToLeader = pgidToLeader,
      _alive = {...alivePids};

  final Map<int, int> _pgidToLeader;
  final Set<int> _alive;
  final List<(int, ProcessSignal)> signals = [];

  @override
  Future<int?> resolvePgid(int pid) async => null;

  @override
  bool processAlive(int pid) => _alive.contains(pid);

  @override
  bool signalGroup(int pgid, ProcessSignal signal) {
    signals.add((pgid, signal));
    if (signal == ProcessSignal.sigterm || signal == ProcessSignal.sigkill) {
      _alive.remove(_pgidToLeader[pgid]);
    }
    return true;
  }

  @override
  int currentGroupId() => 999;

  Set<int> get signalledPgids => signals.map((s) => s.$1).toSet();
}

Bead _sessionWithCursor({
  required String id,
  required String workBead,
  required Map<String, NodeCursor> cursor,
  bool closed = false,
}) {
  final meta = <String, dynamic>{'rig': 'tgdog', 'work_bead': workBead};
  cursor.forEach((path, node) => meta.addAll(nodeCursorMetadata(path, node)));
  return Bead(
    id: id,
    issueType: IssueType.session,
    status: closed ? BeadStatus.closed : BeadStatus.open,
    metadata: meta,
  );
}

GraphSnapshot _state(List<Bead> beads) => GraphSnapshot.fromParts(
  beads: beads,
  dependencies: const [],
  readyIds: const [],
  capturedAt: DateTime(2026, 7),
);

BeadWorktree _wt(String beadId) =>
    BeadWorktree(beadId: beadId, path: '/root/.grid/worktrees/tgdog/$beadId', branch: 'grid/$beadId');

const _root = RootCheckout(path: '/root', defaultBranch: 'main', substation: 'tgdog');

RestartReconciler _reconciler({
  required _FakeGit git,
  required _Groups groups,
  required GraphSnapshot state,
  AdoptProof? adoptProof,
}) => RestartReconciler(
  listWorktrees: git.listWorktrees,
  reapWorktree: git.reapWorktree,
  workRoot: _root,
  groups: groups,
  freshnessBarrier: () async {},
  stateSnapshot: () => state,
  adoptProof: adoptProof,
);

void main() {
  group('Track D — respawn-or-ADOPT (D4)', () {
    test('a live group the AdoptProof accepts is ADOPTED — left running, NOT '
        'killed, NOT reaped, NOT respawned', () async {
      final git = _FakeGit(worktrees: [_wt('tgdog-daemon')], log: []);
      final groups = _Groups(pgidToLeader: {5000: 5001}, alivePids: {5001});
      final state = _state([
        _sessionWithCursor(
          id: 'tgdog-s',
          workBead: 'tgdog-daemon',
          cursor: {
            'tgdog-daemon/harness': const NodeCursor(
              state: StepState.ready,
              pgid: 5000,
              pid: 5001,
              token: 't',
            ),
          },
        ),
      ]);
      final report = await _reconciler(
        git: git,
        groups: groups,
        state: state,
        adoptProof: (_, __, ___, ____) async => true,
      ).reconcile();

      expect(report.adopted.map((e) => e.beadId), ['tgdog-daemon']);
      expect(report.adopted.single.disposition, RestartDisposition.adopted);
      expect(groups.signals, isEmpty, reason: 'adopt never kills');
      expect(git.reaped, isEmpty, reason: 'adopt never reaps');
      expect(report.respawnCount, 0, reason: 'adopt is respawn-free');
      expect(report.killed, isEmpty);
    });

    test('mixed: an accepted daemon is adopted while a REFUSED crash orphan is '
        'killed ⇒ the worktree respawns (killed); only the orphan is signalled',
        () async {
      final git = _FakeGit(worktrees: [_wt('tgdog-mix')], log: []);
      final groups = _Groups(
        pgidToLeader: {5000: 5001, 6000: 6001},
        alivePids: {5001, 6001},
      );
      final state = _state([
        _sessionWithCursor(
          id: 'tgdog-mix-s',
          workBead: 'tgdog-mix',
          cursor: {
            'tgdog-mix/daemon': const NodeCursor(
              state: StepState.ready,
              pgid: 5000,
              pid: 5001,
            ),
            'tgdog-mix/orphan': const NodeCursor(
              state: StepState.running,
              pgid: 6000,
              pid: 6001,
            ),
          },
        ),
      ]);
      // Accept ONLY the daemon node; the orphan is not proven → killed.
      final report = await _reconciler(
        git: git,
        groups: groups,
        state: state,
        adoptProof: (_, __, nodePath, ___) async =>
            nodePath == 'tgdog-mix/daemon',
      ).reconcile();

      expect(report.killed.map((e) => e.beadId), ['tgdog-mix']);
      expect(groups.signalledPgids, {6000}, reason: 'only the orphan is killed');
      expect(report.respawnCount, 1);
    });

    test('no-adopt-on-faith: the DEFAULT proof (none injected) never adopts — a '
        'live group is killed (today respawn-or-skip)', () async {
      final git = _FakeGit(worktrees: [_wt('tgdog-def')], log: []);
      final groups = _Groups(pgidToLeader: {8000: 8001}, alivePids: {8001});
      final state = _state([
        _sessionWithCursor(
          id: 'tgdog-def-s',
          workBead: 'tgdog-def',
          cursor: {
            'tgdog-def/n': const NodeCursor(
              state: StepState.running,
              pgid: 8000,
              pid: 8001,
            ),
          },
        ),
      ]);
      final report = await _reconciler(git: git, groups: groups, state: state)
          .reconcile(); // no adoptProof

      expect(report.adopted, isEmpty);
      expect(report.killed, hasLength(1));
      expect(groups.signalledPgids, {8000});
    });
  });

  group('Track D — the orphan sweep (D4)', () {
    test('a TERMINAL session that left a daemon running ⇒ the group is SWEPT '
        '(killed) and the worktree reaped (skipped)', () async {
      final git = _FakeGit(worktrees: [_wt('tgdog-done')], log: []);
      final groups = _Groups(pgidToLeader: {9000: 9001}, alivePids: {9001});
      final state = _state([
        _sessionWithCursor(
          id: 'tgdog-done-s',
          workBead: 'tgdog-done',
          closed: true, // terminal — nobody re-adopts it
          cursor: {
            'tgdog-done/daemon': const NodeCursor(
              state: StepState.ready,
              pgid: 9000,
              pid: 9001,
            ),
          },
        ),
      ]);
      final report = await _reconciler(git: git, groups: groups, state: state)
          .reconcile();

      expect(report.skipped.map((e) => e.beadId), ['tgdog-done']);
      expect(git.reaped, ['tgdog-done'], reason: 'the worktree is reaped');
      expect(groups.signalledPgids, {9000},
          reason: 'the orphaned daemon is swept (killed)');
      expect(report.respawnCount, 0);
    });

    test('a terminal session with NO live group reaps with no sweep signal '
        '(the today path is unchanged)', () async {
      final git = _FakeGit(worktrees: [_wt('tgdog-clean')], log: []);
      final groups = _Groups(pgidToLeader: const {});
      final state = _state([
        _sessionWithCursor(
          id: 'tgdog-clean-s',
          workBead: 'tgdog-clean',
          closed: true,
          cursor: {
            'tgdog-clean/job': const NodeCursor(state: StepState.complete),
          },
        ),
      ]);
      final report = await _reconciler(git: git, groups: groups, state: state)
          .reconcile();

      expect(report.skipped, hasLength(1));
      expect(git.reaped, ['tgdog-clean']);
      expect(groups.signals, isEmpty);
    });
  });
}
