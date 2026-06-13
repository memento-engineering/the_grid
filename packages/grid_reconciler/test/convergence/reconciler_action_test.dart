import 'package:grid_reconciler/grid_reconciler.dart';
import 'package:test/test.dart';

/// The action vocabulary is the actuator's contract: each variant's derived
/// write sequence must reproduce gc's exact keys, values, and ORDER —
/// `last_processed_wisp` LAST is the commit point, `gate_outcome_wisp` LAST
/// in gate persistence (ADR-0003 invariant 2).
void main() {
  const pour = WispPour(
    parentBeadId: 'gt-c1',
    formula: 'mol-polish',
    idempotencyKey: 'converge:gt-c1:iter:3',
    iteration: 3,
    vars: {'doc_path': 'docs/x.md'},
    evaluatePrompt: 'judge it',
  );

  group('wire strings (handler.go:120-128)', () {
    test('transition variants match gc HandlerAction values exactly', () {
      expect(
        const ReconcilerAction.iterate(
          convergenceBeadId: 'c',
          iteration: 1,
          pour: pour,
          path: IteratePath.wispClosed,
        ).wire,
        'iterate', // handler.go:121
      );
      expect(
        const ReconcilerAction.approved(
          convergenceBeadId: 'c',
          path: TerminalPath.handlerWispClosed,
          actor: 'controller',
          iteration: 1,
          totalIterations: 1,
          closeReason: CloseReasons.handlerRoot,
        ).wire,
        'approved', // handler.go:122
      );
      expect(
        const ReconcilerAction.noConvergence(
          convergenceBeadId: 'c',
          actor: 'controller',
          iteration: 1,
          totalIterations: 1,
          closeReason: CloseReasons.handlerRoot,
        ).wire,
        'no_convergence', // handler.go:123 — snake_case
      );
      expect(
        const ReconcilerAction.waitingManual(
          convergenceBeadId: 'c',
          closedWispId: 'w',
          iteration: 1,
          reason: WaitingReason.manual,
        ).wire,
        'waiting_manual', // handler.go:124
      );
      expect(
        const ReconcilerAction.waitingTrigger(
          convergenceBeadId: 'c',
          closedWispId: 'w',
          iteration: 1,
        ).wire,
        'waiting_trigger', // handler.go:125
      );
      expect(
        const ReconcilerAction.stopped(
          convergenceBeadId: 'c',
          actor: 'operator:nico',
          totalIterations: 1,
          closeReason: CloseReasons.manualStop,
        ).wire,
        'stopped', // handler.go:126
      );
      expect(
        const ReconcilerAction.skipped(
          convergenceBeadId: 'c',
          reason: SkipReason.duplicateWisp,
        ).wire,
        'skipped', // handler.go:127
      );
    });

    test('sub-transition carriers have NO gc HandlerAction analog', () {
      expect(
        const ReconcilerAction.pourSpeculative(
          convergenceBeadId: 'c',
          pour: pour,
        ).wire,
        isNull,
      );
      expect(
        const ReconcilerAction.evaluateGate(
          convergenceBeadId: 'c',
          wispId: 'w',
          iteration: 2,
          config: GateConfig(
            mode: GateMode.condition,
            condition: 'gates/check.sh',
            timeout: ConvergenceMetadata.defaultGateTimeout,
            timeoutAction: GateTimeoutAction.iterate,
          ),
          env: GateEnvInputs(),
        ).wire,
        isNull,
      );
      expect(
        const ReconcilerAction.persistGateOutcome(
          convergenceBeadId: 'c',
          wispId: 'w',
          result: GateResult(outcomeWire: 'fail'),
        ).wire,
        isNull,
      );
      expect(
        const ReconcilerAction.repairIteration(
          convergenceBeadId: 'c',
          derivedIteration: 3,
        ).wire,
        isNull,
      );
      expect(
        const ReconcilerAction.failed(
          convergenceBeadId: 'c',
          message: 'parsing gate config: boom',
        ).wire,
        isNull,
      );
      expect(
        const ReconcilerAction.requeue(
          event: ReducerEvent.operatorStop(
            convergenceBeadId: 'c',
            user: 'n',
            postDrain: true,
          ),
          reason: 'operator stop deferred behind drain',
        ).wire,
        isNull,
      );
    });

    test('operator no-op skips report gc idempotent-success actions '
        '(manual.go:30-34, 251-255, 303-307)', () {
      expect(
        const SkippedAction(
          convergenceBeadId: 'c',
          reason: SkipReason.alreadyApproved,
        ).wire,
        'approved',
      );
      expect(
        const SkippedAction(
          convergenceBeadId: 'c',
          reason: SkipReason.alreadyStopped,
        ).wire,
        'stopped',
      );
      expect(
        const SkippedAction(
          convergenceBeadId: 'c',
          reason: SkipReason.drainTerminated,
        ).wire,
        'stopped',
      );
      expect(
        const SkippedAction(
          convergenceBeadId: 'c',
          reason: SkipReason.triggerNotSatisfied, // trigger.go:96-99
        ).wire,
        'skipped',
      );
      expect(
        const SkippedAction(
          convergenceBeadId: 'c',
          reason: SkipReason.notWaitingTrigger, // trigger.go:58-61
        ).wire,
        'skipped',
      );
    });

    test('the union is exhaustively switchable over thirteen variants', () {
      const actions = <ReconcilerAction>[
        ReconcilerAction.iterate(
          convergenceBeadId: 'c',
          iteration: 1,
          pour: pour,
          path: IteratePath.wispClosed,
        ),
        ReconcilerAction.approved(
          convergenceBeadId: 'c',
          path: TerminalPath.handlerWispClosed,
          actor: 'a',
          iteration: 1,
          totalIterations: 1,
          closeReason: CloseReasons.handlerRoot,
        ),
        ReconcilerAction.noConvergence(
          convergenceBeadId: 'c',
          actor: 'a',
          iteration: 1,
          totalIterations: 1,
          closeReason: CloseReasons.handlerRoot,
        ),
        ReconcilerAction.waitingManual(
          convergenceBeadId: 'c',
          closedWispId: 'w',
          iteration: 1,
          reason: WaitingReason.manual,
        ),
        ReconcilerAction.waitingTrigger(
          convergenceBeadId: 'c',
          closedWispId: 'w',
          iteration: 1,
        ),
        ReconcilerAction.stopped(
          convergenceBeadId: 'c',
          actor: 'a',
          totalIterations: 1,
          closeReason: CloseReasons.manualStop,
        ),
        ReconcilerAction.skipped(
          convergenceBeadId: 'c',
          reason: SkipReason.alreadyTerminated,
        ),
        ReconcilerAction.pourSpeculative(convergenceBeadId: 'c', pour: pour),
        ReconcilerAction.evaluateGate(
          convergenceBeadId: 'c',
          wispId: 'w',
          iteration: 1,
          config: GateConfig(
            mode: GateMode.condition,
            condition: 'gates/check.sh',
            timeout: ConvergenceMetadata.defaultGateTimeout,
            timeoutAction: GateTimeoutAction.iterate,
          ),
          env: GateEnvInputs(),
        ),
        ReconcilerAction.persistGateOutcome(
          convergenceBeadId: 'c',
          wispId: 'w',
          result: GateResult(outcomeWire: 'pass'),
        ),
        ReconcilerAction.repairIteration(
          convergenceBeadId: 'c',
          derivedIteration: 2,
        ),
        ReconcilerAction.failed(convergenceBeadId: 'c', message: 'boom'),
        ReconcilerAction.requeue(
          event: ReducerEvent.operatorStop(
            convergenceBeadId: 'c',
            user: 'n',
            postDrain: true,
          ),
          reason: 'operator stop deferred behind drain',
        ),
      ];
      // Seven gc wire strings; the six carriers map to null.
      expect(actions.map((a) => a.wire).nonNulls.toSet(), hasLength(7));
      expect(actions.map((a) => a.wire).where((w) => w == null), hasLength(6));
      // Every variant carries the root bead id (requeue derives it from
      // the carried event).
      expect(actions.every((a) => a.convergenceBeadId == 'c'), isTrue);
    });
  });

  group('IterateAction — wispClosed path (handler.go:480-573)', () {
    const action = IterateAction(
      convergenceBeadId: 'gt-c1',
      iteration: 2,
      pour: pour,
      path: IteratePath.wispClosed,
      adoptWispId: 'gt-w3spec',
      closedWispId: 'gt-w2',
      clearVerdict: true,
      gateOutcome: GateOutcome.fail,
      slingFailureFallback: WaitingManualAction(
        convergenceBeadId: 'gt-c1',
        closedWispId: 'gt-w2',
        iteration: 2,
        reason: WaitingReason.slingFailure,
      ),
    );

    test('verdict clears come FIRST — before pour/activate '
        '(handler.go:491-498; gates-exec trap 21)', () {
      expect(action.preWrites, const [
        MetadataWrite(key: 'convergence.agent_verdict', value: ''),
        MetadataWrite(key: 'convergence.agent_verdict_wisp', value: ''),
      ]);
    });

    test('activates the wisp; post-pour writes are active_wisp then '
        'last_processed_wisp LAST; pending clear after', () {
      expect(action.activatesWisp, isTrue); // handler.go:525
      expect(action.postPourWrites('gt-w3'), const [
        MetadataWrite(key: 'convergence.active_wisp', value: 'gt-w3'),
        MetadataWrite(key: 'convergence.last_processed_wisp', value: 'gt-w2'),
      ]);
      expect(action.clearsPendingNextWisp, isTrue); // handler.go:563-565
    });

    test('carries the sling-failure fallback — a full waiting_manual '
        'transition with its own commit (handler.go:520-521, 714-726)', () {
      final fallback = action.slingFailureFallback!;
      expect(fallback.reason, WaitingReason.slingFailure);
      expect(
        fallback.orderedWrites.last,
        const MetadataWrite(
          key: 'convergence.last_processed_wisp',
          value: 'gt-w2',
        ),
      );
    });

    test('carries the full pour payload', () {
      expect(pour.parentBeadId, 'gt-c1');
      expect(pour.formula, 'mol-polish');
      expect(pour.idempotencyKey, 'converge:gt-c1:iter:3');
      expect(pour.iteration, 3);
      expect(pour.vars, {'doc_path': 'docs/x.md'});
      expect(pour.evaluatePrompt, 'judge it');
      expect(pour.speculative, isFalse);
    });
  });

  group('IterateAction — operator path (manual.go IterateHandler)', () {
    const action = IterateAction(
      convergenceBeadId: 'gt-c1',
      iteration: 3,
      pour: pour,
      path: IteratePath.operatorIterate,
      clearVerdict: true,
    );

    test('NO pre-writes — the pour comes first so a failed pour preserves '
        'the verdict (manual.go:158-187)', () {
      expect(action.preWrites, isEmpty);
    });

    test('NEVER activates — gc IterateHandler pours visible with no '
        'ActivateWisp call (manual.go:166)', () {
      expect(action.activatesWisp, isFalse);
    });

    test('post-pour: verdict clears, waiting_reason, state, active_wisp — '
        'NO last_processed_wisp (manual.go:121-123), no pending clear', () {
      expect(action.postPourWrites('gt-w3'), const [
        MetadataWrite(key: 'convergence.agent_verdict', value: ''),
        MetadataWrite(key: 'convergence.agent_verdict_wisp', value: ''),
        MetadataWrite(key: 'convergence.waiting_reason', value: ''),
        MetadataWrite(key: 'convergence.state', value: 'active'),
        MetadataWrite(key: 'convergence.active_wisp', value: 'gt-w3'),
      ]);
      expect(action.clearsPendingNextWisp, isFalse);
    });
  });

  group('IterateAction — trigger-advance path (trigger.go:129-180)', () {
    const action = IterateAction(
      convergenceBeadId: 'gt-c1',
      iteration: 3, // HandlerResult.Iteration = nextIteration (trigger.go:177)
      pour: pour, // pour.iteration == 3 == the advanced iteration
      path: IteratePath.triggerAdvance,
    );

    test('no pre-writes, activates the poured wisp (trigger.go:144)', () {
      expect(action.preWrites, isEmpty);
      expect(action.activatesWisp, isTrue);
    });

    test('writes iteration ← EncodeInt(next), active_wisp, then state '
        'LAST — no waiting_reason, no dedup marker (trigger.go:148-156)', () {
      expect(action.postPourWrites('gt-w3'), const [
        MetadataWrite(key: 'convergence.iteration', value: '3'),
        MetadataWrite(key: 'convergence.active_wisp', value: 'gt-w3'),
        MetadataWrite(key: 'convergence.state', value: 'active'),
      ]);
      expect(action.clearsPendingNextWisp, isFalse);
    });
  });

  group('ApprovedAction (handler.go:638-711; manual.go:62-109)', () {
    test('handler path: terminal_reason, terminal_actor, state — then close, '
        'then last_processed_wisp LAST', () {
      const action = ApprovedAction(
        convergenceBeadId: 'gt-c1',
        path: TerminalPath.handlerWispClosed,
        actor: 'controller',
        iteration: 3,
        totalIterations: 3,
        lastProcessedWisp: 'gt-w3',
        gateOutcome: GateOutcome.pass,
        burnWispId: 'gt-w4spec',
        closeReason: CloseReasons.handlerRoot,
      );
      expect(action.terminalWrites, const [
        MetadataWrite(key: 'convergence.terminal_reason', value: 'approved'),
        MetadataWrite(key: 'convergence.terminal_actor', value: 'controller'),
        MetadataWrite(key: 'convergence.state', value: 'terminated'),
      ]);
      expect(
        action.commitWrite,
        const MetadataWrite(
          key: 'convergence.last_processed_wisp',
          value: 'gt-w3',
        ),
      );
      // The iteration-event ID component (converge:<bead>:iter:<N>:iteration)
      // and HandlerResult.Iteration (handler.go:708).
      expect(action.iteration, 3);
      // The origin is a typed discriminator, not a close-reason parse: the
      // handler path emits iteration + terminated BEFORE any terminal write
      // (handler.go:675, 685 precede 689-697); the operator path writes
      // first (manual.go:65-77 precede the emit at 78-88).
      expect(action.path, TerminalPath.handlerWispClosed);
      expect(action.burnPriorPour, isFalse); // default
    });

    test(
      'operator path also clears waiting_reason (manual.go:71-73); '
      'null lastProcessedWisp skips the commit write (manual.go:105-109)',
      () {
        const action = ApprovedAction(
          convergenceBeadId: 'gt-c1',
          path: TerminalPath.operatorApprove,
          actor: 'operator:nico',
          iteration: 2, // = derived count on operator approve (manual.go:113)
          totalIterations: 2,
          clearWaitingReason: true,
          closeReason: CloseReasons.manualApprove,
        );
        expect(action.terminalWrites, const [
          MetadataWrite(key: 'convergence.terminal_reason', value: 'approved'),
          MetadataWrite(
            key: 'convergence.terminal_actor',
            value: 'operator:nico',
          ),
          MetadataWrite(key: 'convergence.waiting_reason', value: ''),
          MetadataWrite(key: 'convergence.state', value: 'terminated'),
        ]);
        expect(action.commitWrite, isNull);
        expect(action.path, TerminalPath.operatorApprove);
      },
    );
  });

  group('NoConvergenceAction (handler.go:687-704)', () {
    test('terminal sequence with reason no_convergence', () {
      const action = NoConvergenceAction(
        convergenceBeadId: 'gt-c1',
        actor: 'controller',
        iteration: 5,
        totalIterations: 5,
        lastProcessedWisp: 'gt-w5',
        gateOutcome: GateOutcome.fail,
        closeReason: CloseReasons.handlerRoot,
      );
      expect(action.terminalWrites, const [
        MetadataWrite(
          key: 'convergence.terminal_reason',
          value: 'no_convergence',
        ),
        MetadataWrite(key: 'convergence.terminal_actor', value: 'controller'),
        MetadataWrite(key: 'convergence.state', value: 'terminated'),
      ]);
      expect(
        action.commitWrite,
        const MetadataWrite(
          key: 'convergence.last_processed_wisp',
          value: 'gt-w5',
        ),
      );
    });
  });

  group('WaitingManualAction (handler.go:442-453)', () {
    test('clears active_wisp, sets waiting_reason and state, then '
        'last_processed_wisp LAST', () {
      const action = WaitingManualAction(
        convergenceBeadId: 'gt-c1',
        closedWispId: 'gt-w2',
        iteration: 2,
        reason: WaitingReason.timeout,
        gateOutcome: GateOutcome.timeout,
        burnWispId: 'gt-w3spec',
      );
      expect(action.orderedWrites, const [
        MetadataWrite(key: 'convergence.active_wisp', value: ''),
        MetadataWrite(key: 'convergence.waiting_reason', value: 'timeout'),
        MetadataWrite(key: 'convergence.state', value: 'waiting_manual'),
        MetadataWrite(key: 'convergence.last_processed_wisp', value: 'gt-w2'),
      ]);
      expect(action.clearStalePending, isFalse); // default
    });

    test('carries the stale-pending self-heal on the no-pour hold paths '
        '(validPendingNextWisp runs unconditionally, handler.go:935-945)', () {
      // Manual-mode hold with a stale pointer in the snapshot: step 3b is
      // skipped (no pourSpeculative to carry the clear), but gc still
      // validates — and clears — the pointer before the hold.
      const action = WaitingManualAction(
        convergenceBeadId: 'gt-c1',
        closedWispId: 'gt-w2',
        iteration: 2,
        reason: WaitingReason.manual,
        clearStalePending: true,
      );
      expect(action.clearStalePending, isTrue);
      expect(
        action.stalePendingClear,
        const MetadataWrite(key: 'convergence.pending_next_wisp', value: ''),
      );
    });
  });

  group('WaitingTriggerAction (handler.go:589-628)', () {
    test('verdict clears first, active_wisp cleared, state, then '
        'last_processed_wisp LAST', () {
      const action = WaitingTriggerAction(
        convergenceBeadId: 'gt-c1',
        closedWispId: 'gt-w1',
        iteration: 1,
        clearVerdict: true,
        gateOutcome: GateOutcome.fail,
      );
      expect(action.orderedWrites, const [
        MetadataWrite(key: 'convergence.agent_verdict', value: ''),
        MetadataWrite(key: 'convergence.agent_verdict_wisp', value: ''),
        MetadataWrite(key: 'convergence.active_wisp', value: ''),
        MetadataWrite(key: 'convergence.state', value: 'waiting_trigger'),
        MetadataWrite(key: 'convergence.last_processed_wisp', value: 'gt-w1'),
      ]);
    });
  });

  group('StoppedAction (manual.go:351-380, 429-439)', () {
    test('unconditional verdict clears, terminal writes with '
        'waiting_reason clear, then commit write LAST', () {
      const action = StoppedAction(
        convergenceBeadId: 'gt-c1',
        actor: 'operator:nico',
        totalIterations: 2,
        lastProcessedWisp: 'gt-w2',
        forceCloseWispId: 'gt-w2',
        closeReason: CloseReasons.manualStop,
        events: EventEmission(
          gateMode: GateMode.manual, // empty stored mode defaults to manual
          priorState: ConvergenceState.active, // ManualActionPayload
        ),
      );
      expect(action.orderedWrites, const [
        MetadataWrite(key: 'convergence.agent_verdict', value: ''),
        MetadataWrite(key: 'convergence.agent_verdict_wisp', value: ''),
        MetadataWrite(key: 'convergence.terminal_reason', value: 'stopped'),
        MetadataWrite(
          key: 'convergence.terminal_actor',
          value: 'operator:nico',
        ),
        MetadataWrite(key: 'convergence.waiting_reason', value: ''),
        MetadataWrite(key: 'convergence.state', value: 'terminated'),
      ]);
      expect(
        action.commitWrite,
        const MetadataWrite(
          key: 'convergence.last_processed_wisp',
          value: 'gt-w2',
        ),
      );
      expect(action.events?.gateMode, GateMode.manual);
      expect(action.events?.priorState, ConvergenceState.active);
    });

    test('no last_processed_wisp -> commit write skipped '
        '(manual.go:435-439)', () {
      const action = StoppedAction(
        convergenceBeadId: 'gt-c1',
        actor: 'operator:nico',
        totalIterations: 0,
        closeReason: CloseReasons.manualStop,
      );
      expect(action.commitWrite, isNull);
    });
  });

  group('SkippedAction', () {
    test('carries the reason; the terminated guard also closes the root '
        'best-effort (handler.go:171-175)', () {
      const guard = SkippedAction(
        convergenceBeadId: 'gt-c1',
        reason: SkipReason.alreadyTerminated,
        closeRootBestEffort: true,
      );
      expect(guard.reason, SkipReason.alreadyTerminated);
      expect(guard.closeRootBestEffort, isTrue);

      const dedup = SkippedAction(
        convergenceBeadId: 'gt-c1',
        wispId: 'gt-w1',
        reason: SkipReason.duplicateWisp,
        detail: 'wisp iteration 1 <= last processed 2',
      );
      expect(dedup.closeRootBestEffort, isFalse);
      expect(dedup.wispId, 'gt-w1');
    });
  });

  group('PourSpeculativeAction (handler.go:244-275, invariant 5)', () {
    const specPour = WispPour(
      parentBeadId: 'gt-c1',
      formula: 'mol-polish',
      idempotencyKey: 'converge:gt-c1:iter:3',
      iteration: 3,
      speculative: true,
    );

    test('pending_next_wisp write — durable immediately after the pour '
        '(handler.go:267-274)', () {
      const action = PourSpeculativeAction(
        convergenceBeadId: 'gt-c1',
        pour: specPour,
      );
      expect(
        action.pendingNextWispWrite('gt-w3spec'),
        const MetadataWrite(
          key: 'convergence.pending_next_wisp',
          value: 'gt-w3spec',
        ),
      );
    });

    test('stale-pointer self-heal clear (handler.go:941)', () {
      const action = PourSpeculativeAction(
        convergenceBeadId: 'gt-c1',
        pour: specPour,
        clearStalePending: true,
      );
      expect(
        action.stalePendingClear,
        const MetadataWrite(key: 'convergence.pending_next_wisp', value: ''),
      );
    });

    test('adoption of a valid prior pour skips the pour (handler.go:247)', () {
      const action = PourSpeculativeAction(
        convergenceBeadId: 'gt-c1',
        pour: specPour,
        adoptPendingWispId: 'gt-w3spec',
      );
      expect(action.adoptPendingWispId, 'gt-w3spec');
      expect(action.pour.speculative, isTrue);
    });

    test('in-list dataflow: a same-list transition binds the pour result '
        'via the prior-pour flags, never a re-pour (handler.go:247-275, '
        '381, 385)', () {
      // Replay path (gate_outcome_wisp == wispId), persisted fail, no
      // pending in the snapshot: 3b still pours, and the iterate in the
      // SAME list must adopt that pour — adoptWispId cannot name it.
      const replayIterate = IterateAction(
        convergenceBeadId: 'gt-c1',
        iteration: 2,
        pour: pour,
        path: IteratePath.wispClosed,
        adoptFromPriorPour: true,
        closedWispId: 'gt-w2',
        slingFailureFallback: WaitingManualAction(
          convergenceBeadId: 'gt-c1',
          closedWispId: 'gt-w2',
          iteration: 2,
          reason: WaitingReason.slingFailure,
        ),
      );
      expect(replayIterate.adoptWispId, isNull);
      expect(replayIterate.adoptFromPriorPour, isTrue);
      // A deferred prior-pour failure routes to the sling fallback instead
      // of a duplicate pour of the same key (handler.go:370-373).
      expect(
        replayIterate.slingFailureFallback?.reason,
        WaitingReason.slingFailure,
      );

      // Terminal replay below max: 3b pours, the persisted pass
      // terminates, the pour burns (handler.go:384-387) — after
      // termination no later entry can self-heal the leak.
      const replayApproved = ApprovedAction(
        convergenceBeadId: 'gt-c1',
        path: TerminalPath.handlerWispClosed,
        actor: 'controller',
        iteration: 2,
        totalIterations: 2,
        burnPriorPour: true,
        closeReason: CloseReasons.handlerRoot,
      );
      expect(replayApproved.burnWispId, isNull);
      expect(replayApproved.burnPriorPour, isTrue);

      // Timeout-with-manual replay: same shape on the waiting hold
      // (handler.go:344-352).
      const replayHold = WaitingManualAction(
        convergenceBeadId: 'gt-c1',
        closedWispId: 'gt-w2',
        iteration: 2,
        reason: WaitingReason.timeout,
        burnPriorPour: true,
      );
      expect(replayHold.burnPriorPour, isTrue);

      // The flags default off everywhere — fresh-path phase-2 actions name
      // ids concretely from GateEvaluatedEvent instead.
      const fresh = NoConvergenceAction(
        convergenceBeadId: 'gt-c1',
        actor: 'controller',
        iteration: 5,
        totalIterations: 5,
        closeReason: CloseReasons.handlerRoot,
      );
      expect(fresh.burnPriorPour, isFalse);
    });
  });

  group('EvaluateGateAction (step 4 fresh branch, handler.go:326-327)', () {
    const config = GateConfig(
      mode: GateMode.hybrid,
      condition: 'gates/review.sh',
      timeout: ConvergenceMetadata.defaultGateTimeout,
      timeoutAction: GateTimeoutAction.retry,
    );
    const action = EvaluateGateAction(
      convergenceBeadId: 'gt-c1',
      wispId: 'gt-w2',
      iteration: 2,
      config: config,
      env: GateEnvInputs(
        cityPath: '/city',
        docPath: 'docs/x.md',
        maxIterations: 5,
        iterationDuration: Duration(seconds: 90),
        cumulativeDuration: Duration(seconds: 240),
        agentVerdict: Verdict.approve,
      ),
    );

    test('carries the step-3a parse product and the step-4 decisions as '
        'data — Track G never re-derives them', () {
      expect(action.config.mode, GateMode.hybrid);
      expect(action.config.condition, 'gates/review.sh');
      // Retry budget travels inside the config (handler.go:739-742).
      expect(action.config.retryBudget, 3);
      // The gate-path verdict (scoped-else-block, handler.go:317-324) —
      // NOT the event payload's '' semantics.
      expect(action.env.agentVerdict, Verdict.approve);
      expect(action.env.maxIterations, 5);
      expect(action.wire, isNull); // no gc HandlerAction analog
    });

    test('GateConfig ports the gate.go predicates', () {
      expect(config.needsConditionExecution, isTrue); // gate.go:90-99
      expect(config.hybridNeedsManual, isFalse); // hybrid.go:25-27
      const manualCfg = GateConfig(
        mode: GateMode.manual,
        condition: 'gates/ignored.sh',
        timeout: ConvergenceMetadata.defaultGateTimeout,
        timeoutAction: GateTimeoutAction.iterate,
      );
      expect(manualCfg.needsConditionExecution, isFalse);
      expect(manualCfg.retryBudget, 0);
      const hybridNoCondition = GateConfig(
        mode: GateMode.hybrid,
        condition: '',
        timeout: ConvergenceMetadata.defaultGateTimeout,
        timeoutAction: GateTimeoutAction.iterate,
      );
      expect(hybridNoCondition.needsConditionExecution, isFalse);
      expect(hybridNoCondition.hybridNeedsManual, isTrue);
    });

    test('env inputs default to gc zero values (handler.go:743-760)', () {
      const env = GateEnvInputs();
      expect(env.cityPath, '');
      expect(env.docPath, '');
      expect(env.maxIterations, 0);
      expect(env.iterationDuration, Duration.zero);
      expect(env.cumulativeDuration, Duration.zero);
      // The unscoped substitute (handler.go:321-323).
      expect(env.agentVerdict, Verdict.block);
    });
  });

  group('PersistGateOutcomeAction (handler.go:776-808; gates-exec §7)', () {
    test('eight writes in gc order; gate_outcome_wisp strictly LAST', () {
      const action = PersistGateOutcomeAction(
        convergenceBeadId: 'gt-c1',
        wispId: 'gt-w2',
        result: GateResult(
          outcomeWire: 'fail',
          exitCode: 1,
          retryCount: 2,
          stdout: 'out',
          stderr: 'err',
          duration: Duration(milliseconds: 1042),
          truncated: true,
        ),
      );
      expect(action.orderedWrites, const [
        MetadataWrite(key: 'convergence.gate_outcome', value: 'fail'),
        MetadataWrite(key: 'convergence.gate_exit_code', value: '1'),
        MetadataWrite(key: 'convergence.gate_retry_count', value: '2'),
        MetadataWrite(key: 'convergence.gate_stdout', value: 'out'),
        MetadataWrite(key: 'convergence.gate_stderr', value: 'err'),
        MetadataWrite(key: 'convergence.gate_duration_ms', value: '1042'),
        MetadataWrite(key: 'convergence.gate_truncated', value: 'true'),
        MetadataWrite(key: 'convergence.gate_outcome_wisp', value: 'gt-w2'),
      ]);
    });

    test('null exit code persists as "" (not "0"); truncated false as "" '
        '(handler.go:780-784, 799-803)', () {
      const action = PersistGateOutcomeAction(
        convergenceBeadId: 'gt-c1',
        wispId: 'gt-w2',
        result: GateResult(outcomeWire: 'timeout'),
      );
      final byKey = {for (final w in action.orderedWrites) w.key: w.value};
      expect(byKey['convergence.gate_exit_code'], '');
      expect(byKey['convergence.gate_truncated'], '');
      expect(byKey['convergence.gate_duration_ms'], '0');
    });

    test('carries the phase-1 speculative wisp to burn on persistence '
        'failure (handler.go:331-338)', () {
      const action = PersistGateOutcomeAction(
        convergenceBeadId: 'gt-c1',
        wispId: 'gt-w2',
        result: GateResult(outcomeWire: 'fail'),
        burnWispId: 'gt-w3spec',
      );
      expect(action.burnWispId, 'gt-w3spec');
    });
  });

  group('RepairIterationAction (handler.go:208-214, invariant 4)', () {
    test('writes the derived count as EncodeInt', () {
      const action = RepairIterationAction(
        convergenceBeadId: 'gt-c1',
        derivedIteration: 3,
        storedIteration: 2,
      );
      expect(
        action.write,
        const MetadataWrite(key: 'convergence.iteration', value: '3'),
      );
    });
  });

  group('FailedAction (gc error returns)', () {
    test('misconfig path carries the pending wisp to burn FIRST '
        '(handler.go:235-242; trap 9)', () {
      const action = FailedAction(
        convergenceBeadId: 'gt-c1',
        message: 'gate mode is "condition" but no condition path configured',
        burnWispId: 'gt-w3spec',
      );
      expect(action.burnWispId, 'gt-w3spec');
      expect(action.wire, isNull);
    });

    test('operator precondition failure carries gc message shape '
        '(manual.go:37-42)', () {
      const action = FailedAction(
        convergenceBeadId: 'gt-c1',
        message:
            'cannot approve bead "gt-c1": state is "active", '
            'expected "waiting_manual"',
      );
      expect(action.message, contains('cannot approve bead'));
      expect(action.burnWispId, isNull);
      expect(action.clearStalePending, isFalse); // default
    });

    test('misconfig with a STALE pointer clears instead of burning '
        '(handler.go:236 → validPendingNextWisp self-heal, 935-945)', () {
      const action = FailedAction(
        convergenceBeadId: 'gt-c1',
        message: 'gate mode is "condition" but no condition path configured',
        clearStalePending: true,
      );
      expect(action.burnWispId, isNull); // valid → burn, stale → clear
      expect(
        action.stalePendingClear,
        const MetadataWrite(key: 'convergence.pending_next_wisp', value: ''),
      );
    });
  });

  group('RequeueAction (gc inline operator-stop drain, manual.go:272-314)', () {
    test('carries the deferred event verbatim, derives the root id from '
        'it, and has no wire string — a pure carrier, always LAST', () {
      const stop = ReducerEvent.operatorStop(
        convergenceBeadId: 'gt-c1',
        user: 'nico',
      );
      const ReconcilerAction action = ReconcilerAction.requeue(
        event: stop,
        reason: 'operator stop deferred behind drain of closed active gt-w2',
      );
      expect(action.wire, isNull);
      expect(action.convergenceBeadId, 'gt-c1'); // from the carried event
      final requeue = action as RequeueAction;
      expect(requeue.event, same(stop));
      expect(requeue.reason, contains('drain'));
    });

    test('the drain re-entry is absorbed by the idempotent skip reasons: '
        'drainTerminated/alreadyStopped both report wire "stopped" '
        '(manual.go:296-308, 251-255)', () {
      expect(
        const SkippedAction(
          convergenceBeadId: 'gt-c1',
          reason: SkipReason.drainTerminated,
        ).wire,
        'stopped',
      );
      expect(
        const SkippedAction(
          convergenceBeadId: 'gt-c1',
          reason: SkipReason.alreadyStopped,
        ).wire,
        'stopped',
      );
    });

    test('a first-arrival operator stop is NOT postDrain; the requeue '
        'carrier stamps postDrain=true so the reducer can tell gc\'s own '
        'drain-termination (manual.go:303-308) from a fresh stop on an '
        'already-terminated loop (manual.go:258-263)', () {
      const fresh = ReducerEvent.operatorStop(
        convergenceBeadId: 'gt-c1',
        user: 'nico',
      );
      expect(
        (fresh as OperatorStopEvent).postDrain,
        isFalse,
        reason: 'first-arrival stop defaults to non-drain',
      );

      // Track G re-enqueues the deferred stop with the re-entry marker set;
      // the carrier is the marked event, not the verbatim first arrival.
      const reentry = ReducerEvent.operatorStop(
        convergenceBeadId: 'gt-c1',
        user: 'nico',
        postDrain: true,
      );
      const ReconcilerAction action = ReconcilerAction.requeue(
        event: reentry,
        reason: 'operator stop deferred behind drain of closed active gt-w2',
      );
      final carried = (action as RequeueAction).event as OperatorStopEvent;
      expect(carried.postDrain, isTrue);

      // The two stops are the same shape EXCEPT the marker — exactly the
      // bit the post-drain snapshot drops and the reducer needs back.
      expect(fresh.convergenceBeadId, carried.convergenceBeadId);
      expect(fresh.user, carried.user);
      expect(fresh, isNot(equals(carried)));
    });
  });

  group('EventEmission rig + eventWispId (handler.go:860-895; '
      'manual.go eventWispID)', () {
    test('rig rides every emission; null means omit, like gc\'s '
        'empty-rig passthrough (handler.go:862-864)', () {
      const withRig = EventEmission(rig: 'rig-vapor');
      expect(withRig.rig, 'rig-vapor');
      const noRig = EventEmission();
      expect(noRig.rig, isNull); // city/HQ loop — payload untouched
    });

    test('approve/stop: active_wisp falls back to last_processed_wisp '
        '(manual.go:54-56, 359-361) — the EVENT value, never the '
        'commit-write value', () {
      // Stop without force-close: the commit write keeps the OLD
      // last_processed_wisp, but the payload's wisp_id is the (stale but
      // set) active_wisp — the exact divergence corner.
      const action = StoppedAction(
        convergenceBeadId: 'gt-c1',
        actor: 'operator:nico',
        totalIterations: 2,
        lastProcessedWisp: 'gt-w1',
        closeReason: CloseReasons.manualStop,
        events: EventEmission(
          gateMode: GateMode.manual,
          priorState: ConvergenceState.waitingManual,
          rig: 'rig-vapor',
          eventWispId: 'gt-w2', // active_wisp ≠ commit write 'gt-w1'
        ),
      );
      expect(action.events?.eventWispId, 'gt-w2');
      expect(action.commitWrite?.value, 'gt-w1');
      expect(action.events?.eventWispId, isNot(action.commitWrite?.value));
    });

    test('iterate/trigger-advance: wisp_id is the PRIOR wisp, null on the '
        'entry-gated first iteration (manual.go:207-208, trigger.go:170)', () {
      const firstAdvance = IterateAction(
        convergenceBeadId: 'gt-c1',
        iteration: 1,
        pour: WispPour(
          parentBeadId: 'gt-c1',
          formula: 'mol-polish',
          idempotencyKey: 'converge:gt-c1:iter:1',
          iteration: 1,
        ),
        path: IteratePath.triggerAdvance,
        events: EventEmission(priorState: ConvergenceState.waitingTrigger),
      );
      // No prior wisp: ManualActionPayload.wisp_id marshals as JSON null.
      expect(firstAdvance.events?.eventWispId, isNull);

      const operatorIterate = IterateAction(
        convergenceBeadId: 'gt-c1',
        iteration: 3,
        pour: pour,
        path: IteratePath.operatorIterate,
        events: EventEmission(
          priorState: ConvergenceState.waitingManual,
          eventWispId: 'gt-w2', // last_processed_wisp — the PRIOR wisp
        ),
      );
      expect(operatorIterate.events?.eventWispId, 'gt-w2');
    });
  });

  group('GateResult (gate.go:25-33)', () {
    test('empty outcome means "no gate ran" — manual mode GateResult{} '
        '(handler.go:305-306)', () {
      const zero = GateResult();
      expect(zero.outcomeWire, '');
      expect(zero.outcome, isNull);
      expect(zero.isPass, isFalse);
      expect(zero.isTimeout, isFalse);
    });

    test('typed view resolves the closed set; out-of-set replays stay '
        'raw (handler.go:282)', () {
      expect(GateResult.of(GateOutcome.pass).isPass, isTrue);
      expect(
        const GateResult(outcomeWire: 'timeout').outcome,
        GateOutcome.timeout,
      );
      const garbage = GateResult(outcomeWire: 'passed');
      expect(garbage.outcome, isNull); // not coerced, not thrown
      expect(garbage.outcomeWire, 'passed'); // preserved for replay parity
      expect(garbage.isPass, isFalse); // falls into iterate/terminal path
    });
  });

  group('ReducerEvent (the reduce input union)', () {
    test('exhaustively switchable over the six input channels', () {
      const events = <ReducerEvent>[
        ReducerEvent.wispClosed(convergenceBeadId: 'c', wispId: 'w'),
        ReducerEvent.gateEvaluated(
          convergenceBeadId: 'c',
          wispId: 'w',
          result: GateResult(outcomeWire: 'pass'),
        ),
        ReducerEvent.operatorApprove(convergenceBeadId: 'c', user: 'nico'),
        ReducerEvent.operatorIterate(convergenceBeadId: 'c', user: 'nico'),
        ReducerEvent.operatorStop(convergenceBeadId: 'c', user: 'nico'),
        ReducerEvent.triggerPassed(convergenceBeadId: 'c', nextIteration: 2),
      ];
      final labels = events
          .map(
            (e) => switch (e) {
              WispClosedEvent() => 'wisp_closed',
              GateEvaluatedEvent() => 'gate_evaluated',
              OperatorApproveEvent() => 'approve',
              OperatorIterateEvent() => 'iterate',
              OperatorStopEvent() => 'stop',
              TriggerPassedEvent() => 'trigger_passed',
            },
          )
          .toSet();
      expect(labels, hasLength(6));
    });

    test('gateEvaluated carries gc phase-split locals: the phase-1 pour '
        'result and the deferred pour failure (handler.go:247-275, '
        '370-373)', () {
      const fresh = GateEvaluatedEvent(
        convergenceBeadId: 'c',
        wispId: 'w2',
        result: GateResult(outcomeWire: 'fail'),
        pouredSpeculativeWispId: 'w3spec',
      );
      expect(fresh.pouredSpeculativeWispId, 'w3spec');
      expect(fresh.pourFailed, isFalse);

      // Pour failed AND the idempotency probe missed — phase 2 surfaces
      // sling_failure iff the outcome is non-terminal.
      const torn = GateEvaluatedEvent(
        convergenceBeadId: 'c',
        wispId: 'w2',
        result: GateResult(outcomeWire: 'fail'),
        pourFailed: true,
      );
      expect(torn.pouredSpeculativeWispId, isNull);
      expect(torn.pourFailed, isTrue);
    });
  });
}
