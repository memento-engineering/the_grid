/// Track G — the reconciler runtime + shadow mode (ADR-0003 Decision 2 & 6).
///
/// The composition that makes the convergence machine actually run: it ingests
/// grid_controller's `GraphEvent` stream, serializes per-bead processing
/// (invariant 7), runs gc's reduce→gate→actuate cycle (the A22 phase split + the
/// A19 operator-stop drain) evaluated against post-actuation state (the A17
/// write-through overlay), actuates only loops the_grid owns (the Decision 6
/// coexistence partition), backstops with the Track C periodic full reconcile,
/// and honors the A25 deferred live-error contract. SHADOW MODE
/// ([ShadowRuntime]) computes the would-be transitions and diffs them against
/// gc's — constructing NO writer at all (strictly read-only).
library;

export 'convergence_source.dart';
export 'cycle_outcome.dart';
export 'gate_evaluator.dart';
export 'graph_event_adapter.dart';
export 'ownership.dart';
export 'per_bead_queue.dart';
export 'reconciler_runtime.dart';
export 'shadow_runtime.dart';
export 'write_through_overlay.dart';
