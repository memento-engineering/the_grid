import 'dart:io';

import 'package:grid_controller/grid_controller.dart';
import 'package:grid_engine/grid_engine.dart';
import 'package:grid_runtime/grid_runtime.dart';
import 'package:test/test.dart';

// ---------------------------------------------------------------------------
// Fakes (Fakes, not mocks). The restart pass runs FULLY offline:
//  - a FakeGit records reap + serves a programmed worktree list, satisfying the
//    narrow ListBeadWorktrees / ReapWorktree seams the reconciler injects (so
//    the engine never names the concrete VCS service — ADR-0007 §1).
//  - a fake ProcessGroupController records signalGroup + reports liveness, so
//    the REAL terminateGroup runs and its `pgid <= 1`/own-group guard is
//    genuinely exercised.
//  - a synthetic state GraphSnapshot of `type=session` beads supplies cursors.
//  - a shared event log proves the freshness barrier completes FIRST.
// ---------------------------------------------------------------------------

/// Records list/reap calls onto a shared [log] (for ordering) and serves a
/// programmed worktree list + per-bead reap outcomes. Exposes [listWorktrees]
/// and [reapWorktree] matching the reconciler's narrow seams (the real binding
/// is to the grid git service's `listBeadWorktrees`/`reap`).
class FakeGit {
  FakeGit({
    required this.worktrees,
    required this.log,
    Map<String, ReapOutcome>? reapOutcomes,
  }) : reapOutcomes = reapOutcomes ?? const {};

  /// The survivors `listWorktrees` returns (null ⇒ a probe error).
  final List<BeadWorktree>? worktrees;

  /// The outcome `reapWorktree` returns per bead id (defaults to removed).
  final Map<String, ReapOutcome> reapOutcomes;

  /// Shared ordering log.
  final List<String> log;

  /// The bead ids `reapWorktree` was called for, in order.
  final List<String> reaped = [];

  Future<List<BeadWorktree>?> listWorktrees(RootCheckout root) async {
    log.add('list');
    return worktrees;
  }

  Future<ReapOutcome> reapWorktree({
    required RootCheckout root,
    required BeadWorktree worktree,
  }) async {
    log.add('reap:${worktree.beadId}');
    reaped.add(worktree.beadId);
    return reapOutcomes[worktree.beadId] ?? ReapOutcome.removed();
  }
}

/// A fake process-group seam. Records every group signal; reports a fixed
/// own-group id (so the own-group guard is testable) and programmed per-pid
/// liveness. The REAL [terminateGroup] runs over this.
class FakeProcessGroupController implements ProcessGroupController {
  FakeProcessGroupController({
    required this.ownGroupId,
    required this.log,
    Set<int> alivePids = const {},
  }) : _alive = {...alivePids};

  final int ownGroupId;
  final List<String> log;
  final Set<int> _alive;

  /// Every (pgid, signal) sent, in order.
  final List<(int, ProcessSignal)> signals = [];

  @override
  Future<int?> resolvePgid(int pid) async => null;

  @override
  bool processAlive(int pid) => _alive.contains(pid);

  @override
  bool signalGroup(int pgid, ProcessSignal signal) {
    log.add('signal:$pgid:${signal.toString()}');
    signals.add((pgid, signal));
    // A SIGTERM/SIGKILL to the group kills the whole group, so the leader pid
    // (the liveness-probe subject) goes away — terminateGroup's poll then
    // observes the exit within the grace window and returns exitedOnTerm
    // (no SIGKILL escalation). One orphan per test, so clearing all is the
    // group dying.
    if (signal == ProcessSignal.sigterm || signal == ProcessSignal.sigkill) {
      _alive.clear();
    }
    return true;
  }

  @override
  int currentGroupId() => ownGroupId;
}

/// Builds a synthetic STATE-store session bead.
Bead _session({
  required String id,
  required String workBead,
  bool closed = false,
  String phase = 'implement',
  int? pgid,
  int? pid,
  String? token,
}) {
  return Bead(
    id: id,
    issueType: IssueType.session,
    status: closed ? BeadStatus.closed : BeadStatus.open,
    metadata: <String, dynamic>{
      'rig': 'tgdog',
      'work_bead': workBead,
      'grid.phase': phase,
      if (pgid != null) 'pgid': '$pgid',
      if (pid != null) 'pid': '$pid',
      if (token != null) 'token': token,
    },
  );
}

