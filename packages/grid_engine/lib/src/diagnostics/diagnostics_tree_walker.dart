// ignore_for_file: invalid_use_of_protected_member

// genesis_tree re-exports genesis_foundation, whose wire types collide with
// grid_diagnostics_contract's identically-named originals. The contract's
// types stay operative here until tg-vg5k migrates this walker onto
// genesis_foundation and retires the local contract package.
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

import 'diagnosable.dart';

/// Projects a mounted genesis tree into the version-1 semantic diagnostics tree.
final class DiagnosticsTreeWalker {
  /// Walks [root] without mutating or subscribing to it.
  TreeSnapshot walk(Branch root, {required DateTime projectedAt}) {
    final roots = _walk(root);
    if (roots.length != 1) {
      throw StateError(
        'Diagnostics walk requires exactly one semantic root; '
        'found ${roots.length}',
      );
    }
    return TreeSnapshot(
      contractVersion: 1,
      projectedAt: projectedAt,
      root: roots.single,
    );
  }

  List<TreeNode> _walk(Branch branch) {
    final children = <TreeNode>[];
    branch.visitChildren((child) => children.addAll(_walk(child)));

    final seed = branch.seed;
    if (seed is! Diagnosable) return children;

    final builder = DiagnosticsBuilder();
    (seed as Diagnosable).debugFillProperties(builder);
    if (branch case StatefulBranch(:final state)) {
      if (state is Diagnosable) {
        (state as Diagnosable).debugFillProperties(builder);
      }
    }

    return [
      TreeNode(
        seedType: seed.runtimeType.toString(),
        id: branch.branchId,
        key: branch.key?.toString(),
        properties: builder.build(),
        children: children,
      ),
    ];
  }
}
