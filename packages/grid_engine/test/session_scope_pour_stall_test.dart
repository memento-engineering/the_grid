import 'dart:async';

import 'package:beads_dart/beads_dart.dart';
import 'package:genesis_tree/genesis_tree.dart';
import 'package:grid_engine/grid_engine.dart';
import 'package:grid_engine/src/seeds/provider.dart';
import 'package:grid_engine/testing.dart';
import 'package:grid_runtime/grid_runtime.dart';
import 'package:test/test.dart';

const _code = Circuit(
  id: 'code',
  terminalStepId: 'agent',
  steps: [CapabilityStep(stepId: 'agent', capabilityId: 'agent')],
);

const _sessionId = 'tgdog-session';

SessionProjection _projection({required bool hasStep}) => SessionProjection(
  workBeadId: 'tg-1',
  sessionId: _sessionId,
  isMolecule: true,
  moleculeBeads: hasStep
      ? [
          Bead(
            id: 'step-agent',
            issueType: GridIssueTypes.step,
            status: BeadStatus.open,
            metadata: const {
              MoleculeStepKeys.path: 'tg-1/agent',
              MoleculeStepKeys.session: _sessionId,
              MoleculeStepKeys.state: 'pending',
              MoleculeStepKeys.stepId: 'agent',
              MoleculeStepKeys.capability: 'agent',
              MoleculeStepKeys.kind: 'job',
            },
          ),
        ]
      : const [],
  moleculeDependencies: const [],
);

JoinedSnapshot _freshSnapshot() => JoinedSnapshot(
  graph: GraphSnapshot.fromParts(
    beads: [bead('tg-1')],
    dependencies: const [],
    readyIds: const {'tg-1'},
    capturedAt: DateTime.now(),
  ),
);

final class _ProjectionHost extends StatefulSeed {
  const _ProjectionHost({
    required this.initial,
    required this.services,
    required this.registry,
    required this.transport,
    required this.onState,
    this.reservation,
  });

  final SessionProjection? initial;
  final StationServices services;
  final CapabilityRegistry registry;
  final ExplorationTransport transport;
  final StationAdmissionReservation? reservation;
  final void Function(_ProjectionHostState state) onState;

  @override
  State<_ProjectionHost> createState() => _ProjectionHostState();
}

final class _ProjectionHostState extends State<_ProjectionHost> {
  SessionProjection? _projection;

  @override
  void initState() {
    _projection = seed.initial;
    seed.onState(this);
  }

  void update(SessionProjection projection) =>
      setState(() => _projection = projection);

  void rebuild() => setState(() {});

  @override
  Seed build(TreeContext context) {
    Seed child = SessionScope(
      bead: bead('tg-1'),
      circuit: _code,
      existingSession: _projection,
    );
    final reservation = seed.reservation;
    if (reservation != null) {
      child = Provider<StationAdmissionReservation>.value(
        reservation,
        key: const ValueKey('reservation'),
        child: child,
      );
    }
    return InheritedSeed<JoinedSnapshot>(
      value: _freshSnapshot(),
      child: InheritedSeed<StationServices>(
        value: seed.services,
        child: InheritedSeed<CapabilityRegistry>(
          value: seed.registry,
          child: InheritedSeed<ServiceBundle>(
            value: ServiceBundle(transport: seed.transport),
            child: child,
          ),
        ),
      ),
    );
  }
}