/// Builds a STATE-store session bead carrying a per-node cursor (D-4) — the
/// reentrant identity, written as flat `grid.cursor.*` metadata.
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

/// A process-group fake that clears ONLY the signalled group's leader pid (so a
/// session with N concurrent live groups terminates each independently — the
/// single-orphan [FakeProcessGroupController] clears all pids at once).
class _PerGroupController implements ProcessGroupController {
  _PerGroupController({
    required this.ownGroupId,
    required this.log,
    required Map<int, int> pgidToLeader,
    Set<int> alivePids = const {},
  }) : _pgidToLeader = pgidToLeader,
       _alive = {...alivePids};

  final int ownGroupId;
  final List<String> log;
  final Map<int, int> _pgidToLeader;
  final Set<int> _alive;
  final List<(int, ProcessSignal)> signals = [];

  @override
  Future<int?> resolvePgid(int pid) async => null;

  @override
  bool processAlive(int pid) => _alive.contains(pid);

  @override
  bool signalGroup(int pgid, ProcessSignal signal) {
    log.add('signal:$pgid');
    signals.add((pgid, signal));
    if (signal == ProcessSignal.sigterm || signal == ProcessSignal.sigkill) {
      _alive.remove(_pgidToLeader[pgid]); // only THIS group's leader dies
    }
    return true;
  }

  @override
  int currentGroupId() => ownGroupId;
}

GraphSnapshot _stateSnapshotOf(List<Bead> beads) => GraphSnapshot.fromParts(
  beads: beads,
  dependencies: const [],
  readyIds: const [],
  capturedAt: DateTime(2026, 6, 25),
);

BeadWorktree _wt(String beadId) => BeadWorktree(
  beadId: beadId,
  path: '/Users/nico/development/engineering.memento/lenny-tgdog/'
      '.grid/worktrees/tgdog/$beadId',
  branch: 'grid/$beadId',
);

const _workRoot = RootCheckout(
  path: '/Users/nico/development/engineering.memento/lenny-tgdog',
  defaultBranch: 'main',
  substation: 'tgdog',
);

