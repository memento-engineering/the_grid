import 'package:grid_controller/grid_controller.dart';

final fakeClock = DateTime.utc(2026, 6, 11, 12);

/// Builds a snapshot from beads + optional deps/ready set.
GraphSnapshot snap(
  List<Bead> beads, {
  List<BeadDependency> deps = const [],
  Set<String> ready = const {},
}) => GraphSnapshot.fromParts(
  beads: beads,
  dependencies: deps,
  readyIds: ready,
  capturedAt: fakeClock,
);

Bead bead(
  String id, {
  BeadStatus status = BeadStatus.open,
  int priority = 0,
  String title = 'title',
}) => Bead(id: id, title: title, status: status, priority: priority);

/// A [SnapshotReader] that returns whatever [builder] produces, counting reads
/// and optionally throwing [error]. Tests mutate [builder]/[error] between
/// refreshes to script the graph's evolution.
class FakeSnapshotReader implements SnapshotReader {
  FakeSnapshotReader(this.builder);

  GraphSnapshot Function() builder;
  Object? error;
  int reads = 0;

  @override
  Future<GraphSnapshot> read() async {
    reads++;
    if (error != null) throw error!;
    return builder();
  }
}

/// A [ChangeProbe] returning [hash] (mutate it to simulate a working-set
/// change), counting probes and optionally throwing [error].
class FakeChangeProbe implements ChangeProbe {
  FakeChangeProbe(this.hash);

  String hash;
  Object? error;
  int probes = 0;

  @override
  Future<String> probe() async {
    probes++;
    if (error != null) throw error!;
    return hash;
  }
}
