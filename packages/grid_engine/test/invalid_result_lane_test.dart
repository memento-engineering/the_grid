// One invalid-result lane retries; its three completed siblings are untouched;
// exhaustion parks at exactly one gate; a valid grade F still completes.
// ignore_for_file: invalid_use_of_protected_member
import 'package:genesis_tree/genesis_tree.dart';
import 'package:grid_engine/grid_engine.dart';
import 'package:grid_engine/src/molecule/bead_path_key.dart';
import 'package:grid_engine/src/molecule/inherited_circuit.dart';
import 'package:grid_engine/src/seeds/provider.dart';
import 'package:grid_engine/testing.dart';
import 'package:test/test.dart';

const _lanes = ['critic1', 'critic2', 'critic3', 'critic4'];
final _clock = DateTime.utc(2026);

const _committee = Circuit(
  id: 'committee',
  terminalStepId: 'critic4',
  steps: [
    CapabilityStep(stepId: 'critic1', capabilityId: 'critic'),
    CapabilityStep(stepId: 'critic2', capabilityId: 'critic'),
    CapabilityStep(stepId: 'critic3', capabilityId: 'critic'),
    CapabilityStep(stepId: 'critic4', capabilityId: 'critic'),
  ],
);

Map<String, String> _beadIds() => {
  for (final lane in _lanes) 'tg-1/$lane': 'tgdog-step-$lane',
};

class _FixedCap extends ServiceCapability {
  const _FixedCap(this.outcome);

  final StepOutcome outcome;

  @override
  SupervisionPolicy supervisionPolicy(StepArgs args) =>
      args.params['seat'] == 'strict'
      ? const SupervisionPolicy(
          byKind: {
            CapabilityFailureKind.invalidResult: RetryPolicy(maxRestarts: 1),
          },
        )
      : const SupervisionPolicy.inherit();

  @override
  Future<StepOutcome> run(TreeContext context, StepArgs args) async => outcome;
}

Future<void> _pump() async {
  for (var i = 0; i < 8; i++) {
    await Future<void>.delayed(Duration.zero);
  }
}

Map<String, String> _updateFor(RecordingBdRunner runner, String beadId) {
  final updates = runner.callsFor('update');
  final index = updates.indexWhere((c) => c.length > 1 && c[1] == beadId);
  expect(index, isNot(-1), reason: 'an update for $beadId');
  return runner
      .metadataOfUpdate(index)
      .map((key, value) => MapEntry(key, '$value'));
}

/// The four lanes mounted under ONE root: a keyed multi-child container is the
/// same shape `CircuitScope` inflates, so the siblings are real siblings.
class _Lanes extends MultiChildSeed {
  _Lanes(List<Seed> children) : super(children: children);
}

({TreeOwner owner, Fakes fakes, RecordingExplorationTransport flares})
_driveLanes({
  required Map<String, StepOutcome> outcomes,
  Map<String, Map<String, String>> paramsByLane = const {},
  int restartCount = 0,
}) {
  final fakes = buildFakes();
  final flares = RecordingExplorationTransport();
  final owner = TreeOwner();
  final hosts = <Seed>[
    for (final lane in _lanes)
      CapabilityHost(
        capability: _FixedCap(outcomes[lane]!),
        mount: StepMount(
          step: CapabilityStep(
            stepId: lane,
            capabilityId: 'critic',
            params: paramsByLane[lane] ?? const {},
          ),
          nodePath: 'tg-1/$lane',
          circuit: _committee,
          circuitPath: 'tg-1',
          session: const SessionHandle('tgdog-s'),
          node: NodeCursor(restartCount: restartCount),
          key: ValueKey('tg-1/$lane#$restartCount.0'),
          maxRestarts: 3,
        ),
        key: ValueKey('tg-1/$lane'),
      ),
  ];
  owner.mountRoot(
    ProviderScope(
      child: InheritedSeed<StationServices>(
        value: fakes.ctx,
        child: InheritedSeed<CapabilityRegistry>(
          value: RecordingCapabilityRegistry(clock: _clock),
          child: InheritedSeed<ServiceBundle>(
            value: ServiceBundle(transport: flares),
            child: InheritedSeed<Workspace>(
              value: testWorkspace('tg-1'),
              child: InheritedSeed<InheritedCircuit>(
                value: InheritedCircuit(
                  root: BeadPathKey(const [
                    'tg-1',
                    'tgdog-s',
                    'tgdog-step-critic1',
                  ]),
                  beadIdByNodePath: _beadIds(),
                  cursor: const {},
                ),
                child: _Lanes(hosts),
              ),
            ),
          ),
        ),
      ),
    ),
  );
  return (owner: owner, fakes: fakes, flares: flares);
}

