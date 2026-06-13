import 'package:grid_controller/grid_controller.dart';
import '../convergence/convergence_metadata.dart';
import '../convergence/convergence_state.dart';
import '../convergence/idempotency_key.dart';
import '../convergence/reconciler_action.dart';
import '../convergence/reducer_event.dart';
import '../projections/convergence.dart';
import '../projections/wisp.dart';
import '../reducer/reduce.dart';

import 'recovery_action.dart';
import 'recovery_event.dart';
import 'recovery_outcome.dart';

/// The full-reconcile pass over a [GraphSnapshot] — the PURE port of gc's
/// `Reconciler` (reconcile.go:27-107), the startup + low-frequency-backstop
/// recovery that completes or repairs convergence loops interrupted by a crash.
///
/// gc detects candidates by listing `type=convergence` non-closed beads
/// (cmd/gc/convergence_tick.go:569; `IncludeClosed` defaults false — spec
/// §2.1) and runs `ReconcileBeads` over them in order. The grid pass takes the
/// same set straight off the snapshot: every **non-closed** convergence
/// projection (closed roots fully terminated never need recovery and never
/// appear in gc's scan). For each, it dispatches on the `convergence.state`
/// reading and emits a [RecoveryOutcome] — the action label gc would assign
/// plus the effects to actuate.
///
/// **Purity.** No `dart:io`, no `Process`, no SQL, no clock, no randomness:
/// `reconcile.go` has no time-based logic, so the pass is safe to run at any
/// cadence as long as per-bead processing is serialized (ADR-0003 invariant 7;
/// spec §1.4 / §12). Every effect — pours, closes, metadata writes, recovery
/// events — is returned as data; Track G actuates it (and supplies the live
/// store reads/find-before-pour gc's `Store` did inline). The two **replay**
/// paths reuse [ConvergenceReducer.reduce] (ADR-0000 A22 — reduce from the Go,
/// never re-implement the 9-step) rather than duplicating the algorithm.
///
/// **Idempotency.** Every path is a no-op on re-run over a snapshot reflecting
/// the first pass's writes (spec §12): absolute metadata writes, state-written-
/// last crash-resume ordering, idempotency-keyed pours, and the
/// `last_processed_wisp == active_wisp` commit short-circuit. The
/// [idempotency test suite] proves running the pass twice yields a second
/// all-`no_action` report.
///
/// **Coexistence (ADR-0003 Decision 6).** These are MUTATING paths — Track G
/// must never actuate them against a convergence bead gc's reconciler owns.
/// Shadow mode computes the would-be outcomes and diffs; it performs no writes.
abstract final class ConvergenceRecovery {
  /// Reconciles every non-closed convergence in [snapshot], in
  /// deterministic id order (gc scans in the store's list order; the grid
  /// sorts by id for a stable, snapshot-derived order). Returns one
  /// [RecoveryOutcome] per scanned convergence.
  static RecoveryReport reconcile(GraphSnapshot snapshot) {
    final convergences = _scan(snapshot);
    final outcomes = <RecoveryOutcome>[
      for (final c in convergences) reconcileBead(c, snapshot),
    ];
    return RecoveryReport(outcomes);
  }

  /// The candidate set: non-closed `convergence`-typed projections, sorted by
  /// id. gc's scan is "non-closed type==convergence" (spec trap 18) — `open`
  /// roots (freshly created, never started) DO reach Path 1a.
  static List<Convergence> _scan(GraphSnapshot snapshot) {
    final out = <Convergence>[];
    for (final bead in snapshot.beads) {
      if (bead.issueType != IssueType.convergence) continue;
      if (bead.status == BeadStatus.closed) continue;
      final result = Convergence.project(
        bead,
        dependencies: snapshot.dependencies,
        beadsById: snapshot.beadsById,
      );
      if (result case ProjectionOk<Convergence>(:final value)) out.add(value);
    }
    out.sort((a, b) => a.id.compareTo(b.id));
    return out;
  }

