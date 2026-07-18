/// R4 — the thin frontier derivation (`DESIGN-tg-pm6.md` §8; Decided item 7:
/// "durable = stamped state; live = derivation; backward = INVALIDATION").
///
/// COMPOSES over `sdk/frontier.dart` and `sdk/rewind.dart`; edits NEITHER.
/// Forward eligibility stays the unchanged, zero-write [depsSatisfied] read;
/// backward motion becomes its exact mirror over `validates` stamps instead of
/// a written `Rewind` verdict — [invalidatedNodes] finds every currently-
/// invalidating `validates` edge and reuses [rewindNodePaths] VERBATIM (with
/// the validates TARGET standing in for both `targetStepIds` and `selfStepId`,
/// since there is no routing "self" in a passive derivation) to compute the
/// exact same closure the old chokepoint write used to flip to `pending`: the
/// target ∪ its transitive dependents, each expanded to its whole subtree.
///
/// [effectiveCursor] is the collapse the design calls out as stronger than
/// either proposal it synthesizes: projection ∘ invalidation-demotion ∘
/// derived-generation compose into ONE effective [CircuitCursor].
/// [liveFrontier] is then just `eligibleSteps` over it — no second predicate,
/// no `RouteVerdict`, no route naming a step.
///
/// A52 Ratified makes [derivedGeneration] the depth of the active step bead's
/// `supersedes` chain. A single recurring critic therefore advances depth 1,
/// 2, 3 across successor beads; three critics failing the first review still
/// spend only round depth 1. History is graph structure, never a mutable
/// counter.
///
/// Reads ONLY structured stamps — [ResultKeys.grade], never
/// [ResultKeys.rationale] — the boolean-not-prose rule (pow-hf2,
/// institutionalized structurally in `molecule_codec_test.dart`). A
/// `validates`-source only counts once its OWN cursor state reaches a
/// [NodeCursor.isPositiveTerminal]: a freshly-demoted source that has not yet
/// re-run carries a STALE grade from its prior incarnation, and re-reading
/// that stale grade as still-invalidating would spin the derivation forever
/// (the exact prose-misread failure pow-hf2 is the standing proof of, just one
/// axis over). Once the source genuinely re-runs and its grade changes, the
/// derivation sees it on the very next snapshot — no signal, no push.
library;

import '../domain/rework.dart' show kMaxReworkRounds;
import '../domain/session_bead.dart' show ResultKeys;
import '../sdk/circuit.dart';
import '../sdk/cursor.dart';
import '../sdk/frontier.dart';
import '../sdk/rewind.dart';
import 'molecule_schema.dart' show kValidatesParam;

/// Every node's recorded RESULT payload, keyed by `nodePath` — the SAME shape
/// `SiblingView.results` / `projectCircuitResults` already carry
/// (`sdk/capability.dart`, `domain/session_bead.dart`). A named typedef purely
/// for readability at this file's call sites; not a new wire shape.
typedef CircuitResults = Map<String, Map<String, String>>;

/// One `validates` edge structurally present in [circuit]'s subtree: the
/// source step's own full path, and the FULL node-path closure its
/// invalidation would demote (mirrors [rewindNodePaths]'s own closure shape
/// exactly — target ∪ transitive dependents ∪ [target itself], each expanded
/// to its whole subtree).
typedef _ValidatesEdge = ({
  String sourcePath,
  String targetPath,
  Set<String> closure,
});

/// Whether the `validates`-SOURCE step at [sourcePath] currently stamps an
/// INVALIDATING verdict. Two conditions, both structural, neither prose:
///
/// - its own projected cursor state has reached a POSITIVE TERMINAL — a
///   source that has been demoted but not yet re-run carries a STALE grade
///   from its prior incarnation, and must NOT re-invalidate on it (the
///   fixed-point guard: once the source re-runs, its state flips back to a
///   positive terminal with a FRESH grade, and the derivation re-evaluates
///   honestly on that later snapshot);
/// - its recorded [ResultKeys.grade] is the failing letter `F` — the SAME
///   convention `grid_cli`'s `gate_command.dart` and the route capability
///   already read (`grade == 'F'`), never the free-text [ResultKeys.rationale].
bool _stampInvalidates(
  CircuitCursor projected,
  CircuitResults results,
  String sourcePath,
) {
  if (!cursorNodeAt(projected, sourcePath).isPositiveTerminal) return false;
  final grade = results[sourcePath]?[ResultKeys.grade];
  return grade != null && grade.toUpperCase() == 'F';
}

