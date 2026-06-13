// Conformance suite — transliterated from
// gascity/internal/convergence/reconcile_test.go per the inventory in
// doc/port/conformance-reconcile-tests.md (ADR-0003 Decision 7). Each test
// cites its conformance number + the Go line of the behavior it pins.
//
// The recovery pass is PURE: it emits the recovery effects gc would perform as
// data (RecoveryOutcome.recovery / .replayActions / .error), never touching a
// store. The two replay paths (Path 1a closed-adopt, Path 4 closed-unprocessed)
// reuse ConvergenceReducer.reduce — so their transition plans are asserted as
// ReconcilerActions, exactly the actions Track G would actuate.

import 'package:grid_controller/grid_controller.dart';
import 'package:grid_reconciler/grid_reconciler.dart';
import 'package:test/test.dart';

import 'support/recovery_fakes.dart';

void main() {
  // ===========================================================================
  // Path 3t — waiting_trigger (reconcile.go:376-385)
  // ===========================================================================
  group('Path 3t — waiting_trigger', () {
    test('1. WaitingTrigger_NoAction — trigger holds are left alone '
        '(reconcile.go:382-384)', () {
      final root = convergenceBead(
        'root-1',
        metadata: meta(
          state: 'waiting_trigger',
          extra: {
            ConvergenceFields.trigger: 'event',
            ConvergenceFields.triggerCondition: '/scripts/check',
          },
        ),
      );
      final o = reconcileOne(root);
      expect(o.action, RecoveryActionLabel.noAction);
      expect(o.action.wire, 'no_action');
      expect(o.recovery, isNull);
      expect(o.replayActions, isEmpty);
      // State preserved: the pass writes nothing.
      expect(o.hasError, isFalse);
    });

    test('2. WaitingTrigger_CompletesInterruptedStop — terminal_reason set → '
        'completeTerminalTransition (reconcile.go:379-381)', () {
      final root = convergenceBead(
        'root-1',
        metadata: meta(
          state: 'waiting_trigger',
          extra: {ConvergenceFields.terminalReason: 'stopped'},
        ),
      );
      final o = reconcileOne(root);
      expect(o.action, RecoveryActionLabel.completedTerminal);
      final a = o.recovery! as CompleteTerminalAction;
      // terminal_actor backfilled to recovery (none set).
      expect(a.backfillActor, isTrue);
      // A convergence.terminated event, recovery=true.
      expect(a.event.recovery, isTrue);
      expect(a.event.eventType, 'convergence.terminated');
      expect(a.event.terminalReason.wire, 'stopped');
      // state ← terminated (snapshot state was waiting_trigger).
      expect(a.writesState, isTrue);
      // close reason ≥20 chars, the fixed reconcile literal.
      expect(
        a.closeReason,
        'convergence reconcile: terminated-state bead closed',
      );
    });
  });

  // ===========================================================================
  // Path 1a — missing/empty state (reconcile.go:111-206)
  // ===========================================================================
  group('Path 1a — missing/empty state', () {
    test('3. MissingState_NoWisps_PoursFirst — key converge:root-1:iter:1, '
        'iteration "0", state LAST (reconcile.go:186-203)', () {
      final root = convergenceBead(
        'root-1',
        metadata: meta(
          extra: {
            ConvergenceFields.target: 'the-target',
            // a var. key to prove ExtractVars threads into the pour.
            'var.depth': '2',
          },
        ),
      );
      final report = ConvergenceRecovery.reconcile(rootSnap(root));
      expect(report.scanned, 1);
      expect(report.recovered, 1);
      expect(report.errors, 0);

      final o = report.outcomes.single;
      expect(o.action, RecoveryActionLabel.pouredWisp);
      expect(o.hasError, isFalse);

      final a = o.recovery! as PourFirstWispAction;
      expect(a.pour.idempotencyKey, 'converge:root-1:iter:1');
      expect(a.pour.iteration, 1);
      expect(a.pour.formula, 'test-formula');
      expect(a.pour.vars, {'depth': '2'});
      expect(a.pour.speculative, isFalse); // visible pour (reconcile.go:178).

      // ⚠ ordering (reconcile.go:186-203): active_wisp → iteration "0" → state.
      final writes = a.postPourWrites('wisp-1');
      expect(writes.map((w) => w.key).toList(), [
        ConvergenceFields.activeWisp,
        ConvergenceFields.iteration,
        ConvergenceFields.state,
      ]);
      expect(writes[0].value, 'wisp-1');
      expect(writes[1].value, '0'); // ⚠ "0" not "1" (counts CLOSED, Inv 4).
      expect(writes[2].value, 'active');
    });

    test('4. MissingState_WispExists_Adopts — open iter-1 wisp adopted, '
        'iteration "0", no replay (reconcile.go:133-157)', () {
      final root = convergenceBead('root-1', metadata: meta());
      final existing = wispBead(
        'existing-wisp',
        key: idempotencyKey('root-1', 1),
        status: BeadStatus.open,
      );
      final o = reconcileOne(root, children: [existing]);
      expect(o.action, RecoveryActionLabel.adoptedWisp);
      expect(o.hasError, isFalse);

      final a = o.recovery! as AdoptWispAction;
      expect(a.wispId, 'existing-wisp');
      expect(a.adoptedClosed, isFalse);
      // ⚠ ordering: active_wisp → iteration (0, wisp open) → state.
      final writes = a.orderedWrites;
      expect(writes.map((w) => w.key).toList(), [
        ConvergenceFields.activeWisp,
        ConvergenceFields.iteration,
        ConvergenceFields.state,
      ]);
      expect(writes[0].value, 'existing-wisp');
      expect(writes[1].value, '0'); // open ⇒ 0.
      expect(writes[2].value, 'active');
      // Open adopt does NOT replay (reconcile.go:161 gates on closed).
      expect(o.replayActions, isEmpty);
    });

    test('G3. MissingState_WispExists_ClosedAdopts — closed iter-1 wisp: '
        'iteration "1" + REPLAY (reconcile.go:140-168, ADR-0000 A22)', () {
      // Closed iter-1 wisp with a cached gate outcome so the replayed
      // HandleWispClosed drives a deterministic transition (pass → approved).
      final root = convergenceBead(
        'root-1',
        metadata: meta(
          extra: {
            ConvergenceFields.gateMode: 'condition',
            ConvergenceFields.gateCondition: '/gate/check',
            ConvergenceFields.gateTimeout: '60s',
            ConvergenceFields.gateOutcomeWisp: 'existing-wisp',
            ConvergenceFields.gateOutcome: 'pass',
            ConvergenceFields.gateRetryCount: '0',
          },
        ),
      );
      final existing = wisp('root-1', 1, id: 'existing-wisp');
      final o = reconcileOne(root, children: [existing]);
      expect(o.action, RecoveryActionLabel.adoptedWisp);

      final a = o.recovery! as AdoptWispAction;
      expect(a.adoptedClosed, isTrue);
      // ⚠ closed ⇒ iteration "1" (reconcile.go:142-145).
      expect(a.orderedWrites[1].value, '1');

      // The replay reuses the reducer: a cached pass terminates as approved.
      expect(o.replayActions, isNotEmpty);
      final terminal = o.replayActions.whereType<ApprovedAction>().single;
      expect(terminal.path, TerminalPath.handlerWispClosed);
      expect(terminal.lastProcessedWisp, 'existing-wisp');
    });
  });

  // ===========================================================================
  // Path 1b — creating (reconcile.go:210-236)
  // ===========================================================================
  group('Path 1b — creating', () {
    test(
      '5. StateCreating_TerminatesPartialCreation — reason/actor/state→close '
      'in order, NO event (reconcile.go:211-234)',
      () {
        final root = convergenceBead(
          'root-1',
          metadata: {ConvergenceFields.state: 'creating'},
        );
        final report = ConvergenceRecovery.reconcile(rootSnap(root));
        expect(report.recovered, 1);
        expect(report.errors, 0);

        final o = report.outcomes.single;
        expect(o.action, RecoveryActionLabel.completedTerminal);
        expect(o.hasError, isFalse);

        final a = o.recovery! as PartialCreationTerminateAction;
        // ⚠ ordering: terminal_reason → terminal_actor → state, then close.
        final writes = a.orderedWrites;
        expect(writes.map((w) => w.key).toList(), [
          ConvergenceFields.terminalReason,
          ConvergenceFields.terminalActor,
          ConvergenceFields.state,
        ]);
        expect(writes[0].value, 'partial_creation');
        expect(writes[1].value, 'recovery');
        expect(writes[2].value, 'terminated');
        expect(
          a.closeReason,
          'convergence reconcile: terminated-state bead closed',
        );
      },
    );
  });

  // ===========================================================================
  // Path 2 — terminated but not closed (reconcile.go:240-296)
  // ===========================================================================
  group('Path 2 — terminated but not closed', () {
    test('6. TerminatedNotClosed_CompletesClosure — emit terminated (rig=prod) '
        'BEFORE close (reconcile.go:255-295)', () {
      final root = convergenceBead(
        'root-1',
        metadata: meta(
          state: 'terminated',
          extra: {
            ConvergenceFields.terminalReason: 'approved',
            ConvergenceFields.terminalActor: 'controller',
            ConvergenceFields.rig: 'prod',
          },
        ),
      );
      final o = reconcileOne(root, children: [wisp('root-1', 1)]);
      expect(o.action, RecoveryActionLabel.completedTerminal);
      expect(o.hasError, isFalse);

      final a = o.recovery! as CompleteTerminalAction;
      expect(a.event.eventType, 'convergence.terminated');
      expect(a.event.convergenceBeadId, 'root-1');
      expect(a.event.recovery, isTrue);
      expect(a.event.rig, 'prod');
      // Payload values (reconcile.go:266-283).
      expect(a.event.terminalReason.wire, 'approved'); // from metadata.
      expect(a.event.totalIterations, 1); // one closed child.
      expect(a.event.actor, 'controller');
      // G10 — cumulative duration ≈600000 ms for one closed wisp.
      expect(a.event.cumulativeDuration.inMilliseconds, closedWispDurationMs);
      // Path 2 backfill is a no-op (actor already set).
      expect(a.backfillActor, isFalse);
      // Path 2 writes NO state and NO last_processed_wisp (spec §6).
      expect(a.writesState, isFalse);
      expect(a.stateWrite, isNull);
      expect(a.commitWrite, isNull);
    });

    test(
      '7. TerminatedNotClosed_BackfillsActor — no actor → backfill "recovery" '
      '(reconcile.go:604-609)',
      () {
        final root = convergenceBead(
          'root-1',
          metadata: meta(
            state: 'terminated',
            extra: {ConvergenceFields.terminalReason: 'stopped'},
          ),
        );
        final o = reconcileOne(root);
        expect(o.action, RecoveryActionLabel.completedTerminal);
        final a = o.recovery! as CompleteTerminalAction;
        expect(a.backfillActor, isTrue);
        expect(
          a.actorBackfillWrite,
          const MetadataWrite(
            key: ConvergenceFields.terminalActor,
            value: 'recovery',
          ),
        );
        // The payload actor also falls back to recovery (snapshot value empty).
        expect(a.event.actor, 'recovery');
      },
    );

    test('8. TerminatedAlreadyClosed_NoAction — closed root → no_action '
        '(reconcile.go:249-252)', () {
      // The scan drops closed roots, so drive reconcileBead directly (the
      // mid-tick backstop entry, spec §2.2).
      final root = convergenceBead(
        'root-1',
        status: BeadStatus.closed,
        metadata: meta(state: 'terminated'),
      );
      final p = project(root);
      final o = ConvergenceRecovery.reconcileBead(p.convergence, p.snapshot);
      expect(o.action, RecoveryActionLabel.noAction);
      expect(o.recovery, isNull);
    });

    test('G7. TerminatedNotClosed_EmptyReasonDefault — empty terminal_reason '
        '→ payload no_convergence (reconcile.go:266-268)', () {
      final root = convergenceBead(
        'root-1',
        metadata: meta(
          state: 'terminated',
          extra: {ConvergenceFields.terminalActor: 'controller'},
        ),
      );
      final o = reconcileOne(root);
      final a = o.recovery! as CompleteTerminalAction;
      expect(a.event.terminalReason.wire, 'no_convergence');
    });

    test('G9. terminated event ID is converge:<bead>:terminated '
        '(events.go EventIDTerminated)', () {
      final root = convergenceBead(
        'root-1',
        metadata: meta(
          state: 'terminated',
          extra: {ConvergenceFields.terminalReason: 'approved'},
        ),
      );
      final a = reconcileOne(root).recovery! as CompleteTerminalAction;
      expect(a.event.eventId, 'converge:root-1:terminated');
    });
  });

  // ===========================================================================
  // Path 3 — waiting_manual (reconcile.go:300-372)
  // ===========================================================================
  group('Path 3 — waiting_manual', () {
    test('9. WaitingManual_TerminalReasonSet_CompletesTerminal — Sub-path A: '
        'state→terminated, close, lpw LAST (reconcile.go:545-599)', () {
      final root = convergenceBead(
        'root-1',
        metadata: meta(
          state: 'waiting_manual',
          extra: {
            ConvergenceFields.waitingReason: 'manual',
            ConvergenceFields.terminalReason: 'stopped',
            ConvergenceFields.terminalActor: 'operator:alice',
          },
        ),
      );
      final o = reconcileOne(root, children: [wisp('root-1', 1)]);
      expect(o.action, RecoveryActionLabel.completedTerminal);

      final a = o.recovery! as CompleteTerminalAction;
      expect(a.event.eventType, 'convergence.terminated');
      expect(a.event.eventId, 'converge:root-1:terminated');
      expect(a.event.terminalReason.wire, 'stopped'); // verbatim, no default.
      expect(a.event.actor, 'operator:alice');
      // state ← terminated (snapshot state was waiting_manual ≠ terminated).
      expect(a.writesState, isTrue);
      // ⚠ last_processed_wisp ← highest closed wisp (wisp-iter-1), LAST.
      expect(a.lastProcessedWisp, 'wisp-iter-1');
      expect(
        a.commitWrite,
        const MetadataWrite(
          key: ConvergenceFields.lastProcessedWisp,
          value: 'wisp-iter-1',
        ),
      );
    });

    test('10. WaitingManual_GenuineHold_NoStateChange — re-emit waiting_manual '
        '(recovery=true, rig=prod), no_action (reconcile.go:310-346)', () {
      final root = convergenceBead(
        'root-1',
        metadata: meta(
          state: 'waiting_manual',
          extra: {
            ConvergenceFields.waitingReason: 'manual',
            ConvergenceFields.lastProcessedWisp: 'wisp-iter-1',
            ConvergenceFields.gateMode: 'manual',
            ConvergenceFields.iteration: '1',
            ConvergenceFields.rig: 'prod',
          },
        ),
      );
      final o = reconcileOne(root, children: [wisp('root-1', 1)]);
      // Marker already points at the highest closed wisp → no repair.
      expect(o.action, RecoveryActionLabel.noAction);

      final a = o.recovery! as WaitingManualRecoveryActionData;
      // The event fires even though the action is no_action (spec §7.2).
      final e = a.event;
      expect(e.eventType, 'convergence.waiting_manual');
      expect(e.recovery, isTrue);
      expect(e.rig, 'prod');
      // G11 — payload field fidelity (reconcile.go:315-324).
      expect(e.eventId, 'converge:root-1:iter:1:waiting_manual');
      expect(e.iteration, 1);
      expect(e.wispId, 'wisp-iter-1'); // from last_processed_wisp.
      expect(e.gateMode, 'manual');
      expect(e.reason.wire, 'manual');
      expect(a.repairWrite, isNull); // no repair.
    });

    test('11. WaitingManual_GenuineHold_RepairsLastProcessedWisp — stale lpw '
        '→ repaired to highest closed (reconcile.go:336-345)', () {
      final root = convergenceBead(
        'root-1',
        metadata: meta(
          state: 'waiting_manual',
          extra: {
            ConvergenceFields.waitingReason: 'manual',
            ConvergenceFields.lastProcessedWisp: 'wisp-0',
            // ⚠ no convergence.iteration → decodes to 0.
          },
        ),
      );
      // closed wisp-0 (key iter:0) and closed wisp-1 (key iter:1).
      final w0 = wisp('root-1', 0, id: 'wisp-0');
      final w1 = wisp('root-1', 1, id: 'wisp-1');
      final o = reconcileOne(root, children: [w0, w1]);
      expect(o.action, RecoveryActionLabel.repairedState);

      final a = o.recovery! as WaitingManualRecoveryActionData;
      expect(a.repairLastProcessedWisp, 'wisp-1'); // highest closed.
      expect(
        a.repairWrite,
        const MetadataWrite(
          key: ConvergenceFields.lastProcessedWisp,
          value: 'wisp-1',
        ),
      );
      // ⚠ iteration decodes to 0 → event id carries :iter:0:.
      expect(a.event.eventId, 'converge:root-1:iter:0:waiting_manual');
      // wisp_id is the PRE-repair value (spec §11).
      expect(a.event.wispId, 'wisp-0');
    });

    test('G1. WaitingManual_OrphanedState_RepairsWaitingReason — no waiting/'
        'terminal reason, closed wisps → waiting_reason=manual '
        '(reconcile.go:359-368)', () {
      final root = convergenceBead(
        'root-1',
        metadata: meta(state: 'waiting_manual'),
      );
      final o = reconcileOne(root, children: [wisp('root-1', 1)]);
      expect(o.action, RecoveryActionLabel.repairedState);
      final a = o.recovery! as RepairWaitingReasonAction;
      expect(
        a.write,
        const MetadataWrite(
          key: ConvergenceFields.waitingReason,
          value: 'manual',
        ),
      );
    });

    test('G1b. WaitingManual_OrphanedState_NoClosedWisps_NoAction '
        '(reconcile.go:371)', () {
      final root = convergenceBead(
        'root-1',
        metadata: meta(state: 'waiting_manual'),
      );
      // Only an OPEN wisp → highestClosedWisp finds nothing.
      final o = reconcileOne(
        root,
        children: [wisp('root-1', 1, status: BeadStatus.open)],
      );
      expect(o.action, RecoveryActionLabel.noAction);
      expect(o.recovery, isNull);
    });

    test('Sub-path precedence — terminal_reason checked BEFORE waiting_reason '
        '(reconcile.go:306, spec trap 8)', () {
      final root = convergenceBead(
        'root-1',
        metadata: meta(
          state: 'waiting_manual',
          extra: {
            ConvergenceFields.waitingReason: 'manual',
            ConvergenceFields.terminalReason: 'stopped',
          },
        ),
      );
      final o = reconcileOne(root, children: [wisp('root-1', 1)]);
      // Terminates — does not take the genuine-hold path.
      expect(o.action, RecoveryActionLabel.completedTerminal);
      expect(o.recovery, isA<CompleteTerminalAction>());
    });
  });

  // ===========================================================================
  // Path 4 — active (reconcile.go:389-539)
  // ===========================================================================
  group('Path 4 — active', () {
    Bead activeRoot(Map<String, dynamic> extra) => convergenceBead(
      'root-1',
      metadata: meta(
        state: 'active',
        extra: {
          ConvergenceFields.iteration: '1',
          ConvergenceFields.gateMode: 'condition',
          ConvergenceFields.gateCondition: '/gate/check',
          ConvergenceFields.gateTimeout: '60s',
          ConvergenceFields.gateTimeoutAction: 'iterate',
          ...extra,
        },
      ),
    );

    test('12. Active_ClosedUnprocessedWisp_Replays — cached fail+iter<max → '
        'replay iterates (reconcile.go:455-464, ADR-0000 A22)', () {
      final root = activeRoot({
        ConvergenceFields.activeWisp: 'wisp-iter-1',
        ConvergenceFields.gateOutcomeWisp: 'wisp-iter-1',
        ConvergenceFields.gateOutcome: 'fail',
        ConvergenceFields.gateRetryCount: '0',
      });
      final o = reconcileOne(root, children: [wisp('root-1', 1)]);
      expect(o.action, RecoveryActionLabel.repairedState);
      expect(o.hasError, isFalse);
      expect(o.recovery, isNull); // resolved pointer, no repair write.

      // The replay reuses the reducer: cached fail, iter 1 < max 5 → iterate.
      final iterate = o.replayActions.whereType<IterateAction>().single;
      expect(iterate.path, IteratePath.wispClosed);
      expect(iterate.closedWispId, 'wisp-iter-1');
      // A new wisp is poured (the next iteration) — proves the chain advanced.
      expect(iterate.pour.idempotencyKey, 'converge:root-1:iter:2');
    });

    test('13. Active_MissingActiveWisp_ReconstructsChain — stale pointer → '
        'derive-and-pour iter:2 (reconcile.go:416-538)', () {
      final root = activeRoot({
        // points at a bead that does not exist in the snapshot.
        ConvergenceFields.activeWisp: 'wisp-iter-2',
        ConvergenceFields.lastProcessedWisp: 'wisp-iter-1',
      });
      // closed iter-1 only; no iter-2 bead anywhere.
      final o = reconcileOne(root, children: [wisp('root-1', 1)]);
      expect(o.hasError, isFalse);
      expect(
        o.action,
        anyOf(RecoveryActionLabel.pouredWisp, RecoveryActionLabel.adoptedWisp),
      );
      final a = o.recovery! as PourNextWispAction;
      // derive: closed=1 → next=2 → pours since no pending/existing.
      expect(a.poured, isTrue);
      expect(a.pour!.idempotencyKey, 'converge:root-1:iter:2');
      expect(a.pour!.iteration, 2);
      expect(a.activates, isTrue);
      // ⚠ ordering (reconcile.go:530-536): active_wisp → clear pending.
      final writes = a.postWrites('wisp-new');
      expect(writes.map((w) => w.key).toList(), [
        ConvergenceFields.activeWisp,
        ConvergenceFields.pendingNextWisp,
      ]);
      expect(writes[0].value, 'wisp-new');
      expect(writes[1].value, ''); // cleared.
    });

    test(
      '14. Active_MissingActiveWisp_ReplaysRecoveredClosedReplacement — '
      'recover by next-key, repair pointer, replay (reconcile.go:427-464)',
      () {
        final root = activeRoot({
          ConvergenceFields.activeWisp: 'wisp-iter-2', // gone.
          ConvergenceFields.lastProcessedWisp: 'wisp-iter-1',
          ConvergenceFields.gateOutcomeWisp: 'wisp-replacement',
          ConvergenceFields.gateOutcome: 'pass',
          ConvergenceFields.gateRetryCount: '0',
        });
        final replacement = wisp('root-1', 2, id: 'wisp-replacement');
        final o = reconcileOne(
          root,
          children: [wisp('root-1', 1), replacement],
        );
        expect(o.hasError, isFalse);
        expect(o.action, RecoveryActionLabel.repairedState);
        // The recovered pointer is persisted BEFORE the status switch (trap 11).
        final repair = o.recovery! as RepairActiveWispAction;
        expect(repair.wispId, 'wisp-replacement');
        expect(
          repair.write,
          const MetadataWrite(
            key: ConvergenceFields.activeWisp,
            value: 'wisp-replacement',
          ),
        );
        // Replay: cached pass → terminal approved, lpw=wisp-replacement.
        final terminal = o.replayActions.whereType<ApprovedAction>().single;
        expect(terminal.lastProcessedWisp, 'wisp-replacement');
      },
    );

    test(
      '15. Active_MissingActiveWisp_RepairsOpenReplacementMetadata — '
      'in_progress replacement adopted, nothing else (reconcile.go:436-443)',
      () {
        final root = activeRoot({
          ConvergenceFields.activeWisp: 'wisp-iter-2', // gone.
          ConvergenceFields.lastProcessedWisp: 'wisp-iter-1',
        });
        final replacement = wisp(
          'root-1',
          2,
          id: 'wisp-replacement',
          status: BeadStatus.inProgress,
        );
        final o = reconcileOne(
          root,
          children: [wisp('root-1', 1), replacement],
        );
        expect(o.hasError, isFalse);
        expect(o.action, RecoveryActionLabel.repairedState);
        final repair = o.recovery! as RepairActiveWispAction;
        expect(repair.wispId, 'wisp-replacement');
        // open/in_progress recovered ⇒ no replay.
        expect(o.replayActions, isEmpty);
      },
    );

    // 16. Active_StoreErrorReadingActiveWisp_ReportsError
    //     (reconcile.go:401-408, conformance spec test 16 — must).
    //
    // gc's test 16 injects a GENERIC (non-NotFound) GetBead failure on the
    // active_wisp read and asserts: Error != nil, Action == "no_action", no
    // mutation. Its load-bearing assertion (spec:409-410) is the NotFound-vs-
    // transient branch — ONLY NotFound triggers the recovery chain of tests
    // 13-15; any other store error aborts with no_action + error + no write.
    //
    // The grid recovery pass is PURE: active_wisp is read off the already-
    // decoded projection, so the transient-failure arm (reconcile.go:402-408)
    // has no analog — there is no fallible store read to fail (recovery_pass.
    // dart:334-337). What test 16 truly pins — that a dangling active_wisp is
    // resolved by the NotFound/recovery branch and NEVER spuriously mutates or
    // errors — is the branch SELECTION, and that IS snapshot-derivable. These
    // two cases pin it directly, so the divergence is tested, not merely argued
    // in a source comment. The transient-store-read contract itself (a live
    // GetBead failure → no_action + error + no mutation) belongs to the Track G
    // actuation seam, which supplies the live reads gc's Store did inline; it
    // is not reproducible — and so not assertable — at this pure layer.
    test(
      '16. Active_DanglingActiveWisp_TakesRecoveryBranch_NeverTransientError — '
      'the only reachable arm is NotFound/recovery (reconcile.go:401-425)',
      () {
        // A dangling pointer WITH a recoverable replacement (anchored off
        // last_processed_wisp + 1) → recovery chain, NOT an abort.
        final recoverable = activeRoot({
          ConvergenceFields.activeWisp: 'wisp-iter-2', // gone.
          ConvergenceFields.lastProcessedWisp: 'wisp-iter-1',
        });
        final replacement = wisp(
          'root-1',
          2,
          id: 'wisp-replacement',
          status: BeadStatus.inProgress,
        );
        final recovered = reconcileOne(
          recoverable,
          children: [wisp('root-1', 1), replacement],
        );
        // The recovery branch ran (a repair was planned) and NO error was
        // surfaced — the transient-abort arm (no_action + error) is unreachable.
        expect(recovered.hasError, isFalse);
        expect(recovered.action, RecoveryActionLabel.repairedState);
        expect(recovered.recovery, isA<RepairActiveWispAction>());

        // A dangling pointer with NOTHING to recover → falls through to derive-
        // and-pour (reconcile.go:416-421), again no_action's-error arm avoided.
        final stale = activeRoot({
          ConvergenceFields.activeWisp: 'wisp-iter-2', // gone, no replacement.
          ConvergenceFields.lastProcessedWisp: 'wisp-iter-1',
        });
        final fellThrough = reconcileOne(stale, children: [wisp('root-1', 1)]);
        expect(fellThrough.hasError, isFalse);
        expect(fellThrough.action, RecoveryActionLabel.pouredWisp);
        expect(fellThrough.recovery, isA<PourNextWispAction>());
        // No outcome on the pure path carries the gc-transient-error message;
        // the only snapshot-derivable error is the unknown-state branch.
        expect(recovered.error, isNull);
        expect(fellThrough.error, isNull);
      },
    );

    test('17. Active_OpenWisp_NoAction — resolved in_progress wisp → no_action '
        '(reconcile.go:436-443)', () {
      final root = activeRoot({ConvergenceFields.activeWisp: 'wisp-iter-1'});
      final o = reconcileOne(
        root,
        children: [wisp('root-1', 1, status: BeadStatus.inProgress)],
      );
      expect(o.action, RecoveryActionLabel.noAction);
      expect(o.recovery, isNull);
      expect(o.replayActions, isEmpty);
    });

    test('18. Active_TerminalReasonSet_CompletesStop — Sub-path A completes '
        'the stop (reconcile.go:392-394)', () {
      final root = activeRoot({
        ConvergenceFields.terminalReason: 'stopped',
        ConvergenceFields.terminalActor: 'operator:bob',
      });
      final o = reconcileOne(root, children: [wisp('root-1', 1)]);
      expect(o.action, RecoveryActionLabel.completedTerminal);
      final a = o.recovery! as CompleteTerminalAction;
      expect(a.event.eventType, 'convergence.terminated');
      expect(a.writesState, isTrue); // active ≠ terminated.
      expect(a.lastProcessedWisp, 'wisp-iter-1'); // highest closed, LAST.
    });

    test('19. Active_EmptyActiveWisp_PoursNext — derive closed=1 → pour iter:2 '
        '(reconcile.go:477-538)', () {
      final root = activeRoot({ConvergenceFields.activeWisp: ''});
      final o = reconcileOne(root, children: [wisp('root-1', 1)]);
      expect(o.action, RecoveryActionLabel.pouredWisp);
      final a = o.recovery! as PourNextWispAction;
      expect(a.poured, isTrue);
      expect(a.pour!.idempotencyKey, 'converge:root-1:iter:2');
      // G8 — ActivateWisp is called on the Path-4 pour.
      expect(a.activates, isTrue);
    });

    test('20. Active_EmptyActiveWisp_AdoptsExisting — existing iter:2 wisp '
        'adopted via FindByIdempotencyKey (reconcile.go:496-505)', () {
      final root = activeRoot({ConvergenceFields.activeWisp: ''});
      final existing = wisp(
        'root-1',
        2,
        id: 'wisp-2',
        status: BeadStatus.inProgress,
      );
      final o = reconcileOne(root, children: [wisp('root-1', 1), existing]);
      expect(o.action, RecoveryActionLabel.adoptedWisp);
      final a = o.recovery! as PourNextWispAction;
      expect(a.poured, isFalse);
      expect(a.adoptWispId, 'wisp-2');
      expect(a.activates, isTrue);
    });

    test('G6. Active_EmptyActiveWisp_AdoptsValidPending — pending_next_wisp '
        'takes priority over key lookup (reconcile.go:492)', () {
      final root = activeRoot({
        ConvergenceFields.activeWisp: '',
        ConvergenceFields.pendingNextWisp: 'wisp-2',
      });
      final pending = wisp(
        'root-1',
        2,
        id: 'wisp-2',
        status: BeadStatus.inProgress,
      );
      final o = reconcileOne(root, children: [wisp('root-1', 1), pending]);
      expect(o.action, RecoveryActionLabel.adoptedWisp);
      final a = o.recovery! as PourNextWispAction;
      expect(a.adoptWispId, 'wisp-2');
    });

    test(
      'G6b. Active_EmptyActiveWisp_InvalidPending_FallsThrough — closed '
      'pending is not valid → pour (reconcile.go:492 + handler.go:935-945)',
      () {
        final root = activeRoot({
          ConvergenceFields.activeWisp: '',
          // pending points at a CLOSED wisp → invalid → fall through.
          ConvergenceFields.pendingNextWisp: 'wisp-2-closed',
        });
        final o = reconcileOne(
          root,
          children: [
            wisp('root-1', 1),
            wisp('root-1', 2, id: 'wisp-2-closed'),
          ],
        );
        // closed=2 (iter-1 + iter-2) → next=3, pours since no valid pending.
        expect(o.action, RecoveryActionLabel.pouredWisp);
        final a = o.recovery! as PourNextWispAction;
        expect(a.pour!.idempotencyKey, 'converge:root-1:iter:3');
      },
    );

    test('21. Active_AlreadyProcessed_NoAction — lpw == active_wisp == closed '
        'wisp → no_action (reconcile.go:447-453, Inv 1+2)', () {
      final root = activeRoot({
        ConvergenceFields.activeWisp: 'wisp-iter-1',
        ConvergenceFields.lastProcessedWisp: 'wisp-iter-1',
      });
      final o = reconcileOne(root, children: [wisp('root-1', 1)]);
      expect(o.action, RecoveryActionLabel.noAction);
      expect(o.replayActions, isEmpty);
    });

    test('G4. Active wisp with unexpected status → no_action + error '
        '(reconcile.go:466-470)', () {
      // BeadStatus is an OPEN extension type, so a wisp can carry a status
      // outside {open, in_progress, closed} — gc\'s switch default arm.
      final root = activeRoot({ConvergenceFields.activeWisp: 'wisp-iter-1'});
      final weird = wispBead(
        'wisp-iter-1',
        key: idempotencyKey('root-1', 1),
        status: const BeadStatus('quarantined'),
      );
      final o = reconcileOne(root, children: [weird]);
      expect(o.action, RecoveryActionLabel.noAction);
      expect(o.hasError, isTrue);
      expect(
        o.error,
        'active wisp "wisp-iter-1" has unexpected status "quarantined"',
      );
    });
  });

  // ===========================================================================
  // Multi-bead / reporting / events
  // ===========================================================================
  group('Multi-bead / reporting / events', () {
    test('22. MultipleBeads_ContinuesOnError — input order preserved, errored '
        'bead not Recovered (reconcile.go:48-56)', () {
      // bead-1: terminated-not-closed (recovers); bead-2: unknown state (the
      // grid\'s deterministic error — gc\'s bead-2 was store-absent, which a
      // pure pass cannot model; the load-bearing behavior is continue-on-error
      // + input-order Details + errored≠Recovered, see decisions[]).
      final b1 = convergenceBead(
        'bead-1',
        metadata: meta(
          state: 'terminated',
          extra: {ConvergenceFields.terminalReason: 'approved'},
        ),
      );
      final b2 = convergenceBead('bead-2', metadata: meta(state: 'bogus'));
      final b3 = convergenceBead(
        'bead-3',
        status: BeadStatus.closed,
        metadata: meta(state: 'terminated'),
      );
      // bead-3 is closed → dropped by the scan; drive all three through
      // reconcileBead in input order to mirror ReconcileBeads exactly.
      final snapshot = snap([b1, b2, b3], deps: const []);
      final p1 = Convergence.project(b1, beadsById: snapshot.beadsById);
      final p2 = Convergence.project(b2, beadsById: snapshot.beadsById);
      final p3 = Convergence.project(b3, beadsById: snapshot.beadsById);
      final outcomes = [
        ConvergenceRecovery.reconcileBead(
          (p1 as ProjectionOk<Convergence>).value,
          snapshot,
        ),
        ConvergenceRecovery.reconcileBead(
          (p2 as ProjectionOk<Convergence>).value,
          snapshot,
        ),
        ConvergenceRecovery.reconcileBead(
          (p3 as ProjectionOk<Convergence>).value,
          snapshot,
        ),
      ];
      final report = RecoveryReport(outcomes);
      expect(report.scanned, 3);
      expect(report.errors, 1);
      expect(report.recovered, 1);
      expect(report.outcomes.length, 3);
      expect(report.outcomes[0].action, RecoveryActionLabel.completedTerminal);
      expect(report.outcomes[1].hasError, isTrue);
      expect(report.outcomes[2].action, RecoveryActionLabel.noAction);
    });

    test('G2. Unknown state value → no_action + error '
        '"unknown convergence state \\"bogus\\"" (reconcile.go:101-106)', () {
      final root = convergenceBead('root-1', metadata: meta(state: 'bogus'));
      final o = reconcileOne(root);
      expect(o.action, RecoveryActionLabel.noAction);
      expect(o.hasError, isTrue);
      expect(o.error, 'unknown convergence state "bogus"');
    });

    test('23. RecoveryEventsHaveRecoveryFlag — every emitted recovery event '
        'carries recovery=true (reconcile.go:685-690)', () {
      final root = convergenceBead(
        'root-1',
        metadata: meta(
          state: 'terminated',
          extra: {ConvergenceFields.terminalReason: 'approved'},
        ),
      );
      final o = reconcileOne(root, children: [wisp('root-1', 1)]);
      final events = <RecoveryEvent>[
        if (o.recovery case CompleteTerminalAction(:final event)) event,
        if (o.recovery case WaitingManualRecoveryActionData(:final event))
          event,
      ];
      expect(events, isNotEmpty);
      expect(events.every((e) => e.recovery), isTrue);
    });

    test('27. EmptyList_NoOp — empty snapshot → scanned 0, recovered 0, no '
        'outcomes (reconcile.go:929-945)', () {
      final report = ConvergenceRecovery.reconcile(
        snap(const [], deps: const []),
      );
      expect(report.scanned, 0);
      expect(report.recovered, 0);
      expect(report.errors, 0);
      expect(report.outcomes, isEmpty);
    });
  });

  // ===========================================================================
  // Pure helper functions (24-26) — exercised through Convergence (Track A)
  // ===========================================================================
  group('Pure helpers (deriveIterationFromChildren / highestClosedWisp)', () {
    test('24. deriveIterationFromChildren — count prefix+closed = 2 '
        '(reconcile.go:614-623)', () {
      final root = convergenceBead('root-1', metadata: meta(state: 'active'));
      final children = [
        wisp('root-1', 1), // closed iter:1
        wisp('root-1', 2), // closed iter:2
        wisp('root-1', 3, status: BeadStatus.inProgress), // open iter:3
        wispKeyed('other', key: 'unrelated-key', rootId: 'root-1'),
      ];
      final p = project(root, children: children);
      // closedWispCount counts prefix+closed regardless of parseability.
      expect(p.convergence.closedWispCount, 2);
    });

    test('25. highestClosedWisp — highest CLOSED iteration wins; open ignored '
        '(reconcile.go:627-652)', () {
      final root = convergenceBead('root-1', metadata: meta(state: 'active'));
      final children = [
        wisp('root-1', 1),
        wisp('root-1', 3, id: 'w3'),
        wisp('root-1', 2),
        wisp('root-1', 4, id: 'w4', status: BeadStatus.inProgress),
      ];
      final p = project(root, children: children);
      expect(p.convergence.highestClosedWisp?.id, 'w3');
      expect(p.convergence.highestClosedWisp?.iteration, 3);
    });

    test('26. highestClosedWisp_NoneFound — only open → null '
        '(reconcile.go:918-927)', () {
      final root = convergenceBead('root-1', metadata: meta(state: 'active'));
      final p = project(
        root,
        children: [wisp('root-1', 1, status: BeadStatus.inProgress)],
      );
      expect(p.convergence.highestClosedWisp, isNull);
    });
  });

  // ===========================================================================
  // Scan / candidate set
  // ===========================================================================
  group('Scan — candidate set (cmd/gc/convergence_tick.go:569, spec §2.1)', () {
    test('non-closed convergence beads only, in id order (spec trap 18)', () {
      final beads = [
        convergenceBead('root-b', metadata: meta(state: 'creating')),
        convergenceBead('root-a', metadata: meta(state: 'creating')),
        // closed convergence → excluded.
        convergenceBead(
          'root-closed',
          status: BeadStatus.closed,
          metadata: meta(state: 'terminated'),
        ),
        // non-convergence bead → excluded.
        Bead(
          id: 'plain',
          title: 'plain',
          issueType: IssueType.task,
          status: BeadStatus.open,
        ),
      ];
      final report = ConvergenceRecovery.reconcile(snap(beads));
      expect(report.scanned, 2);
      // id order: root-a before root-b.
      expect(report.outcomes.map((o) => o.convergenceBeadId).toList(), [
        'root-a',
        'root-b',
      ]);
    });
  });
}
