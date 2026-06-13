import '../convergence/reconciler_action.dart';
import '../convergence/reducer_event.dart';
import '../reducer/reduce.dart';

import 'recovery_action.dart';

/// The recovery-pass result for one convergence — gc's `ReconcileDetail`
/// (reconcile.go:13-17), realized as **data**: the action label plus the
/// effects to actuate.
///
/// Two effect channels, mutually exclusive in practice:
///
/// * [recovery] — the recovery-specific effect ([RecoveryAction]) for the
///   non-replay paths (adopt/pour wisp 1, partial-creation terminate,
///   terminated-but-open close, marker repair, recovered-pointer write).
/// * [replayActions] — the [ReconcilerAction]s produced by reusing
///   [ConvergenceReducer.reduce] over a synthetic [WispClosedEvent] on the two
///   **replay** paths (Path 1a closed-adopt, Path 4 closed-unprocessed). The
///   recovery pass does NOT re-implement the 9-step (ADR-0000 A22): it adopts
///   the pointer first ([recovery], where applicable) and then carries the
///   reducer's transition plan here. Empty on the non-replay paths.
///
/// [error] mirrors gc's `ReconcileDetail.Error`. The recovery pass is PURE (no
/// I/O), so it never surfaces a store error itself — [error] is reserved for
/// the deterministic, snapshot-derivable failure gc reports without touching
/// the store: the **unknown-state** branch (reconcile.go:101-106), which fixes
/// the label to `no_action` and the message to `unknown convergence state %q`.
/// Live-store failures (gc's `GetMetadata`/`GetBead`/`PourWisp` errors) belong
/// to Track G actuation, not this pure pass.
class RecoveryOutcome {
  const RecoveryOutcome({
    required this.convergenceBeadId,
    required this.action,
    this.recovery,
    this.replayActions = const [],
    this.error,
  });

  /// A `no_action` outcome with no effects — the clean / nothing-to-do case.
  const RecoveryOutcome.noAction(String convergenceBeadId)
    : this(
        convergenceBeadId: convergenceBeadId,
        action: RecoveryActionLabel.noAction,
      );

  /// The convergence root bead (gc's `ReconcileDetail.BeadID`).
  final String convergenceBeadId;

  /// gc's `ReconcileDetail.Action` (the *attempted* action on failure).
  final RecoveryActionLabel action;

  /// The recovery-specific effect for non-replay paths, or null.
  final RecoveryAction? recovery;

  /// The reused-reducer transition plan for the replay paths, or empty.
  final List<ReconcilerAction> replayActions;

  /// gc's `ReconcileDetail.Error` — non-null only for the unknown-state branch
  /// (see class doc). The message is gc's verbatim
  /// `unknown convergence state "<state>"` (reconcile.go:104).
  final String? error;

  bool get hasError => error != null;

  /// Whether this outcome carries any work — gc's `Recovered` predicate
  /// (`Error == nil && Action != "no_action"`, reconcile.go:53-55).
  bool get recovered => !hasError && action != RecoveryActionLabel.noAction;

  @override
  String toString() =>
      'RecoveryOutcome($convergenceBeadId, ${action.wire}'
      '${hasError ? ', error="$error"' : ''})';
}

/// The whole-pass summary — gc's `ReconcileReport` (reconcile.go:20-25) with
/// the **`if/else if` accounting** preserved exactly (reconcile.go:51-55; spec
/// trap 17): an errored outcome increments [errors] only, **never**
/// [recovered], even when its action label is a recovery action.
class RecoveryReport {
  RecoveryReport(this.outcomes)
    : scanned = outcomes.length,
      recovered = outcomes.where((o) => o.recovered).length,
      errors = outcomes.where((o) => o.hasError).length;

  /// One outcome per scanned convergence, **in input order**
  /// (reconcile.go:50; Details preserve order).
  final List<RecoveryOutcome> outcomes;

  /// `len(beadIDs)` (reconcile.go:44-46) — includes erroring beads.
  final int scanned;

  /// Count of outcomes with no error AND a non-`no_action` label.
  final int recovered;

  /// Count of outcomes with an error (regardless of action label).
  final int errors;

  @override
  String toString() =>
      'RecoveryReport(scanned=$scanned, recovered=$recovered, errors=$errors)';
}
