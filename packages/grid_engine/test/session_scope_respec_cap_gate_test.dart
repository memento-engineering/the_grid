import 'dart:async';

import 'package:beads_dart/beads_dart.dart';
import 'package:genesis_tree/genesis_tree.dart';
import 'package:grid_engine/grid_engine.dart';
import 'package:grid_engine/src/molecule/live_frontier.dart';
import 'package:grid_engine/src/molecule/molecule_codec.dart'
    show supersedesDepthByPath;
import 'package:grid_engine/src/molecule/molecule_schema.dart';
import 'package:grid_engine/testing.dart';
import 'package:test/test.dart';
import 'package:grid_engine/src/seeds/provider.dart';

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

const sessionId = 'tgdog-session';
const specifyPath = 'tg-lt2a/spec_review/specify';
const routePath = 'tg-lt2a/spec_review/route';

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
  Map<String, String> results = const {},
}) => Bead(
  id: id,
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
    ...results,
  },
);

List<Bead> _moleculeBeads() => [
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
      results: {
        ResultKeys.keyFor(specifyPath, ResultKeys.grade): 'F',
        ResultKeys.keyFor(specifyPath, ResultKeys.rationale):
            'spec generation $generation refused',
      },
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

SessionProjection _projection() => SessionProjection(
  workBeadId: 'tg-lt2a',
  sessionId: sessionId,
  isMolecule: true,
  moleculeBeads: _moleculeBeads(),
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

({TreeOwner owner, Fakes fakes}) _mount({
  ServiceBundle services = const ServiceBundle(),
}) {
  final fakes = buildFakes();
  final owner = TreeOwner();
  final projection = _projection();
  final joined = _joined(projection);
  final registry = RecordingCapabilityRegistry(
    circuits: const {'spec_review': specReviewCircuit},
  );
  owner.mountRoot(
    ProviderScope(
      child: InheritedSeed<JoinedSnapshotNotifier>(
        value: joined,
        child: InheritedSeed<StationServices>(
          value: fakes.ctx,
          child: InheritedSeed<ServiceBundle>(
            value: services,
            child: InheritedSeed<CapabilityRegistry>(
              value: registry,
              child: SessionScope(
                bead: bead('tg-lt2a'),
                circuit: rootCircuit,
                existingSession: projection,
              ),
            ),
          ),
        ),
      ),
    ),
  );
  return (owner: owner, fakes: fakes);
}

Future<void> _drain() async {
  for (var i = 0; i < 8; i++) {
    await Future<void>.delayed(Duration.zero);
  }
}

void main() {
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
}
