import '../convergence/convergence_metadata.dart';
import '../convergence/reconciler_action.dart';

/// The two recovery events `reconcile.go` emits directly, modelled as plain
/// immutable value types (Track C adds no freezed/json-generated types —
/// collision rule 2).
///
/// gc emits via `emitRecoveryEvent` (reconcile.go:685-690), which hard-codes
/// the **recovery flag = true** and routes the payload through
/// `Handler.withEventRig` (handler.go:860-895), stamping `convergence.rig` into
/// the payload's `rig` field (omitted when empty). Only TWO call sites emit:
/// `convergence.terminated` (Path 2 + `completeTerminalTransition`) and
/// `convergence.waiting_manual` (Path 3B). Everything else either emits nothing
/// or replays through `HandleWispClosed` with **recovery = false** (those
/// re-emits are carried as ordinary [ReconcilerAction]s on a replay outcome).
///
/// Event types/ids are byte-faithful to gc (events.go:11-20, 37-81).
sealed class RecoveryEvent {
  const RecoveryEvent();

  /// gc's event-type literal (`convergence.terminated` /
  /// `convergence.waiting_manual`).
  String get eventType;

  /// gc's stable, dedup-key event id.
  String get eventId;

  /// The convergence root bead the event concerns.
  String get convergenceBeadId;

  /// Always `true` — `emitRecoveryEvent` hard-codes the recovery flag
  /// (reconcile.go:689). Kept on the contract even though gc's production
  /// emitter drops it (cmd/gc/convergence_store.go:375-383; spec trap 19).
  bool get recovery => true;
}

/// `convergence.terminated`, event id `converge:<beadID>:terminated`
/// (events.go:11, EventIDTerminated). Emitted by Path 2
/// (reconcile.go:278-285) and `completeTerminalTransition`
/// (reconcile.go:563-570), **BEFORE** the `CloseBead` (at-least-once /
/// TierCritical — spec §11; a stable id lets consumers dedup the re-emit).
///
/// `finalStatus` is **always** `"closed"` (events.go), so it is not carried.
final class TerminatedRecoveryEvent extends RecoveryEvent {
  const TerminatedRecoveryEvent({
    required this.convergenceBeadId,
    required this.terminalReason,
    required this.totalIterations,
    required this.actor,
    required this.cumulativeDuration,
    this.rig,
  });

  @override
  final String convergenceBeadId;

  /// `TerminatedPayload.terminal_reason` — Path 2 defaults an empty stored
  /// reason to `no_convergence` (reconcile.go:266-269);
  /// `completeTerminalTransition` uses the stored value verbatim
  /// (reconcile.go:554).
  final TerminalReason terminalReason;

  /// `total_iterations` — closed-child count, 0 on derive error
  /// (reconcile.go:263, 560; error discarded).
  final int totalIterations;

  /// `actor` — the stored `terminal_actor`, defaulting to `"recovery"` when
  /// empty (the snapshot value, NOT the just-backfilled store value —
  /// reconcile.go:270-273, 555-558).
  final String actor;

  /// `cumulative_duration_ms` — Σ closed-child durations, 0 on error
  /// (reconcile.go:276, 561 → cumulativeDuration, reconcile.go:666-680).
  final Duration cumulativeDuration;

  /// `convergence.rig`, stamped by `withEventRig`; null ⇒ omit the field.
  final String? rig;

  @override
  String get eventType => RecoveryEventTypes.terminated;

  @override
  String get eventId => 'converge:$convergenceBeadId:terminated';

  @override
  String toString() =>
      'TerminatedRecoveryEvent($convergenceBeadId, reason=${terminalReason.wire}, '
      'iterations=$totalIterations, actor=$actor)';
}

/// `convergence.waiting_manual`, event id
/// `converge:<beadID>:iter:<N>:waiting_manual` (events.go:13, 49-51).
/// Emitted by Path 3B on **every** pass through the genuine-hold sub-path,
/// even when the final action is `no_action` (reconcile.go:312-325; the
/// stable id absorbs the repeats via consumer dedup — spec §7.2).
///
/// `iteration` is the silently-zero-defaulting decode of
/// `convergence.iteration` (reconcile.go:315, DecodeInt failure ignored), and
/// it flows into the event id — a missing field yields `:iter:0:` (spec trap
/// 14). `wispId` is the **pre-repair** `last_processed_wisp` (spec §11 / trap
/// 7). Recovery does not reconstruct verdict/gate-result fields — they stay
/// zero/null (spec §11).
final class WaitingManualRecoveryEvent extends RecoveryEvent {
  const WaitingManualRecoveryEvent({
    required this.convergenceBeadId,
    required this.iteration,
    required this.wispId,
    required this.reason,
    required this.cumulativeDuration,
    this.gateMode,
    this.rig,
  });

  @override
  final String convergenceBeadId;

  /// Decoded `convergence.iteration`, 0 on absent/invalid (reconcile.go:315).
  final int iteration;

  /// `wisp_id` = the PRE-repair `convergence.last_processed_wisp`
  /// (reconcile.go:316); `''` when absent (gc map semantics).
  final String wispId;

  /// `reason` = `convergence.waiting_reason` (the non-empty value that selected
  /// sub-path B — reconcile.go:302, 322).
  final WaitingReason reason;

  /// `cumulative_duration_ms` (reconcile.go:317).
  final Duration cumulativeDuration;

  /// `gate_mode` = `convergence.gate_mode` verbatim, `''` when absent
  /// (reconcile.go:321); null ⇒ the empty string.
  final String? gateMode;

  /// `convergence.rig` via `withEventRig`; null ⇒ omit.
  final String? rig;

  @override
  String get eventType => RecoveryEventTypes.waitingManual;

  @override
  String get eventId =>
      'converge:$convergenceBeadId:iter:$iteration:waiting_manual';

  @override
  String toString() =>
      'WaitingManualRecoveryEvent($convergenceBeadId, iter=$iteration, '
      'wisp=$wispId, reason=${reason.wire})';
}

/// gc's recovery event-type literals (events.go:11-13).
abstract final class RecoveryEventTypes {
  /// events.go:11 — `EventTerminated`.
  static const terminated = 'convergence.terminated';

  /// events.go:13 — `EventWaitingManual`.
  static const waitingManual = 'convergence.waiting_manual';
}
