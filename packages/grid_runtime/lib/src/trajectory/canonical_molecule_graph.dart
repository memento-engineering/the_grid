/// The one canonical molecule graph shared by the legacy graph writer and
/// the Stage-2 trajectory record.
library;

import 'dart:collection';
import 'dart:convert';

import 'package:beads_dart/beads_dart.dart';
import 'package:grid_trajectory/grid_trajectory.dart' show sha256Hex;
import 'package:meta/meta.dart';

import '../models/grid_issue_types.dart';

/// One semantic molecule edge.
///
/// Parent/child structure is deliberately absent: it is reconstructed by
/// [CanonicalMoleculeGraph.toGraphApplyPlan] from node paths and molecule
/// metadata for the legacy writer only.
@immutable
final class CanonicalMoleculeEdge {
  CanonicalMoleculeEdge({
    required this.fromPath,
    required this.toPath,
    required this.kind,
  }) {
    if (kind != DependencyType.blocks.wire &&
        kind != DependencyType.validates.wire) {
      throw ArgumentError.value(
        kind,
        'kind',
        'canonical molecule edges must be blocks or validates',
      );
    }
  }

  final String fromPath;
  final String toPath;
  final String kind;

  Map<String, Object?> get _json => Map<String, Object?>.unmodifiable({
    'from_path': fromPath,
    'kind': kind,
    'to_path': toPath,
  });

  @override
  bool operator ==(Object other) =>
      other is CanonicalMoleculeEdge &&
      other.fromPath == fromPath &&
      other.toPath == toPath &&
      other.kind == kind;

  @override
  int get hashCode => Object.hash(fromPath, toPath, kind);

  @override
  String toString() => 'CanonicalMoleculeEdge(${jsonEncode(_json)})';
}

/// The selected formula's canonical executable graph.
///
/// The constructor derives [nodes], [nodeCount], [graph], and [graphDigest]
/// once. [toGraphApplyPlan] is therefore an adapter from this value, never a
/// second graph derivation.
@immutable
final class CanonicalMoleculeGraph {
  factory CanonicalMoleculeGraph({
    required String formula,
    required String commitMessage,
    required Iterable<GraphNode> nodeDefinitions,
    required Iterable<CanonicalMoleculeEdge> edges,
  }) {
    if (formula.isEmpty) {
      throw ArgumentError.value(formula, 'formula', 'must not be empty');
    }
    if (commitMessage.isEmpty) {
      throw ArgumentError.value(
        commitMessage,
        'commitMessage',
        'must not be empty',
      );
    }
    final copiedNodes = <GraphNode>[];
    final nodeKeys = <String>{};
    for (final node in nodeDefinitions) {
      if (node.key.isEmpty || !nodeKeys.add(node.key)) {
        throw ArgumentError.value(
          node.key,
          'nodeDefinitions',
          node.key.isEmpty
              ? 'node keys must not be empty'
              : 'duplicate node key',
        );
      }
      copiedNodes.add(_copyNode(node));
    }
    if (copiedNodes.isEmpty) {
      throw ArgumentError.value(
        nodeDefinitions,
        'nodeDefinitions',
        'must contain at least one molecule node',
      );
    }
    final copiedEdges = edges.toList(growable: false)..sort(_compareEdges);
    for (final edge in copiedEdges) {
      if (!nodeKeys.contains(edge.fromPath) ||
          !nodeKeys.contains(edge.toPath)) {
        throw ArgumentError.value(
          edge,
          'edges',
          'edge endpoints must name graph nodes',
        );
      }
    }
    final executableNodes = <String>[
      for (final node in copiedNodes)
        if (node.type == GridIssueTypes.step.wire) node.key,
    ]..sort();
    final graph =
        _deeplyUnmodifiable({
              'edges': [for (final edge in copiedEdges) edge._json],
              'nodes': executableNodes,
            })!
            as Map<String, Object?>;
    return CanonicalMoleculeGraph._(
      formula: formula,
      commitMessage: commitMessage,
      nodeDefinitions: List<GraphNode>.unmodifiable(copiedNodes),
      edges: List<CanonicalMoleculeEdge>.unmodifiable(copiedEdges),
      nodes: List<String>.unmodifiable(executableNodes),
      graph: graph,
      graphDigest: sha256Hex(jsonEncode(_sortJsonKeys(graph))),
    );
  }

