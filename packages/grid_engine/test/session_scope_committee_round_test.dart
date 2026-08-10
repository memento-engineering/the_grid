import 'dart:async';

import 'package:beads_dart/beads_dart.dart';
import 'package:genesis_tree/genesis_tree.dart';
import 'package:grid_engine/grid_engine.dart';
import 'package:grid_engine/testing.dart';
import 'package:grid_runtime/grid_runtime.dart';
import 'package:test/test.dart';
import 'package:grid_engine/src/seeds/provider.dart';

const _sessionId = 'tgdog-session';
const _routePath = 'tg-rvt7/spec_review/route';

const _root = Circuit(
  id: 'root',
  terminalStepId: 'spec_review',
  steps: [SubCircuitStep(stepId: 'spec_review', circuitId: 'spec_review')],
);

const _specReview = Circuit(
  id: 'spec_review',
  terminalStepId: 'route',
  steps: [CapabilityStep(stepId: 'route', capabilityId: 'route')],
);

class _RealCommitteeRegistry implements CapabilityRegistry {
  _RealCommitteeRegistry(this.route);

  final RouteCapability route;

  @override
  DateTime now() => DateTime(2026);

  @override
  Circuit? circuit(String circuitId) =>
      circuitId == 'spec_review' ? _specReview : null;

  @override
  Seed host(StepMount mount) =>
      CapabilityHost(capability: route, mount: mount, key: mount.key);
}

class _CurrentRoundRoute extends RouteCapability {
  _CurrentRoundRoute(this.verdicts, this.seenRounds);

  final List<Map<String, String>> verdicts;
  final List<String?> seenRounds;

  @override
  Future<RouteVerdict> route(TreeContext context, StepArgs args) async {
    final round = args.params['grid.round'];
    seenRounds.add(round);
    final current =
        round != null && verdicts.every((verdict) => verdict['round'] == round);
    return current
        ? Advance({
            for (final verdict in verdicts) verdict['lane']!: verdict['grade']!,
          })
        : const Escalate('no current-round verdict');
  }
}

class _SiblingResultRoute extends RouteCapability {
  _SiblingResultRoute(this.sourcePath, this.seenGrades);

  final String sourcePath;
  final List<String?> seenGrades;

  @override
  Future<RouteVerdict> route(TreeContext context, StepArgs args) async {
    final siblings =
        context.getInheritedSeedOfExactType<SiblingView>() ??
        const SiblingView();
    final grade = siblings.resultOf(sourcePath)[ResultKeys.grade];
    seenGrades.add(grade);
    return grade == 'A'
        ? const Advance({'joined': 'A'})
        : const Escalate('current verdict unavailable');
  }
}

Bead _stepBead(
  String id, {
  required String path,
  required StepState state,
  String capability = 'route',
  Map<String, String> result = const {},
}) => Bead(
  id: id,
  issueType: GridIssueTypes.step,
  status: BeadStatus.open,
  metadata: {
    MoleculeStepKeys.path: path,
    MoleculeStepKeys.session: _sessionId,
    MoleculeStepKeys.state: state.name,
    MoleculeStepKeys.stepId: path.split('/').last,
    MoleculeStepKeys.capability: capability,
    MoleculeStepKeys.kind: StepKind.job.name,
    for (final entry in result.entries)
      ResultKeys.keyFor(path, entry.key): entry.value,
  },
);

SessionProjection _projection(
  List<Bead> routeIncarnations,
  List<BeadDependency> supersedes,
) => SessionProjection(
  workBeadId: 'tg-rvt7',
  sessionId: _sessionId,
  isMolecule: true,
  cursor: const {_routePath: NodeCursor()},
  moleculeBeads: [
    _stepBead(
      'spec-review',
      path: 'tg-rvt7/spec_review',
      state: StepState.pending,
      capability: 'spec_review',
    ),
    ...routeIncarnations,
  ],
  moleculeDependencies: supersedes,
);

List<Map<String, String>> _verdicts(String round) => [
  {'lane': 'plan-completeness', 'grade': 'A', 'round': round},
  {'lane': 'coherence', 'grade': 'B', 'round': round},
  {'lane': 'adr-alignment', 'grade': 'A', 'round': round},
  {'lane': 'acceptance-testability', 'grade': 'A', 'round': round},
];

BeadDependency _supersedes(String successor, String prior) => BeadDependency(
  issueId: successor,
  dependsOnId: prior,
  type: DependencyType.supersedes,
);

Future<void> _pump() async {
  for (var i = 0; i < 40; i++) {
    await Future<void>.delayed(Duration.zero);
  }
}

