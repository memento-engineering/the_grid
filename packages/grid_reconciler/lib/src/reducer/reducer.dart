/// Track B — the pure convergence reducer (ADR-0003 Decision 2).
///
/// `ConvergenceReducer.reduce(convergence, event, snapshot) → ReduceResult`:
/// gc's `HandleWispClosed` 9-step algorithm + the operator/trigger handlers,
/// ported 1:1 as a pure function. The orchestrator re-exports these from the
/// package barrel (`lib/grid_reconciler.dart`).
library;

export 'reduce.dart';
export 'reduce_result.dart';
