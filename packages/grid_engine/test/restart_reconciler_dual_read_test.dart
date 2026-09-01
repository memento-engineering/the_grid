/// THE RECONCILER'S HALF OF C2 (cut-wiring §C2) — the teardown-replay OBSERVER
/// APPEND and `_projectOwnedSessions`' comparator.
///
/// Two regressions live here by name:
///
///   * **J7-B4 / J8-B1** — the teardown replay closes an OPEN session bead and
///     emits no terminal, so its P1 head would stay open forever: an
///     unhealable `terminalLag` that escalates and makes the C2/C3
///     zero-divergence gates unsatisfiable. The fix is scoped to EXACTLY the
///     closed-an-open-session arm, carries `outcome='unknown'` (never
///     `settled` — that outcome is the settle arm's, earned by joining the
///     attempt row), and NEVER mints an attempt id.
///   * **O-m3** — `_projectOwnedSessions` picks its winner by MAP ITERATION
///     ORDER when two sessions share a work-bead key, so a mismatch there is
///     `incumbentAdjudication`, not a divergence.
library;

import 'dart:io';

import 'package:beads_dart/beads_dart.dart';
import 'package:grid_engine/grid_engine.dart';
import 'package:grid_engine/testing.dart';
import 'package:grid_runtime/grid_runtime.dart';
import 'package:test/test.dart';

class _FakeGit {
  Future<List<BeadWorktree>?> listWorktrees(RootCheckout root) async =>
      const <BeadWorktree>[];

  Future<ReapOutcome> reapWorktree({
    required RootCheckout root,
    required BeadWorktree worktree,
  }) async => ReapOutcome.removed();
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

final class _CapturingSink implements TrajectoryRecordSink {
  final List<TrajectoryRecord> records = [];
  final List<TrajectoryProvenance> provenances = [];
  final List<String?> bases = [];

  @override
  bool get accepting => true;

  @override
  void enqueue(
    TrajectoryRecord record, {
    DateTime? occurredAt,
    String? seat,
    TrajectoryProvenance provenance = TrajectoryProvenance.observed,
    String? provenanceBasis,
  }) {
    records.add(record);
    provenances.add(provenance);
    bases.add(provenanceBasis);
  }

  List<String> get types => [for (final r in records) r.recordType];

  Map<String, Object?> get onlyTerminal {
    final terminals = [
      for (final record in records)
        if (record.recordType == 'attempt.terminal') record,
    ];
    expect(terminals, hasLength(1));
    return {
      ...terminals.single.payloadToJson(),
      ...terminals.single.correlationToJson(),
    };
  }
}

final class _Head implements SessionHeadView {
  _Head({
    required this.sessionId,
    required this.workBeadId,
    this.isOpen = true,
    this.outcome,
  });

  @override
  final String sessionId;
  @override
  final String workBeadId;

  /// Every head in this suite is a CURRENT one — the retired-into marker is
  /// exercised in `dual_read_session_test.dart`.
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
  SessionHeadProvenance? get terminalProvenance => null;
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
  int get version => 3;
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

const _workRoot = RootCheckout(
  path: '/workspace/example',
  defaultBranch: 'main',
  substation: 'tgdog',
);

Bead _session(
  String id, {
  required String workBead,
  bool closed = false,
  String? outcome = 'complete',
}) => Bead(
  id: id,
  issueType: GridIssueTypes.session,
  status: closed ? BeadStatus.closed : BeadStatus.open,
  metadata: <String, dynamic>{
    'rig': 'tgdog',
    'work_bead': workBead,
    if (outcome != null) 'grid.outcome': outcome,
  },
);

/// A step bead carrying (or not) the vendor's attempt-id breadcrumb — the ONLY
/// thing the observer append can recover an id from.
Bead _step(
  String id, {
  required String sessionId,
  String? attemptId,
  bool closed = false,
}) => Bead(
  id: id,
  issueType: GridIssueTypes.step,
  status: closed ? BeadStatus.closed : BeadStatus.open,
  metadata: <String, dynamic>{
    'rig': 'tgdog',
    'grid.step.session': sessionId,
    // The vendor's breadcrumb key, spelled out here because the engine
    // deliberately does not export `LeaseKeys` — the vendor owns that schema
    // and the reconciler is kept ignorant of it.
    if (attemptId != null) 'grid.lease.attempt_id': attemptId,
  },
);

Bead _molecule(String id, {required String sessionId}) => Bead(
  id: id,
  issueType: GridIssueTypes.molecule,
  status: BeadStatus.open,
  metadata: <String, dynamic>{
    'rig': 'tgdog',
    'grid.circuit.session': sessionId,
  },
);

({
  RestartReconciler reconciler,
  _CapturingSink sink,
  DualReadAccounting accounting,
  List<(String, Map<String, String>)> flares,
  List<String> loud,
})
_build({required List<Bead> state, TrajectoryHeadSnapshot? snapshot}) {
  final bd = RecordingBdRunner()..exportBeads = state;
  final sink = _CapturingSink();
  final accounting = DualReadAccounting();
  final flares = <(String, Map<String, String>)>[];
  final loud = <String>[];
  final git = _FakeGit();
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
      onOrphan: loud.add,
      freshnessBarrier: () async {},
      stateSnapshot: () => GraphSnapshot.fromParts(
        beads: state,
        dependencies: const [],
        readyIds: const [],
        capturedAt: DateTime(2026, 8, 31),
      ),
      recorder: StationTrajectoryRecorder(
        sink: sink,
        seatPrefixes: const {'tg'},
      ),
      headSnapshot: snapshot == null ? null : () => snapshot,
      dualReadAccounting: accounting,
      onFlare: (name, data) => flares.add((name, data)),
    ),
    sink: sink,
    accounting: accounting,
    flares: flares,
    loud: loud,
  );
}

