/// The immutable in-memory read surface for `proj_step_edges`.
library;

import 'package:grid_engine/grid_engine.dart';
import 'package:grid_trajectory/grid_trajectory.dart';
import 'package:meta/meta.dart';
import 'package:state_notifier/state_notifier.dart' show RemoveListener;

@immutable
final class MoleculeEdgeRowView implements TrajectoryStepEdgeView {
  const MoleculeEdgeRowView(this.row);

  final MoleculeEdgeRow row;

  @override
  String get sessionId => row.sessionId;
  @override
  int get round => row.round;
  @override
  String get fromPath => row.fromPath;
  @override
  String get toPath => row.toPath;
  @override
  String get kind => row.kind;
}

@immutable
final class MoleculeEdgeSnapshot implements TrajectoryStepEdgeSnapshot {
  MoleculeEdgeSnapshot({
    required this.version,
    required this.health,
    required Iterable<MoleculeEdgeRow> rows,
    this.seededAt,
  }) : rows = List<TrajectoryStepEdgeView>.unmodifiable(
         _orderedRows(rows).map(MoleculeEdgeRowView.new),
       ) {
    for (final row in this.rows) {
      (_bySession[row.sessionId] ??= <TrajectoryStepEdgeView>[]).add(row);
    }
  }

  MoleculeEdgeSnapshot.unseeded()
    : this(
        version: 0,
        health: TrajectorySnapshotHealth.refused,
        rows: const <MoleculeEdgeRow>[],
      );

  @override
  final int version;
  @override
  final TrajectorySnapshotHealth health;
  @override
  final DateTime? seededAt;
  @override
  final List<TrajectoryStepEdgeView> rows;

  final Map<String, List<TrajectoryStepEdgeView>> _bySession = {};

  @override
  Iterable<TrajectoryStepEdgeView> bySessionId(String sessionId) =>
      List<TrajectoryStepEdgeView>.unmodifiable(
        _bySession[sessionId] ?? const <TrajectoryStepEdgeView>[],
      );
}

List<MoleculeEdgeRow> _orderedRows(Iterable<MoleculeEdgeRow> rows) {
  final ordered = rows.toList(growable: false);
  for (final row in ordered) {
    if (row.kind != 'blocks' && row.kind != 'validates') {
      throw StateError('unsupported proj_step_edges kind "${row.kind}"');
    }
  }
  ordered.sort((left, right) {
    var compared = left.sessionId.compareTo(right.sessionId);
    if (compared != 0) return compared;
    compared = left.round.compareTo(right.round);
    if (compared != 0) return compared;
    compared = left.fromPath.compareTo(right.fromPath);
    if (compared != 0) return compared;
    compared = left.toPath.compareTo(right.toPath);
    if (compared != 0) return compared;
    return left.kind.compareTo(right.kind);
  });
  return ordered;
}

final class MoleculeEdgeMirror {
  final Map<MoleculeEdgeKey, MoleculeEdgeRow> _rows = {};
  final List<void Function(TrajectoryStepEdgeSnapshot)> _listeners = [];
  TrajectoryStepEdgeSnapshot _snapshot = MoleculeEdgeSnapshot.unseeded();
  var _version = 0;
  DateTime? _seededAt;
  var _health = TrajectorySnapshotHealth.refused;

  TrajectoryStepEdgeSnapshot get snapshot => _snapshot;
  bool get isSeeded => _seededAt != null;

  RemoveListener addListener(
    void Function(TrajectoryStepEdgeSnapshot) listener, {
    bool fireImmediately = true,
  }) {
    _listeners.add(listener);
    if (fireImmediately) _notify(listener, _snapshot);
    return () => _listeners.remove(listener);
  }

  void seed({
    required Iterable<MoleculeEdgeRow> rows,
    required DateTime seededAt,
    required bool stale,
  }) {
    final firstSeed = _seededAt == null;
    _replace(rows);
    _seededAt = seededAt;
    if (stale) {
      _health = TrajectorySnapshotHealth.refused;
    } else if (firstSeed && _health == TrajectorySnapshotHealth.refused) {
      _health = TrajectorySnapshotHealth.live;
    }
    _publish();
  }

  void reseed({
    required Iterable<MoleculeEdgeRow> rows,
    required DateTime seededAt,
  }) {
    _replace(rows);
    _seededAt = seededAt;
    _publish();
  }

  void applyAppended(
    TrajectoryEnvelope envelope, {
    required int seq,
    TrajectoryRecord? decoded,
  }) {
    final delta = moleculeEdgeDeltaFor(envelope, decoded: decoded);
    if (delta == null) return;
    applyMoleculeEdgeDelta(_rows, delta);
    _publish();
  }

  int evictClosedSessions(Set<String> closedSessionIds) {
    final before = _rows.length;
    _rows.removeWhere((key, _) => closedSessionIds.contains(key.sessionId));
    final dropped = before - _rows.length;
    if (dropped > 0) _publish();
    return dropped;
  }

  bool latchCompromised() {
    if (_health != TrajectorySnapshotHealth.live) return false;
    _health = TrajectorySnapshotHealth.compromised;
    _publish();
    return true;
  }

  void _replace(Iterable<MoleculeEdgeRow> rows) {
    _rows
      ..clear()
      ..addEntries(rows.map((row) => MapEntry(row.key, row)));
  }

  void _publish() {
    _snapshot = MoleculeEdgeSnapshot(
      version: ++_version,
      health: _health,
      rows: _rows.values,
      seededAt: _seededAt,
    );
    for (final listener in [..._listeners]) {
      _notify(listener, _snapshot);
    }
  }

  static void _notify(
    void Function(TrajectoryStepEdgeSnapshot) listener,
    TrajectoryStepEdgeSnapshot snapshot,
  ) {
    try {
      listener(snapshot);
    } on Object {
      // Emit-only: a subscriber cannot break the sole append writer.
    }
  }
}
