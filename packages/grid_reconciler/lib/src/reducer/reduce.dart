import 'package:grid_controller/grid_controller.dart';

import '../convergence/convergence_metadata.dart';
import '../convergence/convergence_state.dart';
import '../convergence/gate_config.dart';
import '../convergence/gate_mode.dart';
import '../convergence/gate_outcome.dart';
import '../convergence/gate_result.dart';
import '../convergence/gate_timeout_action.dart';
import '../convergence/idempotency_key.dart';
import '../convergence/reconciler_action.dart';
import '../convergence/reducer_event.dart';
import '../convergence/verdict.dart';
import '../projections/convergence.dart';
import '../projections/wisp.dart';
import 'reduce_result.dart';

/// The PURE convergence reducer (ADR-0003 Decision 2; M2 Track B): gc's
/// `HandleWispClosed` 9-step algorithm + the operator (`manual.go`) and
/// trigger (`trigger.go`) handlers, ported 1:1 as
/// `reduce(convergence, event, snapshot) → ReduceResult`.
///
/// **Reduce from the Go, not the ADR table.** ADR-0003's transition table is
/// incomplete (ADR-0000 A19): the trigger-gated create→waiting_trigger row,
/// the pour-failure→waiting_manual(`sling_failure`) row, stop-from-
/// waiting_trigger, the operator-stop inline drain, and the after-`CloseBead`
/// `last_processed_wisp` ordering are all in the source but not the table.
/// This reducer ports the source; the table is orientation only.
///
/// **Phase split (gate evaluation).** A fresh, non-replay wisp-closed reduce
/// cannot run the gate (gates are subprocesses — Track D's job). It returns
/// an [EvaluateGateAction]; Track D runs it and re-enters the reducer with
/// `ReducerEvent.gateEvaluated`, which carries the [GateResult] AND the
/// phase-1 speculative-pour outcome. The reducer **consumes** gate results;
/// it never runs gates. On the replay branch (`gate_outcome_wisp == wispId`)
/// the cached result is reconstructed from metadata and the whole pipeline
/// runs in one reduce — no phase split.
///
/// **Purity contract.** No I/O, no clock, no randomness; the only inputs are
/// the three arguments. The reduce is a total function of
/// `(convergence, event, snapshot)`. Every effect — pours, burns, metadata
/// writes, closes, event emissions, requeues — is returned as data in the
/// ordered [ReduceResult.actions]; an actuator executes them. Each action
/// already encodes its ordered write sequence (Track A), so the reducer fills
/// semantic fields only.
abstract final class ConvergenceReducer {
  /// Reduces one [event] for [convergence] against [snapshot].
  ///
  /// Exhaustive over [ReducerEvent]; each event dispatches to gc's
  /// corresponding handler. [snapshot] supplies cross-bead reads gc's `Store`
  /// would do live (wisp `BeadInfo`, durations) — the projection
  /// [convergence] is the snapshot-derived view of the root and its wisps.
  static ReduceResult reduce(
    Convergence convergence,
    ReducerEvent event,
    GraphSnapshot snapshot,
  ) {
    return switch (event) {
      WispClosedEvent(:final wispId) => _handleWispClosed(
        convergence,
        snapshot,
        wispId: wispId,
        // No gate result yet — fresh-or-replay is decided inside.
        phase2: null,
      ),
      GateEvaluatedEvent(
        :final wispId,
        :final result,
        :final pouredSpeculativeWispId,
        :final pourFailed,
      ) =>
        _handleWispClosed(
          convergence,
          snapshot,
          wispId: wispId,
          phase2: _Phase2(
            result: result,
            pouredSpeculativeWispId: pouredSpeculativeWispId,
            pourFailed: pourFailed,
          ),
        ),
      OperatorApproveEvent(:final user) => _approve(convergence, user),
      OperatorIterateEvent(:final user) => _iterate(convergence, user),
      OperatorStopEvent(:final user, :final postDrain) => _stop(
        convergence,
        snapshot,
        user,
        postDrain: postDrain,
      ),
      TriggerPassedEvent(:final nextIteration) => _triggerAdvance(
        convergence,
        nextIteration,
      ),
    };
  }

  // ===========================================================================
  // HandleWispClosed — the 9-step algorithm (handler.go:161-390)
  // ===========================================================================

