import 'package:grid_engine/grid_engine.dart' show WorkSessionLiveness;
import 'package:grid_trajectory/grid_trajectory.dart';

/// Cadence adapter that evaluates durable session relay horizons on the
/// existing fenced service tick.
///
/// This deliberately shares cadence, not state, with
/// `LivenessDetectorObligation` in
/// `packages/grid_runtime/lib/src/trajectory/stage1_obligations.dart`. That
/// shipped obligation detects current-epoch attempt-pulse loss/regain under
/// `TrajectoryConfig.livenessThreshold`. Relay observation is instead a
/// per-session durable TTL check-in whose external verdict either persists a
/// new horizon or escalates. It never reuses the attempt pulse table, attempt
/// identity, threshold, or lost/regained latch; the two independent queries
/// compose beneath the same `TrajectoryTick` fence, cadence, busy guard, and
/// shutdown loop.
final class WorkSessionLivenessObligation extends ObligationQuery {
  /// Creates the no-write cadence adapter for [liveness].
  const WorkSessionLivenessObligation(this.liveness);

  /// The station-lifetime coordinator evaluated by each repair pass.
  final WorkSessionLiveness liveness;

  @override
  String get name => 'work-session-liveness';

  @override
  String get sql => 'SELECT 1 AS fenced_tick';

  @override
  Future<List<ObligationAppend>> repair(List<Map<String, String?>> rows) {
    liveness.onFencedTick();
    return Future<List<ObligationAppend>>.value(const <ObligationAppend>[]);
  }
}
