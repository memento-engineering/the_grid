import 'package:beads_dart/beads_dart.dart';
import 'package:genesis_tree/genesis_tree.dart';
import 'package:grid_engine/grid_engine.dart' hide StepState;
import 'package:grid_engine/grid_engine.dart' as engine show StepState;
import 'package:grid_engine/src/molecule/molecule_schema.dart'
    show kValidatesParam;
import 'package:grid_engine/testing.dart';
import 'package:grid_runtime/grid_runtime.dart';
import 'package:grid_sdk/grid_sdk.dart'
    show GridCommandCompleted, GridCommandRequest, StationCommandHandler;
import 'package:grid_trajectory/grid_trajectory.dart';
import 'package:test/test.dart';

const _routePath = 'tg-1/route';
const _routeStepId = 'tgdog-step-route';

const _circuit = Circuit(
  id: 'code',
  terminalStepId: 'route',
  steps: [CapabilityStep(stepId: 'route', capabilityId: 'route')],
);

const _reviewRoot = Circuit(
  id: 'review-root',
  terminalStepId: 'deliver',
  steps: [
    SubCircuitStep(stepId: 'review', circuitId: 'review'),
    CapabilityStep(
      stepId: 'deliver',
      capabilityId: 'deliver',
      dependsOn: {'review'},
    ),
  ],
);

const _reviewCircuit = Circuit(
  id: 'review',
  terminalStepId: 'route',
  steps: [
    CapabilityStep(
      stepId: 'code-validation',
      capabilityId: 'code-validation',
      params: {kValidatesParam: 'route'},
    ),
    CapabilityStep(
      stepId: 'route',
      capabilityId: 'review-route',
      dependsOn: {'code-validation'},
    ),
  ],
);

const _discoveryRoot = Circuit(
  id: 'discovery-root',
  terminalStepId: 'spec_review',
  steps: [SubCircuitStep(stepId: 'spec_review', circuitId: 'spec-review')],
);

const _specReviewCircuit = Circuit(
  id: 'spec-review',
  terminalStepId: 'specify',
  steps: [
    SubCircuitStep(stepId: 'discovery', circuitId: 'discovery'),
    CapabilityStep(
      stepId: 'specify',
      capabilityId: 'specify',
      dependsOn: {'discovery'},
    ),
  ],
);

const _discoveryCircuit = Circuit(
  id: 'discovery',
  terminalStepId: 'discovery-route',
  steps: [
    CapabilityStep(
      stepId: 'evidence',
      capabilityId: 'evidence',
      params: {kValidatesParam: 'discovery-route'},
    ),
    CapabilityStep(
      stepId: 'discovery-route',
      capabilityId: 'discovery-route',
      dependsOn: {'evidence'},
    ),
  ],
);

final class _ParkThenAdvanceRoute extends RouteCapability {
  int runs = 0;

  @override
  Future<RouteVerdict> route(TreeContext context, StepArgs args) async {
    runs += 1;
    return runs == 1
        ? const Escalate('park once for operator repair')
        : const Advance({'grade': 'A'});
  }
}

final class _RulingAwareRoute extends RouteCapability {
  _RulingAwareRoute(this.feedingPath);

  final String feedingPath;
  int runs = 0;

  @override
  Future<RouteVerdict> route(TreeContext context, StepArgs args) async {
    runs += 1;
    final siblings =
        context.getInheritedSeedOfExactType<SiblingView>() ??
        const SiblingView();
    final result = siblings.resultOf(feedingPath);
    return result[ResultKeys.grade] == 'A'
        ? Advance({
            ResultKeys.grade: 'A',
            ResultKeys.transport:
                result[ResultKeys.transport] ?? kOperatorRulingTransport,
          })
        : const Escalate('the feeding ruling is still invalidating');
  }
}

final class _CountingSuccess extends ServiceCapability {
  int runs = 0;

  @override
  Future<StepOutcome> run(TreeContext context, StepArgs args) async {
    runs += 1;
    return const Ok();
  }
}