({TreeOwner owner, Branch root, _ProjectionHostState state}) _mount({
  required SessionProjection? projection,
  required StationServices services,
  required RecordingExplorationTransport transport,
  StationAdmissionReservation? reservation,
}) {
  late _ProjectionHostState state;
  final owner = TreeOwner();
  final root = owner.mountRoot(
    ProviderScope(
      child: _ProjectionHost(
        initial: projection,
        services: services,
        registry: RecordingCapabilityRegistry(circuits: const {}),
        transport: transport,
        reservation: reservation,
        onState: (value) => state = value,
      ),
    ),
  );
  return (owner: owner, root: root, state: state);
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

final class _TimeoutFirstMoleculeRead implements BeadProbeReader {
  _TimeoutFirstMoleculeRead(this.delegate);

  final BeadProbeReader delegate;
  bool _timedOut = false;

  @override
  Future<Bead?> beadById(String id, {required Set<IssueType> types}) =>
      delegate.beadById(id, types: types);

  @override
  Future<List<Bead>> openBeads({
    required Set<IssueType> types,
    Map<String, String> metadataAll = const {},
    Map<String, String> metadataAny = const {},
  }) {
    if (!_timedOut && types.contains(GridIssueTypes.molecule)) {
      _timedOut = true;
      throw TimeoutException('Future not completed');
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

void _expectStallFlare(
  RecordingExplorationTransport transport, {
  required String stage,
  required String sessionId,
  required Duration window,
}) {
  final stalled = transport.named('session.moleculePourStalled').toList();
  expect(stalled, hasLength(1));
  expect(stalled.single.data['workBeadId'], 'tg-1');
  expect(stalled.single.data['sessionId'], sessionId);
  expect(stalled.single.data['stage'], stage);
  expect(
    int.parse(stalled.single.data['elapsedMs']!),
    greaterThanOrEqualTo(window.inMilliseconds),
  );
  expect(stalled.single.data, isNot(contains('deadlineConstant')));
  expect(stalled.single.data, isNot(contains('deadlineMs')));
}

void main() {
  test('a continuously empty molecule projection flares once', () async {
    final originalWindow = SessionScopeState.moleculePourStallWindow;
    const window = Duration(milliseconds: 20);
    SessionScopeState.moleculePourStallWindow = window;
    addTearDown(() {
      SessionScopeState.moleculePourStallWindow = originalWindow;
    });

    final fakes = buildFakes();
    addTearDown(fakes.ctx.dispose);
    addTearDown(fakes.provider.close);
    final transport = RecordingExplorationTransport();
    final mounted = _mount(
      projection: _projection(hasStep: false),
      services: fakes.ctx,
      transport: transport,
    );
    addTearDown(mounted.owner.dispose);

    await _pumpUntil(
      mounted.owner,
      () => transport.named('session.moleculePourStalled').isNotEmpty,
    );
    _expectStallFlare(
      transport,
      stage: 'empty-projection',
      sessionId: _sessionId,
      window: window,
    );

    for (var i = 0; i < 3; i++) {
      mounted.state.rebuild();
      mounted.owner.flush();
      await Future<void>.delayed(window);
    }
    expect(transport.named('session.moleculePourStalled'), hasLength(1));
  });

  test('a step projection landing in place cancels the watchdog', () async {
    final originalWindow = SessionScopeState.moleculePourStallWindow;
    const window = Duration(milliseconds: 40);
    SessionScopeState.moleculePourStallWindow = window;
    addTearDown(() {
      SessionScopeState.moleculePourStallWindow = originalWindow;
    });

    final fakes = buildFakes();
    addTearDown(fakes.ctx.dispose);
    addTearDown(fakes.provider.close);
    final transport = RecordingExplorationTransport();
    final mounted = _mount(
      projection: _projection(hasStep: false),
      services: fakes.ctx,
      transport: transport,
    );
    addTearDown(mounted.owner.dispose);

    mounted.state.update(_projection(hasStep: true));
    mounted.owner.flush();
    await Future<void>.delayed(window + const Duration(milliseconds: 20));
    mounted.owner.flush();

    expect(transport.named('session.moleculePourStalled'), isEmpty);
  });

  test(
    'a compensated pour with no replacement grant flares post-void',
    () async {
      final originalWindow = SessionScopeState.moleculePourStallWindow;
      const window = Duration(milliseconds: 20);
      SessionScopeState.moleculePourStallWindow = window;
      addTearDown(() {
        SessionScopeState.moleculePourStallWindow = originalWindow;
      });

      final fakes = buildFakes();
      final services = StationServices(
        provider: fakes.provider,
        writer: StationBeadWriter(
          bd: BdCliService(fakes.runner),
          reader: _TimeoutFirstMoleculeRead(fakes.runner),
          ownership: BeadOwnershipPredicate(const {stateSubstation}),
        ),
        stateSubstation: stateSubstation,
      );
      addTearDown(services.dispose);
      addTearDown(fakes.ctx.dispose);
      addTearDown(fakes.provider.close);
      final transport = RecordingExplorationTransport();
      final snapshot = _freshSnapshot();
      final candidate = StationAdmissionCandidate(
        bead: bead('tg-1'),
        session: null,
      );
      const config = SubstationConfig(
        substationId: 'tg',
        ownedSubstations: {'tg'},
      );
      final initial = services.admission.admitPending(
        snapshot,
        config,
        ServiceBundle(transport: transport),
        [candidate],
      );
      expect(initial.admitted, hasLength(1));
      final mounted = _mount(
        projection: null,
        services: services,
        transport: transport,
        reservation: initial.admitted.single,
      );
      addTearDown(mounted.owner.dispose);

      await _pumpUntil(
        mounted.owner,
        () => transport.named('session.mintAbandoned').isNotEmpty,
      );
      await _pumpUntil(
        mounted.owner,
        () => transport.named('session.moleculePourStalled').isNotEmpty,
      );

      _expectStallFlare(
        transport,
        stage: 'post-void',
        sessionId: 'tgdog-sess1',
        window: window,
      );
      expect(transport.named('session.mintFailed'), isEmpty);
      expect(transport.named('session.mintExhausted'), isEmpty);
    },
  );
}
