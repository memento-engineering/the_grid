// Conformance suite — transliterated from manual_test.go + trigger_test.go per
// doc/port/conformance-operator-tests.md (ADR-0003 Decision 7). Each test cites
// its M##/TR## id and the Go line of the pinned behavior.
//
// RetryHandler (retry_test.go / R1-R9) is the CREATE/retry surface
// (create.go), NOT a reduce(state, event, snapshot) transition — it has no
// ReducerEvent and is out of Track B's scope (the reducer never creates a
// loop). Recorded as a goAmbiguity.

import 'package:grid_controller/grid_controller.dart';
import 'package:grid_reconciler/grid_reconciler.dart';
import 'package:test/test.dart';

import 'support/reducer_fakes.dart';

ReduceResult approve(
  ({Convergence convergence, GraphSnapshot snapshot}) f, {
  String user = 'alice',
}) => ConvergenceReducer.reduce(
  f.convergence,
  ReducerEvent.operatorApprove(convergenceBeadId: 'root-1', user: user),
  f.snapshot,
);

ReduceResult iterate(
  ({Convergence convergence, GraphSnapshot snapshot}) f, {
  String user = 'alice',
}) => ConvergenceReducer.reduce(
  f.convergence,
  ReducerEvent.operatorIterate(convergenceBeadId: 'root-1', user: user),
  f.snapshot,
);

ReduceResult stop(
  ({Convergence convergence, GraphSnapshot snapshot}) f, {
  String user = 'alice',
  bool postDrain = false,
}) => ConvergenceReducer.reduce(
  f.convergence,
  ReducerEvent.operatorStop(
    convergenceBeadId: 'root-1',
    user: user,
    postDrain: postDrain,
  ),
  f.snapshot,
);