void main() {
  roundFreezeRegression();
  test('threads nested committee rounds from supersedes depth', () async {
    final fakes = buildFakes();
    final services = StationServices(
      provider: fakes.provider,
      writer: StationBeadWriter(
        bd: BdCliService(fakes.runner),
        reader: fakes.runner,
        ownership: BeadOwnershipPredicate(const {stateSubstation, 'route'}),
      ),
      stateSubstation: stateSubstation,
    );
    final transport = RecordingExplorationTransport();
    final seenRounds = <String?>[];
    var owner = TreeOwner();
    addTearDown(() {
      owner.dispose();
      unawaited(fakes.provider.close());
    });

    void mount(SessionProjection projection, String round) {
      owner.mountRoot(
        ProviderScope(
          child: InheritedSeed<StationServices>(
            value: services,
            child: InheritedSeed<CapabilityRegistry>(
              value: _RealCommitteeRegistry(
                _CurrentRoundRoute(_verdicts(round), seenRounds),
              ),
              child: InheritedSeed<ServiceBundle>(
                value: ServiceBundle(transport: transport),
                child: SessionScope(
                  bead: bead('tg-rvt7'),
                  circuit: _root,
                  existingSession: projection,
                ),
              ),
            ),
          ),
        ),
      );
    }

    final route0 = _stepBead(
      'route-0',
      path: _routePath,
      state: StepState.complete,
    );
    final route1 = _stepBead(
      'route-1',
      path: _routePath,
      state: StepState.complete,
    );
    final route2 = _stepBead(
      'route-2',
      path: _routePath,
      state: StepState.pending,
    );
    final round2 = _projection(
      [route0, route1, route2],
      [_supersedes('route-1', 'route-0'), _supersedes('route-2', 'route-1')],
    );
    expect(round2.cursor.values.every((node) => node.rewindCount == 0), isTrue);

    mount(round2, '2');
    await _pump();

    expect(seenRounds, ['2']);
    expect(transport.named('step.persistFailed'), isEmpty);
    final round2Write = fakes.runner.callsFor('update').single;
    expect(round2Write[1], 'route-2');
    final round2Metadata = fakes.runner.metadataOfUpdate(0);
    expect(round2Metadata[MoleculeStepKeys.state], StepState.complete.name);
    expect(fakes.runner.callsFor('create'), isEmpty);
    for (final verdict in _verdicts('2')) {
      expect(
        round2Metadata[ResultKeys.keyFor(_routePath, verdict['lane']!)],
        verdict['grade'],
      );
    }

    owner.dispose();
    owner = TreeOwner();
    final route3 = _stepBead(
      'route-3',
      path: _routePath,
      state: StepState.pending,
    );
    mount(
      _projection(
        [route0, route1, route2, route3],
        [
          _supersedes('route-1', 'route-0'),
          _supersedes('route-2', 'route-1'),
          _supersedes('route-3', 'route-2'),
        ],
      ),
      '3',
    );
    await _pump();

    expect(fakes.runner.callsFor('create'), isEmpty);
    expect(seenRounds, ['2', '3']);
    expect(fakes.runner.callsFor('update').last[1], 'route-3');
  });

  test('routes with results from only the active step incarnation', () async {
    final fakes = buildFakes();
    final services = StationServices(
      provider: fakes.provider,
      writer: StationBeadWriter(
        bd: BdCliService(fakes.runner),
        reader: fakes.runner,
        ownership: BeadOwnershipPredicate(const {stateSubstation, 'route'}),
      ),
      stateSubstation: stateSubstation,
    );
    final transport = RecordingExplorationTransport();
    final seenGrades = <String?>[];
    var owner = TreeOwner();
    addTearDown(() {
      owner.dispose();
      unawaited(fakes.provider.close());
    });

    const sourcePath = 'tg-rvt7/spec_review/coherence';

    void mount(SessionProjection projection) {
      owner.mountRoot(
        ProviderScope(
          child: InheritedSeed<StationServices>(
            value: services,
            child: InheritedSeed<CapabilityRegistry>(
              value: _RealCommitteeRegistry(
                _SiblingResultRoute(sourcePath, seenGrades),
              ),
              child: InheritedSeed<ServiceBundle>(
                value: ServiceBundle(transport: transport),
                child: SessionScope(
                  bead: bead('tg-rvt7'),
                  circuit: _root,
                  existingSession: projection,
                ),
              ),
            ),
          ),
        ),
      );
    }

    final predecessor = _stepBead(
      'coherence-prior',
      path: sourcePath,
      state: StepState.complete,
      result: const {ResultKeys.grade: 'F'},
    );
    final successor = _stepBead(
      'coherence-current',
      path: sourcePath,
      state: StepState.complete,
      result: const {ResultKeys.grade: 'A'},
    );
    final pendingRoute = _stepBead(
      'route-current',
      path: _routePath,
      state: StepState.pending,
    );
    mount(
      _projection(
        [successor, predecessor, pendingRoute],
        [_supersedes(successor.id, predecessor.id)],
      ),
    );
    await _pump();

    expect(seenGrades, ['A']);
    expect(fakes.runner.callsFor('update').single[1], 'route-current');
    expect(
      fakes.runner.metadataOfUpdate(0)[MoleculeStepKeys.state],
      StepState.complete.name,
    );

    owner.dispose();
    owner = TreeOwner();
    final resultFreeSuccessor = _stepBead(
      'coherence-result-free',
      path: sourcePath,
      state: StepState.complete,
    );
    final secondPendingRoute = _stepBead(
      'route-result-free',
      path: _routePath,
      state: StepState.pending,
    );
    mount(
      _projection(
        [resultFreeSuccessor, predecessor, secondPendingRoute],
        [_supersedes(resultFreeSuccessor.id, predecessor.id)],
      ),
    );
    await _pump();

    expect(seenGrades.last, isNull);
  });
}

