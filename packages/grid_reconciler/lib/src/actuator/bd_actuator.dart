import 'package:grid_controller/grid_controller.dart';

import '../convergence/convergence_metadata.dart';
import '../convergence/idempotency_key.dart';
import '../convergence/reconciler_action.dart';
import '../projections/convergence.dart';
import '../reducer/reduce_result.dart';
import 'actuator.dart';

/// Raised when an actuator step gc treats as fatal fails — a pour the
/// idempotency probe could not adopt (operator/trigger paths hard-error,
/// manual.go:158-175 / trigger.go:135-143), a `persistGateOutcome` write
/// failure, or a `failed` action. The convergence loop is left at its prior
/// state, with NO transition commit, so the same event re-processes safely
/// (gc's `(HandlerResult{}, err)` contract — handler-9step §6).
class ActuationFailed implements Exception {
  ActuationFailed(this.message, {this.action});

  final String message;
  final ReconcilerAction? action;

  @override
  String toString() => 'ActuationFailed: $message';
}

/// The production [Actuator]: executes a [ReduceResult]'s ordered actions
/// through grid_controller's bd surface — the ONLY writer in the_grid.
///
/// Every metadata transition is a sequence of `bd update --metadata` writes
/// **in the order Track A's getters dictate** (`last_processed_wisp` LAST, it
/// IS the commit point — ADR-0003 invariant 2); the close sits between the
/// metadata writes and the final commit marker on terminal paths (handler.go:
/// 699-704). A burn is `bd delete` over the wisp's POST-ORDER subtree, NEVER
/// `bd close` (ADR-0000 A16). A pour is find-before-pour: the LIVE
/// [IdempotencyProbe] first (adopt a hit, no pour), else `bd cook` →
/// `bd create --graph` PERSISTENT (no `--ephemeral`, ADR-0000 A15).
///
/// The actuator never re-decides: each action carries its ordered writes. It
/// only threads the one value the reducer could not name — a freshly-poured
/// wisp id — from a [PourSpeculativeAction] / pouring [IterateAction] to a
/// later action's `adoptFromPriorPour` / `burnPriorPour` (the in-list dataflow
/// rule on [ReconcilerAction]).
class BdActuator implements Actuator {
  BdActuator(this._bd, this._probe);

  final BdCliService _bd;
  final IdempotencyProbe _probe;

  @override
  Future<ActuationResult> apply(
    ReduceResult result,
    Convergence convergence,
  ) async {
    // gc's `speculativeWispID` local: the in-list pour result the later
    // transition adopts/burns (handler.go:247-275). A deferred pour failure
    // is `_priorPourFailed` (gc's `speculativePourErr`).
    String? priorPourWispId;
    var priorPourFailed = false;
    RequeueAction? requeue;

    for (final action in result.actions) {
      switch (action) {
        case RepairIterationAction():
          // Step-3 self-heal, BEFORE any transition (a failure here blocks it).
          await _writeAll(action.convergenceBeadId, [action.write]);

        case PourSpeculativeAction():
          final id = await _executePourSpeculative(action);
          priorPourWispId = id;
          priorPourFailed = id == null;

        case IterateAction():
          await _executeIterate(
            action,
            convergence,
            priorPourWispId: priorPourWispId,
            priorPourFailed: priorPourFailed,
          );

        case ApprovedAction():
          await _executeApproved(action, convergence, priorPourWispId);

        case NoConvergenceAction():
          await _executeNoConvergence(action, convergence, priorPourWispId);

        case WaitingManualAction():
          await _executeWaitingManual(action, convergence, priorPourWispId);

        case WaitingTriggerAction():
          await _executeWaitingTrigger(action);

        case StoppedAction():
          await _executeStopped(action);

        case PersistGateOutcomeAction():
          await _executePersistGateOutcome(action, convergence);

        case EvaluateGateAction():
          // The fresh-gate handoff — Track D runs the gate; the actuator
          // performs no writes for it (the transition is phase 2's).
          break;

        case SkippedAction():
          await _executeSkipped(action);

        case FailedAction():
          await _executeFailed(action, convergence);

        case RequeueAction():
          // Pure carrier — no writes; Track G re-enqueues the event.
          requeue = action;
      }
    }

    return ActuationResult(
      pouredWispId: priorPourWispId,
      requeue: requeue,
      pourFailed: priorPourFailed,
    );
  }

