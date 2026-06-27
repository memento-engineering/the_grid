import 'package:genesis_tree/genesis_tree.dart';

import 'substation_scope.dart';

/// The root of the running system (ADR-0007): a keyed-reconcile container of
/// per-rig scopes. `build(observed)` starts here — the tree IS the engine, and
/// the Station's children ARE the substations.
///
/// A [MultiChildSeed] (not a component): it *declares* its rig children up
/// front rather than building one. Each [SubstationScope] should be keyed by rig id so
/// adding/removing a rig mounts/unmounts exactly that scope.
class Station extends MultiChildSeed {
  /// Creates the Station over [substations].
  Station(List<SubstationScope> substations, {super.key}) : super(children: substations);
}
