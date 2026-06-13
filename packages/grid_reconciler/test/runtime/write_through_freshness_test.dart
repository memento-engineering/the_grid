import 'package:grid_reconciler/grid_reconciler.dart';
import 'package:test/test.dart';

import 'support/runtime_fakes.dart';

/// Write-through freshness (ADR-0000 A17, load-bearing): events MUST be
/// evaluated against post-actuation state, never the raw (stale) snapshot, so a
/// fast gate/closure that beats the Dolt watcher cannot re-fire a transition —
/// the duplicate-pour race. We reproduce the race and assert exactly ONE pour.
void main() {
  group('WriteThroughOverlay — unit', () {
    test('layers recorded writes over the snapshot metadata', () {
      // A loop whose snapshot shows last_processed_wisp absent; after an
      // iterate actuation the overlay carries last_processed_wisp ← w1.
      final loop = activeLoop(rootId: 'O', activeWispId: 'O-w1');
      final source = FakeConvergenceSource(
        snapWith(
          roots: [loop.root],
          children: {
            'O': [loop.closedWisp],
          },
        ),
      );
      final base = source.convergence('O')!;
      expect(base.metadata.lastProcessedWisp, isNull);

      final overlay = WriteThroughOverlay();
      overlay.recordWrites('O', const [
        MetadataWrite(key: ConvergenceFields.lastProcessedWisp, value: 'O-w1'),
      ]);
      final overlaid = overlay.apply(base);
      expect(overlaid.metadata.lastProcessedWisp, 'O-w1');
      // The base projection is untouched.
      expect(base.metadata.lastProcessedWisp, isNull);
    });

    test('reconcileWithSnapshot drops only caught-up keys', () {
      final overlay = WriteThroughOverlay()
        ..recordWrites('X', const [
          MetadataWrite(key: ConvergenceFields.lastProcessedWisp, value: 'w5'),
          MetadataWrite(key: ConvergenceFields.state, value: 'terminated'),
        ]);
      // The snapshot caught up on last_processed_wisp but not state.
      overlay.reconcileWithSnapshot('X', {
        ConvergenceFields.lastProcessedWisp: 'w5',
        ConvergenceFields.state: 'active',
      });
      final remaining = overlay.overlayFor('X');
      expect(
        remaining.containsKey(ConvergenceFields.lastProcessedWisp),
        isFalse,
      );
      expect(remaining[ConvergenceFields.state], 'terminated');
    });
  });

  group('ReconcilerRuntime — A17 duplicate-pour race', () {
    test(
      'a re-delivered triggerPassed beating the watcher pours exactly ONCE',
      () async {
        // A trigger-gated loop in waiting_trigger, iteration 0, no wisps yet.
        // Two triggerPassed(1) events arrive back-to-back (a re-delivery / a
        // probe that beat the watcher). The snapshot NEVER updates between them
        // (the watcher lag). Only the write-through overlay can dedup the
        // second — and it must, to exactly one pour.
        final root = convergenceBead(
          'T',
          metadata: {
            ConvergenceFields.state: 'waiting_trigger',
            ConvergenceFields.iteration: '0',
            ConvergenceFields.maxIterations: '5',
            ConvergenceFields.formula: 'test-formula',
            ConvergenceFields.gateMode: 'condition',
            ConvergenceFields.gateCondition: '/gate/check.sh',
            ConvergenceFields.gateTimeout: '60s',
            ConvergenceFields.trigger: 'event',
            ConvergenceFields.triggerCondition: '/trigger/check.sh',
          },
        );
        final source = FakeConvergenceSource(snapWith(roots: [root]));
        final actuator = RecordingActuator(
          nextResult: const ActuationResult(pouredWispId: 'T-w1'),
        );
        final gate = FakeGate();

        final runtime = ReconcilerRuntime(
          source: source,
          actuator: actuator,
          gateEvaluator: gate,
          ownership: const OwnsEverything(),
          runRecoveryAtStartup: false,
        );
        await runtime.start();

        // Two trigger passes for iteration 1 — the duplicate-submit race.
        await runtime.submit(
          ReducerEvent.triggerPassed(convergenceBeadId: 'T', nextIteration: 1),
        );
        await runtime.submit(
          ReducerEvent.triggerPassed(convergenceBeadId: 'T', nextIteration: 1),
        );
        await runtime.idle();
        await runtime.dispose();

        // The trigger-advance iterate transitions waiting_trigger → active and
        // writes state=active + iteration=1. The SECOND triggerPassed reduces
        // over the OVERLAID convergence (state now active), where the trigger
        // guard (state != waiting_trigger) skips it (trigger.go:58-61). So
        // exactly one iterate / one pour.
        final iterates = actuator.actions.whereType<IterateAction>().toList();
        expect(
          iterates.length,
          1,
          reason:
              'the second triggerPassed deduped by the write-through overlay',
        );
        expect(iterates.single.path, IteratePath.triggerAdvance);
        // The second cycle was a no-op skip (the trigger guard).
        final skips = runtime.outcomes
            .where((o) => o.primary is SkippedAction)
            .map((o) => (o.primary! as SkippedAction).reason);
        expect(skips, contains(SkipReason.notWaitingTrigger));
      },
    );

    test('WITHOUT the overlay both events would pour — control: raw snapshot '
        'double-fires', () async {
      // Same setup, but we prove the race is REAL: reducing the second event
      // over the RAW (un-overlaid) snapshot still shows waiting_trigger and
      // would advance again. This is what the overlay prevents.
      final root = convergenceBead(
        'T2',
        metadata: {
          ConvergenceFields.state: 'waiting_trigger',
          ConvergenceFields.iteration: '0',
          ConvergenceFields.maxIterations: '5',
          ConvergenceFields.formula: 'f',
          ConvergenceFields.trigger: 'event',
          ConvergenceFields.triggerCondition: '/t.sh',
        },
      );
      final source = FakeConvergenceSource(snapWith(roots: [root]));
      final raw = source.convergence('T2')!;
      // The raw snapshot, reduced twice, advances BOTH times — the race.
      final r1 = ConvergenceReducer.reduce(
        raw,
        ReducerEvent.triggerPassed(convergenceBeadId: 'T2', nextIteration: 1),
        source.current!,
      );
      final r2 = ConvergenceReducer.reduce(
        raw,
        ReducerEvent.triggerPassed(convergenceBeadId: 'T2', nextIteration: 1),
        source.current!,
      );
      expect(r1.primary, isA<IterateAction>());
      expect(
        r2.primary,
        isA<IterateAction>(),
        reason:
            'the raw snapshot re-fires — exactly the race the overlay fixes',
      );
    });
  });
}
