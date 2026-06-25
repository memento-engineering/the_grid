import 'package:grid_controller/grid_controller.dart';
import 'package:grid_engine/grid_engine.dart';

/// Adapts a live [GridControllerRuntime] to grid_engine's [SnapshotSource] —
/// the decoupling the bridge author deferred to `grid_cli` (see
/// `grid_engine`'s `snapshot_source.dart`: "`grid_cli` adapts the two real
/// `GridControllerRuntime`s (work + state) to this interface at composition
/// time").
///
/// The [GridControllerRuntime] already exposes the exact surface the bridge
/// needs — a change-gated, broadcast, non-replaying [snapshots] stream and a
/// `null`-before-baseline [current] — so this adapter is a pure pass-through; it
/// owns nothing and subscribes to nothing (the [GridJoinBridge] is the lone
/// subscriber, A39).
class RuntimeSnapshotSource implements SnapshotSource {
  /// Wraps [runtime] (the M1 controller) as a [SnapshotSource].
  const RuntimeSnapshotSource(this._runtime);

  final GridControllerRuntime _runtime;

  @override
  Stream<GraphSnapshot> get snapshots => _runtime.snapshots;

  @override
  GraphSnapshot? get current => _runtime.current;
}