final class _CapturingSink implements TrajectoryRecordSink {
  final List<TrajectoryRecord> records = <TrajectoryRecord>[];

  @override
  bool get accepting => true;

  @override
  void enqueue(
    TrajectoryRecord record, {
    DateTime? occurredAt,
    String? substation,
    TrajectoryProvenance provenance = TrajectoryProvenance.observed,
    String? provenanceBasis,
  }) {
    records.add(record);
  }
}

final class _CompleteLegacySteps implements LegacyStepReader {
  const _CompleteLegacySteps();

  @override
  Future<List<LegacyStepView>> stepViews(String sessionId) async => const [
    LegacyStepView(stepPath: _routePath, state: 'complete'),
  ];
}

TrajectoryEnvelope _envelope(TrajectoryRecord record, int seq) {
  final correlation = record.correlationToJson();
  return TrajectoryEnvelope(
    seq: seq,
    epochSeq: seq,
    recordId: '01JAAAAAAAAAAAAAAAAAAA${seq.toString().padLeft(3, '0')}',
    idemKey: seq.toString().padLeft(64, '0'),
    idemKeyText: record.idemKeyText(
      const IdemContext(station: 'test', bootEpoch: 1),
    ),
    family: record.family,
    recordType: record.recordType,
    typeVersion: record.typeVersion,
    occurredAt: DateTime.utc(2026, 8, 31, 12, 0, seq),
    recordedAt: DateTime.utc(2026, 8, 31, 12, 0, seq),
    station: 'test',
    authorityId: 'test/1',
    bootEpoch: 1,
    source: 'test',
    payload: record.payloadToJson(),
    sessionId: correlation['session_id'] as String?,
    round: correlation['round'] as int?,
    stepPath: correlation['step_path'] as String?,
    stepRound: correlation['step_round'] as int?,
    incarnation: correlation['incarnation'] as int?,
    attemptId: correlation['attempt_id'] as String?,
  );
}

GraphSnapshot _snapshot(
  List<Bead> beads, {
  List<BeadDependency> dependencies = const [],
  Set<String> readyIds = const {},
  int tick = 0,
}) => GraphSnapshot.fromParts(
  beads: beads,
  dependencies: dependencies,
  readyIds: readyIds,
  capturedAt: DateTime.fromMillisecondsSinceEpoch(tick),
);

Bead _session({Map<String, String> results = const {}}) => Bead(
  id: 'tgdog-s',
  issueType: GridIssueTypes.session,
  status: BeadStatus.open,
  metadata: {
    'rig': stateSubstation,
    SessionBeadKeys.workBead: 'tg-1',
    SessionBeadKeys.model: kSessionModelMolecule,
    ...results,
  },
);

Bead _routeStep(engine.StepState state) => Bead(
  id: _routeStepId,
  issueType: GridIssueTypes.step,
  status: BeadStatus.open,
  metadata: {
    'rig': stateSubstation,
    MoleculeStepKeys.stepId: 'route',
    MoleculeStepKeys.capability: 'route',
    MoleculeStepKeys.kind: StepKind.job.name,
    MoleculeStepKeys.path: _routePath,
    MoleculeStepKeys.session: 'tgdog-s',
    MoleculeStepKeys.state: state.name,
  },
);

Bead _gate({required bool closed}) => Bead(
  id: 'tgdog-g1',
  issueType: GridIssueTypes.gate,
  status: closed ? BeadStatus.closed : BeadStatus.open,
  metadata: const {
    'rig': stateSubstation,
    'blocks': 'tgdog-s',
    'node': _routePath,
  },
);

Bead _step({
  required String id,
  required String path,
  required engine.StepState state,
  Map<String, String> results = const {},
}) {
  final stepId = path.substring(path.lastIndexOf('/') + 1);
  return Bead(
    id: id,
    issueType: GridIssueTypes.step,
    status: BeadStatus.open,
    metadata: {
      'rig': stateSubstation,
      MoleculeStepKeys.stepId: stepId,
      MoleculeStepKeys.capability: stepId,
      MoleculeStepKeys.kind: StepKind.job.name,
      MoleculeStepKeys.path: path,
      MoleculeStepKeys.session: 'tgdog-s',
      MoleculeStepKeys.state: state.name,
      ...nodeResultMetadata(path, results),
    },
  );
}

