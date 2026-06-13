import '../convergence/reconciler_action.dart';
import '../projections/convergence.dart';
import '../projections/wisp.dart';
import '../reducer/reduce_result.dart';

/// The ACTUATOR seam (ADR-0003 Decision 4): the ONLY component in the_grid
/// that **writes**. It turns a reducer's [ReduceResult] — Track A's ordered,
/// data-encoded effect plan — into the exact sequence of bd mutations gc would
/// perform in-process, executed through grid_controller's bd surface
/// (`bd update --metadata` / `bd close` / `bd delete` / `bd cook` +
/// `bd create --graph`).
///
/// **Why a seam:** the reducer is pure and the actuator is all I/O; the seam
/// lets tests drive the full convergence machine with a [FakeActuator] that
/// records the call sequence, and lets Track G compose a real [BdActuator]
/// over the live workspace. Nothing here re-decides anything — each action
/// already carries its ordered write sequence (Track A's getters); the
/// actuator only *executes* them, in list order, threading the one runtime
/// value the reducer could not name (a freshly-poured wisp id — see the
/// in-list dataflow rule on [ReconcilerAction]).
///
/// **Coexistence safety (ADR-0003 Decision 6 / ADR-0000 A7):** an actuator may
/// only ever be pointed at beads the_grid owns. It never reconciles or mutates
/// a bead gc's reconciler owns. (The seam itself enforces nothing — ownership
/// is a deployment-time partition; M2 shadow mode constructs no actuator at
/// all, only the reducer.)
abstract interface class Actuator {
  /// Executes [result]'s ordered actions for [convergence] (the projected
  /// loop the reduce ran over — supplies the wisp subtrees burns need and the
  /// child-key map the live idempotency probe complements).
  ///
  /// Returns an [ActuationResult] capturing the runtime ids the execution
  /// produced (the poured/adopted wisp id for the in-list `adoptFromPriorPour`
  /// thread, and any requeued event Track G must re-enqueue).
  Future<ActuationResult> apply(ReduceResult result, Convergence convergence);
}

/// The runtime outcome of executing one [ReduceResult].
class ActuationResult {
  const ActuationResult({this.pouredWispId, this.requeue});

  /// The wisp id produced (poured or adopted) by a [PourSpeculativeAction] /
  /// [IterateAction] in the list — the value the reducer could not name. Null
  /// when the list poured nothing.
  final String? pouredWispId;

  /// The reducer event Track G must re-enqueue behind this batch (gc's inline
  /// operator-stop drain — [RequeueAction]). Null when the list had no
  /// requeue.
  final RequeueAction? requeue;
}

/// The find-before-pour probe seam (ADR-0000 A15/A17): a **LIVE** query for
/// the existing child wisp under `parentId` whose `metadata.idempotency_key`
/// is `key`, or null. Implemented by grid_controller's
/// `DoltQueryService.findWispByIdempotencyKey` in production
/// ([doltIdempotencyProbe]); a fake in tests.
///
/// It MUST be live — never a snapshot scan
/// ([Convergence.findByIdempotencyKey] is the fast path: a snapshot HIT is
/// adopted without a round-trip, but a snapshot MISS proves nothing because a
/// fast actuation routinely beats the Dolt watcher poll, so it must fall
/// through to this probe before pouring).
typedef IdempotencyProbe =
    Future<String?> Function(String parentId, String key);

/// Resolves a [Wisp]'s burn order from [convergence] — the POST-ORDER
/// subtree id list (children before parents, the wisp LAST), which is exactly
/// `Wisp.subtreeIds` (gc's `deleteBeadSubtree` recursion, handler.go:919-933).
/// Falls back to the lone id when the wisp is not in the projection (a
/// crash-adopted wisp whose edges the snapshot has not captured yet — burning
/// just the root is still correct, the children are unreachable).
List<String> burnOrderFor(Convergence convergence, String wispId) {
  for (final wisp in convergence.wisps) {
    if (wisp.id == wispId) return wisp.subtreeIds;
  }
  return [wispId];
}
