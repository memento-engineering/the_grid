import 'package:beads_dart/beads_dart.dart';
import 'package:genesis_tree/genesis_tree.dart';
import 'package:grid_engine/grid_engine.dart';
import 'package:grid_engine/src/seeds/provider.dart';
import 'package:grid_engine/testing.dart';
import 'package:grid_runtime/grid_runtime.dart';
import 'package:test/test.dart';

const _circuit = Circuit(
  id: 'code',
  terminalStepId: 'land',
  steps: [
    CapabilityStep(stepId: 'agent', capabilityId: 'agent'),
    CapabilityStep(stepId: 'land', capabilityId: 'land', dependsOn: {'agent'}),
  ],
);

const _config = SubstationConfig(substationId: 'tg', ownedSubstations: {'tg'});

class _Transport implements ExplorationTransport {
  final List<({String name, Map<String, String> data})> flares = [];

  @override
  void flare(String name, Map<String, String> data) =>
      flares.add((name: name, data: data));
}

class _SelectiveThrowingReader implements BeadProbeReader {
  const _SelectiveThrowingReader(this.delegate);

  final BeadProbeReader delegate;

  @override
  Future<Bead?> beadById(String id, {required Set<IssueType> types}) =>
      delegate.beadById(id, types: types);

  @override
  Future<List<Bead>> openBeads({
    required Set<IssueType> types,
    Map<String, String> metadataAll = const {},
    Map<String, String> metadataAny = const {},
  }) {
    if (types.contains(GridIssueTypes.molecule) ||
        types.contains(GridIssueTypes.step)) {
      throw StateError('reap exploded');
    }
    return delegate.openBeads(
      types: types,
      metadataAll: metadataAll,
      metadataAny: metadataAny,
    );
  }

  @override
  Future<List<Bead>> openSuperseding(Set<String> priorIds) =>
      delegate.openSuperseding(priorIds);
}

StationServices _servicesWithFailingReap(Fakes fakes) => StationServices(
  provider: fakes.provider,
  writer: StationBeadWriter(
    bd: BdCliService(fakes.runner),
    reader: _SelectiveThrowingReader(fakes.runner),
    ownership: BeadOwnershipPredicate(const {stateSubstation}),
  ),
  stateSubstation: stateSubstation,
);

JoinedSnapshot _joined(SessionProjection projection, {DateTime? capturedAt}) =>
    JoinedSnapshot(
      graph: GraphSnapshot.fromParts(
        beads: const [Bead(id: 'tg-1', issueType: IssueType.task)],
        dependencies: const [],
        readyIds: const {'tg-1'},
        capturedAt: capturedAt ?? DateTime(2026),
      ),
      sessionsByWorkBead: {projection.workBeadId: projection},
    );

Bead _molecule(String sessionId) => Bead(
  id: '$sessionId-molecule',
  issueType: GridIssueTypes.molecule,
  status: BeadStatus.open,
  metadata: {'rig': 'tgdog', 'grid.circuit.session': sessionId},
);

Bead _step(String sessionId) => Bead(
  id: '$sessionId-step',
  issueType: GridIssueTypes.step,
  status: BeadStatus.open,
  metadata: {
    'rig': 'tgdog',
    'grid.step.session': sessionId,
    'grid.step.path': 'tg-1/agent',
    'grid.step.state': 'pending',
  },
);

Bead _session(String sessionId, String workBeadId) => Bead(
  id: sessionId,
  issueType: GridIssueTypes.session,
  status: BeadStatus.open,
  metadata: {'rig': 'tgdog', 'work_bead': workBeadId},
);

Bead _attempt(String id, String workBeadId) => Bead(
  id: id,
  issueType: GridIssueTypes.mountAttempt,
  status: BeadStatus.open,
  metadata: {
    'rig': 'tgdog',
    StationBeadWriter.mountAttemptWorkBeadKey: workBeadId,
    StationBeadWriter.mountAttemptCountKey: '1',
  },
);

({TreeOwner owner, _Transport transport}) _mount(
  JoinedSnapshotNotifier joined,
  StationServices services,
) {
  final owner = TreeOwner();
  final transport = _Transport();
  owner.mountRoot(
    ProviderScope(
      child: InheritedSeed<JoinedSnapshotNotifier>(
        value: joined,
        child: InheritedSeed<StationServices>(
          value: services,
          child: InheritedSeed<CapabilityRegistry>(
            value: RecordingCapabilityRegistry(circuits: const {}),
            child: InheritedSeed<SessionResolver>(
              value: CircuitResolver((_) => _circuit),
              child: Station([
                SubstationScope(
                  configNotifier: SubstationConfigNotifier(_config),
                  services: ServiceBundle(transport: transport),
                  key: const ValueKey('scope.tg'),
                ),
              ]),
            ),
          ),
        ),
      ),
    ),
  );
  return (owner: owner, transport: transport);
}

