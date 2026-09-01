/// P1-PRIMARY AT THE TWO READ SITES (cut-wiring C3) — the join bridge's
/// sessions map and the restart reconciler's owned-session projection.
///
/// C2 proved the snapshot is a PURE third input; this suite proves the flip is
/// real at both sites and IDENTICAL at both: the same overlay, the same
/// suppressors, the same disengage latch. A disposition must not depend on
/// which pass asked for it — the bridge decides mounts and the reconciler
/// decides worktree reaps off the same projections, and C2's own
/// `incumbentAdjudication` class exists precisely because those two passes can
/// see the same beads differently.
library;

import 'dart:async';

import 'dart:io';

import 'package:beads_dart/beads_dart.dart';
import 'package:grid_engine/grid_engine.dart';
import 'package:grid_engine/testing.dart';
import 'package:grid_runtime/grid_runtime.dart';
import 'package:test/test.dart';

// ── shared fakes ─────────────────────────────────────────────────────────

final class _Head implements SessionHeadView {
  _Head({
    required this.sessionId,
    required this.workBeadId,
    this.isOpen = true,
    this.outcome,
    this.terminalProvenance,
  });

  @override
  final String sessionId;
  @override
  final String workBeadId;

  /// Every head in this suite is a CURRENT one — the retired-into marker is
  /// exercised in `dual_read_primary_test.dart`'s rework-window walk.
  @override
  int get round => 0;
  @override
  final bool isOpen;
  @override
  final SessionHeadOutcome? outcome;
  @override
  bool get held => false;
  @override
  String? get heldReason => null;
  @override
  String? get workTerminalReason => null;
  @override
  int? get pgid => null;
  @override
  int? get pid => null;
  @override
  String? get attemptId => null;
  @override
  final SessionHeadProvenance? terminalProvenance;
  @override
  String? get unknownReason => null;
  @override
  DateTime get startedAt => DateTime.utc(2026, 8, 31, 10);
  @override
  DateTime? get closedAt => isOpen ? null : DateTime.utc(2026, 8, 31, 11);
  @override
  int get lastSeq => 1;
}

final class _Snapshot implements TrajectoryHeadSnapshot {
  _Snapshot(this._rows, {this.health = TrajectorySnapshotHealth.live});

  final List<SessionHeadView> _rows;

  @override
  int get version => 5;
  @override
  final TrajectorySnapshotHealth health;
  @override
  DateTime? get seededAt => DateTime.utc(2026, 8, 31, 9);
  @override
  DateTime? get firstEpochClaimedAt => DateTime.utc(2026, 8, 31, 9);

  @override
  SessionHeadView? bySessionId(String sessionId) {
    for (final row in _rows) {
      if (row.sessionId == sessionId) return row;
    }
    return null;
  }

  @override
  SessionHeadWinner byWorkBead(String workBeadId) => sessionHeadWinnerOf([
    for (final row in _rows)
      if (row.workBeadId == workBeadId) row,
  ]);

  @override
  Iterable<SessionHeadView> get rows => _rows;
}

// ── the join bridge ──────────────────────────────────────────────────────

class _Source implements SnapshotSource {
  _Source([this._current]);

  final _controller = StreamController<GraphSnapshot>.broadcast();
  final GraphSnapshot? _current;

  @override
  Stream<GraphSnapshot> get snapshots => _controller.stream;

  @override
  GraphSnapshot? get current => _current;
}

GraphSnapshot _graph(List<Bead> beads) => GraphSnapshot.fromParts(
  beads: beads,
  dependencies: const [],
  readyIds: beads.map((b) => b.id),
  capturedAt: DateTime.fromMillisecondsSinceEpoch(0),
);

Bead _work(String id) =>
    Bead(id: id, issueType: IssueType.feature, status: BeadStatus.open);

Bead _sessionBead(
  String id, {
  required String workBeadId,
  bool closed = false,
  String? moleculeStep,
}) => Bead(
  id: id,
  issueType: GridIssueTypes.session,
  status: closed ? BeadStatus.closed : BeadStatus.open,
  metadata: {
    'rig': 'tgdog',
    'work_bead': workBeadId,
    if (closed) 'grid.outcome': 'complete',
    if (moleculeStep != null) 'grid.session.model': 'molecule',
  },
);

// ── the restart reconciler ───────────────────────────────────────────────

