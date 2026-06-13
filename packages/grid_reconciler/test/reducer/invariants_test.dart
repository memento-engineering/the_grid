// Dedicated tests for the 7 crash-safety invariants (ADR-0003 Decision 2) and
// the exhaustive-dispatch contract. These pin the invariants directly (not as
// a side effect of a transition test) so a regression names the invariant it
// broke.

import 'package:grid_controller/grid_controller.dart';
import 'package:grid_reconciler/grid_reconciler.dart';
import 'package:test/test.dart';

import 'support/reducer_fakes.dart';

ReduceResult close(
  ({Convergence convergence, GraphSnapshot snapshot}) f,
  String wispId,
) => ConvergenceReducer.reduce(
  f.convergence,
  ReducerEvent.wispClosed(convergenceBeadId: 'root-1', wispId: wispId),
  f.snapshot,
);

void main() {
  group('Inv 1 — monotonic dedup skip FIRES', () {
    test(
      'the skip fires on equal iteration and is reported as duplicateWisp',
      () {
        final f = baseline(
          extra: {ConvergenceFields.lastProcessedWisp: 'wisp-iter-1'},
        );
        final a = close(f, 'wisp-iter-1').primary as SkippedAction;
        expect(a.reason, SkipReason.duplicateWisp);
      },
    );

    test('a NEW iteration is NOT skipped (the guard is strict <=)', () {
      // last_processed at iter-1; iter-2 closes (replay fail → iterate).
      final f = baseline(
        includeDefaultWisp: false,
        wisps: [wispChild('root-1', 1), wispChild('root-1', 2)],
        extra: {
          ConvergenceFields.lastProcessedWisp: 'wisp-iter-1',
          ...replay('fail', wisp: 'wisp-iter-2'),
        },
      );
      expect(close(f, 'wisp-iter-2').primary, isA<IterateAction>());
    });
  });

  group('Inv 2 — write ordering: last_processed_wisp is the LAST write', () {
    test('iterate: last_processed is the last load-bearing commit write '
        '(before the best-effort pending clear)', () {
      final f = baseline(extra: replay('fail'));
      final a = close(f, 'wisp-iter-1').primary as IterateAction;
      final w = a.postPourWrites('wisp-2');
      expect(w.last.key, ConvergenceFields.lastProcessedWisp);
    });

    test('waiting_manual: last_processed is the final ordered write', () {
      final f = baseline(extra: {ConvergenceFields.gateMode: 'manual'});
      final a = close(f, 'wisp-iter-1').primary as WaitingManualAction;
      expect(a.orderedWrites.last.key, ConvergenceFields.lastProcessedWisp);
    });

    test('waiting_trigger: last_processed is the final ordered write', () {
      final f = baseline(
        extra: {
          ...replay('fail'),
          ConvergenceFields.trigger: 'event',
          ConvergenceFields.triggerCondition: '/t/check',
        },
      );
      final a = close(f, 'wisp-iter-1').primary as WaitingTriggerAction;
      expect(a.orderedWrites.last.key, ConvergenceFields.lastProcessedWisp);
    });

    test('terminal AFTER-close ordering (A19): state=terminated is in the '
        'terminalWrites, the close happens, THEN last_processed is the '
        'separate commitWrite', () {
      final f = baseline(extra: replay('pass'));
      final a = close(f, 'wisp-iter-1').primary as ApprovedAction;
      // state=terminated is the LAST terminal write; the close + commit follow.
      expect(a.terminalWrites.last.key, ConvergenceFields.state);
      expect(a.terminalWrites.last.value, ConvergenceState.terminated.wire);
      // commitWrite (last_processed) is a SEPARATE write — actuated after the
      // CloseBead (the store accepts writes on a closed bead).
      expect(a.commitWrite!.key, ConvergenceFields.lastProcessedWisp);
    });

    test('Inv 2 gate half — persistGateOutcome writes gate_outcome_wisp LAST '
        '(coverage gap #1)', () {
      final f = baseline(
        extra: {ConvergenceFields.gateCondition: '/g/check.sh'},
      );
      final r = ConvergenceReducer.reduce(
        f.convergence,
        ReducerEvent.gateEvaluated(
          convergenceBeadId: 'root-1',
          wispId: 'wisp-iter-1',
          result: GateResult.of(GateOutcome.fail),
          pouredSpeculativeWispId: 'wisp-2',
        ),
        f.snapshot,
      );
      final persist = r.actions.whereType<PersistGateOutcomeAction>().single;
      final w = persist.orderedWrites;
      expect(w.length, 8);
      expect(w.first.key, ConvergenceFields.gateOutcome);
      expect(w.last.key, ConvergenceFields.gateOutcomeWisp);
      expect(w.last.value, 'wisp-iter-1');
    });
  });

  group('Inv 3 — idempotency keys', () {
    test('the poured wisp key is converge:<root>:iter:<N+1>', () {
      final f = baseline(extra: replay('fail'));
      final a = close(f, 'wisp-iter-1').primary as IterateAction;
      expect(a.pour.idempotencyKey, 'converge:root-1:iter:2');
    });

    test('parseIterationFromKey edge cases (handler.go:26-39, H02)', () {
      expect(parseIterationFromKey('converge:root-1:iter:1'), 1);
      expect(parseIterationFromKey('converge:root-1:iter:0'), 0); // 0 valid
      expect(parseIterationFromKey('converge:a:iter:7:iter:3'), 3); // last
      expect(parseIterationFromKey('converge:root-1:iter:-1'), isNull);
      expect(parseIterationFromKey('converge:root-1:iter:abc'), isNull);
      expect(parseIterationFromKey('converge:root-1:iter:'), isNull);
      expect(parseIterationFromKey('no-iter-marker'), isNull);
      expect(parseIterationFromKey(''), isNull);
    });

    test('IdempotencyKey formula + round trip (H03)', () {
      expect(idempotencyKey('bead-42', 3), 'converge:bead-42:iter:3');
      expect(parseIterationFromKey(idempotencyKey('bead-42', 3)), 3);
    });
  });

  group('Inv 4 — iteration derived from closed-wisp count, self-healing', () {
    test('repair fires when stored disagrees with derived count', () {
      final f = baseline(
        extra: {ConvergenceFields.iteration: '7', ...replay('fail')},
      );
      final r = close(f, 'wisp-iter-1');
      final repair = r.actions.whereType<RepairIterationAction>().single;
      expect(repair.derivedIteration, 1);
      expect(repair.write.value, '1');
    });

    test('derived count ignores OPEN wisps (only closed children count)', () {
      // Two children: iter-1 closed, iter-2 OPEN. Derived count = 1.
      final f = baseline(
        includeDefaultWisp: false,
        wisps: [
          wispChild('root-1', 1),
          wispChild('root-1', 2, status: BeadStatus.inProgress),
        ],
        extra: {ConvergenceFields.iteration: '9', ...replay('fail')},
      );
      final repair = close(
        f,
        'wisp-iter-1',
      ).actions.whereType<RepairIterationAction>().single;
      expect(repair.derivedIteration, 1);
    });
  });

  group(
    'Inv 5 — speculative pour before gate eval; burned on terminal/manual',
    () {
      test('fresh condition gate: the speculative pour PRECEDES the gate eval '
          'in the action list', () {
        final f = baseline(
          extra: {ConvergenceFields.gateCondition: '/g/check.sh'},
        );
        final r = close(f, 'wisp-iter-1');
        final pourIdx = r.actions.indexWhere((a) => a is PourSpeculativeAction);
        final evalIdx = r.actions.indexWhere((a) => a is EvaluateGateAction);
        expect(pourIdx, isNonNegative);
        expect(evalIdx, isNonNegative);
        expect(pourIdx < evalIdx, isTrue);
      });

      test('the speculative pour is BURNED on a terminal outcome (replay pass '
          'below max → burnPriorPour)', () {
        final f = baseline(extra: replay('pass'));
        final a = close(f, 'wisp-iter-1').primary as ApprovedAction;
        expect(a.burnPriorPour, isTrue);
      });

      test('the speculative pour is BURNED on a manual/timeout-manual hold '
          '(replay timeout+manual → burnPriorPour)', () {
        final f = baseline(
          extra: {
            ConvergenceFields.gateTimeoutAction: 'manual',
            ...replay('timeout'),
          },
        );
        final a = close(f, 'wisp-iter-1').primary as WaitingManualAction;
        expect(a.burnPriorPour, isTrue);
      });

      test('manual mode pours NOTHING to burn (skipSpeculativePour)', () {
        final f = baseline(extra: {ConvergenceFields.gateMode: 'manual'});
        final r = close(f, 'wisp-iter-1');
        expect(r.actions.whereType<PourSpeculativeAction>(), isEmpty);
        final a = r.primary as WaitingManualAction;
        expect(a.burnPriorPour, isFalse);
        expect(a.burnWispId, isNull);
      });

      test('validPendingNextWisp adopts a valid pending; a STALE pending is '
          'self-healed (clearStalePending) on a hold path', () {
        // Stale pending: points at a CLOSED bead (invalid).
        final stale = wispChild('root-1', 2); // closed → invalid as pending
        final f = baseline(
          includeDefaultWisp: false,
          wisps: [wispChild('root-1', 1), stale],
          extra: {
            ConvergenceFields.gateMode: 'manual',
            ConvergenceFields.pendingNextWisp: 'wisp-iter-2',
          },
        );
        final a = close(f, 'wisp-iter-1').primary as WaitingManualAction;
        // No valid pending to burn; the stale pointer is cleared.
        expect(a.burnWispId, isNull);
        expect(a.clearStalePending, isTrue);
      });
    },
  );

  group('Inv 6 — terminal irreversibility', () {
    test('any wisp-closed event on a terminated loop → skipped', () {
      final f = baseline(extra: {ConvergenceFields.state: 'terminated'});
      expect(
        (close(f, 'wisp-iter-1').primary as SkippedAction).reason,
        SkipReason.alreadyTerminated,
      );
    });

    test('a closed terminated root does NOT re-close (closeRootBestEffort '
        'false when already closed)', () {
      final f = baseline(extra: {ConvergenceFields.state: 'terminated'});
      // Reproject with a closed root to drive isClosed=true.
      final closedRoot = convergenceBead(
        'root-1',
        status: BeadStatus.closed,
        metadata: {ConvergenceFields.state: 'terminated'},
      );
      final p = project(closedRoot, [wispChild('root-1', 1)]);
      final a = close(p, 'wisp-iter-1').primary as SkippedAction;
      expect(a.closeRootBestEffort, isFalse);
      // The original (open) terminated root DOES request the best-effort close.
      final aOpen = close(f, 'wisp-iter-1').primary as SkippedAction;
      expect(aOpen.closeRootBestEffort, isTrue);
    });
  });

  group('exhaustive dispatch — every ReducerEvent + state reading is handled', () {
    test('a not-adopted state (absent convergence.state) wisp-close does not '
        'throw and is NOT treated as terminated', () {
      // No convergence.state key at all → notAdopted reading.
      final root = convergenceBead(
        'root-1',
        metadata: {
          ConvergenceFields.maxIterations: '5',
          ConvergenceFields.formula: 'f',
          ConvergenceFields.gateMode: 'manual',
        },
      );
      final f = project(root, [wispChild('root-1', 1)]);
      // notAdopted is not terminated, so the wisp-closed pipeline runs (manual
      // gate → waiting_manual). The point: no crash, no default arm swallowing.
      final r = close(f, 'wisp-iter-1');
      expect(r.primary, isA<WaitingManualAction>());
    });

    test('an UNRECOGNIZED state (drift) is not terminated and reduces without '
        'throwing', () {
      final f = baseline(extra: {ConvergenceFields.state: 'limbo'});
      // limbo != terminated → the pipeline runs (no guard skip).
      expect(() => close(f, 'wisp-iter-1'), returnsNormally);
    });

    test('every ReducerEvent variant returns a non-empty ReduceResult', () {
      final wm = waitingManual();
      final wt = waitingTrigger();
      final base = baseline(extra: replay('fail'));
      final events =
          <(({Convergence convergence, GraphSnapshot snapshot}), ReducerEvent)>[
            (
              base,
              const ReducerEvent.wispClosed(
                convergenceBeadId: 'root-1',
                wispId: 'wisp-iter-1',
              ),
            ),
            (
              base,
              ReducerEvent.gateEvaluated(
                convergenceBeadId: 'root-1',
                wispId: 'wisp-iter-1',
                result: GateResult.of(GateOutcome.fail),
              ),
            ),
            (
              wm,
              const ReducerEvent.operatorApprove(
                convergenceBeadId: 'root-1',
                user: 'a',
              ),
            ),
            (
              wm,
              const ReducerEvent.operatorIterate(
                convergenceBeadId: 'root-1',
                user: 'a',
              ),
            ),
            (
              wm,
              const ReducerEvent.operatorStop(
                convergenceBeadId: 'root-1',
                user: 'a',
              ),
            ),
            (
              wt,
              const ReducerEvent.triggerPassed(
                convergenceBeadId: 'root-1',
                nextIteration: 1,
              ),
            ),
          ];
      for (final (f, event) in events) {
        final r = ConvergenceReducer.reduce(f.convergence, event, f.snapshot);
        expect(r.actions, isNotEmpty, reason: '$event produced no actions');
      }
    });
  });

  group('TR1 — ParseTriggerConfig rows (trigger.go:26-41)', () {
    test('event without a condition path → failed', () {
      // trigger=event but NO trigger_condition.
      final root = convergenceBead(
        'root-1',
        metadata: {
          ConvergenceFields.state: 'active',
          ConvergenceFields.iteration: '1',
          ConvergenceFields.maxIterations: '5',
          ConvergenceFields.gateMode: 'condition',
          ConvergenceFields.gateCondition: '/g/c.sh',
          ConvergenceFields.trigger: 'event',
          // no trigger_condition
        },
      );
      final f = project(root, [wispChild('root-1', 1)]);
      final a =
          ConvergenceReducer.reduce(
                f.convergence,
                const ReducerEvent.wispClosed(
                  convergenceBeadId: 'root-1',
                  wispId: 'wisp-iter-1',
                ),
                f.snapshot,
              ).primary
              as FailedAction;
      expect(a.message, contains('requires a trigger condition'));
    });

    test('invalid trigger mode → failed', () {
      final f = baseline(extra: {ConvergenceFields.trigger: 'cron'});
      final a = close(f, 'wisp-iter-1').primary as FailedAction;
      expect(a.message, contains('invalid trigger mode'));
    });
  });

  group('gate config parse errors (gate.go:44-85) → failed', () {
    test('invalid gate mode → failed', () {
      final f = baseline(extra: {ConvergenceFields.gateMode: 'weird'});
      expect(
        (close(f, 'wisp-iter-1').primary as FailedAction).message,
        contains('invalid gate mode'),
      );
    });

    test('invalid gate timeout action → failed', () {
      final f = baseline(extra: {ConvergenceFields.gateTimeoutAction: 'spin'});
      expect(
        (close(f, 'wisp-iter-1').primary as FailedAction).message,
        contains('invalid gate timeout action'),
      );
    });
  });
}
