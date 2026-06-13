import 'dart:convert';

/// The `--graph` payload for `bd create --graph <plan.json>`
/// (beads `cmd/bd/graph_apply.go` `GraphApplyPlan`): an atomic, single-
/// transaction graph apply (one `DOLT_COMMIT`).
///
/// Plain value classes (not freezed): the shape is a thin JSON DTO the
/// [BdCliService] serialises straight to a temp `plan.json` (or `--graph -`
/// stdin), and a plain class keeps the controller free of codegen on this
/// path. Equality is structural via [toJson] so tests can assert the exact
/// emitted plan.
///
/// **Convergence pour usage (ADR-0000 A15):** the root [GraphNode] carries
/// `parentId` → the convergence bead and `metadata['idempotency_key']` =
/// `converge:{beadID}:iter:{N}`; step nodes hang off it via [GraphNode.parentKey];
/// a step's `needs` become `blocks` [GraphEdge]s. The pour is **PERSISTENT** —
/// [BdCliService.applyGraph] is called with `ephemeral: false` (the default),
/// dropping `--ephemeral`, because gc's convergence iterations are committed
/// `issues` rows, not vapor wisps (A15 correction).
class GraphApplyPlan {
  const GraphApplyPlan({
    required this.commitMessage,
    this.nodes = const [],
    this.edges = const [],
  });

  /// The `DOLT_COMMIT` message stamped on the single transaction.
  final String commitMessage;

  /// The nodes to create, keyed by [GraphNode.key] for edge wiring.
  final List<GraphNode> nodes;

  /// The dependency edges, referencing node [GraphNode.key]s.
  final List<GraphEdge> edges;

  Map<String, dynamic> toJson() => {
    'commit_message': commitMessage,
    'nodes': [for (final n in nodes) n.toJson()],
    'edges': [for (final e in edges) e.toJson()],
  };

  /// The canonical JSON string written to `bd create --graph`.
  String toJsonString() => jsonEncode(toJson());

  @override
  bool operator ==(Object other) =>
      other is GraphApplyPlan && other.toJsonString() == toJsonString();

  @override
  int get hashCode => toJsonString().hashCode;

  @override
  String toString() => 'GraphApplyPlan(${toJsonString()})';
}

/// One node in a [GraphApplyPlan] — a bead to create. Mirrors the
/// graph-apply node shape (`graph_apply.go`): a stable [key] for edge
/// references, plus the bead fields.
class GraphNode {
  const GraphNode({
    required this.key,
    required this.title,
    this.type = 'task',
    this.priority,
    this.parentId,
    this.parentKey,
    this.assignee,
    this.metadata = const {},
  });

  /// The plan-local key edges and `parent_key` references resolve against;
  /// the returned id map (see [BdCliService.applyGraph]) is keyed by this.
  final String key;

  final String title;

  /// The bead's `issue_type`. A speculative pour passes `'gate'` here and
  /// stashes the real type under `metadata['gc.deferred_type']` (A15).
  final String type;

  final int? priority;

  /// An EXISTING bead id this node is parented under (a parent-child edge;
  /// the `parent_id` column stays null — A15). The convergence root for a
  /// pour's root wisp node.
  final String? parentId;

  /// A plan-local [key] of another node this node is parented under (step
  /// nodes hang off the root wisp node by its key).
  final String? parentKey;

  final String? assignee;

  /// Per-node metadata (e.g. the root's `idempotency_key`, or a speculative
  /// step's `gc.deferred_*` stash). Empty omits the field.
  final Map<String, String> metadata;

  Map<String, dynamic> toJson() => {
    'key': key,
    'title': title,
    'type': type,
    if (priority != null) 'priority': priority,
    if (parentId != null) 'parent_id': parentId,
    if (parentKey != null) 'parent_key': parentKey,
    if (assignee != null) 'assignee': assignee,
    if (metadata.isNotEmpty) 'metadata': metadata,
  };

  @override
  String toString() => 'GraphNode(${jsonEncode(toJson())})';
}

/// One dependency edge in a [GraphApplyPlan], referencing node [GraphNode.key]s.
/// A convergence pour turns each step's `needs` into a `blocks` edge.
class GraphEdge {
  const GraphEdge({
    required this.fromKey,
    required this.toKey,
    this.type = 'blocks',
  });

  /// The plan-local key of the edge's source node (`issue_id`).
  final String fromKey;

  /// The plan-local key of the edge's target node (`depends_on_id`).
  final String toKey;

  final String type;

  Map<String, dynamic> toJson() => {
    'from_key': fromKey,
    'to_key': toKey,
    'type': type,
  };

  @override
  String toString() => 'GraphEdge(${jsonEncode(toJson())})';
}
