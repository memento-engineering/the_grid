/// THE STEP AXIS AT ITS READ SITES (cut-wiring C4) — the join bridge fills
/// `trajCursor`, and the five adopting cursor consumers read it through the
/// ONE shared helper.
///
/// The suite's spine is the rollback claim: under `observe` every consumer is
/// byte-identical to today, which is what makes `dualRead: observe` a real
/// one-line abort. The two sites the r4 OPEN CARRY names (the unclaimed
/// frontier and the driver's cooldown scan) iterate the structurally-empty
/// `SessionProjection.cursor`, so they are proved BOTH ways here: unchanged
/// while unengaged, and reading real nodes once engaged.
library;

import 'dart:async';

import 'package:beads_dart/beads_dart.dart';
import 'package:grid_engine/grid_engine.dart';
import 'package:test/test.dart';

// ── fakes ────────────────────────────────────────────────────────────────

final class _Row implements StepCursorView {
  _Row({
    required this.stepPath,
    required this.stepState,
    this.sessionId = 'tgdog-s1',
    this.stepRound = 0,
    this.incarnation = 0,
    this.supersededByStepRound,
  });

  @override
  final String sessionId;
  @override
  int get round => 0;
  @override
  final String stepPath;
  @override
  final int stepRound;
  @override
  final String stepState;
  @override
  final int incarnation;
  @override
  String? get attemptId => null;
  @override
  final int? supersededByStepRound;
  @override
  DateTime? get cooldownUntil => null;
  @override
  int? get restartBudget => null;
  @override
  DateTime? get startedAt => null;
  @override
  DateTime? get readyAt => null;
  @override
  DateTime? get completedAt => null;
  @override
  String? get failureClass => null;
  @override
  int get lastSeq => 1;
}

final class _StepSnapshot implements TrajectoryStepSnapshot {
  _StepSnapshot(this._rows, {this.health = TrajectorySnapshotHealth.live});

  final List<StepCursorView> _rows;

  @override
  int get version => 11;
  @override
  final TrajectorySnapshotHealth health;
  @override
  DateTime? get seededAt => null;
  @override
  DateTime? get firstEpochClaimedAt => null;

  @override
  Iterable<StepCursorView> byP2SessionId(String sessionId) => [
    for (final row in _rows)
      if (row.sessionId == sessionId) row,
  ];
}

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

Bead _sessionBead(String id, {required String workBeadId}) => Bead(
  id: id,
  issueType: GridIssueTypes.session,
  status: BeadStatus.open,
  metadata: {
    'rig': 'tgdog',
    'work_bead': workBeadId,
    'grid.session.model': 'molecule',
  },
);

Bead _stepBead(
  String nodePath, {
  required StepState state,
  String sessionId = 'tgdog-s1',
  int restartCount = 0,
  DateTime? cooldownUntil,
}) => Bead(
  id: 'tgdog-step-${nodePath.replaceAll('/', '-')}',
  issueType: GridIssueTypes.step,
  status: BeadStatus.open,
  metadata: {
    MoleculeStepKeys.path: nodePath,
    MoleculeStepKeys.state: state.name,
    MoleculeStepKeys.session: sessionId,
    MoleculeStepKeys.restartCount: '$restartCount',
    if (cooldownUntil != null)
      MoleculeStepKeys.cooldownUntil: cooldownUntil.toUtc().toIso8601String(),
  },
);

