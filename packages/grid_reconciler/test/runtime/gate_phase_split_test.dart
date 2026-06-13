import 'package:grid_reconciler/grid_reconciler.dart';
import 'package:test/test.dart';

import '../gates/support/fake_process_runner.dart';
import 'support/runtime_fakes.dart';

/// The gate phase-split handoff end-to-end (ADR-0000 A22):
/// reduce → evaluateGate → GateRunnerService → gateEvaluated → actuate, driven
/// through the REAL [GateRunnerService] over a [FakeProcessRunner] so the whole
/// chain (Track B → Track D → Track B → Track E) is exercised.
void main() {
  group('ReconcilerRuntime — gate phase split', () {
    late FakeConvergenceSource source;
    late RecordingActuator actuator;
    late FakeProcessRunner process;
    late GateRunnerProcessGate gate;

    setUp(() {
      process = FakeProcessRunner();
      gate = GateRunnerProcessGate(
        runner: GateRunnerService(
          processRunner: process,
          ambientEnvironment: const {},
          lookPathDir: (_) => null,
          tempDir: '/tmp',
        ),
      );
    });

    ReconcilerRuntime build() => ReconcilerRuntime(
      source: source,
      actuator: actuator,
      gateEvaluator: gate,
      ownership: const OwnsEverything(),
      runRecoveryAtStartup: false,
    );

    test('gate PASS → fresh evaluation → terminal approved', () async {
      final loop = activeLoop(rootId: 'P', activeWispId: 'P-w1');
      source = FakeConvergenceSource(
        snapWith(
          roots: [loop.root],
          children: {
            'P': [loop.closedWisp],
          },
        ),
      );
      actuator = RecordingActuator();
      // The gate script exits 0 → pass → terminal approved.
      process.stub('/gate/check.sh', FakeRun.exited(0));

      final runtime = build();
      await runtime.start();
      source.emit(beadClosedEvent(loop.closedWisp, loop.closedWisp));
      await runtime.idle();
      await runtime.dispose();

      // The chain ran: the gate subprocess was invoked exactly once...
      expect(process.calls.length, 1);
      expect(process.calls.single.executable, '/gate/check.sh');
      // ...and phase 2 produced a terminal `approved` transition.
      final approvedActions = actuator.actions.whereType<ApprovedAction>();
      expect(approvedActions, isNotEmpty);
      expect(approvedActions.first.path, TerminalPath.handlerWispClosed);
      // The cycle trace recorded the gate-eval phase + the actuated terminal.
      expect(
        runtime.outcomes.map((o) => o.status),
        containsAll([CycleStatus.gateEvaluated, CycleStatus.actuated]),
      );
    });

    test('gate FAIL below max → fresh evaluation → iterate', () async {
      final loop = activeLoop(rootId: 'F', activeWispId: 'F-w1');
      source = FakeConvergenceSource(
        snapWith(
          roots: [loop.root],
          children: {
            'F': [loop.closedWisp],
          },
        ),
      );
      actuator = RecordingActuator(
        // Phase 1 pours the speculative wisp; the actuator reports its id so
        // phase 2 adopts it (the in-list dataflow across the phase boundary).
        nextResult: const ActuationResult(pouredWispId: 'F-w2-spec'),
      );
      process.stub('/gate/check.sh', FakeRun.exited(1));

      final runtime = build();
      await runtime.start();
      source.emit(beadClosedEvent(loop.closedWisp, loop.closedWisp));
      await runtime.idle();
      await runtime.dispose();

      expect(process.calls.length, 1);
      final iterates = actuator.actions.whereType<IterateAction>();
      expect(iterates, isNotEmpty);
      expect(iterates.first.path, IteratePath.wispClosed);
      // Phase 1 emitted the speculative pour + the gate handoff.
      expect(actuator.actions.whereType<PourSpeculativeAction>(), isNotEmpty);
      expect(
        actuator.actions.whereType<PersistGateOutcomeAction>(),
        isNotEmpty,
      );
    });
  });
}
