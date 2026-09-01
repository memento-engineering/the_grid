/// The reentrant inflater — it energizes (electrifies) a [Circuit] into a
/// mounted subtree (ADR-0008 D4 / M4-P1 §4, Track D).
///
/// `CircuitScope` is a PURE `StatelessSeed` — the depth-analogue of `WorkList` +
/// `SessionResolver`, with ZERO pipeline subscription (invariant 1). Its `build`
/// reads only the INJECTED cursor (threaded down from `WorkList`'s reconcile
/// cascade, A39 — never a re-query), computes the eligible frontier with the
/// pure predicate, and maps every declared step to a stable, path-keyed node.
/// Only an eligible step has an effect child:
///
/// - a [CapabilityStep] → an engine leaf via `CapabilityRegistry.host`
///   (a `CapabilityHost` — Track E; a fake in Track D tests);
/// - a [SubCircuitStep] → a nested `CircuitScope` (REENTRANCY: the SAME inflater
///   one level down).
///
/// The await-all barrier IS the predicate withholding a downstream step until
/// its deps reach a positive terminal; a supervised restart bumps the
/// incarnation in the child key, so keyed reconcile unmounts the old + mounts
/// the new. `CircuitScope` compiles to a `ComponentBranch` (single child) →
/// one `_CircuitChildren` (`MultiChildBranch`, keyed reconcile), mirroring the
/// proven `WorkList → _WorkBeads` topology exactly.
library;

import 'package:genesis_tree/genesis_tree.dart';

import '../seeds/provider.dart';

import '../diagnostics/diagnosable.dart';
import '../molecule/inherited_circuit.dart';
import '../sdk/cursor.dart';
import '../sdk/circuit.dart';
import '../sdk/frontier.dart';
import 'capability_registry.dart';
import 'session_handle.dart';

/// The pure inflater for one circuit instance rooted at [nodePath], under
/// [cursor] (M4-P1 §4). Engine-private — an asset never subclasses it.
class CircuitScope extends StatelessSeed with GridDiagnosticable {
  /// Inflates [circuit] at [nodePath] under [cursor]. The work `Bead` and the
  /// session `SiblingView` are AMBIENT (mounted by `WorkBead`/`SessionScope`,
  /// 2026-07-02) — an effect reads them with the non-binding lookup; the
  /// inflater threads nothing but the frontier's own inputs.
  const CircuitScope({
    required this.circuit,
    required this.cursor,
    required this.nodePath,
    this.circuitRoundsByPath = const {},
    this.gateResumePaths = const {},
    super.key,
  });

  /// The circuit to inflate.
  final Circuit circuit;

  /// The injected cursor (config, threaded from `WorkList`'s cascade — NOT a
  /// subscription). A missing node reads as a fresh `pending` cursor.
  final CircuitCursor cursor;

  /// This circuit instance's path (`bead.id` at the root; `'$parent/$stepId'`
  /// for a nested sub-circuit).
  final String nodePath;

  /// Session circuit incarnation by full step node path.
  final Map<String, int> circuitRoundsByPath;

  /// Step paths whose circuit round includes at least one closed gate cycle.
  final Set<String> gateResumePaths;

  @override
  void debugFillProperties(DiagnosticsBuilder properties) {
    super.debugFillProperties(properties);
    properties.addTyped(StringProperty('nodePath', nodePath));
  }