void main() {
  // ===========================================================================
  // ApproveHandler (manual.go:20-115) — M1-M6
  // ===========================================================================
  group('M1-M6 ApproveHandler (T8)', () {
    test('M1 happy path → approved, operator actor, derived iteration', () {
      final a = approve(waitingManual()).primary as ApprovedAction;
      expect(a.wire, 'approved');
      expect(a.iteration, 1); // derived closed-children count
      expect(a.actor, 'operator:alice');
      expect(a.path, TerminalPath.operatorApprove);
      expect(a.closeReason, CloseReasons.manualApprove);
      expect(a.clearWaitingReason, isTrue);
    });

    test('M2 wrong state (active) → failed mentioning both states', () {
      final a =
          approve(
                waitingManual(extra: {ConvergenceFields.state: 'active'}),
              ).primary
              as FailedAction;
      expect(a.message, contains('waiting_manual'));
      expect(a.message, contains('active'));
    });

    test('M3 terminated/no_convergence → failed (not idempotent)', () {
      final f = waitingManual(
        extra: {
          ConvergenceFields.state: 'terminated',
          ConvergenceFields.terminalReason: 'no_convergence',
        },
      );
      expect(approve(f).primary, isA<FailedAction>());
    });

    test('M4 terminated/approved → idempotent no-op (no event)', () {
      final f = waitingManual(
        extra: {
          ConvergenceFields.state: 'terminated',
          ConvergenceFields.terminalReason: 'approved',
          ConvergenceFields.terminalActor: 'operator:bob',
        },
      );
      final a = approve(f).primary as SkippedAction;
      expect(a.reason, SkipReason.alreadyApproved);
      expect(a.wire, 'approved'); // wire is the idempotent success
    });

    test('M5 write ordering: terminal writes before state; commit last; '
        'terminated emitted before close', () {
      final a = approve(waitingManual()).primary as ApprovedAction;
      final tw = a.terminalWrites;
      // terminal_reason and terminal_actor precede state.
      final reasonIdx = tw.indexWhere(
        (w) => w.key == ConvergenceFields.terminalReason,
      );
      final actorIdx = tw.indexWhere(
        (w) => w.key == ConvergenceFields.terminalActor,
      );
      final stateIdx = tw.indexWhere((w) => w.key == ConvergenceFields.state);
      expect(reasonIdx < stateIdx, isTrue);
      expect(actorIdx < stateIdx, isTrue);
      // last_processed re-written to its own prior value, LAST.
      expect(a.commitWrite!.key, ConvergenceFields.lastProcessedWisp);
      expect(a.commitWrite!.value, 'wisp-iter-1');
    });

    test('M6 event payloads: prior_state waiting_manual, new_state '
        'terminated, operator actor', () {
      final a = approve(waitingManual()).primary as ApprovedAction;
      expect(a.events!.priorState, ConvergenceState.waitingManual);
      expect(a.events!.eventWispId, 'wisp-iter-1');
    });

    test('G-APPROVE-1 — active_wisp present overrides last_processed for '
        'the event wisp (manual.go:51-57)', () {
      // active_wisp set to an open wisp-iter-2; event wisp = active_wisp.
      final f = waitingManual(
        includeDefaultWisp: false,
        wisps: [
          wispChild('root-1', 1),
          wispChild('root-1', 2, status: BeadStatus.inProgress),
        ],
        extra: {ConvergenceFields.activeWisp: 'wisp-iter-2'},
      );
      final a = approve(f).primary as ApprovedAction;
      expect(a.events!.eventWispId, 'wisp-iter-2');
    });

    test('G-APPROVE-2 — empty last_processed_wisp skips the final commit '
        'write (manual.go:105-109)', () {
      final f = waitingManual(extra: {ConvergenceFields.lastProcessedWisp: ''});
      final a = approve(f).primary as ApprovedAction;
      expect(a.commitWrite, isNull);
    });
  });

  // ===========================================================================
  // IterateHandler (manual.go:124-217) — M7-M14
  // ===========================================================================
  group('M7-M14 IterateHandler (T9)', () {
    test(
      'M7 happy path → iterate, NEXT iteration, active, no dedup marker',
      () {
        final a = iterate(waitingManual()).primary as IterateAction;
        expect(a.wire, 'iterate');
        expect(a.path, IteratePath.operatorIterate);
        expect(a.iteration, 2); // derived 1 + 1
        expect(a.pour.idempotencyKey, 'converge:root-1:iter:2');
        // Operator path writes NO last_processed_wisp and NO pending clear.
        final w = a.postPourWrites('wisp-2');
        expect(
          w.any((m) => m.key == ConvergenceFields.lastProcessedWisp),
          isFalse,
        );
        expect(a.clearsPendingNextWisp, isFalse);
        // It does NOT activate (manual.go has no ActivateWisp).
        expect(a.activatesWisp, isFalse);
        // state→active, waiting_reason cleared.
        expect(
          w.any(
            (m) =>
                m.key == ConvergenceFields.state &&
                m.value == ConvergenceState.active.wire,
          ),
          isTrue,
        );
        expect(
          w.any(
            (m) => m.key == ConvergenceFields.waitingReason && m.value == '',
          ),
          isTrue,
        );
      },
    );

    test('M8 wrong state active → failed (waiting_manual)', () {
      final a =
          iterate(
                waitingManual(extra: {ConvergenceFields.state: 'active'}),
              ).primary
              as FailedAction;
      expect(a.message, contains('waiting_manual'));
    });

    test(
      'M9 terminated → failed (iterate has NO idempotent terminal path)',
      () {
        expect(
          iterate(
            waitingManual(extra: {ConvergenceFields.state: 'terminated'}),
          ).primary,
          isA<FailedAction>(),
        );
      },
    );

    test('M10 at max iterations (derived count >= max) → failed', () {
      final a =
          iterate(
                waitingManual(extra: {ConvergenceFields.maxIterations: '1'}),
              ).primary
              as FailedAction;
      expect(a.message, contains('max iterations'));
      expect(a.message, contains('(1/1)'));
    });

    test('M11 clears verdict scoped to last_processed (manual.go:180)', () {
      final f = waitingManual(
        extra: {
          ConvergenceFields.agentVerdict: 'block',
          ConvergenceFields.agentVerdictWisp: 'wisp-iter-1',
        },
      );
      final a = iterate(f).primary as IterateAction;
      expect(a.clearVerdict, isTrue);
      // Operator clears AFTER the pour (in postPourWrites, not preWrites).
      expect(a.preWrites, isEmpty);
      final w = a.postPourWrites('wisp-2');
      expect(w.first.key, ConvergenceFields.agentVerdict);
    });

    test('M12 preserves verdict scoped to a DIFFERENT wisp', () {
      final f = waitingManual(
        extra: {
          ConvergenceFields.agentVerdict: 'approve',
          ConvergenceFields.agentVerdictWisp: 'wisp-other',
        },
      );
      final a = iterate(f).primary as IterateAction;
      expect(a.clearVerdict, isFalse);
    });

    test('M13 event: manual_iterate uses NEW iteration; wisp_id is the PRIOR '
        'wisp, next_wisp_id the new (manual.go:207-208)', () {
      final a = iterate(waitingManual()).primary as IterateAction;
      expect(a.events!.priorState, ConvergenceState.waitingManual);
      expect(a.events!.eventWispId, 'wisp-iter-1'); // prior wisp
    });
  });

  // ===========================================================================
  // StopHandler (manual.go:241-445) — M15-M21 + gaps
  // ===========================================================================
  group('M15-M21 StopHandler (T11)', () {
    test('M15 stop from waiting_manual → stopped', () {
      final a = stop(waitingManual()).primary as StoppedAction;
      expect(a.wire, 'stopped');
      expect(a.totalIterations, 1);
      expect(a.actor, 'operator:alice');
      expect(a.closeReason, CloseReasons.manualStop);
    });

    test('M16 stop from active (no active_wisp → no drain/force-close)', () {
      final f = waitingManual(extra: {ConvergenceFields.state: 'active'});
      expect(stop(f).primary, isA<StoppedAction>());
    });

    test('M17 terminated/approved → failed (lists all three valid states)', () {
      final f = waitingManual(
        extra: {
          ConvergenceFields.state: 'terminated',
          ConvergenceFields.terminalReason: 'approved',
        },
      );
      final a = stop(f).primary as FailedAction;
      expect(a.message, contains('active'));
      expect(a.message, contains('waiting_manual'));
      expect(a.message, contains('waiting_trigger'));
    });

    test('M18 terminated/stopped → idempotent no-op (no event)', () {
      final f = waitingManual(
        extra: {
          ConvergenceFields.state: 'terminated',
          ConvergenceFields.terminalReason: 'stopped',
          ConvergenceFields.terminalActor: 'operator:bob',
        },
      );
      final a = stop(f).primary as SkippedAction;
      expect(a.reason, SkipReason.alreadyStopped);
      expect(a.wire, 'stopped');
    });

    test('M19 write ordering: unconditional verdict clear, terminal writes '
        'before state, last_processed LAST', () {
      final a = stop(waitingManual()).primary as StoppedAction;
      final w = a.orderedWrites;
      // Verdict cleared FIRST, unconditionally.
      expect(w[0].key, ConvergenceFields.agentVerdict);
      expect(w[1].key, ConvergenceFields.agentVerdictWisp);
      final reasonIdx = w.indexWhere(
        (m) => m.key == ConvergenceFields.terminalReason,
      );
      final stateIdx = w.indexWhere((m) => m.key == ConvergenceFields.state);
      expect(reasonIdx < stateIdx, isTrue);
      expect(a.commitWrite!.key, ConvergenceFields.lastProcessedWisp);
    });

    test('M21 prior_state reflects the actual pre-stop state (active), not '
        'hardcoded waiting_manual (manual.go:420-426)', () {
      final f = waitingManual(extra: {ConvergenceFields.state: 'active'});
      final a = stop(f).primary as StoppedAction;
      expect(a.events!.priorState, ConvergenceState.active);
    });

    test(
      'G-STOP-3 force-close: open active wisp → forceCloseWispId set, '
      'last_processed repoints to it, count includes it (manual.go:430-434)',
      () {
        final f = waitingManual(
          includeDefaultWisp: false,
          wisps: [
            wispChild('root-1', 1),
            wispChild('root-1', 2, status: BeadStatus.inProgress),
          ],
          extra: {
            ConvergenceFields.state: 'active',
            ConvergenceFields.activeWisp: 'wisp-iter-2',
          },
        );
        final a = stop(f).primary as StoppedAction;
        expect(a.forceCloseWispId, 'wisp-iter-2');
        expect(a.lastProcessedWisp, 'wisp-iter-2');
        // count: 1 closed + 1 force-closed.
        expect(a.totalIterations, 2);
      },
    );

    test(
      'A19 — G-STOP-4: stop from waiting_trigger is VALID (manual.go:258)',
      () {
        final f = waitingTrigger();
        expect(stop(f).primary, isA<StoppedAction>());
      },
    );

    test('G-STOP-5 — dangling active_wisp recovers a replacement before '
        'force-close (manual.go:276-286, 322-331 → recoverCurrentActiveWisp; '
        'TestStopHandler_MissingActiveWisp_RecoversReplacementBeforeForceClose '
        'stop_test.go:307-334)', () {
      // active_wisp points at an iter-2 wisp that is GONE from the snapshot
      // (the dangling case gc recovers from). A replacement open wisp lives
      // at the successor key converge:root-1:iter:2. Recovery finds it by
      // last_processed(iter-1)+1, force-closes it, repoints last_processed.
      final f = waitingManual(
        includeDefaultWisp: false,
        wisps: [
          wispChild('root-1', 1),
          wispChild(
            'root-1',
            2,
            id: 'wisp-replacement',
            status: BeadStatus.inProgress,
          ),
        ],
        extra: {
          ConvergenceFields.state: 'active',
          // Pointer set to a bead absent from the snapshot ⇒ dangling.
          ConvergenceFields.activeWisp: 'wisp-iter-2-deleted',
          ConvergenceFields.lastProcessedWisp: 'wisp-iter-1',
        },
      );
      final a = stop(f).primary as StoppedAction;
      expect(a.forceCloseWispId, 'wisp-replacement');
      expect(a.lastProcessedWisp, 'wisp-replacement');
      // 1 already-closed child + the force-closed replacement.
      expect(a.totalIterations, 2);
      // Event wisp is the recovered active wisp, not last_processed.
      expect(a.events!.eventWispId, 'wisp-replacement');
    });

    test('G-STOP-6 — dangling active_wisp with no recoverable replacement → '
        'plain stop, no force-close (recoverCurrentActiveWisp found=false, '
        'manual.go:285-286)', () {
      // Pointer dangles and the successor key has no child ⇒ recovery
      // yields nothing; stop proceeds with no force-close.
      final f = waitingManual(
        extra: {
          ConvergenceFields.state: 'active',
          ConvergenceFields.activeWisp: 'wisp-iter-2-deleted',
          ConvergenceFields.lastProcessedWisp: 'wisp-iter-1',
        },
      );
      final a = stop(f).primary as StoppedAction;
      expect(a.forceCloseWispId, isNull);
      expect(a.lastProcessedWisp, 'wisp-iter-1');
      expect(a.totalIterations, 1);
    });

    test(
      'G-STOP-7 — dangling active_wisp + recovered CLOSED replacement drains '
      'first (manual.go:272-314 inline drain over the recovered wisp)',
      () {
        // Recovery resolves to a CLOSED iter-2 replacement that is still
        // unprocessed (last_processed at iter-1) ⇒ gc drains it inline. The
        // split reducer emits the drain pipeline + requeue(postDrain:true).
        final f = waitingManual(
          includeDefaultWisp: false,
          wisps: [
            wispChild('root-1', 1),
            wispChild('root-1', 2, id: 'wisp-replacement'),
          ],
          extra: {
            ConvergenceFields.state: 'active',
            ConvergenceFields.activeWisp: 'wisp-iter-2-deleted',
            ConvergenceFields.lastProcessedWisp: 'wisp-iter-1',
            ConvergenceFields.gateMode: 'manual',
          },
        );
        final r = stop(f);
        final last = r.actions.last as RequeueAction;
        expect((last.event as OperatorStopEvent).postDrain, isTrue);
        // The drain reduces the recovered closed wisp (manual gate ⇒
        // waiting_manual) before the requeue.
        expect(r.actions.whereType<WaitingManualAction>(), hasLength(1));
      },
    );
  });

  // ===========================================================================
  // The operator-stop INLINE DRAIN (manual.go:272-314) — A19 carrier protocol
  // ===========================================================================
  group('A19 operator-stop drain → wispClosed pipeline + requeue', () {
    test('closed-but-unprocessed active wisp → emits the drain (wispClosed) '
        'pipeline, then requeue(operatorStop postDrain:true) LAST', () {
      // active_wisp closed (iter-2) but last_processed still at iter-1.
      final f = waitingManual(
        includeDefaultWisp: false,
        wisps: [wispChild('root-1', 1), wispChild('root-1', 2)],
        extra: {
          ConvergenceFields.state: 'active',
          ConvergenceFields.activeWisp: 'wisp-iter-2',
          ConvergenceFields.lastProcessedWisp: 'wisp-iter-1',
          ConvergenceFields.gateMode: 'manual',
        },
      );
      final r = stop(f);
      // LAST action is the requeue carrier.
      final last = r.actions.last as RequeueAction;
      final event = last.event as OperatorStopEvent;
      expect(event.postDrain, isTrue);
      expect(event.user, 'alice');
      expect(last.wire, isNull);
      // The drain pipeline precedes it — a wispClosed reduction of iter-2
      // (manual gate ⇒ waiting_manual).
      expect(r.actions.whereType<WaitingManualAction>(), hasLength(1));
    });

    test('postDrain re-entry resolving drainTerminated: stop over a '
        'terminated/non-stopped loop with postDrain → skipped(drainTerminated) '
        '(manual.go:303-308)', () {
      final f = waitingManual(
        extra: {
          ConvergenceFields.state: 'terminated',
          ConvergenceFields.terminalReason: 'approved',
        },
      );
      final a = stop(f, postDrain: true).primary as SkippedAction;
      expect(a.reason, SkipReason.drainTerminated);
      expect(a.wire, 'stopped');
    });

    test('the SAME terminated/non-stopped shape with postDrain:false is a '
        'FRESH stop → failed error path (manual.go:258-263)', () {
      final f = waitingManual(
        extra: {
          ConvergenceFields.state: 'terminated',
          ConvergenceFields.terminalReason: 'approved',
        },
      );
      final a = stop(f).primary as FailedAction;
      expect(a.message, contains('terminated'));
    });

    test(
      'terminated/stopped collapses to alreadyStopped for BOTH flag values',
      () {
        final f = waitingManual(
          extra: {
            ConvergenceFields.state: 'terminated',
            ConvergenceFields.terminalReason: 'stopped',
          },
        );
        expect(
          (stop(f).primary as SkippedAction).reason,
          SkipReason.alreadyStopped,
        );
        expect(
          (stop(f, postDrain: true).primary as SkippedAction).reason,
          SkipReason.alreadyStopped,
        );
      },
    );
  });

  // ===========================================================================
  // Trigger (trigger.go) — TR1-TR8
  // ===========================================================================
  group('TR2/TR5 trigger advance (T10, trigger.go:129-180)', () {
    ReduceResult advance(
      ({Convergence convergence, GraphSnapshot snapshot}) f,
      int nextIteration,
    ) => ConvergenceReducer.reduce(
      f.convergence,
      ReducerEvent.triggerPassed(
        convergenceBeadId: 'root-1',
        nextIteration: nextIteration,
      ),
      f.snapshot,
    );

    test('TR2 entry pours the first wisp: iterate, iteration 1, NEW key, '
        'iteration counter WRITTEN, controller actor', () {
      // F2: waiting_trigger, iteration 0, no children → next = 1.
      final a = advance(waitingTrigger(), 1).primary as IterateAction;
      expect(a.iteration, 1);
      expect(a.path, IteratePath.triggerAdvance);
      expect(a.pour.idempotencyKey, 'converge:root-1:iter:1');
      // trigger advance DOES write convergence.iteration (unlike manual iterate).
      final w = a.postPourWrites('wisp-1');
      expect(w.first.key, ConvergenceFields.iteration);
      expect(w.first.value, '1');
      // state→active is LAST (no dedup marker, no waiting_reason).
      expect(w.last.key, ConvergenceFields.state);
      expect(w.last.value, ConvergenceState.active.wire);
      // event: entry wisp_id is null (no prior wisp).
      expect(a.events!.eventWispId, isNull);
      expect(a.events!.priorState, ConvergenceState.waitingTrigger);
    });

    test('TR5 mid-loop advance: 1 closed child + last_processed → iteration 2, '
        'key iter:2', () {
      final f = waitingTrigger(
        extra: {
          ConvergenceFields.iteration: '1',
          ConvergenceFields.lastProcessedWisp: 'wisp-iter-1',
        },
        wisps: [wispChild('root-1', 1)],
      );
      final a = advance(f, 2).primary as IterateAction;
      expect(a.iteration, 2);
      expect(a.pour.idempotencyKey, 'converge:root-1:iter:2');
      // mid-loop wisp_id = last_processed.
      expect(a.events!.eventWispId, 'wisp-iter-1');
    });

    test('TR6 advance over a non-waiting_trigger loop → skipped '
        '(trigger.go:58-61)', () {
      final f = waitingTrigger(extra: {ConvergenceFields.state: 'active'});
      final a = advance(f, 1).primary as SkippedAction;
      expect(a.reason, SkipReason.notWaitingTrigger);
    });

    test(
      'TR7 max guard: next > max (>0) → failed loudly (trigger.go:89-91)',
      () {
        final f = waitingTrigger(
          extra: {
            ConvergenceFields.maxIterations: '1',
            ConvergenceFields.iteration: '1',
            ConvergenceFields.lastProcessedWisp: 'wisp-iter-1',
          },
          wisps: [wispChild('root-1', 1)],
        );
        final a = advance(f, 2).primary as FailedAction;
        expect(a.message, contains('exceeds max_iterations'));
      },
    );

    test('TR7 boundary — max 0/absent DISABLES the guard (maxIter > 0)', () {
      final f = waitingTrigger(extra: {ConvergenceFields.maxIterations: '0'});
      // next=99 with max 0 → guard disabled, advance proceeds.
      expect(advance(f, 99).primary, isA<IterateAction>());
    });
  });

  group('TR8 wisp-closed on a trigger-gated loop → waiting_trigger (T6)', () {
    test('cached fail outcome + trigger=event → waiting_trigger, NO next pour, '
        'last_processed LAST (handler.go:619-628)', () {
      // F4-equivalent: active, replay fail, trigger=event.
      final f = baseline(
        extra: {
          ...replay('fail'),
          ConvergenceFields.trigger: 'event',
          ConvergenceFields.triggerCondition: '/some/trigger/check',
        },
      );
      final r = ConvergenceReducer.reduce(
        f.convergence,
        const ReducerEvent.wispClosed(
          convergenceBeadId: 'root-1',
          wispId: 'wisp-iter-1',
        ),
        f.snapshot,
      );
      // No speculative pour for trigger-gated loops.
      expect(r.actions.whereType<PourSpeculativeAction>(), isEmpty);
      final a = r.primary as WaitingTriggerAction;
      expect(a.wire, 'waiting_trigger');
      final w = a.orderedWrites;
      // active_wisp='' → state=waiting_trigger → last_processed LAST.
      expect(w.last.key, ConvergenceFields.lastProcessedWisp);
      expect(w.last.value, 'wisp-iter-1');
      expect(a.events!.priorState, isNull); // waiting_trigger payload action
    });
  });
}
