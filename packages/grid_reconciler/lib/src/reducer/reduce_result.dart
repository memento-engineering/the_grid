import '../convergence/reconciler_action.dart';

/// The pure output of [reduce]: the ordered list of [ReconcilerAction]s an
/// actuator (Track G) executes to advance one convergence loop by one event.
///
/// gc's handler returns `(HandlerResult, error)` and performs its writes
/// inline. The split reducer instead returns the writes as **data** — every
/// action exposes its ordered metadata-write sequence as derived getters
/// (ADR-0003 invariant 2 is encoded once, in Track A's
/// [ReconcilerAction]), so a `ReduceResult` is the complete, ordered effect
/// plan with no residual decision left to the actuator.
///
/// **The action list is ordered and load-bearing.** Reading gc's one frame
/// top-to-bottom, the reducer emits at most:
///
/// 1. [RepairIterationAction] — step-3 iteration self-heal, BEFORE any
///    transition (handler.go:208-214; invariant 4). An actuator failure here
///    BLOCKS the transition.
/// 2. [PourSpeculativeAction] — step-3b speculative pour (handler.go:244-275;
///    invariant 5). Its runtime result (a wisp id, or a deferred failure)
///    threads into a LATER action in the same list via
///    `IterateAction.adoptFromPriorPour` / the terminal/waiting
///    `burnPriorPour` flags — the reducer cannot name a wisp that does not
///    exist yet (see [ReconcilerAction]'s in-list dataflow rule).
/// 3. Either an [EvaluateGateAction] (the fresh-gate handoff — phase 1 ends
///    here; the transition is phase 2's to make when the gate result returns
///    as `ReducerEvent.gateEvaluated`), OR — on the replay branch and on
///    every operator/trigger path — a [PersistGateOutcomeAction] (step 5,
///    fresh non-replay only) followed by the single transition action.
/// 4. [RequeueAction] — the operator-stop drain carrier, strictly LAST
///    (manual.go:272-314).
///
/// A [ReduceResult] is **never empty**: every reduce produces at least one
/// action (a transition, a `skipped`, a `failed`, or a phase-1 handoff).
class ReduceResult {
  const ReduceResult(this.actions);

  /// A single-action result — the common case (a lone transition / skip /
  /// failure).
  ReduceResult.one(ReconcilerAction action) : actions = [action];

  /// The ordered actions to execute, in list order.
  final List<ReconcilerAction> actions;

  /// The transition or carrier action — gc's `HandlerResult` analog: the
  /// LAST action that is not a pure pre-write ([RepairIterationAction]) or
  /// the speculative pour ([PourSpeculativeAction]). For a phase-1 handoff
  /// this is the [EvaluateGateAction]; for a transition reduce it is the
  /// transition; for a drain it is the [RequeueAction].
  ReconcilerAction get primary => actions.last;

  @override
  String toString() => 'ReduceResult($actions)';
}