  /// Reconciles a single convergence — gc's `reconcileBead`
  /// (reconcile.go:64-107). Dispatches on the `convergence.state` reading.
  ///
  /// gc's `GetMetadata` read-failure branch (reconcile.go:65-68) has no analog
  /// here: the projection already carries decoded metadata, and a malformed
  /// map surfaces per-field on [ConvergenceMetadata.failures], not as a pass
  /// abort. The **unknown-state** branch (reconcile.go:101-106) IS reproduced —
  /// it is snapshot-derivable and surfaces drift loudly (spec trap 21).
  static RecoveryOutcome reconcileBead(
    Convergence convergence,
    GraphSnapshot snapshot,
  ) {
    final state = convergence.state;
    return switch (state) {
      // Path 1a — "" / not-adopted: adopt an existing wisp-1 or pour wisp 1.
      ConvergenceNotAdopted() => _missingState(convergence, snapshot),
      KnownConvergenceState(:final state) => switch (state) {
        ConvergenceState.creating => _creating(convergence),
        ConvergenceState.terminated => _terminatedNotClosed(convergence),
        ConvergenceState.waitingManual => _waitingManual(convergence),
        ConvergenceState.waitingTrigger => _waitingTrigger(convergence),
        ConvergenceState.active => _active(convergence, snapshot),
      },
      // reconcile.go:101-106 — unknown state: no_action + a loud error.
      UnrecognizedConvergenceState(:final rawValue) => RecoveryOutcome(
        convergenceBeadId: convergence.id,
        action: RecoveryActionLabel.noAction,
        error: 'unknown convergence state "${_stateText(rawValue)}"',
      ),
    };
  }

  // ===========================================================================
  // Path 1a — state "" : adopt or pour wisp 1 (reconcile.go:111-206)
  // ===========================================================================

  static RecoveryOutcome _missingState(
    Convergence convergence,
    GraphSnapshot snapshot,
  ) {
    final root = convergence.id;
    final key1 = idempotencyKey(root, 1);
    final existingId = convergence.findByIdempotencyKey(key1);

    if (existingId != null) {
      // Adopt the existing iteration-1 wisp (reconcile.go:123-171).
      final wisp = _wisp(convergence, existingId);
      // findByIdempotencyKey hit but the bead is not a projected wisp ⇒ a
      // dangling edge; gc's GetBead would resolve it. With no status to read
      // we treat it as not-closed (open/in_progress — no replay), matching
      // gc's "still live, don't replay" for anything != "closed".
      final adoptedClosed = wisp?.isClosed ?? false;
      final adopt = AdoptWispAction(
        convergenceBeadId: root,
        wispId: existingId,
        adoptedClosed: adoptedClosed,
      );
      // If the adopted wisp is closed, replay the transition so the loop does
      // not stall in `active` with a dead wisp (reconcile.go:159-168) — REUSE
      // the reducer, never re-implement (ADR-0000 A22). The adopt writes land
      // first (the outcome carries both); the replay is computed against the
      // SAME snapshot — its monotonic dedup + terminal guards make it safe.
      final replay = adoptedClosed
          ? _replay(convergence, snapshot, existingId)
          : const <ReconcilerAction>[];
      return RecoveryOutcome(
        convergenceBeadId: root,
        action: RecoveryActionLabel.adoptedWisp,
        recovery: adopt,
        replayActions: replay,
      );
    }

    // No wisp — pour the first one (reconcile.go:173-205).
    return RecoveryOutcome(
      convergenceBeadId: root,
      action: RecoveryActionLabel.pouredWisp,
      recovery: PourFirstWispAction(
        convergenceBeadId: root,
        pour: WispPour(
          parentBeadId: root,
          formula: convergence.metadata.formula ?? '',
          idempotencyKey: key1,
          iteration: 1,
          vars: convergence.metadata.vars,
          evaluatePrompt: convergence.metadata.evaluatePrompt,
        ),
      ),
    );
  }

  // ===========================================================================
  // Path 1b — state "creating" : terminate partial creation (reconcile.go:210)
  // ===========================================================================

  static RecoveryOutcome _creating(Convergence convergence) => RecoveryOutcome(
    convergenceBeadId: convergence.id,
    action: RecoveryActionLabel.completedTerminal,
    recovery: PartialCreationTerminateAction(convergenceBeadId: convergence.id),
  );

  // ===========================================================================
  // Path 2 — state "terminated" but not closed (reconcile.go:240-296)
  // ===========================================================================

