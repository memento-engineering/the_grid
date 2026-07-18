/// The molecule model's write/read codec + `instantiateMolecule` — cook's role
/// (`DESIGN-tg-pm6.md` §4, R1).
///
/// [stepBeadMetadata] is the repeated per-transition write (the molecule-model
/// analogue of `session_bead.dart`'s `nodeCursorMetadata`); [projectMoleculeCursor]
/// is its read-back mirror of `projectCircuitCursor`
/// (`session_bead.dart:459`); [instantiateMolecule] is the one-time MINT that
/// compiles a `Circuit` formula into a [GraphApplyPlan] — a pure function, zero
/// I/O, exactly like `sdk/frontier.dart`'s `eligibleSteps`. Every dependency
/// resolution here rides `sdk/frontier.dart`'s own `stepPath`/`depTerminalPath`
/// VERBATIM, so a `dependsOn` on a `SubCircuitStep` sibling targets the
/// IDENTICAL terminal-step descendant path the live engine's `depsSatisfied`
/// would read — the native edges this file mints and the in-memory frontier
/// the unchanged engine derives never disagree about what a dependency means.
///
/// Never edits `domain/session_bead.dart`. `ResultKeys` there is reused
/// VERBATIM on the step bead (not re-declared here).
library;

import 'package:beads_dart/beads_dart.dart';

import '../domain/session_bead.dart' show truncateReason;
import '../sdk/circuit.dart';
import '../sdk/cursor.dart';
import '../sdk/frontier.dart' show depTerminalPath, stepPath;
import 'bead_path_key.dart';
import 'molecule_schema.dart';

/// The flat metadata payload for a step bead's CURSOR-relevant fields — the
/// fields [projectMoleculeCursor] reads back into a [NodeCursor]. NO
/// `{nodePath}` infix (the bead IS the node) and NO `rewindCount` key (Decided
/// item 7: derived, never persisted — see [MoleculeStepKeys]).
///
/// Structural role fields (`stepId`/`capability`/`kind`/`path`/`session`/
/// `swarm`) are stamped ONCE at mint by [instantiateMolecule]; this builder is
/// the REPEATED write a `CapabilityHost` issues on every transition (R5b wires
/// the call site onto the existing `writer.update(stepBeadId, …)` chokepoint —
/// no new writer interface, Decided in `DESIGN-tg-pm6.md` §3 conflict 3).
///
/// [node]'s [NodeCursor.pgid]/[NodeCursor.pid]/[NodeCursor.token] are
/// deliberately NEVER written here — those ride [LeaseKeys], a namespace only
/// the process-lease vendor (R3) ever writes.
Map<String, String> stepBeadMetadata(NodeCursor node) => {
  MoleculeStepKeys.state: node.state.name,
  MoleculeStepKeys.restartCount: node.restartCount.toString(),
  if (node.cooldownUntil != null)
    MoleculeStepKeys.cooldownUntil: node.cooldownUntil!
        .toUtc()
        .toIso8601String(),
  if (node.startedAt != null)
    MoleculeStepKeys.startedAt: node.startedAt!.toUtc().toIso8601String(),
  if (node.finishedAt != null)
    MoleculeStepKeys.finishedAt: node.finishedAt!.toUtc().toIso8601String(),
  if (node.durationMs != null)
    MoleculeStepKeys.durationMs: node.durationMs.toString(),
  if (node.failureReason != null)
    MoleculeStepKeys.failureReason: truncateReason(node.failureReason!),
};

