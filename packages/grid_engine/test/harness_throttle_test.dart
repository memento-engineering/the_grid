// A harness usage-limit exit is infra, not work.
//
// These cases drive CapabilityHost through the recording bd chokepoint and
// assert on its durable writes and trajectory records.
// ignore_for_file: invalid_use_of_protected_member
import 'dart:async';

import 'package:genesis_tree/genesis_tree.dart';
import 'package:grid_engine/grid_engine.dart';
import 'package:grid_engine/src/molecule/bead_path_key.dart';
import 'package:grid_engine/src/molecule/inherited_circuit.dart';
import 'package:grid_engine/testing.dart';
import 'package:grid_runtime/grid_runtime.dart';
import 'package:test/test.dart';

const _stepBeadId = 'tgdog-step1';
const _nodePath = 'tg-1/agent';
const _providerName = 'tgdog-s/$_nodePath';
const _usageLine = 'Claude usage limit reached; resets at 09:00Z';
const _artifactless = 'unresolved: declared completion artifact is not durable';
final _clock = DateTime.utc(2026);

const _circuit = Circuit(
  id: 'code',
  terminalStepId: 'agent',
  steps: [CapabilityStep(stepId: 'agent', capabilityId: 'agent')],
);

final class _Sink implements TrajectoryRecordSink {
  final List<TrajectoryRecord> records = [];

  @override
  bool get accepting => true;

  @override
  void enqueue(
    TrajectoryRecord record, {
    DateTime? occurredAt,
    String? seat,
    TrajectoryProvenance provenance = TrajectoryProvenance.observed,
    String? provenanceBasis,
  }) => records.add(record);

  Map<String, Object?> only(String recordType) {
    final all = [
      for (final record in records)
        if (record.recordType == recordType)
          {...record.correlationToJson(), ...record.payloadToJson()},
    ];
    expect(all, hasLength(1), reason: 'exactly one $recordType');
    return all.single;
  }

  Map<String, Object?> last(String recordType) {
    final record = records.lastWhere(
      (candidate) => candidate.recordType == recordType,
    );
    return {...record.correlationToJson(), ...record.payloadToJson()};
  }
}

class _FixedCap extends ServiceCapability {
  const _FixedCap(this.outcome);

  final StepOutcome outcome;

  @override
  Future<StepOutcome> run(TreeContext context, StepArgs args) async => outcome;
}

Future<void> _pump() async {
  for (var i = 0; i < 8; i++) {
    await Future<void>.delayed(Duration.zero);
  }
}

typedef _Harness = ({
  TreeOwner owner,
  Fakes fakes,
  _Sink sink,
  RecordingExplorationTransport flares,
});

_Harness _drive(
  StepOutcome outcome, {
  int restartCount = 0,
  String? priorReason,
  DateTime Function()? nowFn,
  String exitOutput = _usageLine,
}) {
  final fakes = buildFakes();
  if (exitOutput.isNotEmpty) {
    fakes.provider.stageExitOutput(_providerName, exitOutput);
  }
  final sink = _Sink();
  final flares = RecordingExplorationTransport();
  final owner = TreeOwner();
  final mount = StepMount(
    step: const CapabilityStep(stepId: 'agent', capabilityId: 'agent'),
    nodePath: _nodePath,
    circuit: _circuit,
    circuitPath: 'tg-1',
    session: const SessionHandle('tgdog-s'),
    node: NodeCursor(restartCount: restartCount, failureReason: priorReason),
    key: ValueKey('$_nodePath#$restartCount.0'),
    maxRestarts: 3,
  );
  owner.mountRoot(
    InheritedSeed<StationServices>(
      value: fakes.ctx,
      child: InheritedSeed<CapabilityRegistry>(
        value: nowFn == null
            ? RecordingCapabilityRegistry(clock: _clock)
            : RecordingCapabilityRegistry(nowFn: nowFn),
        child: InheritedSeed<TrajectoryRecorderScope>(
          value: TrajectoryRecorderScope(
            StationTrajectoryRecorder(
              sink: sink,
              seatPrefixes: const {'tg', 'tgdog'},
            ),
          ),
          child: InheritedSeed<ServiceBundle>(
            value: ServiceBundle(transport: flares),
            child: InheritedSeed<Workspace>(
              value: testWorkspace('tg-1'),
              child: InheritedSeed<InheritedCircuit>(
                value: InheritedCircuit(
                  root: BeadPathKey(const ['tg-1', 'tgdog-s', _stepBeadId]),
                  beadIdByNodePath: const {_nodePath: _stepBeadId},
                  cursor: const {},
                ),
                child: CapabilityHost(
                  capability: _FixedCap(outcome),
                  mount: mount,
                ),
              ),
            ),
          ),
        ),
      ),
    ),
  );
  return (owner: owner, fakes: fakes, sink: sink, flares: flares);
}