  // ---------------------------------------------------------------------------
  // Transitions.
  // ---------------------------------------------------------------------------

  Future<void> _executeIterate(
    IterateAction action,
    Convergence convergence, {
    required String? priorPourWispId,
    required bool priorPourFailed,
  }) async {
    final root = action.convergenceBeadId;

    // 1. Pre-writes (wisp-closed path clears the verdict up front).
    await _writeAll(root, action.preWrites);

    // 2. Resolve the next wisp.
    final nextWispId = await _resolveIterateWisp(
      action,
      convergence,
      priorPourWispId: priorPourWispId,
      priorPourFailed: priorPourFailed,
    );

    // A sling-failure fallback was executed instead of iterating.
    if (nextWispId == null) return;

    // 3. Activate (wisp-closed + trigger paths; never the operator path).
    if (action.activatesWisp) {
      await _activate(nextWispId, convergence);
    }

    // 4. Post-pour writes (ending with last_processed_wisp LAST on the
    //    wisp-closed path).
    await _writeAll(root, action.postPourWrites(nextWispId));

    // 5. Best-effort clear pending_next_wisp (wisp-closed path only).
    if (action.clearsPendingNextWisp) {
      await _clearPendingBestEffort(root);
    }
  }

  /// Resolves the iterate action's next wisp: adopt a reduce-time-known id,
  /// bind the in-list prior pour, or fallback-pour. Returns null when a
  /// sling-failure fallback was executed instead (the caller must not write
  /// the iterate transition).
  Future<String?> _resolveIterateWisp(
    IterateAction action,
    Convergence convergence, {
    required String? priorPourWispId,
    required bool priorPourFailed,
  }) async {
    // a) reduce-time-known adoption.
    if (action.adoptWispId case final adopt?) return adopt;

    // b) bind the in-list prior pour.
    if (action.adoptFromPriorPour) {
      if (priorPourFailed || priorPourWispId == null) {
        // The 3b pour deferred-failed — sling-failure fallback instead of a
        // second pour of the same key (handler.go:370-373).
        await _executeSlingFailureFallback(action, convergence);
        return null;
      }
      return priorPourWispId;
    }

    // c) fallback-pour (find-before-pour).
    final poured = await _pour(action.pour);
    if (poured == null) {
      // A real pour error with a probe miss.
      switch (action.path) {
        case IteratePath.wispClosed:
          await _executeSlingFailureFallback(action, convergence);
          return null;
        case IteratePath.operatorIterate:
        case IteratePath.triggerAdvance:
          // Operator/trigger pour failure with a miss = hard error, NO writes
          // (manual.go:158-175, trigger.go:135-143).
          throw ActuationFailed(
            'pour failed and idempotency probe missed on '
            '${action.path} for $action',
            action: action,
          );
      }
    }
    return poured;
  }

  Future<void> _executeSlingFailureFallback(
    IterateAction action,
    Convergence convergence,
  ) async {
    final fallback = action.slingFailureFallback;
    if (fallback == null) {
      throw ActuationFailed(
        'iterate pour failed with no slingFailureFallback for $action',
        action: action,
      );
    }
    await _executeWaitingManual(fallback, convergence, null);
  }

  Future<void> _executeApproved(
    ApprovedAction action,
    Convergence convergence,
    String? priorPourWispId,
  ) async {
    final root = action.convergenceBeadId;
    switch (action.path) {
      case TerminalPath.handlerWispClosed:
        // 1. Burn first (reduce-time-known id and/or the in-list prior pour).
        await _burnTerminal(
          convergence,
          burnWispId: action.burnWispId,
          burnPriorPour: action.burnPriorPour,
          priorPourWispId: priorPourWispId,
        );
        // 2. (events emitted by Track G before any write — no actuator write.)
        // 3. Terminal writes.
        await _writeAll(root, action.terminalWrites);
        // 4. Close the root.
        await _bd.close(root, reason: action.closeReason);
        // 5. last_processed_wisp LAST (after the close, on the closed bead).
        await _writeCommit(root, action.commitWrite);

      case TerminalPath.operatorApprove:
        // No burn. 1. Terminal writes (incl. waiting_reason clear) FIRST.
        await _writeAll(root, action.terminalWrites);
        // 2. (terminated emitted before the close — Track G.)
        // 3. Close the root.
        await _bd.close(root, reason: action.closeReason);
        // 4. (manual_approve emitted after the close — Track G.)
        // 5. commit LAST.
        await _writeCommit(root, action.commitWrite);
    }
  }

