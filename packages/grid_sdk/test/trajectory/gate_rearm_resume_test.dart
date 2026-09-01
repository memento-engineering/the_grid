import 'package:beads_dart/beads_dart.dart';
import 'package:genesis_tree/genesis_tree.dart';
import 'package:grid_engine/grid_engine.dart' hide StepState;
import 'package:grid_engine/grid_engine.dart' as engine show StepState;
import 'package:grid_engine/testing.dart';
import 'package:grid_runtime/grid_runtime.dart';
import 'package:grid_trajectory/grid_trajectory.dart';
import 'package:test/test.dart';

const _routePath = 'tg-1/route';
const _routeStepId = 'tgdog-step-route';

const _circuit = Circuit(
  id: 'code',
  terminalStepId: 'route',
  steps: [CapabilityStep(stepId: 'route', capabilityId: 'route')],
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

final class _CapturingSink implements TrajectoryRecordSink {
  final List<TrajectoryRecord> records = <TrajectoryRecord>[];

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
  Set<String> readyIds = const {},
  int tick = 0,
}) => GraphSnapshot.fromParts(
  beads: beads,
  dependencies: const [],
  readyIds: readyIds,
  capturedAt: DateTime.fromMillisecondsSinceEpoch(tick),
);

Bead _session() => Bead(
  id: 'tgdog-s',
  issueType: GridIssueTypes.session,
  status: BeadStatus.open,
  metadata: const {
    'rig': stateSubstation,
    SessionBeadKeys.workBead: 'tg-1',
    SessionBeadKeys.model: kSessionModelMolecule,
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

({TreeOwner owner, Branch root}) _mount({
  required JoinedSnapshotNotifier joined,
  required StationServices services,
  required CapabilityRegistry registry,
  required _CapturingSink sink,
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
                seatPrefixes: const {'tg', 'tgdog'},
              ),
            ),
            child: InheritedSeed<SessionResolver>(
              value: CircuitResolver((_) => _circuit),
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
}
