import 'package:genesis_tree/genesis_tree.dart';

/// The terminal leaf of an effect subtree — a branch with no children and the
/// default (empty) rebuild hook (the genesis `Leaf` idiom).
///
/// An effect Seed's `build()` returns this: the effect's real work happens in
/// `initState` / `dispose` (spawn / kill), NOT in `build`, which stays a pure
/// idle leaf (A39 — perception/observation is pull-free; `build` never acts).
class Idle extends Seed {
  /// Creates an idle leaf, optionally [key]ed.
  const Idle({super.key});

  @override
  Branch createBranch() => _IdleBranch(this);
}

class _IdleBranch extends Branch {
  _IdleBranch(Idle super.seed);
}
