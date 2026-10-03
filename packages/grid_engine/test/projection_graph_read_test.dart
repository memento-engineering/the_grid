import 'package:grid_engine/grid_engine.dart';
import 'package:grid_engine/src/molecule/live_frontier.dart';
import 'package:grid_engine/src/molecule/molecule_schema.dart'
    show kValidatesParam;
import 'package:test/test.dart';

void main() {
  test(
    'poured session frontier uses P2 and projected edges without a graph-bead read',
    () {
      final graph = _graph(
        rows: [
          _StepRow(path: 'work/build', state: 'complete'),
          _StepRow(path: 'work/verify'),
        ],
        edges: const [
          _Edge(from: 'work/verify', to: 'work/build', kind: 'blocks'),
        ],
      );
      final circuit = Circuit(
        id: 'code',
        terminalStepId: 'verify',
        steps: const [
          CapabilityStep(stepId: 'build', capabilityId: 'build'),
          CapabilityStep(
            stepId: 'verify',
            capabilityId: 'verify',
            dependsOn: {'build'},
          ),
        ],
      );

      final frontier = eligibleSteps(
        circuit,
        graph.cursor,
        'work',
        circuitById: (_) => null,
        now: DateTime.utc(2026),
        dependencyPathsFor: graph.blockersFor,
      );

      expect(frontier.map((step) => step.stepId), ['verify']);
    },
  );

  test('authoritative zero-edge blockers fall back to declared dependsOn', () {
    final graph = _graph(
      rows: [
        _StepRow(path: 'work/build'),
        _StepRow(path: 'work/verify'),
      ],
    );
    final circuit = Circuit(
      id: 'code',
      terminalStepId: 'verify',
      steps: const [
        CapabilityStep(stepId: 'build', capabilityId: 'build'),
        CapabilityStep(
          stepId: 'verify',
          capabilityId: 'verify',
          dependsOn: {'build'},
        ),
      ],
    );

    expect(graph.blockersFor('work/verify'), isNull);

    final frontier = eligibleSteps(
      circuit,
      graph.cursor,
      'work',
      circuitById: (_) => null,
      now: DateTime.utc(2026),
      dependencyPathsFor: graph.blockersFor,
    );

    expect(frontier.map((step) => step.stepId), ['build']);
  });

  test('authoritative zero-edge validates fall back to declared validates', () {
    final graph = _graph(
      rows: [
        _StepRow(path: 'work/build', state: 'complete'),
        _StepRow(
          path: 'work/verify',
          state: 'complete',
          result: const {ResultKeys.grade: 'F'},
        ),
      ],
    );
    final circuit = Circuit(
      id: 'code',
      terminalStepId: 'verify',
      steps: const [
        CapabilityStep(stepId: 'build', capabilityId: 'build'),
        CapabilityStep(
          stepId: 'verify',
          capabilityId: 'verify',
          dependsOn: {'build'},
          params: {kValidatesParam: 'build'},
        ),
      ],
    );

    expect(graph.validatesFor('work/verify'), isNull);
    expect(
      invalidatedNodes(
        circuit,
        graph.cursor,
        graph.results,
        'work',
        circuitById: (_) => null,
        supersedesDepthByPath: const {},
        validatesPathsFor: graph.validatesFor,
      ),
      contains('work/build'),
    );

    final frontier = liveFrontier(
      circuit,
      graph.cursor,
      graph.results,
      'work',
      circuitById: (_) => null,
      supersedesDepthByPath: const {},
      now: DateTime.utc(2026),
      validatesPathsFor: graph.validatesFor,
      dependencyPathsFor: graph.blockersFor,
    );

    expect(frontier.map((step) => step.stepId), ['build']);
  });

  test('absent P2 row is pending and not complete', () {
    final read = _graph().stepAt('work/unmaterialized');
    expect(read, isA<ProjectionStepNotMaterialized>());
    expect(read.isPending, isTrue);
    expect(read.isComplete, isFalse);
  });

  test('absent P2 row is pending and not superseded', () {
    final read = _graph().stepAt('work/unmaterialized');
    expect(read.isPending, isTrue);
    expect(read.isSuperseded, isFalse);
  });

  test('absent P2 row is pending and not graph-missing', () {
    final read = _graph().stepAt('work/unmaterialized');
    expect(read.isPending, isTrue);
    expect(read.isGraphMissing, isFalse);
  });

  test('result cooldown and restart retain StepTransition values', () {
    final cooldown = DateTime.utc(2026, 9, 22, 12);
    final graph = _graph(
      rows: [
        _StepRow(
          path: 'work/build',
          state: 'failed',
          incarnation: 3,
          cooldown: cooldown,
          restartBudget: 4,
          result: const {'grade': 'F'},
        ),
      ],
      edges: const [
        _Edge(from: 'work/build', to: 'work/other', kind: 'validates'),
      ],
    );

    final read = graph.stepAt('work/build') as ProjectionStepMaterialized;
    final legacy = {
      'work/build': NodeCursor(
        state: StepState.complete,
        restartCount: 99,
        cooldownUntil: DateTime.utc(2030),
      ),
    };
    final served = effectiveStepCursor(
      SessionProjection(
        workBeadId: 'work',
        sessionId: 'session-1',
        isMolecule: true,
        results: const {
          'work/build': {'grade': 'A'},
        },
        trajectoryGraph: graph,
      ),
      siteCursor: legacy,
      beadCursor: legacy,
    );
    expect(read.result, {'grade': 'F'});
    expect(read.cooldownUntil, cooldown);
    expect(read.incarnation, 3);
    expect(read.restartBudget, 4);
    expect(read.cursor.restartCount, 3);
    expect(served['work/build']!.state, StepState.failed);
    expect(served['work/build']!.restartCount, 3);
    expect(served['work/build']!.cooldownUntil, cooldown);
  });

  test('a supersedes chain must close at every predecessor', () {
    expect(
      () => _graph(
        rows: [
          _StepRow(path: 'work/build', stepRound: 0, supersededBy: 2),
          _StepRow(path: 'work/build', stepRound: 1),
        ],
      ),
      throwsStateError,
    );
  });

  test('an exact held P6 row supplies the active P2 lease', () {
    final graph = _graph(
      rows: const [
        _StepRow(
          path: 'work/build',
          state: 'running',
          incarnation: 2,
          attemptId: 'attempt-1',
        ),
      ],
      processes: const [
        _Process(
          attemptId: 'attempt-1',
          stepPath: 'work/build',
          incarnation: 2,
          pid: 42,
          pgid: 41,
        ),
      ],
    );
    final read = graph.stepAt('work/build') as ProjectionStepMaterialized;
    expect(
      read.lease,
      isA<ProjectionAttemptLeaseHeld>()
          .having((lease) => lease.attemptId, 'attempt', 'attempt-1')
          .having((lease) => lease.pid, 'pid', 42)
          .having((lease) => lease.pgid, 'pgid', 41),
    );
  });
}

