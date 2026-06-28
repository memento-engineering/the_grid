/// The reentrant resolver (ADR-0008 D4 / M4-P1 §4, Track D).
///
/// Drops in at the `EffectResolver` seam (`effectFor` is typed `Seed`, so it
/// roots a subtree with no change to `WorkBead`): instead of a single effect
/// leaf, it returns an engine-private `SessionScope` that adopt-or-mints the
/// session and inflates the work bead's root formula. This is the live work
/// path — the per-node reentrant cursor (D-3) replaced the 3-value `WorkPhase`.
library;

import 'package:genesis_tree/genesis_tree.dart';
import 'package:grid_controller/grid_controller.dart';

import '../domain/session_projection.dart';
import '../kernel/effect_resolver.dart';
import '../sdk/formula.dart';
import 'session_scope.dart';

/// Picks the root [Formula] for a work [bead] — the bead→formula policy (P1: all
/// coding work → the `code` formula; the Burn bead → the `burn` formula). The
/// composing extension supplies it (Track H); tests inject a fake.
typedef RootFormulaFor = Formula Function(Bead bead);

/// An [EffectResolver] that roots a reentrant `SessionScope` subtree per work
/// bead (Track D).
class FormulaResolver implements EffectResolver {
  /// Creates the resolver over the [rootFormulaFor] policy.
  const FormulaResolver(this.rootFormulaFor);

  /// The bead→root-formula policy.
  final RootFormulaFor rootFormulaFor;

  @override
  Seed effectFor({required Bead bead, SessionProjection? session}) =>
      SessionScope(
        bead: bead,
        formula: rootFormulaFor(bead),
        existingSession: session,
        key: ValueKey('${bead.id}:session'),
      );
}