  static RecoveryOutcome _terminatedNotClosed(Convergence convergence) {
    final root = convergence.id;
    // Guard: already fully terminated → no_action, no writes, no events
    // (reconcile.go:241-252). The candidate scan already drops closed roots,
    // but the guard is ported for the mid-tick backstop entry (spec §2.2).
    if (convergence.isClosed) return RecoveryOutcome.noAction(root);

    final meta = convergence.metadata;
    final storedActor = meta.terminalActor;
    // Reason defaults to no_convergence when empty (reconcile.go:266-269).
    final reason = meta.terminalReason ?? TerminalReason.noConvergence;
    // Actor: the SNAPSHOT value, "recovery" when empty — NOT the just-
    // backfilled store value (reconcile.go:270-273).
    final actor = (storedActor == null || storedActor.isEmpty)
        ? 'recovery'
        : storedActor;

    final event = TerminatedRecoveryEvent(
      convergenceBeadId: root,
      terminalReason: reason,
      totalIterations: convergence.closedWispCount,
      actor: actor,
      cumulativeDuration: _cumulativeDuration(convergence),
      rig: meta.rig,
    );

    return RecoveryOutcome(
      convergenceBeadId: root,
      action: RecoveryActionLabel.completedTerminal,
      recovery: CompleteTerminalAction(
        convergenceBeadId: root,
        event: event,
        // Backfill only when the snapshot value is empty (reconcile.go:604-609).
        backfillActor: storedActor == null || storedActor.isEmpty,
        // Path 2 never writes state (already terminated) and never repairs
        // last_processed_wisp (spec §6 — contrast completeTerminalTransition).
        writesState: false,
        lastProcessedWisp: null,
      ),
    );
  }

  // ===========================================================================
  // Path 3 — state "waiting_manual" (reconcile.go:300-372)
  // ===========================================================================

  static RecoveryOutcome _waitingManual(Convergence convergence) {
    final meta = convergence.metadata;
    final terminalReason = meta.terminalReason;
    final waitingReason = meta.waitingReason;

    // Sub-path A — terminal reason set: an interrupted stop (reconcile.go:306).
    // Checked BEFORE waiting_reason (spec §7.1, trap 8).
    if (terminalReason != null) {
      return _completeTerminalTransition(convergence);
    }

    // Sub-path B — genuine hold (reconcile.go:310-347).
    if (waitingReason != null) {
      return _genuineHold(convergence, waitingReason);
    }

    // Sub-path C — orphaned state (reconcile.go:349-371): no event.
    final highest = convergence.highestClosedWisp;
    if (highest != null) {
      return RecoveryOutcome(
        convergenceBeadId: convergence.id,
        action: RecoveryActionLabel.repairedState,
        recovery: RepairWaitingReasonAction(convergenceBeadId: convergence.id),
      );
    }
    return RecoveryOutcome.noAction(convergence.id);
  }

  static RecoveryOutcome _genuineHold(
    Convergence convergence,
    WaitingReason waitingReason,
  ) {
    final root = convergence.id;
    final meta = convergence.metadata;
    // Iteration: DecodeInt with silent-zero fallback (reconcile.go:315; trap
    // 14) — flows into the event id.
    final iteration = meta.iterationOrZero;
    // wisp_id = the PRE-repair last_processed_wisp (reconcile.go:316; trap 7).
    final preRepairWisp = meta.lastProcessedWisp ?? '';

    final event = WaitingManualRecoveryEvent(
      convergenceBeadId: root,
      iteration: iteration,
      wispId: preRepairWisp,
      reason: waitingReason,
      cumulativeDuration: _cumulativeDuration(convergence),
      // gate_mode verbatim (reconcile.go:321); '' when absent.
      gateMode: meta.gateMode.valueOrNull?.wire,
      rig: meta.rig,
    );

    // Repair last_processed_wisp ← highest closed wisp, ONLY when found AND
    // the stored marker disagrees (reconcile.go:336-345). The event fires on
    // every pass regardless of the outcome.
    final highest = convergence.highestClosedWisp;
    final needsRepair = highest != null && preRepairWisp != highest.id;
    return RecoveryOutcome(
      convergenceBeadId: root,
      action: needsRepair
          ? RecoveryActionLabel.repairedState
          : RecoveryActionLabel.noAction,
      recovery: WaitingManualRecoveryActionData(
        convergenceBeadId: root,
        event: event,
        repairLastProcessedWisp: needsRepair ? highest.id : null,
      ),
    );
  }

  // ===========================================================================
  // Path 3t — state "waiting_trigger" (reconcile.go:376-385)
  // ===========================================================================