/// Every `validates` edge anywhere in [circuit]'s subtree, depth-first in
/// declaration order (mirrors [firstBrokenNode]'s own traversal) — a step
/// whose `params[kValidatesParam]` names a SIBLING step id at ITS OWN circuit
/// level (the same scope `instantiateMolecule`'s `_emitSiblingEdges` mints the
/// edge at, and the same scope [rewindNodePaths] bounds a rewind to: a
/// `validates` edge never reaches into a PARENT circuit).
///
/// A dangling `validates` target mints no edge — fail-closed, mirroring
/// `instantiateMolecule`'s own convention for the same convention key.
Iterable<_ValidatesEdge> _validatesEdges(
  Circuit circuit,
  String nodePath, {
  required Circuit? Function(String circuitId) circuitById,
}) sync* {
  for (final step in circuit.steps) {
    final sourcePath = stepPath(nodePath, step.stepId);
    final targetId = step.params[kValidatesParam];
    final target = targetId == null ? null : circuit.stepById(targetId);
    if (targetId != null && target != null) {
      yield (
        sourcePath: sourcePath,
        targetPath: stepPath(nodePath, targetId),
        closure: rewindNodePaths(
          circuit,
          nodePath,
          {targetId},
          // No routing "self" exists in a passive derivation; naming the
          // target as its own "self" is a no-op union (the target is already
          // in `targetStepIds`) that lets this reuse rewindNodePaths VERBATIM.
          selfStepId: targetId,
          circuitById: circuitById,
        ),
      );
    }
    if (step is SubCircuitStep) {
      final sub = circuitById(step.circuitId);
      if (sub != null) {
        yield* _validatesEdges(sub, sourcePath, circuitById: circuitById);
      }
    }
  }
}

/// Every node path currently invalidated in [circuit]'s subtree, mapped to how
/// many DISTINCT `validates`-source stamps invalidate it right now (zero
/// entries for a node nothing currently invalidates). The shared engine of
/// [invalidatedNodes] and [derivedGeneration] — computed once, read twice, so
/// [effectiveCursor] never re-walks the circuit per node.
Map<String, int> _generationsByPath(
  Circuit circuit,
  CircuitCursor projected,
  CircuitResults results,
  String nodePath, {
  required Circuit? Function(String circuitId) circuitById,
  required Map<String, int> supersedesDepthByPath,
}) {
  final generations = <String, int>{};
  for (final edge in _validatesEdges(
    circuit,
    nodePath,
    circuitById: circuitById,
  )) {
    if (!_stampInvalidates(projected, results, edge.sourcePath)) continue;
    final generation = supersedesDepthByPath[edge.targetPath] ?? 0;
    for (final path in edge.closure) {
      generations[path] = generation;
    }
  }
  return generations;
}

/// The set of node paths a `validates`-source stamp currently invalidates,
/// transitively — backward motion's exact mirror of [depsSatisfied]: a
/// `validates` source whose stamp invalidates marks its target's transitive-
/// dependent closure (∪ the target itself) invalidated. Pure, total: a
/// missing/partial stamp, or no `validates` edges at all, yields the empty set
/// (Q4).
Set<String> invalidatedNodes(
  Circuit circuit,
  CircuitCursor projected,
  CircuitResults results,
  String nodePath, {
  required Circuit? Function(String circuitId) circuitById,
  required Map<String, int> supersedesDepthByPath,
}) => _generationsByPath(
  circuit,
  projected,
  results,
  nodePath,
  circuitById: circuitById,
  supersedesDepthByPath: supersedesDepthByPath,
).keys.toSet();

/// The derived incarnation axis for [path] (item 7): the active step bead's
/// supersedes-chain depth when [path] is currently invalidated. Zero when
/// [path] is not currently invalidated by anything. A52 Ratified makes that
/// chain the durable rework-round history; this reads graph structure, never a
/// mutable counter.
int derivedGeneration(
  Circuit circuit,
  CircuitCursor projected,
  CircuitResults results,
  String nodePath, {
  required String path,
  required Circuit? Function(String circuitId) circuitById,
  required Map<String, int> supersedesDepthByPath,
}) =>
    _generationsByPath(
      circuit,
      projected,
      results,
      nodePath,
      circuitById: circuitById,
      supersedesDepthByPath: supersedesDepthByPath,
    )[path] ??
    0;

