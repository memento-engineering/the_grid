@Tags(['integration'])
library;

import 'package:grid_controller/grid_controller.dart';
import 'package:grid_reconciler/grid_reconciler.dart';
import 'package:test/test.dart';

import '../gates/support/fake_process_runner.dart';
import 'support/runtime_fakes.dart';

/// Integration (tag `integration`): drive a synthetic convergence loop through a
/// full lifecycle end-to-end with a hermetic gate surface (the real
/// [GateRunnerService] over a [FakeProcessRunner]) and a recording actuator,
/// asserting the end-to-end transition sequence — iterate (gate fail) → iterate
/// (gate fail) → terminate (gate pass) — and the operator approve/iterate/stop
/// verbs over the same machine.
///
/// This is a single mutable in-memory "store" (the snapshot + the actuator's
/// recorded writes) advanced by hand between events, modelling how the real
/// controller re-captures the snapshot after each bd-mediated transition.
void main() {
  group('full convergence lifecycle (hermetic gate)', () {
    test('pour → close wisp → gate fail → iterate → gate fail → iterate → '
        'gate pass → terminate', () async {
      const root = 'L';
      // The mutable store: the root bead + its children, re-snapshotted after
      // each transition the actuator applies.
      Bead rootBead(Map<String, dynamic> meta) =>
          convergenceBead(root, metadata: meta);

      // Baseline: active, iter 1, max 3, condition gate, active_wisp = iter-1.
      final baseMeta = <String, dynamic>{
        ConvergenceFields.state: 'active',
        ConvergenceFields.iteration: '1',
        ConvergenceFields.maxIterations: '3',
        ConvergenceFields.formula: 'lifecycle-formula',
        ConvergenceFields.gateMode: 'condition',
        ConvergenceFields.gateCondition: '/gate/check.sh',
        ConvergenceFields.gateTimeout: '60s',
        ConvergenceFields.gateTimeoutAction: 'iterate',
        ConvergenceFields.activeWisp: '$root-w1',
      };

      Bead closedWisp(int iter) => wispBead(
        '$root-w$iter',
        key: idempotencyKey(root, iter),
        status: BeadStatus.closed,
        createdAt: fakeClock.subtract(const Duration(minutes: 10)),
        closedAt: fakeClock,
      );

      // The store starts with iter-1 closed.
      final source = FakeConvergenceSource(
        snapWith(
          roots: [rootBead(baseMeta)],
          children: {
            root: [closedWisp(1)],
          },
        ),
      );
      final actuator = RecordingActuator(
        nextResult: const ActuationResult(pouredWispId: '$root-w2-spec'),
      );
      final process = FakeProcessRunner();
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

      // --- Iteration 1 closes → gate FAILS → iterate to iter 2 ---
      process.stub('/gate/check.sh', FakeRun.exited(1));
      source.emit(beadClosedEvent(closedWisp(1), closedWisp(1)));
      await runtime.idle();

      // Advance the store: iter-1 processed, now active on iter-2.
      source.setSnapshot(
        snapWith(
          roots: [
            rootBead({
              ...baseMeta,
              ConvergenceFields.activeWisp: '$root-w2',
              ConvergenceFields.lastProcessedWisp: '$root-w1',
              ConvergenceFields.iteration: '1',
            }),
          ],
          children: {
            root: [
              closedWisp(1),
              wispBead(
                '$root-w2',
                key: idempotencyKey(root, 2),
                status: BeadStatus.open,
              ),
            ],
          },
        ),
      );

      // --- Iteration 2 closes → gate FAILS → iterate to iter 3 ---
      process.stub('/gate/check.sh', FakeRun.exited(1));
      actuator.nextResult = const ActuationResult(
        pouredWispId: '$root-w3-spec',
      );
      source.emit(beadClosedEvent(closedWisp(2), closedWisp(2)));
      await runtime.idle();

      // Advance: iter-2 processed, active on iter-3 (== max).
      source.setSnapshot(
        snapWith(
          roots: [
            rootBead({
              ...baseMeta,
              ConvergenceFields.activeWisp: '$root-w3',
              ConvergenceFields.lastProcessedWisp: '$root-w2',
            }),
          ],
          children: {
            root: [
              closedWisp(1),
              closedWisp(2),
              wispBead(
                '$root-w3',
                key: idempotencyKey(root, 3),
                status: BeadStatus.open,
              ),
            ],
          },
        ),
      );

      // --- Iteration 3 closes → gate PASSES → terminate (approved) ---
      process.stub('/gate/check.sh', FakeRun.exited(0));
      source.emit(beadClosedEvent(closedWisp(3), closedWisp(3)));
      await runtime.idle();
      await runtime.dispose();

      // The end-to-end transition sequence: two iterates then a terminal
      // approved (gate pass).
      final iterates = actuator.actions.whereType<IterateAction>().toList();
      final approved = actuator.actions.whereType<ApprovedAction>().toList();
      expect(
        iterates.length,
        2,
        reason: 'iter-1 fail → iterate, iter-2 fail → iterate',
      );
      expect(approved.length, 1, reason: 'iter-3 pass → approved');
      expect(approved.single.path, TerminalPath.handlerWispClosed);
      // The gate subprocess ran once per closure (3 times).
      expect(process.calls.length, 3);
    });

    test('operator approve terminates a waiting_manual loop', () async {
      const root = 'M';
      final source = FakeConvergenceSource(
        snapWith(
          roots: [
            convergenceBead(
              root,
              metadata: {
                ConvergenceFields.state: 'waiting_manual',
                ConvergenceFields.iteration: '1',
                ConvergenceFields.maxIterations: '5',
                ConvergenceFields.formula: 'f',
                ConvergenceFields.gateMode: 'manual',
                ConvergenceFields.waitingReason: 'manual',
                ConvergenceFields.lastProcessedWisp: '$root-w1',
              },
            ),
          ],
          children: {
            root: [
              wispBead(
                '$root-w1',
                key: idempotencyKey(root, 1),
                status: BeadStatus.closed,
                createdAt: fakeClock.subtract(const Duration(minutes: 5)),
                closedAt: fakeClock,
              ),
            ],
          },
        ),
      );
      final actuator = RecordingActuator();
      final runtime = ReconcilerRuntime(
        source: source,
        actuator: actuator,
        gateEvaluator: FakeGate(),
        ownership: const OwnsEverything(),
        runRecoveryAtStartup: false,
      );
      await runtime.start();

      final out = await runtime.submit(
        ReducerEvent.operatorApprove(convergenceBeadId: root, user: 'nico'),
      );
      await runtime.idle();
      await runtime.dispose();

      expect(out.status, CycleStatus.actuated);
      final approved = actuator.actions.whereType<ApprovedAction>().single;
      expect(approved.path, TerminalPath.operatorApprove);
      expect(approved.actor, 'operator:nico');
    });

    test('operator iterate advances a waiting_manual loop', () async {
      const root = 'I';
      final source = FakeConvergenceSource(
        snapWith(
          roots: [
            convergenceBead(
              root,
              metadata: {
                ConvergenceFields.state: 'waiting_manual',
                ConvergenceFields.iteration: '1',
                ConvergenceFields.maxIterations: '5',
                ConvergenceFields.formula: 'f',
                ConvergenceFields.gateMode: 'manual',
                ConvergenceFields.waitingReason: 'manual',
                ConvergenceFields.lastProcessedWisp: '$root-w1',
              },
            ),
          ],
          children: {
            root: [
              wispBead(
                '$root-w1',
                key: idempotencyKey(root, 1),
                status: BeadStatus.closed,
                createdAt: fakeClock.subtract(const Duration(minutes: 5)),
                closedAt: fakeClock,
              ),
            ],
          },
        ),
      );
      final actuator = RecordingActuator(
        nextResult: const ActuationResult(pouredWispId: '$root-w2'),
      );
      final runtime = ReconcilerRuntime(
        source: source,
        actuator: actuator,
        gateEvaluator: FakeGate(),
        ownership: const OwnsEverything(),
        runRecoveryAtStartup: false,
      );
      await runtime.start();

      final out = await runtime.submit(
        ReducerEvent.operatorIterate(convergenceBeadId: root, user: 'nico'),
      );
      await runtime.idle();
      await runtime.dispose();

      expect(out.status, CycleStatus.actuated);
      final iterate = actuator.actions.whereType<IterateAction>().single;
      expect(iterate.path, IteratePath.operatorIterate);
      expect(iterate.iteration, 2);
    });
  });
}