  Future<void> _executeNoConvergence(
    NoConvergenceAction action,
    Convergence convergence,
    String? priorPourWispId,
  ) async {
    final root = action.convergenceBeadId;
    // Handler-only — always the wisp-closed terminal order.
    await _burnTerminal(
      convergence,
      burnWispId: action.burnWispId,
      burnPriorPour: action.burnPriorPour,
      priorPourWispId: priorPourWispId,
    );
    await _writeAll(root, action.terminalWrites);
    await _bd.close(root, reason: action.closeReason);
    await _writeCommit(root, action.commitWrite);
  }

  Future<void> _executeWaitingManual(
    WaitingManualAction action,
    Convergence convergence,
    String? priorPourWispId,
  ) async {
    final root = action.convergenceBeadId;
    // 1. Best-effort stale-pending clear FIRST.
    if (action.clearStalePending) {
      await _writeBestEffort(root, action.stalePendingClear);
    }
    // 2. Burn the reduce-time-known/in-list-prior pour (no close here).
    await _burnTerminal(
      convergence,
      burnWispId: action.burnWispId,
      burnPriorPour: action.burnPriorPour,
      priorPourWispId: priorPourWispId,
    );
    // 3. Ordered writes (active_wisp '', waiting_reason, state, lpw LAST). No
    //    close. Verdict deliberately survives (trap 7).
    await _writeAll(root, action.orderedWrites);
  }

  Future<void> _executeWaitingTrigger(WaitingTriggerAction action) async {
    // No pour, no burn, no close — just the ordered writes (verdict clears,
    // active_wisp '', state, last_processed_wisp LAST).
    await _writeAll(action.convergenceBeadId, action.orderedWrites);
  }

  Future<void> _executeStopped(StoppedAction action) async {
    final root = action.convergenceBeadId;
    // 1. Force-close a still-open active wisp (manual.go:334-339) — a CLOSE,
    //    not a burn: a force-closed iteration counts toward deriveIterationCount.
    if (action.forceCloseWispId case final forceClose?) {
      await _bd.close(forceClose, reason: CloseReasons.manualSupersede);
    }
    // 2. Ordered writes (verdict clears, then the terminal sequence).
    await _writeAll(root, action.orderedWrites);
    // 3. Close the root.
    await _bd.close(root, reason: action.closeReason);
    // 4. commit LAST (after the close).
    await _writeCommit(root, action.commitWrite);
  }

  Future<void> _executePersistGateOutcome(
    PersistGateOutcomeAction action,
    Convergence convergence,
  ) async {
    // The eight ordered gate-outcome writes, gate_outcome_wisp LAST. On
    // failure, gc burns the speculative wisp then hard-fails with no
    // transition (handler.go:331-338).
    try {
      await _writeAll(action.convergenceBeadId, action.orderedWrites);
    } on Object catch (error) {
      if (action.burnWispId case final burn?) {
        await _burn(convergence, burn);
        await _clearPendingBestEffort(action.convergenceBeadId);
      }
      throw ActuationFailed(
        'gate-outcome persistence failed: $error',
        action: action,
      );
    }
  }

  Future<void> _executeSkipped(SkippedAction action) async {
    // The only skip with a write is the already-terminated guard, which
    // best-effort closes the root (handler.go:172-173).
    if (action.closeRootBestEffort) {
      try {
        await _bd.close(
          action.convergenceBeadId,
          reason: CloseReasons.handlerCleanup,
        );
      } on Object {
        // best-effort: a non-fatal close (gc ignores the error).
      }
    }
  }

  Future<void> _executeFailed(
    FailedAction action,
    Convergence convergence,
  ) async {
    // Misconfig path: burn a valid pending wisp, or clear a stale pointer,
    // BEFORE surfacing the error (handler.go:235-242, trap 9). Mutually
    // exclusive (a pointer is either valid → burn, or stale → clear).
    if (action.burnWispId case final burn?) {
      await _burn(convergence, burn);
      await _clearPendingBestEffort(action.convergenceBeadId);
    } else if (action.clearStalePending) {
      await _writeBestEffort(
        action.convergenceBeadId,
        action.stalePendingClear,
      );
    }
    throw ActuationFailed(action.message, action: action);
  }