/// Delivers a projection UPDATE into the SAME tree — the mid-wave shape the
/// single-shot mounts above cannot reproduce (tg-q3q0 deep).
class _ProjectionHost extends StatefulSeed {
  const _ProjectionHost({
    required this.initial,
    required this.registry,
    required this.onState,
  });

  final SessionProjection initial;
  final CapabilityRegistry registry;
  final void Function(_ProjectionHostState) onState;

  @override
  State<_ProjectionHost> createState() => _ProjectionHostState();
}

class _ProjectionHostState extends State<_ProjectionHost> {
  late SessionProjection _projection;

  @override
  void initState() {
    _projection = seed.initial;
    seed.onState(this);
  }

  void update(SessionProjection next) => setState(() => _projection = next);

  @override
  Seed build(TreeContext context) => InheritedSeed<CapabilityRegistry>(
    value: seed.registry,
    child: SessionScope(
      bead: bead('tg-rvt7'),
      circuit: _root,
      existingSession: _projection,
    ),
  );
}

void roundFreezeRegression() {
  test('tg-q3q0 (deep): a supersedes edge landing AFTER the successor mounts '
      're-keys the element — grid.round can never stay frozen at the old '
      'round (the round-0 starvation class)', () async {
    final fakes = buildFakes();
    final services = StationServices(
      provider: fakes.provider,
      writer: StationBeadWriter(
        bd: BdCliService(fakes.runner),
        reader: fakes.runner,
        ownership: BeadOwnershipPredicate(const {stateSubstation, 'route'}),
      ),
      stateSubstation: stateSubstation,
    );
    final transport = RecordingExplorationTransport();
    final seenRounds = <String?>[];
    final owner = TreeOwner();
    addTearDown(() {
      owner.dispose();
      unawaited(fakes.provider.close());
    });

    final route0 = _stepBead(
      'route-0',
      path: _routePath,
      state: StepState.complete,
    );
    final route1 = _stepBead(
      'route-1',
      path: _routePath,
      state: StepState.pending,
    );
    // THE WINDOW: the successor exists at the path with NO supersedes edge
    // (the mint's writes are not atomic) — both incarnations at depth 0, and
    // the active-bead tie-break (strict >, first-encountered wins) selects
    // the SUCCESSOR when it happens to iterate first: a pending step at
    // round 0.
    final windowProjection = _projection([route1, route0], const []);
    // THE EDGE LANDS a snapshot later — depth 1.
    final edgedProjection = _projection(
      [route1, route0],
      [_supersedes('route-1', 'route-0')],
    );

    _ProjectionHostState? hostState;
    final host = _ProjectionHost(
      initial: windowProjection,
      registry: _RealCommitteeRegistry(
        _CurrentRoundRoute(_verdicts('1'), seenRounds),
      ),
      onState: (state) => hostState = state,
    );
    owner.mountRoot(
      ProviderScope(
        child: InheritedSeed<StationServices>(
          value: services,
          child: InheritedSeed<ServiceBundle>(
            value: ServiceBundle(transport: transport),
            child: host,
          ),
        ),
      ),
    );
    await _pump();
    expect(seenRounds, [
      '0',
    ], reason: 'the window mount runs with the pre-edge round');

    hostState!.update(edgedProjection);
    owner.flush();
    await _pump();

    expect(
      seenRounds,
      ['0', '1'],
      reason:
          'the edge landing must RE-KEY the step element so the lane '
          're-runs with the incremented round — a frozen element repeats '
          "round 0 and the route's current-round join starves",
    );
  });
}
