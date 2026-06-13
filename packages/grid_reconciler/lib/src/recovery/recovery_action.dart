import '../convergence/convergence_metadata.dart';
import '../convergence/convergence_state.dart';
import '../convergence/reconciler_action.dart';
import '../convergence/reducer_event.dart';
import '../reducer/reduce.dart';

import 'recovery_event.dart';

/// The recovery-pass label for one reconciled convergence — gc's
/// `ReconcileDetail.Action` (reconcile.go:15), one of exactly these five
/// literals. **On failure the label is the *attempted* action**, not a
/// completed recovery (spec §1.1); the pass is pure (no I/O) so the_grid's
/// failures are surfaced by Track G at actuation time, but the label is fixed
/// at reduce time exactly as gc fixes it.
enum RecoveryActionLabel {
  /// reconcile.go:15 — partial-creation terminate, terminated-but-open close,
  /// interrupted-stop completion.
  completedTerminal('completed_terminal'),

  /// An existing wisp adopted (Path 1a wisp-exists, Path 4 pending/existing
  /// next).
  adoptedWisp('adopted_wisp'),

  /// A wisp poured (Path 1a no-wisp, Path 4 pour-next).
  pouredWisp('poured_wisp'),

  /// A metadata marker repaired (Path 3B/3C, Path 4 recovered-pointer).
  repairedState('repaired_state'),

  /// No recovery needed.
  noAction('no_action');

  const RecoveryActionLabel(this.wire);

  /// gc's exact `ReconcileDetail.Action` string (reconcile.go:15).
  final String wire;
}

/// One recovery effect, as **data** — the Track-C analog of [ReconcilerAction]
/// for the effects `reconcile.go` performs that have no normal-path
/// [ReconcilerAction] variant (adopt-wisp-1, pour-wisp-1, partial-creation
/// terminate, terminated-but-open close, marker repair, recovered-pointer
/// write). A plain immutable sealed union: Track C adds no freezed types
/// (collision rule 2).
///
/// Each variant exposes its **ordered** metadata-write sequence (and any
/// close / recovery-event emission) so the recovery-ordering invariants
/// (ADR-0003 invariants 2, 4; the at-least-once emit-before-close and the
/// state-written-last crash-resume contracts — spec traps 2-4) are encoded
/// once, here, and cannot be re-derived wrongly by an actuator.
///
/// The two **replay** paths (Path 1a closed-adopt, Path 4 closed-unprocessed)
/// do NOT appear here: they reuse [ConvergenceReducer.reduce] over a synthetic
/// [WispClosedEvent] and carry its [ReconcilerAction]s on the
/// [RecoveryOutcome] directly (`reduce`-from-the-Go, ADR-0000 A22). See
/// [RecoveryOutcome.replayActions].
sealed class RecoveryAction {
  const RecoveryAction();

  /// The convergence root this effect concerns.
  String get convergenceBeadId;
}

/// Path 1a wisp-exists adopt (reconcile.go:123-171): point `active_wisp` at the
/// pre-existing iteration-1 wisp and flip to `active`. **Ordered writes**
/// (reconcile.go:133-157): `active_wisp` → `iteration` → `state`, state LAST so
/// a half-completed adopt re-enters Path 1a (spec trap 2).
///
/// ⚠ Iteration asymmetry (reconcile.go:140-145; spec trap 1): `"1"` when the
/// adopted wisp is **closed** (iteration 1 demonstrably completed), `"0"` when
/// still open (`HandleWispClosed` derives the real count when it closes).
/// Writing `"1"` everywhere corrupts the closed-children invariant (Inv 4).
///
/// If the adopted wisp is closed, the loop must not stall in `active` with a
/// dead wisp — the closed-adopt is a **replay** path and is therefore NOT
/// modelled by this action; it carries the reducer's
/// [ReconcilerAction]s on the outcome instead (see [RecoveryOutcome]).
final class AdoptWispAction extends RecoveryAction {
  const AdoptWispAction({
    required this.convergenceBeadId,
    required this.wispId,
    required this.adoptedClosed,
  });