class _CursorHost extends StatefulSeed {
  const _CursorHost(this.circuit, this.initial);

  final Circuit circuit;
  final CircuitCursor initial;

  @override
  State<_CursorHost> createState() => _CursorHostState();
}

class _CursorHostState extends State<_CursorHost> {
  late CircuitCursor _cursor;

  @override
  void initState() => _cursor = seed.initial;

  void advance(CircuitCursor cursor) => setState(() => _cursor = cursor);

  @override
  Seed build(TreeContext context) => InheritedSeed<InheritedCircuit>(
    value: InheritedCircuit(
      root: BeadPathKey(const ['tg-1', 'tgdog-s', 'tgdog-step-critic1']),
      beadIdByNodePath: _beadIds(),
      cursor: _cursor,
    ),
    child: CircuitScope(
      circuit: seed.circuit,
      cursor: _cursor,
      nodePath: 'tg-1',
    ),
  );
}

List<Branch> _all(Branch root) {
  final out = <Branch>[];
  void walk(Branch b) {
    out.add(b);
    b.visitChildren(walk);
  }

  walk(root);
  return out;
}

Branch _stepBranch(Branch root, String path) =>
    _all(root).singleWhere((branch) => branch.seed.key == ValueKey(path));

({
  TreeOwner owner,
  Branch root,
  RecordingCapabilityRegistry reg,
  _CursorHostState state,
})
_mount(_CursorHost host) {
  final reg = RecordingCapabilityRegistry(clock: _clock);
  final owner = TreeOwner();
  final root = owner.mountRoot(
    ProviderScope(
      child: InheritedSeed<CapabilityRegistry>(
        value: reg,
        child: InheritedSeed<SessionHandle>(
          value: const SessionHandle('tgdog-s'),
          child: host,
        ),
      ),
    ),
  );
  final branch =
      _all(root).firstWhere((b) => b.seed is _CursorHost) as StatefulBranch;
  return (
    owner: owner,
    root: root,
    reg: reg,
    state: branch.state as _CursorHostState,
  );
}

