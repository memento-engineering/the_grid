/// The pure REWIND SET — routing's actuation surface (the dual of fan-out;
/// `docs/M5-THE-CIRCUIT-BUILD-ORDER.md` D-4 promoted to a first-class
/// `StepOutcome` arm, tg-o90).
///
/// A `Rewind` names SIBLING step ids in the rewinding node's OWN circuit. The
/// nodes that must re-run are: those steps, every step transitively DOWNSTREAM
/// of them (the `dependsOn` closure), and the rewinding node ITSELF — each
/// expanded to its full node paths, because a `SubCircuitStep` whose `complete`
/// descendants were left behind would keep satisfying the parent's dep and never
/// re-run.
///
/// Pure (zero I/O, zero `Seed`, injected `circuitById`) — the `CapabilityHost`
/// maps the returned paths to ONE merge-safe cursor write.
library;

import 'circuit.dart';
import 'frontier.dart';

/// The step ids of [circuit] that transitively DEPEND on any of [stepIds] — the
/// downstream closure ([stepIds] themselves are NOT included). Fixed-point
/// iteration, so it terminates on any graph (a cyclic `dependsOn` simply
/// saturates).
Set<String> transitiveDependents(Circuit circuit, Set<String> stepIds) {
  final downstream = <String>{};
  var changed = true;
  while (changed) {
    changed = false;
    for (final step in circuit.steps) {
      if (stepIds.contains(step.stepId) || downstream.contains(step.stepId)) {
        continue;
      }
      final blocked = step.dependsOn.any(
        (dep) => stepIds.contains(dep) || downstream.contains(dep),
      );
      if (blocked) {
        downstream.add(step.stepId);
        changed = true;
      }
    }
  }
  return downstream;
}

/// Every node path in [step]'s subtree, rooted at [circuitPath]: the step's own
/// path, plus — for a [SubCircuitStep] — every descendant node path (recursing
/// through [circuitById]).
///
/// [ancestors] is the chain of circuit ids ABOVE this step (never a global
/// visited set: the SAME circuitId legitimately appears in two sibling
/// sub-circuits — the Burn's two `deploy` harnesses — and both must expand). A
/// self-referential circuit id terminates fail-closed at its own path; an
/// unresolvable circuitId contributes only its own (never-written) path.
Set<String> subtreeNodePaths(
  String circuitPath,
  CircuitStep step, {
  required Circuit? Function(String circuitId) circuitById,
  Set<String> ancestors = const {},
}) {
  final path = stepPath(circuitPath, step.stepId);
  final paths = <String>{path};
  if (step is! SubCircuitStep) return paths;
  if (ancestors.contains(step.circuitId)) return paths; // cyclic — stop.
  final sub = circuitById(step.circuitId);
  if (sub == null) return paths;
  final nextAncestors = {...ancestors, step.circuitId};
  for (final child in sub.steps) {
    paths.addAll(
      subtreeNodePaths(
        path,
        child,
        circuitById: circuitById,
        ancestors: nextAncestors,
      ),
    );
  }
  return paths;
}

/// The full node-path set ONE `Rewind` resets (tg-o90): the named
/// [targetStepIds] ∪ their transitive dependents ∪ the rewinding [selfStepId],
/// each expanded to its whole subtree.
///
/// Every returned path gets `state=pending` + a bumped per-node `rewindCount` in
/// ONE chokepoint write; the bump RE-KEYS each node, so keyed reconcile tears
/// the old incarnations down (killing any live effect) and re-runs them virgin.
///
/// SCOPE: siblings of the rewinding node, in ITS circuit. A node in a PARENT
/// circuit is never reset — it cannot have advanced, because its `dependsOn` on
/// this circuit resolves to this circuit's terminal descendant, which is in the
/// set (or downstream of it) and is going `pending` right now.
///
/// A dangling id in [targetStepIds] is SKIPPED here; the host validates first
/// and routes a dangling/empty rewind to a LOUD supervised failure (a typo'd
/// step id must never silently degrade into "re-run only myself, forever").
Set<String> rewindNodePaths(
  Circuit circuit,
  String circuitPath,
  Set<String> targetStepIds, {
  required String selfStepId,
  required Circuit? Function(String circuitId) circuitById,
}) {
  final ids = <String>{
    ...targetStepIds,
    ...transitiveDependents(circuit, targetStepIds),
    selfStepId,
  };
  final paths = <String>{};
  for (final id in ids) {
    final step = circuit.stepById(id);
    if (step == null) continue; // dangling — the host already failed LOUD.
    paths.addAll(subtreeNodePaths(circuitPath, step, circuitById: circuitById));
  }
  return paths;
}