/// The projected cursor with every currently-invalidated node DEMOTED and
/// re-keyed (item 7/8's collapse — DESIGN-tg-pm6.md §3 conflict 8): a node
/// [derivedGeneration] counts below [kMaxReworkRounds] is set to
/// [StepState.pending] with `rewindCount := derivedGeneration` only as a
/// compatibility read for existing `CircuitScope`. A52 Ratified makes the
/// successor bead id the real incarnation identity: new bead id -> new
/// breadcrumb -> new ValueKey. A node AT the cap is set to [StepState.gated] —
/// "surfaces escalation instead of demoting" — which `frontier.dart`'s
/// UNCHANGED runnable-state gate already withholds from the frontier exactly
/// like a human-parked node today (D-7: `StepState.gated => false`), so
/// [derivedEscalation] is a companion READ, not a second gate this file adds.
///
/// A node nothing currently invalidates passes through from [projected]
/// UNTOUCHED — in particular its `rewindCount` stays whatever [projected]
/// carries (always `0` under the molecule codec, R1). Pure, total, cheap,
/// idempotent (Q4): calling this twice on the identical snapshot returns
/// value-equal cursors.
CircuitCursor effectiveCursor(
  Circuit circuit,
  CircuitCursor projected,
  CircuitResults results,
  String nodePath, {
  required Circuit? Function(String circuitId) circuitById,
  required Map<String, int> supersedesDepthByPath,
}) {
  final generations = _generationsByPath(
    circuit,
    projected,
    results,
    nodePath,
    circuitById: circuitById,
    supersedesDepthByPath: supersedesDepthByPath,
  );
  if (generations.isEmpty) return projected;
  final effective = <String, NodeCursor>{...projected};
  generations.forEach((path, generation) {
    effective[path] = cursorNodeAt(projected, path).copyWith(
      state: generation >= kMaxReworkRounds
          ? StepState.gated
          : StepState.pending,
      rewindCount: generation,
    );
  });
  return effective;
}

/// = `eligibleSteps(circuit, effectiveCursor(...), nodePath, ...)`. Forward
/// motion (a `dependsOn` completed) and backward motion (a `validates` stamp
/// invalidated an ancestor) both fall out of this ONE call — no signal, no
/// `RouteVerdict`, no route naming a step (item 7; tg-ie8 falls out for free).
/// Pure, total, cheap, idempotent (Q4) — safe to call every reconcile tick.
List<CircuitStep> liveFrontier(
  Circuit circuit,
  CircuitCursor projected,
  CircuitResults results,
  String nodePath, {
  required Circuit? Function(String circuitId) circuitById,
  required DateTime now,
  required Map<String, int> supersedesDepthByPath,
}) => eligibleSteps(
  circuit,
  effectiveCursor(
    circuit,
    projected,
    results,
    nodePath,
    circuitById: circuitById,
    supersedesDepthByPath: supersedesDepthByPath,
  ),
  nodePath,
  circuitById: circuitById,
  now: now,
);

/// Every node path in [circuit]'s subtree, depth-first in DECLARATION order
/// (mirrors [firstBrokenNode]'s own traversal, so "the first escalating node"
/// means the same thing here that it means there).
Iterable<String> _declarationOrderPaths(
  Circuit circuit,
  String nodePath, {
  required Circuit? Function(String circuitId) circuitById,
}) sync* {
  for (final step in circuit.steps) {
    final path = stepPath(nodePath, step.stepId);
    yield path;
    if (step is SubCircuitStep) {
      final sub = circuitById(step.circuitId);
      if (sub != null) {
        yield* _declarationOrderPaths(sub, path, circuitById: circuitById);
      }
    }
  }
}

/// The FIRST node (declaration order, depth-first) whose [derivedGeneration]
/// has reached [kMaxReworkRounds] — the rework-cap BELT, derived: at the cap
/// the derivation STOPS demoting (see [effectiveCursor]) and surfaces the node
/// here instead, for a later rung's wiring to feed into the EXISTING
/// `firstBrokenNode` / `_scheduleEscalation` path (`session_scope.dart:696`) —
/// no router-side check, no engine primitive of its own. Null when nothing is
/// at the cap. Capture-only shape (mirrors [firstBrokenNode]): never gates
/// orchestration by itself — [effectiveCursor] already withheld the node via
/// [StepState.gated] before this is ever consulted.
({String path, String reason})? derivedEscalation(
  Circuit circuit,
  CircuitCursor projected,
  CircuitResults results,
  String nodePath, {
  required Circuit? Function(String circuitId) circuitById,
  required Map<String, int> supersedesDepthByPath,
}) {
  final generations = _generationsByPath(
    circuit,
    projected,
    results,
    nodePath,
    circuitById: circuitById,
    supersedesDepthByPath: supersedesDepthByPath,
  );
  for (final path in _declarationOrderPaths(
    circuit,
    nodePath,
    circuitById: circuitById,
  )) {
    final generation = generations[path] ?? 0;
    if (generation >= kMaxReworkRounds) {
      return (
        path: path,
        reason: 'rework cap reached ($generation/$kMaxReworkRounds)',
      );
    }
  }
  return null;
}
