import 'dart:async';

import 'package:grid_diagnostics_contract/grid_diagnostics_contract.dart';

/// Observable diagnostics snapshots consumed by cockpit projections.
abstract interface class TreeSource {
  /// The current snapshot, or null before a live source receives one.
  TreeSnapshot? get latest;

  /// Broadcast observations after [latest].
  Stream<TreeSnapshot> get snapshots;

  /// Releases source-owned resources.
  Future<void> dispose();
}

/// Reporter/client seam injected into [LiveTreeSource].
abstract interface class TreeWireSource {
  /// The most recently received snapshot, if any.
  TreeSnapshot? get latest;

  /// Broadcast snapshots received from the wire.
  Stream<TreeSnapshot> get snapshots;
}

/// Transport-neutral adapter over an injected wire source.
final class LiveTreeSource implements TreeSource {
  /// Creates an adapter over [wire].
  const LiveTreeSource(this._wire);

  final TreeWireSource _wire;

  @override
  TreeSnapshot? get latest => _wire.latest;

  @override
  Stream<TreeSnapshot> get snapshots => _wire.snapshots;

  @override
  Future<void> dispose() async {}
}

/// Deterministic recorded source for tests and demonstrations.
final class ReplayTreeSource implements TreeSource {
  /// Creates a replay source positioned at the first recorded snapshot.
  ReplayTreeSource(List<TreeSnapshot> recording)
    : _recording = List.unmodifiable(recording) {
    if (_recording.isEmpty) {
      throw ArgumentError.value(recording, 'recording', 'must not be empty');
    }
  }

  final List<TreeSnapshot> _recording;
  final StreamController<TreeSnapshot> _controller =
      StreamController<TreeSnapshot>.broadcast(sync: true);
  int _index = 0;

  @override
  TreeSnapshot get latest => _recording[_index];

  @override
  Stream<TreeSnapshot> get snapshots => _controller.stream;

  /// The current position in the recording.
  int get index => _index;

  /// Whether another recorded snapshot follows [latest].
  bool get canAdvance => _index < _recording.length - 1;

  /// Moves to [index] and synchronously emits that snapshot.
  void seek(int index) {
    RangeError.checkValidIndex(index, _recording, 'index');
    _index = index;
    _controller.add(latest);
  }

  /// Advances and emits the next snapshot, or returns false at the end.
  bool advance() {
    if (!canAdvance) return false;
    seek(_index + 1);
    return true;
  }

  @override
  Future<void> dispose() => _controller.close();
}
