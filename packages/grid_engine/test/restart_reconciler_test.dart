// Track D — the restart respawn-or-skip reconciler, post tg-eli phase 2 (the
// flat-cursor model retired; the molecule lease sweep — proven in
// restart_reconciler_molecule_test.dart — is the ONE process-identity
// reconciliation).
//
// Fakes, not mocks. The restart pass runs FULLY offline:
//  - a FakeGit records reap + serves a programmed worktree list, satisfying the
//    narrow ListBeadWorktrees / ReapWorktree seams the reconciler injects (so
//    the engine never names the concrete VCS service — ADR-0007 §1).
//  - a fake ProcessGroupController records liveness probes/signals, proving the
//    retired flat kill fence sends NOTHING any more.
//  - a synthetic state GraphSnapshot of `type=session` beads supplies the
//    projections.
//  - a shared event log proves the freshness barrier completes FIRST.
import 'dart:io';

import 'package:beads_dart/beads_dart.dart';
import 'package:grid_engine/grid_engine.dart';
import 'package:grid_engine/testing.dart';
import 'package:grid_runtime/grid_runtime.dart';
import 'package:test/test.dart';

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

/// A fake process-group seam. Records every group signal + programmed per-pid
/// liveness — post phase 2 the per-worktree pass must NEVER signal (the flat
/// kill fence is gone; kills belong to the molecule lease sweep).
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
    log.add('signal:$pgid:$signal');
    signals.add((pgid, signal));
    if (signal == ProcessSignal.sigterm || signal == ProcessSignal.sigkill) {
      _alive.clear();
    }
    return true;
  }

  @override
  int currentGroupId() => ownGroupId;
}

/// The recording bd chokepoint over the OWNED state substation (`tgdog`) —
/// wired so `hasChokepoint` reads true; post phase 2 the pass issues NO writes
/// of its own, which these tests assert.
({StationBeadWriter writer, RecordingBdRunner bd}) _chokepoint() {
  final bd = RecordingBdRunner();
  return (
    writer: StationBeadWriter(
      bd: BdCliService(bd),
      ownership: BeadOwnershipPredicate(const {'tgdog'}),
    ),
    bd: bd,
  );
}

/// Builds a synthetic STATE-store session bead. [pgid]/[pid]/[token] stage the
/// LEGACY scalar identity a historical flat bead may still carry; [metadata]
/// stages arbitrary further legacy keys (e.g. `grid.cursor.*`).
Bead _session({
  required String id,
  required String workBead,
  bool closed = false,
  int? pgid,
  int? pid,
  String? token,
  Map<String, String> metadata = const {},
}) {
  return Bead(
    id: id,
    issueType: IssueType.session,
    status: closed ? BeadStatus.closed : BeadStatus.open,
    metadata: <String, dynamic>{
      'rig': 'tgdog',
      'work_bead': workBead,
      if (pgid != null) 'pgid': '$pgid',
      if (pid != null) 'pid': '$pid',
      if (token != null) 'token': token,
      ...metadata,
    },
  );
}

/// The HISTORICAL flat per-node cursor metadata a real pre-phase-2 store row
/// carries (`grid.cursor.{nodePath}.{field}`, no `grid.session.model` marker)
/// — written as raw wire literals here because the flat codec itself is
/// deleted. The existing-store safety tests feed these to prove every
/// surviving read treats them as INERT (never parsed, never thrown on).
Map<String, String> _legacyFlatCursor(
  String nodePath, {
  String state = 'running',
  int? pgid,
  int? pid,
}) => {
  'grid.cursor.$nodePath.state': state,
  'grid.cursor.$nodePath.restartCount': '2',
  'grid.cursor.$nodePath.rewindCount': '1',
  if (pgid != null) 'grid.cursor.$nodePath.pgid': '$pgid',
  if (pid != null) 'grid.cursor.$nodePath.pid': '$pid',
};

GraphSnapshot _stateSnapshotOf(List<Bead> beads) => GraphSnapshot.fromParts(
  beads: beads,
  dependencies: const [],
  readyIds: const [],
  capturedAt: DateTime(2026, 6, 25),
);

BeadWorktree _wt(String beadId) => BeadWorktree(
  beadId: beadId,
  path: '/workspace/example-substation/'
      '.grid/worktrees/tgdog/$beadId',
  branch: 'grid/$beadId',
);

const _workRoot = RootCheckout(
  path: '/workspace/example-substation',
  defaultBranch: 'main',
  substation: 'tgdog',
);

RestartReconciler _reconciler({
  required FakeGit git,
  required FakeProcessGroupController groups,
  required GraphSnapshot state,
  StationBeadWriter? writer,
  Future<void> Function()? freshnessBarrier,
  GraphSnapshot Function()? stateSnapshot,
}) => RestartReconciler(
  listWorktrees: git.listWorktrees,
  reapWorktree: git.reapWorktree,
  workRoot: _workRoot,
  groups: groups,
  writer: writer ?? _chokepoint().writer,
  freshnessBarrier: freshnessBarrier ?? () async {},
  stateSnapshot: stateSnapshot ?? () => state,
);