/// Projects a molecule's own beads (a session's `type=molecule`/`type=step`
/// beads — `SessionProjection.moleculeBeads`, wired by a later rung) into the
/// SAME in-memory shape [projectCircuitCursor] yields for the flat model
/// (mirrors `session_bead.dart:459`), plus the reverse lookup a
/// `CapabilityHost` needs to target its writes at the right bead
/// (`InheritedCircuit.beadIdByNodePath`, R2).
///
/// Only `type=step` beads contribute a cursor entry (a molecule bead carries
/// no per-node state of its own — its role is nesting, `DependencyType.parentChild`).
/// A step bead missing [MoleculeStepKeys.path] is malformed and is skipped,
/// fail-closed, exactly like a malformed flat cursor key.
({CircuitCursor cursor, Map<String, String> beadIdByNodePath})
projectMoleculeCursor(Iterable<Bead> moleculeBeads) {
  final cursor = <String, NodeCursor>{};
  final beadIdByNodePath = <String, String>{};
  for (final bead in moleculeBeads) {
    if (bead.issueType != IssueType.step) continue;
    final path = bead.metadata[MoleculeStepKeys.path];
    if (path is! String || path.isEmpty) continue;
    beadIdByNodePath[path] = bead.id;
    cursor[path] = NodeCursor(
      state: _stepState(bead),
      restartCount: _asInt(bead.metadata[MoleculeStepKeys.restartCount]) ?? 0,
      cooldownUntil: _parseDate(bead.metadata[MoleculeStepKeys.cooldownUntil]),
      startedAt: _parseDate(bead.metadata[MoleculeStepKeys.startedAt]),
      finishedAt: _parseDate(bead.metadata[MoleculeStepKeys.finishedAt]),
      durationMs: _asInt(bead.metadata[MoleculeStepKeys.durationMs]),
      failureReason: bead.metadata[MoleculeStepKeys.failureReason]?.toString(),
      // rewindCount stays the freezed default 0 — R4's `effectiveCursor`
      // layers the DERIVED generation in, in memory only, never here.
      // pgid/pid/token stay null — LeaseKeys is a namespace this codec NEVER
      // reads (structurally tested in molecule_codec_test.dart).
    );
  }
  return (cursor: cursor, beadIdByNodePath: beadIdByNodePath);
}

/// The fine [StepState] off [MoleculeStepKeys.state], falling back to bd's own
/// coarse STATUS when the fine key is absent or unrecognised (`closed` ⇒
/// [StepState.complete], `open` ⇒ [StepState.pending]) — the "mostly native
/// vocabulary" mandate: a freshly-minted step bead legitimately carries no
/// fine state yet, and that is read as "hasn't run", not defaulted around.
StepState _stepState(Bead bead) {
  final wire = bead.metadata[MoleculeStepKeys.state]?.toString();
  for (final s in StepState.values) {
    if (s.name == wire) return s;
  }
  return bead.isClosed ? StepState.complete : StepState.pending;
}

int? _asInt(Object? value) => switch (value) {
  final int i => i,
  final String s => int.tryParse(s),
  final num n => n.toInt(),
  _ => null,
};

DateTime? _parseDate(Object? value) =>
    value == null ? null : DateTime.tryParse(value.toString());

/// A [Circuit] is a Dart-implemented FORMULA; mounting it for a session plays
/// COOK's role — this pure function is the compile step that instantiates the
/// durable molecule (Decided item 8). Walks [Circuit.steps], emitting one
/// [GraphNode] per molecule/step (recursing into a [SubCircuitStep]'s own
/// nested circuit) and one [GraphEdge] per nesting / `dependsOn` /
/// validates-convention edge, riding [GraphApplyPlan] verbatim — the caller
/// pours it with `applyGraph(plan, ephemeral: false)` (R6): durable, never a
/// wisp (Decided item 1).
///
/// [sessionId] is the OWNING session bead — already minted before this is
/// called (R5 mints the session, THEN pours the molecule), so it is addressed
/// as an EXISTING bead via [GraphNode.parentId] on the root molecule node
/// only; every nested node's nesting is instead an explicit
/// `DependencyType.parentChild` [GraphEdge] to its enclosing molecule's
/// plan-local key (a [GraphEdge] can only reference keys inside this SAME
/// plan).
///
/// [root] is the caller's breadcrumb so far (work ⇄ session); it seeds the
/// pour's audit [GraphApplyPlan.commitMessage]. The newly-minted beads' OWN
/// [MoleculeCircuitKeys.crumb]/[MoleculeStepKeys.crumb] values do not exist
/// yet — their bead ids are born BY this very pour — so stamping the crumb is
/// a POST-POUR write a later rung performs once `createMolecule` (R6) returns
/// the plan-key → bead-id map; this pure function cannot know them.
///
/// [nodePath] is the engine coordinate root this molecule occupies — the SAME
/// address space `sdk/frontier.dart`'s `stepPath`/`depTerminalPath` already
/// use, reused here verbatim.
///
/// [circuitById] resolves a nested [SubCircuitStep]'s circuit id. A dangling
/// `circuitId`, `dependsOn` target, or [kValidatesParam] target mints nothing
/// for that edge/step — fail-closed, mirroring `depTerminalPath`'s own null
/// propagation.
GraphApplyPlan instantiateMolecule(
  Circuit circuit, {
  required String sessionId,
  required BeadPathKey root,
  required String nodePath,
  Circuit? Function(String id)? circuitById,
}) {
  final resolve = circuitById ?? (String _) => null;
  final nodes = <GraphNode>[];
  final edges = <GraphEdge>[];
  _emitCircuit(
    circuit,
    sessionId: sessionId,
    nodePath: nodePath,
    parentId: sessionId,
    circuitById: resolve,
    nodes: nodes,
    edges: edges,
  );
  return GraphApplyPlan(
    commitMessage: 'grid molecule ${circuit.id} @ ${root.canonical}',
    nodes: nodes,
    edges: edges,
  );
}

