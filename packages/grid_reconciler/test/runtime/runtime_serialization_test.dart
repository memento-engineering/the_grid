import 'package:grid_reconciler/grid_reconciler.dart';
import 'package:test/test.dart';

import 'support/runtime_fakes.dart';

/// Track G serialization (invariant 7): events for ONE convergence process in
/// arrival order; events for DIFFERENT convergences interleave; a slow gate on
/// bead A does not block bead B.
void main() {
  group('ReconcilerRuntime — per-bead serialization', () {
    test('a slow gate on bead A does not block bead B', () async {
      // Two independent loops, each with a closed active wisp. A's gate is
      // slow, B's is instant. B's cycle must complete before A's.
      final a = activeLoop(rootId: 'A', activeWispId: 'A-w1');
      final b = activeLoop(rootId: 'B', activeWispId: 'B-w1');
      final snapshot = snapWith(
        roots: [a.root, b.root],
        children: {
          'A': [a.closedWisp],
          'B': [b.closedWisp],
        },
      );
      final source = FakeConvergenceSource(snapshot);
      final actuator = RecordingActuator();
      final gate =
          FakeGate(defaultResult: GateResult.of(GateOutcome.fail, exitCode: 1))
            ..delayByBead['A'] = const Duration(milliseconds: 60)
            ..delayByBead['B'] = Duration.zero;

      final completionOrder = <String>[];
      final runtime = ReconcilerRuntime(
        source: source,
        actuator: actuator,
        gateEvaluator: gate,
        ownership: const OwnsEverything(),
        runRecoveryAtStartup: false,
        onCycle: (o) {
          if (o.status == CycleStatus.actuated) {
            completionOrder.add(o.convergenceBeadId);
          }
        },
      );
      await runtime.start();

      // Fire A's closure first, then B's — but A's gate is slow.
      source.emit(beadClosedEvent(a.closedWisp, a.closedWisp));
      source.emit(beadClosedEvent(b.closedWisp, b.closedWisp));

      await runtime.idle();
      await runtime.dispose();

      expect(
        completionOrder,
        ['B', 'A'],
        reason: 'B (fast gate) completes before A (slow gate) — not serialized',
      );
      // Both loops iterated (gate fail < max ⇒ iterate).
      expect(actuator.appliesByBead['A'], greaterThan(0));
      expect(actuator.appliesByBead['B'], greaterThan(0));
    });

    test(
      'concurrent events on ONE convergence process in arrival order',
      () async {
        // Two distinct events for the SAME bead (a wisp closure + a later
        // re-delivery of the same closure). Both route to bead C and must be
        // processed strictly serially — never overlapping — by the per-bead
        // queue. We observe the cycle-start order via the trace.
        final loop = activeLoop(rootId: 'C', activeWispId: 'C-w1');
        final snapshot = snapWith(
          roots: [loop.root],
          children: {
            'C': [loop.closedWisp],
          },
        );
        final source = FakeConvergenceSource(snapshot);
        final actuator = RecordingActuator();
        // A gate delay makes any overlap observable: a second cycle that
        // started before the first committed would re-pour (no overlay yet).
        final gate = FakeGate(
          defaultResult: GateResult.of(GateOutcome.fail, exitCode: 1),
          delay: const Duration(milliseconds: 20),
        );

        final runtime = ReconcilerRuntime(
          source: source,
          actuator: actuator,
          gateEvaluator: gate,
          ownership: const OwnsEverything(),
          runRecoveryAtStartup: false,
        );
        await runtime.start();

        // Both events route to bead C. Serialization guarantees the second
        // reduces over the first's overlay (post-actuation): the dedup marker
        // (last_processed_wisp ← C-w1) makes it a no-op. Were they NOT
        // serialized, both would reduce over the same pre-actuation snapshot
        // and pour twice.
        source.emit(beadClosedEvent(loop.closedWisp, loop.closedWisp));
        source.emit(beadClosedEvent(loop.closedWisp, loop.closedWisp));
        await runtime.idle();
        await runtime.dispose();

        // The first cycle iterated (fail < max); the second, over overlaid
        // post-actuation state, deduped (last_processed advanced) → skipped.
        final iterates = actuator.actions.whereType<IterateAction>().length;
        expect(
          iterates,
          1,
          reason: 'serialized + overlay-deduped: exactly one iterate',
        );
      },
    );
  });
}
