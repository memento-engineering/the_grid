import 'dart:async';

import 'package:riverpod/riverpod.dart';

import '../diff/graph_event.dart';
import '../interactors/graph_sync_interactor.dart';
import '../models/bead.dart';
import '../models/graph_snapshot.dart';
import 'beads_repository.dart';
import 'dirty_signal.dart';
import 'snapshot_reader.dart';

/// The running reactive controller: composes a [BeadsRepository] over a
/// [SnapshotReader], merges any number of [DirtySignalSource]s into the
/// [GraphSyncInteractor], and exposes the observable surface (snapshots,
/// events, state, ready set, stats) plus a manual `requery`.
///
/// Construction is dependency-injected so the integration layer wires the
/// concrete SQL/CLI readers and dirty sources, while tests inject fakes. Call
/// [start] to take the baseline snapshot and begin reacting; [dispose] tears
/// everything down.
class GridControllerRuntime {
  GridControllerRuntime({
    required SnapshotReader reader,
    required List<DirtySignalSource> dirtySources,
    Duration quietPeriod = const Duration(milliseconds: 150),
    int eventBufferSize = 256,
  }) : _dirtySources = dirtySources,
       repository = BeadsRepository(reader, eventBufferSize: eventBufferSize) {
    _merged = StreamController<DirtySignal>.broadcast();
    for (final source in dirtySources) {
      _subs.add(source.signals.listen(_merged.add, onError: (_) {}));
    }
    interactor = GraphSyncInteractor(
      signals: _merged.stream,
      onRefresh: repository.refresh,
      quietPeriod: quietPeriod,
    );
  }

  final List<DirtySignalSource> _dirtySources;
  final BeadsRepository repository;
  late final GraphSyncInteractor interactor;
  late final StreamController<DirtySignal> _merged;
  final List<StreamSubscription<DirtySignal>> _subs = [];
  bool _started = false;

  /// Subscribes the sync loop and takes the baseline snapshot.
  Future<void> start() async {
    if (_started) return;
    _started = true;
    await interactor.start();
  }

  // ----- observable surface -----
  Stream<GraphSnapshot> get snapshots => repository.snapshots;
  Stream<GraphEvent> get events => repository.events;
  Stream<AsyncValue<GraphSnapshot>> get states => repository.states;
  GraphSnapshot? get current => repository.current;
  AsyncValue<GraphSnapshot> get state => repository.state;
  List<Bead> get readyBeads => repository.readyBeads;
  List<GraphEvent> get recentEvents => repository.recentEvents;
  Bead? bead(String id) => repository.bead(id);
  GraphSyncStats get stats => interactor.stats;

  /// Forces an immediate re-query, completing when it finishes.
  Future<void> requery() => interactor.refreshNow();

  Future<void> dispose() async {
    for (final sub in _subs) {
      await sub.cancel();
    }
    await interactor.dispose();
    await _merged.close();
    for (final source in _dirtySources) {
      await source.dispose();
    }
    await repository.dispose();
  }
}