  static ReduceResult _handleWispClosed(
    Convergence convergence,
    GraphSnapshot snapshot, {
    required String wispId,
    required _Phase2? phase2,
  }) {
    final root = convergence.id;
    final meta = convergence.metadata;

    // --- Step 1: guard — terminal irreversibility (handler.go:170-175; Inv 6)
    if (meta.state.stateOrNull == ConvergenceState.terminated) {
      // gc best-effort closes a terminated-but-open root (handler.go:172-173).
      return ReduceResult.one(
        ReconcilerAction.skipped(
          convergenceBeadId: root,
          wispId: wispId,
          reason: SkipReason.alreadyTerminated,
          closeRootBestEffort: !convergence.isClosed,
        ),
      );
    }

    // --- Step 2: monotonic dedup (handler.go:177-201; Inv 1)
    final closingWisp = _wisp(convergence, wispId);
    if (closingWisp == null) {
      // gc hard-errors reading the closing wisp / parsing its key
      // (handler.go:177-186). No commit marker — safe re-process.
      return _failed(
        root,
        'parsing iteration from wisp key "${_keyOf(convergence, wispId)}"',
      );
    }
    final wispIteration = closingWisp.iteration;
    if (wispIteration == null) {
      return _failed(
        root,
        'parsing iteration from wisp key "${closingWisp.idempotencyKey}"',
      );
    }
    // last_processed_wisp degrades to iteration 0 on any read failure
    // (handler.go:188-198) — exactly the graceful path: a missing / unparseable
    // marker bead means "treat as 0 and continue", never block the loop.
    final lastProcessedIteration = _lastProcessedIteration(convergence);
    if (wispIteration <= lastProcessedIteration) {
      return ReduceResult.one(
        ReconcilerAction.skipped(
          convergenceBeadId: root,
          wispId: wispId,
          reason: SkipReason.duplicateWisp,
          detail:
              'wisp iteration $wispIteration <= last_processed '
              '$lastProcessedIteration',
        ),
      );
    }

    // --- Step 3: derive iteration + self-healing repair (handler.go:203-216)
    final globalIteration = convergence.closedWispCount;
    final storedIteration = meta.iterationOrZero;
    final maxIterations = meta.maxIterationsOrZero;
    final pre = <ReconcilerAction>[];
    if (globalIteration != storedIteration) {
      pre.add(
        ReconcilerAction.repairIteration(
          convergenceBeadId: root,
          derivedIteration: globalIteration,
          storedIteration: storedIteration,
        ),
      );
    }

    // --- Step 3a: config parse BEFORE any speculative work (handler.go:218-242)
    final gateConfigResult = _parseGateConfig(meta);
    if (gateConfigResult.error != null) {
      return _failed(root, gateConfigResult.error!);
    }
    final gateConfig = gateConfigResult.config!;
    final triggerError = _parseTriggerError(meta);
    if (triggerError != null) return _failed(root, triggerError);
    final triggerEnabled = meta.triggerEnabled;

    final nextIteration = wispIteration + 1;
    final nextKey = idempotencyKey(root, nextIteration);

    // The gate-replay marker (handler.go:233-234; Inv 2).
    final skipGateEval = meta.gateOutcomeWisp == wispId;

    // Misconfiguration: condition mode with no condition path, and not
    // replaying (handler.go:235-242). Burn a VALID pending first (trap 9);
    // clear a stale one. Replay short-circuits this (the persisted outcome
    // bypasses gate config entirely).
    if (!skipGateEval &&
        gateConfig.mode == GateMode.condition &&
        gateConfig.condition.isEmpty) {
      final pending = _validPendingNextWisp(convergence, nextKey);
      return ReduceResult([
        ...pre,
        ReconcilerAction.failed(
          convergenceBeadId: root,
          message: 'gate mode is "condition" but no condition path configured',
          burnWispId: pending,
          clearStalePending:
              pending == null && _hasStalePending(convergence, nextKey),
        ),
      ]);
    }

    // --- Step 3b: speculative pour (handler.go:244-275; Inv 5)
    final needsManualWithoutGate =
        gateConfig.mode == GateMode.manual ||
        (gateConfig.mode == GateMode.hybrid && gateConfig.hybridNeedsManual);
    final skipSpeculativePour = needsManualWithoutGate || triggerEnabled;

    final adoptedPending = _validPendingNextWisp(convergence, nextKey);
    final clearStalePending =
        adoptedPending == null && _hasStalePending(convergence, nextKey);

    // gc pours speculatively iff: below max, not a manual/trigger path, and
    // no valid pending already exists (handler.go:254).
    final pours =
        wispIteration < maxIterations &&
        !skipSpeculativePour &&
        adoptedPending == null;

    // --- Resolve the gate result: replay (this reduce) vs fresh (phase split)
    final _Phase2 resolved;
    if (skipGateEval) {
      // Replay branch — reconstruct from metadata (handler.go:280-298). The
      // 3b pour still runs in THIS reduce (no phase split on replay), so the
      // speculative wisp threads in-list, not via event data.
      resolved = _Phase2(
        result: _replayGateResult(meta),
        // In-list pour; bound by adoptFromPriorPour / burnPriorPour below.
        pouredSpeculativeWispId: adoptedPending,
        pourFailed: false,
        inListPour: pours,
      );
    } else if (phase2 != null) {
      // Phase 2 of a fresh evaluation — gate result + phase-1 pour outcome
      // arrive as event data (never re-read from snapshot).
      resolved = phase2;
    } else if (needsManualWithoutGate) {
      // Step 4 fresh manual short-circuit (handler.go:301-316): manual mode or
      // hybrid-without-condition transition to waiting_manual WITHOUT running
      // a gate — so there is no phase split and no speculative pour to thread
      // (skipSpeculativePour is true for these). The reason distinguishes the
      // two; no gate ran so gateOutcome/gateResult are null.
      final reason = gateConfig.mode == GateMode.manual
          ? WaitingReason.manual
          : WaitingReason.hybridNoCondition;
      return ReduceResult([
        ...pre,
        _waitingManual(
          convergence,
          snapshot,
          wispId: wispId,
          wispIteration: wispIteration,
          reason: reason,
          gateOutcome: null,
          gateResult: null,
          // No 3b pour happened, but a stale pending pointer must still be
          // self-healed (handler.go:935-945; the burn target here is only a
          // snapshot-validated pending, which manual paths can still adopt).
          burnWispId: _validPendingNextWisp(convergence, nextKey),
          burnPriorPour: false,
        ),
      ]);
    } else {
      // Phase 1 of a fresh evaluation — emit the speculative pour and the
      // gate-eval handoff; the transition is phase 2's to make.
      return _phase1FreshGate(
        convergence,
        snapshot,
        pre: pre,
        wispId: wispId,
        wispIteration: wispIteration,
        gateConfig: gateConfig,
        pours: pours,
        adoptedPending: adoptedPending,
        clearStalePending: clearStalePending,
        nextIteration: nextIteration,
        nextKey: nextKey,
      );
    }

    // On the replay branch the step-3b pour runs in THIS reduce (no phase
    // split); build it so the transition can bind it in-list. Manual/trigger
    // paths reach here only on replay (a persisted outcome can drive any
    // mode) but never poured (skipSpeculativePour); below-max non-skip replays
    // do pour.
    final inListPourAction = (skipGateEval && (pours || adoptedPending != null))
        ? ReconcilerAction.pourSpeculative(
            convergenceBeadId: root,
            pour: _wispPour(
              convergence,
              iteration: nextIteration,
              key: nextKey,
              speculative: true,
            ),
            adoptPendingWispId: adoptedPending,
            clearStalePending: false,
          )
        : null;

    // --- Steps 4 (manual short-circuits), 5 (persist), 7 (outcome) ----------
    return _completeWispClosed(
      convergence,
      snapshot,
      pre: pre,
      inListPourAction: inListPourAction,
      wispId: wispId,
      wispIteration: wispIteration,
      globalIteration: globalIteration,
      maxIterations: maxIterations,
      gateConfig: gateConfig,
      triggerEnabled: triggerEnabled,
      skipGateEval: skipGateEval,
      nextIteration: nextIteration,
      nextKey: nextKey,
      phase: resolved,
    );
  }

