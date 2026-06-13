import 'package:freezed_annotation/freezed_annotation.dart';

import 'gate_result.dart';

part 'reducer_event.freezed.dart';

/// The reducer's input union — the "event" in ADR-0003's
/// `reduce(state, event, snapshot) → (state′, actions)`.
///
/// grid_controller's `GraphEvent` carries bead-graph changes only; the
/// convergence reducer additionally consumes **gate results** (computed
/// asynchronously by the Track-D subprocess runner), **operator commands**
/// (gc's socket verbs `approve`/`iterate`/`stop`, emulated by the_grid's
/// command surface), and **trigger passes** (trigger.go:96-101). Track G
/// adapts `GraphEvent.beadClosed` on a convergence root's active wisp into
/// [ReducerEvent.wispClosed]; the other variants come from the gate runner
/// and the command surface. Without this union the ADR-0003 rows
/// `waitingManual / operator approve|iterate`, `any / operator stop`,
/// `waitingTrigger / trigger passes`, and every fresh-gate row would have
/// no input channel.
@freezed
sealed class ReducerEvent with _$ReducerEvent {
  const ReducerEvent._();

  /// A convergence root's wisp closed — the `HandleWispClosed` entry point
  /// (handler.go:161).
  const factory ReducerEvent.wispClosed({
    required String convergenceBeadId,
    required String wispId,
  }) = WispClosedEvent;

  /// The Track-D runner finished evaluating the gate for [wispId] — the
  /// fresh branch of step 4 (handler.go:326-327), requested by
  /// `ReconcilerAction.evaluateGate`. Re-enters the reducer with the
  /// result, which step 5 persists and step 7 branches on — AND with the
  /// phase-1 speculative-pour outcome: gc threads `speculativeWispID` /
  /// `speculativePourErr` through steps 3b→7 as locals in ONE frame
  /// (handler.go:247-275, 370-373, 381, 385); the split reducer gets them
  /// back as **event data**, threaded by Track G from the executed
  /// `pourSpeculative` action. Never recover them from a snapshot re-read:
  /// a fast gate (ms) routinely beats the Dolt watcher poll, so phase-1's
  /// `pending_next_wisp` write may not yet be visible in the snapshot this
  /// event reduces over — and a reducer that misses it would re-pour the
  /// key (duplicate, invariant 4) or skip a mandatory burn (leak,
  /// invariant 5).
  const factory ReducerEvent.gateEvaluated({
    required String convergenceBeadId,
    required String wispId,
    required GateResult result,

    /// The wisp the phase-1 `ReconcilerAction.pourSpeculative` produced —
    /// its fresh pour, its `adoptPendingWispId` adoption, or its
    /// find-before-pour hit; null when no wisp resulted (pour skipped, or
    /// failed with a probe miss). Feeds the phase-2 reduce's
    /// `IterateAction.adoptWispId`, the terminal/waiting `burnWispId`s,
    /// and `PersistGateOutcomeAction.burnWispId`.
    String? pouredSpeculativeWispId,

    /// gc's deferred `speculativePourErr` (handler.go:259-266): the
    /// speculative pour failed AND the idempotency probe missed. Not fatal
    /// at pour time — the phase-2 reduce surfaces it as the
    /// `sling_failure` waiting_manual transition exactly when the gate
    /// outcome is non-terminal (handler.go:370-373); terminal outcomes
    /// swallow it, exactly like gc.
    @Default(false) bool pourFailed,
  }) = GateEvaluatedEvent;

  /// Operator approve (manual.go `ApproveHandler`, lines 20-115).
  /// [user] feeds `terminal_actor` as `operator:<user>` (manual.go:27).
  const factory ReducerEvent.operatorApprove({
    required String convergenceBeadId,
    required String user,
  }) = OperatorApproveEvent;

  /// Operator iterate (manual.go `IterateHandler`, lines 124-217).
  const factory ReducerEvent.operatorIterate({
    required String convergenceBeadId,
    required String user,
  }) = OperatorIterateEvent;

