import 'package:freezed_annotation/freezed_annotation.dart';

import 'diagnostics_property.dart';

part 'tree_snapshot.freezed.dart';
part 'tree_snapshot.g.dart';

/// A complete versioned projection of the live diagnostics tree.
@freezed
abstract class TreeSnapshot with _$TreeSnapshot {
  /// Creates a full snapshot stamped at [projectedAt].
  const factory TreeSnapshot({
    required int contractVersion,
    required DateTime projectedAt,
    required TreeNode root,
  }) = _TreeSnapshot;

  /// Decodes a complete snapshot from its wire representation.
  factory TreeSnapshot.fromJson(Map<String, Object?> json) =>
      _$TreeSnapshotFromJson(json);
}

/// One semantic node in a [TreeSnapshot].
@freezed
abstract class TreeNode with _$TreeNode {
  /// Creates a diagnostics node and its complete child subtree.
  const factory TreeNode({
    required String seedType,
    required String id,
    String? key,
    required List<DiagnosticsProperty> properties,
    required List<TreeNode> children,
  }) = _TreeNode;

  /// Decodes a node from its wire representation.
  factory TreeNode.fromJson(Map<String, Object?> json) =>
      _$TreeNodeFromJson(json);
}
