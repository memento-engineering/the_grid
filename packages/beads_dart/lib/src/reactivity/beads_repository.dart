import 'dart:async';
import 'dart:collection';

import '../diff/graph_event.dart';
import '../models/bead.dart';
import '../models/graph_snapshot.dart';
import '../transformers/graph_events_transformer.dart';
import 'snapshot_reader.dart';

/// A failed [BeadsRepository.refresh], surfaced on [BeadsRepository.errors]
/// so a bad read never crashes the sync loop but stays observable.
typedef RefreshError = ({Object error, StackTrace stackTrace});

/// Owns the [GraphSnapshot] cache and emits derived state (predictable-flutter
/// Repository tier: owns exactly one source — the [SnapshotReader] — and emits).
///
/// [refresh] is the work the [GraphSyncInteractor] schedules: read a fresh
/// snapshot, diff it against the previous one, and publish the snapshot plus
/// the typed events. It never throws — a failed read is published on [errors]
/// instead, leaving the loop alive.
class BeadsRepository {
  BeadsRepository(this._reader, {int eventBufferSize = 256})
    : _eventBufferSize = eventBufferSize;

  final SnapshotReader _reader;
  final int _eventBufferSize;
  final _transformer = GraphEventsTransformer();

  final _snapshots = StreamController<GraphSnapshot>.broadcast();
  final _events = StreamController<GraphEvent>.broadcast();
  final _errors = StreamController<RefreshError>.broadcast();
  final Queue<GraphEvent> _recent = Queue<GraphEvent>();

  GraphSnapshot? _current;
  bool _closed = false;

  /// Snapshots, emitted once per refresh that produced a change (or the
  /// baseline). Broadcast.
  Stream<GraphSnapshot> get snapshots => _snapshots.stream;

  /// Individual typed events, flattened across refreshes. Broadcast.
  Stream<GraphEvent> get events => _events.stream;

  /// Failed refreshes. Broadcast.
  Stream<RefreshError> get errors => _errors.stream;

  /// The most recent successful snapshot — the synchronous seed value for a
  /// late subscriber (D-A7); null before the baseline refresh completes.
  GraphSnapshot? get current => _current;

  /// The most recent events, newest last, capped at the buffer size — backs the
  /// exploration `events` tool.
  List<GraphEvent> get recentEvents => List.unmodifiable(_recent);

  /// Beads currently in the ready set, by snapshot order of [GraphSnapshot.readyIds].
  List<Bead> get readyBeads {
    final snapshot = _current;
    if (snapshot == null) return const [];
    return [
      for (final id in snapshot.readyIds)
        if (snapshot.bead(id) case final bead?) bead,
    ];
  }

  Bead? bead(String id) => _current?.bead(id);

  /// Reads, diffs, and publishes. Single-flight is the interactor's guarantee;
  /// this method assumes it is not called concurrently with itself.
  Future<void> refresh() async {
    if (_closed) return;
    try {
      final snapshot = await _reader.read();
      if (_closed) return; // disposed during the read await
      final events = _transformer.ingest(snapshot);
      _current = snapshot;
      // Emit only when something changed (or it is the baseline). An empty
      // diff on a non-baseline refresh publishes nothing.
      if (events.isNotEmpty) {
        _snapshots.add(snapshot);
        for (final event in events) {
          _recent.addLast(event);
          while (_recent.length > _eventBufferSize) {
            _recent.removeFirst();
          }
          _events.add(event);
        }
      }
    } on Object catch (error, stackTrace) {
      if (_closed) return; // disposed during the read await
      _errors.add((error: error, stackTrace: stackTrace));
    }
  }

  Future<void> dispose() async {
    _closed = true;
    await _snapshots.close();
    await _events.close();
    await _errors.close();
  }
}