Bead _nodeGate(String nodePath, {required bool closed}) => Bead(
  id: 'tgdog-g1',
  issueType: GridIssueTypes.gate,
  status: closed ? BeadStatus.closed : BeadStatus.open,
  metadata: {'rig': stateSubstation, 'blocks': 'tgdog-s', 'node': nodePath},
);

({TreeOwner owner, Branch root}) _mount({
  required JoinedSnapshotNotifier joined,
  required StationServices services,
  required CapabilityRegistry registry,
  required _CapturingSink sink,
  SessionResolver? circuitResolver,
}) {
  final owner = TreeOwner();
  final root = owner.mountRoot(
    InheritedSeed<JoinedSnapshotNotifier>(
      value: joined,
      child: InheritedSeed<StationServices>(
        value: services,
        child: InheritedSeed<CapabilityRegistry>(
          value: registry,
          child: InheritedSeed<TrajectoryRecorderScope>(
            value: TrajectoryRecorderScope(
              StationTrajectoryRecorder(
                sink: sink,
                substationPrefixes: const {'tg', 'tgdog'},
              ),
            ),
            child: InheritedSeed<SessionResolver>(
              value: circuitResolver ?? CircuitResolver((_) => _circuit),
              child: Station([
                SubstationScope(
                  configNotifier: SubstationConfigNotifier(
                    const SubstationConfig(
                      substationId: 'tg',
                      ownedSubstations: {'tg'},
                    ),
                  ),
                  services: const ServiceBundle(),
                  key: const ValueKey('scope.tg'),
                ),
              ]),
            ),
          ),
        ),
      ),
    ),
  );
  return (owner: owner, root: root);
}

Future<void> _pumpUntil(
  TreeOwner owner,
  bool Function() condition, {
  int maxRounds = 500,
}) async {
  for (var round = 0; round < maxRounds && !condition(); round += 1) {
    await Future<void>.delayed(const Duration(milliseconds: 1));
    owner.flush();
  }
  expect(condition(), isTrue, reason: 'condition did not settle');
}