  @override
  final String convergenceBeadId;

  /// The existing iteration-1 wisp to adopt as `active_wisp`.
  final String wispId;

  /// True iff the adopted wisp's status is **exactly** `closed`
  /// (reconcile.go:143) — selects the iteration value and (on the outcome)
  /// the replay.
  final bool adoptedClosed;

  /// Ordered writes (reconcile.go:133-157), `state` LAST.
  List<MetadataWrite> get orderedWrites => [
    MetadataWrite(key: ConvergenceFields.activeWisp, value: wispId),
    MetadataWrite(
      key: ConvergenceFields.iteration,
      // 1 if the adopted wisp is closed, else 0 (reconcile.go:140-145).
      value: adoptedClosed ? '1' : '0',
    ),
    MetadataWrite(
      key: ConvergenceFields.state,
      value: ConvergenceState.active.wire,
    ),
  ];
}

/// Path 1a no-wisp pour (reconcile.go:173-205): pour the first wisp and
/// activate the loop. **Ordered writes** (reconcile.go:178-203):
/// `PourWisp` → `active_wisp` → `iteration` = `"0"` → `state` = `active`,
/// state LAST.
///
/// ⚠ Iteration is `"0"`, NOT `1` — `convergence.iteration` counts **closed**
/// wisps (Inv 4; spec trap 1). The pour is **visible** (`PourWisp`, not
/// speculative) with **no** activation call here (reconcile.go:178; spec §4.2).
/// Idempotency: re-running lands in the adopt branch (the key lookup finds the
/// wisp poured last time); all metadata writes are absolute (spec §4.2).
final class PourFirstWispAction extends RecoveryAction {
  const PourFirstWispAction({
    required this.convergenceBeadId,
    required this.pour,
  });

  @override
  final String convergenceBeadId;

  /// The visible (non-speculative) iteration-1 pour. The actuator applies the
  /// find-before-pour obligation ([WispPour]); on a hit it adopts and the
  /// post-pour writes use the existing wisp id.
  final WispPour pour;

  /// Ordered writes after the pour resolves to [nextWispId], `state` LAST.
  List<MetadataWrite> postPourWrites(String nextWispId) => [
    MetadataWrite(key: ConvergenceFields.activeWisp, value: nextWispId),
    // 0, not 1 — counts closed wisps (reconcile.go:192; spec trap 1).
    const MetadataWrite(key: ConvergenceFields.iteration, value: '0'),
    MetadataWrite(
      key: ConvergenceFields.state,
      value: ConvergenceState.active.wire,
    ),
  ];
}

/// Path 1b partial-creation terminate (reconcile.go:210-236): an interrupted
/// `creating` flow — stamp the terminal reason and close. **Ordered writes**
/// (reconcile.go:211-234): `terminal_reason` = `partial_creation` →
/// `terminal_actor` = `recovery` → `state` = `terminated` → `CloseBead`.
///
/// **No event** (spec §5): a partial creation never announced itself, so there
/// is nothing to re-announce — unlike Path 2. Idempotency: a crash before the
/// state write re-enters Path 1b; after it (pre-close) re-enters Path 2.
final class PartialCreationTerminateAction extends RecoveryAction {
  const PartialCreationTerminateAction({required this.convergenceBeadId});

  @override
  final String convergenceBeadId;

  /// Ordered writes BEFORE the close (reconcile.go:211-228).
  List<MetadataWrite> get orderedWrites => [
    MetadataWrite(
      key: ConvergenceFields.terminalReason,
      value: TerminalReason.partialCreation.wire,
    ),
    const MetadataWrite(
      key: ConvergenceFields.terminalActor,
      value: 'recovery',
    ),
    MetadataWrite(
      key: ConvergenceFields.state,
      value: ConvergenceState.terminated.wire,
    ),
  ];

  /// The close, AFTER the ordered writes
  /// ([CloseReasons.reconcileDone] — reconcile.go:229).
  String get closeReason => CloseReasons.reconcileDone;
}

