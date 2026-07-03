import 'package:freezed_annotation/freezed_annotation.dart';
import 'package:beads_dart/beads_dart.dart';

import '../convergence/idempotency_key.dart';
import '../convergence/reconciler_action.dart' show DeferredWispFields;

part 'wisp.freezed.dart';

/// One node of a speculative (deferred-pour) subtree: a bead carrying at
/// least one `gc.deferred_*` key ([DeferredWispFields]). A speculative pour
/// withholds each actionable node's claimability by pouring it as the
/// ready-excluded type `gate` and stashing the real type / assignee /
/// routing under these keys (molecule.go:1009-1026); activation promotes
/// them back per node, recursing over children (`activateDeferredAssignees`,
/// cmd/gc/convergence_store.go:204-246 — each value applied only when
/// non-empty AND different from the live value).
///
/// Each field is the verbatim stored value, null when the key is absent or
/// empty (gc's `!= ""` guards read empty as not-deferred).
@freezed
abstract class SpeculativeNode with _$SpeculativeNode {
  const SpeculativeNode._();

  const factory SpeculativeNode({
    required String id,

    /// `gc.deferred_type` (molecule.go:73) — the real bead type the node
    /// is promoted back to on activation (convergence_store.go:224-226).
    String? deferredType,

    /// `gc.deferred_assignee` (molecule.go:60) — restored as the assignee
    /// (convergence_store.go:214-216).
    String? deferredAssignee,

    /// `gc.deferred_routed_to` (molecule.go:64) — restored as
    /// `gc.routed_to` (convergence_store.go:218-220).
    String? deferredRoutedTo,

    /// `gc.deferred_execution_routed_to` (molecule.go:68) — restored as
    /// `gc.execution_routed_to` (convergence_store.go:221-223).
    String? deferredExecutionRoutedTo,
  }) = _SpeculativeNode;
}

/// A convergence wisp: the ephemeral root child poured for one iteration of
/// a convergence loop, identified by its `metadata.idempotency_key`
/// (`converge:{beadID}:iter:{N}`).
///
/// gc identifies wisps **only** by the key prefix — it checks neither the
/// bead's issue type nor its `ephemeral` flag (`deriveIterationCount`,
/// handler.go:812-825) — so this projection requires only the key. Step
/// children are resolved from parent-child dependency edges (the hierarchy is
/// an edge; the `parent_id` column stays null — ADR-0000 A15) and reuse
/// beads_dart's [Step].
///
/// Two surfaces serve the speculative life-cycle, where [steps] is blind
/// by design (speculative steps are gate-typed): [subtreeIds] (post-order
/// burn list) and [speculativeNodes] (pre-order activation worklist) — the
/// crash-recovery enumeration for adopted wisps whose pour-time id map is
/// gone (`adoptWispId` / `adoptPendingWispId`, Track C §9.3 adoption).
@freezed
abstract class Wisp with _$Wisp {
  const Wisp._();

  const factory Wisp({
    required String id,
    required String title,
    required BeadStatus status,
    required bool ephemeral,

    /// The full `converge:{beadID}:iter:{N}` key, verbatim.
    required String idempotencyKey,

    /// The iteration parsed from [idempotencyKey], or null when the suffix
    /// does not parse (gc's `ParseIterationFromKey` ok=false). A null
    /// iteration still **counts** toward the closed-wisp count (gc counts by
    /// prefix + closed, not by parseability) but is skipped by
    /// highest-closed-wisp resolution (reconcile.go:640-643).
    required int? iteration,

    /// Step children of the **ACTIVATED**-wisp view: children that are
    /// step-typed RIGHT NOW. A speculative (deferred) pour creates its
    /// actionable nodes as the ready-excluded type `gate` with the real
    /// type under `gc.deferred_type` (molecule.go:1009-1026), so for
    /// exactly the wisps Track E must activate or burn this list is EMPTY
    /// (and `bd children` hides them too — spike-pinned). Enumerate a
    /// speculative subtree via [subtreeIds] / [speculativeNodes] instead.
    @Default(<Step>[]) List<Step> steps,

    /// The wisp's full subtree from parent-child edges, in **POST-ORDER**
    /// — children before parents, the wisp itself LAST. **Burn order is
    /// exactly this list**: gc's burn is a recursive post-order subtree
    /// delete (`deleteBeadSubtree`, handler.go:919-933 — each node's
    /// children deleted before the node, the root last). Built from the
    /// dependency edges alone (a child id missing from the bead map is
    /// still included — the edge proves it exists; siblings ordered by id
    /// for determinism, where gc takes whatever `Store.Children`
    /// returns). Includes EVERY descendant regardless of type — unlike
    /// [steps], which filters — because speculative steps are gate-typed
    /// and crash-adopted wisps (`adoptWispId` / `adoptPendingWispId` from
    /// the snapshot) have no pour-time id map to fall back on.
    @Default(<String>[]) List<String> subtreeIds,

    /// Every subtree node (the wisp itself included) carrying at least one
    /// `gc.deferred_*` key, in **PRE-ORDER** — parent before children,
    /// matching the activation recursion (`activateDeferredAssignees`
    /// updates the node, then recurses into its children —
    /// convergence_store.go:208-246). Empty for an activated or
    /// directly-poured wisp. This is the Track E activation worklist: one
    /// `bd update` per node promoting the deferred values back.
    @Default(<SpeculativeNode>[]) List<SpeculativeNode> speculativeNodes,
    DateTime? createdAt,
    DateTime? closedAt,
    @Default('') String closeReason,
  }) = _Wisp;

