import 'dart:async';

import 'package:genesis_tree/genesis_tree.dart';
import 'package:grid_diagnostics_contract/grid_diagnostics_contract.dart';

import 'diagnostics_tree_walker.dart';

/// Projects the live semantic tree after completed kernel flushes.
final class TreeProjector {
  /// Creates a projector with an injectable wall clock.
  TreeProjector({DateTime Function()? clock}) : _clock = clock ?? DateTime.now;

  final DateTime Function() _clock;
  final DiagnosticsTreeWalker _walker = DiagnosticsTreeWalker();
  final StreamController<TreeSnapshot> _controller =
      StreamController<TreeSnapshot>.broadcast(sync: true);

  TreeSnapshot? _latest;
  bool _disposed = false;

  /// The most recently emitted snapshot, or null before the first flush.
  TreeSnapshot? get latest => _latest;

  /// Full snapshots emitted once per completed kernel flush.
  Stream<TreeSnapshot> get snapshots => _controller.stream;

  /// Re-walks [root] once and publishes the resulting full snapshot.
  void afterFlush(Branch root) {
    if (_disposed) return;
    final projectedAt = _clock();
    final snapshot = _walker.walk(root, projectedAt: projectedAt);
    _latest = snapshot;
    _controller.add(snapshot);
  }

  /// Closes the snapshot stream. Idempotent.
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    unawaited(_controller.close());
  }
}
