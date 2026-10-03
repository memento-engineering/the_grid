import 'package:beads_dart/beads_dart.dart';
import 'package:grid_engine/grid_engine.dart';
import 'package:grid_engine/testing.dart';
import 'package:test/test.dart';

final class _StepRow implements StepCursorView {
  const _StepRow({
    required this.sessionId,
    required this.stepPath,
    this.stepRound = 0,
    this.supersededByStepRound,
  });

  @override
  final String sessionId;
  @override
  final String stepPath;
  @override
  final int stepRound;
  @override
  final int? supersededByStepRound;
  @override
  int get round => 0;
  @override
  String get stepState => StepState.pending.name;
  @override
  int get incarnation => stepRound;
  @override
  String? get attemptId => null;
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
  int get lastSeq => stepRound + 1;
}

final class _StepSnapshot implements TrajectoryStepSnapshot {
  const _StepSnapshot(this.rows);

  final List<StepCursorView> rows;

  @override
  Iterable<StepCursorView> byP2SessionId(String sessionId) =>
      rows.where((row) => row.sessionId == sessionId);
  @override
  int get version => 1;
  @override
  TrajectorySnapshotHealth get health => TrajectorySnapshotHealth.live;
  @override
  DateTime? get seededAt => null;
  @override
  DateTime? get firstEpochClaimedAt => null;
}

final class _EdgeRow implements TrajectoryStepEdgeView {
  const _EdgeRow({required this.sessionId, required this.kind});

  @override
  final String sessionId;
  @override
  final String kind;
  @override
  String get fromPath => 'build';
  @override
  String get toPath => 'prep';
  @override
  int get round => 0;
}

final class _EdgeSnapshot implements TrajectoryStepEdgeSnapshot {
  const _EdgeSnapshot(this.rows);

  @override
  final List<TrajectoryStepEdgeView> rows;

  @override
  Iterable<TrajectoryStepEdgeView> bySessionId(String sessionId) =>
      rows.where((row) => row.sessionId == sessionId);
  @override
  int get version => 1;
  @override
  TrajectorySnapshotHealth get health => TrajectorySnapshotHealth.live;
  @override
  DateTime? get seededAt => null;
}

final class _ProcessSnapshot implements TrajectoryProcessIdentitySnapshot {
  const _ProcessSnapshot();

  @override
  Iterable<ProcessIdentityView> bySessionId(String sessionId) => const [];
  @override
  Iterable<ProcessIdentityView> get rows => const [];
  @override
  int get version => 1;
  @override
  TrajectorySnapshotHealth get health => TrajectorySnapshotHealth.live;
  @override
  DateTime? get seededAt => null;
  @override
  DateTime? get lastTickAt => null;
  @override
  bool get tickStalled => false;
}

Bead _work(String id) =>
    Bead(id: id, issueType: IssueType.feature, status: BeadStatus.open);

Bead _session(String id, String workBeadId) => Bead(
  id: id,
  issueType: GridIssueTypes.session,
  status: BeadStatus.open,
  metadata: {
    'rig': 'tgdog',
    'work_bead': workBeadId,
    'grid.session.model': 'molecule',
  },
);

GraphSnapshot _snapshot(Iterable<Bead> beads) => GraphSnapshot.fromParts(
  beads: beads,
  dependencies: const [],
  readyIds: beads.map((bead) => bead.id),
  capturedAt: DateTime.utc(2026, 10, 3),
);

Future<void> _settleStreams() async {
  await Future<void>.delayed(Duration.zero);
  await Future<void>.delayed(Duration.zero);
}

