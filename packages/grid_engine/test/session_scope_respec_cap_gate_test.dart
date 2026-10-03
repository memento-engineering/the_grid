import 'dart:async';

import 'package:beads_dart/beads_dart.dart';
import 'package:genesis_tree/genesis_tree.dart';
import 'package:grid_engine/grid_engine.dart';
import 'package:grid_engine/src/molecule/inherited_circuit.dart';
import 'package:grid_engine/src/molecule/live_frontier.dart';
import 'package:grid_engine/src/molecule/molecule_codec.dart'
    show supersedesDepthByPath, supersedesVerdictCountByPath;
import 'package:grid_engine/src/molecule/molecule_schema.dart';
import 'package:grid_engine/testing.dart';
import 'package:grid_runtime/grid_runtime.dart';
import 'package:test/test.dart';

const rootCircuit = Circuit(
  id: 'root',
  steps: [SubCircuitStep(stepId: 'spec_review', circuitId: 'spec_review')],
  terminalStepId: 'spec_review',
);

const specReviewCircuit = Circuit(
  id: 'spec_review',
  steps: [
    CapabilityStep(stepId: 'specify', capabilityId: 'specify'),
    CapabilityStep(
      stepId: 'route',
      capabilityId: 'route',
      dependsOn: {'specify'},
      params: {kValidatesParam: 'specify'},
    ),
  ],
  terminalStepId: 'route',
);

const discoveryCircuit = Circuit(
  id: 'discovery',
  steps: [
    CapabilityStep(stepId: 'anchors', capabilityId: 'anchors'),
    CapabilityStep(
      stepId: 'discovery-route',
      capabilityId: 'route',
      dependsOn: {'anchors'},
      params: {kValidatesParam: 'anchors'},
    ),
  ],
  terminalStepId: 'discovery-route',
);

const retryRootCircuit = Circuit(
  id: 'retry-root',
  steps: [
    SubCircuitStep(stepId: 'spec_review', circuitId: 'spec_review'),
    SubCircuitStep(stepId: 'discovery', circuitId: 'discovery'),
  ],
  terminalStepId: 'spec_review',
);

const sessionId = 'tgdog-session';
const specifyPath = 'tg-lt2a/spec_review/specify';
const routePath = 'tg-lt2a/spec_review/route';
const legacyTargetPath = 'tg-lt2a/legacy-target';
const projectedTargetPath = 'tg-lt2a/projected-target';
const declaredBlockerPath = 'tg-lt2a/declared-blocker';
const projectedBlockerPath = 'tg-lt2a/projected-blocker';
const authorityValidatorPath = 'tg-lt2a/validator';

const authorityCircuit = Circuit(
  id: 'authority',
  steps: [
    CapabilityStep(stepId: 'legacy-target', capabilityId: 'legacy-target'),
    CapabilityStep(
      stepId: 'projected-target',
      capabilityId: 'projected-target',
      dependsOn: {'declared-blocker'},
    ),
    CapabilityStep(
      stepId: 'declared-blocker',
      capabilityId: 'declared-blocker',
    ),
    CapabilityStep(
      stepId: 'projected-blocker',
      capabilityId: 'projected-blocker',
    ),
    CapabilityStep(
      stepId: 'validator',
      capabilityId: 'validator',
      params: {kValidatesParam: 'legacy-target'},
    ),
  ],
  terminalStepId: 'validator',
);

Bead _moleculeBead() => const Bead(
  id: 'molecule-root',
  issueType: GridIssueTypes.molecule,
  status: BeadStatus.open,
  metadata: {
    'rig': stateSubstation,
    MoleculeCircuitKeys.formula: 'root',
    MoleculeCircuitKeys.session: sessionId,
  },
);

Bead _stepBead({
  required String id,
  required String stepId,
  required String capability,
  required String path,
  required StepState state,
  int restartCount = 0,
  Map<String, String> results = const {},
}) => Bead(
  id: id,
  title: stepId,
  issueType: GridIssueTypes.step,
  status: BeadStatus.open,
  metadata: {
    'rig': stateSubstation,
    MoleculeStepKeys.stepId: stepId,
    MoleculeStepKeys.capability: capability,
    MoleculeStepKeys.kind: StepKind.job.name,
    MoleculeStepKeys.path: path,
    MoleculeStepKeys.session: sessionId,
    MoleculeStepKeys.state: state.name,
    MoleculeStepKeys.restartCount: '$restartCount',
    ...results,
  },
);

List<Bead> _moleculeBeads({Set<int> specifyVerdicts = const {0, 1, 2}}) => [
  _moleculeBead(),
  _stepBead(
    id: 'tgdog-spec-review',
    stepId: 'spec_review',
    capability: 'spec_review',
    path: 'tg-lt2a/spec_review',
    state: StepState.pending,
  ),
  for (var generation = 0; generation < 3; generation++)
    _stepBead(
      id: 'tgdog-specify-$generation',
      stepId: 'specify',
      capability: 'specify',
      path: specifyPath,
      state: StepState.complete,
      results: specifyVerdicts.contains(generation)
          ? {
              ResultKeys.keyFor(specifyPath, ResultKeys.grade): 'F',
              ResultKeys.keyFor(specifyPath, ResultKeys.rationale):
                  'spec generation $generation refused',
            }
          : const {},
    ),
  _stepBead(
    id: 'tgdog-specify-3',
    stepId: 'specify',
    capability: 'specify',
    path: specifyPath,
    state: StepState.complete,
  ),
  for (var generation = 0; generation < 4; generation++)
    _stepBead(
      id: 'tgdog-route-$generation',
      stepId: 'route',
      capability: 'route',
      path: routePath,
      state: StepState.complete,
      results: {
        ResultKeys.keyFor(routePath, ResultKeys.grade): 'F',
        ResultKeys.keyFor(routePath, ResultKeys.rationale):
            'spec generation $generation still needs rework',
      },
    ),
];