  /// Projects a bead carrying a wisp idempotency key.
  ///
  /// Fails (typed) only when `metadata.idempotency_key` is missing, empty,
  /// or not a String — the one property that makes a bead a wisp. Callers
  /// (the Convergence projection) apply the prefix filter; projecting in
  /// isolation accepts any key.
  static ProjectionResult<Wisp> project(
    Bead bead, {
    Iterable<BeadDependency> dependencies = const [],
    Map<String, Bead> beadsById = const {},
  }) {
    final Object? key = bead.metadata[wispIdempotencyKeyField];
    if (key is! String || key.isEmpty) {
      return ProjectionFailed(
        ProjectionError(
          beadId: bead.id,
          issueType: bead.issueType.wire,
          projection: 'Wisp',
          reason: key == null || key == ''
              ? 'missing metadata.$wispIdempotencyKeyField'
              : 'metadata.$wispIdempotencyKeyField is not a String '
                    '(${key.runtimeType})',
        ),
      );
    }

    final deps = dependencies.toList(growable: false);

    // Parent → children adjacency over ALL parent-child edges (child =
    // issue_id, parent = depends_on_id — upstream
    // beads/internal/storage/issueops/blocked.go:60-63); subtrees nest
    // arbitrarily deep. Sibling order: by id, for determinism.
    final childrenOf = <String, List<String>>{};
    for (final dep in deps) {
      if (dep.type != DependencyType.parentChild) continue;
      (childrenOf[dep.dependsOnId] ??= <String>[]).add(dep.issueId);
    }
    for (final children in childrenOf.values) {
      children.sort();
    }

    // One walk yields both orders: post-order (burn — children before
    // parents, deleteBeadSubtree handler.go:919-933) and pre-order
    // (activation — parent first, convergence_store.go:208-246). The
    // visited set guards against cycles/diamonds a malformed snapshot
    // could carry.
    final postOrder = <String>[];
    final preOrder = <String>[];
    final visited = <String>{};
    void walk(String id) {
      if (!visited.add(id)) return;
      preOrder.add(id);
      for (final child in childrenOf[id] ?? const <String>[]) {
        walk(child);
      }
      postOrder.add(id);
    }

    walk(bead.id);

    // Speculative nodes: any subtree bead carrying a gc.deferred_* key
    // (empty reads as not-deferred, matching activateDeferredAssignees'
    // `!= ""` guards).
    final speculativeNodes = <SpeculativeNode>[];
    for (final id in preOrder) {
      final node = id == bead.id ? bead : beadsById[id];
      if (node == null) continue; // dangling edge — snapshot-safe
      String? deferred(String field) {
        final Object? value = node.metadata[field];
        return value is String && value.isNotEmpty ? value : null;
      }

      final type = deferred(DeferredWispFields.type);
      final assignee = deferred(DeferredWispFields.assignee);
      final routedTo = deferred(DeferredWispFields.routedTo);
      final executionRoutedTo = deferred(DeferredWispFields.executionRoutedTo);
      if (type == null &&
          assignee == null &&
          routedTo == null &&
          executionRoutedTo == null) {
        continue;
      }
      speculativeNodes.add(
        SpeculativeNode(
          id: id,
          deferredType: type,
          deferredAssignee: assignee,
          deferredRoutedTo: routedTo,
          deferredExecutionRoutedTo: executionRoutedTo,
        ),
      );
    }

    // Step children: step-typed beads joined to this wisp by a direct
    // parent-child edge — the ACTIVATED-wisp view (see [Wisp.steps]).
    final stepIds = <String>{};
    for (final childId in childrenOf[bead.id] ?? const <String>[]) {
      if (beadsById[childId]?.issueType == IssueType.step) {
        stepIds.add(childId);
      }
    }

    // Each step's `needs`: blocking edges to sibling steps (the molecule
    // composition rule, ADR-0000 A13).
    final steps = <Step>[];
    for (final stepId in stepIds) {
      final stepBead = beadsById[stepId];
      if (stepBead == null) continue;
      final needs = <String>[
        for (final dep in deps)
          if (dep.issueId == stepId &&
              dep.type.isBlockingEdge &&
              stepIds.contains(dep.dependsOnId))
            dep.dependsOnId,
      ];
      final result = Step.project(stepBead, needs: needs);
      if (result case ProjectionOk<Step>(:final value)) steps.add(value);
    }
    steps.sort((a, b) => a.id.compareTo(b.id));

    return ProjectionOk(
      Wisp(
        id: bead.id,
        title: bead.title,
        status: bead.status,
        ephemeral: bead.ephemeral,
        idempotencyKey: key,
        iteration: parseIterationFromKey(key),
        steps: List<Step>.unmodifiable(steps),
        subtreeIds: List<String>.unmodifiable(postOrder),
        speculativeNodes: List<SpeculativeNode>.unmodifiable(speculativeNodes),
        createdAt: bead.createdAt,
        closedAt: bead.closedAt,
        closeReason: bead.closeReason,
      ),
    );
  }

  bool get isClosed => status == BeadStatus.closed;

  int get stepCount => steps.length;
  int get closedStepCount => steps.where((s) => s.isClosed).length;

  /// closed / total steps, in [0,1]; 1.0 with no steps (mirrors Molecule).
  double get progress => steps.isEmpty ? 1 : closedStepCount / stepCount;

  /// The close time gc's duration math would use (`beadToInfo`,
  /// cmd/gc/convergence_store.go:345-349): the recorded close time, falling
  /// back to [createdAt] for a closed wisp with no close timestamp (duration
  /// zero).
  DateTime? get effectiveClosedAt => closedAt ?? (isClosed ? createdAt : null);
}