class _FakeGit {
  _FakeGit(this.worktrees);

  final List<BeadWorktree> worktrees;
  final List<String> reaped = [];

  Future<List<BeadWorktree>?> listWorktrees(RootCheckout root) async =>
      worktrees;

  Future<ReapOutcome> reapWorktree({
    required RootCheckout root,
    required BeadWorktree worktree,
  }) async {
    reaped.add(worktree.beadId);
    return ReapOutcome.removed();
  }
}

class _FakeGroups implements ProcessGroupController {
  @override
  bool processAlive(int pid) => false;
  @override
  bool signalGroup(int pgid, ProcessSignal signal) => false;
  @override
  int currentGroupId() => 1;
  @override
  Future<int?> resolvePgid(int pid) async => null;
}

const _workRoot = RootCheckout(
  path: '/workspace/example',
  defaultBranch: 'main',
  substation: 'tgdog',
);

({RestartReconciler reconciler, _FakeGit git, DualReadAccounting accounting})
_reconciler({
  required List<Bead> state,
  required TrajectoryHeadSnapshot snapshot,
  required DualReadMode mode,
  DualReadAccounting? accounting,
}) {
  final bd = RecordingBdRunner()..exportBeads = state;
  final git = _FakeGit([
    const BeadWorktree(
      beadId: 'tg-1',
      path: '/workspace/example/.grid/worktrees/tgdog/tg-1',
      branch: 'grid/tg-1',
    ),
  ]);
  final counters = accounting ?? DualReadAccounting();
  return (
    reconciler: RestartReconciler(
      listWorktrees: git.listWorktrees,
      reapWorktree: git.reapWorktree,
      workRoot: _workRoot,
      groups: _FakeGroups(),
      writer: StationBeadWriter(
        bd: BdCliService(bd),
        reader: bd,
        ownership: BeadOwnershipPredicate(const {'tgdog'}),
      ),
      freshnessBarrier: () async {},
      stateSnapshot: () => GraphSnapshot.fromParts(
        beads: state,
        dependencies: const [],
        readyIds: const [],
        capturedAt: DateTime(2026, 8, 31),
      ),
      headSnapshot: () => snapshot,
      dualReadAccounting: counters,
      dualReadMode: mode,
    ),
    git: git,
    accounting: counters,
  );
}