Future<void> _exerciseResidentResolve({
  required Circuit rootCircuit,
  required Map<String, Circuit> circuits,
  required String nodePath,
  required String feedingPath,
  required String routeCapabilityId,
  required String downstreamCapabilityId,
  required String downstreamPath,
  required List<Bead> Function(
    bool? gateClosed,
    engine.StepState routeState,
    Map<String, String> sessionResults,
    Map<String, String> routeResults,
  )
  stateBeads,
}) async {
  BdCliService.resetGuardedWriteCapabilityForTesting();
  final route = _RulingAwareRoute(feedingPath);
  final downstream = _CountingSuccess();
  final sink = _CapturingSink();
  final runner = RecordingBdRunner(createdId: 'tgdog-g1');
  final provider = FakeRuntimeProvider();
  addTearDown(provider.close);
  final ownership = BeadOwnershipPredicate(const {stateSubstation});
  final writer = StationBeadWriter(
    bd: BdCliService(runner),
    reader: runner,
    ownership: ownership,
  );
  final services = StationServices(
    provider: provider,
    writer: writer,
    stateSubstation: stateSubstation,
  );
  final work = FakeSnapshotSource(
    _snapshot([bead('tg-1')], readyIds: const {'tg-1'}),
  );
  final state = FakeSnapshotSource(
    _snapshot(stateBeads(null, engine.StepState.gated, const {}, const {})),
  );
  addTearDown(work.close);
  addTearDown(state.close);
  final bridge = StationJoinBridge(work: work, state: state)..start();
  addTearDown(bridge.dispose);
  final mounted = _mount(
    joined: bridge.notifier,
    services: services,
    registry: DefaultCapabilityRegistry(
      capabilities: {
        routeCapabilityId: route,
        downstreamCapabilityId: downstream,
      },
      circuits: circuits,
      clock: () => DateTime.utc(2026, 9, 16),
    ),
    sink: sink,
    circuitResolver: CircuitResolver((_) => rootCircuit),
  );
  addTearDown(mounted.owner.dispose);
  await _pumpUntil(
    mounted.owner,
    () =>
        runner.callsFor('create').isNotEmpty &&
        runner
            .callsFor('update')
            .any((call) => call.length > 1 && call[1] == 'tgdog-g1'),
  );
  state.push(
    _snapshot(
      stateBeads(false, engine.StepState.gated, const {}, const {}),
      tick: 1,
    ),
  );
  await _pumpUntil(
    mounted.owner,
    () =>
        bridge.latest.sessionsByWorkBead['tg-1']?.openGateNodes.contains(
          nodePath,
        ) ??
        false,
  );
  runner.calls.clear();
  runner.stdins.clear();
  final routeRunsBeforeResolve = route.runs;

  final handler = StationCommandHandler(
    stateSource: state,
    refreshState: () async {},
    stateWriter: writer,
    stateOwnership: ownership,
    workStoresByIdentity: const {},
  );
  const rationale = 'operator accepted the pre-existing finding';
  final result = await handler(
    GridCommandRequest.resolveGate(
      gateId: 'tgdog-g1',
      grades: {feedingPath: 'A'},
      rationale: rationale,
    ),
  );
  expect(result, isA<GridCommandCompleted>());

  final ruling = operatorRulingMetadata(
    feedingPath,
    grade: 'A',
    rationale: rationale,
    evidenceSession: 'tgdog-s',
  );
  final residentMutations = runner.calls
      .where((call) => !call.contains('--help'))
      .toList(growable: false);
  expect(
    residentMutations.map((call) => (call.first, call[1])).toList(),
    const [
      ('update', 'tgdog-s'),
      ('update', 'tgdog-g1'),
      ('update', 'tgdog-g1'),
      ('close', 'tgdog-g1'),
    ],
  );
  expect(residentMutations.first.join(' '), contains('operator-ruling'));

  state.push(
    _snapshot(
      stateBeads(true, engine.StepState.gated, ruling, const {}),
      tick: 2,
    ),
  );
  await _pumpUntil(
    mounted.owner,
    () => sink.records.whereType<StepTransition>().any(
      (record) =>
          record.stepPath == nodePath && record.state == StepState.pending,
    ),
  );
  expect(
    runner
        .callsFor('update')
        .any(
          (call) =>
              call.length > 1 && call[1].contains(nodePath.split('/').last),
        ),
    isTrue,
  );

  state.push(
    _snapshot(
      stateBeads(true, engine.StepState.pending, ruling, const {}),
      tick: 3,
    ),
  );
  await _pumpUntil(
    mounted.owner,
    () => sink.records.whereType<StepTransition>().any(
      (record) =>
          record.stepPath == nodePath && record.state == StepState.complete,
    ),
  );
  state.push(
    _snapshot(
      stateBeads(true, engine.StepState.complete, ruling, const {
        ResultKeys.grade: 'A',
        ResultKeys.transport: kOperatorRulingTransport,
      }),
      tick: 4,
    ),
  );
  await _pumpUntil(mounted.owner, () => downstream.runs == 1);

  final transitions = sink.records
      .whereType<StepTransition>()
      .where((record) => record.stepPath == nodePath)
      .toList(growable: false);
  expect(
    transitions.map((record) => record.state).toList(),
    containsAllInOrder(const [
      StepState.pending,
      StepState.running,
      StepState.complete,
    ]),
  );
  final complete = transitions.lastWhere(
    (record) => record.state == StepState.complete,
  );
  expect(complete.result, containsPair(ResultKeys.grade, 'A'));
  expect(
    complete.result,
    containsPair(ResultKeys.transport, kOperatorRulingTransport),
  );
  expect(
    sink.records.whereType<StepTransition>().any(
      (record) =>
          record.stepPath == downstreamPath &&
          record.state == StepState.running,
    ),
    isTrue,
    reason: 'the downstream step starts by the second state tick',
  );
  expect(route.runs, routeRunsBeforeResolve + 1);
  expect(runner.callsFor('create'), isEmpty, reason: 'the session resumes');
}

