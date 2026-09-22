import 'package:grid_engine/grid_engine.dart';
import 'package:test/test.dart';

void main() {
  test('lease breadcrumbs use P2 and P6 without legacy metadata fallback', () {
    final graph = ProjectionGraphRead(
      sessionId: 'session-1',
      round: 0,
      steps: const _StepSnapshot(),
      edges: const _EdgeSnapshot(),
      processIdentities: const _ProcessSnapshot(),
      isAuthoritative: true,
    );

    final step = graph.stepAt('work/build') as ProjectionStepMaterialized;
    expect(
      step.lease,
      const ProjectionAttemptLeaseHeld(
        attemptId: 'attempt-projected',
        pid: 42,
        pgid: 41,
      ),
    );
    expect(step.cursor.token, 'attempt-projected');
    expect(step.cursor.pid, 42);
    expect(step.cursor.pgid, 41);
  });
}

final class _Step implements StepTransitionCursorView {
  const _Step();

  @override
  String get sessionId => 'session-1';
  @override
  int get round => 0;
  @override
  String get stepPath => 'work/build';
  @override
  int get stepRound => 0;
  @override
  String get stepState => 'running';
  @override
  int get incarnation => 2;
  @override
  String? get attemptId => 'attempt-projected';
  @override
  int? get supersededByStepRound => null;
  @override
  DateTime? get cooldownUntil => null;
  @override
  int? get restartBudget => 3;
  @override
  DateTime? get startedAt => null;
  @override
  DateTime? get readyAt => null;
  @override
  DateTime? get completedAt => null;
  @override
  String? get failureClass => null;
  @override
  Map<String, Object?>? get result => null;
  @override
  int get lastSeq => 1;
}

final class _StepSnapshot implements TrajectoryStepSnapshot {
  const _StepSnapshot();

  @override
  Iterable<StepCursorView> byP2SessionId(String sessionId) => const [_Step()];
  @override
  int get version => 1;
  @override
  TrajectorySnapshotHealth get health => TrajectorySnapshotHealth.live;
  @override
  DateTime? get seededAt => DateTime.utc(2026);
  @override
  DateTime? get firstEpochClaimedAt => DateTime.utc(2026);
}

final class _EdgeSnapshot implements TrajectoryStepEdgeSnapshot {
  const _EdgeSnapshot();

  @override
  Iterable<TrajectoryStepEdgeView> bySessionId(String sessionId) => const [];
  @override
  Iterable<TrajectoryStepEdgeView> get rows => const [];
  @override
  int get version => 1;
  @override
  TrajectorySnapshotHealth get health => TrajectorySnapshotHealth.live;
  @override
  DateTime? get seededAt => DateTime.utc(2026);
}

final class _Process implements ProcessIdentityView {
  const _Process();

  @override
  String get attemptId => 'attempt-projected';
  @override
  String get sessionId => 'session-1';
  @override
  int get round => 0;
  @override
  String get stepPath => 'work/build';
  @override
  int get stepRound => 0;
  @override
  int get incarnation => 2;
  @override
  int? get pid => 42;
  @override
  int? get pgid => 41;
  @override
  String? get leaseState => 'held';
  @override
  String? get worktree => null;
  @override
  String? get branch => null;
  @override
  String? get baseSha => null;
  @override
  bool? get adoptedExisting => null;
  @override
  String? get worktreeState => null;
  @override
  String? get predecessorAttemptId => null;
  @override
  int get lastSeq => 1;
}

final class _ProcessSnapshot implements TrajectoryProcessIdentitySnapshot {
  const _ProcessSnapshot();

  @override
  Iterable<ProcessIdentityView> bySessionId(String sessionId) => const [
    _Process(),
  ];
  @override
  Iterable<ProcessIdentityView> get rows => const [_Process()];
  @override
  int get version => 1;
  @override
  TrajectorySnapshotHealth get health => TrajectorySnapshotHealth.live;
  @override
  DateTime? get seededAt => DateTime.utc(2026);
  @override
  DateTime? get lastTickAt => DateTime.utc(2026);
}