/// Path 2 terminated-but-open close (reconcile.go:240-296) and
/// `completeTerminalTransition` (reconcile.go:545-600): finish an interrupted
/// terminal transition.
///
/// ⚠ Ordering — the most order-sensitive recovery effect (spec traps 3, 4):
/// 1. backfill `terminal_actor` = `recovery` ([backfillActor]) **only if** the
///    snapshot value is empty;
/// 2. **EMIT** [event] (`convergence.terminated`, recovery=true) — BEFORE the
///    state write and the close (at-least-once / TierCritical);
/// 3. [stateWrite] `state` = `terminated` — Path 2 already has it
///    ([writesState] false); `completeTerminalTransition` writes it only when
///    the snapshot state ≠ terminated (reconcile.go:573-580);
/// 4. `CloseBead` ([closeReason]);
/// 5. [commitWrite] `last_processed_wisp` = highest-closed-wisp id — LAST,
///    after the close, **only** when a closed wisp exists
///    (`completeTerminalTransition` only; Path 2 omits it entirely — spec §6).
final class CompleteTerminalAction extends RecoveryAction {
  const CompleteTerminalAction({
    required this.convergenceBeadId,
    required this.event,
    required this.backfillActor,
    required this.writesState,
    required this.lastProcessedWisp,
  });

  @override
  final String convergenceBeadId;

  /// The `convergence.terminated` recovery event, emitted FIRST (step 2).
  final TerminatedRecoveryEvent event;

  /// `terminal_actor` ← `recovery`, applied FIRST, **only** when the snapshot
  /// value was empty (reconcile.go:604-609; never overwrites — spec trap 6).
  final bool backfillActor;

  /// Whether to write `state` = `terminated` (step 3). False on Path 2 (already
  /// terminated) and on `completeTerminalTransition` when the snapshot state is
  /// already terminated (reconcile.go:573).
  final bool writesState;

  /// The highest-closed-wisp id for the final `last_processed_wisp` write
  /// (step 5), or null to skip — Path 2 always null; `completeTerminalTransition`
  /// only when a closed wisp exists (reconcile.go:592-597).
  final String? lastProcessedWisp;

  /// `terminal_actor` backfill, applied FIRST (reconcile.go:604-609).
  MetadataWrite? get actorBackfillWrite => backfillActor
      ? const MetadataWrite(
          key: ConvergenceFields.terminalActor,
          value: 'recovery',
        )
      : null;

  /// `state` ← terminated (step 3), or null to skip.
  MetadataWrite? get stateWrite => writesState
      ? MetadataWrite(
          key: ConvergenceFields.state,
          value: ConvergenceState.terminated.wire,
        )
      : null;

  /// The close ([CloseReasons.reconcileDone] — reconcile.go:288, 583).
  String get closeReason => CloseReasons.reconcileDone;

  /// The final `last_processed_wisp` write (LAST, after the close), or null.
  MetadataWrite? get commitWrite => lastProcessedWisp == null
      ? null
      : MetadataWrite(
          key: ConvergenceFields.lastProcessedWisp,
          value: lastProcessedWisp!,
        );
}

/// Path 3B genuine-hold (reconcile.go:310-347): re-announce the hold and
/// repair the dedup marker.
///
/// 1. **EMIT** [event] (`convergence.waiting_manual`, recovery=true) — on
///    EVERY pass, even when the outcome is `no_action` (spec §7.2 / trap 8);
/// 2. **repair** `last_processed_wisp` ← [repairWrite] **only** when a highest
///    closed wisp exists AND the stored marker disagrees (reconcile.go:336-345);
///    otherwise no write.
final class WaitingManualRecoveryActionData extends RecoveryAction {
  const WaitingManualRecoveryActionData({
    required this.convergenceBeadId,
    required this.event,
    required this.repairLastProcessedWisp,
  });

  @override
  final String convergenceBeadId;

  /// The `convergence.waiting_manual` recovery event, emitted FIRST.
  final WaitingManualRecoveryEvent event;