Future<void> _pumpUntil(
  TreeOwner owner,
  bool Function() done, {
  int rounds = 500,
}) async {
  for (var i = 0; i < rounds && !done(); i++) {
    await Future<void>.delayed(const Duration(milliseconds: 1));
    owner.flush();
  }
}

List<String> _closedInOrder(RecordingBdRunner runner) {
  final ids = <String>[];
  for (var i = 0; i < runner.calls.length; i++) {
    final call = runner.calls[i];
    if (call.isEmpty) continue;
    if (call.first == 'close' && call.length > 1) ids.add(call[1]);
    if (call.first == 'batch') {
      for (final line in (runner.stdins[i] ?? '').split('\n')) {
        final parts = line.trim().split(RegExp(r'\s+'));
        if (parts.length >= 2 && parts.first == 'close') ids.add(parts[1]);
      }
    }
  }
  return ids;
}

void _expectChildrenBeforeSession(RecordingBdRunner runner, String sessionId) {
  final closed = _closedInOrder(runner);
  final moleculeId = '$sessionId-molecule';
  final stepId = '$sessionId-step';
  expect(closed, containsAll([moleculeId, stepId, sessionId]));
  expect(closed.indexOf(stepId), lessThan(closed.indexOf(sessionId)));
  expect(closed.indexOf(moleculeId), lessThan(closed.indexOf(sessionId)));
}

void _expectChildrenAndAttemptBeforeSession(
  RecordingBdRunner runner,
  String sessionId,
  String attemptId,
) {
  final closed = _closedInOrder(runner);
  expect(closed.where((id) => id == attemptId), hasLength(1));
  expect(closed.indexOf(attemptId), lessThan(closed.indexOf(sessionId)));
  _expectChildrenBeforeSession(runner, sessionId);
}

void _expectLoudNonFatalReapFailure(
  _Transport transport,
  RecordingBdRunner runner, {
  required String sessionId,
  required String closeReason,
}) {
  final flares = transport.flares
      .where((flare) => flare.name == 'session.moleculeReapFailed')
      .toList(growable: false);
  expect(flares, hasLength(1));
  expect(flares.single.data, containsPair('sessionId', sessionId));
  expect(flares.single.data, containsPair('closeReason', closeReason));
  expect(flares.single.data['reason'], contains('reap exploded'));
  expect(_closedInOrder(runner), contains(sessionId));
}