  /// Phase 1 of a fresh gate evaluation: the step-3b speculative pour (when
  /// gc pours) and the step-4 fresh-gate handoff. The transition is deferred
  /// to phase 2 (the `gateEvaluated` re-entry).
  static ReduceResult _phase1FreshGate(
    Convergence convergence,
    GraphSnapshot snapshot, {
    required List<ReconcilerAction> pre,
    required String wispId,
    required int wispIteration,
    required GateConfig gateConfig,
    required bool pours,
    required String? adoptedPending,
    required bool clearStalePending,
    required int nextIteration,
    required String nextKey,
  }) {
    final root = convergence.id;
    final actions = <ReconcilerAction>[...pre];

    // Step 3b pour (or adopt a valid pending). Manual / hybrid-no-condition /
    // trigger paths never reach a fresh gate eval (they short-circuit in
    // _completeWispClosed's step 4 on replay; on the fresh path they are
    // resolved here only when the gate truly runs — condition/hybrid+cond).
    if (pours || adoptedPending != null || clearStalePending) {
      actions.add(
        ReconcilerAction.pourSpeculative(
          convergenceBeadId: root,
          pour: _wispPour(
            convergence,
            iteration: nextIteration,
            key: nextKey,
            speculative: true,
          ),
          adoptPendingWispId: adoptedPending,
          clearStalePending: clearStalePending,
        ),
      );
    }

    // Step 4 fresh branch: hand the parsed config + snapshot env to Track D.
    actions.add(
      ReconcilerAction.evaluateGate(
        convergenceBeadId: root,
        wispId: wispId,
        iteration: wispIteration,
        config: gateConfig,
        env: _gateEnv(
          convergence,
          snapshot,
          wispId: wispId,
          maxIterations: convergence.metadata.maxIterationsOrZero,
        ),
      ),
    );
    return ReduceResult(actions);
  }

  /// Steps 4 (manual/hybrid-no-condition short-circuits) → 5 (persist) → 7
  /// (outcome branch), shared by the replay branch and phase 2 of a fresh
  /// evaluation. [phase] carries the resolved gate result and the
  /// speculative-pour outcome.
  static ReduceResult _completeWispClosed(
    Convergence convergence,
    GraphSnapshot snapshot, {
    required List<ReconcilerAction> pre,
    required ReconcilerAction? inListPourAction,
    required String wispId,
    required int wispIteration,
    required int globalIteration,
    required int maxIterations,
    required GateConfig gateConfig,
    required bool triggerEnabled,
    required bool skipGateEval,
    required int nextIteration,
    required String nextKey,
    required _Phase2 phase,
  }) {
    final root = convergence.id;
    final result = phase.result;
    // The speculative wisp threaded from phase 1 (event data) or the replay
    // in-list pour. `adoptFromPriorPour` / `burnPriorPour` bind the in-list
    // pour result; an event-data id binds via the explicit *WispId fields.
    final pouredId = phase.pouredSpeculativeWispId;
    final inListPour = phase.inListPour;

    // Step 4's manual / hybrid-without-condition short-circuits
    // (handler.go:301-316) fire ONLY on the fresh path and are resolved
    // upstream in _handleWispClosed (no gate to run, no phase split). The
    // replay branch (skipGateEval) drives the transition from the persisted
    // outcome regardless of mode; a fresh phase-2 reduce only reaches here
    // for condition / hybrid-with-condition, which DID run the gate. So by
    // here a result always exists and we proceed straight to persist (fresh)
    // + outcome.

    final actions = <ReconcilerAction>[
      ...pre,
      // The step-3b speculative pour (replay branch — it runs before step 4
      // in this same reduce; the transition binds it via adoptFromPriorPour /
      // burnPriorPour).
      if (inListPourAction != null) inListPourAction,
    ];

    // Step 5: persist the gate outcome (fresh only — replay skips, Inv 2).
    if (!skipGateEval) {
      actions.add(
        ReconcilerAction.persistGateOutcome(
          convergenceBeadId: root,
          wispId: wispId,
          result: result,
          // Burn the phase-1 pour if persistence fails (handler.go:331-338).
          burnWispId: pouredId,
        ),
      );
    }

    // Step 7: prepare outcome — evaluation order is load-bearing
    // (handler.go:343-389).

    // 7.1 timeout + action=manual → waiting_manual(timeout), BEFORE the
    // terminal switch (handler.go:345-351).
    if (result.isTimeout &&
        gateConfig.timeoutAction == GateTimeoutAction.manual) {
      actions.add(
        _waitingManual(
          convergence,
          snapshot,
          wispId: wispId,
          wispIteration: wispIteration,
          reason: WaitingReason.timeout,
          gateOutcome: result.outcome,
          gateResult: result,
          burnWispId: pouredId,
          burnPriorPour: inListPour && pouredId == null,
        ),
      );
      return ReduceResult(actions);
    }

    // 7.2 terminal determination, first match wins (handler.go:354-368).
    final TerminalReason? terminalReason;
    if (result.isPass) {
      terminalReason = TerminalReason.approved;
    } else if (result.isTimeout &&
        gateConfig.timeoutAction == GateTimeoutAction.terminate) {
      terminalReason = TerminalReason.noConvergence;
    } else if (wispIteration >= maxIterations) {
      terminalReason = TerminalReason.noConvergence;
    } else {
      terminalReason = null;
    }

    if (terminalReason == null) {
      // 7.3 non-terminal, in order (handler.go:370-382).
      // (a) deferred speculative-pour failure → sling_failure hold.
      if (phase.pourFailed) {
        actions.add(
          _waitingManual(
            convergence,
            snapshot,
            wispId: wispId,
            wispIteration: wispIteration,
            reason: WaitingReason.slingFailure,
            gateOutcome: result.outcome,
            gateResult: result,
            // Sling failure's defining condition is no wisp exists — no burn.
            burnWispId: null,
            burnPriorPour: false,
          ),
        );
        return ReduceResult(actions);
      }
      // (b) trigger enabled → waiting_trigger.
      if (triggerEnabled) {
        actions.add(
          _waitingTrigger(
            convergence,
            snapshot,
            wispId: wispId,
            wispIteration: wispIteration,
            gateResult: result,
          ),
        );
        return ReduceResult(actions);
      }
      // (c) else iterate (handler.go:381).
      actions.add(
        _iterateWispClosed(
          convergence,
          snapshot,
          wispId: wispId,
          wispIteration: wispIteration,
          nextIteration: nextIteration,
          nextKey: nextKey,
          gateResult: result,
          adoptWispId: inListPour ? null : pouredId,
          adoptFromPriorPour: inListPour,
        ),
      );
      return ReduceResult(actions);
    }

    // 7.4 terminal: burn the speculative wisp, then terminate
    // (handler.go:384-389). burnPriorPour when the burn target is the in-list
    // pour whose id the reducer cannot name.
    final burnPrior =
        inListPour &&
        pouredId == null &&
        _terminalCanBurn(
          wispIteration: wispIteration,
          maxIterations: maxIterations,
        );
    actions.add(
      _terminate(
        convergence,
        snapshot,
        wispId: wispId,
        wispIteration: wispIteration,
        globalIteration: globalIteration,
        reason: terminalReason,
        gateResult: result,
        burnWispId: pouredId,
        burnPriorPour: burnPrior,
      ),
    );
    return ReduceResult(actions);
  }

