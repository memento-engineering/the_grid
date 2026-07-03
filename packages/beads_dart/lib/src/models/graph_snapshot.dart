import 'bead.dart';
import 'bead_dependency.dart';

/// An immutable point-in-time view of the work graph: every bead by id, every
/// dependency edge, and the ready set, with the wall-clock capture time.
///
/// Deliberately *not* freezed: snapshots can hold tens of thousands of beads,
/// so deep structural equality on the whole snapshot would be wasteful. Change
/// detection is the job of `diffSnapshots` (per-bead comparison), and emission
/// is gated on a non-empty diff — never on snapshot equality.
class GraphSnapshot {
  GraphSnapshot({
    required Map<String, Bead> beadsById,
    required List<BeadDependency> dependencies,
    required Set<String> readyIds,
    required this.capturedAt,
  }) : beadsById = Map.unmodifiable(beadsById),
       dependencies = List.unmodifiable(dependencies),
       readyIds = Set.unmodifiable(readyIds);

  /// Builds a snapshot from a flat bead list, indexing by id.
  factory GraphSnapshot.fromParts({
    required Iterable<Bead> beads,
    required Iterable<BeadDependency> dependencies,
    required Iterable<String> readyIds,
    required DateTime capturedAt,
  }) {
    return GraphSnapshot(
      beadsById: {for (final bead in beads) bead.id: bead},
      dependencies: dependencies.toList(growable: false),
      readyIds: readyIds.toSet(),
      capturedAt: capturedAt,
    );
  }

  final Map<String, Bead> beadsById;
  final List<BeadDependency> dependencies;
  final Set<String> readyIds;
  final DateTime capturedAt;

  Iterable<Bead> get beads => beadsById.values;
  int get beadCount => beadsById.length;
  int get readyCount => readyIds.length;

  Bead? bead(String id) => beadsById[id];
  bool get isEmpty => beadsById.isEmpty;
}
