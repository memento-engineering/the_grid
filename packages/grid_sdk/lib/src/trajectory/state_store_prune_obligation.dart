import 'package:grid_trajectory/grid_trajectory.dart';

import '../stores/state_store_pruner.dart';

/// Runs the station-owned state-store prune on the existing fenced tick.
final class StateStorePruneObligation extends ObligationQuery {
  /// Creates the cadence adapter for [pruner].
  const StateStorePruneObligation(this.pruner);

  /// The station-lifetime pruner evaluated by each repair pass.
  final StateStorePruner pruner;

  @override
  String get name => 'state-store-prune';

  @override
  String get sql => 'SELECT 1 AS fenced_tick';

  @override
  Future<List<ObligationAppend>> repair(List<Map<String, String?>> rows) async {
    await pruner.run();
    return const <ObligationAppend>[];
  }
}