  /// Whether a terminal transition could have a speculative wisp to burn: gc
  /// pours at 3b only below max (`wispIteration < maxIterations`), so the
  /// at-max terminal never poured (handler-9step trap 20).
  static bool _terminalCanBurn({
    required int wispIteration,
    required int maxIterations,
  }) => wispIteration < maxIterations;

  // ===========================================================================
  // Transition builders (wisp-closed path)
  // ===========================================================================

  static ReconcilerAction _iterateWispClosed(
    Convergence convergence,
    GraphSnapshot snapshot, {
    required String wispId,
    required int wispIteration,
    required int nextIteration,
    required String nextKey,
    required GateResult gateResult,
    required String? adoptWispId,
    required bool adoptFromPriorPour,
  }) {
    final root = convergence.id;
    // Verdict cleared only when scoped to the closed wisp (handler.go:491).
    final scoped = convergence.metadata.agentVerdictWisp == wispId;
    return ReconcilerAction.iterate(
      convergenceBeadId: root,
      iteration: wispIteration,
      path: IteratePath.wispClosed,
      pour: _wispPour(
        convergence,
        iteration: nextIteration,
        key: nextKey,
        speculative: false,
      ),
      adoptWispId: adoptWispId,
      adoptFromPriorPour: adoptFromPriorPour,
      closedWispId: wispId,
      clearVerdict: scoped,
      gateOutcome: gateResult.outcome,
      // Fallback pour failure → sling_failure waiting_manual (handler.go:520).
      slingFailureFallback: _slingFailureHold(
        convergence,
        snapshot,
        wispId: wispId,
        wispIteration: wispIteration,
        gateResult: gateResult,
      ),
      events: _iterationEvent(
        convergence,
        snapshot,
        wispId: wispId,
        gateMode: convergence.metadata.gateMode.valueOrNull,
        gateResult: gateResult,
      ),
    );
  }

  static ReconcilerAction _terminate(
    Convergence convergence,
    GraphSnapshot snapshot, {
    required String wispId,
    required int wispIteration,
    required int globalIteration,
    required TerminalReason reason,
    required GateResult gateResult,
    required String? burnWispId,
    required bool burnPriorPour,
  }) {
    final root = convergence.id;
    final events = _iterationEvent(
      convergence,
      snapshot,
      wispId: wispId,
      gateMode: convergence.metadata.gateMode.valueOrNull,
      gateResult: gateResult,
    );
    if (reason.wire == TerminalReason.approved.wire) {
      return ReconcilerAction.approved(
        convergenceBeadId: root,
        path: TerminalPath.handlerWispClosed,
        actor: 'controller',
        iteration: wispIteration,
        totalIterations: globalIteration,
        lastProcessedWisp: wispId,
        gateOutcome: gateResult.outcome,
        burnWispId: burnWispId,
        burnPriorPour: burnPriorPour,
        closeReason: CloseReasons.handlerRoot,
        events: events,
      );
    }
    return ReconcilerAction.noConvergence(
      convergenceBeadId: root,
      actor: 'controller',
      iteration: wispIteration,
      totalIterations: globalIteration,
      lastProcessedWisp: wispId,
      gateOutcome: gateResult.outcome,
      burnWispId: burnWispId,
      burnPriorPour: burnPriorPour,
      closeReason: CloseReasons.handlerRoot,
      events: events,
    );
  }

  static WaitingManualAction _waitingManual(
    Convergence convergence,
    GraphSnapshot snapshot, {
    required String wispId,
    required int wispIteration,
    required WaitingReason reason,
    required GateOutcome? gateOutcome,
    required GateResult? gateResult,
    required String? burnWispId,
    required bool burnPriorPour,
  }) {
    return WaitingManualAction(
      convergenceBeadId: convergence.id,
      closedWispId: wispId,
      iteration: wispIteration,
      reason: reason,
      gateOutcome: gateOutcome,
      burnWispId: burnWispId,
      burnPriorPour: burnPriorPour,
      // Self-heal a stale pending pointer even on hold paths that pour
      // nothing (handler.go:935-945; the carrier on the action). The pending
      // is validated against the SAME successor key gc's `validPendingNextWisp`
      // used at handler.go:247 — `iter(closed wisp) + 1`.
      clearStalePending:
          burnWispId == null &&
          !burnPriorPour &&
          _hasStalePending(
            convergence,
            idempotencyKey(convergence.id, wispIteration + 1),
          ),
      events: _iterationEvent(
        convergence,
        snapshot,
        wispId: wispId,
        gateMode: convergence.metadata.gateMode.valueOrNull,
        // The waiting_manual payload's verdict is NOT cleared and survives;
        // no gate result for the pure-manual reason (gateOutcome==null).
        gateResult: gateResult,
      ),
    );
  }

  /// A pre-built `sling_failure` waiting_manual transition for the iterate
  /// action's fallback-pour-failure escape (handler.go:520-521 →
  /// handleSlingFailure).
  static WaitingManualAction _slingFailureHold(
    Convergence convergence,
    GraphSnapshot snapshot, {
    required String wispId,
    required int wispIteration,
    required GateResult gateResult,
  }) => _waitingManual(
    convergence,
    snapshot,
    wispId: wispId,
    wispIteration: wispIteration,
    reason: WaitingReason.slingFailure,
    gateOutcome: gateResult.outcome,
    gateResult: gateResult,
    burnWispId: null,
    burnPriorPour: false,
  );

