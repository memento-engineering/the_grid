import 'package:riverpod/riverpod.dart';

import '../diff/graph_event.dart';
import '../interactors/graph_sync_interactor.dart';
import '../models/bead.dart';
import '../models/graph_snapshot.dart';
import '../reactivity/grid_controller_runtime.dart';

/// The running controller. Has no constructable default — the application
/// (grid_cli, the exploration host, tests) builds a configured
/// [GridControllerRuntime] and overrides this provider with it:
///
/// ```dart
/// final container = ProviderContainer(
///   overrides: [gridRuntimeProvider.overrideWithValue(runtime)],
/// );
/// ```
final gridRuntimeProvider = Provider<GridControllerRuntime>(
  (ref) => throw UnimplementedError(
    'gridRuntimeProvider must be overridden with a configured '
    'GridControllerRuntime',
  ),
);

/// The work-graph snapshot as it changes. Seeds late subscribers with the
/// current snapshot (broadcast streams do not replay), then follows the live
/// stream — so a widget mounting after the baseline still sees state.
final graphSnapshotProvider = StreamProvider<GraphSnapshot>((ref) async* {
  final runtime = ref.watch(gridRuntimeProvider);
  final seed = runtime.current;
  if (seed != null) yield seed;
  yield* runtime.snapshots;
});

/// Individual typed change events, flattened across refreshes.
final graphEventsProvider = StreamProvider<GraphEvent>(
  (ref) => ref.watch(gridRuntimeProvider).events,
);

/// Beads currently in the ready set, derived from the latest snapshot.
final readyBeadsProvider = Provider<List<Bead>>((ref) {
  final snapshot = ref.watch(graphSnapshotProvider).value;
  if (snapshot == null) return const [];
  return [
    for (final id in snapshot.readyIds)
      if (snapshot.bead(id) case final bead?) bead,
  ];
});

/// A single bead by id, tracking the latest snapshot.
final beadProvider = Provider.family<Bead?, String>((ref, id) {
  return ref.watch(graphSnapshotProvider).value?.bead(id);
});

/// Live sync-loop stats (signal counts, refresh latency, in-flight state).
final gridStatsProvider = Provider<GraphSyncStats>(
  (ref) => ref.watch(gridRuntimeProvider).stats,
);
