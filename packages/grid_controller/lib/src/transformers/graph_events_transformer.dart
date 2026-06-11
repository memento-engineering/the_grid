import '../diff/diff_snapshots.dart';
import '../diff/graph_event.dart';
import '../models/graph_snapshot.dart';

/// Turns a sequence of snapshots into a sequence of typed change events by
/// diffing each new snapshot against the previously ingested one.
///
/// Pure and stateful only in the most local sense — it remembers the last
/// snapshot. The first ingest (no previous) yields a single
/// [SnapshotInitialized]; thereafter [ingest] returns exactly the events
/// `diffSnapshots` computes. Holds no IO and is fully unit-testable.
class GraphEventsTransformer {
  GraphSnapshot? _previous;

  /// The most recently ingested snapshot, or null before the first ingest.
  GraphSnapshot? get previous => _previous;

  /// Diffs [next] against the previous snapshot, advances the cursor, and
  /// returns the events. An empty result means nothing changed.
  List<GraphEvent> ingest(GraphSnapshot next) {
    final events = diffSnapshots(_previous, next);
    _previous = next;
    return events;
  }

  /// Resets the cursor so the next ingest re-emits a baseline.
  void reset() => _previous = null;
}