const _supersedes = [
  BeadDependency(
    issueId: 'tgdog-specify-1',
    dependsOnId: 'tgdog-specify-0',
    type: DependencyType.supersedes,
  ),
  BeadDependency(
    issueId: 'tgdog-specify-2',
    dependsOnId: 'tgdog-specify-1',
    type: DependencyType.supersedes,
  ),
  BeadDependency(
    issueId: 'tgdog-specify-3',
    dependsOnId: 'tgdog-specify-2',
    type: DependencyType.supersedes,
  ),
  BeadDependency(
    issueId: 'tgdog-route-1',
    dependsOnId: 'tgdog-route-0',
    type: DependencyType.supersedes,
  ),
  BeadDependency(
    issueId: 'tgdog-route-2',
    dependsOnId: 'tgdog-route-1',
    type: DependencyType.supersedes,
  ),
  BeadDependency(
    issueId: 'tgdog-route-3',
    dependsOnId: 'tgdog-route-2',
    type: DependencyType.supersedes,
  ),
];

SessionProjection _projection({Set<int> specifyVerdicts = const {0, 1, 2}}) =>
    SessionProjection(
      workBeadId: 'tg-lt2a',
      sessionId: sessionId,
      isMolecule: true,
      moleculeBeads: _moleculeBeads(specifyVerdicts: specifyVerdicts),
      moleculeDependencies: _supersedes,
    );

JoinedSnapshotNotifier _joined(SessionProjection projection) =>
    JoinedSnapshotNotifier(
      JoinedSnapshot(
        graph: GraphSnapshot.fromParts(
          beads: [bead('tg-lt2a')],
          dependencies: const [],
          readyIds: const {'tg-lt2a'},
          capturedAt: DateTime.utc(2026, 7, 26),
        ),
        sessionsByWorkBead: {'tg-lt2a': projection},
      ),
    );

SessionProjection _persistedInvalidationProjection({
  required String sourceCircuit,
}) {
  final isSpec = sourceCircuit == 'spec_review';
  final targetStep = isSpec ? 'specify' : 'anchors';
  final sourceStep = isSpec ? 'route' : 'discovery-route';
  final targetPath = 'tg-lt2a/$sourceCircuit/$targetStep';
  final sourcePath = 'tg-lt2a/$sourceCircuit/$sourceStep';
  return SessionProjection(
    workBeadId: 'tg-lt2a',
    sessionId: sessionId,
    isMolecule: true,
    moleculeBeads: [
      _moleculeBead(),
      _stepBead(
        id: 'tgdog-$sourceCircuit-root',
        stepId: sourceCircuit,
        capability: sourceCircuit,
        path: 'tg-lt2a/$sourceCircuit',
        state: StepState.pending,
      ),
      _stepBead(
        id: 'tgdog-$sourceCircuit-target',
        stepId: targetStep,
        capability: targetStep,
        path: targetPath,
        state: StepState.complete,
      ),
      _stepBead(
        id: 'tgdog-$sourceCircuit-source',
        stepId: sourceStep,
        capability: 'route',
        path: sourcePath,
        state: StepState.complete,
        results: {ResultKeys.keyFor(sourcePath, ResultKeys.grade): 'F'},
      ),
    ],
    moleculeDependencies: const [],
  );
}

SessionProjection _interleavedProjection() {
  final spec = _persistedInvalidationProjection(sourceCircuit: 'spec_review');
  final discovery = _persistedInvalidationProjection(
    sourceCircuit: 'discovery',
  );
  return SessionProjection(
    workBeadId: 'tg-lt2a',
    sessionId: sessionId,
    isMolecule: true,
    moleculeBeads: [
      spec.moleculeBeads.first,
      ...spec.moleculeBeads.skip(1),
      ...discovery.moleculeBeads.skip(1),
    ],
    moleculeDependencies: const [],
  );
}