  static ReconcilerAction _waitingTrigger(
    Convergence convergence,
    GraphSnapshot snapshot, {
    required String wispId,
    required int wispIteration,
    required GateResult gateResult,
  }) {
    // Verdict cleared when scoped to the closed wisp (handler.go:589-596).
    final scoped = convergence.metadata.agentVerdictWisp == wispId;
    return ReconcilerAction.waitingTrigger(
      convergenceBeadId: convergence.id,
      closedWispId: wispId,
      iteration: wispIteration,
      gateOutcome: gateResult.outcome,
      clearVerdict: scoped,
      events: _iterationEvent(
        convergence,
        snapshot,
        wispId: wispId,
        gateMode: convergence.metadata.gateMode.valueOrNull,
        gateResult: gateResult,
      ),
    );
  }

  // ===========================================================================
  // Operator approve (manual.go:20-115)
  // ===========================================================================

  static ReduceResult _approve(Convergence convergence, String user) {
    final root = convergence.id;
    final state = convergence.metadata.state.stateOrNull;
    final terminalReason = convergence.metadata.terminalReason;

    // Idempotent: terminated + approved → no-op success (manual.go:30-34).
    if (state == ConvergenceState.terminated &&
        terminalReason?.wire == TerminalReason.approved.wire) {
      return ReduceResult.one(
        ReconcilerAction.skipped(
          convergenceBeadId: root,
          reason: SkipReason.alreadyApproved,
        ),
      );
    }
    // Else must be waiting_manual (manual.go:37-42).
    if (state != ConvergenceState.waitingManual) {
      return _failed(
        root,
        'cannot approve bead "$root": state is "${_wire(state)}", '
        'expected "${ConvergenceState.waitingManual.wire}"',
      );
    }

    final iterationCount = convergence.closedWispCount;
    // Event wisp: active_wisp if non-empty, else last_processed_wisp
    // (manual.go:51-57).
    final eventWisp =
        convergence.metadata.activeWisp ??
        convergence.metadata.lastProcessedWisp;
    final lpw = convergence.metadata.lastProcessedWisp;

    return ReduceResult.one(
      ReconcilerAction.approved(
        convergenceBeadId: root,
        path: TerminalPath.operatorApprove,
        actor: 'operator:$user',
        iteration: iterationCount,
        totalIterations: iterationCount,
        // The dedup marker re-written to its own prior value, skipped when
        // empty (manual.go:104-109).
        lastProcessedWisp: lpw,
        clearWaitingReason: true,
        closeReason: CloseReasons.manualApprove,
        events: EventEmission(
          priorState: ConvergenceState.waitingManual,
          rig: convergence.metadata.rig,
          eventWispId: eventWisp,
        ),
      ),
    );
  }

  // ===========================================================================
  // Operator iterate (manual.go:124-217)
  // ===========================================================================

  static ReduceResult _iterate(Convergence convergence, String user) {
    final root = convergence.id;
    final state = convergence.metadata.state.stateOrNull;

    // Must be waiting_manual; NO idempotent terminal path (manual.go:133-138).
    if (state != ConvergenceState.waitingManual) {
      return _failed(
        root,
        'cannot iterate bead "$root": state is "${_wire(state)}", '
        'expected "${ConvergenceState.waitingManual.wire}"',
      );
    }

    final iterationCount = convergence.closedWispCount;
    final maxIterations = convergence.metadata.maxIterationsOrZero;
    // Derived-count ceiling, not the stored field (manual.go:141-151).
    if (iterationCount >= maxIterations) {
      return _failed(
        root,
        'cannot iterate bead "$root": at max iterations '
        '($iterationCount/$maxIterations)',
      );
    }

    final nextIteration = iterationCount + 1;
    final nextKey = idempotencyKey(root, nextIteration);
    final lpw = convergence.metadata.lastProcessedWisp;
    // Verdict cleared only when scoped to last_processed_wisp (manual.go:180).
    final scoped = lpw != null && convergence.metadata.agentVerdictWisp == lpw;

    return ReduceResult.one(
      ReconcilerAction.iterate(
        convergenceBeadId: root,
        iteration: nextIteration,
        path: IteratePath.operatorIterate,
        pour: _wispPour(
          convergence,
          iteration: nextIteration,
          key: nextKey,
          speculative: false,
        ),
        clearVerdict: scoped,
        events: EventEmission(
          priorState: ConvergenceState.waitingManual,
          rig: convergence.metadata.rig,
          // wisp_id = the PRIOR wisp; next travels as next_wisp_id
          // (manual.go:207-208).
          eventWispId: lpw,
        ),
      ),
    );
  }

  // ===========================================================================
  // Operator stop (manual.go:241-445) — incl. the inline drain
  // ===========================================================================