  // ---------------------------------------------------------------------------
  // Pour (find-before-pour) + activation + burn.
  // ---------------------------------------------------------------------------

  /// Step-3b speculative pour. Returns the poured/adopted wisp id, or null on
  /// a deferred pour failure (gc's `speculativePourErr` — non-fatal here; it
  /// surfaces later as `sling_failure` only if the outcome is non-terminal).
  Future<String?> _executePourSpeculative(PourSpeculativeAction action) async {
    final root = action.convergenceBeadId;
    // 1. Best-effort stale-pending clear.
    if (action.clearStalePending) {
      await _writeBestEffort(root, action.stalePendingClear);
    }
    // 2. Adopt a validated pending pour, skipping the pour.
    if (action.adoptPendingWispId case final adopt?) {
      await _writeBestEffort(root, action.pendingNextWispWrite(adopt));
      return adopt;
    }
    // 3. Pour speculatively (find-before-pour).
    final String? wispId;
    try {
      wispId = await _pour(action.pour);
    } on Object {
      // A real pour error → deferred failure (NOT fatal; handler.go:259-266).
      return null;
    }
    if (wispId == null) return null;
    // 4. pending_next_wisp ← the poured wisp — durable BEFORE the gate runs
    //    (handler.go:267-274). If THIS write fails: burn the wisp and hard-fail.
    try {
      await _write(root, action.pendingNextWispWrite(wispId));
    } on Object catch (error) {
      await _burnByIds([wispId]); // no projection yet — burn the root id.
      throw ActuationFailed(
        'pending_next_wisp persistence failed after pour: $error',
        action: action,
      );
    }
    return wispId;
  }

  /// Find-before-pour: probe the LIVE idempotency key FIRST (adopt a hit, no
  /// pour); on a miss, `bd cook` (resolve) → build a [GraphApplyPlan] → `bd
  /// create --graph` PERSISTENT (no `--ephemeral`, ADR-0000 A15). Returns the
  /// poured/adopted wisp id. Rethrows a real cook/create error to the caller.
  Future<String?> _pour(WispPour pour) async {
    // 1. LIVE find-before-pour. A hit is adopted with no pour, no round-trip
    //    waste (ADR-0000 A15/A17 — bd never dedups on the key itself).
    final existing = await _probe(pour.parentBeadId, pour.idempotencyKey);
    if (existing != null) return existing;

    // 2. Resolve the formula.
    final resolved = await _bd.cook(pour.formula, vars: pour.vars);

    // 3. Build the graph plan (root wisp node parented + idempotency-keyed;
    //    step nodes hang off it; needs → blocks edges). A speculative pour
    //    pours each actionable node as the ready-excluded type `gate` with the
    //    real type stashed under gc.deferred_type (ADR-0000 A15).
    final plan = _buildPlan(pour, resolved);

    // 4. POUR atomically — PERSISTENT (drop --ephemeral).
    final ids = await _bd.applyGraph(plan, ephemeral: false);
    final wispId = ids[_kRootKey];
    if (wispId == null) {
      throw ActuationFailed(
        'graph-apply returned no id for the root wisp node (keys: '
        '${ids.keys.toList()})',
      );
    }
    return wispId;
  }

  static const String _kRootKey = 'wisp';

  GraphApplyPlan _buildPlan(WispPour pour, Map<String, dynamic> resolved) {
    final nodes = <GraphNode>[
      GraphNode(
        key: _kRootKey,
        title: 'Convergence wisp iter ${pour.iteration}',
        type: pour.speculative ? 'gate' : 'epic',
        parentId: pour.parentBeadId,
        metadata: {
          wispIdempotencyKeyField: pour.idempotencyKey,
          if (pour.speculative) DeferredWispFields.type: 'epic',
        },
      ),
    ];
    final edges = <GraphEdge>[];

    final steps = resolved['steps'];
    if (steps is List) {
      for (final raw in steps) {
        if (raw is! Map) continue;
        final step = raw.cast<String, dynamic>();
        final stepKey = step['id']?.toString();
        if (stepKey == null || stepKey.isEmpty) continue;
        final realType = step['type']?.toString() ?? 'task';
        nodes.add(
          GraphNode(
            key: stepKey,
            title: step['title']?.toString() ?? stepKey,
            type: pour.speculative ? 'gate' : realType,
            priority: _asInt(step['priority']),
            parentKey: _kRootKey,
            metadata: pour.speculative
                ? {DeferredWispFields.type: realType}
                : const {},
          ),
        );
        // needs → blocks edges between sibling steps.
        final needs = step['needs'] ?? step['depends_on'];
        if (needs is List) {
          for (final need in needs) {
            final needKey = need?.toString();
            if (needKey != null && needKey.isNotEmpty) {
              edges.add(GraphEdge(fromKey: stepKey, toKey: needKey));
            }
          }
        }
      }
    }

    return GraphApplyPlan(
      commitMessage: 'pour wisp ${pour.idempotencyKey}',
      nodes: nodes,
      edges: edges,
    );
  }

