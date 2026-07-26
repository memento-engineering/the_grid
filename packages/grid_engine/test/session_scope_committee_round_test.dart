import 'dart:async';

import 'package:beads_dart/beads_dart.dart';
import 'package:genesis_tree/genesis_tree.dart';
import 'package:grid_engine/grid_engine.dart';
import 'package:grid_engine/testing.dart';
import 'package:grid_runtime/grid_runtime.dart';
import 'package:test/test.dart';

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

  final _CurrentRoundRoute route;

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

Bead _stepBead(
  String id, {
  required String path,
  required StepState state,
  String capability = 'route',
}) => Bead(
  id: id,
  issueType: IssueType.step,
  status: BeadStatus.open,
  metadata: {
    MoleculeStepKeys.path: path,
    MoleculeStepKeys.session: _sessionId,
    MoleculeStepKeys.state: state.name,
    MoleculeStepKeys.stepId: path.split('/').last,
    MoleculeStepKeys.capability: capability,
    MoleculeStepKeys.kind: StepKind.job.name,
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
  test('threads nested committee rounds from supersedes depth', () async {
    final fakes = buildFakes();
    final services = StationServices(
      provider: fakes.provider,
      writer: StationBeadWriter(
        bd: BdCliService(fakes.runner),
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
        InheritedSeed<StationServices>(
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
        round2Metadata['grid.result.$_routePath.${verdict['lane']}'],
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
}