  static ReduceResult _stop(
    Convergence convergence,
    GraphSnapshot snapshot,
    String user, {
    required bool postDrain,
  }) {
    final root = convergence.id;
    final state = convergence.metadata.state.stateOrNull;
    final terminalReason = convergence.metadata.terminalReason;

    // Idempotent: terminated + stopped → no-op (manual.go:251-255). Same on
    // both flag values.
    if (state == ConvergenceState.terminated &&
        terminalReason?.wire == TerminalReason.stopped.wire) {
      return ReduceResult.one(
        ReconcilerAction.skipped(
          convergenceBeadId: root,
          reason: SkipReason.alreadyStopped,
        ),
      );
    }

    // postDrain disambiguates a terminated/non-stopped loop (A19 / the
    // OperatorStopEvent.postDrain contract):
    if (state == ConvergenceState.terminated) {
      if (postDrain) {
        // My own drain terminated it — gc's no-reason ActionStopped return
        // (manual.go:303-308).
        return ReduceResult.one(
          ReconcilerAction.skipped(
            convergenceBeadId: root,
            reason: SkipReason.drainTerminated,
          ),
        );
      }
      // A fresh stop on an already-terminated/non-stopped loop falls through
      // gc's state guard → error (manual.go:258-263).
      return _failed(
        root,
        'cannot stop bead "$root": state is '
        '"${ConvergenceState.terminated.wire}", expected '
        '"${ConvergenceState.active.wire}", '
        '"${ConvergenceState.waitingManual.wire}", or '
        '"${ConvergenceState.waitingTrigger.wire}"',
      );
    }

    // State guard: active | waiting_manual | waiting_trigger (manual.go:258).
    if (state != ConvergenceState.active &&
        state != ConvergenceState.waitingManual &&
        state != ConvergenceState.waitingTrigger) {
      return _failed(
        root,
        'cannot stop bead "$root": state is "${_wire(state)}", expected '
        '"${ConvergenceState.active.wire}", '
        '"${ConvergenceState.waitingManual.wire}", or '
        '"${ConvergenceState.waitingTrigger.wire}"',
      );
    }

    // The effective active wisp gc would act on: the metadata pointer's
    // resolved wisp, or — when that pointer DANGLES (set but its bead is gone
    // from the store; gc's `GetBead` → ErrNotFound) — a recovered replacement
    // (manual.go:276-286, 322-331 → recoverCurrentActiveWisp). gc runs the
    // same recovery before BOTH the drain (step 2) and the force-close
    // (step 3), so resolve it once here.
    final active = _effectiveActiveWisp(convergence);

    // Step 2 — DRAIN. If the active wisp is set and already CLOSED-but-
    // unprocessed, gc runs the full HandleWispClosed inline first
    // (manual.go:272-314). The split reducer cannot block, so it emits the
    // wispClosed drain pipeline with requeue(operatorStop, postDrain:true)
    // LAST (the A19 drain protocol). Only on the FIRST arrival
    // (postDrain==false) — the re-entry already drained.
    if (!postDrain) {
      if (active != null && active.isClosed) {
        final drain = _handleWispClosed(
          convergence,
          snapshot,
          wispId: active.id,
          phase2: null,
        );
        return ReduceResult([
          ...drain.actions,
          ReconcilerAction.requeue(
            event: ReducerEvent.operatorStop(
              convergenceBeadId: root,
              user: user,
              postDrain: true,
            ),
            reason:
                'operator stop deferred behind drain of closed active '
                'wisp ${active.id}',
          ),
        ]);
      }
    }

    // Step 3 — force-close a still-open active wisp (manual.go:317-340), then
    // the terminal sequence. After a force-close the derived count includes it
    // and last_processed_wisp repoints to it (manual.go:430-434).
    final forceClose = (active != null && !active.isClosed) ? active.id : null;
    final iterationCount =
        convergence.closedWispCount + (forceClose != null ? 1 : 0);

    final lpw = convergence.metadata.lastProcessedWisp;
    final finalLpw = forceClose ?? lpw;
    final eventWisp = (active != null) ? active.id : lpw;

    return ReduceResult.one(
      ReconcilerAction.stopped(
        convergenceBeadId: root,
        actor: 'operator:$user',
        totalIterations: iterationCount,
        lastProcessedWisp: finalLpw,
        forceCloseWispId: forceClose,
        closeReason: CloseReasons.manualStop,
        events: EventEmission(
          // The pre-stop state — never hardcoded waiting_manual
          // (manual.go:420-426).
          priorState: state,
          rig: convergence.metadata.rig,
          // Synthetic force-close iteration event defaults an empty mode to
          // manual (manual.go:387-389).
          gateMode:
              convergence.metadata.gateMode.valueOrNull ?? GateMode.manual,
          eventWispId: eventWisp,
        ),
      ),
    );
  }

  // ===========================================================================
  // Trigger advance (trigger.go:129-180) — ReducerEvent.triggerPassed
  // ===========================================================================

  static ReduceResult _triggerAdvance(
    Convergence convergence,
    int nextIteration,
  ) {
    final root = convergence.id;
    final state = convergence.metadata.state.stateOrNull;

    // gc's HandleTrigger state guard (trigger.go:58-61): a non-waiting_trigger
    // loop is skipped before any pour. The reducer only receives a
    // triggerPassed for a loop Track G saw in waiting_trigger, but the guard
    // is ported for fidelity (a stale event arriving after a state change).
    if (state != ConvergenceState.waitingTrigger) {
      return ReduceResult.one(
        ReconcilerAction.skipped(
          convergenceBeadId: root,
          reason: SkipReason.notWaitingTrigger,
        ),
      );
    }

    // Defense-in-depth max guard: refuse loudly, never skip (trigger.go:89-91).
    // maxIter > 0 && next > maxIter — an absent/zero max DISABLES the guard.
    final maxIterations = convergence.metadata.maxIterationsOrZero;
    if (maxIterations > 0 && nextIteration > maxIterations) {
      return _failed(
        root,
        'trigger-gated loop "$root" at iteration $nextIteration exceeds '
        'max_iterations $maxIterations; refusing to advance',
      );
    }

    final nextKey = idempotencyKey(root, nextIteration);
    final lpw = convergence.metadata.lastProcessedWisp;

    return ReduceResult.one(
      ReconcilerAction.iterate(
        convergenceBeadId: root,
        iteration: nextIteration,
        path: IteratePath.triggerAdvance,
        pour: _wispPour(
          convergence,
          iteration: nextIteration,
          key: nextKey,
          speculative: false,
        ),
        events: EventEmission(
          priorState: ConvergenceState.waitingTrigger,
          rig: convergence.metadata.rig,
          // wisp_id = last_processed_wisp, null on the entry-gated first
          // iteration (trigger.go:170).
          eventWispId: lpw,
        ),
      ),
    );
  }

  // ===========================================================================
  // Helpers
  // ===========================================================================

  static ReduceResult _failed(String root, String message) => ReduceResult.one(
    ReconcilerAction.failed(convergenceBeadId: root, message: message),
  );

  /// gc `ParseGateConfig` (gate.go:44-85) over the typed codec — defaults
  /// applied, parse errors surfaced. mode→manual, timeout→5m & must be >0,
  /// action→iterate; any non-empty unrecognized value is an error.
  static _GateConfigResult _parseGateConfig(ConvergenceMetadata meta) {
    final modeReading = meta.gateMode;
    if (modeReading.isMalformed) {
      return _GateConfigResult.error(
        'invalid gate mode "${meta.raw[ConvergenceFields.gateMode]}"',
      );
    }
    final mode = modeReading.valueOrNull ?? GateMode.defaultMode;

    final actionReading = meta.gateTimeoutAction;
    if (actionReading.isMalformed) {
      return _GateConfigResult.error(
        'invalid gate timeout action '
        '"${meta.raw[ConvergenceFields.gateTimeoutAction]}"',
      );
    }
    final action = actionReading.valueOrNull ?? GateTimeoutAction.defaultAction;

    final timeoutReading = meta.gateTimeout;
    if (timeoutReading.isMalformed) {
      return _GateConfigResult.error(
        'invalid gate timeout '
        '"${meta.raw[ConvergenceFields.gateTimeout]}"',
      );
    }
    final timeout =
        timeoutReading.valueOrNull ?? ConvergenceMetadata.defaultGateTimeout;
    // gc requires timeout > 0 (gate.go:57-67).
    if (timeout.nanoseconds <= 0) {
      return _GateConfigResult.error('gate timeout must be positive');
    }

    return _GateConfigResult.ok(
      GateConfig(
        mode: mode,
        condition: meta.gateCondition ?? '',
        timeout: timeout,
        timeoutAction: action,
      ),
    );
  }