ProjectionGraphRead _graph({
  List<_StepRow> rows = const [],
  List<_Edge> edges = const [],
  List<_Process> processes = const [],
}) => ProjectionGraphRead(
  sessionId: 'session-1',
  round: 0,
  steps: _Steps(rows),
  edges: _Edges(edges),
  processIdentities: _Processes(processes),
  isAuthoritative: true,
);

final class _StepRow implements StepTransitionCursorView {
  const _StepRow({
    required this.path,
    this.state = 'pending',
    this.stepRound = 0,
    this.supersededBy,
    this.incarnation = 0,
    this.cooldown,
    this.restartBudget,
    this.result,
    this.attemptId,
  });

  final String path;
  final String state;
  @override
  final int stepRound;
  final int? supersededBy;
  @override
  final int incarnation;
  final DateTime? cooldown;
  @override
  final int? restartBudget;
  @override
  final Map<String, Object?>? result;
  @override
  final String? attemptId;
  @override
  String get sessionId => 'session-1';
  @override
  int get round => 0;
  @override
  String get stepPath => path;
  @override
  String get stepState => state;
  @override
  int? get supersededByStepRound => supersededBy;
  @override
  DateTime? get cooldownUntil => cooldown;
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

final class _Steps implements TrajectoryStepSnapshot {
  const _Steps(this.rows);
  final List<StepCursorView> rows;
  @override
  Iterable<StepCursorView> byP2SessionId(String sessionId) => rows;
  @override
  int get version => 1;
  @override
  TrajectorySnapshotHealth get health => TrajectorySnapshotHealth.live;
  @override
  DateTime? get seededAt => DateTime.utc(2026);
  @override
  DateTime? get firstEpochClaimedAt => DateTime.utc(2026);
}

final class _Edge implements TrajectoryStepEdgeView {
  const _Edge({required this.from, required this.to, required this.kind});
  final String from;
  final String to;
  @override
  String get sessionId => 'session-1';
  @override
  int get round => 0;
  @override
  String get fromPath => from;
  @override
  String get toPath => to;
  @override
  final String kind;
}

final class _Edges implements TrajectoryStepEdgeSnapshot {
  const _Edges(this.rows);
  @override
  final List<TrajectoryStepEdgeView> rows;
  @override
  Iterable<TrajectoryStepEdgeView> bySessionId(String sessionId) => rows;
  @override
  int get version => 1;
  @override
  TrajectorySnapshotHealth get health => TrajectorySnapshotHealth.live;
  @override
  DateTime? get seededAt => DateTime.utc(2026);
}

final class _Process implements ProcessIdentityView {
  const _Process({
    required this.attemptId,
    required this.stepPath,
    required this.incarnation,
    this.pid,
    this.pgid,
  });
  @override
  final String attemptId;
  @override
  final String stepPath;
  @override
  final int incarnation;
  @override
  final int? pid;
  @override
  final int? pgid;
  @override
  String? get leaseState => 'held';
  @override
  String get sessionId => 'session-1';
  @override
  int get round => 0;
  @override
  int get stepRound => 0;
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

final class _Processes implements TrajectoryProcessIdentitySnapshot {
  const _Processes(this.rows);
  @override
  final List<ProcessIdentityView> rows;
  @override
  Iterable<ProcessIdentityView> bySessionId(String sessionId) => rows;
  @override
  int get version => 1;
  @override
  TrajectorySnapshotHealth get health => TrajectorySnapshotHealth.live;
  @override
  DateTime? get seededAt => DateTime.utc(2026);
  @override
  DateTime? get lastTickAt => DateTime.utc(2026);
  @override
  bool get tickStalled => false;
}