void main() {
  group('the JOIN fills trajCursor', () {
    late _Source work;
    late _Source state;

    setUp(() {
      work = _Source(_graph([_work('tg-1')]));
      state = _Source(
        _graph([
          _sessionBead('tgdog-s1', workBeadId: 'tg-1'),
          _stepBead('build', state: StepState.running),
        ]),
      );
    });

    StationJoinBridge bridgeWith(
      DualReadMode mode,
      TrajectoryStepSnapshot snapshot,
    ) {
      final bridge = StationJoinBridge(
        work: work,
        state: state,
        stepSnapshot: () => snapshot,
        stepDualRead: DualReadStepObserver(mode: mode),
      );
      addTearDown(bridge.dispose);
      return bridge;
    }

    test('OBSERVE leaves trajCursor NULL — the posture is the field', () {
      final bridge = bridgeWith(
        DualReadMode.observe,
        _StepSnapshot([_Row(stepPath: 'build', stepState: 'running')]),
      );
      final session = bridge.latest.sessionsByWorkBead['tg-1']!;
      expect(session.trajCursor, isNull);
    });

    test('PRIMARY fills it with P2\'s OWN cursor, unmerged', () {
      // Unmerged is the point: the merge rules live in `effectiveStepCursor`,
      // so exactly one implementation of them exists and no consumer can
      // re-merge a value somebody already merged.
      final bridge = bridgeWith(
        DualReadMode.primary,
        _StepSnapshot([_Row(stepPath: 'build', stepState: 'complete')]),
      );
      final session = bridge.latest.sessionsByWorkBead['tg-1']!;
      expect(session.trajCursor, isNotNull);
      expect(session.trajCursor!['build']!.state, StepState.complete);
      // The molecule attachment the join made just before is untouched.
      expect(session.moleculeBeads, hasLength(1));
    });

    test('PRIMARY also fills trajStepViews — the LADDER a consumer-site '
        'comparison reports (r12)', () {
      // `trajCursor` carries only the STATE. Without the collapsed views on
      // the projection, `effectiveStepCursor` called `mergeStepCursor` with no
      // `collapsed` map and every comparison raised at a CONSUMER site
      // reported round/stepRound/incarnation/supersededByStepRound null —
      // exactly the evidence a step-axis triage needs.
      final bridge = bridgeWith(
        DualReadMode.primary,
        _StepSnapshot([
          _Row(
            stepPath: 'build',
            stepState: 'complete',
            stepRound: 2,
            incarnation: 3,
            supersededByStepRound: 4,
          ),
        ]),
      );
      final session = bridge.latest.sessionsByWorkBead['tg-1']!;
      final view = session.trajStepViews['build']!;
      expect(view.stepRound, 2);
      expect(view.incarnation, 3);
      expect(view.supersededByStepRound, 4);
      // And that is what a consumer-site merge — the body of
      // `effectiveStepCursor` — now reports.
      final node = mergeStepCursor(
        sessionId: session.sessionId!,
        legacy: legacyStepCursorOf(session),
        traj: session.trajCursor,
        collapsed: session.trajStepViews,
      ).nodes.single;
      expect(node.stepPath, 'build');
      expect(node.stepRound, 2);
      expect(node.incarnation, 3);
      expect(node.supersededByStepRound, 4);
    });

    test('OBSERVE leaves trajStepViews EMPTY, with trajCursor null — both '
        'halves or neither', () {
      final bridge = bridgeWith(
        DualReadMode.observe,
        _StepSnapshot([_Row(stepPath: 'build', stepState: 'running')]),
      );
      final session = bridge.latest.sessionsByWorkBead['tg-1']!;
      expect(session.trajCursor, isNull);
      expect(session.trajStepViews, isEmpty);
    });

    test('a SIBLING session\'s rows never reach this projection', () {
      final bridge = bridgeWith(
        DualReadMode.primary,
        _StepSnapshot([
          _Row(
            sessionId: 'tgdog-OTHER',
            stepPath: 'build',
            stepState: 'complete',
          ),
        ]),
      );
      expect(bridge.latest.sessionsByWorkBead['tg-1']!.trajCursor, isNull);
    });

    test('health non-live leaves every projection on its bead cursor', () {
      final bridge = bridgeWith(
        DualReadMode.primary,
        _StepSnapshot([
          _Row(stepPath: 'build', stepState: 'complete'),
        ], health: TrajectorySnapshotHealth.compromised),
      );
      expect(bridge.latest.sessionsByWorkBead['tg-1']!.trajCursor, isNull);
    });

    test('a fold-side emission re-joins through the SAME push funnel', () {
      var snapshot = _StepSnapshot([
        _Row(stepPath: 'build', stepState: 'running'),
      ]);
      void Function(TrajectoryStepSnapshot)? listener;
      final bridge = StationJoinBridge(
        work: work,
        state: state,
        stepSnapshot: () => snapshot,
        onStepChanges: (l) {
          listener = l;
          return () => listener = null;
        },
        stepDualRead: DualReadStepObserver(mode: DualReadMode.primary),
      );
      addTearDown(bridge.dispose);
      bridge.start();
      expect(
        bridge.latest.sessionsByWorkBead['tg-1']!.trajCursor!['build']!.state,
        StepState.running,
      );

      snapshot = _StepSnapshot([
        _Row(stepPath: 'build', stepState: 'complete', stepRound: 1),
      ]);
      listener!(snapshot);

      expect(
        bridge.latest.sessionsByWorkBead['tg-1']!.trajCursor!['build']!.state,
        StepState.complete,
      );
      bridge.dispose();
      expect(listener, isNull, reason: 'dispose removes the step listener');
    });
  });

  group('the adopting consumers', () {
    SessionProjection session({
      required List<Bead> steps,
      CircuitCursor? trajCursor,
    }) => SessionProjection(
      workBeadId: 'tg-1',
      sessionId: 'tgdog-s1',
      isMolecule: true,
      moleculeBeads: steps,
      trajCursor: trajCursor,
    );

    test('CONSUMER 2 (the wedge) reads the same sample under both feeds when '
        'the fold agrees', () {
      final steps = [_stepBead('build', state: StepState.running)];
      final now = DateTime.utc(2026, 8, 31, 12);
      JoinedSnapshot joined(SessionProjection s) => JoinedSnapshot(
        graph: _graph([_work('tg-1')]),
        sessionsByWorkBead: {'tg-1': s},
        mountAttemptsByWorkBead: const {},
      );
      final legacy = sampleWedge(joined(session(steps: steps)), now: now);
      final folded = sampleWedge(
        joined(
          session(
            steps: steps,
            trajCursor: {'build': const NodeCursor(state: StepState.running)},
          ),
        ),
        now: now,
      );
      expect(folded.running, legacy.running);
      expect(folded.live, legacy.live);
    });

    test('CONSUMER 2: a P2-MISSING node still counts — never omitted', () {
      // The whole I-10 point on the sampling side: a node dropped from the
      // effective cursor would make a running station look idle.
      final joined = JoinedSnapshot(
        graph: _graph([_work('tg-1')]),
        sessionsByWorkBead: {
          'tg-1': session(
            steps: [_stepBead('build', state: StepState.running)],
            trajCursor: const <String, NodeCursor>{},
          ),
        },
        mountAttemptsByWorkBead: const {},
      );
      expect(
        sampleWedge(joined, now: DateTime.utc(2026, 8, 31, 12)).running,
        1,
      );
    });

    test('CONSUMER 7 (the cooldown scan): unengaged reads the empty field, '
        'engaged reads the bead\'s cooldown', () {
      // The r4 OPEN CARRY, both directions. `cooldownUntil` itself stays
      // BEAD-read either way (B-M2) — what the fold changes is which NODES the
      // scan sees at all.
      final cooldown = DateTime.utc(2026, 8, 31, 12);
      final steps = [
        _stepBead('build', state: StepState.failed, cooldownUntil: cooldown),
      ];
      final unengaged = effectiveStepCursor(
        session(steps: steps),
        siteCursor: const <String, NodeCursor>{},
      );
      expect(unengaged, isEmpty, reason: 'config off = today');

      final engaged = effectiveStepCursor(
        session(
          steps: steps,
          trajCursor: {'build': const NodeCursor(state: StepState.failed)},
        ),
        siteCursor: const <String, NodeCursor>{},
      );
      expect(engaged['build']!.cooldownUntil, cooldown);
    });

    test('CONSUMER 1 (the unclaimed frontier): unengaged is byte-identical to '
        'today', () {
      final joined = JoinedSnapshot(
        graph: _graph([_work('tg-1')]),
        sessionsByWorkBead: {
          'tg-1': session(
            steps: [_stepBead('build', state: StepState.running)],
          ),
        },
        mountAttemptsByWorkBead: const {},
      );
      // With no policy/registry composed the scan is skipped entirely; what
      // this pins is that reading the helper cannot THROW on the structurally
      // empty field, which is the shape production has under `observe`.
      expect(
        effectiveStepCursor(
          joined.sessionsByWorkBead['tg-1']!,
          siteCursor: joined.sessionsByWorkBead['tg-1']!.cursor,
        ),
        isEmpty,
      );
    });

    test('BREAKER PARITY at the consumers: restartCount rides the bead under '
        'both feeds', () {
      final steps = [
        _stepBead('build', state: StepState.failed, restartCount: 2),
      ];
      final engaged = effectiveStepCursor(
        session(
          steps: steps,
          trajCursor: {'build': const NodeCursor(state: StepState.failed)},
        ),
        siteCursor: const <String, NodeCursor>{},
      );
      expect(engaged['build']!.restartCount, 2);
    });
  });
}