  @override
  Seed build(TreeContext context) {
    final registry = context.watch<CapabilityRegistry>();
    if (registry == null) {
      throw StateError(
        'CircuitScope requires an ambient CapabilityRegistry '
        '(the kernel/extension provides one; tests inject a fake)',
      );
    }
    final session = context.watch<SessionHandle>();
    if (session == null) {
      throw StateError(
        'CircuitScope requires an ambient SessionHandle '
        '(SessionScope provides it once the session resolves)',
      );
    }
    final inheritedCircuit = context.watch<InheritedCircuit>();

    final beadIds = <String, String>{};
    if (inheritedCircuit != null) {
      final pathsByBeadId = <String, String>{};
      for (final step in circuit.steps) {
        final path = stepPath(nodePath, step.stepId);
        final beadId = inheritedCircuit.beadIdByNodePath[path];
        // A passive step can precede its durable bead in adopted historical
        // projections. Its id becomes mandatory when it reaches the frontier.
        if (beadId == null) continue;
        if (beadId.isEmpty) {
          throw StateError(
            'CircuitScope has an empty step-bead id for "$path"',
          );
        }
        final priorPath = pathsByBeadId[beadId];
        if (priorPath != null && priorPath != path) {
          throw StateError(
            'CircuitScope step-bead id "$beadId" is assigned to both '
            '"$priorPath" and "$path"',
          );
        }
        beadIds[path] = beadId;
        pathsByBeadId[beadId] = path;
      }
    }

    final eligiblePaths = eligibleSteps(
      circuit,
      cursor,
      nodePath,
      circuitById: registry.circuit,
      now: registry.now(),
    ).map((step) => stepPath(nodePath, step.stepId)).toSet();

    final activeChildren = <Seed>[];
    final passiveChildren = <Seed>[];
    for (final step in circuit.steps) {
      final path = stepPath(nodePath, step.stepId);
      final node = cursorNodeAt(cursor, path);
      Seed? effect;
      if (eligiblePaths.contains(path)) {
        switch (step) {
          case CapabilityStep():
            final beadId = beadIds[path];
            // An adopted cursor can briefly lead its successor-bead join,
            // and a fresh projection is complete by construction —
            // SessionScope refuses to mount an `InheritedCircuit` whose
            // molecule projection carries zero step beads (tg-nmhy). A
            // remaining path-level miss is a mis-composition whose LOUD
            // point of consumption is `CapabilityHost._stepBeadId`,
            // contained per-work at the allocation seam (ADR-0008 D10: one
            // bad bead never crashes the station). NEVER throw here: a
            // build-path throw escapes the tree flush unguarded
            // (`StationKernel._scheduleFlush` runs in a root-zone
            // microtask) and killed the whole resident VM.
            effect = registry.host(
              StepMount(
                step: step,
                nodePath: path,
                circuit: circuit,
                circuitPath: nodePath,
                session: session,
                node: node,
                circuitRound: circuitRoundsByPath[path] ?? 0,
                isGateResume: gateResumePaths.contains(path),
                // tg-q3q0 (deep): the circuit round is part of the key. The
                // host freezes StepArgs (grid.round included) at initState
                // and NEVER re-keys on seed change, so a round that flips
                // after mount (the supersedes edge landing a snapshot later,
                // a generation demotion) MUST re-key the element or the lane
                // runs an entire wave stamping the old round — the round-0
                // starvation class.
                key: ValueKey(
                  beadId == null
                      ? '$path#${node.restartCount}'
                            '#g${circuitRoundsByPath[path] ?? 0}'
                      : '$beadId#${node.restartCount}'
                            '#g${circuitRoundsByPath[path] ?? 0}',
                ),
                backoff: circuit.backoff,
                maxRestarts: circuit.maxRestarts,
              ),
            );
          case SubCircuitStep(:final circuitId):
            final sub = registry.circuit(circuitId);
            if (sub != null) {
              effect = CircuitScope(
                circuit: sub,
                cursor: cursor,
                nodePath: path,
                circuitRoundsByPath: circuitRoundsByPath,
                gateResumePaths: gateResumePaths,
                key: ValueKey('$path/scope'),
              );
            }
        }
      }
      final child = _CircuitStep(
        nodePath: path,
        effect: effect,
        key: ValueKey(path),
      );
      (effect == null ? passiveChildren : activeChildren).add(child);
    }
    return _CircuitChildren([...activeChildren, ...passiveChildren]);
  }
}

/// A stable path-keyed node for one declared circuit step.
///
/// The node persists across frontier changes; only [effect] is
/// frontier/incarnation keyed.
class _CircuitStep extends MultiChildSeed {
  _CircuitStep({required this.nodePath, required Seed? effect, super.key})
    : effect = effect,
      super(children: [if (effect != null) effect]);

  final String nodePath;
  final Seed? effect;
}

/// The keyed-reconcile container holding every declared circuit step.
///
/// Each `_CircuitStep` is path-keyed and persistent. Only its effect child is
/// mounted on the frontier and keyed to its current incarnation.
class _CircuitChildren extends MultiChildSeed {
  _CircuitChildren(List<Seed> children) : super(children: children);
}
