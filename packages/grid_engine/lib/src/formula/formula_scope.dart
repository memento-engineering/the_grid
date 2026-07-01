/// The reentrant inflater (ADR-0008 D4 / M4-P1 §4, Track D).
///
/// `FormulaScope` is a PURE `StatelessSeed` — the depth-analogue of `WorkList` +
/// `SessionResolver`, with ZERO pipeline subscription (invariant 1). Its `build`
/// reads only the INJECTED cursor (threaded down from `WorkList`'s reconcile
/// cascade, A39 — never a re-query), computes the eligible frontier with the
/// pure predicate, and maps each eligible step to a keyed child Seed:
///
/// - a [CapabilityStep] → an engine leaf via `CapabilityRegistry.host`
///   (a `CapabilityHost` — Track E; a fake in Track D tests);
/// - a [SubFormulaStep] → a nested `FormulaScope` (REENTRANCY: the SAME inflater
///   one level down).
///
/// The await-all barrier IS the predicate withholding a downstream step until
/// its deps reach a positive terminal; a supervised restart bumps the
/// incarnation in the child key, so keyed reconcile unmounts the old + mounts
/// the new. `FormulaScope` compiles to a `ComponentBranch` (single child) →
/// one `_FormulaChildren` (`MultiChildBranch`, keyed reconcile), mirroring the
/// proven `WorkList → _WorkBeads` topology exactly.
library;

import 'package:genesis_tree/genesis_tree.dart';
import 'package:grid_controller/grid_controller.dart';

import '../sdk/cursor.dart';
import '../sdk/formula.dart';
import '../sdk/frontier.dart';
import 'capability_registry.dart';
import 'session_handle.dart';

/// The pure inflater for one formula instance rooted at [nodePath], under
/// [cursor] (M4-P1 §4). Engine-private — an asset never subclasses it.
class FormulaScope extends StatelessSeed {
  /// Inflates [formula] for work [bead] at [nodePath] under [cursor] (with the
  /// session [results] threaded down for sibling reads — D-5).
  const FormulaScope({
    required this.formula,
    required this.bead,
    required this.cursor,
    required this.results,
    required this.nodePath,
    super.key,
  });

  /// The formula to inflate.
  final Formula formula;

  /// The full work bead this formula serves — pure config, threaded into each
  /// `StepMount` (and down any nested sub-formula) so a `CapabilityHost` can hand
  /// its capability the rich bead. Reentrant: a sub-formula serves the SAME bead.
  final Bead bead;

  /// The injected cursor (config, threaded from `WorkList`'s cascade — NOT a
  /// subscription). A missing node reads as a fresh `pending` cursor.
  final FormulaCursor cursor;

  /// The injected per-node result payloads (config, threaded from `SessionScope`
  /// — NOT a subscription). Handed to each `StepMount` so a `ServiceCapability`
  /// reads its siblings' grades pull-free (D-5).
  final Map<String, Map<String, String>> results;

  /// This formula instance's path (`bead.id` at the root; `'$parent/$stepId'`
  /// for a nested sub-formula).
  final String nodePath;

  @override
  Seed build(TreeContext context) {
    final registry = context.dependOnInheritedSeedOfExactType<CapabilityRegistry>();
    assert(
      registry != null,
      'FormulaScope requires an ambient CapabilityRegistry (the kernel/extension '
      'provides one; tests inject a fake)',
    );
    final session = context.dependOnInheritedSeedOfExactType<SessionHandle>();
    assert(
      session != null,
      'FormulaScope requires an ambient SessionHandle (SessionScope provides it '
      'once the session resolves)',
    );
    final reg = registry!;
    final eligible = eligibleSteps(
      formula,
      cursor,
      nodePath,
      formulaById: reg.formula,
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
                bead: bead,
                nodePath: path,
                session: session!,
                node: node,
                // The incarnation key: a supervised restart bumps restartCount
                // → a new key → keyed reconcile swaps the leaf (D-5).
                key: ValueKey('$path#${node.restartCount}'),
                backoff: formula.backoff,
                maxRestarts: formula.maxRestarts,
                // The WHOLE cursor + results, threaded down so a host's
                // ServiceCapability reads its siblings pull-free (D-5).
                cursor: cursor,
                results: results,
              ),
            ),
          );
        case SubFormulaStep(:final formulaId):
          final sub = reg.formula(formulaId);
          // An unresolvable sub-formula is skipped (the predicate already
          // fail-closes any dep ON it; nothing to inflate).
          if (sub == null) continue;
          children.add(
            FormulaScope(
              formula: sub,
              bead: bead,
              cursor: cursor,
              results: results,
              nodePath: path,
              key: ValueKey('$path/scope'),
            ),
          );
      }
    }
    return _FormulaChildren(children);
  }
}

/// The keyed-reconcile container `FormulaScope` builds — the ONE generic
/// container kind for a formula's frontier (the depth-analogue of `_WorkBeads`).
///
/// Each child is keyed (incarnation-keyed for a leaf, path-keyed for a nested
/// scope), so reconcile preserves a still-eligible step's branch (and its
/// running process) across cursor ticks; a step entering the frontier mounts
/// (spawn), one leaving (job complete / supervised re-key) unmounts (kill).
class _FormulaChildren extends MultiChildSeed {
  _FormulaChildren(List<Seed> children) : super(children: children);
}