  /// The highest-closed-wisp id to repair `last_processed_wisp` to, or null
  /// when no repair is needed (marker already correct, or no closed wisp).
  final String? repairLastProcessedWisp;

  /// The marker repair write (reconcile.go:338), or null to skip.
  MetadataWrite? get repairWrite => repairLastProcessedWisp == null
      ? null
      : MetadataWrite(
          key: ConvergenceFields.lastProcessedWisp,
          value: repairLastProcessedWisp!,
        );
}

/// Path 3C orphaned-state repair (reconcile.go:349-371): a `waiting_manual`
/// hold with **neither** `waiting_reason` nor `terminal_reason`, but closed
/// wisps present → stamp `waiting_reason` = `manual` so operator commands
/// behave. **No event** (spec §7.3).
final class RepairWaitingReasonAction extends RecoveryAction {
  const RepairWaitingReasonAction({required this.convergenceBeadId});

  @override
  final String convergenceBeadId;

  /// `waiting_reason` ← `manual` (reconcile.go:362; `WaitManual`,
  /// metadata.go:98).
  MetadataWrite get write => MetadataWrite(
    key: ConvergenceFields.waitingReason,
    value: WaitingReason.manual.wire,
  );
}

/// Path 4 sub-path B′ pour-or-adopt-next (reconcile.go:475-538): `active_wisp`
/// was cleared (or stale) but the loop did not yet point at the next wisp.
///
/// Wisp selection is three-way, in priority order (reconcile.go:489-521):
/// validated `pending_next_wisp`, then `FindByIdempotencyKey(nextKey)`, then
/// pour. The reducer resolves which here ([pour] is null on the adopt
/// branches). **Ordered writes** (reconcile.go:523-536): `ActivateWisp` →
/// `active_wisp` → clear `pending_next_wisp` (best-effort).
///
/// ⚠ Does NOT write `iteration` (self-heals at handler step 3) or `state`
/// (already active) — spec trap 14.
final class PourNextWispAction extends RecoveryAction {
  const PourNextWispAction({
    required this.convergenceBeadId,
    required this.adoptWispId,
    required this.pour,
    required this.activates,
  });

  @override
  final String convergenceBeadId;

  /// An existing wisp id to adopt (validated pending or
  /// find-by-key hit), or null when [pour] must run.
  final String? adoptWispId;

  /// The visible pour for the next iteration, or null when [adoptWispId] is
  /// set.
  final WispPour? pour;

  /// `ActivateWisp(wispID)` is always called (reconcile.go:523), idempotent
  /// when the wisp is already active.
  final bool activates;

  /// Whether this branch poured (true) or adopted (false) — selects the
  /// [RecoveryActionLabel] (`poured_wisp` vs `adopted_wisp`).
  bool get poured => pour != null;

  /// Ordered writes after the wisp resolves to [wispId] (reconcile.go:530-536).
  /// `pending_next_wisp` ← `''` is best-effort LAST (error discarded by gc).
  List<MetadataWrite> postWrites(String wispId) => [
    MetadataWrite(key: ConvergenceFields.activeWisp, value: wispId),
    const MetadataWrite(key: ConvergenceFields.pendingNextWisp, value: ''),
  ];
}

/// The recovered-pointer write for Path 4 sub-path B when
/// `recoverCurrentActiveWisp` finds a replacement: `active_wisp` ←
/// recovered id, written **immediately, before** the status switch
/// (reconcile.go:428-435; spec trap 11). Even an `open` recovered wisp
/// produces this write (and action `repaired_state`).
final class RepairActiveWispAction extends RecoveryAction {
  const RepairActiveWispAction({
    required this.convergenceBeadId,
    required this.wispId,
  });

  @override
  final String convergenceBeadId;

  /// The recovered wisp id.
  final String wispId;

  /// `active_wisp` ← [wispId] (reconcile.go:429).
  MetadataWrite get write =>
      MetadataWrite(key: ConvergenceFields.activeWisp, value: wispId);
}
