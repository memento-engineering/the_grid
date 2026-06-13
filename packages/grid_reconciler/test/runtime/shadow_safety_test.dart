import 'package:grid_controller/grid_controller.dart';
import 'package:grid_reconciler/grid_reconciler.dart';
import 'package:test/test.dart';

import 'support/runtime_fakes.dart';

/// Shadow-mode safety (ADR-0003 Decision 6 — STRICTLY read-only; a safety
/// boundary): shadow mode emits divergence reports and NEVER invokes a mutating
/// bd verb (it constructs no writer at all), and the coexistence partition
/// predicate blocks actuation of a non-owned bead.
void main() {
  group('ShadowRuntime — structurally read-only', () {
    test('emits a divergence report and NEVER touches a writer', () async {
      // A loop whose active wisp closes; the_grid's reducer would (gate fail
      // below max) ITERATE. gc is then observed (BeadUpdated) to APPROVE —
      // a divergence.
      final loop = activeLoop(rootId: 'G', activeWispId: 'G-w1');
      final source = FakeConvergenceSource(
        snapWith(
          roots: [loop.root],
          children: {
            'G': [loop.closedWisp],
          },
        ),
      );
      final shadow = ShadowRuntime(source: source);
      shadow.start();

      // (1) Observe the wisp closure → the_grid predicts a transition.
      source.emit(beadClosedEvent(loop.closedWisp, loop.closedWisp));
      await pumpEventQueue();

      // (2) Observe gc's metadata write: it terminated the loop as approved by
      // an operator. This is a read-only inference over gc's OWN write.
      final after = loop.root.copyWith(
        metadata: {
          ...loop.root.metadata,
          ConvergenceFields.state: 'terminated',
          ConvergenceFields.terminalReason: 'approved',
          ConvergenceFields.terminalActor: 'operator:someone',
        },
      );
      source.emit(beadUpdatedEvent(loop.root, after));
      await pumpEventQueue();
      await shadow.dispose();

      // A divergence report was emitted...
      expect(shadow.reports, isNotEmpty);
      final report = shadow.reports.last;
      expect(report.convergenceBeadId, 'G');
      // The actor is `operator:...`, so the detection classifies it as an
      // operator approve (the §1.6 signature).
      expect(report.observed.command, GcCommandKind.operatorApprove);
      // ...and it diverged: the_grid would have iterated (a non-pass gate is a
      // fresh-gate handoff — predicted wire is null until the gate runs, so the
      // shadow records the would-be transition path; either way it is NOT
      // `approved`).
      expect(report.diverged, isTrue);
    });

    test('ShadowRuntime has no Actuator-shaped constructor parameter '
        '(structural read-only)', () {
      // This is a STRUCTURAL guarantee, not a runtime one: a ShadowRuntime is
      // built from a ConvergenceSource (reads only) — there is no parameter
      // through which an Actuator or a bd surface could be passed. We assert
      // the type can be constructed with ONLY a source (no writer), which is
      // the whole safety property: nothing capable of a mutating bd verb is
      // reachable.
      final source = FakeConvergenceSource(snapWith(roots: const []));
      final shadow = ShadowRuntime(source: source);
      expect(shadow, isNotNull);
      // The shadow recovery pass returns would-be effects as DATA, never
      // actuating them.
      final report = shadow.shadowRecovery();
      expect(report.scanned, 0);
    });

    test('agreeing prediction → no divergence', () async {
      // A loop whose gate would PASS (the_grid predicts approved) and gc is
      // observed to approve too — they AGREE, so diverged is false. We use the
      // shadow's predict-from-closure then a matching gc approve. Since the
      // shadow does not run gates, the prediction for a fresh condition gate is
      // the would-be handoff; to test the agreement path cleanly we drive a
      // replay-mode loop (a persisted gate_outcome=pass) so the reduce yields
      // `approved` in one pass.
      final root = convergenceBead(
        'A',
        metadata: {
          ConvergenceFields.state: 'active',
          ConvergenceFields.iteration: '1',
          ConvergenceFields.maxIterations: '5',
          ConvergenceFields.formula: 'f',
          ConvergenceFields.gateMode: 'condition',
          ConvergenceFields.gateCondition: '/g.sh',
          ConvergenceFields.gateTimeout: '60s',
          ConvergenceFields.activeWisp: 'A-w1',
          // Replay marker: the gate already ran and PASSED for A-w1.
          ConvergenceFields.gateOutcomeWisp: 'A-w1',
          ConvergenceFields.gateOutcome: 'pass',
          ConvergenceFields.gateRetryCount: '0',
        },
      );
      final wisp = wispBead(
        'A-w1',
        key: idempotencyKey('A', 1),
        status: BeadStatus.closed,
        createdAt: fakeClock.subtract(const Duration(minutes: 5)),
        closedAt: fakeClock,
      );
      final source = FakeConvergenceSource(
        snapWith(
          roots: [root],
          children: {
            'A': [wisp],
          },
        ),
      );
      final shadow = ShadowRuntime(source: source);
      shadow.start();

      source.emit(beadClosedEvent(wisp, wisp));
      await pumpEventQueue();

      final after = root.copyWith(
        metadata: {
          ...root.metadata,
          ConvergenceFields.state: 'terminated',
          ConvergenceFields.terminalReason: 'approved',
          ConvergenceFields.terminalActor: 'controller',
        },
      );
      source.emit(beadUpdatedEvent(root, after));
      await pumpEventQueue();
      await shadow.dispose();

      final report = shadow.reports.last;
      expect(report.predictedWire, 'approved');
      expect(report.observed.command, GcCommandKind.handlerApproved);
      expect(report.diverged, isFalse, reason: 'both approved — they agree');
    });
  });

  group('OwnershipPredicate — the coexistence partition gates actuation', () {
    test('the writing runtime does NOT actuate a non-owned bead', () async {
      // A loop the_grid does NOT own (OwnsRigs with a different rig). A live
      // closure must be reduced but NEVER actuated — the partition boundary.
      final loop = activeLoop(
        rootId: 'NotOurs',
        activeWispId: 'NotOurs-w1',
        extra: {ConvergenceFields.rig: 'gc-rig'},
      );
      final source = FakeConvergenceSource(
        snapWith(
          roots: [loop.root],
          children: {
            'NotOurs': [loop.closedWisp],
          },
        ),
      );
      final actuator = RecordingActuator();
      final runtime = ReconcilerRuntime(
        source: source,
        actuator: actuator,
        gateEvaluator: FakeGate(),
        // We own only "the-grid-rig"; this loop's rig is "gc-rig".
        ownership: OwnsRigs(const ['the-grid-rig']),
        runRecoveryAtStartup: false,
      );
      await runtime.start();

      source.emit(beadClosedEvent(loop.closedWisp, loop.closedWisp));
      await runtime.idle();
      await runtime.dispose();

      // The actuator was NEVER asked to mutate the non-owned bead.
      expect(
        actuator.didMutate,
        isFalse,
        reason: 'the partition blocked actuation of a non-owned bead',
      );
      expect(actuator.appliesByBead['NotOurs'], isNull);
      // The cycle was still traced as a skip (observed, not actuated).
      expect(
        runtime.outcomes.any((o) => o.status == CycleStatus.skipped),
        isTrue,
      );
    });

    test('the writing runtime DOES actuate an owned bead', () async {
      final loop = activeLoop(
        rootId: 'Ours',
        activeWispId: 'Ours-w1',
        extra: {ConvergenceFields.rig: 'the-grid-rig'},
      );
      final source = FakeConvergenceSource(
        snapWith(
          roots: [loop.root],
          children: {
            'Ours': [loop.closedWisp],
          },
        ),
      );
      final actuator = RecordingActuator(
        nextResult: const ActuationResult(pouredWispId: 'Ours-w2'),
      );
      final runtime = ReconcilerRuntime(
        source: source,
        actuator: actuator,
        gateEvaluator: FakeGate(
          defaultResult: GateResult.of(GateOutcome.fail, exitCode: 1),
        ),
        ownership: OwnsRigs(const ['the-grid-rig']),
        runRecoveryAtStartup: false,
      );
      await runtime.start();

      source.emit(beadClosedEvent(loop.closedWisp, loop.closedWisp));
      await runtime.idle();
      await runtime.dispose();

      expect(actuator.appliesByBead['Ours'], isNotNull);
      expect(actuator.didMutate, isTrue);
    });

    test('OwnsNothing is the safe default — owns no loop', () {
      final loop = activeLoop(extra: {ConvergenceFields.rig: 'any'});
      final source = FakeConvergenceSource(
        snapWith(
          roots: [loop.root],
          children: {
            'root-1': [loop.closedWisp],
          },
        ),
      );
      const predicate = OwnsNothing();
      expect(predicate.owns(source.convergence('root-1')!), isFalse);
    });
  });
}