void main() {
  group('the JOIN serves the overlay under primary', () {
    late _Source work;
    late _Source state;

    setUp(() {
      work = _Source(_graph([_work('tg-1')]));
      state = _Source(_graph([_sessionBead('tgdog-s1', workBeadId: 'tg-1')]));
    });

    StationJoinBridge bridgeWith(
      DualReadSessionObserver observer,
      TrajectoryHeadSnapshot snapshot,
    ) {
      final bridge = StationJoinBridge(
        work: work,
        state: state,
        headSnapshot: () => snapshot,
        dualRead: observer,
      );
      addTearDown(bridge.dispose);
      return bridge;
    }

    test('a fold-ahead terminal becomes the served projection — and the SAME '
        'input under observe does not', () {
      final snapshot = _Snapshot([
        _Head(
          sessionId: 'tgdog-s1',
          workBeadId: 'tg-1',
          isOpen: false,
          outcome: SessionHeadOutcome.succeeded,
        ),
      ]);
      final observing = bridgeWith(
        DualReadSessionObserver(mode: DualReadMode.observe),
        snapshot,
      );
      final serving = bridgeWith(
        DualReadSessionObserver(mode: DualReadMode.primary),
        snapshot,
      );

      final legacy = observing.latest.sessionsByWorkBead['tg-1']!;
      final served = serving.latest.sessionsByWorkBead['tg-1']!;
      expect(sessionDispositionOf(legacy), isA<LiveSession>());
      expect(sessionDispositionOf(served), isA<DoneSession>());
      // …and everything OUTSIDE the certified four fields is the legacy row's.
      expect(served.workBeadId, legacy.workBeadId);
      expect(served.sessionId, legacy.sessionId);
      expect(served.startedAt, legacy.startedAt);
      expect(served.token, legacy.token);
    });

    test('the overlay NEVER CREATES: a P1 row with no legacy counterpart is '
        'not a sessions-map entry, whatever the posture', () {
      final serving = bridgeWith(
        DualReadSessionObserver(mode: DualReadMode.primary),
        _Snapshot([
          _Head(sessionId: 'tgdog-s1', workBeadId: 'tg-1'),
          _Head(
            sessionId: 'tgdog-s9',
            workBeadId: 'tg-9',
            isOpen: false,
            outcome: SessionHeadOutcome.succeeded,
          ),
        ]),
      );
      expect(serving.latest.sessionsByWorkBead.keys, ['tg-1']);
    });

    test('an agreeing head leaves the map REFERENCE-identical to pure legacy '
        '— primary changes nothing it has no reason to', () {
      final snapshot = _Snapshot([
        _Head(sessionId: 'tgdog-s1', workBeadId: 'tg-1'),
      ]);
      final observing = bridgeWith(
        DualReadSessionObserver(mode: DualReadMode.observe),
        snapshot,
      );
      final serving = bridgeWith(
        DualReadSessionObserver(mode: DualReadMode.primary),
        snapshot,
      );
      expect(
        serving.latest.sessionsByWorkBead['tg-1'],
        observing.latest.sessionsByWorkBead['tg-1'],
      );
    });

    test('the molecule and gate attachments SURVIVE the overlay — they are '
        'made before it and ride the copy', () {
      final stateWithMolecule = _Source(
        _graph([
          _sessionBead('tgdog-s1', workBeadId: 'tg-1', moleculeStep: 'root'),
          Bead(
            id: 'tgdog-mol1',
            issueType: GridIssueTypes.molecule,
            status: BeadStatus.open,
            metadata: const {
              'rig': 'tgdog',
              'grid.circuit.session': 'tgdog-s1',
            },
          ),
        ]),
      );
      final bridge = StationJoinBridge(
        work: work,
        state: stateWithMolecule,
        headSnapshot: () => _Snapshot([
          _Head(
            sessionId: 'tgdog-s1',
            workBeadId: 'tg-1',
            isOpen: false,
            outcome: SessionHeadOutcome.succeeded,
          ),
        ]),
        dualRead: DualReadSessionObserver(mode: DualReadMode.primary),
      );
      addTearDown(bridge.dispose);
      final served = bridge.latest.sessionsByWorkBead['tg-1']!;
      expect(sessionDispositionOf(served), isA<DoneSession>());
      expect(served.isMolecule, isTrue);
      expect(served.moleculeBeads.map((b) => b.id), ['tgdog-mol1']);
    });

    test(
      'an AGREEING fold leaves the whole map equal to the legacy-only '
      "bridge's — the reason the engine's suites stay green under primary",
      () {
        final many = [_work('tg-1'), _work('tg-2'), _work('tg-3')];
        final beads = [
          _sessionBead('tgdog-s1', workBeadId: 'tg-1'),
          _sessionBead('tgdog-s2', workBeadId: 'tg-2', closed: true),
          _sessionBead('tgdog-s3', workBeadId: 'tg-3'),
        ];
        final workMany = _Source(_graph(many));
        final stateMany = _Source(_graph(beads));
        final snapshot = _Snapshot([
          _Head(sessionId: 'tgdog-s1', workBeadId: 'tg-1'),
          _Head(
            sessionId: 'tgdog-s2',
            workBeadId: 'tg-2',
            isOpen: false,
            outcome: SessionHeadOutcome.succeeded,
          ),
          _Head(sessionId: 'tgdog-s3', workBeadId: 'tg-3'),
        ]);
        final legacyOnly = StationJoinBridge(work: workMany, state: stateMany);
        final serving = StationJoinBridge(
          work: workMany,
          state: stateMany,
          headSnapshot: () => snapshot,
          dualRead: DualReadSessionObserver(mode: DualReadMode.primary),
        );
        addTearDown(legacyOnly.dispose);
        addTearDown(serving.dispose);
        final pure = legacyOnly.latest.sessionsByWorkBead;
        final served = serving.latest.sessionsByWorkBead;
        expect(served.keys, pure.keys);
        for (final key in pure.keys) {
          expect(
            sessionDispositionOf(served[key]),
            sessionDispositionOf(pure[key]),
            reason: 'the disposition of $key moved under primary',
          );
          // The ONE field that may differ on an agreeing pair is `closedAt`:
          // it is in the certified override set but NOT in the comparator's
          // tuple, so P1 fills an instant a pre-stamp legacy bead never carried.
          // It is capture-only telemetry and gates nothing — which is why an
          // agreeing round can serve it without dirtying the round.
          expect(
            served[key]!.copyWith(closedAt: null),
            pure[key]!.copyWith(closedAt: null),
          );
        }
      },
    );

    test('a COMPROMISED snapshot serves pure legacy — the boot rides the '
        'incumbent, which wave 1 never stopped writing', () {
      final serving = bridgeWith(
        DualReadSessionObserver(mode: DualReadMode.primary),
        _Snapshot([
          _Head(
            sessionId: 'tgdog-s1',
            workBeadId: 'tg-1',
            isOpen: false,
            outcome: SessionHeadOutcome.succeeded,
          ),
        ], health: TrajectorySnapshotHealth.compromised),
      );
      expect(
        sessionDispositionOf(serving.latest.sessionsByWorkBead['tg-1']),
        isA<LiveSession>(),
      );
    });
  });

  group('the RECONCILER serves the identical overlay', () {
    List<Bead> stateBeads({bool closed = false}) => [
      Bead(
        id: 'tgdog-s1',
        issueType: GridIssueTypes.session,
        status: closed ? BeadStatus.closed : BeadStatus.open,
        metadata: const {'rig': 'tgdog', 'work_bead': 'tg-1'},
      ),
    ];

    test('a fold-ahead DONE head reaps the worktree under primary and leaves '
        'it respawn-pending under observe — the same beads, the same '
        'snapshot, one config line apart', () async {
      final snapshot = _Snapshot([
        _Head(
          sessionId: 'tgdog-s1',
          workBeadId: 'tg-1',
          isOpen: false,
          outcome: SessionHeadOutcome.succeeded,
        ),
      ]);

      final observing = _reconciler(
        state: stateBeads(),
        snapshot: snapshot,
        mode: DualReadMode.observe,
      );
      final observed = await observing.reconciler.reconcile();
      expect(
        observed.entries.single.disposition,
        RestartDisposition.respawnPending,
      );
      expect(observing.git.reaped, isEmpty);

      final serving = _reconciler(
        state: stateBeads(),
        snapshot: snapshot,
        mode: DualReadMode.primary,
      );
      final served = await serving.reconciler.reconcile();
      expect(served.entries.single.disposition, RestartDisposition.skipped);
      expect(serving.git.reaped, ['tg-1']);
      expect(serving.accounting.overlaysServed, 1);
    });

    test('MONOTONE TERMINALITY holds here too: a P1 row still open never '
        'un-reaps a legacy-terminal session', () async {
      final serving = _reconciler(
        state: stateBeads(closed: true),
        snapshot: _Snapshot([_Head(sessionId: 'tgdog-s1', workBeadId: 'tg-1')]),
        mode: DualReadMode.primary,
      );
      final report = await serving.reconciler.reconcile();
      expect(report.entries.single.disposition, RestartDisposition.skipped);
      expect(serving.git.reaped, ['tg-1']);
      expect(serving.accounting.overlaysServed, isZero);
      expect(serving.accounting.overlaysSuppressed, 1);
    });

    test('a RECONSTRUCTED head is never served here either — testimony does '
        'not reap a worktree', () async {
      final serving = _reconciler(
        state: stateBeads(),
        snapshot: _Snapshot([
          _Head(
            sessionId: 'tgdog-s1',
            workBeadId: 'tg-1',
            isOpen: false,
            outcome: SessionHeadOutcome.unknown,
            terminalProvenance: SessionHeadProvenance.reconstructed,
          ),
        ]),
        mode: DualReadMode.primary,
      );
      final report = await serving.reconciler.reconcile();
      expect(
        report.entries.single.disposition,
        RestartDisposition.respawnPending,
      );
      expect(serving.git.reaped, isEmpty);
    });

    test('a compromised snapshot latches the SHARED disengage — the bridge '
        'observer built on the same accounting stops serving too', () async {
      final accounting = DualReadAccounting();
      final serving = _reconciler(
        state: stateBeads(),
        snapshot: _Snapshot(
          const [],
          health: TrajectorySnapshotHealth.compromised,
        ),
        mode: DualReadMode.primary,
        accounting: accounting,
      );
      await serving.reconciler.reconcile();
      expect(accounting.overlayDisengaged, isTrue);
      expect(
        DualReadSessionObserver(
          mode: DualReadMode.primary,
          accounting: accounting,
        ).overlayEngaged,
        isFalse,
      );
    });
  });
}