/// Emits [circuit]'s own molecule [GraphNode] — parented onto [parentId] ONLY
/// when this is the pour's true root (an EXISTING session bead); a recursive
/// call for a [SubCircuitStep] passes `parentId: null` and relies entirely on
/// the `DependencyType.parentChild` edge its enclosing step already wired —
/// plus one node per step, recursing into every [SubCircuitStep] one level
/// deeper.
void _emitCircuit(
  Circuit circuit, {
  required String sessionId,
  required String nodePath,
  required String? parentId,
  required Circuit? Function(String) circuitById,
  required List<GraphNode> nodes,
  required List<GraphEdge> edges,
}) {
  nodes.add(
    GraphNode(
      key: nodePath,
      title: 'circuit ${circuit.id}',
      type: IssueType.molecule.wire,
      parentId: parentId,
      metadata: {
        MoleculeCircuitKeys.formula: circuit.id,
        MoleculeCircuitKeys.session: sessionId,
      },
    ),
  );

  for (final step in circuit.steps) {
    final stepKey = stepPath(nodePath, step.stepId);
    switch (step) {
      case CapabilityStep(:final capabilityId, :final kind, :final params):
        nodes.add(
          GraphNode(
            key: stepKey,
            title: 'step ${step.stepId}',
            type: IssueType.step.wire,
            metadata: {
              MoleculeStepKeys.stepId: step.stepId,
              MoleculeStepKeys.capability: capabilityId,
              MoleculeStepKeys.kind: kind.name,
              MoleculeStepKeys.path: stepKey,
              MoleculeStepKeys.session: sessionId,
              if (params[kSwarmParam] != null)
                MoleculeStepKeys.swarm: params[kSwarmParam]!,
            },
          ),
        );
        edges.add(
          GraphEdge(
            fromKey: stepKey,
            toKey: nodePath,
            type: DependencyType.parentChild.wire,
          ),
        );
        _emitSiblingEdges(circuit, step, nodePath, stepKey, circuitById, edges);

      case SubCircuitStep(:final circuitId):
        final nested = circuitById(circuitId);
        // A dangling circuitId mints nothing for this step (fail-closed).
        if (nested == null) {
          continue;
        }
        edges.add(
          GraphEdge(
            fromKey: stepKey,
            toKey: nodePath,
            type: DependencyType.parentChild.wire,
          ),
        );
        _emitSiblingEdges(circuit, step, nodePath, stepKey, circuitById, edges);
        _emitCircuit(
          nested,
          sessionId: sessionId,
          nodePath: stepKey,
          parentId: null,
          circuitById: circuitById,
          nodes: nodes,
          edges: edges,
        );
    }
  }
}

/// Wires [step]'s `dependsOn` barrier as [DependencyType.blocks] edges, plus
/// its optional [kValidatesParam] edge — both resolved through
/// `sdk/frontier.dart`'s own [depTerminalPath], so a dependency on a
/// [SubCircuitStep] sibling targets the SAME terminal-step descendant path the
/// live engine's `depsSatisfied` reads. A dangling dep or validates target
/// mints no edge (fail-closed).
void _emitSiblingEdges(
  Circuit circuit,
  CircuitStep step,
  String nodePath,
  String stepKey,
  Circuit? Function(String) circuitById,
  List<GraphEdge> edges,
) {
  for (final depId in step.dependsOn) {
    final depPath = depTerminalPath(circuit, nodePath, depId, circuitById);
    if (depPath == null) continue;
    edges.add(
      GraphEdge(
        fromKey: stepKey,
        toKey: depPath,
        type: DependencyType.blocks.wire,
      ),
    );
  }
  final validatesTarget = step.params[kValidatesParam];
  if (validatesTarget == null) return;
  final targetPath = depTerminalPath(
    circuit,
    nodePath,
    validatesTarget,
    circuitById,
  );
  if (targetPath == null) return;
  edges.add(
    GraphEdge(
      fromKey: stepKey,
      toKey: targetPath,
      type: DependencyType.validates.wire,
    ),
  );
}
