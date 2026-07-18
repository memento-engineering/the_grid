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
/// derived-generation compose into ONE effective [CircuitCursor] whose
/// [NodeCursor.rewindCount] field carries [derivedGeneration] — so the
/// UNCHANGED `ValueKey('$path#$restart.$rewind')` (`circuit_scope.dart:100`)
/// re-keys a still-mounted incarnation with ZERO edits to `circuit_scope.dart`.
/// [liveFrontier] is then just `eligibleSteps` over it — no second predicate,
/// no `RouteVerdict`, no route naming a step.
///
/// **What "generation" counts, precisely** (there is no persisted counter to
/// read back — item 7 forbids one): [derivedGeneration] is the number of
/// DISTINCT `validates`-source stamps currently invalidating a node — i.e. how
/// many independent structured verdicts are, on THIS snapshot, holding it back.
/// A single always-failing critic can never re-derive "round 3" from a
/// snapshot that only ever remembers ITS OWN latest grade (that would require
/// a persisted history item 7 forbids); a SWARM of same-capability critics
/// each independently validating the SAME target (the established
/// `critic-correctness` / `critic-security` shape, `molecule_codec_test.dart`)
/// gives a genuinely deterministic, snapshot-pure width instead — and widens
/// exactly the case [kMaxReworkRounds] exists to bound: too many simultaneous
/// objections park the work for a human rather than looping it forever.
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
typedef _ValidatesEdge = ({String sourcePath, Set<String> closure});

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
    if (targetId != null && circuit.stepById(targetId) != null) {
      yield (
        sourcePath: sourcePath,
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
}) {
  final generations = <String, int>{};
  for (final edge in _validatesEdges(
    circuit,
    nodePath,
    circuitById: circuitById,
  )) {
    if (!_stampInvalidates(projected, results, edge.sourcePath)) continue;
    for (final path in edge.closure) {
      generations[path] = (generations[path] ?? 0) + 1;
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
}) => _generationsByPath(
  circuit,
  projected,
  results,
  nodePath,
  circuitById: circuitById,
).keys.toSet();

/// The derived incarnation axis for [path] (item 7): how many DISTINCT
/// `validates`-source stamps currently invalidate it — NOT a persisted
/// `rewindCount`, and NOT read back from any durable counter (there is none).
/// Zero when [path] is not currently invalidated by anything. See this file's
/// library doc for why a snapshot-pure derivation counts WIDTH (independent
/// simultaneous objections) rather than a temporal round number.
int derivedGeneration(
  Circuit circuit,
  CircuitCursor projected,
  CircuitResults results,
  String nodePath, {
  required String path,
  required Circuit? Function(String circuitId) circuitById,
}) =>
    _generationsByPath(
      circuit,
      projected,
      results,
      nodePath,
      circuitById: circuitById,
    )[path] ??
    0;

/// The projected cursor with every currently-invalidated node DEMOTED and
/// re-keyed (item 7/8's collapse — DESIGN-tg-pm6.md §3 conflict 8): a node
/// [derivedGeneration] counts below [kMaxReworkRounds] is set to
/// [StepState.pending] with `rewindCount := derivedGeneration`, so the
/// UNCHANGED `ValueKey('$path#$restart.$rewind')` (`circuit_scope.dart:100`)
/// changes and keyed reconcile tears a still-mounted incarnation down
/// (`LeaseAllocation.dispose` releases the process lease — R3) and re-mounts
/// it virgin; a node AT the cap is set to [StepState.gated] instead —
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
}) {
  final generations = _generationsByPath(
    circuit,
    projected,
    results,
    nodePath,
    circuitById: circuitById,
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
}) => eligibleSteps(
  circuit,
  effectiveCursor(
    circuit,
    projected,
    results,
    nodePath,
    circuitById: circuitById,
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
}) {
  final generations = _generationsByPath(
    circuit,
    projected,
    results,
    nodePath,
    circuitById: circuitById,
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
