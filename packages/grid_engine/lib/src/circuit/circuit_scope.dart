/// The reentrant inflater — it energizes (electrifies) a [Circuit] into a
/// mounted subtree (ADR-0008 D4 / M4-P1 §4, Track D).
///
/// `CircuitScope` is a PURE `StatelessSeed` — the depth-analogue of `WorkList` +
/// `SessionResolver`, with ZERO pipeline subscription (invariant 1). Its `build`
/// reads only the INJECTED cursor (threaded down from `WorkList`'s reconcile
/// cascade, A39 — never a re-query), computes the eligible frontier with the
/// pure predicate, and maps each eligible step to a keyed child Seed:
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

import '../diagnostics/diagnosable.dart';
import '../sdk/cursor.dart';
import '../sdk/circuit.dart';
import '../sdk/frontier.dart';
import 'capability_registry.dart';
import 'session_handle.dart';

/// The pure inflater for one circuit instance rooted at [nodePath], under
/// [cursor] (M4-P1 §4). Engine-private — an asset never subclasses it.
class CircuitScope extends StatelessSeed with Diagnosable {
  /// Inflates [circuit] at [nodePath] under [cursor]. The work `Bead` and the
  /// session `SiblingView` are AMBIENT (mounted by `WorkBead`/`SessionScope`,
  /// 2026-07-02) — an effect reads them with the non-binding lookup; the
  /// inflater threads nothing but the frontier's own inputs.
  const CircuitScope({
    required this.circuit,
    required this.cursor,
    required this.nodePath,
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

  @override
  void debugFillProperties(DiagnosticsBuilder builder) {
    super.debugFillProperties(builder);
    builder.add(StringProperty('nodePath', nodePath));
  }

  @override
  Seed build(TreeContext context) {
    final registry = context
        .dependOnInheritedSeedOfExactType<CapabilityRegistry>();
    assert(
      registry != null,
      'CircuitScope requires an ambient CapabilityRegistry (the kernel/extension '
      'provides one; tests inject a fake)',
    );
    final session = context.dependOnInheritedSeedOfExactType<SessionHandle>();
    assert(
      session != null,
      'CircuitScope requires an ambient SessionHandle (SessionScope provides it '
      'once the session resolves)',
    );
    final reg = registry!;
    final eligible = eligibleSteps(
      circuit,
      cursor,
      nodePath,
      circuitById: reg.circuit,
      now: reg.now(),
    );
    final children = <Seed>[];
    for (final step in eligible) {
      final path = stepPath(nodePath, step.stepId);
      final node = cursorNodeAt(cursor, path);
      switch (step) {
        case CapabilityStep():
          children.add(
            reg.host(
              StepMount(
                step: step,
                nodePath: path,
                // The graph this step is a member of (a VALUE — the Rewind arm
                // resolves its named siblings + their dependents against it).
                circuit: circuit,
                circuitPath: nodePath,
                session: session!,
                node: node,
                // The incarnation key: a supervised restart bumps restartCount
                // (D-5) and a routing REWIND bumps rewindCount (tg-o90) → a new
                // key → keyed reconcile swaps the leaf. A rewound node that is
                // still MOUNTED (a daemon) is therefore torn down and re-run,
                // never left alive under a stale incarnation.
                key: ValueKey('$path#${node.restartCount}.${node.rewindCount}'),
                backoff: circuit.backoff,
                maxRestarts: circuit.maxRestarts,
              ),
            ),
          );
        case SubCircuitStep(:final circuitId):
          final sub = reg.circuit(circuitId);
          // An unresolvable sub-circuit is skipped (the predicate already
          // fail-closes any dep ON it; nothing to inflate).
          if (sub == null) continue;
          children.add(
            CircuitScope(
              circuit: sub,
              cursor: cursor,
              nodePath: path,
              key: ValueKey('$path/scope'),
            ),
          );
      }
    }
    return _CircuitChildren(children);
  }
}

/// The keyed-reconcile container `CircuitScope` builds — the ONE generic
/// container kind for a circuit's frontier (the depth-analogue of `_WorkBeads`).
///
/// Each child is keyed (incarnation-keyed for a leaf, path-keyed for a nested
/// scope), so reconcile preserves a still-eligible step's branch (and its
/// running process) across cursor ticks; a step entering the frontier mounts
/// (spawn), one leaving (job complete / supervised re-key) unmounts (kill).
class _CircuitChildren extends MultiChildSeed {
  _CircuitChildren(List<Seed> children) : super(children: children);
}