SessionProjection _authorityProjection({required bool authoritative}) {
  final beads = <Bead>[
    _moleculeBead(),
    _stepBead(
      id: 'tgdog-legacy-target-0',
      stepId: 'legacy-target',
      capability: 'legacy-target',
      path: legacyTargetPath,
      state: StepState.complete,
    ),
    _stepBead(
      id: 'tgdog-legacy-target-1',
      stepId: 'legacy-target',
      capability: 'legacy-target',
      path: legacyTargetPath,
      state: StepState.complete,
    ),
    _stepBead(
      id: 'tgdog-legacy-target-2',
      stepId: 'legacy-target',
      capability: 'legacy-target',
      path: legacyTargetPath,
      state: StepState.failed,
      restartCount: 3,
      results: {ResultKeys.keyFor(legacyTargetPath, 'source'): 'legacy'},
    ),
    _stepBead(
      id: 'tgdog-projected-target',
      stepId: 'projected-target',
      capability: 'projected-target',
      path: projectedTargetPath,
      state: StepState.complete,
    ),
    _stepBead(
      id: 'tgdog-declared-blocker',
      stepId: 'declared-blocker',
      capability: 'declared-blocker',
      path: declaredBlockerPath,
      state: StepState.pending,
    ),
    _stepBead(
      id: 'tgdog-projected-blocker',
      stepId: 'projected-blocker',
      capability: 'projected-blocker',
      path: projectedBlockerPath,
      state: StepState.complete,
    ),
    _stepBead(
      id: 'tgdog-authority-validator',
      stepId: 'validator',
      capability: 'validator',
      path: authorityValidatorPath,
      state: StepState.complete,
      results: {
        ResultKeys.keyFor(authorityValidatorPath, ResultKeys.grade): 'F',
        ResultKeys.keyFor(authorityValidatorPath, 'source'): 'legacy',
      },
    ),
  ];
  const dependencies = <BeadDependency>[
    BeadDependency(
      issueId: 'tgdog-legacy-target-1',
      dependsOnId: 'tgdog-legacy-target-0',
      type: DependencyType.supersedes,
    ),
    BeadDependency(
      issueId: 'tgdog-legacy-target-2',
      dependsOnId: 'tgdog-legacy-target-1',
      type: DependencyType.supersedes,
    ),
  ];
  final graph = ProjectionGraphRead(
    sessionId: sessionId,
    round: 0,
    steps: const _AuthoritySteps([
      _AuthorityStep(path: legacyTargetPath, state: 'complete'),
      _AuthorityStep(
        path: projectedTargetPath,
        state: 'complete',
        stepRound: 0,
        supersededBy: 1,
      ),
      _AuthorityStep(
        path: projectedTargetPath,
        state: 'complete',
        stepRound: 1,
        supersededBy: 2,
        result: {'spent': 'first'},
      ),
      _AuthorityStep(
        path: projectedTargetPath,
        state: 'complete',
        stepRound: 2,
        supersededBy: 3,
      ),
      _AuthorityStep(
        path: projectedTargetPath,
        state: 'complete',
        stepRound: 3,
        supersededBy: 4,
      ),
      _AuthorityStep(
        path: projectedTargetPath,
        state: 'failed',
        stepRound: 4,
        incarnation: 3,
        attemptId: 'projection-attempt',
        result: {'source': 'projection'},
      ),
      _AuthorityStep(path: declaredBlockerPath, state: 'pending'),
      _AuthorityStep(path: projectedBlockerPath, state: 'complete'),
      _AuthorityStep(
        path: authorityValidatorPath,
        state: 'complete',
        result: {'grade': 'F', 'source': 'projection'},
      ),
    ]),
    edges: const _AuthorityEdges([
      _AuthorityEdge(
        from: authorityValidatorPath,
        to: projectedTargetPath,
        kind: 'validates',
      ),
      _AuthorityEdge(
        from: projectedTargetPath,
        to: projectedBlockerPath,
        kind: 'blocks',
      ),
    ]),
    processIdentities: const _AuthorityProcesses([
      _AuthorityProcess(
        attemptId: 'legacy-attempt',
        path: projectedTargetPath,
        stepRound: 4,
        incarnation: 3,
        pid: 800,
        pgid: 801,
      ),
      _AuthorityProcess(
        attemptId: 'projection-attempt',
        path: projectedTargetPath,
        stepRound: 4,
        incarnation: 3,
        pid: 900,
        pgid: 901,
      ),
    ]),
    isAuthoritative: authoritative,
  );
  return SessionProjection(
    workBeadId: 'tg-lt2a',
    sessionId: sessionId,
    isMolecule: true,
    moleculeBeads: beads,
    moleculeDependencies: dependencies,
    trajectoryGraph: graph,
  );
}

final class _AuthorityStep implements StepTransitionCursorView {
  const _AuthorityStep({
    required this.path,
    required this.state,
    this.stepRound = 0,
    this.supersededBy,
    this.incarnation = 0,
    this.attemptId,
    this.result,
  });