void main() {
  group('the pure classification', () {
    test('a non-result under the floor is silence; nothing else is', () {
      const under = Duration(seconds: 9);
      const over = Duration(seconds: 31);
      expect(isHarnessSilence(nonResult: true, ranFor: under), isTrue);
      expect(isHarnessSilence(nonResult: true, ranFor: over), isFalse);
      expect(isHarnessSilence(nonResult: false, ranFor: under), isFalse);
      expect(isHarnessSilence(nonResult: true, ranFor: null), isFalse);
      expect(
        isHarnessSilence(nonResult: true, ranFor: kHarnessSilenceFloor),
        isFalse,
      );
    });

    test('the window instant chains through the persisted reason', () {
      final first = harnessThrottleReason(
        since: DateTime.utc(2026, 9, 3, 5, 43),
        silentExits: 1,
        exitOutputHead: _usageLine,
        underlying: _artifactless,
      );
      expect(first, startsWith(kHarnessThrottleMarker));
      expect(first, contains(_usageLine));
      expect(
        harnessThrottleSince(priorReason: first, now: DateTime.utc(2026, 9, 4)),
        DateTime.utc(2026, 9, 3, 5, 43),
      );
      expect(
        harnessThrottleSince(
          priorReason: 'exit 1',
          now: DateTime.utc(2026, 9, 4),
        ),
        DateTime.utc(2026, 9, 4),
      );
    });

    test('a reason without captured output names the underlying failure', () {
      expect(
        harnessThrottleReason(
          since: DateTime.utc(2026),
          silentExits: 2,
          exitOutputHead: '',
          underlying: _artifactless,
        ),
        contains(_artifactless),
      );
    });

    test('the throttle backoff lands at +5, +15, and +30 minutes', () {
      expect(Backoff.harnessThrottle.delayFor(1), const Duration(minutes: 5));
      expect(Backoff.harnessThrottle.delayFor(2), const Duration(minutes: 15));
      expect(Backoff.harnessThrottle.delayFor(3), const Duration(minutes: 30));
      expect(Backoff.harnessThrottle.delayFor(9), const Duration(minutes: 30));
    });

    test('the gate reason names the session, count, and instant', () {
      final gate = harnessThrottleGateReason(
        sessionId: 'tranquility-ltkod1',
        nodePath: _nodePath,
        since: DateTime.utc(2026, 9, 3, 5, 43),
        silentExits: 3,
        exitOutputHead: _usageLine,
      );
      expect(gate, contains('tranquility-ltkod1'));
      expect(gate, contains('3 model steps'));
      expect(gate, contains('2026-09-03T05:43:00.000Z'));
      expect(gate, contains(_usageLine));
    });
  });

  group('a silent exit is INFRA, retried on the throttle schedule', () {
    test('the first silent exit records infra, backs off 5 min, and does NOT '
        'gate the round', () async {
      final h = _drive(const Failed.nonResult(_artifactless));
      addTearDown(() {
        h.owner.dispose();
        unawaited(h.fakes.provider.close());
      });
      await _pump();

      final meta = h.fakes.runner.metadataOfUpdate(0);
      expect(meta[MoleculeStepKeys.state], 'failed');
      expect(meta[MoleculeStepKeys.restartCount], '1');
      expect(
        meta[MoleculeStepKeys.cooldownUntil],
        _clock.add(const Duration(minutes: 5)).toIso8601String(),
      );
      expect(meta[MoleculeStepKeys.failureReason], contains(_usageLine));
      expect(
        meta[MoleculeStepKeys.failureReason],
        startsWith(kHarnessThrottleMarker),
      );

      final step = h.sink.only('step.transition');
      expect(step['failure_class'], 'infra');
      expect(step['incarnation'], 1);
      expect(step['restart_budget'], 2);
      expect(h.fakes.runner.callsFor('create'), isEmpty);
    });

    test('the flare carries the session, step, and captured head', () async {
      final h = _drive(const Failed.nonResult(_artifactless));
      addTearDown(() {
        h.owner.dispose();
        unawaited(h.fakes.provider.close());
      });
      await _pump();

      final flare = h.flares.named(kHarnessThrottledFlare).single;
      expect(flare.data['sessionId'], 'tgdog-s');
      expect(flare.data['nodePath'], _nodePath);
      expect(flare.data['exitOutput'], _usageLine);
      expect(flare.data['silentExits'], '1');
      expect(
        h.fakes.runner.metadataOfUpdate(0)[MoleculeStepKeys.failureReason],
        contains(flare.data['exitOutput']!),
      );
    });

    test(
      'the exhausted budget PARKS at one type=gate bead naming the throttle, '
      'and writes no failed cursor',
      () async {
        final prior = harnessThrottleReason(
          since: DateTime.utc(2026, 9, 3, 5, 43),
          silentExits: 2,
          exitOutputHead: _usageLine,
          underlying: _artifactless,
        );
        final h = _drive(
          const Failed.nonResult(_artifactless),
          restartCount: 2,
          priorReason: prior,
        );
        addTearDown(() {
          h.owner.dispose();
          unawaited(h.fakes.provider.close());
        });
        await _pump();

        final meta = h.fakes.runner.metadataOfUpdate(0);
        expect(meta[MoleculeStepKeys.state], 'gated');
        final creates = h.fakes.runner.callsFor('create');
        expect(creates, hasLength(1));
        expect(creates.single, containsAllInOrder(['--type', 'gate']));
        final gate = h.fakes.runner.metadataOfUpdate(1);
        expect(gate['reason'], contains('harness throttled'));
        expect(gate['reason'], contains('tgdog-s'));
        expect(gate['reason'], contains('3 model steps'));
        expect(gate['reason'], contains('2026-09-03T05:43:00.000Z'));
        for (final call in h.fakes.runner.calls) {
          expect(call.join(' '), isNot(contains('grid.step.state=failed')));
        }
      },
    );
  });

  group('CONTROL — the graded path is untouched', () {
    test('a critic that graded F completes without a throttle flare', () async {
      final h = _drive(const Ok({'grade': 'F', 'round': '1'}));
      addTearDown(() {
        h.owner.dispose();
        unawaited(h.fakes.provider.close());
      });
      await _pump();

      final meta = h.fakes.runner.metadataOfUpdate(0);
      expect(meta[MoleculeStepKeys.state], 'complete');
      expect(h.flares.named(kHarnessThrottledFlare), isEmpty);
      expect(h.sink.last('step.transition')['failure_class'], isNull);
    });

    test('a work failure keeps its class and standard backoff', () async {
      final h = _drive(const Failed('exit 1'));
      addTearDown(() {
        h.owner.dispose();
        unawaited(h.fakes.provider.close());
      });
      await _pump();

      final meta = h.fakes.runner.metadataOfUpdate(0);
      expect(meta[MoleculeStepKeys.failureReason], 'exit 1');
      expect(
        meta[MoleculeStepKeys.cooldownUntil],
        _clock.add(const Duration(seconds: 1)).toIso8601String(),
      );
      expect(h.sink.only('step.transition')['failure_class'], 'work');
      expect(h.flares.named(kHarnessThrottledFlare), isEmpty);
    });

    test('a long non-result remains work', () async {
      final h = _drive(
        const Failed.nonResult(_artifactless),
        nowFn: advancingClock(from: _clock, step: const Duration(minutes: 1)),
      );
      addTearDown(() {
        h.owner.dispose();
        unawaited(h.fakes.provider.close());
      });
      await _pump();

      expect(h.sink.only('step.transition')['failure_class'], 'work');
      expect(h.flares.named(kHarnessThrottledFlare), isEmpty);
      expect(
        h.fakes.runner.metadataOfUpdate(0)[MoleculeStepKeys.failureReason],
        _artifactless,
      );
    });
  });
}
