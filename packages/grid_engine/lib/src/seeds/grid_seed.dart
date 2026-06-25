import 'package:genesis_tree/genesis_tree.dart';

import 'rig_scope.dart';

/// The root of the running system (ADR-0007): a keyed-reconcile container of
/// per-rig scopes. `build(observed)` starts here — the tree IS the engine, and
/// the Grid's children ARE the rigs.
///
/// A [MultiChildSeed] (not a component): it *declares* its rig children up
/// front rather than building one. Each [RigScope] should be keyed by rig id so
/// adding/removing a rig mounts/unmounts exactly that scope.
class Grid extends MultiChildSeed {
  /// Creates the Grid over [rigs].
  Grid(List<RigScope> rigs, {super.key}) : super(children: rigs);
}
