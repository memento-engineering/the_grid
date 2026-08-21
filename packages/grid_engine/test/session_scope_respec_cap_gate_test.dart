import 'dart:async';

import 'package:beads_dart/beads_dart.dart';
import 'package:genesis_tree/genesis_tree.dart';
import 'package:grid_engine/grid_engine.dart';
import 'package:grid_engine/src/molecule/live_frontier.dart';
import 'package:grid_engine/src/molecule/molecule_codec.dart'
    show supersedesDepthByPath, supersedesVerdictCountByPath;
import 'package:grid_engine/src/molecule/molecule_schema.dart';
import 'package:grid_engine/testing.dart';
import 'package:grid_runtime/grid_runtime.dart';
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

StationServices _ctxOver(RecordingBdRunner runner) => StationServices(
  provider: FakeRuntimeProvider(),
  writer: StationBeadWriter(
    bd: BdCliService(runner),
    reader: runner,
    ownership: BeadOwnershipPredicate(const {stateSubstation}),
  ),
  stateSubstation: stateSubstation,
);

({TreeOwner owner, Fakes fakes}) _mount({
  ServiceBundle services = const ServiceBundle(),
  Set<int> specifyVerdicts = const {0, 1, 2},
  SessionProjection? projection,
  RecordingBdRunner? runner,
  Circuit circuit = rootCircuit,
  Map<String, Circuit> circuits = const {'spec_review': specReviewCircuit},
}) {
  final fakes = buildFakes();
  final owner = TreeOwner();
  final effectiveProjection =
      projection ?? _projection(specifyVerdicts: specifyVerdicts);
  final joined = _joined(effectiveProjection);
  final registry = RecordingCapabilityRegistry(circuits: circuits);
  owner.mountRoot(
    ProviderScope(
      child: InheritedSeed<JoinedSnapshotNotifier>(
        value: joined,
        child: InheritedSeed<StationServices>(
          value: runner == null ? fakes.ctx : _ctxOver(runner),
          child: InheritedSeed<ServiceBundle>(
            value: services,
            child: InheritedSeed<CapabilityRegistry>(
              value: registry,
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
  );
  return (owner: owner, fakes: fakes);
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