  /// gc `ParseTriggerConfig` errors (trigger.go:26-41): event mode requires a
  /// condition; any non-(""|event) mode is invalid. Returns the error message
  /// or null when the config is valid.
  static String? _parseTriggerError(ConvergenceMetadata meta) {
    final reading = meta.trigger;
    if (reading.isMalformed) {
      return 'invalid trigger mode "${meta.raw[ConvergenceFields.trigger]}"';
    }
    if (reading.valueOrNull == TriggerMode.event &&
        (meta.triggerCondition == null)) {
      return 'trigger mode "event" requires a trigger condition path';
    }
    return null;
  }

  /// Reconstructs the replay [GateResult] from persisted metadata
  /// (handler.go:280-298) — VERBATIM outcome (never the validating reading),
  /// collapsing readers for the rest.
  static GateResult _replayGateResult(ConvergenceMetadata meta) => GateResult(
    outcomeWire: meta.gateOutcomeWire,
    exitCode: meta.gateExitCodeOrNull,
    retryCount: meta.gateRetryCountOrZero,
    stdout: meta.gateStdoutWire,
    stderr: meta.gateStderrWire,
    duration: meta.gateDurationOrZero,
    truncated: meta.gateTruncated,
  );

  /// gc `validPendingNextWisp` (handler.go:935-945): the recorded
  /// `pending_next_wisp` is valid iff it names a child of this root whose
  /// idempotency key == [nextKey] and is NOT closed. Returns the id, or null
  /// (which also signals the actuator to self-heal the stale pointer — see
  /// [_hasStalePending]).
  static String? _validPendingNextWisp(
    Convergence convergence,
    String nextKey,
  ) {
    final pending = convergence.metadata.pendingNextWisp;
    if (pending == null) return null;
    final wisp = _wisp(convergence, pending);
    if (wisp == null) return null; // missing / not our child
    if (wisp.idempotencyKey != nextKey) return null; // wrong iteration
    if (wisp.isClosed) return null; // already consumed
    return pending;
  }

  /// True when `pending_next_wisp` is set but does not validate against
  /// [nextKey] — gc clears it as a side effect of `validPendingNextWisp`
  /// (handler.go:935-945). The clear fires on ANY of gc's reject conditions:
  /// the pointer's bead is gone, names a child of a DIFFERENT root, carries
  /// the WRONG idempotency key (an open child of ours but at the wrong
  /// iteration — the case [_validPendingNextWisp]'s key check rejects), or is
  /// already closed. So "stale" is exactly "set but not the valid pending for
  /// [nextKey]". Drives the `clearStalePending` carriers.
  static bool _hasStalePending(Convergence convergence, String nextKey) {
    final pending = convergence.metadata.pendingNextWisp;
    if (pending == null) return false;
    return _validPendingNextWisp(convergence, nextKey) == null;
  }

  /// The wisp projection for [wispId] within this loop, or null if it is not
  /// one of the loop's wisps (gc resolves these through `Store`).
  static Wisp? _wisp(Convergence convergence, String wispId) {
    for (final wisp in convergence.wisps) {
      if (wisp.id == wispId) return wisp;
    }
    return null;
  }

  /// The active wisp gc's stop handler would actually act on: the
  /// `active_wisp` pointer's resolved wisp, or — when the pointer is set but
  /// DANGLES (its bead is gone; gc's `GetBead` → ErrNotFound) — a recovered
  /// replacement (manual.go:276-286, 322-331 → [_recoverActiveWisp]). Null
  /// when no pointer is set, or recovery finds nothing.
  static Wisp? _effectiveActiveWisp(Convergence convergence) {
    final resolved = convergence.activeWisp;
    if (resolved != null) return resolved;
    // Pointer absent/empty ⇒ nothing to act on (gc's `activeWisp == ""`
    // guard, never recovers). A present-but-unresolved pointer is the
    // dangling case gc recovers from.
    final pointer = convergence.metadata.activeWisp;
    if (pointer == null || pointer.isEmpty) return null;
    return _recoverActiveWisp(convergence);
  }

  /// gc `recoverCurrentActiveWisp` (manual.go:447-518), pure over the
  /// snapshot. When the recorded `active_wisp` bead has vanished, gc finds a
  /// replacement: prefer the wisp at `last_processed + 1` by idempotency key;
  /// failing a parseable last-processed marker, scan this loop's children for
  /// the highest-iteration OPEN wisp, then the highest-iteration CLOSED one.
  /// Returns null when nothing qualifies (gc's `found == false`).
  static Wisp? _recoverActiveWisp(Convergence convergence) {
    final lpw = convergence.metadata.lastProcessedWisp;
    // Branch 1: a parseable last-processed marker fixes the search to its
    // successor key. gc returns whatever that key lookup yields and does NOT
    // fall through to the child scan (manual.go:471-497).
    if (lpw != null && lpw.isNotEmpty) {
      final lastWisp = _wisp(convergence, lpw);
      final lastIter = lastWisp?.iteration;
      if (lastIter != null) {
        final nextKey = idempotencyKey(convergence.id, lastIter + 1);
        final candidateId = convergence.findByIdempotencyKey(nextKey);
        if (candidateId == null) return null;
        return _wisp(convergence, candidateId);
      }
    }
    // Branch 2: no parseable successor — scan loop children (already prefix
    // filtered into `wisps`) for the highest-iteration open wisp, else the
    // highest-iteration closed one (manual.go:499-517).
    Wisp? bestOpen;
    var bestOpenIter = -1;
    Wisp? bestClosed;
    var bestClosedIter = -1;
    for (final wisp in convergence.wisps) {
      final iter = wisp.iteration;
      if (iter == null) continue; // unparseable key — skipped, like gc
      if (wisp.isClosed) {
        if (iter > bestClosedIter) {
          bestClosed = wisp;
          bestClosedIter = iter;
        }
      } else if (iter > bestOpenIter) {
        bestOpen = wisp;
        bestOpenIter = iter;
      }
    }
    return bestOpen ?? bestClosed;
  }