  final String path;
  final String state;
  @override
  final int stepRound;
  final int? supersededBy;
  @override
  final int incarnation;
  @override
  final String? attemptId;
  @override
  final Map<String, Object?>? result;
  @override
  String get sessionId => 'tgdog-session';
  @override
  int get round => 0;
  @override
  String get stepPath => path;
  @override
  String get stepState => state;
  @override
  int? get supersededByStepRound => supersededBy;
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

final class _AuthoritySteps implements TrajectoryStepSnapshot {
  const _AuthoritySteps(this.rows);
  final List<StepCursorView> rows;
  @override
  Iterable<StepCursorView> byP2SessionId(String value) => [
    for (final row in rows)
      if (row.sessionId == value) row,
  ];
  @override
  int get version => 1;
  @override
  TrajectorySnapshotHealth get health => TrajectorySnapshotHealth.live;
  @override
  DateTime? get seededAt => null;
  @override
  DateTime? get firstEpochClaimedAt => null;
}

final class _AuthorityEdge implements TrajectoryStepEdgeView {
  const _AuthorityEdge({
    required this.from,
    required this.to,
    required this.kind,
  });
  final String from;
  final String to;
  @override
  String get sessionId => 'tgdog-session';
  @override
  int get round => 0;
  @override
  String get fromPath => from;
  @override
  String get toPath => to;
  @override
  final String kind;
}

final class _AuthorityEdges implements TrajectoryStepEdgeSnapshot {
  const _AuthorityEdges(this.rows);
  @override
  final List<TrajectoryStepEdgeView> rows;
  @override
  Iterable<TrajectoryStepEdgeView> bySessionId(String value) => [
    for (final row in rows)
      if (row.sessionId == value) row,
  ];
  @override
  int get version => 1;
  @override
  TrajectorySnapshotHealth get health => TrajectorySnapshotHealth.live;
  @override
  DateTime? get seededAt => null;
}

final class _AuthorityProcess implements ProcessIdentityView {
  const _AuthorityProcess({
    required this.attemptId,
    required this.path,
    required this.stepRound,
    required this.incarnation,
    required this.pid,
    required this.pgid,
  });
  @override
  final String attemptId;
  final String path;
  @override
  final int stepRound;
  @override
  final int incarnation;
  @override
  final int? pid;
  @override
  final int? pgid;
  @override
  String get sessionId => 'tgdog-session';
  @override
  int get round => 0;
  @override
  String get stepPath => path;
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

final class _AuthorityProcesses implements TrajectoryProcessIdentitySnapshot {
  const _AuthorityProcesses(this.rows);
  @override
  final List<ProcessIdentityView> rows;
  @override
  Iterable<ProcessIdentityView> bySessionId(String value) => [
    for (final row in rows)
      if (row.sessionId == value) row,
  ];
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

final class _AuthorityObservation {
  const _AuthorityObservation({
    required this.mount,
    required this.siblings,
    required this.circuit,
  });
  final StepMount mount;
  final SiblingView siblings;
  final InheritedCircuit circuit;
}

final class _AuthorityRegistry implements CapabilityRegistry {
  final List<_AuthorityObservation> observations = [];

  @override
  Circuit? circuit(String circuitId) => null;

  @override
  Seed host(StepMount mount) =>
      _AuthorityProbe(registry: this, mount: mount, key: mount.key);

  @override
  DateTime now() => DateTime.utc(2026);
}

final class _AuthorityProbe extends StatelessSeed {
  const _AuthorityProbe({
    required this.registry,
    required this.mount,
    super.key,
  });

  final _AuthorityRegistry registry;
  final StepMount mount;

  @override
  Seed build(TreeContext context) {
    final siblings = context.dependOnInheritedSeedOfExactType<SiblingView>();
    final circuit = context
        .dependOnInheritedSeedOfExactType<InheritedCircuit>();
    if (siblings == null || circuit == null) {
      throw StateError('authority probe requires molecule session ambients');
    }
    registry.observations.add(
      _AuthorityObservation(mount: mount, siblings: siblings, circuit: circuit),
    );
    return const Idle();
  }
}

final class _RefusingSuccessorRunner extends RecordingBdRunner {
  _RefusingSuccessorRunner(this.failuresByTitle);

  final Map<String, int> failuresByTitle;
  final Map<String, int> refusedByTitle = {};

  static const message =
      'Error: invalid issue type "agent" '
      '(valid: bug, feature, task, epic, chore, decision, session, molecule, '
      'step, link, mount-attempt)';

  String? _titleOf(List<String> args) {
    final index = args.indexOf('--title');
    return index < 0 ? null : args[index + 1];
  }

  @override
  Future<BdResult> run(
    List<String> args, {
    Duration? timeout,
    String? stdin,
  }) async {
    final title = _titleOf(args);
    final isStepCreate =
        args.isNotEmpty &&
        args.first == 'create' &&
        args.contains('--type') &&
        args.contains(GridIssueTypes.step.wire);
    final refused = title == null ? 0 : refusedByTitle[title] ?? 0;
    final limit = title == null ? 0 : failuresByTitle[title] ?? 0;
    if (isStepCreate && title != null && refused < limit) {
      calls.add(List<String>.unmodifiable(args));
      stdins.add(stdin);
      refusedByTitle[title] = refused + 1;
      throw BdCommandFailed(command: args, exitCode: 1, message: message);
    }
    return await super.run(args, timeout: timeout, stdin: stdin);
  }
}

final class _SuccessorAckSink implements TrajectoryAckRecordSink {
  _SuccessorAckSink({this.resultFor});

  final TrajectoryAppendResult Function(TrajectoryRecord record)? resultFor;
  final List<TrajectoryRecord> records = [];

  @override
  bool get accepting => true;

  @override
  void enqueue(
    TrajectoryRecord record, {
    DateTime? occurredAt,
    String? substation,
    TrajectoryProvenance provenance = TrajectoryProvenance.observed,
    String? provenanceBasis,
  }) => records.add(record);

