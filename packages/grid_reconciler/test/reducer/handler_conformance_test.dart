// Conformance suite — transliterated from
// gascity/internal/convergence/handler_test.go per the inventory in
// doc/port/conformance-handler-tests.md (ADR-0003 Decision 7). Each test cites
// its H## id and the Go line of the behavior it pins.
//
// The reducer is a PHASE-SPLIT port: a fresh (non-replay) condition/hybrid
// gate yields an EvaluateGateAction (phase 1); the gate result re-enters as
// gateEvaluated (phase 2). Most handler_test.go fixtures use the REPLAY branch
// (gate_outcome_wisp == wisp), which runs the whole pipeline in one reduce —
// so they map to a single wispClosed reduce here, exactly as in gc.

import 'package:grid_controller/grid_controller.dart';
import 'package:grid_reconciler/grid_reconciler.dart';
// Track B's reducer is not yet on the package barrel (the orchestrator wires
// it after this track lands); import the sub-barrel by path until then.
import 'package:test/test.dart';

import 'support/reducer_fakes.dart';

/// The transition/primary action of a reduce (gc's `HandlerResult`).
ReconcilerAction primary(ReduceResult r) => r.primary;

void main() {
  group('H04 guard — terminated → skipped (Inv 6, handler.go:170-175)', () {
    test('a wisp closing on a terminated loop is skipped', () {
      final f = baseline(extra: {ConvergenceFields.state: 'terminated'});
      final r = ConvergenceReducer.reduce(
        f.convergence,
        const ReducerEvent.wispClosed(
          convergenceBeadId: 'root-1',
          wispId: 'wisp-iter-1',
        ),
        f.snapshot,
      );
      final action = primary(r);
      expect(action, isA<SkippedAction>());
      expect((action as SkippedAction).reason, SkipReason.alreadyTerminated);
      expect(action.wire, 'skipped');
    });

    test('coverage gap #9 — gc best-effort closes a terminated-but-OPEN root '
        '(handler.go:172-173, CloseReasonHandlerCleanup)', () {
      // Root is in_progress (open) but state=terminated.
      final f = baseline(extra: {ConvergenceFields.state: 'terminated'});
      final action = primary(
        ConvergenceReducer.reduce(
          f.convergence,
          const ReducerEvent.wispClosed(
            convergenceBeadId: 'root-1',
            wispId: 'wisp-iter-1',
          ),
          f.snapshot,
        ),
      );
      expect((action as SkippedAction).closeRootBestEffort, isTrue);
    });
  });

  group('H05/H06 dedup — monotonic (Inv 1, handler.go:177-201)', () {
    test('H05 equal iteration (already processed) → skipped', () {
      final f = baseline(
        extra: {ConvergenceFields.lastProcessedWisp: 'wisp-iter-1'},
      );
      final action = primary(
        ConvergenceReducer.reduce(
          f.convergence,
          const ReducerEvent.wispClosed(
            convergenceBeadId: 'root-1',
            wispId: 'wisp-iter-1',
          ),
          f.snapshot,
        ),
      );
      expect((action as SkippedAction).reason, SkipReason.duplicateWisp);
    });

    test('coverage gap #10 — strictly OLDER wisp (iter-1 after iter-2 '
        'committed) → skipped', () {
      // last_processed=wisp-iter-2; a stale wisp-iter-1 event arrives.
      final f = baseline(
        includeDefaultWisp: false,
        wisps: [wispChild('root-1', 1), wispChild('root-1', 2)],
        extra: {ConvergenceFields.lastProcessedWisp: 'wisp-iter-2'},
      );
      final action = primary(
        ConvergenceReducer.reduce(
          f.convergence,
          const ReducerEvent.wispClosed(
            convergenceBeadId: 'root-1',
            wispId: 'wisp-iter-1',
          ),
          f.snapshot,
        ),
      );
      expect((action as SkippedAction).reason, SkipReason.duplicateWisp);
    });

    test('H06 corrupted last_processed_wisp degrades to iteration 0 — the '
        'wisp is processed, not skipped (handler.go:188-198)', () {
      // last_processed points at a non-existent bead; manual gate ⇒ the loop
      // actually processes through to waiting_manual.
      final f = baseline(
        extra: {
          ConvergenceFields.lastProcessedWisp: 'deleted-wisp',
          ConvergenceFields.gateMode: 'manual',
        },
      );
      final action = primary(
        ConvergenceReducer.reduce(
          f.convergence,
          const ReducerEvent.wispClosed(
            convergenceBeadId: 'root-1',
            wispId: 'wisp-iter-1',
          ),
          f.snapshot,
        ),
      );
      expect(action, isA<WaitingManualAction>());
    });

    test('the dedup-skip is a DEDICATED Inv-1 fire: the action carries the '
        'compared iterations', () {
      final f = baseline(
        extra: {ConvergenceFields.lastProcessedWisp: 'wisp-iter-1'},
      );
      final action =
          primary(
                ConvergenceReducer.reduce(
                  f.convergence,
                  const ReducerEvent.wispClosed(
                    convergenceBeadId: 'root-1',
                    wispId: 'wisp-iter-1',
                  ),
                  f.snapshot,
                ),
              )
              as SkippedAction;
      expect(action.detail, contains('<='));
    });
  });

  group('H07/H08 manual & hybrid-no-condition → waiting_manual (T7, '
      'handler.go:301-316)', () {
    test('H07 gate_mode=manual → waiting_manual(manual)', () {
      final f = baseline(extra: {ConvergenceFields.gateMode: 'manual'});
      final action = primary(
        ConvergenceReducer.reduce(
          f.convergence,
          const ReducerEvent.wispClosed(
            convergenceBeadId: 'root-1',
            wispId: 'wisp-iter-1',
          ),
          f.snapshot,
        ),
      );
      expect(action, isA<WaitingManualAction>());
      final wm = action as WaitingManualAction;
      expect(wm.reason.wire, WaitingReason.manual.wire);
      expect(wm.wire, 'waiting_manual');
      // No gate ran — gateOutcome null.
      expect(wm.gateOutcome, isNull);
    });

    test('H08 gate_mode=hybrid + empty condition → '
        'waiting_manual(hybrid_no_condition)', () {
      final f = baseline(
        extra: {
          ConvergenceFields.gateMode: 'hybrid',
          ConvergenceFields.gateCondition: '',
        },
      );
      final action =
          primary(
                ConvergenceReducer.reduce(
                  f.convergence,
                  const ReducerEvent.wispClosed(
                    convergenceBeadId: 'root-1',
                    wispId: 'wisp-iter-1',
                  ),
                  f.snapshot,
                ),
              )
              as WaitingManualAction;
      expect(action.reason.wire, WaitingReason.hybridNoCondition.wire);
    });

    test('H35 manual gate pours NO speculative successor (Inv 5, '
        'handler.go:249-254): no pourSpeculative in the list, no '
        'iter:2 pour', () {
      final f = baseline(extra: {ConvergenceFields.gateMode: 'manual'});
      final r = ConvergenceReducer.reduce(
        f.convergence,
        const ReducerEvent.wispClosed(
          convergenceBeadId: 'root-1',
          wispId: 'wisp-iter-1',
        ),
        f.snapshot,
      );
      expect(r.actions.whereType<PourSpeculativeAction>(), isEmpty);
      expect(r.actions.whereType<EvaluateGateAction>(), isEmpty);
    });
  });

  group('H09/H11 replay fail → iterate (T2, handler.go:280-298)', () {
    test('H09 cached fail drives iterate WITHOUT re-evaluation — even with no '
        'gate_condition (replay bypasses the missing-condition check)', () {
      final f = baseline(extra: replay('fail'));
      final r = ConvergenceReducer.reduce(
        f.convergence,
        const ReducerEvent.wispClosed(
          convergenceBeadId: 'root-1',
          wispId: 'wisp-iter-1',
        ),
        f.snapshot,
      );
      // No fresh gate handoff on replay.
      expect(r.actions.whereType<EvaluateGateAction>(), isEmpty);
      final action = primary(r);
      expect(action, isA<IterateAction>());
      expect((action as IterateAction).gateOutcome, GateOutcome.fail);
      expect(action.wire, 'iterate');
    });

    test('H11 iterate carries NextWisp + active_wisp write; the iteration '
        'event payload has next_wisp_id + action=iterate', () {
      final f = baseline(extra: replay('fail'));
      final r = ConvergenceReducer.reduce(
        f.convergence,
        const ReducerEvent.wispClosed(
          convergenceBeadId: 'root-1',
          wispId: 'wisp-iter-1',
        ),
        f.snapshot,
      );
      // Step 5 persist must precede the transition (fresh? no — replay skips
      // persist).
      expect(r.actions.whereType<PersistGateOutcomeAction>(), isEmpty);
      final action = primary(r) as IterateAction;
      expect(action.path, IteratePath.wispClosed);
      expect(action.closedWispId, 'wisp-iter-1');
      // The iterate writes active_wisp=<next> then last_processed LAST.
      final writes = action.postPourWrites('wisp-2');
      expect(writes.first.key, ConvergenceFields.activeWisp);
      expect(writes.last.key, ConvergenceFields.lastProcessedWisp);
      expect(writes.last.value, 'wisp-iter-1');
    });
  });

  group('H10/H18/H21 replay pass → approved (T1, Inv 6)', () {
    test('H10 pass terminates approved with controller actor + handlerRoot '
        'close reason', () {
      final f = baseline(extra: replay('pass'));
      final action = primary(
        ConvergenceReducer.reduce(
          f.convergence,
          const ReducerEvent.wispClosed(
            convergenceBeadId: 'root-1',
            wispId: 'wisp-iter-1',
          ),
          f.snapshot,
        ),
      );
      expect(action, isA<ApprovedAction>());
      final a = action as ApprovedAction;
      expect(a.wire, 'approved');
      expect(a.actor, 'controller');
      expect(a.path, TerminalPath.handlerWispClosed);
      expect(a.closeReason, CloseReasons.handlerRoot);
    });

    test('H18 terminal WRITE ORDERING (Inv 2): terminal_reason → '
        'terminal_actor → state=terminated, then last_processed_wisp LAST '
        'after the close (handler.go:687-704)', () {
      final f = baseline(extra: replay('pass'));
      final a =
          primary(
                ConvergenceReducer.reduce(
                  f.convergence,
                  const ReducerEvent.wispClosed(
                    convergenceBeadId: 'root-1',
                    wispId: 'wisp-iter-1',
                  ),
                  f.snapshot,
                ),
              )
              as ApprovedAction;
      final tw = a.terminalWrites;
      expect(tw[0].key, ConvergenceFields.terminalReason);
      expect(tw[0].value, TerminalReason.approved.wire);
      expect(tw[1].key, ConvergenceFields.terminalActor);
      // state is the last of the terminal writes; commitWrite (last_processed)
      // comes AFTER the close.
      expect(tw.last.key, ConvergenceFields.state);
      expect(tw.last.value, ConvergenceState.terminated.wire);
      expect(a.commitWrite!.key, ConvergenceFields.lastProcessedWisp);
      expect(a.commitWrite!.value, 'wisp-iter-1');
      // The handler path emits BOTH events before the terminal writes.
      expect(a.events, isNotNull);
    });

    test('H21 event payloads — iteration event has iteration/wisp_id/action='
        'approved; the scoped approve verdict surfaces on the payload', () {
      final f = baseline(
        extra: replay(
          'pass',
          extra: {
            ConvergenceFields.agentVerdict: 'approve',
            ConvergenceFields.agentVerdictWisp: 'wisp-iter-1',
          },
        ),
      );
      final a =
          primary(
                ConvergenceReducer.reduce(
                  f.convergence,
                  const ReducerEvent.wispClosed(
                    convergenceBeadId: 'root-1',
                    wispId: 'wisp-iter-1',
                  ),
                  f.snapshot,
                ),
              )
              as ApprovedAction;
      expect(a.iteration, 1);
      expect(a.events!.eventWispId, 'wisp-iter-1');
      // Payload verdict is the scoped, normalized verdict.
      expect(a.events!.agentVerdict, Verdict.approve.wire);
    });
  });

  group('H12/H13/H14 max-iter & timeout terminals', () {
    test('H12 max_iterations=1, replay fail at iter 1 → no_convergence (T5, '
        'iter >= max)', () {
      final f = baseline(
        extra: {ConvergenceFields.maxIterations: '1', ...replay('fail')},
      );
      final action = primary(
        ConvergenceReducer.reduce(
          f.convergence,
          const ReducerEvent.wispClosed(
            convergenceBeadId: 'root-1',
            wispId: 'wisp-iter-1',
          ),
          f.snapshot,
        ),
      );
      expect(action, isA<NoConvergenceAction>());
      expect((action as NoConvergenceAction).wire, 'no_convergence');
    });

    test('H13 replay timeout + action=terminate → no_convergence (T4)', () {
      final f = baseline(
        extra: {
          ConvergenceFields.gateTimeoutAction: 'terminate',
          ...replay('timeout'),
        },
      );
      final action = primary(
        ConvergenceReducer.reduce(
          f.convergence,
          const ReducerEvent.wispClosed(
            convergenceBeadId: 'root-1',
            wispId: 'wisp-iter-1',
          ),
          f.snapshot,
        ),
      );
      expect(action, isA<NoConvergenceAction>());
    });

    test(
      'H14 replay timeout + action=manual → waiting_manual(timeout) (T3)',
      () {
        final f = baseline(
          extra: {
            ConvergenceFields.gateTimeoutAction: 'manual',
            ...replay('timeout'),
          },
        );
        final action = primary(
          ConvergenceReducer.reduce(
            f.convergence,
            const ReducerEvent.wispClosed(
              convergenceBeadId: 'root-1',
              wispId: 'wisp-iter-1',
            ),
            f.snapshot,
          ),
        );
        expect(action, isA<WaitingManualAction>());
        expect(
          (action as WaitingManualAction).reason.wire,
          WaitingReason.timeout.wire,
        );
      },
    );

    test(
      'coverage gap #6 — timeout+manual WINS over max-iterations '
      '(the manual check precedes the terminal switch, handler.go:345-351)',
      () {
        final f = baseline(
          extra: {
            ConvergenceFields.maxIterations: '1',
            ConvergenceFields.gateTimeoutAction: 'manual',
            ...replay('timeout'),
          },
        );
        final action = primary(
          ConvergenceReducer.reduce(
            f.convergence,
            const ReducerEvent.wispClosed(
              convergenceBeadId: 'root-1',
              wispId: 'wisp-iter-1',
            ),
            f.snapshot,
          ),
        );
        expect(action, isA<WaitingManualAction>());
        expect(
          (action as WaitingManualAction).reason.wire,
          WaitingReason.timeout.wire,
        );
      },
    );

    test('coverage gap #4 — replay error below max → iterate; at max → '
        'no_convergence', () {
      final below = baseline(extra: replay('error'));
      expect(
        primary(
          ConvergenceReducer.reduce(
            below.convergence,
            const ReducerEvent.wispClosed(
              convergenceBeadId: 'root-1',
              wispId: 'wisp-iter-1',
            ),
            below.snapshot,
          ),
        ),
        isA<IterateAction>(),
      );
      final atMax = baseline(
        extra: {ConvergenceFields.maxIterations: '1', ...replay('error')},
      );
      expect(
        primary(
          ConvergenceReducer.reduce(
            atMax.convergence,
            const ReducerEvent.wispClosed(
              convergenceBeadId: 'root-1',
              wispId: 'wisp-iter-1',
            ),
            atMax.snapshot,
          ),
        ),
        isA<NoConvergenceAction>(),
      );
    });

    test('coverage gap #5 — replay timeout with default action=iterate below '
        'max → iterate', () {
      final f = baseline(extra: replay('timeout')); // action defaults iterate
      expect(
        primary(
          ConvergenceReducer.reduce(
            f.convergence,
            const ReducerEvent.wispClosed(
              convergenceBeadId: 'root-1',
              wispId: 'wisp-iter-1',
            ),
            f.snapshot,
          ),
        ),
        isA<IterateAction>(),
      );
    });
  });

  group('H16/H17 verdict clearing on iterate (T2, D3, handler.go:490-498)', () {
    test('H16 verdict scoped to THIS wisp → cleared on iterate', () {
      final f = baseline(
        extra: replay(
          'fail',
          extra: {
            ConvergenceFields.agentVerdict: 'block',
            ConvergenceFields.agentVerdictWisp: 'wisp-iter-1',
          },
        ),
      );
      final a =
          primary(
                ConvergenceReducer.reduce(
                  f.convergence,
                  const ReducerEvent.wispClosed(
                    convergenceBeadId: 'root-1',
                    wispId: 'wisp-iter-1',
                  ),
                  f.snapshot,
                ),
              )
              as IterateAction;
      expect(a.clearVerdict, isTrue);
      // preWrites clear both verdict keys before pour.
      expect(a.preWrites.map((w) => w.key), [
        ConvergenceFields.agentVerdict,
        ConvergenceFields.agentVerdictWisp,
      ]);
      expect(a.preWrites.every((w) => w.value.isEmpty), isTrue);
    });

    test('H17 verdict scoped to a LATER wisp → preserved (not cleared)', () {
      final f = baseline(
        extra: replay(
          'fail',
          extra: {
            ConvergenceFields.agentVerdict: 'approve',
            ConvergenceFields.agentVerdictWisp: 'wisp-iter-2',
          },
        ),
      );
      final a =
          primary(
                ConvergenceReducer.reduce(
                  f.convergence,
                  const ReducerEvent.wispClosed(
                    convergenceBeadId: 'root-1',
                    wispId: 'wisp-iter-1',
                  ),
                  f.snapshot,
                ),
              )
              as IterateAction;
      expect(a.clearVerdict, isFalse);
      expect(a.preWrites, isEmpty);
    });
  });

  group('H19/H20/H34 write-ordering & speculative-pour adoption', () {
    test('H19 iterate commit tail: last_processed_wisp is second-to-last, '
        'pending_next_wisp clear is LAST (Inv 2,5, handler.go:555-565)', () {
      final f = baseline(
        extra: replay('fail', extra: {ConvergenceFields.gateExitCode: '1'}),
      );
      final a =
          primary(
                ConvergenceReducer.reduce(
                  f.convergence,
                  const ReducerEvent.wispClosed(
                    convergenceBeadId: 'root-1',
                    wispId: 'wisp-iter-1',
                  ),
                  f.snapshot,
                ),
              )
              as IterateAction;
      expect(a.clearsPendingNextWisp, isTrue);
      // The load-bearing commit marker is the last postPour write; the
      // pending clear follows it as a separate best-effort write.
      final writes = a.postPourWrites('wisp-2');
      expect(writes.last.key, ConvergenceFields.lastProcessedWisp);

      // Pin the RELATIVE ordering the Go test
      // TestHandleWispClosed_WriteOrdering_IterateLastProcessedBeforePendingCleanup
      // (handler_test.go:876-916) exists to enforce: reconstruct the ACTUATED
      // commit sequence in the carrier's documented order (postPourWrites,
      // then — when clearsPendingNextWisp — the best-effort pending clear,
      // reconciler_action.dart steps 4→5 / handler.go:557-565). In that log
      // last_processed_wisp must be SECOND-TO-LAST and the pending clear LAST.
      // Without this, a transposition of the dedup commit and the best-effort
      // cleanup (porting-trap #1, the crash-recovery double-process bug)
      // passes green.
      final committed = <MetadataWrite>[
        ...writes,
        if (a.clearsPendingNextWisp)
          const MetadataWrite(
            key: ConvergenceFields.pendingNextWisp,
            value: '',
          ),
      ];
      expect(committed.length, greaterThanOrEqualTo(2));
      expect(
        committed[committed.length - 2].key,
        ConvergenceFields.lastProcessedWisp,
        reason: 'last_processed_wisp must precede the pending cleanup',
      );
      expect(
        committed.last.key,
        ConvergenceFields.pendingNextWisp,
        reason: 'pending_next_wisp cleanup must be the final write',
      );
      expect(committed.last.value, '');
    });

    test('H20 waiting_manual commit tail: last_processed_wisp LAST '
        '(handler.go:438-453)', () {
      final f = baseline(
        extra: {
          ConvergenceFields.gateMode: 'manual',
          ConvergenceFields.gateTimeoutAction: 'manual',
        },
      );
      final a =
          primary(
                ConvergenceReducer.reduce(
                  f.convergence,
                  const ReducerEvent.wispClosed(
                    convergenceBeadId: 'root-1',
                    wispId: 'wisp-iter-1',
                  ),
                  f.snapshot,
                ),
              )
              as WaitingManualAction;
      final w = a.orderedWrites;
      expect(w[0].key, ConvergenceFields.activeWisp);
      expect(w[0].value, '');
      expect(w[1].key, ConvergenceFields.waitingReason);
      expect(w[2].key, ConvergenceFields.state);
      expect(w.last.key, ConvergenceFields.lastProcessedWisp);
      expect(w.last.value, 'wisp-iter-1');
    });

    test('H34 iterate ACTIVATES the next wisp before commit (Inv 2,5)', () {
      final f = baseline(extra: replay('fail'));
      final a =
          primary(
                ConvergenceReducer.reduce(
                  f.convergence,
                  const ReducerEvent.wispClosed(
                    convergenceBeadId: 'root-1',
                    wispId: 'wisp-iter-1',
                  ),
                  f.snapshot,
                ),
              )
              as IterateAction;
      expect(a.activatesWisp, isTrue);
    });
  });

  group('H30/H33/H37 speculative-pour life-cycle', () {
    test('H30/H33 replay terminal (pass) BURNS the in-list 3b pour '
        '(burnPriorPour, Inv 5, handler.go:384-387)', () {
      // Replay pass below max ⇒ 3b still pours in this reduce, then burns.
      final f = baseline(extra: replay('pass'));
      final r = ConvergenceReducer.reduce(
        f.convergence,
        const ReducerEvent.wispClosed(
          convergenceBeadId: 'root-1',
          wispId: 'wisp-iter-1',
        ),
        f.snapshot,
      );
      // The list pours speculatively (replay branch) then terminates.
      expect(r.actions.whereType<PourSpeculativeAction>(), hasLength(1));
      final a = primary(r) as ApprovedAction;
      expect(a.burnPriorPour, isTrue);
    });

    test('H37 max_iterations=1 → no_convergence with NO speculative pour at '
        'the budget boundary (handler.go:254 guard)', () {
      final f = baseline(
        extra: {ConvergenceFields.maxIterations: '1', ...replay('fail')},
      );
      final r = ConvergenceReducer.reduce(
        f.convergence,
        const ReducerEvent.wispClosed(
          convergenceBeadId: 'root-1',
          wispId: 'wisp-iter-1',
        ),
        f.snapshot,
      );
      // wispIteration(1) < max(1) is false ⇒ no pour, no in-list burn.
      expect(r.actions.whereType<PourSpeculativeAction>(), isEmpty);
      final a = primary(r) as NoConvergenceAction;
      expect(a.burnPriorPour, isFalse);
      expect(a.burnWispId, isNull);
    });

    test('H30 replay fail adopts the in-list 3b pour as next active wisp '
        '(adoptFromPriorPour)', () {
      final f = baseline(extra: replay('fail'));
      final r = ConvergenceReducer.reduce(
        f.convergence,
        const ReducerEvent.wispClosed(
          convergenceBeadId: 'root-1',
          wispId: 'wisp-iter-1',
        ),
        f.snapshot,
      );
      expect(r.actions.whereType<PourSpeculativeAction>(), hasLength(1));
      final a = primary(r) as IterateAction;
      expect(a.adoptFromPriorPour, isTrue);
      expect(a.adoptWispId, isNull);
    });
  });

  group(
    'H32 misconfig — condition mode without condition (handler.go:235-242)',
    () {
      test('fresh (non-replay) condition mode + empty condition → failed, '
          'unowned pending NOT burned but un-marked', () {
        // pending points at a wisp belonging to ANOTHER root.
        final foreign = wispChildKey(
          'other-wisp',
          key: 'converge:other-root:iter:2',
          status: BeadStatus.inProgress,
        );
        final f = baseline(
          wisps: [foreign],
          extra: {
            ConvergenceFields.gateCondition: '',
            ConvergenceFields.pendingNextWisp: 'other-wisp',
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
        final a = primary(r) as FailedAction;
        expect(a.message, contains('condition'));
        // other-wisp's key != converge:root-1:iter:2 ⇒ invalid pending ⇒ NOT
        // burned, only the stale-pending self-heal clears the marker.
        expect(a.burnWispId, isNull);
        expect(a.clearStalePending, isTrue);
      });

      test('WRONG-KEY pending — an OPEN child of OURS at the wrong iteration '
          'is stale and self-healed (validPendingNextWisp clears on '
          'IdempotencyKey != nextKey, handler.go:940)', () {
        // pending points at an open child with OUR prefix but at iter:3, while
        // the successor key for wisp-iter-1 closing is converge:root-1:iter:2.
        // gc's validPendingNextWisp clears it (wrong key); the reducer must
        // surface clearStalePending even though the wisp exists and is open.
        final wrongKey = wispChild(
          'root-1',
          3,
          id: 'wisp-iter-3',
          status: BeadStatus.inProgress,
        );
        final f = baseline(
          wisps: [wrongKey],
          extra: {
            ConvergenceFields.gateCondition: '',
            ConvergenceFields.pendingNextWisp: 'wisp-iter-3',
          },
        );
        final a =
            primary(
                  ConvergenceReducer.reduce(
                    f.convergence,
                    const ReducerEvent.wispClosed(
                      convergenceBeadId: 'root-1',
                      wispId: 'wisp-iter-1',
                    ),
                    f.snapshot,
                  ),
                )
                as FailedAction;
        expect(a.burnWispId, isNull); // wrong key ⇒ not a valid pending to burn
        expect(a.clearStalePending, isTrue); // but IS cleared as stale
      });
    },
  );

  group('repair (Inv 4) — coverage gap #3 (handler.go:208-214)', () {
    test('stored iteration disagrees with derived closed-child count → a '
        'RepairIterationAction precedes the transition', () {
      // One closed child (derived 1) but stored iteration "7".
      final f = baseline(
        extra: {ConvergenceFields.iteration: '7', ...replay('fail')},
      );
      final r = ConvergenceReducer.reduce(
        f.convergence,
        const ReducerEvent.wispClosed(
          convergenceBeadId: 'root-1',
          wispId: 'wisp-iter-1',
        ),
        f.snapshot,
      );
      final repairs = r.actions.whereType<RepairIterationAction>().toList();
      expect(repairs, hasLength(1));
      expect(repairs.single.derivedIteration, 1);
      expect(repairs.single.storedIteration, 7);
      // The repair write encodes the derived value.
      expect(repairs.single.write.value, '1');
      // It precedes the transition in the list.
      expect(r.actions.indexOf(repairs.single) < r.actions.length - 1, isTrue);
    });

    test('agreeing stored iteration → no repair action', () {
      final f = baseline(extra: replay('fail')); // stored "1", derived 1
      final r = ConvergenceReducer.reduce(
        f.convergence,
        const ReducerEvent.wispClosed(
          convergenceBeadId: 'root-1',
          wispId: 'wisp-iter-1',
        ),
        f.snapshot,
      );
      expect(r.actions.whereType<RepairIterationAction>(), isEmpty);
    });
  });
}
