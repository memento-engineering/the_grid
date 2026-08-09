import 'package:grid_engine/grid_engine.dart' show JoinedSnapshot, WedgeState;

/// The narrow status view a station delegate vends — the VALUES the command
/// shell's banner, `/status` view, and dev-mode seat read. A view over the
/// boot-assembled work machinery; never the runtime object wholesale.
abstract interface class StationView {
  /// The owned state partition sessions are minted into.
  String get stateSubstation;

  /// The controllers' read-path provenance (banner material).
  String get readPathName;

  /// The producer-side latest join (status counts read THIS).
  JoinedSnapshot get latest;

  /// The station's wedge signal — one truth for "is the grid stuck?".
  WedgeState get wedge;

  /// The JSON-shaped sync-loop observability payload for `/status` (tg-zd4v):
  /// per-store `GraphSyncStats` under `stats`, the federation's per-member
  /// freshness vector under `freshness`. Empty when the assembly exposes none.
  Map<String, Object?> syncStatus();
}