  static RecoveryOutcome _waitingTrigger(Convergence convergence) {
    // Terminal reason set → complete the interrupted stop (reconcile.go:379).
    if (convergence.metadata.terminalReason != null) {
      return _completeTerminalTransition(convergence);
    }
    // Otherwise nothing: no wisp in flight; the tick re-evaluates the trigger
    // (reconcile.go:382-384). No reads, no writes, no events.
    return RecoveryOutcome.noAction(convergence.id);
  }

  // ===========================================================================
  // Path 4 — state "active" (reconcile.go:389-539)
  // ===========================================================================

  static RecoveryOutcome _active(
    Convergence convergence,
    GraphSnapshot snapshot,
  ) {
    final meta = convergence.metadata;

    // Sub-path A — interrupted stop (reconcile.go:392-394). Checked first.
    if (meta.terminalReason != null) {
      return _completeTerminalTransition(convergence);
    }

    // Sub-path B — active_wisp set (reconcile.go:396-473).
    final activeWispId = meta.activeWisp;
    if (activeWispId != null) {
      final resolved = convergence.activeWisp;
      if (resolved != null) {
        // The pointer resolves — gc's GetBead succeeds. Branch on status.
        return _activeWithWisp(
          convergence,
          snapshot,
          wisp: resolved,
          recovered: false,
        );
      }
      // The pointer DANGLES (set, bead gone) — gc's ErrNotFound branch
      // (reconcile.go:402-425): recover a replacement. A transient store
      // failure (gc's non-ErrNotFound branch, reconcile.go:402-408) cannot
      // arise from a pure snapshot read, so only the not-found path applies.
      // This is the SELECTION conformance test 16 pins (the NotFound-vs-
      // transient branch); the pure-pass analog — a dangling pointer always
      // taking the recovery arm, never spuriously erroring — is asserted in
      // recovery_pass_test.dart test 16. The live transient-read contract
      // itself belongs to the Track G actuation seam, which owns the fallible
      // store read gc's `Store.GetBead` did inline.
      final recovered = _recoverActiveWisp(convergence);
      if (recovered == null) {
        // Stale recovery state — fall through to derive-and-pour
        // (reconcile.go:416-421).
        return _activeEmptyOrStale(convergence);
      }
      // Persist the recovered pointer BEFORE inspecting status
      // (reconcile.go:428-435; trap 11), then branch on status.
      return _activeWithWisp(
        convergence,
        snapshot,
        wisp: recovered,
        recovered: true,
      );
    }

    // Sub-path B′ — active_wisp empty (reconcile.go:475-538).
    return _activeEmptyOrStale(convergence);
  }

  /// Status switch for a resolved/recovered active wisp (reconcile.go:436-471).
  static RecoveryOutcome _activeWithWisp(
    Convergence convergence,
    GraphSnapshot snapshot, {
    required Wisp wisp,
    required bool recovered,
  }) {
    final root = convergence.id;
    final repair = recovered
        ? RepairActiveWispAction(convergenceBeadId: root, wispId: wisp.id)
        : null;

    final status = wisp.status;
    final isOpenOrInProgress =
        status == BeadStatus.open || status == BeadStatus.inProgress;
    if (isOpenOrInProgress) {
      // open / in_progress — wisp still running. no_action, or repaired_state
      // when the pointer was just recovered (reconcile.go:437-443).
      return RecoveryOutcome(
        convergenceBeadId: root,
        action: recovered
            ? RecoveryActionLabel.repairedState
            : RecoveryActionLabel.noAction,
        recovery: repair,
      );
    }

    if (!wisp.isClosed) {
      // gc's switch default: a status outside {open, in_progress, closed} →
      // no_action + a loud error (reconcile.go:466-470; spec G4). The grid's
      // open-extension-type BeadStatus CAN carry such a value, unlike a sealed
      // enum, so this arm is reachable. The recovered-pointer repair still
      // stands (persisted before the status switch — trap 11).
      return RecoveryOutcome(
        convergenceBeadId: root,
        action: RecoveryActionLabel.noAction,
        recovery: repair,
        error:
            'active wisp "${wisp.id}" has unexpected status "${status.wire}"',
      );
    }

    // closed — already processed? (reconcile.go:445-453). last_processed_wisp
    // == active_wisp ⇒ the commit completed (it is always the last write).
    final lpw = convergence.metadata.lastProcessedWisp;
    if (lpw == wisp.id) {
      return RecoveryOutcome(
        convergenceBeadId: root,
        action: recovered
            ? RecoveryActionLabel.repairedState
            : RecoveryActionLabel.noAction,
        recovery: repair,
      );
    }

    // Closed but unprocessed — REPLAY through the reducer (reconcile.go:455-464;
    // ADR-0000 A22). Both branches report `repaired_state`. When the pointer
    // was recovered, the repair write precedes the replay plan.
    return RecoveryOutcome(
      convergenceBeadId: root,
      action: RecoveryActionLabel.repairedState,
      recovery: repair,
      replayActions: _replay(convergence, snapshot, wisp.id),
    );
  }