void main() {
  test(
    'a gate-cured route resumes on one successor attempt and shadows cleanly',
    () async {
      final route = _ParkThenAdvanceRoute();
      final sink = _CapturingSink();
      final runner = RecordingBdRunner(createdId: 'tgdog-g1');
      final provider = FakeRuntimeProvider();
      addTearDown(provider.close);
      final services = StationServices(
        provider: provider,
        writer: StationBeadWriter(
          bd: BdCliService(runner),
          reader: runner,
          ownership: BeadOwnershipPredicate(const {stateSubstation}),
        ),
        stateSubstation: stateSubstation,
      );
      final work = FakeSnapshotSource(
        _snapshot([bead('tg-1')], readyIds: const {'tg-1'}),
      );
      final state = FakeSnapshotSource(
        _snapshot([_session(), _routeStep(engine.StepState.pending)]),
      );
      final bridge = StationJoinBridge(work: work, state: state)..start();
      addTearDown(bridge.dispose);
      final mounted = _mount(
        joined: bridge.notifier,
        services: services,
        registry: DefaultCapabilityRegistry(
          capabilities: {'route': route},
          clock: () => DateTime.utc(2026, 8, 31, 12),
        ),
        sink: sink,
      );
      addTearDown(mounted.owner.dispose);

      await _pumpUntil(
        mounted.owner,
        () =>
            route.runs == 1 &&
            sink.records.whereType<StepTransition>().any(
              (record) =>
                  record.stepRound == 0 && record.state == StepState.gated,
            ) &&
            runner.callsFor('create').any((call) {
              final type = call.indexOf('--type');
              return type >= 0 &&
                  type + 1 < call.length &&
                  call[type + 1] == 'gate';
            }),
      );

      state.push(
        _snapshot([
          _session(),
          _routeStep(engine.StepState.gated),
          _gate(closed: false),
        ], tick: 1),
      );
      await _pumpUntil(
        mounted.owner,
        () => bridge.latest.sessionsByWorkBead['tg-1']!.openGateNodes.contains(
          _routePath,
        ),
      );

      state.push(
        _snapshot([
          _session(),
          _routeStep(engine.StepState.gated),
          _gate(closed: true),
        ], tick: 2),
      );
      await _pumpUntil(
        mounted.owner,
        () => sink.records.whereType<StepTransition>().any(
          (record) =>
              record.stepRound == 1 && record.state == StepState.pending,
        ),
      );

      state.push(
        _snapshot([
          _session(),
          _routeStep(engine.StepState.pending),
          _gate(closed: true),
        ], tick: 3),
      );
      await _pumpUntil(
        mounted.owner,
        () =>
            route.runs == 2 &&
            sink.records.whereType<StepTransition>().any(
              (record) =>
                  record.stepRound == 1 && record.state == StepState.complete,
            ),
      );

      final transitions = sink.records.whereType<StepTransition>().toList();
      expect(
        transitions.map((record) => (record.stepRound, record.state)).toList(),
        containsAllInOrder(const [
          (0, StepState.gated),
          (1, StepState.pending),
          (1, StepState.running),
          (1, StepState.complete),
        ]),
      );
      final resumed = transitions
          .where((record) => record.stepRound == 1)
          .toList();
      final running = resumed.singleWhere(
        (record) => record.state == StepState.running,
      );
      final complete = resumed.singleWhere(
        (record) => record.state == StepState.complete,
      );
      expect(running.attemptId, isNotEmpty);
      expect(complete.attemptId, running.attemptId);

      final legacyRunningWrites = <Map<String, dynamic>>[
        for (
          var index = 0;
          index < runner.callsFor('update').length;
          index += 1
        )
          if (runner.metadataOfUpdate(index)[MoleculeStepKeys.state] ==
              engine.StepState.running.name)
            runner.metadataOfUpdate(index),
      ];
      expect(
        legacyRunningWrites,
        isEmpty,
        reason:
            'the recorder observes the in-process run without a new legacy '
            'write',
      );

      final envelopes = <TrajectoryEnvelope>[
        for (var index = 0; index < transitions.length; index += 1)
          _envelope(transitions[index], index + 1),
      ];
      final fold = foldStepCursors(envelopes);
      final cured =
          fold.rows[(
            sessionId: 'tgdog-s',
            round: 0,
            stepPath: _routePath,
            stepRound: 1,
          )]!;
      expect(cured.state, 'complete');
      expect(cured.attemptId, running.attemptId);

      final shadow = await StepTransitionShadow(const _CompleteLegacySteps())
          .compare(
            sessionId: 'tgdog-s',
            records: SubjectRecords(records: envelopes),
          );
      expect(shadow.mismatches, isEmpty);
    },
  );

  test(
    'review route resolve records the ruling and reaches deliver within two ticks',
    () async {
      const nodePath = 'tg-1/review/route';
      const feedingPath = 'tg-1/review/code-validation';
      await _exerciseResidentResolve(
        rootCircuit: _reviewRoot,
        circuits: const {'review': _reviewCircuit},
        nodePath: nodePath,
        feedingPath: feedingPath,
        routeCapabilityId: 'review-route',
        downstreamCapabilityId: 'deliver',
        downstreamPath: 'tg-1/deliver',
        stateBeads: (gateClosed, routeState, sessionResults, routeResults) => [
          _session(results: sessionResults),
          _step(
            id: 'tgdog-review',
            path: 'tg-1/review',
            state: engine.StepState.pending,
          ),
          _step(
            id: 'tgdog-code-validation',
            path: feedingPath,
            state: engine.StepState.complete,
            results: const {ResultKeys.grade: 'F'},
          ),
          _step(
            id: 'tgdog-review-route',
            path: nodePath,
            state: routeState,
            results: routeResults,
          ),
          _step(
            id: 'tgdog-deliver',
            path: 'tg-1/deliver',
            state: engine.StepState.pending,
          ),
          if (gateClosed case final closed?)
            _nodeGate(nodePath, closed: closed),
        ],
      );
    },
  );

  test(
    'discovery route resolve records the ruling and reaches specify within two ticks',
    () async {
      const nodePath = 'tg-1/spec_review/discovery/discovery-route';
      const feedingPath = 'tg-1/spec_review/discovery/evidence';
      await _exerciseResidentResolve(
        rootCircuit: _discoveryRoot,
        circuits: const {
          'spec-review': _specReviewCircuit,
          'discovery': _discoveryCircuit,
        },
        nodePath: nodePath,
        feedingPath: feedingPath,
        routeCapabilityId: 'discovery-route',
        downstreamCapabilityId: 'specify',
        downstreamPath: 'tg-1/spec_review/specify',
        stateBeads: (gateClosed, routeState, sessionResults, routeResults) => [
          _session(results: sessionResults),
          _step(
            id: 'tgdog-spec-review',
            path: 'tg-1/spec_review',
            state: engine.StepState.pending,
          ),
          _step(
            id: 'tgdog-discovery',
            path: 'tg-1/spec_review/discovery',
            state: engine.StepState.pending,
          ),
          _step(
            id: 'tgdog-evidence',
            path: feedingPath,
            state: engine.StepState.complete,
            results: const {ResultKeys.grade: 'F'},
          ),
          _step(
            id: 'tgdog-discovery-route',
            path: nodePath,
            state: routeState,
            results: routeResults,
          ),
          _step(
            id: 'tgdog-specify',
            path: 'tg-1/spec_review/specify',
            state: engine.StepState.pending,
          ),
          if (gateClosed case final closed?)
            _nodeGate(nodePath, closed: closed),
        ],
      );
    },
  );
}