void main() {
  group('RestartReconciler — respawn-or-skip (the surviving contract)', () {
    test(
      'a FOREIGN work bead with a TERMINAL owned session ⇒ SKIPPED '
      '(reaped, never signalled, marked skipped)',
      () async {
        final log = <String>[];
        // The work bead id is FOREIGN (genesis-*) — the_grid could never stamp
        // it. The done evidence is on the OWNED tgdog session, which is
        // terminal.
        final git = FakeGit(worktrees: [_wt('genesis-aaa')], log: log);
        final groups = FakeProcessGroupController(ownGroupId: 999, log: log);
        final state = _stateSnapshotOf([
          _session(id: 'tgdog-1', workBead: 'genesis-aaa', closed: true),
        ]);

        final report = await _reconciler(
          git: git,
          groups: groups,
          state: state,
        ).reconcile();

        expect(report.skipped, hasLength(1));
        final entry = report.skipped.single;
        expect(entry.beadId, 'genesis-aaa');
        expect(entry.disposition, RestartDisposition.skipped);
        expect(entry.sessionId, 'tgdog-1');
        expect(entry.reapOutcome!.removed, isTrue);

        // git.reap WAS called for the foreign bead; nothing was signalled.
        expect(git.reaped, ['genesis-aaa']);
        expect(groups.signals, isEmpty);
        expect(report.respawnPending, isEmpty);
        expect(report.respawnCount, 0);
      },
    );

    test(
      'a LIVE (non-terminal) session ⇒ respawn-pending, carrying its session '
      'id — and NO kill even when legacy scalar pgid/pid identity is on the '
      'bead (the flat fence is retired; kills are the lease sweep\'s)',
      () async {
        final log = <String>[];
        final git = FakeGit(worktrees: [_wt('tgdog-work-b')], log: log);
        // The recorded leader pid IS alive — under the retired flat fence this
        // was the KILL case; now the identity is inert legacy metadata.
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

        final report = await _reconciler(
          git: git,
          groups: groups,
          state: state,
        ).reconcile();

        expect(report.respawnPending, hasLength(1));
        final entry = report.respawnPending.single;
        expect(entry.disposition, RestartDisposition.respawnPending);
        expect(entry.sessionId, 'tgdog-2');
        expect(groups.signals, isEmpty, reason: 'the flat kill fence is gone');
        expect(git.reaped, isEmpty);
        expect(report.killed, isEmpty);
        expect(report.adopted, isEmpty);
        expect(report.refusedUnsafe, isEmpty);
        expect(report.respawnCount, 1);
      },
    );

    test(
      'a worktree with NO session record ⇒ respawn-pending, no kill, no reap',
      () async {
        final log = <String>[];
        final git = FakeGit(worktrees: [_wt('genesis-orphan')], log: log);
        final groups = FakeProcessGroupController(ownGroupId: 999, log: log);
        final state = _stateSnapshotOf(const []); // no sessions at all.

        final report = await _reconciler(
          git: git,
          groups: groups,
          state: state,
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
      'ordering: the freshnessBarrier completes BEFORE listBeadWorktrees and '
      'before the state snapshot is read',
      () async {
        final log = <String>[];
        final git = FakeGit(worktrees: [_wt('tgdog-ord')], log: log);
        final groups = FakeProcessGroupController(ownGroupId: 999, log: log);
        final state = _stateSnapshotOf([
          _session(id: 'tgdog-ord-s', workBead: 'tgdog-ord'),
        ]);

        var barrierDone = false;
        final reconciler = _reconciler(
          git: git,
          groups: groups,
          state: state,
          // An async barrier that yields the event loop, then records its
          // completion onto the shared log AFTER a real delay. If list ran on
          // stale state, it would appear before 'barrier' in the log.
          freshnessBarrier: () async {
            await Future<void>.delayed(const Duration(milliseconds: 5));
            barrierDone = true;
            log.add('barrier');
          },
          stateSnapshot: () {
            // The state snapshot must only be READ after the barrier resolved.
            expect(
              barrierDone,
              isTrue,
              reason: 'sessions projected on post-barrier state only',
            );
            return state;
          },
        );
        await reconciler.reconcile();

        // The barrier is the FIRST log entry; list follows it.
        expect(log.first, 'barrier');
        expect(log.indexOf('barrier'), lessThan(log.indexOf('list')));
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

        final report = await _reconciler(
          git: git,
          groups: groups,
          state: state,
        ).reconcile();

        expect(report.entries, isEmpty);
        expect(git.reaped, isEmpty);
        expect(groups.signals, isEmpty);
      },
    );

    test(
      'a full restart with every case at once reconciles each correctly '
      '(skip / live-respawn / fresh-respawn)',
      () async {
        final log = <String>[];
        final git = FakeGit(
          worktrees: [
            _wt('genesis-done'), // A: foreign + terminal ⇒ skipped
            _wt('tgdog-live'), // B: live ⇒ respawn-pending
            _wt('genesis-fresh'), // C: no session ⇒ respawn-pending
          ],
          log: log,
        );
        final groups = FakeProcessGroupController(
          ownGroupId: 999,
          log: log,
          alivePids: {2001},
        );
        final state = _stateSnapshotOf([
          _session(id: 'tgdog-a', workBead: 'genesis-done', closed: true),
          _session(
            id: 'tgdog-b',
            workBead: 'tgdog-live',
            pgid: 2000,
            pid: 2001,
          ),
        ]);

        final report = await _reconciler(
          git: git,
          groups: groups,
          state: state,
        ).reconcile();

        expect(report.skipped.map((e) => e.beadId), ['genesis-done']);
        expect(
          report.respawnPending.map((e) => e.beadId),
          unorderedEquals(['tgdog-live', 'genesis-fresh']),
        );

        // Only the done bead is reaped; nothing is ever signalled.
        expect(git.reaped, ['genesis-done']);
        expect(groups.signals, isEmpty);

        // respawnCount = everything except the skipped done bead.
        expect(report.respawnCount, 2);

        // The retired flat buckets stay structurally empty.
        expect(report.killed, isEmpty);
        expect(report.adopted, isEmpty);
        expect(report.refusedUnsafe, isEmpty);
        expect(report.reaped, isEmpty);
      },
    );
  });

  group(
    'EXISTING-STORE SAFETY — historical FLAT session beads are INERT '
    '(grid.cursor.* metadata, no grid.session.model marker; tg-eli phase 2)',
    () {
      test(
        'an OPEN legacy flat session bearing a full grid.cursor.* cursor '
        '(running node, live pid, scalar identity) reconciles WITHOUT a '
        'crash, WITHOUT a signal, and WITHOUT a write — respawn-pending',
        () async {
          final cp = _chokepoint();
          final log = <String>[];
          final git = FakeGit(worktrees: [_wt('pow-77g')], log: log);
          final groups = FakeProcessGroupController(
            ownGroupId: 999,
            log: log,
            alivePids: {29629},
          );
          final state = _stateSnapshotOf([
            _session(
              id: 'tgdog-legacy',
              workBead: 'pow-77g',
              pgid: 29629,
              pid: 29629,
              metadata: _legacyFlatCursor(
                'pow-77g/agent',
                pgid: 29629,
                pid: 29629,
              ),
            ),
          ]);

          final report = await _reconciler(
            git: git,
            groups: groups,
            state: state,
            writer: cp.writer,
          ).reconcile();

          expect(report.respawnPending, hasLength(1));
          expect(report.respawnPending.single.sessionId, 'tgdog-legacy');
          expect(
            groups.signals,
            isEmpty,
            reason: 'legacy identity is never parsed into a kill target',
          );
          expect(
            cp.bd.calls,
            isEmpty,
            reason:
                'the zombie-cursor reap retired — the boot pass issues no '
                'writes at all',
          );
          expect(report.reaped, isEmpty);
          expect(report.sweptLeases, isEmpty);
        },
      );

      test(
        'a CLOSED legacy flat session (grid.outcome marker present — the A48 '
        'done evidence the mount boundary reads) still SKIPS and reaps its '
        'worktree; the stale cursor keys are ignored',
        () async {
          final cp = _chokepoint();
          final log = <String>[];
          final git = FakeGit(worktrees: [_wt('pow-88h')], log: log);
          final groups = FakeProcessGroupController(ownGroupId: 999, log: log);
          final state = _stateSnapshotOf([
            _session(
              id: 'tgdog-legacy-done',
              workBead: 'pow-88h',
              closed: true,
              metadata: {
                SessionBeadKeys.outcome: kSessionOutcomeComplete,
                ..._legacyFlatCursor('pow-88h/agent', state: 'complete'),
              },
            ),
          ]);

          final report = await _reconciler(
            git: git,
            groups: groups,
            state: state,
            writer: cp.writer,
          ).reconcile();

          expect(report.skipped, hasLength(1));
          expect(git.reaped, ['pow-88h']);
          expect(groups.signals, isEmpty);
          expect(cp.bd.calls, isEmpty);
        },
      );

      test(
        'projectSession leaves the cursor EMPTY for a cursor-bearing legacy '
        'bead — the flat keys are never parsed (the surviving-read-site '
        'proof for every cursor consumer)',
        () {
          final projection = projectSession(
            _session(
              id: 'tgdog-legacy',
              workBead: 'pow-77g',
              pgid: 4242,
              pid: 4243,
              metadata: _legacyFlatCursor('pow-77g/agent'),
            ),
          );
          expect(projection.cursor, isEmpty);
          expect(projection.isMolecule, isFalse);
          // The legacy SCALAR identity still projects (the projection fields
          // survive) — carried, not acted on, by this pass.
          expect(projection.pgid, 4242);
          expect(projection.pid, 4243);
        },
      );
    },
  );
}