  const CanonicalMoleculeGraph._({
    required this.formula,
    required this.commitMessage,
    required this.nodeDefinitions,
    required this.edges,
    required this.nodes,
    required this.graph,
    required this.graphDigest,
  });

  /// The selected circuit/formula identity.
  final String formula;

  /// The audit message retained by the legacy graph writer.
  final String commitMessage;

  /// Defensive copies of every molecule and executable step definition.
  final List<GraphNode> nodeDefinitions;

  /// Semantic edges sorted by `(from_path, to_path, kind)`.
  final List<CanonicalMoleculeEdge> edges;

  /// Lexically sorted executable step paths.
  final List<String> nodes;

  /// The number of executable step paths in [nodes].
  int get nodeCount => nodes.length;

  /// The deeply immutable trajectory payload graph.
  final Map<String, Object?> graph;

  /// Lowercase SHA-256 over recursively key-sorted canonical JSON of [graph].
  final String graphDigest;

  /// Adapts this canonical value to the incumbent graph-apply payload.
  ///
  /// Each node without an existing [GraphNode.parentId] is parented to its
  /// nearest strict molecule-path ancestor. A node for which that structure
  /// cannot be reconstructed is invalid and refuses loudly.
  GraphApplyPlan toGraphApplyPlan() {
    final moleculePaths = <String>[
      for (final node in nodeDefinitions)
        if (node.type == GridIssueTypes.molecule.wire) node.key,
    ];
    final parentEdges = <GraphEdge>[];
    for (final node in nodeDefinitions) {
      if (node.parentId != null) continue;
      final ancestors =
          moleculePaths
              .where((path) => node.key.startsWith('$path/'))
              .toList(growable: false)
            ..sort((a, b) => b.length.compareTo(a.length));
      if (ancestors.isEmpty) {
        throw StateError(
          'molecule node ${node.key} has no strict molecule ancestor',
        );
      }
      parentEdges.add(
        GraphEdge(
          fromKey: node.key,
          toKey: ancestors.first,
          type: DependencyType.parentChild.wire,
        ),
      );
    }
    return GraphApplyPlan(
      commitMessage: commitMessage,
      nodes: nodeDefinitions,
      edges: [
        ...parentEdges,
        for (final edge in edges)
          GraphEdge(
            fromKey: edge.fromPath,
            toKey: edge.toPath,
            type: edge.kind,
          ),
      ],
    );
  }

  String get _identity => jsonEncode(
    _sortJsonKeys({
      'formula': formula,
      'commit_message': commitMessage,
      'node_definitions': [for (final node in nodeDefinitions) node.toJson()],
      'edges': [for (final edge in edges) edge._json],
    }),
  );

  @override
  bool operator ==(Object other) =>
      other is CanonicalMoleculeGraph && other._identity == _identity;

  @override
  int get hashCode => _identity.hashCode;

  @override
  String toString() => 'CanonicalMoleculeGraph($_identity)';
}

GraphNode _copyNode(GraphNode node) => GraphNode(
  key: node.key,
  title: node.title,
  type: node.type,
  priority: node.priority,
  parentId: node.parentId,
  parentKey: node.parentKey,
  assignee: node.assignee,
  metadata: Map<String, String>.unmodifiable(node.metadata),
);

int _compareEdges(CanonicalMoleculeEdge a, CanonicalMoleculeEdge b) {
  final from = a.fromPath.compareTo(b.fromPath);
  if (from != 0) return from;
  final to = a.toPath.compareTo(b.toPath);
  if (to != 0) return to;
  return a.kind.compareTo(b.kind);
}

Object? _sortJsonKeys(Object? value) {
  if (value case final Map<Object?, Object?> map) {
    return SplayTreeMap<String, Object?>()..addEntries(
      map.entries.map(
        (entry) => MapEntry(entry.key! as String, _sortJsonKeys(entry.value)),
      ),
    );
  }
  if (value case final Iterable<Object?> values) {
    return [for (final value in values) _sortJsonKeys(value)];
  }
  return value;
}

Object? _deeplyUnmodifiable(Object? value) => switch (value) {
  final Map<Object?, Object?> map => Map<String, Object?>.unmodifiable({
    for (final entry in map.entries)
      entry.key! as String: _deeplyUnmodifiable(entry.value),
  }),
  final Iterable<Object?> values => List<Object?>.unmodifiable(
    values.map(_deeplyUnmodifiable),
  ),
  _ => value,
};