  /// The idempotency key recorded for [wispId] (for error messages when the
  /// wisp is unknown / its key unparseable).
  static String _keyOf(Convergence convergence, String wispId) =>
      convergence.childIdempotencyKeys[wispId] ?? '';

  /// The dedup baseline (handler.go:188-198): the iteration parsed from the
  /// `last_processed_wisp` bead's key, degrading to 0 on any read/parse
  /// failure (missing bead, unparseable key, absent field).
  static int _lastProcessedIteration(Convergence convergence) {
    final lpw = convergence.metadata.lastProcessedWisp;
    if (lpw == null) return 0;
    final wisp = _wisp(convergence, lpw);
    if (wisp == null) return 0; // GetBead failure → graceful degradation
    return wisp.iteration ?? 0; // unparseable key → 0
  }

  /// Builds the [WispPour] payload from the loop's create-time metadata
  /// (formula, vars, evaluate prompt) — gc threads these into every pour
  /// (handler.go:256-258, manual.go:166, trigger.go:135).
  static WispPour _wispPour(
    Convergence convergence, {
    required int iteration,
    required String key,
    required bool speculative,
  }) => WispPour(
    parentBeadId: convergence.id,
    formula: convergence.metadata.formula ?? '',
    idempotencyKey: key,
    iteration: iteration,
    vars: convergence.metadata.vars,
    evaluatePrompt: convergence.metadata.evaluatePrompt,
    speculative: speculative,
  );

  /// The step-8 `convergence.iteration` event payload data (the verdict
  /// reported from the SNAPSHOT — gc's stale-snapshot semantics,
  /// handler.go:532-535 — and durations from `computeDurations`).
  static EventEmission _iterationEvent(
    Convergence convergence,
    GraphSnapshot snapshot, {
    required String wispId,
    required GateMode? gateMode,
    required GateResult? gateResult,
  }) {
    // Payload verdict: normalized when scoped to the closed wisp, else ''
    // (NOT the gate path's `block` — handler.go:417-420). verdictFor returns
    // the normalized verdict or null; the EventEmission default is ''.
    final verdict = convergence.metadata.verdictFor(wispId);
    final (iterDur, cumDur) = _durations(convergence, snapshot, wispId);
    return EventEmission(
      agentVerdict: verdict?.wire ?? '',
      gateMode: gateMode,
      gateResult: gateResult,
      iterationDuration: iterDur,
      cumulativeDuration: cumDur,
      rig: convergence.metadata.rig,
      eventWispId: wispId,
    );
  }

  /// gc `computeDurations` (handler.go:829-850), pure over the snapshot:
  /// the closed wisp's own duration, and the Σ over all closed
  /// convergence-keyed children. Best-effort — zero when timestamps are
  /// missing.
  static (Duration, Duration) _durations(
    Convergence convergence,
    GraphSnapshot snapshot,
    String wispId,
  ) {
    Duration durOf(Wisp wisp) {
      final created = wisp.createdAt;
      final closed = wisp.effectiveClosedAt;
      if (created == null || closed == null) return Duration.zero;
      final d = closed.difference(created);
      return d.isNegative ? Duration.zero : d;
    }

    var iterDur = Duration.zero;
    final closing = _wisp(convergence, wispId);
    if (closing != null) iterDur = durOf(closing);

    var cumDur = Duration.zero;
    for (final wisp in convergence.wisps) {
      if (!wisp.isClosed) continue;
      cumDur += durOf(wisp);
    }
    return (iterDur, cumDur);
  }

  /// The snapshot-derived [GateEnvInputs] for the fresh-gate handoff
  /// (handler.go:743-760) — Track D assembles the full `ConditionEnv` from
  /// these without re-reading live metadata.
  static GateEnvInputs _gateEnv(
    Convergence convergence,
    GraphSnapshot snapshot, {
    required String wispId,
    required int maxIterations,
  }) {
    final (iterDur, cumDur) = _durations(convergence, snapshot, wispId);
    // Gate-path verdict: normalized when scoped, else the `block` substitute
    // (handler.go:317-324) — NOT the event payload's '' default.
    final verdict = convergence.metadata.verdictFor(wispId) ?? Verdict.block;
    return GateEnvInputs(
      cityPath: convergence.metadata.cityPath ?? '',
      docPath: convergence.metadata.vars['doc_path'] ?? '',
      maxIterations: maxIterations,
      iterationDuration: iterDur,
      cumulativeDuration: cumDur,
      agentVerdict: verdict,
    );
  }

  /// gc's `state` printed for error messages — the wire string, or `""` for
  /// not-adopted (Go's `meta[FieldState]` reads `""` when absent).
  static String _wire(ConvergenceState? state) => state?.wire ?? '';
}

/// The resolved gate-evaluation phase: the gate [result] plus the
/// speculative-pour outcome threaded from phase 1 (or the replay in-list
/// pour).
class _Phase2 {
  const _Phase2({
    required this.result,
    required this.pouredSpeculativeWispId,
    required this.pourFailed,
    this.inListPour = false,
  });

  final GateResult result;

  /// The phase-1 speculative wisp's id (event data), null when none. On the
  /// replay branch this carries the adopted pending id; a fresh in-list pour
  /// (replay) leaves it null and sets [inListPour].
  final String? pouredSpeculativeWispId;

  /// gc's deferred `speculativePourErr` — surfaces as sling_failure on a
  /// non-terminal outcome.
  final bool pourFailed;

  /// True when phase 1's speculative pour was emitted IN THE SAME action list
  /// (the replay branch pours at 3b in this reduce), so the transition binds
  /// it via `adoptFromPriorPour` / `burnPriorPour` rather than a named id.
  final bool inListPour;
}

/// `ParseGateConfig` outcome — either a parsed [config] or an [error] message.
class _GateConfigResult {
  const _GateConfigResult.ok(this.config) : error = null;
  const _GateConfigResult.error(this.error) : config = null;

  final GateConfig? config;
  final String? error;
}
