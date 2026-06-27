import 'package:grid_controller/grid_controller.dart';

/// The observable snapshot seam the join bridge subscribes to — the narrow
/// surface of a `GridControllerRuntime` the bridge actually needs.
///
/// Decouples [StationJoinBridge] from the concrete runtime so the bridge is
/// fake-testable in pure-Dart (a broadcast controller + a settable [current]).
/// `grid_cli` adapts the two real `GridControllerRuntime`s (work + state) to
/// this interface at composition time — the bridge never constructs one.
///
/// The contract mirrors the real runtime exactly:
/// - [snapshots] is **change-gated** — it emits only on a non-empty diff, never
///   on every re-query (so the bridge can push 1:1 per real change), and it is a
///   **broadcast** stream that does **not** replay (A39).
/// - [current] is the last emitted snapshot, or `null` before the baseline —
///   how a late subscriber recovers the value the broadcast stream won't replay.
abstract interface class SnapshotSource {
  /// The work graph as it changes — change-gated, broadcast, non-replaying.
  Stream<GraphSnapshot> get snapshots;

  /// The most recent snapshot, or `null` before the first baseline.
  GraphSnapshot? get current;
}
