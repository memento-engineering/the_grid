import 'dart:async';
import 'dart:collection';

import 'package:riverpod/riverpod.dart';

import '../diff/graph_event.dart';
import '../models/bead.dart';
import '../models/graph_snapshot.dart';
import '../transformers/graph_events_transformer.dart';
import 'snapshot_reader.dart';

/// Owns the [GraphSnapshot] cache and emits derived state (predictable-flutter
/// Repository tier: owns exactly one source — the [SnapshotReader] — and emits).
///
/// [refresh] is the work the [GraphSyncInteractor] schedules: read a fresh
/// snapshot, diff it against the previous one, publish the snapshot, the typed
/// events, and the new [AsyncValue] state. It never throws — a failed read
/// becomes an [AsyncError] state and a logged error, leaving the loop alive.
class BeadsRepository {
  BeadsRepository(this._reader, {int eventBufferSize = 256})
    : _eventBufferSize = eventBufferSize;

  final SnapshotReader _reader;
  final int _eventBufferSize;
  final _transformer = GraphEventsTransformer();

  final _snapshots = StreamController<GraphSnapshot>.broadcast();
  final _events = StreamController<GraphEvent>.broadcast();
  final _states = StreamController<AsyncValue<GraphSnapshot>>.broadcast();
  final Queue<GraphEvent> _recent = Queue<GraphEvent>();

  GraphSnapshot? _current;
  AsyncValue<GraphSnapshot> _state = const AsyncLoading();
  bool _closed = false;

  /// Snapshots, emitted once per refresh that produced a change (or the
  /// baseline). Broadcast.
  Stream<GraphSnapshot> get snapshots => _snapshots.stream;

  /// Individual typed events, flattened across refreshes. Broadcast.
  Stream<GraphEvent> get events => _events.stream;

  /// `AsyncValue` state transitions (loading → data/error). Broadcast.
  Stream<AsyncValue<GraphSnapshot>> get states => _states.stream;

  GraphSnapshot? get current => _current;
  AsyncValue<GraphSnapshot> get state => _state;

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
      _state = AsyncData(snapshot);
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
      _states.add(_state);
    } on Object catch (error, stackTrace) {
      _state = AsyncError(error, stackTrace);
      _states.add(_state);
    }
  }

  Future<void> dispose() async {
    _closed = true;
    await _snapshots.close();
    await _events.close();
    await _states.close();
  }
}
