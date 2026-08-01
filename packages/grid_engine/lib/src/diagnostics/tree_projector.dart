// The hidden genesis_foundation names exist only when genesis resolves by
// path (post-y61 source); on pub (tree 0.1.4) the hide is a no-op the
// analyzer warns about. tg-vg5k removes this with the hides.
// ignore_for_file: undefined_hidden_name
import 'dart:async';

// Foundation wire-type names hidden: grid_diagnostics_contract's stay
// operative until tg-vg5k migrates onto genesis_foundation.
import 'package:genesis_tree/genesis_tree.dart'
    hide
        CheckedFromJsonException,
        Diagnosticable,
        DiagnosticableTree,
        DiagnosticsDoubleProperty,
        DiagnosticsDurationProperty,
        DiagnosticsEnumProperty,
        DiagnosticsFlagProperty,
        DiagnosticsIntProperty,
        DiagnosticsLevel,
        DiagnosticsObjectProperty,
        DiagnosticsProperty,
        DiagnosticsReferenceProperty,
        DiagnosticsStringProperty,
        DiagnosticsTimestampProperty,
        ReferenceKind,
        TreeNode,
        TreeSnapshot;
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