  @override
  Future<TrajectoryAppendResult> appendAcked(
    TrajectoryRecord record, {
    DateTime? occurredAt,
    String? substation,
    TrajectoryProvenance provenance = TrajectoryProvenance.observed,
    String? provenanceBasis,
    required bool decisionBearing,
  }) async {
    expect(decisionBearing, isTrue);
    records.add(record);
    return resultFor?.call(record) ?? const TrajectoryAppendResult.acked();
  }
}

StationServices _ctxOver(
  RecordingBdRunner runner, {
  required RuntimeProvider provider,
  G2EmissionMode g2EmissionMode = G2EmissionMode.off,
}) => StationServices(
  provider: provider,
  writer: StationBeadWriter(
    bd: BdCliService(runner),
    reader: runner,
    ownership: BeadOwnershipPredicate(const {stateSubstation}),
  ),
  stateSubstation: stateSubstation,
  g2EmissionMode: g2EmissionMode,
);

({TreeOwner owner, Fakes fakes, StationTrajectoryRecorder recorder}) _mount({
  ServiceBundle services = const ServiceBundle(),
  Set<int> specifyVerdicts = const {0, 1, 2},
  SessionProjection? projection,
  RecordingBdRunner? runner,
  Circuit circuit = rootCircuit,
  Map<String, Circuit> circuits = const {'spec_review': specReviewCircuit},
  CapabilityRegistry? registry,
  G2EmissionMode g2EmissionMode = G2EmissionMode.off,
  TrajectoryRecordSink? trajectorySink,
  TrajectoryRecorderFlare? onRecorderFlare,
}) {
  final fakes = buildFakes();
  final owner = TreeOwner();
  final effectiveProjection =
      projection ?? _projection(specifyVerdicts: specifyVerdicts);
  final joined = _joined(effectiveProjection);
  final effectiveRegistry =
      registry ?? RecordingCapabilityRegistry(circuits: circuits);
  final recorder = trajectorySink == null
      ? StationTrajectoryRecorder.disabled()
      : StationTrajectoryRecorder(
          sink: trajectorySink,
          onFlare: onRecorderFlare,
        );
  final station = _ctxOver(
    runner ?? fakes.runner,
    provider: fakes.provider,
    g2EmissionMode: g2EmissionMode,
  );
  owner.mountRoot(
    ProviderScope(
      child: InheritedSeed<JoinedSnapshotNotifier>(
        value: joined,
        child: InheritedSeed<StationServices>(
          value: station,
          child: InheritedSeed<ServiceBundle>(
            value: services,
            child: InheritedSeed<CapabilityRegistry>(
              value: effectiveRegistry,
              child: InheritedSeed<TrajectoryRecorderScope>(
                value: TrajectoryRecorderScope(recorder),
                child: SessionScope(
                  bead: bead('tg-lt2a'),
                  circuit: circuit,
                  existingSession: effectiveProjection,
                ),
              ),
            ),
          ),
        ),
      ),
    ),
  );
  return (owner: owner, fakes: fakes, recorder: recorder);
}

Future<void> _drain() async {
  for (var i = 0; i < 8; i++) {
    await Future<void>.delayed(Duration.zero);
  }
}

Future<void> _pumpUntil(
  TreeOwner owner,
  bool Function() condition, {
  int maxRounds = 500,
}) async {
  for (var i = 0; i < maxRounds && !condition(); i++) {
    await Future<void>.delayed(const Duration(milliseconds: 1));
    owner.flush();
  }
}

void main() {
  test('projection graph authority exposes projected graph inputs', () {
    final registry = _AuthorityRegistry();
    final mounted = _mount(
      projection: _authorityProjection(authoritative: true),
      circuit: authorityCircuit,
      circuits: const {},
      registry: registry,
    );
    addTearDown(mounted.owner.dispose);

    final target = registry.observations.lastWhere(
      (observation) => observation.mount.step.stepId == 'projected-target',
    );
    expect(
      registry.observations.map((observation) => observation.mount.step.stepId),
      contains('projected-target'),
    );
    expect(
      registry.observations.map((observation) => observation.mount.step.stepId),
      isNot(contains('legacy-target')),
    );
    expect(target.mount.circuitRound, 4);
    expect(target.mount.node.rewindCount, 2);
    expect(target.siblings.resultOf(projectedTargetPath), {
      'source': 'projection',
    });
    expect(
      target.siblings.cursorOf(declaredBlockerPath).state,
      StepState.pending,
    );
    expect(
      target.siblings.cursorOf(projectedBlockerPath).state,
      StepState.complete,
    );
    expect(
      target.circuit.projectedLeases[projectedTargetPath],
      const ProjectionAttemptLeaseHeld(
        attemptId: 'projection-attempt',
        pid: 900,
        pgid: 901,
      ),
    );
  });

  test('projection graph authority false preserves every legacy input', () {
    final registry = _AuthorityRegistry();
    final mounted = _mount(
      projection: _authorityProjection(authoritative: false),
      circuit: authorityCircuit,
      circuits: const {},
      registry: registry,
    );
    addTearDown(mounted.owner.dispose);

    final target = registry.observations.lastWhere(
      (observation) => observation.mount.step.stepId == 'legacy-target',
    );
    expect(
      registry.observations.map((observation) => observation.mount.step.stepId),
      contains('legacy-target'),
    );
    expect(
      registry.observations.map((observation) => observation.mount.step.stepId),
      isNot(contains('projected-target')),
    );
    expect(target.mount.circuitRound, 2);
    expect(target.mount.node.rewindCount, 1);
    expect(target.siblings.resultOf(legacyTargetPath), {'source': 'legacy'});
    expect(target.circuit.projectedLeases, isEmpty);
  });

  test('cut-held projection graph idles the affected session', () {
    final registry = _AuthorityRegistry();
    final projection = _authorityProjection(authoritative: true).copyWith(
      trajectoryGraph: null,
      projectionGraphFailurePosture: ProjectionGraphFailurePosture.cutHeld,
    );
    final mounted = _mount(
      projection: projection,
      circuit: authorityCircuit,
      circuits: const {},
      registry: registry,
    );
    addTearDown(mounted.owner.dispose);

    expect(registry.observations, isEmpty);
    expect(mounted.fakes.provider.started, isEmpty);
  });

  test(
    'three verdict-less predecessors mint the depth-four successor',
    () async {
      final projection = _projection(specifyVerdicts: const {});
      expect(
        supersedesDepthByPath(
          projection.moleculeBeads,
          projection.moleculeDependencies,
        )[specifyPath],
        3,
      );
      expect(
        supersedesVerdictCountByPath(
          projection.moleculeBeads,
          projection.moleculeDependencies,
        )[specifyPath],
        0,
      );
      final mounted = _mount(specifyVerdicts: const {});
      addTearDown(mounted.owner.dispose);
      await _drain();
      expect(
        mounted.fakes.runner.callsFor('dep').single,
        containsAllInOrder([
          'dep',
          'add',
          isNot('tgdog-specify-3'),
          'tgdog-specify-3',
          '--type',
          'supersedes',
        ]),
      );
    },
  );

  test('three verdict predecessors gate and never mint a successor', () async {
    final mounted = _mount(specifyVerdicts: const {0, 1, 2});
    addTearDown(mounted.owner.dispose);
    await _drain();
    expect(
      mounted.fakes.runner
          .callsFor('dep')
          .where((call) => call.contains('tgdog-specify-3')),
      isEmpty,
    );
    expect(
      mounted.fakes.runner.callsFor('create').single,
      containsAllInOrder(['--type', 'gate']),
    );
  });

  test(
    'lenny-749o (tg-9q58) keeps structural generation three but spends one',
    () {
      final projection = _projection(specifyVerdicts: const {0});
      expect(
        supersedesDepthByPath(
          projection.moleculeBeads,
          projection.moleculeDependencies,
        )[specifyPath],
        3,
      );
      expect(
        supersedesVerdictCountByPath(
          projection.moleculeBeads,
          projection.moleculeDependencies,
        )[specifyPath],
        1,
      );
    },
  );

  test('a specify cap-out parks at a durable human gate', () async {
    final projection = _projection();
    final projected = projectMoleculeCursor(
      projection.moleculeBeads,
      dependencies: projection.moleculeDependencies,
    );
    final results = <String, Map<String, String>>{};
    for (final step in projection.moleculeBeads) {
      results.addAll(projectCircuitResults(step));
    }
    expect(
      derivedEscalation(
        rootCircuit,
        projected.cursor,
        results,
        'tg-lt2a',
        circuitById: (id) => id == 'spec_review' ? specReviewCircuit : null,
        supersedesDepthByPath: supersedesDepthByPath(
          projection.moleculeBeads,
          projection.moleculeDependencies,
        ),
        spentReworkRoundsByPath: supersedesVerdictCountByPath(
          projection.moleculeBeads,
          projection.moleculeDependencies,
        ),
      )?.path,
      specifyPath,
    );

    final mounted = _mount();
    addTearDown(mounted.owner.dispose);
    await _drain();

    final updates = mounted.fakes.runner.callsFor('update');
    final activeSpecifyUpdate = mounted.fakes.runner.metadataOfUpdate(
      updates.indexWhere((call) => call[1] == 'tgdog-specify-3'),
    );
    expect(activeSpecifyUpdate[MoleculeStepKeys.state], StepState.gated.name);

    final gateCreates = mounted.fakes.runner.callsFor('create');
    expect(gateCreates, hasLength(1));
    expect(gateCreates.single, containsAllInOrder(['--type', 'gate']));
    final gateUpdateIndex = updates.indexWhere(
      (call) => call[1] != 'tgdog-specify-3' && call[1] != sessionId,
    );
    final gateBirth = mounted.fakes.runner.metadataOfUpdate(gateUpdateIndex);
    expect(gateBirth['blocks'], sessionId);
    expect(gateBirth['node'], specifyPath);
    expect(gateBirth['reason'], 'rework cap reached (3/3)');

    expect(
      mounted.fakes.runner
          .callsFor('close')
          .where((call) => call.contains(sessionId)),
      isEmpty,
    );
    final sessionUpdates = <Map<String, dynamic>>[
      for (var i = 0; i < updates.length; i++)
        if (updates[i][1] == sessionId)
          mounted.fakes.runner.metadataOfUpdate(i),
    ];
    expect(
      sessionUpdates.where(
        (metadata) => metadata.containsKey(SessionBeadKeys.escalation),
      ),
      isEmpty,
    );
  });

  test('a specify cap-out traverses the bound escalation handler', () async {
    final handler = RecordingEscalationHandler();
    final mounted = _mount(services: ServiceBundle(escalation: handler));
    addTearDown(mounted.owner.dispose);
    await _drain();

    expect(handler.requests, hasLength(1));
    expect(handler.requests.single.nodePath, specifyPath);
    expect(handler.requests.single.rewindCount, 3);
    expect(handler.requests.single.reason, 'rework cap reached (3/3)');
  });

  test('G2 off mints a successor without observing it', () async {
    final sink = _SuccessorAckSink();
    final mounted = _mount(
      projection: _persistedInvalidationProjection(
        sourceCircuit: 'spec_review',
      ),
      trajectorySink: sink,
    );
    addTearDown(mounted.owner.dispose);

    await _pumpUntil(
      mounted.owner,
      () => mounted.fakes.runner
          .callsFor('dep')
          .any((call) => call.length > 1 && call[1] == 'add'),
    );

    expect(sink.records, isEmpty);
    expect(mounted.recorder.stats.derived, 0);
  });

  test('fresh and existing successors append the same G2 fact', () async {
    Future<TrajectoryRecord> observe({required bool existing}) async {
      final runner = RecordingBdRunner();
      if (existing) {
        runner.exportBeads = [
          _stepBead(
            id: 'tgdog-existing-successor',
            stepId: 'specify',
            capability: 'specify',
            path: specifyPath,
            state: StepState.pending,
          ),
        ];
        runner.exportDependencies = const [
          BeadDependency(
            issueId: 'tgdog-existing-successor',
            dependsOnId: 'tgdog-spec_review-target',
            type: DependencyType.supersedes,
          ),
        ];
      }
      final sink = _SuccessorAckSink();
      final mounted = _mount(
        projection: _persistedInvalidationProjection(
          sourceCircuit: 'spec_review',
        ),
        runner: runner,
        g2EmissionMode: G2EmissionMode.shadow,
        trajectorySink: sink,
      );
      addTearDown(mounted.owner.dispose);

      await _pumpUntil(
        mounted.owner,
        () => sink.records.any(
          (record) => record.correlationToJson()['step_path'] == specifyPath,
        ),
      );
      final record = sink.records.singleWhere(
        (record) => record.correlationToJson()['step_path'] == specifyPath,
      );
      if (existing) {
        expect(
          runner
              .callsFor('create')
              .where(
                (call) =>
                    call.contains(GridIssueTypes.step.wire) &&
                    call.contains('specify'),
              ),
          isEmpty,
        );
      } else {
        expect(
          runner
              .callsFor('create')
              .where(
                (call) =>
                    call.contains(GridIssueTypes.step.wire) &&
                    call.contains('specify'),
              ),
          hasLength(1),
        );
      }
      return record;
    }

    final fresh = await observe(existing: false);
    final existing = await observe(existing: true);
    const context = IdemContext(station: 'station', bootEpoch: 1);
    for (final record in [fresh, existing]) {
      expect(record.recordType, 'step.superseded');
      expect(
        record.idemKeyText(context),
        'supersede:$sessionId:0:$specifyPath:0',
      );
      expect(record.payloadToJson(), {
        'cause': 'validation-failed',
        'budget_remaining': 2,
        'old_step_round': 0,
        'new_step_round': 1,
      });
    }
  });

  test('a failed G2 append does not retry a successful successor', () async {
    final runner = RecordingBdRunner();
    final sink = _SuccessorAckSink(
      resultFor: (record) =>
          record.correlationToJson()['step_path'] == specifyPath
          ? const TrajectoryAppendResult.dropped()
          : const TrajectoryAppendResult.acked(),
    );
    final recorderFlares = <(String, Map<String, String>)>[];
    final transport = RecordingExplorationTransport();
    final mounted = _mount(
      projection: _persistedInvalidationProjection(
        sourceCircuit: 'spec_review',
      ),
      runner: runner,
      g2EmissionMode: G2EmissionMode.shadow,
      trajectorySink: sink,
      onRecorderFlare: (name, data) => recorderFlares.add((name, data)),
      services: ServiceBundle(transport: transport),
    );
    addTearDown(mounted.owner.dispose);

    await _pumpUntil(
      mounted.owner,
      () => sink.records.any(
        (record) => record.correlationToJson()['step_path'] == specifyPath,
      ),
    );
    await _drain();

    expect(
      runner
          .callsFor('create')
          .where(
            (call) =>
                call.contains(GridIssueTypes.step.wire) &&
                call.contains('specify'),
          ),
      hasLength(1),
    );
    expect(transport.named('session.stepSuccessorMintFailed'), isEmpty);
    expect(mounted.recorder.stats.g2ShadowAppendDivergences, 1);
    expect(
      recorderFlares.where(
        (flare) => flare.$1 == 'trajectory.g2ShadowAppendDivergence',
      ),
      hasLength(1),
    );
  });

  for (final sourceCircuit in ['spec_review', 'discovery']) {
    test(
      '$sourceCircuit persistent refusal retries five times and gates',
      () async {
        final targetTitle = sourceCircuit == 'spec_review'
            ? 'specify'
            : 'anchors';
        final targetPath = 'tg-lt2a/$sourceCircuit/$targetTitle';
        final projection = _persistedInvalidationProjection(
          sourceCircuit: sourceCircuit,
        );
        final runner = _RefusingSuccessorRunner({targetTitle: 100});
        final transport = RecordingExplorationTransport();
        final mounted = _mount(
          projection: projection,
          runner: runner,
          circuit: retryRootCircuit,
          circuits: const {
            'spec_review': specReviewCircuit,
            'discovery': discoveryCircuit,
          },
          services: ServiceBundle(transport: transport),
        );
        addTearDown(mounted.owner.dispose);

        await _pumpUntil(
          mounted.owner,
          () =>
              (runner.refusedByTitle[targetTitle] ?? 0) == 5 &&
              runner
                  .callsFor('create')
                  .any(
                    (call) => call.contains('--type') && call.contains('gate'),
                  ),
        );

        expect(runner.refusedByTitle[targetTitle], 5);
        final gateCreates = runner
            .callsFor('create')
            .where((call) => call.contains('--type') && call.contains('gate'));
        expect(gateCreates, hasLength(1));
        final failed = transport
            .named('session.stepSuccessorMintFailed')
            .toList();
        expect(failed, hasLength(5));
        expect(failed.last.data['reason'], contains('invalid issue type'));
        expect(failed.last.data['attempt'], '5');
        expect(
          transport.named('session.stepSuccessorMintExhausted'),
          hasLength(1),
        );
        final updates = runner.callsFor('update');
        final gateUpdate = List<int>.generate(updates.length, (index) => index)
            .firstWhere(
              (index) => runner.metadataOfUpdate(index)['blocks'] == sessionId,
            );
        expect(runner.metadataOfUpdate(gateUpdate)['node'], targetPath);
        expect(
          runner.metadataOfUpdate(gateUpdate)['reason'],
          failed.last.data['reason'],
        );
      },
    );
  }

  test('a transient successor refusal recovers on attempt three', () async {
    final runner = _RefusingSuccessorRunner({'specify': 2});
    final transport = RecordingExplorationTransport();
    final mounted = _mount(
      projection: _persistedInvalidationProjection(
        sourceCircuit: 'spec_review',
      ),
      runner: runner,
      services: ServiceBundle(transport: transport),
    );
    addTearDown(mounted.owner.dispose);

    await _pumpUntil(
      mounted.owner,
      () => runner
          .callsFor('dep')
          .any(
            (call) =>
                call.length > 2 &&
                call[0] == 'dep' &&
                call[1] == 'add' &&
                call.contains('tgdog-spec_review-target'),
          ),
    );

    expect(runner.refusedByTitle['specify'], 2);
    final specifyCreates = runner
        .callsFor('create')
        .where((call) => call.contains('--title') && call.contains('specify'));
    expect(specifyCreates, hasLength(3));
    expect(
      runner
          .callsFor('create')
          .where((call) => call.contains('--type') && call.contains('gate')),
      isEmpty,
    );
    expect(transport.named('session.stepSuccessorMintFailed'), hasLength(2));
    expect(transport.named('session.stepSuccessorMintExhausted'), isEmpty);
  });

  test('interleaved successor budgets are isolated per node path', () async {
    final runner = _RefusingSuccessorRunner({'specify': 2, 'anchors': 100});
    final transport = RecordingExplorationTransport();
    final mounted = _mount(
      projection: _interleavedProjection(),
      runner: runner,
      circuit: retryRootCircuit,
      circuits: const {
        'spec_review': specReviewCircuit,
        'discovery': discoveryCircuit,
      },
      services: ServiceBundle(transport: transport),
    );
    addTearDown(mounted.owner.dispose);

    await _pumpUntil(
      mounted.owner,
      () =>
          (runner.refusedByTitle['anchors'] ?? 0) == 5 &&
          runner
              .callsFor('create')
              .any((call) => call.contains('--type') && call.contains('gate')),
    );

    final stepCreates = runner
        .callsFor('create')
        .where(
          (call) =>
              call.contains('--type') &&
              call.contains(GridIssueTypes.step.wire),
        );
    expect(stepCreates.where((call) => call.contains('specify')), hasLength(3));
    expect(stepCreates.where((call) => call.contains('anchors')), hasLength(5));
    expect(runner.refusedByTitle['specify'], 2);
    expect(runner.refusedByTitle['anchors'], 5);
    final gateCreates = runner
        .callsFor('create')
        .where((call) => call.contains('--type') && call.contains('gate'));
    expect(gateCreates, hasLength(1));
    final updates = runner.callsFor('update');
    final gateUpdate = List<int>.generate(updates.length, (index) => index)
        .firstWhere(
          (index) => runner.metadataOfUpdate(index)['blocks'] == sessionId,
        );
    expect(
      runner.metadataOfUpdate(gateUpdate)['node'],
      'tg-lt2a/discovery/anchors',
    );
    expect(
      transport
          .named('session.stepSuccessorMintFailed')
          .where((flare) => flare.data['nodePath'] == specifyPath),
      hasLength(2),
    );
  });
}