void main() {
  test('shadow isolates a corrupt projection graph per session', () async {
    for (final corruption in ['supersedes-hole', 'unsupported-edge']) {
      final work = FakeSnapshotSource(
        _snapshot([_work('tg-good'), _work('tg-bad')]),
      );
      final state = FakeSnapshotSource(
        _snapshot([
          _session('tgdog-good', 'tg-good'),
          _session('tgdog-bad', 'tg-bad'),
        ]),
      );

      final badRows = corruption == 'supersedes-hole'
          ? const <StepCursorView>[
              _StepRow(
                sessionId: 'tgdog-bad',
                stepPath: 'build',
                supersededByStepRound: 2,
              ),
              _StepRow(sessionId: 'tgdog-bad', stepPath: 'build', stepRound: 1),
            ]
          : const <StepCursorView>[
              _StepRow(sessionId: 'tgdog-bad', stepPath: 'build'),
            ];
      final steps = _StepSnapshot([
        const _StepRow(sessionId: 'tgdog-good', stepPath: 'build'),
        ...badRows,
      ]);
      final edges = _EdgeSnapshot([
        if (corruption == 'unsupported-edge')
          const _EdgeRow(sessionId: 'tgdog-bad', kind: 'contains'),
      ]);
      final flares = <({String name, Map<String, String> data})>[];
      final bridge = StationJoinBridge(
        work: work,
        state: state,
        stepSnapshot: () => steps,
        edgeSnapshot: () => edges,
        processIdentitySnapshot: () => const _ProcessSnapshot(),
        onFlare: (name, data) {
          flares.add((name: name, data: data));
          throw StateError('the flare sink is unavailable');
        },
      );
      final publications = <JoinedSnapshot>[];
      final removeListener = bridge.notifier.addListener(
        publications.add,
        fireImmediately: false,
      );

      bridge.start();
      work.push(_snapshot([_work('tg-good'), _work('tg-bad')]));
      work.push(_snapshot([_work('tg-good'), _work('tg-bad')]));
      await _settleStreams();

      final good = bridge.latest.sessionsByWorkBead['tg-good']!;
      final bad = bridge.latest.sessionsByWorkBead['tg-bad']!;
      expect(publications, hasLength(3));
      expect(good.trajectoryGraph, isNotNull);
      expect(
        good.projectionGraphFailurePosture,
        ProjectionGraphFailurePosture.none,
      );
      expect(bad.trajectoryGraph, isNull);
      expect(
        bad.projectionGraphFailurePosture,
        ProjectionGraphFailurePosture.shadowIsolated,
      );
      expect(flares, hasLength(1));
      expect(flares.single.name, kProjectionGraphRejectedFlare);
      expect(flares.single.data['sessionId'], 'tgdog-bad');
      expect(flares.single.data['workBeadId'], 'tg-bad');
      expect(flares.single.data['round'], '0');
      expect(flares.single.data['posture'], 'shadowIsolated');
      expect(flares.single.data['reason'], contains(corruption.split('-')[0]));

      removeListener();
      bridge.dispose();
      await work.close();
      await state.close();
    }
  });

  test('cut holds only the corrupt session', () async {
    final work = FakeSnapshotSource(
      _snapshot([_work('tg-good'), _work('tg-bad')]),
    );
    final state = FakeSnapshotSource(
      _snapshot([
        _session('tgdog-good', 'tg-good'),
        _session('tgdog-bad', 'tg-bad'),
      ]),
    );
    addTearDown(work.close);
    addTearDown(state.close);
    const steps = _StepSnapshot([
      _StepRow(sessionId: 'tgdog-good', stepPath: 'build'),
      _StepRow(
        sessionId: 'tgdog-bad',
        stepPath: 'build',
        supersededByStepRound: 2,
      ),
      _StepRow(sessionId: 'tgdog-bad', stepPath: 'build', stepRound: 1),
    ]);
    final flares = <({String name, Map<String, String> data})>[];
    final bridge = StationJoinBridge(
      work: work,
      state: state,
      stepSnapshot: () => steps,
      edgeSnapshot: () => const _EdgeSnapshot([]),
      processIdentitySnapshot: () => const _ProcessSnapshot(),
      projectionGraphAuthoritative: true,
      onFlare: (name, data) => flares.add((name: name, data: data)),
    );
    addTearDown(bridge.dispose);

    bridge.start();
    state.push(
      _snapshot([
        _session('tgdog-good', 'tg-good'),
        _session('tgdog-bad', 'tg-bad'),
      ]),
    );
    await _settleStreams();

    final good = bridge.latest.sessionsByWorkBead['tg-good']!;
    final bad = bridge.latest.sessionsByWorkBead['tg-bad']!;
    expect(good.trajectoryGraph, isNotNull);
    expect(good.trajectoryGraph!.isAuthoritative, isTrue);
    expect(
      good.projectionGraphFailurePosture,
      ProjectionGraphFailurePosture.none,
    );
    expect(bad.trajectoryGraph, isNull);
    expect(
      bad.projectionGraphFailurePosture,
      ProjectionGraphFailurePosture.cutHeld,
    );
    expect(flares, hasLength(1));
    expect(flares.single.data['posture'], 'cutHeld');
  });
}
