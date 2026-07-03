/// Track C — the recovery / full-reconcile pass (ADR-0003 Decision 2,
/// "Recovery paths"; M2 Track C, ⊣ A, B).
///
/// `ConvergenceRecovery.reconcile(snapshot) → RecoveryReport`: gc's
/// `Reconciler` (reconcile.go) ported as a PURE pass over a [GraphSnapshot].
/// For each non-closed convergence it dispatches on the `convergence.state`
/// reading and emits the recovery effects gc would perform — adopt/pour wisp 1,
/// terminate a partial creation, close a terminated-but-open root + re-emit,
/// re-announce a manual hold + repair its marker, recover/replay/pour an active
/// loop — preserving the 7 invariants and idempotent on re-run.
///
/// Runs at startup AND as a low-frequency backstop. The replay paths reuse
/// Track B's [ConvergenceReducer] (ADR-0000 A22 — reduce from the Go); the
/// non-replay paths carry plain-value recovery effects ([RecoveryAction]) with
/// their ordered writes encoded once. The orchestrator re-exports these from
/// the package barrel.
library;

export 'recovery_action.dart';
export 'recovery_event.dart';
export 'recovery_outcome.dart';
export 'recovery_pass.dart';
