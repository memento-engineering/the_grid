/// A stable ambient provider (ADR-0008 D6 / M4-P1 D-6).
///
/// `updateShouldNotify => false`: the value is a long-lived handle (the
/// `CapabilityRegistry`, the `ServiceBundle`, the `DartEnvironment`), never an
/// in-place-swapped value. Resolving it is a benign dependency, never a rebuild
/// — so even if the kernel ever re-provides it, no `FormulaScope` at any depth
/// force-rebuilds (the "config built 100×" failure invariant 1 forbids). Dynamic
/// reload is modeled as a NEW run / subtree remount, never an in-place swap.
library;

import 'package:genesis_tree/genesis_tree.dart';

/// An [InheritedSeed] that NEVER notifies its dependents on update — for stable
/// ambient handles (D-6).
class StableInheritedSeed<T extends Object> extends InheritedSeed<T> {
  /// Provides the stable [value] over [child].
  const StableInheritedSeed({
    required super.value,
    required super.child,
    super.key,
  });

  @override
  bool updateShouldNotify(InheritedSeed<T> oldSeed) => false;
}