void main() {
  test('only the invalid lane fails; the three completed siblings keep their '
      'cursor and results', () async {
    final h = _driveLanes(
      outcomes: {
        'critic1': const Ok({'grade': 'A'}),
        'critic2': const Ok({'grade': 'B'}),
        'critic3': const Ok({'grade': 'F'}),
        'critic4': const Failed.invalidResult('verdict file is not valid JSON'),
      },
    );
    addTearDown(h.owner.dispose);
    await _pump();

    const completed = {'critic1': 'A', 'critic2': 'B', 'critic3': 'F'};
    for (final entry in completed.entries) {
      final lane = entry.key;
      final meta = _updateFor(h.fakes.runner, 'tgdog-step-$lane');
      expect(meta[MoleculeStepKeys.state], 'complete');
      expect(meta[MoleculeStepKeys.restartCount], '0');
      expect(meta.containsKey(MoleculeStepKeys.failureReason), isFalse);
      expect(
        meta[ResultKeys.keyFor('tg-1/$lane', ResultKeys.grade)],
        entry.value,
      );
    }

    final failed = _updateFor(h.fakes.runner, 'tgdog-step-critic4');
    expect(failed[MoleculeStepKeys.state], 'failed');
    expect(failed[MoleculeStepKeys.restartCount], '1');
    expect(
      failed[MoleculeStepKeys.cooldownUntil],
      _clock.add(const Duration(seconds: 1)).toIso8601String(),
    );
    expect(failed[MoleculeStepKeys.failureReason], contains('not valid JSON'));
    expect(h.fakes.runner.callsFor('create'), isEmpty);
  });

  test(
    'a critic that validly graded F is a COMPLETED verdict, not a failure',
    () async {
      final h = _driveLanes(
        outcomes: {
          for (final lane in _lanes)
            lane: const Ok({'grade': 'F', 'round': '1'}),
        },
      );
      addTearDown(h.owner.dispose);
      await _pump();

      for (final lane in _lanes) {
        final meta = _updateFor(h.fakes.runner, 'tgdog-step-$lane');
        expect(meta[MoleculeStepKeys.state], 'complete');
        expect(meta[ResultKeys.keyFor('tg-1/$lane', ResultKeys.grade)], 'F');
      }
      expect(h.fakes.runner.callsFor('create'), isEmpty);
      expect(h.flares.named(kHarnessThrottledFlare), isEmpty);
    },
  );

  test('an EXHAUSTED invalid-result lane parks at exactly one gate and writes '
      'no failed cursor', () async {
    final h = _driveLanes(
      outcomes: {
        'critic1': const Ok({'grade': 'A'}),
        'critic2': const Ok({'grade': 'A'}),
        'critic3': const Ok({'grade': 'A'}),
        'critic4': const Failed.invalidResult('verdict file is not valid JSON'),
      },
      restartCount: 2,
    );
    addTearDown(h.owner.dispose);
    await _pump();

    final gated = _updateFor(h.fakes.runner, 'tgdog-step-critic4');
    expect(gated[MoleculeStepKeys.state], 'gated');
    final creates = h.fakes.runner.callsFor('create');
    expect(creates, hasLength(1));
    expect(creates.single, containsAllInOrder(['--type', 'gate']));
    final gateMetadata = [
      for (var i = 0; i < h.fakes.runner.callsFor('update').length; i++)
        h.fakes.runner.metadataOfUpdate(i),
    ].singleWhere((metadata) => metadata.containsKey('reason'));
    expect(gateMetadata['reason'], contains('invalid_result'));
    expect(gateMetadata['reason'], contains('verdict file is not valid JSON'));
    for (final call in h.fakes.runner.calls) {
      expect(call.join(' '), isNot(contains('grid.step.state=failed')));
    }
  });

  test('a per-seat declaration tightens only the strict lane', () async {
    final h = _driveLanes(
      outcomes: {
        for (final lane in _lanes)
          lane: const Failed.invalidResult('verdict file is not valid JSON'),
      },
      paramsByLane: const {
        'critic1': {'seat': 'strict'},
        'critic2': {'seat': 'standard'},
      },
    );
    addTearDown(h.owner.dispose);
    await _pump();

    expect(
      _updateFor(h.fakes.runner, 'tgdog-step-critic1')[MoleculeStepKeys.state],
      'gated',
      reason: 'maxRestarts: 1 is spent by the first attempt',
    );
    final standard = _updateFor(h.fakes.runner, 'tgdog-step-critic2');
    expect(standard[MoleculeStepKeys.state], 'failed');
    expect(standard[MoleculeStepKeys.restartCount], '1');
  });

  test('a supervised restart re-keys ONLY the failed lane; the completed '
      'siblings keep their branch identity', () {
    final host = _CursorHost(_committee, {
      for (final lane in const ['critic1', 'critic2', 'critic3'])
        'tg-1/$lane': const NodeCursor(state: StepState.complete),
      'tg-1/critic4': const NodeCursor(state: StepState.running),
    });
    final m = _mount(host);
    addTearDown(m.owner.dispose);
    expect(m.reg.events, ['START critic(tgdog-s/tg-1/critic4)']);
    final ids = {
      for (final lane in _lanes)
        lane: _stepBranch(m.root, 'tg-1/$lane').branchId,
    };

    m.reg.events.clear();
    m.state.advance({
      for (final lane in const ['critic1', 'critic2', 'critic3'])
        'tg-1/$lane': const NodeCursor(state: StepState.complete),
      'tg-1/critic4': const NodeCursor(
        state: StepState.failed,
        restartCount: 1,
      ),
    });
    m.owner.flush();

    expect(
      m.reg.events,
      unorderedEquals([
        'STOP critic(tgdog-s/tg-1/critic4)',
        'START critic(tgdog-s/tg-1/critic4)',
      ]),
      reason: 'only the failed lane re-keys (one_for_one)',
    );
    for (final lane in _lanes) {
      expect(_stepBranch(m.root, 'tg-1/$lane').branchId, ids[lane]);
    }
  });
}
