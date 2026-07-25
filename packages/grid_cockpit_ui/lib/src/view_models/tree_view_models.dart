import 'dart:async';

import 'package:grid_diagnostics_contract/grid_diagnostics_contract.dart';
import 'package:state_notifier/state_notifier.dart';

import '../models/view_state.dart';
import '../selectors/tree_selectors.dart';
import '../source/tree_source.dart';

/// Empty overview used before a live source receives its first snapshot.
final emptyOverviewState = OverviewState(
  projectedAt: DateTime.fromMillisecondsSinceEpoch(0, isUtc: true),
  substations: const [],
  activeWorkCount: 0,
  warningCount: 0,
  errorCount: 0,
);

abstract class _TreeViewModel<T> extends StateNotifier<T> {
  _TreeViewModel(this.source, super.initialState) {
    _subscription = source.snapshots.listen(onSnapshot);
  }

  final TreeSource source;
  late final StreamSubscription<TreeSnapshot> _subscription;

  void onSnapshot(TreeSnapshot snapshot);

  @override
  void dispose() {
    unawaited(_subscription.cancel());
    super.dispose();
  }
}

/// Snapshot-driven overview projection.
final class OverviewViewModel extends _TreeViewModel<OverviewState> {
  /// Creates an overview projection subscribed to [source].
  OverviewViewModel(TreeSource source)
    : super(
        source,
        source.latest == null ? emptyOverviewState : overviewOf(source.latest!),
      );

  @override
  void onSnapshot(TreeSnapshot snapshot) => state = overviewOf(snapshot);
}

/// Snapshot-driven work-list projection.
final class WorkListViewModel extends _TreeViewModel<WorkListState> {
  /// Creates a work-list projection subscribed to [source].
  WorkListViewModel(TreeSource source)
    : super(
        source,
        source.latest == null
            ? const WorkListState(items: [])
            : workListOf(source.latest!),
      );

  @override
  void onSnapshot(TreeSnapshot snapshot) => state = workListOf(snapshot);
}

/// Snapshot-driven pipeline projection.
final class PipelineViewModel extends _TreeViewModel<PipelineState> {
  /// Creates a pipeline projection subscribed to [source].
  PipelineViewModel(TreeSource source)
    : super(
        source,
        source.latest == null
            ? const PipelineState(roots: [])
            : pipelineOf(source.latest!),
      );

  @override
  void onSnapshot(TreeSnapshot snapshot) => state = pipelineOf(snapshot);
}

/// Snapshot-driven inspector projection for one diagnostics node.
final class InspectorViewModel extends _TreeViewModel<InspectorState?> {
  /// Creates an inspector projection for [nodeId] subscribed to [source].
  InspectorViewModel(TreeSource source, {required this.nodeId})
    : super(
        source,
        source.latest == null ? null : inspectorOf(source.latest!, nodeId),
      );

  /// The diagnostics node selected for inspection.
  final String nodeId;

  @override
  void onSnapshot(TreeSnapshot snapshot) =>
      state = inspectorOf(snapshot, nodeId);
}

/// Snapshot-driven recursive cost projection.
final class CostRollupViewModel extends _TreeViewModel<CostRollupState> {
  /// Creates a cost projection subscribed to [source].
  CostRollupViewModel(TreeSource source)
    : super(
        source,
        source.latest == null
            ? const CostRollupState(hasData: false)
            : costRollupOf(source.latest!),
      );

  @override
  void onSnapshot(TreeSnapshot snapshot) => state = costRollupOf(snapshot);
}
