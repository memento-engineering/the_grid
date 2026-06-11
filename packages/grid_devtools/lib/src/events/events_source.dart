import 'dart:async';

import 'package:flutter/foundation.dart';

import '../protocol/grid_exploration_client.dart';

/// Append-only feed of [GridEventRecord]s for the events timeline panel.
///
/// Seeds from the `ext.exploration.grid.events` tool (the ring-buffer
/// snapshot of recent events) then grows live off the
/// `grid.controller.event` postEvent stream. Keeps at most [maxRecords]
/// rows, newest last, so a long-running session does not grow unbounded.
///
/// Pure over [GridExplorationClient] — a fake client drives it in tests
/// with no VM service. Always reassigns [records] to a fresh unmodifiable
/// list on change so `ValueListenableBuilder` sees a new value.
class GridEventsSource {
  GridEventsSource(this._client, {this.maxRecords = 200});

  final GridExplorationClient _client;
  final int maxRecords;

  final ValueNotifier<List<GridEventRecord>> _records =
      ValueNotifier<List<GridEventRecord>>(const []);

  StreamSubscription<GridEventRecord>? _sub;
  bool _closed = false;
  bool _started = false;

  /// The records observed so far, newest last.
  ValueListenable<List<GridEventRecord>> get records => _records;

  /// Seeds the backlog via the `events` tool, then subscribes to the live
  /// stream. Idempotent — a second call is a no-op. Tool failures are
  /// swallowed (the live stream still attaches); a caller wanting the seed
  /// error should call [GridExplorationClient.fetchEvents] directly.
  Future<void> start({int? seedLimit = 64}) async {
    if (_started || _closed) return;
    _started = true;
    try {
      final page = await _client.fetchEvents(limit: seedLimit);
      if (!_closed) _append(page.events);
    } on Object {
      // Seed is best-effort; the live subscription below is the substance.
    }
    if (_closed) return;
    _sub = _client.eventStream.listen((record) {
      if (_closed) return;
      _append(<GridEventRecord>[record]);
    });
  }

  void _append(List<GridEventRecord> incoming) {
    if (incoming.isEmpty) return;
    final merged = <GridEventRecord>[..._records.value, ...incoming];
    final trimmed = merged.length > maxRecords
        ? merged.sublist(merged.length - maxRecords)
        : merged;
    _records.value = List<GridEventRecord>.unmodifiable(trimmed);
  }

  /// Releases the subscription and notifier. Idempotent.
  Future<void> close() async {
    if (_closed) return;
    _closed = true;
    await _sub?.cancel();
    _sub = null;
    _records.dispose();
  }
}