void main() {
  test('positive-terminal close retires mount attempt', () async {
    const sessionId = 'tgdog-positive';
    final fakes = buildFakes();
    fakes.runner.exportBeads = [
      _session(sessionId, 'tg-1'),
      _attempt('tgdog-att-positive', 'tg-1'),
      _molecule(sessionId),
      _step(sessionId),
    ];
    final joined = JoinedSnapshotNotifier(
      _joined(
        const SessionProjection(
          workBeadId: 'tg-1',
          sessionId: sessionId,
          isMolecule: true,
        ),
      ),
    );
    final mounted = _mount(joined, fakes.ctx);
    addTearDown(mounted.owner.dispose);

    joined.push(
      _joined(
        SessionProjection(
          workBeadId: 'tg-1',
          sessionId: sessionId,
          isMolecule: true,
          moleculeBeads: [
            Bead(
              id: '$sessionId-agent',
              issueType: GridIssueTypes.step,
              metadata: const {
                'grid.step.session': sessionId,
                'grid.step.path': 'tg-1/agent',
                'grid.step.state': 'complete',
              },
            ),
            Bead(
              id: '$sessionId-land',
              issueType: GridIssueTypes.step,
              metadata: const {
                'grid.step.session': sessionId,
                'grid.step.path': 'tg-1/land',
                'grid.step.state': 'complete',
              },
            ),
          ],
        ),
      ),
    );
    mounted.owner.flush();
    await _pumpUntil(
      mounted.owner,
      () => _closedInOrder(fakes.runner).contains(sessionId),
    );

    _expectChildrenAndAttemptBeforeSession(
      fakes.runner,
      sessionId,
      'tgdog-att-positive',
    );
  });

  test('positive-terminal dependency cycle is loud and non-fatal', () async {
    const sessionId = 'tgdog-positive-cycle';
    final fakes = buildFakes();
    final graphIds = {
      '$sessionId-molecule',
      '$sessionId-step-a',
      '$sessionId-step-b',
    };
    fakes.runner
      ..exportBeads = [
        _molecule(sessionId),
        for (final suffix in ['a', 'b'])
          Bead(
            id: '$sessionId-step-$suffix',
            issueType: GridIssueTypes.step,
            status: BeadStatus.open,
            metadata: const {'rig': 'tgdog', 'grid.step.session': sessionId},
          ),
      ]
      ..exportDependencies = const [
        BeadDependency(
          issueId: '$sessionId-step-a',
          dependsOnId: '$sessionId-step-b',
          type: DependencyType.blocks,
        ),
        BeadDependency(
          issueId: '$sessionId-step-b',
          dependsOnId: '$sessionId-step-a',
          type: DependencyType.blocks,
        ),
      ];
    final joined = JoinedSnapshotNotifier(
      _joined(
        const SessionProjection(
          workBeadId: 'tg-1',
          sessionId: sessionId,
          isMolecule: true,
        ),
      ),
    );
    final mounted = _mount(joined, fakes.ctx);
    addTearDown(mounted.owner.dispose);

    joined.push(
      _joined(
        SessionProjection(
          workBeadId: 'tg-1',
          sessionId: sessionId,
          isMolecule: true,
          moleculeBeads: [
            for (final stepId in ['agent', 'land'])
              Bead(
                id: '$sessionId-$stepId',
                issueType: GridIssueTypes.step,
                metadata: {
                  'grid.step.session': sessionId,
                  'grid.step.path': 'tg-1/$stepId',
                  'grid.step.state': 'complete',
                },
              ),
          ],
        ),
      ),
    );
    mounted.owner.flush();
    await _pumpUntil(
      mounted.owner,
      () => _closedInOrder(fakes.runner).contains(sessionId),
    );

    final failure = mounted.transport.flares.singleWhere(
      (flare) => flare.name == 'session.moleculeReapFailed',
    );
    expect(failure.data, containsPair('sessionId', sessionId));
    expect(failure.data, containsPair('closeReason', 'positive-terminal'));
    expect(failure.data['reason'], contains('molecule reap dependency cycle:'));
    expect(failure.data['reason'], contains('$sessionId-step-a'));
    expect(failure.data['reason'], contains('$sessionId-step-b'));
    expect(_closedInOrder(fakes.runner), contains(sessionId));
    expect(_closedInOrder(fakes.runner), everyElement(isNot(isIn(graphIds))));
    expect(fakes.runner.callsFor('batch'), isEmpty);
  });

  test('breaker-exhaustion close retires mount attempt', () async {
    const sessionId = 'tgdog-broken';
    final fakes = buildFakes();
    fakes.runner.exportBeads = [
      _session(sessionId, 'tg-1'),
      _attempt('tgdog-att-broken', 'tg-1'),
      _molecule(sessionId),
      _step(sessionId),
    ];
    final joined = JoinedSnapshotNotifier(
      _joined(
        SessionProjection(
          workBeadId: 'tg-1',
          sessionId: sessionId,
          isMolecule: true,
          moleculeBeads: [
            Bead(
              id: '$sessionId-step',
              issueType: GridIssueTypes.step,
              metadata: const {
                'rig': 'tgdog',
                'grid.step.session': sessionId,
                'grid.step.path': 'tg-1/agent',
                'grid.step.state': 'failed',
                'grid.step.restartCount': '3',
                'grid.step.id': 'agent',
                'grid.step.capability': 'agent',
                'grid.step.kind': 'job',
              },
            ),
          ],
        ),
      ),
    );
    final mounted = _mount(joined, fakes.ctx);
    addTearDown(mounted.owner.dispose);

    await _pumpUntil(
      mounted.owner,
      () => _closedInOrder(fakes.runner).contains(sessionId),
    );

    _expectChildrenAndAttemptBeforeSession(
      fakes.runner,
      sessionId,
      'tgdog-att-broken',
    );
  });

  test('rework retirement collects molecule graph before close', () async {
    const sessionId = 'tgdog-retired';
    final fakes = buildFakes(createdId: 'tgdog-successor');
    fakes.runner.exportBeads = [_molecule(sessionId), _step(sessionId)];
    final before = DateTime.now().subtract(const Duration(seconds: 1));
    final joined = JoinedSnapshotNotifier(
      _joined(
        const SessionProjection(
          workBeadId: 'tg-1',
          sessionId: sessionId,
          isMolecule: true,
          cursor: {'tg-1/agent': NodeCursor(state: StepState.gated)},
        ),
        capturedAt: before,
      ),
    );
    final mounted = _mount(joined, fakes.ctx);
    addTearDown(mounted.owner.dispose);

    joined.push(
      _joined(
        const SessionProjection(
          workBeadId: 'tg-1#r1',
          sessionId: sessionId,
          isMolecule: true,
          cursor: {'tg-1/agent': NodeCursor(state: StepState.gated)},
        ),
        capturedAt: before,
      ),
    );
    mounted.owner.flush();
    await _pumpUntil(
      mounted.owner,
      () => _closedInOrder(fakes.runner).contains(sessionId),
    );

    _expectChildrenBeforeSession(fakes.runner, sessionId);
  });

  test('positive-terminal reap failure is loud and non-fatal', () async {
    const sessionId = 'tgdog-positive-failure';
    final fakes = buildFakes();
    fakes.runner.exportBeads = [_molecule(sessionId), _step(sessionId)];
    final joined = JoinedSnapshotNotifier(
      _joined(
        const SessionProjection(
          workBeadId: 'tg-1',
          sessionId: sessionId,
          isMolecule: true,
        ),
      ),
    );
    final mounted = _mount(joined, _servicesWithFailingReap(fakes));
    addTearDown(mounted.owner.dispose);

    joined.push(
      _joined(
        SessionProjection(
          workBeadId: 'tg-1',
          sessionId: sessionId,
          isMolecule: true,
          moleculeBeads: [
            Bead(
              id: '$sessionId-agent',
              issueType: GridIssueTypes.step,
              metadata: const {
                'grid.step.session': sessionId,
                'grid.step.path': 'tg-1/agent',
                'grid.step.state': 'complete',
              },
            ),
            Bead(
              id: '$sessionId-land',
              issueType: GridIssueTypes.step,
              metadata: const {
                'grid.step.session': sessionId,
                'grid.step.path': 'tg-1/land',
                'grid.step.state': 'complete',
              },
            ),
          ],
        ),
      ),
    );
    mounted.owner.flush();
    await _pumpUntil(
      mounted.owner,
      () => _closedInOrder(fakes.runner).contains(sessionId),
    );

    _expectLoudNonFatalReapFailure(
      mounted.transport,
      fakes.runner,
      sessionId: sessionId,
      closeReason: 'positive-terminal',
    );
  });

  test('breaker-exhaustion reap failure is loud and non-fatal', () async {
    const sessionId = 'tgdog-broken-failure';
    final fakes = buildFakes();
    fakes.runner.exportBeads = [_molecule(sessionId), _step(sessionId)];
    final joined = JoinedSnapshotNotifier(
      _joined(
        SessionProjection(
          workBeadId: 'tg-1',
          sessionId: sessionId,
          isMolecule: true,
          moleculeBeads: [
            Bead(
              id: '$sessionId-step',
              issueType: GridIssueTypes.step,
              metadata: const {
                'rig': 'tgdog',
                'grid.step.session': sessionId,
                'grid.step.path': 'tg-1/agent',
                'grid.step.state': 'failed',
                'grid.step.restartCount': '3',
                'grid.step.id': 'agent',
                'grid.step.capability': 'agent',
                'grid.step.kind': 'job',
              },
            ),
          ],
        ),
      ),
    );
    final mounted = _mount(joined, _servicesWithFailingReap(fakes));
    addTearDown(mounted.owner.dispose);

    await _pumpUntil(
      mounted.owner,
      () => _closedInOrder(fakes.runner).contains(sessionId),
    );

    _expectLoudNonFatalReapFailure(
      mounted.transport,
      fakes.runner,
      sessionId: sessionId,
      closeReason: 'breaker-exhausted',
    );
  });

  test('rework-retirement reap failure is loud and non-fatal', () async {
    const sessionId = 'tgdog-retired-failure';
    final fakes = buildFakes(createdId: 'tgdog-successor');
    fakes.runner.exportBeads = [_molecule(sessionId), _step(sessionId)];
    final before = DateTime.now().subtract(const Duration(seconds: 1));
    final joined = JoinedSnapshotNotifier(
      _joined(
        const SessionProjection(
          workBeadId: 'tg-1',
          sessionId: sessionId,
          isMolecule: true,
          cursor: {'tg-1/agent': NodeCursor(state: StepState.gated)},
        ),
        capturedAt: before,
      ),
    );
    final mounted = _mount(joined, _servicesWithFailingReap(fakes));
    addTearDown(mounted.owner.dispose);

    joined.push(
      _joined(
        const SessionProjection(
          workBeadId: 'tg-1#r1',
          sessionId: sessionId,
          isMolecule: true,
          cursor: {'tg-1/agent': NodeCursor(state: StepState.gated)},
        ),
        capturedAt: before,
      ),
    );
    mounted.owner.flush();
    await _pumpUntil(
      mounted.owner,
      () => _closedInOrder(fakes.runner).contains(sessionId),
    );

    _expectLoudNonFatalReapFailure(
      mounted.transport,
      fakes.runner,
      sessionId: sessionId,
      closeReason: 'reworked',
    );
  });
}
