import 'package:genesis_foundation/genesis_foundation.dart';
import 'package:genesis_tree/genesis_tree.dart' show Branch, StatefulBranch;

import 'diagnosable.dart';

/// Projects a mounted genesis tree into the version-1 semantic diagnostics tree.
final class DiagnosticsTreeWalker {
  /// Walks [root] without mutating or subscribing to it.
  TreeSnapshot walk(Branch root, {required DateTime projectedAt}) {
    final roots = _walk(root);
    if (roots.isEmpty) {
      throw StateError(
        'Diagnostics walk found no semantic root — nothing diagnosable is '
        'mounted.',
      );
    }
    // A wide roster surfaces SEVERAL top-level diagnosables (a resident
    // station mounts one SubstationScope per store — seven on the first
    // armed lunar boot, 2026-08-07, which this walk refused and took the
    // whole arm down). Synthesize the station root instead: the projection
    // is a VIEW, and a view never dictates the tree's shape.
    final semanticRoot = roots.length == 1
        ? roots.single
        : TreeNode(
            seedType: 'Station',
            id: root.branchId,
            key: root.key?.toString(),
            properties: const [],
            children: roots,
          );
    return TreeSnapshot(
      contractVersion: 1,
      projectedAt: projectedAt,
      root: semanticRoot,
    );
  }

  List<TreeNode> _walk(Branch branch) {
    final children = <TreeNode>[];
    branch.visitChildren((child) => children.addAll(_walk(child)));

    final seed = branch.seed;
    if (seed is! GridDiagnosticable) return children;

    final builder = DiagnosticsBuilder();
    seed.debugFillProperties(builder);
    if (branch is StatefulBranch) {
      final state = (branch as dynamic).state as Object?;
      if (state is GridDiagnosticable && state is Diagnosticable) {
        (state as Diagnosticable).debugFillProperties(builder);
      }
    }

    return [
      TreeNode(
        seedType: seed.runtimeType.toString(),
        id: branch.branchId,
        key: branch.key?.toString(),
        properties: builder.properties,
        children: children,
      ),
    ];
  }
}
