@Tags(['integration'])
library;

import 'package:grid_controller/grid_controller.dart';
import 'package:grid_reconciler/grid_reconciler.dart';
import 'package:test/test.dart';

import '../actuator/support/recording_bd_runner.dart';
import '../gates/support/fake_process_runner.dart';
import 'support/runtime_fakes.dart';

/// Integration (tag `integration`): compose the FULL runtime over the REAL
/// [BdActuator] (over a [RecordingBdRunner]) — not the recording-fake actuator —
/// so the load-bearing bd CALL SEQUENCE and final committed metadata the
/// orchestration drives are validated end-to-end through reduce→gate→actuate,
/// not just in the isolated [BdActuator] unit.
///
/// The lifecycle-fake test ([runtime_lifecycle_integration_test]) asserts the
/// action TYPES (IterateAction/ApprovedAction) the runtime selects; this test
/// asserts the verbs the actuator actually emits for those actions, proving the
/// commit-point ordering (ADR-0003 invariant 2) survives the whole runtime path.
void main() {
  group('runtime over the real BdActuator — bd call sequence (invariant 2)', () {
    test(
      'a wisp-closed → gate PASS → terminal approved cycle emits '
      'burn(delete) → terminal updates → close → last_processed_wisp LAST',
      () async {
        const root = 'A';
        // active, iteration at MAX so a gate PASS terminates (approved).
        final rootMeta = <String, dynamic>{
          ConvergenceFields.state: 'active',
          ConvergenceFields.iteration: '1',
          ConvergenceFields.maxIterations: '1',
          ConvergenceFields.formula: 'f',
          ConvergenceFields.gateMode: 'condition',
          ConvergenceFields.gateCondition: '/gate/check.sh',
          ConvergenceFields.gateTimeout: '60s',
          ConvergenceFields.gateTimeoutAction: 'iterate',
          ConvergenceFields.activeWisp: '$root-w1',
        };
        final closedWisp = wispBead(
          '$root-w1',
          key: idempotencyKey(root, 1),
          status: BeadStatus.closed,
          createdAt: fakeClock.subtract(const Duration(minutes: 10)),
          closedAt: fakeClock,
        );
        final source = FakeConvergenceSource(
          snapWith(
            roots: [convergenceBead(root, metadata: rootMeta)],
            children: {
              root: [closedWisp],
            },
          ),
        );

        // The REAL actuator over a recording bd runner + a probe that misses
        // (no pre-existing wisp). A terminal approve pours nothing, so the probe
        // is never consulted; the burn/close/commit sequence is the witness.
        final runner = RecordingBdRunner();
        final actuator = BdActuator(
          BdCliService(runner),
          (_, __) async => null,
        );

        // The real Track-D gate over a fake process: exit 0 → PASS.
        final process = FakeProcessRunner()
          ..stub('/gate/check.sh', FakeRun.pass());
        final gate = GateRunnerProcessGate(
          runner: GateRunnerService(
            processRunner: process,
            ambientEnvironment: const {},
            lookPathDir: (_) => null,
            tempDir: '/tmp',
          ),
        );

        final runtime = ReconcilerRuntime(
          source: source,
          actuator: actuator,
          gateEvaluator: gate,
          ownership: const OwnsEverything(),
          runRecoveryAtStartup: false,
        );
        await runtime.start();

        source.emit(beadClosedEvent(closedWisp, closedWisp));
        await runtime.idle();
        await runtime.dispose();

        // The gate ran exactly once.
        expect(
          process.calls.length,
          1,
          reason: 'one gate eval for the closure',
        );

        // The metadata-write key order — last_processed_wisp is the FINAL write
        // (the commit point), and it lands AFTER the root close.
        final keys = [
          for (final w in runner.metadataWrites) w.metadata.keys.single,
        ];
        expect(
          keys,
          contains(ConvergenceFields.lastProcessedWisp),
          reason: 'the terminal cycle committed last_processed_wisp',
        );
        expect(
          keys.last,
          ConvergenceFields.lastProcessedWisp,
          reason: 'last_processed_wisp is the commit point — written LAST',
        );
        expect(
          keys,
          containsAllInOrder([
            ConvergenceFields.terminalReason,
            ConvergenceFields.state,
            ConvergenceFields.lastProcessedWisp,
          ]),
          reason: 'terminal metadata precedes the commit',
        );

        // The close lands between the terminal writes and the commit write.
        final closeCall = runner.calls.indexWhere((c) => c.first == 'close');
        expect(
          closeCall,
          greaterThanOrEqualTo(0),
          reason: 'the root was closed',
        );
        final lpwCall = runner.calls.lastIndexWhere(
          (c) =>
              c.isNotEmpty &&
              c.first == 'update' &&
              c.contains('--metadata') &&
              c[c.indexOf('--metadata') + 1].contains(
                ConvergenceFields.lastProcessedWisp,
              ),
        );
        expect(
          closeCall,
          lessThan(lpwCall),
          reason: 'last_processed_wisp is committed AFTER the close',
        );

        // The final committed metadata: terminated + the commit marker.
        final commitWrite = runner.metadataWrites.last;
        expect(
          commitWrite.metadata[ConvergenceFields.lastProcessedWisp],
          '$root-w1',
        );
        final stateWrite = runner.metadataWrites.firstWhere(
          (w) => w.metadata.containsKey(ConvergenceFields.state),
        );
        expect(
          stateWrite.metadata[ConvergenceFields.state],
          ConvergenceState.terminated.wire,
        );
      },
    );
  });

  group('runtime — gate TIMEOUT result carries through reduce→actuate', () {
    // A gate that TIMES OUT is a normal GateOutcome.timeout result (not a
    // gate-runner error → A25 live-error path). The runtime must reduce the
    // timeout + the configured timeout_action into the right transition and
    // actuate it. Covered at the reducer + gate-runner units; this drives the
    // distinction end-to-end through the runtime, which the lifecycle fixture
    // (gateTimeoutAction:'iterate') never triggers.

    /// Drives one closure whose gate deadlines, with [timeoutAction] configured,
    /// and returns the recorded actions.
    Future<List<ReconcilerAction>> driveTimeout(String timeoutAction) async {
      const root = 'T';
      final rootMeta = <String, dynamic>{
        ConvergenceFields.state: 'active',
        ConvergenceFields.iteration: '1',
        ConvergenceFields.maxIterations: '5',
        ConvergenceFields.formula: 'f',
        ConvergenceFields.gateMode: 'condition',
        ConvergenceFields.gateCondition: '/gate/slow.sh',
        // A short per-gate timeout; the fake fires the deadline directly.
        ConvergenceFields.gateTimeout: '100ms',
        ConvergenceFields.gateTimeoutAction: timeoutAction,
        ConvergenceFields.activeWisp: '$root-w1',
      };
      final closedWisp = wispBead(
        '$root-w1',
        key: idempotencyKey(root, 1),
        status: BeadStatus.closed,
        createdAt: fakeClock.subtract(const Duration(minutes: 10)),
        closedAt: fakeClock,
      );
      final source = FakeConvergenceSource(
        snapWith(
          roots: [convergenceBead(root, metadata: rootMeta)],
          children: {
            root: [closedWisp],
          },
        ),
      );
      // The gate deadlines → GateOutcome.timeout (NOT a launch/error failure).
      final process = FakeProcessRunner()
        ..stub('/gate/slow.sh', FakeRun.deadline());
      final gate = GateRunnerProcessGate(
        runner: GateRunnerService(
          processRunner: process,
          ambientEnvironment: const {},
          lookPathDir: (_) => null,
          tempDir: '/tmp',
        ),
      );
      final actuator = RecordingActuator(
        nextResult: const ActuationResult(pouredWispId: '$root-w2-spec'),
      );
      final runtime = ReconcilerRuntime(
        source: source,
        actuator: actuator,
        gateEvaluator: gate,
        ownership: const OwnsEverything(),
        runRecoveryAtStartup: false,
        onError: (e, _) =>
            fail('a timeout must NOT surface as a live error: $e'),
      );
      await runtime.start();
      source.emit(beadClosedEvent(closedWisp, closedWisp));
      await runtime.idle();
      await runtime.dispose();
      // No cycle failed (the timeout is a normal transition, not A25).
      expect(
        runtime.outcomes.any((o) => o.isFailure),
        isFalse,
        reason: 'a timeout is a transition, not a deferred live error',
      );
      return actuator.actions;
    }

    test('timeout + action=iterate → the runtime actuates an iterate (not a '
        'failed cycle)', () async {
      final actions = await driveTimeout('iterate');
      expect(
        actions.whereType<IterateAction>(),
        isNotEmpty,
        reason: 'timeout+iterate iterates the loop',
      );
      expect(actions.whereType<ApprovedAction>(), isEmpty);
      expect(actions.whereType<NoConvergenceAction>(), isEmpty);
    });

    test('timeout + action=terminate → the runtime actuates a terminal '
        '(no_convergence)', () async {
      final actions = await driveTimeout('terminate');
      expect(
        actions.whereType<NoConvergenceAction>(),
        isNotEmpty,
        reason: 'timeout+terminate ends the loop as no_convergence',
      );
      expect(actions.whereType<IterateAction>(), isEmpty);
    });

    test('timeout + action=manual → the runtime actuates waiting_manual'
        '(timeout)', () async {
      final actions = await driveTimeout('manual');
      final manual = actions.whereType<WaitingManualAction>().toList();
      expect(
        manual,
        isNotEmpty,
        reason: 'timeout+manual holds for the operator',
      );
      expect(
        manual.first.reason,
        WaitingReason.timeout,
        reason: 'the hold reason is the timeout',
      );
      expect(actions.whereType<IterateAction>(), isEmpty);
    });
  });
}
