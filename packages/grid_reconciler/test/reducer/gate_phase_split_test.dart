// The PHASE SPLIT: a fresh (non-replay) condition/hybrid gate cannot run a
// subprocess inside the pure reducer (Track D's job). Phase 1 (wispClosed,
// fresh) emits a PourSpeculativeAction (step 3b) + an EvaluateGateAction
// (step 4 handoff) and NO transition. Phase 2 (gateEvaluated) carries the
// GateResult + the phase-1 pour outcome back and makes the transition.
//
// This is the reducer-specific structure that replaces gc's in-frame gate
// call (handler.go:326-327). It also closes the must-tier hole H31 left by
// being subprocess-coupled in Go: the pure "speculative pour failed but the
// gate passed → still approved" variant (coverage gap #8).

import 'package:grid_reconciler/grid_reconciler.dart';
import 'package:test/test.dart';

import 'support/reducer_fakes.dart';

const _wispClosed = ReducerEvent.wispClosed(
  convergenceBeadId: 'root-1',
  wispId: 'wisp-iter-1',
);

void main() {
  group('phase 1 — fresh condition gate (handler.go:244-327)', () {
    test('emits pourSpeculative THEN evaluateGate, and NO transition', () {
      // Baseline condition mode WITH a condition path, no replay marker.
      final f = baseline(
        extra: {ConvergenceFields.gateCondition: '/gate/check.sh'},
      );
      final r = ConvergenceReducer.reduce(
        f.convergence,
        _wispClosed,
        f.snapshot,
      );

      // Exactly: [pourSpeculative, evaluateGate] (iteration matches stored, no
      // repair).
      expect(r.actions, hasLength(2));
      expect(r.actions[0], isA<PourSpeculativeAction>());
      expect(r.actions[1], isA<EvaluateGateAction>());

      // No transition action of any kind in phase 1.
      expect(r.actions.whereType<IterateAction>(), isEmpty);
      expect(r.actions.whereType<ApprovedAction>(), isEmpty);
      expect(r.actions.whereType<WaitingManualAction>(), isEmpty);
      expect(r.actions.whereType<PersistGateOutcomeAction>(), isEmpty);
    });

    test('the speculative pour is the next-iteration key, marked speculative; '
        'the gate handoff carries the parsed config + snapshot env', () {
      final f = baseline(
        extra: {ConvergenceFields.gateCondition: '/gate/check.sh'},
      );
      final r = ConvergenceReducer.reduce(
        f.convergence,
        _wispClosed,
        f.snapshot,
      );

      final pour = r.actions.whereType<PourSpeculativeAction>().single;
      expect(pour.pour.idempotencyKey, 'converge:root-1:iter:2');
      expect(pour.pour.iteration, 2);
      expect(pour.pour.speculative, isTrue);
      expect(pour.pour.formula, 'test-formula');

      final eval = r.actions.whereType<EvaluateGateAction>().single;
      expect(eval.wispId, 'wisp-iter-1');
      expect(eval.iteration, 1);
      expect(eval.config.mode, GateMode.condition);
      expect(eval.config.condition, '/gate/check.sh');
      // Default 5m timeout, default iterate action.
      expect(eval.config.timeoutAction, GateTimeoutAction.iterate);
      // env defaults — gate-path verdict is the `block` substitute when no
      // scoped verdict is present (handler.go:317-324).
      expect(eval.env.agentVerdict.wire, Verdict.block.wire);
    });

    test('the EvaluateGateAction and PourSpeculativeAction carry no '
        'HandlerAction wire (they are carriers)', () {
      final f = baseline(
        extra: {ConvergenceFields.gateCondition: '/gate/check.sh'},
      );
      final r = ConvergenceReducer.reduce(
        f.convergence,
        _wispClosed,
        f.snapshot,
      );
      expect(r.actions[0].wire, isNull);
      expect(r.actions[1].wire, isNull);
    });

    test('hybrid WITH condition also runs a fresh gate (phase 1 handoff)', () {
      final f = baseline(
        extra: {
          ConvergenceFields.gateMode: 'hybrid',
          ConvergenceFields.gateCondition: '/gate/check.sh',
        },
      );
      final r = ConvergenceReducer.reduce(
        f.convergence,
        _wispClosed,
        f.snapshot,
      );
      expect(r.actions.whereType<EvaluateGateAction>(), hasLength(1));
      expect(
        r.actions.whereType<EvaluateGateAction>().single.config.mode,
        GateMode.hybrid,
      );
    });

    test(
      'hybrid gate env feeds the SCOPED verdict (not block) when present',
      () {
        final f = baseline(
          extra: {
            ConvergenceFields.gateMode: 'hybrid',
            ConvergenceFields.gateCondition: '/gate/check.sh',
            ConvergenceFields.agentVerdict: 'approve',
            ConvergenceFields.agentVerdictWisp: 'wisp-iter-1',
          },
        );
        final eval = ConvergenceReducer.reduce(
          f.convergence,
          _wispClosed,
          f.snapshot,
        ).actions.whereType<EvaluateGateAction>().single;
        expect(eval.env.agentVerdict.wire, Verdict.approve.wire);
      },
    );
  });

  group('phase 2 — gateEvaluated drives the transition (handler.go:330-389)', () {
    GateEvaluatedEvent evaluated(
      GateOutcome outcome, {
      String? pouredSpeculativeWispId,
      bool pourFailed = false,
    }) =>
        ReducerEvent.gateEvaluated(
              convergenceBeadId: 'root-1',
              wispId: 'wisp-iter-1',
              result: GateResult.of(outcome),
              pouredSpeculativeWispId: pouredSpeculativeWispId,
              pourFailed: pourFailed,
            )
            as GateEvaluatedEvent;

    test('fresh pass → persistGateOutcome (step 5) THEN approved; the '
        'persist action burns the phase-1 wisp', () {
      final f = baseline(
        extra: {ConvergenceFields.gateCondition: '/gate/check.sh'},
      );
      final r = ConvergenceReducer.reduce(
        f.convergence,
        evaluated(GateOutcome.pass, pouredSpeculativeWispId: 'wisp-2'),
        f.snapshot,
      );
      // Step 5 persist precedes the transition (Inv 2 gate half).
      final persist = r.actions.whereType<PersistGateOutcomeAction>().single;
      expect(persist.wispId, 'wisp-iter-1');
      expect(persist.burnWispId, 'wisp-2');
      // gate_outcome_wisp is LAST in the eight persist writes.
      expect(persist.orderedWrites.last.key, ConvergenceFields.gateOutcomeWisp);
      expect(persist.orderedWrites.last.value, 'wisp-iter-1');
      // Transition: approved, burning the phase-1 wisp by id.
      final a = r.primary as ApprovedAction;
      expect(a.burnWispId, 'wisp-2');
    });

    test('fresh fail below max → persist THEN iterate adopting the phase-1 '
        'wisp by id (adoptWispId, not adoptFromPriorPour)', () {
      final f = baseline(
        extra: {ConvergenceFields.gateCondition: '/gate/check.sh'},
      );
      final a =
          ConvergenceReducer.reduce(
                f.convergence,
                evaluated(GateOutcome.fail, pouredSpeculativeWispId: 'wisp-2'),
                f.snapshot,
              ).primary
              as IterateAction;
      expect(a.adoptWispId, 'wisp-2');
      expect(a.adoptFromPriorPour, isFalse);
    });

    test('coverage gap #8 / H31 pure variant — phase-1 pour FAILED but gate '
        'PASSED → approved, the pour failure is ignored on terminal '
        '(handler.go:370-374)', () {
      final f = baseline(
        extra: {ConvergenceFields.gateCondition: '/gate/pass.sh'},
      );
      final r = ConvergenceReducer.reduce(
        f.convergence,
        evaluated(GateOutcome.pass, pourFailed: true),
        f.snapshot,
      );
      final a = r.primary;
      expect(a, isA<ApprovedAction>());
      // No sling_failure hold — pour error consulted only on NON-terminal.
      expect(r.actions.whereType<WaitingManualAction>(), isEmpty);
    });

    test('H15 — phase-1 pour FAILED and gate FAILED (non-terminal) → '
        'waiting_manual(sling_failure), no error (handler.go:370-373)', () {
      final f = baseline(
        extra: {ConvergenceFields.gateCondition: '/gate/check.sh'},
      );
      final a = ConvergenceReducer.reduce(
        f.convergence,
        evaluated(GateOutcome.fail, pourFailed: true),
        f.snapshot,
      ).primary;
      expect(a, isA<WaitingManualAction>());
      expect(
        (a as WaitingManualAction).reason.wire,
        WaitingReason.slingFailure.wire,
      );
      // sling_failure never burns — its defining condition is no wisp exists.
      expect(a.burnWispId, isNull);
      expect(a.burnPriorPour, isFalse);
    });

    test('coverage gap #7 — phase-1 pour error RESCUED by key lookup: the '
        'event carries pouredSpeculativeWispId AND pourFailed=false → iterate, '
        'NO sling failure', () {
      final f = baseline(
        extra: {ConvergenceFields.gateCondition: '/gate/check.sh'},
      );
      final r = ConvergenceReducer.reduce(
        f.convergence,
        evaluated(
          GateOutcome.fail,
          pouredSpeculativeWispId: 'wisp-2', // adopted via FindByIdempotencyKey
          // pourFailed false — the probe found the wisp.
        ),
        f.snapshot,
      );
      expect(r.primary, isA<IterateAction>());
      expect(r.actions.whereType<WaitingManualAction>(), isEmpty);
    });
  });
}