  /// Sub-path B′ — pour or adopt the next wisp (reconcile.go:475-538).
  static RecoveryOutcome _activeEmptyOrStale(Convergence convergence) {
    final root = convergence.id;
    final meta = convergence.metadata;
    final closedIter = convergence.closedWispCount;
    final nextIter = closedIter + 1;
    final nextKey = idempotencyKey(root, nextIter);

    // Priority 1: a valid pending_next_wisp (reconcile.go:492).
    final pending = _validPendingNextWisp(convergence, nextKey);
    if (pending != null) {
      return RecoveryOutcome(
        convergenceBeadId: root,
        action: RecoveryActionLabel.adoptedWisp,
        recovery: PourNextWispAction(
          convergenceBeadId: root,
          adoptWispId: pending,
          pour: null,
          activates: true,
        ),
      );
    }

    // Priority 2: an existing wisp for the next iteration (reconcile.go:496).
    final existing = convergence.findByIdempotencyKey(nextKey);
    if (existing != null) {
      return RecoveryOutcome(
        convergenceBeadId: root,
        action: RecoveryActionLabel.adoptedWisp,
        recovery: PourNextWispAction(
          convergenceBeadId: root,
          adoptWispId: existing,
          pour: null,
          activates: true,
        ),
      );
    }

    // Priority 3: pour (reconcile.go:507-520).
    return RecoveryOutcome(
      convergenceBeadId: root,
      action: RecoveryActionLabel.pouredWisp,
      recovery: PourNextWispAction(
        convergenceBeadId: root,
        adoptWispId: null,
        pour: WispPour(
          parentBeadId: root,
          formula: meta.formula ?? '',
          idempotencyKey: nextKey,
          iteration: nextIter,
          vars: meta.vars,
          evaluatePrompt: meta.evaluatePrompt,
        ),
        activates: true,
      ),
    );
  }

  // ===========================================================================
  // completeTerminalTransition (reconcile.go:545-600) — Paths 3A, 3tA, 4A
  // ===========================================================================

  static RecoveryOutcome _completeTerminalTransition(Convergence convergence) {
    final root = convergence.id;
    final meta = convergence.metadata;
    final storedActor = meta.terminalActor;
    // No reason default here — reachable only when terminal_reason is non-empty
    // (spec trap 5). Fall back to no_convergence defensively (a precondition
    // violation would otherwise carry a null).
    final reason = meta.terminalReason ?? TerminalReason.noConvergence;
    final actor = (storedActor == null || storedActor.isEmpty)
        ? 'recovery'
        : storedActor;

    final event = TerminatedRecoveryEvent(
      convergenceBeadId: root,
      terminalReason: reason,
      totalIterations: convergence.closedWispCount,
      actor: actor,
      cumulativeDuration: _cumulativeDuration(convergence),
      rig: meta.rig,
    );

    // state ← terminated ONLY when the snapshot state ≠ terminated
    // (reconcile.go:573). last_processed_wisp ← highest closed wisp, LAST,
    // only when one exists (reconcile.go:592-597).
    final alreadyTerminated =
        meta.state.stateOrNull == ConvergenceState.terminated;
    final highest = convergence.highestClosedWisp;

    return RecoveryOutcome(
      convergenceBeadId: root,
      action: RecoveryActionLabel.completedTerminal,
      recovery: CompleteTerminalAction(
        convergenceBeadId: root,
        event: event,
        backfillActor: storedActor == null || storedActor.isEmpty,
        writesState: !alreadyTerminated,
        lastProcessedWisp: highest?.id,
      ),
    );
  }

