// A resident boot re-evaluates durable failure exhaustion through the same
// leaf-host policy path as a live failure. Pure-Dart: fakes, no live store.
import 'dart:async';

import 'package:beads_dart/beads_dart.dart';
import 'package:genesis_tree/genesis_tree.dart';
import 'package:grid_engine/grid_engine.dart';
import 'package:grid_engine/testing.dart';
import 'package:test/test.dart';

final _now = DateTime.utc(2026, 9, 22);
final _elapsedCooldown = _now.subtract(const Duration(minutes: 1));

const _circuit = Circuit(
  id: 'code',
  terminalStepId: 'agent',
  steps: [CapabilityStep(stepId: 'agent', capabilityId: 'agent')],
);

final class _StepRow implements StepCursorView {
  const _StepRow({required this.restartBudget, required this.incarnation});

  @override
  final int restartBudget;
  @override
  final int incarnation;
  @override
  String get sessionId => 'tgdog-s';
  @override
  int get round => 0;
  @override
  String get stepPath => 'tg-1/agent';
  @override
  int get stepRound => 0;
  @override
  String get stepState => 'failed';
  @override
  String get failureClass => 'infra';
  @override
  String get attemptId => 'attempt-$incarnation';
  @override
  int? get supersededByStepRound => null;
  @override
  DateTime get cooldownUntil => _elapsedCooldown;
  @override
  DateTime get startedAt => _now.subtract(const Duration(minutes: 10));
  @override
  DateTime? get readyAt => null;
  @override
  DateTime? get completedAt => null;
  @override
  int get lastSeq => 89;
}

final class _RecordingAgent extends ServiceCapability {
  _RecordingAgent(this.events);

  final List<String> events;
  final Completer<StepOutcome> _outcome = Completer<StepOutcome>();

  @override
  Future<StepOutcome> run(TreeContext context, StepArgs args) {
    final session = context.read<SessionHandle>();
    events.add('START agent(${session!.sessionId}/${args.nodePath})');
    return _outcome.future;
  }
}

Bead _stepBead({required int restartCount}) => Bead(
  id: 'tgdog-step-agent',
  issueType: GridIssueTypes.step,
  metadata: {
    'rig': stateSubstation,
    MoleculeStepKeys.stepId: 'agent',
    MoleculeStepKeys.capability: 'agent',
    MoleculeStepKeys.kind: StepKind.job.name,
    MoleculeStepKeys.path: 'tg-1/agent',
    MoleculeStepKeys.session: 'tgdog-s',
    MoleculeStepKeys.state: StepState.failed.name,
    MoleculeStepKeys.restartCount: '$restartCount',
    MoleculeStepKeys.cooldownUntil: _elapsedCooldown.toIso8601String(),
    MoleculeStepKeys.failureReason:
        'harness-throttled since 2026-09-21T23:00:00.000Z after '
        '$restartCount silent exit(s)',
  },
);

SessionProjection _session({required int restartBudget}) {
  final restartCount = _circuit.maxRestarts - restartBudget;
  return SessionProjection(
    workBeadId: 'tg-1',
    sessionId: 'tgdog-s',
    isMolecule: true,
    moleculeBeads: [_stepBead(restartCount: restartCount)],
    trajStepViews: {
      'tg-1/agent': _StepRow(
        restartBudget: restartBudget,
        incarnation: restartCount,
      ),
    },
  );
}

({TreeOwner owner, Fakes fakes, List<String> events}) _mount({
  required int restartBudget,
}) {
  final fakes = buildFakes(createdId: 'tgdog-gate');
  final events = <String>[];
  final projection = _session(restartBudget: restartBudget);
  final work = bead('tg-1');
  final snapshot = JoinedSnapshot(
    graph: GraphSnapshot.fromParts(
      beads: [work],
      dependencies: const [],
      readyIds: {'tg-1'},
      capturedAt: _now,
    ),
    sessionsByWorkBead: {'tg-1': projection},
  );
  final registry = DefaultCapabilityRegistry(
    capabilities: {'agent': _RecordingAgent(events)},
    circuits: const {'code': _circuit},
    clock: () => _now,
  );
  final owner = TreeOwner();
  owner.mountRoot(
    ProviderScope(
      child: InheritedSeed<JoinedSnapshot>(
        value: snapshot,
        child: InheritedSeed<StationServices>(
          value: fakes.ctx,
          child: InheritedSeed<CapabilityRegistry>(
            value: registry,
            child: InheritedSeed<ServiceBundle>(
              value: const ServiceBundle(),
              child: SessionScope(
                bead: work,
                circuit: _circuit,
                existingSession: projection,
              ),
            ),
          ),
        ),
      ),
    ),
  );
  return (owner: owner, fakes: fakes, events: events);
}

Future<void> _drain() async {
  for (var i = 0; i < 12; i++) {
    await Future<void>.delayed(Duration.zero);
  }
}

Iterable<List<String>> _gateCreates(RecordingBdRunner runner) => runner
    .callsFor('create')
    .where((call) => call.contains('--type') && call.contains('gate'));

Map<String, dynamic> _gateMetadata(RecordingBdRunner runner) {
  for (var index = 0; index < runner.workUpdates.length; index++) {
    final call = runner.workUpdates[index];
    if (call.length > 1 && call[1] == 'tgdog-gate') {
      return runner.metadataOfUpdate(index);
    }
  }
  fail('no gate metadata update was recorded');
}

void main() {
  test(
    'adopted exhausted infra step parks at a gate within one tick',
    () async {
      final mounted = _mount(restartBudget: 0);
      addTearDown(() {
        mounted.owner.dispose();
        mounted.fakes.ctx.dispose();
        unawaited(mounted.fakes.provider.close());
      });

      await _drain();

      expect(_gateCreates(mounted.fakes.runner), hasLength(1));
      final metadata = _gateMetadata(mounted.fakes.runner);
      expect(metadata['node'], 'tg-1/agent');
      expect(metadata['reason'], contains('tg-1/agent'));
      expect(metadata['reason'], contains('failure_class=infra'));
      expect(metadata['reason'], contains('restart_budget=0 (spent)'));
      expect(mounted.events, isEmpty);
      expect(
        mounted.fakes.runner.callsFor('close'),
        isEmpty,
        reason: 'the withheld breaker must not double-fire beside the gate',
      );
    },
  );

  test('adopted infra step with restart budget remaining re-drives', () async {
    final mounted = _mount(restartBudget: 1);
    addTearDown(() {
      mounted.owner.dispose();
      mounted.fakes.ctx.dispose();
      unawaited(mounted.fakes.provider.close());
    });

    await _drain();

    expect(mounted.events, ['START agent(tgdog-s/tg-1/agent)']);
    expect(_gateCreates(mounted.fakes.runner), isEmpty);
  });
}
