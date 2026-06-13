import '../convergence/reconciler_action.dart';
import '../projections/convergence.dart';
import '../reducer/reduce_result.dart';
import 'actuator.dart';

/// A recording [Actuator] for tests that drive the reduce→actuate loop without
/// any bd surface: it records each [ReduceResult] it was asked to apply (and
/// the per-result action list), and returns a programmable [ActuationResult].
///
/// Use this where the unit under test is *above* the actuator (Track G's
/// orchestration: per-bead serialization, requeue handling). To assert the
/// exact bd call SEQUENCE an action produces, drive the real [BdActuator] with
/// a recording `BdRunner` instead — the fake here is intentionally blind to
/// the write order.
class FakeActuator implements Actuator {
  FakeActuator({this.nextResult});

  /// The result returned by the next [apply] (then cleared). When null,
  /// [apply] returns an empty [ActuationResult].
  ActuationResult? nextResult;

  /// Every [ReduceResult] applied, in order.
  final List<ReduceResult> applied = [];

  /// Every action applied, flattened across results, in order.
  final List<ReconcilerAction> actions = [];

  /// Each apply's [Convergence], parallel to [applied].
  final List<Convergence> convergences = [];

  @override
  Future<ActuationResult> apply(
    ReduceResult result,
    Convergence convergence,
  ) async {
    applied.add(result);
    convergences.add(convergence);
    actions.addAll(result.actions);
    final out = nextResult ?? const ActuationResult();
    nextResult = null;
    return out;
  }
}