  // ===========================================================================
  // Shared helpers
  // ===========================================================================

  /// Replays the closed [wispId] through the reducer (ADR-0000 A22): build a
  /// synthetic [WispClosedEvent] and reduce it against [snapshot]. gc calls
  /// `Handler.HandleWispClosed` directly (reconcile.go:162, 456); the grid
  /// reuses the SAME pure reducer Track G drives on the live path, so the
  /// recovery replay and live processing produce identical transition plans.
  static List<ReconcilerAction> _replay(
    Convergence convergence,
    GraphSnapshot snapshot,
    String wispId,
  ) {
    final result = ConvergenceReducer.reduce(
      convergence,
      ReducerEvent.wispClosed(
        convergenceBeadId: convergence.id,
        wispId: wispId,
      ),
      snapshot,
    );
    return result.actions;
  }

  /// `cumulativeDuration` (reconcile.go:666-680): Σ (closedAt − createdAt) over
  /// closed convergence-keyed children with both timestamps present, 0 on any
  /// missing timestamp. Pure over the projection's wisps.
  static Duration _cumulativeDuration(Convergence convergence) {
    var total = Duration.zero;
    for (final wisp in convergence.wisps) {
      if (!wisp.isClosed) continue;
      final created = wisp.createdAt;
      final closed = wisp.closedAt;
      // gc requires BOTH timestamps non-zero (reconcile.go:674-676); a closed
      // wisp without a real close timestamp contributes 0 (trap 16 — note this
      // uses the raw closedAt, NOT effectiveClosedAt's createdAt fallback).
      if (created == null || closed == null) continue;
      final d = closed.difference(created);
      if (d.isNegative) continue;
      total += d;
    }
    return total;
  }

  /// gc `validPendingNextWisp` as a pure snapshot read (handler.go:935-945,
  /// the same logic Track B ports): the stored `pending_next_wisp` is valid iff
  /// it names a child of this root whose key == [nextKey] and is NOT closed.
  /// Returns the id or null. (The stale-clear side effect is a Track-G concern;
  /// Path 4's pour branch clears `pending_next_wisp` unconditionally anyway —
  /// reconcile.go:536.)
  static String? _validPendingNextWisp(
    Convergence convergence,
    String nextKey,
  ) {
    final pending = convergence.metadata.pendingNextWisp;
    if (pending == null) return null;
    final wisp = _wisp(convergence, pending);
    if (wisp == null) return null;
    if (wisp.idempotencyKey != nextKey) return null;
    if (wisp.isClosed) return null;
    return pending;
  }

  /// gc `recoverCurrentActiveWisp` (manual.go:447-518) as a pure snapshot read
  /// — the same algorithm Track B ports for the operator-stop dangling case.
  /// Anchored search off `last_processed + 1` (no fallback scan when anchored),
  /// else an unanchored scan preferring the highest-iteration OPEN wisp, then
  /// the highest CLOSED one. Returns null when nothing qualifies.
  static Wisp? _recoverActiveWisp(Convergence convergence) {
    final lpw = convergence.metadata.lastProcessedWisp;
    if (lpw != null && lpw.isNotEmpty) {
      final lastWisp = _wisp(convergence, lpw);
      final lastIter = lastWisp?.iteration;
      if (lastIter != null) {
        final nextKey = idempotencyKey(convergence.id, lastIter + 1);
        final candidateId = convergence.findByIdempotencyKey(nextKey);
        if (candidateId == null) return null; // anchored: no fallback scan.
        return _wisp(convergence, candidateId);
      }
    }
    Wisp? bestOpen;
    var bestOpenIter = -1;
    Wisp? bestClosed;
    var bestClosedIter = -1;
    for (final wisp in convergence.wisps) {
      final iter = wisp.iteration;
      if (iter == null) continue;
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

  static Wisp? _wisp(Convergence convergence, String wispId) {
    for (final wisp in convergence.wisps) {
      if (wisp.id == wispId) return wisp;
    }
    return null;
  }

  /// gc prints the unknown state via `%q` on the raw `meta[FieldState]` string
  /// (reconcile.go:104). A non-String raw value cannot occur in gc (the field
  /// is a string map), but the projection's reading can carry one — render it
  /// through toString for a stable, non-crashing message.
  static String _stateText(Object? rawValue) =>
      rawValue is String ? rawValue : '$rawValue';
}