void main() {
  group('RestartReconciler — simulated restart, FOREIGN-rig arm', () {
    test(
      'bead A: a FOREIGN work bead with a TERMINAL owned session ⇒ SKIPPED '
      '(reaped, never terminated, marked skipped)',
      () async {
        final log = <String>[];
        // The work bead id is FOREIGN (genesis-*) — the_grid could never stamp
        // it. The cursor lives on the OWNED tgdog session, which is terminal.
        final git = FakeGit(
          worktrees: [_wt('genesis-aaa')],
          log: log,
        );
        final groups = FakeProcessGroupController(ownGroupId: 999, log: log);
        final state = _stateSnapshotOf([
          _session(id: 'tgdog-1', workBead: 'genesis-aaa', closed: true),
        ]);

        final reconciler = RestartReconciler(
          listWorktrees: git.listWorktrees,
          reapWorktree: git.reapWorktree,
          workRoot: _workRoot,
          groups: groups,
          freshnessBarrier: () async {},
          stateSnapshot: () => state,
        );
        final report = await reconciler.reconcile();

        expect(report.skipped, hasLength(1));
        final entry = report.skipped.single;
        expect(entry.beadId, 'genesis-aaa');
        expect(entry.disposition, RestartDisposition.skipped);
        expect(entry.sessionId, 'tgdog-1');
        expect(entry.reapOutcome!.removed, isTrue);

        // git.reap WAS called for the foreign bead; terminateGroup NEVER ran.
        expect(git.reaped, ['genesis-aaa']);
        expect(groups.signals, isEmpty);
        expect(report.killed, isEmpty);
        expect(report.respawnPending, isEmpty);
        expect(report.respawnCount, 0);
      },
    );

    test(
      'bead B: a live non-terminal session with pgid=4242 ⇒ terminateGroup '
      'called BEFORE any respawn, marked killed; reap NOT called',
      () async {
        final log = <String>[];
        final git = FakeGit(worktrees: [_wt('tgdog-work-b')], log: log);
        // The leader pid (4243) is alive, so the real guard sends SIGTERM.
        final groups = FakeProcessGroupController(
          ownGroupId: 999,
          log: log,
          alivePids: {4243},
        );
        final state = _stateSnapshotOf([
          _session(
            id: 'tgdog-2',
            workBead: 'tgdog-work-b',
            pgid: 4242,
            pid: 4243,
            token: 'cafef00d',
          ),
        ]);

        final reconciler = RestartReconciler(
          listWorktrees: git.listWorktrees,
          reapWorktree: git.reapWorktree,
          workRoot: _workRoot,
          groups: groups,
          freshnessBarrier: () async {},
          stateSnapshot: () => state,
        );
        final report = await reconciler.reconcile();

        expect(report.killed, hasLength(1));
        final entry = report.killed.single;
        expect(entry.beadId, 'tgdog-work-b');
        expect(entry.disposition, RestartDisposition.killed);
        expect(entry.terminateResult, GroupTerminateResult.exitedOnTerm);

        // terminateGroup signalled the RIGHT group (4242); reap never ran.
        expect(groups.signals.first.$1, 4242);
        expect(groups.signals.first.$2, ProcessSignal.sigterm);
        expect(git.reaped, isEmpty);

        // It is respawn-pending (killed ⇒ tree re-mounts + respawns).
        expect(report.respawnCount, 1);

        // Ordering: the kill happened (it appears in the shared log).
        expect(log.contains('signal:4242:${ProcessSignal.sigterm}'), isTrue);
      },
    );

    test(
      'bead C: a live session with pgid=1 ⇒ terminateGroup refusedUnsafe; '
      'bead stays respawn-pending (NOT skipped, NOT reaped, NOT signalled)',
      () async {
        final log = <String>[];
        final git = FakeGit(worktrees: [_wt('tgdog-work-c')], log: log);
        final groups = FakeProcessGroupController(
          ownGroupId: 999,
          log: log,
          alivePids: {7},
        );
        final state = _stateSnapshotOf([
          _session(
            id: 'tgdog-3',
            workBead: 'tgdog-work-c',
            pgid: 1, // init group — the load-bearing safety guard refuses it.
            pid: 7,
          ),
        ]);

        final reconciler = RestartReconciler(
          listWorktrees: git.listWorktrees,
          reapWorktree: git.reapWorktree,
          workRoot: _workRoot,
          groups: groups,
          freshnessBarrier: () async {},
          stateSnapshot: () => state,
        );
        final report = await reconciler.reconcile();

        expect(report.refusedUnsafe, hasLength(1));
        final entry = report.refusedUnsafe.single;
        expect(entry.disposition, RestartDisposition.refusedUnsafe);
        expect(entry.terminateResult, GroupTerminateResult.refusedUnsafe);

        // The guard sent NO signal; nothing was reaped; it IS respawn-pending.
        expect(groups.signals, isEmpty);
        expect(git.reaped, isEmpty);
        expect(report.skipped, isEmpty);
        expect(report.respawnCount, 1);
      },
    );

    test(
      'pgid==0 also refusedUnsafe (the other arm of pgid <= 1)',
      () async {
        final log = <String>[];
        final git = FakeGit(worktrees: [_wt('tgdog-work-c0')], log: log);
        final groups = FakeProcessGroupController(
          ownGroupId: 999,
          log: log,
          alivePids: {8},
        );
        final state = _stateSnapshotOf([
          _session(id: 'tgdog-3b', workBead: 'tgdog-work-c0', pgid: 0, pid: 8),
        ]);

        final report = await RestartReconciler(
          listWorktrees: git.listWorktrees,
          reapWorktree: git.reapWorktree,
          workRoot: _workRoot,
          groups: groups,
          freshnessBarrier: () async {},
          stateSnapshot: () => state,
        ).reconcile();

        expect(report.refusedUnsafe.single.terminateResult,
            GroupTerminateResult.refusedUnsafe);
        expect(groups.signals, isEmpty);
      },
    );

    test(
      'a pgid == the supervisor own-group is refused too (own-group guard)',
      () async {
        final log = <String>[];
        final git = FakeGit(worktrees: [_wt('tgdog-own')], log: log);
        const ownGroup = 555;
        final groups = FakeProcessGroupController(
          ownGroupId: ownGroup,
          log: log,
          alivePids: {600},
        );
        final state = _stateSnapshotOf([
          _session(id: 'tgdog-own-s', workBead: 'tgdog-own', pgid: ownGroup, pid: 600),
        ]);

        final report = await RestartReconciler(
          listWorktrees: git.listWorktrees,
          reapWorktree: git.reapWorktree,
          workRoot: _workRoot,
          groups: groups,
          freshnessBarrier: () async {},
          stateSnapshot: () => state,
        ).reconcile();

        expect(report.refusedUnsafe.single.terminateResult,
            GroupTerminateResult.refusedUnsafe);
        expect(groups.signals, isEmpty);
      },
    );

    test(
      'a worktree with NO session record ⇒ respawn-pending, no kill, no reap',
      () async {
        final log = <String>[];
        final git = FakeGit(worktrees: [_wt('genesis-orphan')], log: log);
        final groups = FakeProcessGroupController(ownGroupId: 999, log: log);
        final state = _stateSnapshotOf(const []); // no sessions at all.

        final report = await RestartReconciler(
          listWorktrees: git.listWorktrees,
          reapWorktree: git.reapWorktree,
          workRoot: _workRoot,
          groups: groups,
          freshnessBarrier: () async {},
          stateSnapshot: () => state,
        ).reconcile();

        expect(report.respawnPending, hasLength(1));
        final entry = report.respawnPending.single;
        expect(entry.beadId, 'genesis-orphan');
        expect(entry.disposition, RestartDisposition.respawnPending);
        expect(entry.sessionId, isNull);
        expect(git.reaped, isEmpty);
        expect(groups.signals, isEmpty);
        expect(report.respawnCount, 1);
      },
    );

    test(
      'a live session with a pgid but NO leader pid ⇒ respawn-pending '
      '(no usable kill target, no signal sent)',
      () async {
        final log = <String>[];
        final git = FakeGit(worktrees: [_wt('tgdog-nopid')], log: log);
        final groups = FakeProcessGroupController(ownGroupId: 999, log: log);
        final state = _stateSnapshotOf([
          // pgid present but pid (the liveness-probe subject) missing.
          _session(id: 'tgdog-np', workBead: 'tgdog-nopid', pgid: 4242),
        ]);

        final report = await RestartReconciler(
          listWorktrees: git.listWorktrees,
          reapWorktree: git.reapWorktree,
          workRoot: _workRoot,
          groups: groups,
          freshnessBarrier: () async {},
          stateSnapshot: () => state,
        ).reconcile();

        expect(report.respawnPending, hasLength(1));
        expect(report.respawnPending.single.disposition,
            RestartDisposition.respawnPending);
        expect(groups.signals, isEmpty);
        expect(git.reaped, isEmpty);
      },
    );

    test(
      'ordering: the freshnessBarrier completes BEFORE listBeadWorktrees and '
      'before any terminate',
      () async {
        final log = <String>[];
        final git = FakeGit(worktrees: [_wt('tgdog-ord')], log: log);
        final groups = FakeProcessGroupController(
          ownGroupId: 999,
          log: log,
          alivePids: {4243},
        );
        final state = _stateSnapshotOf([
          _session(
            id: 'tgdog-ord-s',
            workBead: 'tgdog-ord',
            pgid: 4242,
            pid: 4243,
          ),
        ]);

        var barrierDone = false;
        final reconciler = RestartReconciler(
          listWorktrees: git.listWorktrees,
          reapWorktree: git.reapWorktree,
          workRoot: _workRoot,
          groups: groups,
          // An async barrier that yields the event loop, then records its
          // completion onto the shared log AFTER a microtask gap. If list/kill
          // ran on stale state, they would appear before 'barrier' in the log.
          freshnessBarrier: () async {
            await Future<void>.delayed(const Duration(milliseconds: 5));
            barrierDone = true;
            log.add('barrier');
          },
          stateSnapshot: () {
            // The state snapshot must only be READ after the barrier resolved.
            expect(barrierDone, isTrue,
                reason: 'cursors projected on post-barrier state only');
            return state;
          },
        );
        await reconciler.reconcile();

        // The barrier is the FIRST log entry; list + signal follow it.
        expect(log.first, 'barrier');
        final barrierIdx = log.indexOf('barrier');
        final listIdx = log.indexOf('list');
        final signalIdx =
            log.indexWhere((e) => e.startsWith('signal:'));
        expect(barrierIdx, lessThan(listIdx),
            reason: 'barrier completes before worktrees are listed');
        expect(barrierIdx, lessThan(signalIdx),
            reason: 'barrier completes before any group is terminated');
        expect(listIdx, lessThan(signalIdx),
            reason: 'worktrees listed before any kill');
      },
    );

    test(
      'a null worktree probe (fail-closed) ⇒ an empty report, no kills/reaps',
      () async {
        final log = <String>[];
        final git = FakeGit(worktrees: null, log: log);
        final groups = FakeProcessGroupController(ownGroupId: 999, log: log);
        final state = _stateSnapshotOf([
          _session(id: 'tgdog-x', workBead: 'tgdog-x-w', closed: true),
        ]);

        final report = await RestartReconciler(
          listWorktrees: git.listWorktrees,
          reapWorktree: git.reapWorktree,
          workRoot: _workRoot,
          groups: groups,
          freshnessBarrier: () async {},
          stateSnapshot: () => state,
        ).reconcile();

        expect(report.entries, isEmpty);
        expect(git.reaped, isEmpty);
        expect(groups.signals, isEmpty);
      },
    );

    test(
      'a full restart with all four cases at once reconciles each correctly',
      () async {
        final log = <String>[];
        final git = FakeGit(
          worktrees: [
            _wt('genesis-done'), // A: foreign + terminal ⇒ skipped
            _wt('tgdog-live'), // B: live + pgid ⇒ killed
            _wt('tgdog-init'), // C: live + pgid=1 ⇒ refusedUnsafe
            _wt('genesis-fresh'), // D: no session ⇒ respawn-pending
          ],
          log: log,
        );
        final groups = FakeProcessGroupController(
          ownGroupId: 999,
          log: log,
          alivePids: {2001, 3001},
        );
        final state = _stateSnapshotOf([
          _session(id: 'tgdog-a', workBead: 'genesis-done', closed: true),
          _session(id: 'tgdog-b', workBead: 'tgdog-live', pgid: 2000, pid: 2001),
          _session(id: 'tgdog-c', workBead: 'tgdog-init', pgid: 1, pid: 3001),
        ]);

        final report = await RestartReconciler(
          listWorktrees: git.listWorktrees,
          reapWorktree: git.reapWorktree,
          workRoot: _workRoot,
          groups: groups,
          freshnessBarrier: () async {},
          stateSnapshot: () => state,
        ).reconcile();

        expect(report.skipped.map((e) => e.beadId), ['genesis-done']);
        expect(report.killed.map((e) => e.beadId), ['tgdog-live']);
        expect(report.refusedUnsafe.map((e) => e.beadId), ['tgdog-init']);
        expect(report.respawnPending.map((e) => e.beadId), ['genesis-fresh']);

        // Only the done bead is reaped; only the live orphan is signalled.
        expect(git.reaped, ['genesis-done']);
        expect(groups.signals.single.$1, 2000);

        // respawnCount = everything except the skipped done bead.
        expect(report.respawnCount, 3);
      },
    );
  });

  group('RestartReconciler — D-4 per-node respawn (the reentrant Burn arm)', () {
    test(
      'a session with N live per-node groups terminates EVERY one (not just '
      'a scalar pgid); a completed node is not killed',
      () async {
        final log = <String>[];
        final git = FakeGit(worktrees: [_wt('tgdog-burn')], log: log);
        // Two live daemon groups + one completed job (no kill target).
        final groups = _PerGroupController(
          ownGroupId: 999,
          log: log,
          pgidToLeader: {5000: 5001, 6000: 6001},
          alivePids: {5001, 6001},
        );
        final state = _stateSnapshotOf([
          _sessionWithCursor(
            id: 'tgdog-burn-s',
            workBead: 'tgdog-burn',
            cursor: {
              'tgdog-burn/harnessPeripheral/launch': const NodeCursor(
                state: StepState.ready,
                pgid: 5000,
                pid: 5001,
                token: 'tA',
              ),
              'tgdog-burn/harnessCentral/launch': const NodeCursor(
                state: StepState.running,
                pgid: 6000,
                pid: 6001,
                token: 'tB',
              ),
              'tgdog-burn/coordinator': const NodeCursor(
                state: StepState.complete, // not live → never signalled
              ),
            },
          ),
        ]);

        final report = await RestartReconciler(
          listWorktrees: git.listWorktrees,
          reapWorktree: git.reapWorktree,
          workRoot: _workRoot,
          groups: groups,
          freshnessBarrier: () async {},
          stateSnapshot: () => state,
        ).reconcile();

        // One worktree entry, killed; BOTH live groups terminated (the D-4 fix —
        // the P0 scalar reconciler had no scalar pgid here and would have killed
        // NONE, then respawned over still-live daemons).
        expect(report.killed, hasLength(1));
        expect(groups.signals.map((s) => s.$1).toSet(), {5000, 6000});
        expect(report.respawnCount, 1);
      },
    );

    test(
      'mixed per-node: one live group killed + one pgid<=1 refused ⇒ the '
      'worktree is killed (any group signalled) and respawn-pending',
      () async {
        final log = <String>[];
        final git = FakeGit(worktrees: [_wt('tgdog-mix')], log: log);
        final groups = _PerGroupController(
          ownGroupId: 999,
          log: log,
          pgidToLeader: {7000: 7001},
          alivePids: {7001, 9},
        );
        final state = _stateSnapshotOf([
          _sessionWithCursor(
            id: 'tgdog-mix-s',
            workBead: 'tgdog-mix',
            cursor: {
              'tgdog-mix/a': const NodeCursor(
                state: StepState.running,
                pgid: 7000,
                pid: 7001,
              ),
              'tgdog-mix/b': const NodeCursor(
                state: StepState.running,
                pgid: 1, // unsafe — refused, no signal
                pid: 9,
              ),
            },
          ),
        ]);

        final report = await RestartReconciler(
          listWorktrees: git.listWorktrees,
          reapWorktree: git.reapWorktree,
          workRoot: _workRoot,
          groups: groups,
          freshnessBarrier: () async {},
          stateSnapshot: () => state,
        ).reconcile();

        expect(report.killed, hasLength(1));
        // Only the safe group was signalled; the pgid=1 group was refused.
        expect(groups.signals.map((s) => s.$1), [7000]);
        expect(report.respawnCount, 1);
      },
    );

    test(
      'all per-node groups refused (every pgid<=1) ⇒ refusedUnsafe, no signal',
      () async {
        final log = <String>[];
        final git = FakeGit(worktrees: [_wt('tgdog-allbad')], log: log);
        final groups = _PerGroupController(
          ownGroupId: 999,
          log: log,
          pgidToLeader: const {},
          alivePids: {10, 11},
        );
        final state = _stateSnapshotOf([
          _sessionWithCursor(
            id: 'tgdog-allbad-s',
            workBead: 'tgdog-allbad',
            cursor: {
              'tgdog-allbad/a': const NodeCursor(
                state: StepState.running,
                pgid: 1,
                pid: 10,
              ),
              'tgdog-allbad/b': const NodeCursor(
                state: StepState.ready,
                pgid: 0,
                pid: 11,
              ),
            },
          ),
        ]);

        final report = await RestartReconciler(
          listWorktrees: git.listWorktrees,
          reapWorktree: git.reapWorktree,
          workRoot: _workRoot,
          groups: groups,
          freshnessBarrier: () async {},
          stateSnapshot: () => state,
        ).reconcile();

        expect(report.refusedUnsafe, hasLength(1));
        expect(groups.signals, isEmpty);
        expect(report.respawnCount, 1);
      },
    );
  });
}