  /// Activation (`ActivateWisp`, convergence_store.go:204-246): per
  /// speculative node, restore the real type/assignee/routing via `bd update`
  /// (only when the deferred value is non-empty AND differs from the live
  /// value — the projection already filtered absent/empty). Pre-order over the
  /// subtree (parent before children).
  Future<void> _activate(String wispId, Convergence convergence) async {
    for (final wisp in convergence.wisps) {
      if (wisp.id != wispId) continue;
      for (final node in wisp.speculativeNodes) {
        final metadata = <String, String>{
          if (node.deferredRoutedTo case final r?) 'gc.routed_to': r,
          if (node.deferredExecutionRoutedTo case final e?)
            'gc.execution_routed_to': e,
        };
        final hasType = node.deferredType != null;
        final hasAssignee = node.deferredAssignee != null;
        if (!hasType && !hasAssignee && metadata.isEmpty) continue;
        await _bd.update(
          node.id,
          type: hasType ? IssueType(node.deferredType!) : null,
          assignee: node.deferredAssignee,
          metadata: metadata.isEmpty ? null : metadata,
        );
      }
      return;
    }
    // Wisp not in the projection (crash-adopted, no edges yet): nothing to
    // activate from the snapshot. Track C handles re-derivation.
  }

  /// Burns the reduce-time-known wisp and/or the in-list prior pour, terminal-
  /// order helper (burn precedes the terminal writes; handler.go:384-387).
  Future<void> _burnTerminal(
    Convergence convergence, {
    required String? burnWispId,
    required bool burnPriorPour,
    required String? priorPourWispId,
  }) async {
    if (burnWispId case final id?) {
      await _burn(convergence, id);
    }
    if (burnPriorPour && priorPourWispId != null) {
      await _burn(convergence, priorPourWispId);
    }
  }

  /// Burn = `bd delete` over the wisp's POST-ORDER subtree (children before
  /// parents, the wisp LAST — exactly `Wisp.subtreeIds`), NEVER `bd close`
  /// (ADR-0000 A16). Followed by a best-effort `pending_next_wisp` ← ''.
  Future<void> _burn(Convergence convergence, String wispId) async {
    final order = burnOrderFor(convergence, wispId);
    await _burnByIds(order);
    await _clearPendingBestEffort(convergence.id);
  }

  Future<void> _burnByIds(List<String> postOrderIds) async {
    for (final id in postOrderIds) {
      await _bd.delete(id);
    }
  }

  // ---------------------------------------------------------------------------
  // Write helpers — every metadata write is one `bd update --metadata {k:v}`.
  // ---------------------------------------------------------------------------

  Future<void> _writeAll(String id, List<MetadataWrite> writes) async {
    for (final write in writes) {
      await _write(id, write);
    }
  }

  Future<void> _write(String id, MetadataWrite write) =>
      _bd.update(id, metadata: {write.key: write.value});

  Future<void> _writeCommit(String id, MetadataWrite? commit) async {
    if (commit != null) await _write(id, commit);
  }

  Future<void> _writeBestEffort(String id, MetadataWrite write) async {
    try {
      await _write(id, write);
    } on Object {
      // best-effort (gc's `_ = SetMetadata(...)`).
    }
  }

  Future<void> _clearPendingBestEffort(String id) => _writeBestEffort(
    id,
    const MetadataWrite(key: ConvergenceFields.pendingNextWisp, value: ''),
  );

  static int? _asInt(Object? value) => switch (value) {
    final int v => v,
    final num v => v.toInt(),
    final String v => int.tryParse(v.trim()),
    _ => null,
  };
}
