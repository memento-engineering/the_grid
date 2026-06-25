import 'package:state_notifier/state_notifier.dart';

import '../domain/joined_snapshot.dart';

/// The single observable source the **work axis** builds from — a
/// [StateNotifier] the join bridge (Track B) drives from OUTSIDE the tree.
///
/// `WorkList` is its ONLY tree observer (derailment-invariant 1: exactly one
/// subscription into the pipelines, living at the work boundary). When the
/// bridge pushes a new value, only `WorkList` marks dirty — observational
/// isolation; the reconcile cascade does the rest.
class JoinedSnapshotNotifier extends StateNotifier<JoinedSnapshot> {
  /// Creates the notifier seeded with [initial] (use [JoinedSnapshot.empty] as
  /// the pre-first-refresh baseline).
  JoinedSnapshotNotifier(super.initial);

  /// Pushes a new joined value — the bridge's only write path. Public because
  /// the notifier is driven externally (by the join bridge), not by internal
  /// transitions; `StateNotifier.state`'s setter is protected.
  void push(JoinedSnapshot snapshot) => state = snapshot;

  /// The current value, read through the public listener API (the `state`
  /// getter is `@visibleForTesting`, off-limits to lib consumers): subscribe
  /// with `fireImmediately`, capture synchronously, then remove.
  JoinedSnapshot get current {
    late JoinedSnapshot value;
    addListener((snapshot) => value = snapshot, fireImmediately: true)();
    return value;
  }
}