void main() {
  group('the teardown-replay OBSERVER APPEND (J7-B4/J8-B1)', () {
    test('a planted replay WITH a breadcrumb appends the reconstructed close '
        'under the RECOVERED attempt id, unknown/teardown-replay', () async {
      final f = _build(
        state: [
          _session('tgdog-sess1', workBead: 'tg-1'),
          _step('tgdog-step1', sessionId: 'tgdog-sess1', attemptId: 'att-1'),
        ],
      );

      await f.reconciler.replayTeardownTail();

      final terminal = f.sink.onlyTerminal;
      expect(terminal['attempt_id'], 'att-1');
      expect(terminal['session_id'], 'tgdog-sess1');
      expect(terminal['work_bead_id'], 'tg-1');
      expect(terminal['outcome'], 'unknown');
      expect(terminal['unknown_reason'], 'teardown-replay');
      // NOT `settled`: that outcome stays reserved for the settle arm, which
      // EARNS it by joining the attempt row.
      expect(terminal['resolves_record_id'], isNull);
      // NOT minted: `attempt_id_basis` is the marker a mint would leave.
      expect(terminal['attempt_id_basis'], isNull);
      expect(f.sink.provenances.single, TrajectoryProvenance.reconstructed);
      expect(f.sink.bases.single, kRestartReconcilerBasis);
      expect(f.accounting.teardownReplayAppends, 1);
    });

    test('the record carries NO heal basis, so it takes the PLAIN '
        '`terminal:<attemptId>` idem key and a re-run of the replay dedupes '
        'rather than writing a second row (the key grammar itself is pinned '
        'in grid_trajectory)', () async {
      final f = _build(
        state: [
          _session('tgdog-sess1', workBead: 'tg-1'),
          _step('tgdog-step1', sessionId: 'tgdog-sess1', attemptId: 'att-1'),
        ],
      );

      await f.reconciler.replayTeardownTail();

      expect(f.sink.onlyTerminal['heal_basis'], isNull);
    });

    test('a BREADCRUMBLESS open candidate SKIPS the append, counts it, and '
        'flares — no id is ever minted', () async {
      final f = _build(
        state: [
          _session('tgdog-sess1', workBead: 'tg-1'),
          _step('tgdog-step1', sessionId: 'tgdog-sess1'),
        ],
      );

      await f.reconciler.replayTeardownTail();

      expect(f.sink.types, isNot(contains('attempt.terminal')));
      expect(f.accounting.reconstructedTerminalSkipped, 1);
      expect(f.accounting.teardownReplayAppends, isZero);
      final flare = f.flares.single;
      expect(flare.$1, kReconstructedTerminalSkippedFlare);
      expect(flare.$2['session_id'], 'tgdog-sess1');
      expect(flare.$2['basis'], 'restart-reconciler');
      expect(f.loud.join('\n'), contains('SKIPPED'));
    });

    test('J8-B1 REGRESSION: a CLOSED candidate with open molecules appends '
        'NOTHING — an already-closed session had its terminal, and its '
        'absence from P1 is not this arm to invent', () async {
      final f = _build(
        state: [
          _session('tgdog-sess1', workBead: 'tg-1', closed: true),
          _molecule('tgdog-mol1', sessionId: 'tgdog-sess1'),
          _step('tgdog-step1', sessionId: 'tgdog-sess1', attemptId: 'att-1'),
        ],
      );

      final report = await f.reconciler.replayTeardownTail();

      expect(report.replayed.map((e) => e.sessionId), ['tgdog-sess1']);
      expect(f.sink.types, isNot(contains('attempt.terminal')));
      expect(f.accounting.teardownReplayAppends, isZero);
      expect(f.accounting.reconstructedTerminalSkipped, isZero);
    });

    test('a candidate that is NOT done-dispositioned is never replayed and '
        'never appends', () async {
      final f = _build(
        state: [
          _session('tgdog-sess1', workBead: 'tg-1', outcome: null),
          _step('tgdog-step1', sessionId: 'tgdog-sess1', attemptId: 'att-1'),
        ],
      );

      await f.reconciler.replayTeardownTail();

      expect(f.sink.types, isNot(contains('attempt.terminal')));
    });
  });

  group('_projectOwnedSessions dual read (O-m3)', () {
    test('a matching head is a HIT with no divergence', () async {
      final f = _build(
        state: [_session('tgdog-sess1', workBead: 'tg-1', outcome: null)],
        snapshot: _Snapshot([
          _Head(sessionId: 'tgdog-sess1', workBeadId: 'tg-1'),
        ]),
      );

      await f.reconciler.reconcile();

      expect(f.accounting.hits, greaterThanOrEqualTo(1));
      expect(f.accounting.divergences, isZero);
      expect(f.flares, isEmpty);
    });

    test('a planted mismatch on a SINGLE-session bead flares a divergence '
        'scoped to the reconciler', () async {
      final f = _build(
        state: [_session('tgdog-sess1', workBead: 'tg-1', outcome: null)],
        snapshot: _Snapshot([
          _Head(
            sessionId: 'tgdog-sess1',
            workBeadId: 'tg-1',
            isOpen: false,
            outcome: SessionHeadOutcome.succeeded,
          ),
        ]),
      );

      await f.reconciler.reconcile();

      expect(f.accounting.divergences, greaterThan(0));
      final flare = f.flares.first;
      expect(flare.$1, kDualReadDivergenceFlare);
      expect(flare.$2['scope'], 'restart-reconciler');
      expect(flare.$2['session_id'], 'tgdog-sess1');
    });

    test('TWO sessions on ONE work-bead key route to incumbentAdjudication — '
        'the incumbent picked its winner by map iteration order, so the fold '
        'is never auto-presumed wrong', () async {
      final f = _build(
        state: [
          _session('tgdog-sess1', workBead: 'tg-1', outcome: null),
          _session('tgdog-sess2', workBead: 'tg-1', outcome: null),
        ],
        snapshot: _Snapshot([
          _Head(
            sessionId: 'tgdog-sess1',
            workBeadId: 'tg-1',
            isOpen: false,
            outcome: SessionHeadOutcome.succeeded,
          ),
          _Head(
            sessionId: 'tgdog-sess2',
            workBeadId: 'tg-1',
            isOpen: false,
            outcome: SessionHeadOutcome.succeeded,
          ),
        ]),
      );

      await f.reconciler.reconcile();

      expect(f.accounting.incumbentAdjudications, 1);
      expect(f.accounting.divergences, isZero);
      expect(f.flares, isEmpty);
      expect(f.loud.join('\n'), contains('incumbent adjudication'));
    });

    test(
      'a non-live snapshot disengages the compare and counts fallbacks',
      () async {
        final f = _build(
          state: [_session('tgdog-sess1', workBead: 'tg-1', outcome: null)],
          snapshot: _Snapshot(
            const [],
            health: TrajectorySnapshotHealth.compromised,
          ),
        );

        await f.reconciler.reconcile();

        expect(f.accounting.hits, isZero);
        expect(f.accounting.fallbacks, greaterThanOrEqualTo(1));
        expect(f.flares, isEmpty);
      },
    );

    test('with NO snapshot wired the pass is byte-identical to before: no '
        'counters move and nothing flares', () async {
      final f = _build(
        state: [_session('tgdog-sess1', workBead: 'tg-1', outcome: null)],
      );

      await f.reconciler.reconcile();

      expect(f.accounting.hits, isZero);
      expect(f.accounting.fallbacks, isZero);
      expect(f.flares, isEmpty);
    });
  });
}