  /// Operator stop (manual.go `StopHandler`, lines 241-445).
  ///
  /// **Drain-then-requeue protocol (manual.go:272-314):** gc's
  /// `StopHandler`, finding the active wisp closed-but-unprocessed
  /// (closed, but `last_processed_wisp` has not caught up), runs the full
  /// `HandleWispClosed` INLINE — possibly a multi-minute fresh gate
  /// evaluation — re-reads metadata, and only then decides no-op vs
  /// force-close. The split reducer cannot block, so `reduce(operatorStop)`
  /// over that snapshot returns the synthesized wispClosed drain pipeline
  /// with `ReconcilerAction.requeue(operatorStop)` strictly LAST; Track G
  /// executes the drain (including any async `evaluateGate` hop) and
  /// re-enqueues this event behind it on the same per-bead serial queue
  /// **stamped [postDrain]`=true`** (the re-entry marker
  /// `RequeueAction.event` already carries; Track G must not strip it).
  /// The re-entry is absorbed idempotently: a drain that terminated the
  /// loop skips as `SkipReason.drainTerminated` /
  /// `SkipReason.alreadyStopped` (manual.go:296-308, 251-255); a surviving
  /// loop proceeds to the normal force-close/terminal
  /// `ReconcilerAction.stopped`.
  ///
  /// **Why [postDrain] is load-bearing (not cosmetic).** gc's monolithic
  /// `StopHandler` resolves a fact the split reducer loses to the snapshot:
  /// *who terminated the loop.* When gc's OWN inline drain terminates it,
  /// the drain return (manual.go:303-308) reports `ActionStopped`
  /// REGARDLESS of `terminal_reason` — a no-reason check, reachable only
  /// because the same call ran the drain. But a FRESH stop arriving on a
  /// loop that is already `terminated` with `terminal_reason != stopped`
  /// (e.g. `gate_passed` / `max_iterations` / `approved`) misses the
  /// top-of-handler idempotency no-op (manual.go:251-255 fires only on
  /// `terminal_reason == stopped`) and falls through to the state guard,
  /// which ERRORs (manual.go:258-263 — `terminated` is not `active` /
  /// `waiting_manual` / `waiting_trigger`). A reducer keying purely on the
  /// post-drain snapshot sees one shape — `operatorStop` over
  /// `terminated/non-stopped` — for BOTH causes and cannot tell them apart.
  /// [postDrain] restores the causality the snapshot dropped: `true` ⇒ my
  /// drain just terminated it ⇒ `SkipReason.drainTerminated` (wire
  /// `stopped`); `false` ⇒ a fresh stop on an already-terminated loop ⇒
  /// gc's error path (`ReconcilerAction.failed`, the
  /// `cannot stop bead … state is "terminated"` message). On a loop that is
  /// terminated *with* `terminal_reason == stopped`, both flag values
  /// collapse to the same idempotent `SkipReason.alreadyStopped`
  /// (manual.go:251-255), so the marker matters only for the non-stopped
  /// terminal reasons — exactly the rows gc disambiguates by causality.
  const factory ReducerEvent.operatorStop({
    required String convergenceBeadId,
    required String user,

    /// `true` only on the [ReconcilerAction.requeue] re-entry, after Track
    /// G ran the inline drain (manual.go:272-314). Marks "this stop already
    /// drained the closed active wisp; its termination, if any, is MINE"
    /// so the reducer maps `operatorStop` over `terminated/non-stopped` to
    /// `SkipReason.drainTerminated` (gc's no-reason `ActionStopped` return,
    /// manual.go:303-308) instead of the fresh-stop error path
    /// (manual.go:258-263). A first-arrival operator stop is always
    /// `false`. The snapshot alone cannot recover this — gc only knows
    /// because the same handler call ran the drain.
    @Default(false) bool postDrain,
  }) = OperatorStopEvent;

  /// The trigger condition passed for a `waiting_trigger` loop
  /// (trigger.go:96-101). [nextIteration] is the derived closed-wisp count
  /// + 1, computed by the trigger evaluator exactly as `HandleTrigger`
  /// does (trigger.go:77-83). A non-pass evaluation produces **no** event —
  /// gc returns `skipped` and re-evaluates next tick (trigger.go:97-98).
  const factory ReducerEvent.triggerPassed({
    required String convergenceBeadId,
    required int nextIteration,
  }) = TriggerPassedEvent;
}
