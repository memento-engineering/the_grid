/// The typed, pre-fetched P6 process/worktree identity mirror.
library;

import 'package:grid_engine/grid_engine.dart';
import 'package:grid_trajectory/grid_trajectory.dart';
import 'package:meta/meta.dart';
import 'package:state_notifier/state_notifier.dart' show RemoveListener;

/// Non-live P6 rows older than this fold-sequence horizon are evicted.
const int kProcessIdentityRetentionHorizon = 50000;

@immutable
final class ProcessIdentityRowView implements ProcessIdentityView {
  const ProcessIdentityRowView(this.row);

  final ProcessIdentityRow row;

  @override
  String get attemptId => row.attemptId;
  @override
  String get sessionId => row.sessionId;
  @override
  int get round => row.round;
  @override
  String get stepPath => row.stepPath;
  @override
  int get stepRound => row.stepRound;
  @override
  int get incarnation => row.incarnation;
  @override
  int? get pid => row.pid;
  @override
  int? get pgid => row.pgid;
  @override
  String? get leaseState => row.leaseState;
  @override
  String? get worktree => row.worktree;
  @override
  String? get branch => row.branch;
  @override
  String? get baseSha => row.baseSha;
  @override
  bool? get adoptedExisting => row.adoptedExisting;
  @override
  String? get worktreeState => row.worktreeState;
  @override
  String? get predecessorAttemptId => row.predecessorAttemptId;
  @override
  int get lastSeq => row.lastSeq;
}

@immutable
final class ProcessIdentitySnapshot
    implements TrajectoryProcessIdentitySnapshot {
  ProcessIdentitySnapshot({
    required this.version,
    required this.health,
    required Iterable<ProcessIdentityRow> rows,
    this.seededAt,
    this.lastTickAt,
  }) : rows = List<ProcessIdentityView>.unmodifiable(
         rows.map(ProcessIdentityRowView.new),
       ) {
    for (final row in this.rows) {
      (_bySession[row.sessionId] ??= <ProcessIdentityView>[]).add(row);
    }
  }

  ProcessIdentitySnapshot.unseeded()
    : this(
        version: 0,
        health: TrajectorySnapshotHealth.refused,
        rows: const <ProcessIdentityRow>[],
      );

  @override
  final int version;
  @override
  final TrajectorySnapshotHealth health;
  @override
  final DateTime? seededAt;
  @override
  final DateTime? lastTickAt;
  @override
  final List<ProcessIdentityView> rows;

  final Map<String, List<ProcessIdentityView>> _bySession = {};

  @override
  Iterable<ProcessIdentityView> bySessionId(String sessionId) =>
      List<ProcessIdentityView>.unmodifiable(
        _bySession[sessionId] ?? const <ProcessIdentityView>[],
      );
}

/// Listener-owned mutable P6 mirror; the published value is always immutable.
final class ProcessIdentityMirror {
  final Map<String, ProcessIdentityRow> _rows = {};
  final List<void Function(TrajectoryProcessIdentitySnapshot)> _listeners = [];
  TrajectoryProcessIdentitySnapshot _snapshot =
      ProcessIdentitySnapshot.unseeded();
  int _version = 0;
  DateTime? _seededAt;
  DateTime? _lastTickAt;
  var _health = TrajectorySnapshotHealth.refused;

  TrajectoryProcessIdentitySnapshot get snapshot => _snapshot;
  bool get isSeeded => _seededAt != null;

  RemoveListener addListener(
    void Function(TrajectoryProcessIdentitySnapshot) listener, {
    bool fireImmediately = true,
  }) {
    _listeners.add(listener);
    if (fireImmediately) _notify(listener, _snapshot);
    return () => _listeners.remove(listener);
  }

  void seed({
    required Iterable<ProcessIdentityRow> rows,
    required DateTime seededAt,
    required bool stale,
    required int foldHeadSeq,
  }) {
    final firstSeed = _seededAt == null;
    _replace(rows);
    _seededAt = seededAt;
    if (stale) {
      _health = TrajectorySnapshotHealth.refused;
    } else if (firstSeed && _health == TrajectorySnapshotHealth.refused) {
      _health = TrajectorySnapshotHealth.live;
    }
    _evict(foldHeadSeq);
    _publish();
  }

  void reseed({
    required Iterable<ProcessIdentityRow> rows,
    required DateTime seededAt,
    required int foldHeadSeq,
  }) {
    _replace(rows);
    _seededAt = seededAt;
    _evict(foldHeadSeq);
    _publish();
  }

  void applyAppended(
    TrajectoryEnvelope envelope, {
    required int seq,
    TrajectoryRecord? decoded,
  }) {
    final delta = processIdentityDeltaFor(envelope, decoded: decoded);
    if (delta != null) applyProcessIdentityDelta(_rows, delta, lastSeq: seq);
    final evicted = _evict(seq);
    if (delta != null || evicted > 0) _publish();
  }

  int evictAt(int foldHeadSeq) {
    final dropped = _evict(foldHeadSeq);
    if (dropped > 0) _publish();
    return dropped;
  }

  void noteTickAt(DateTime instant) {
    _lastTickAt = instant;
    _publish();
  }

  bool latchCompromised() {
    if (_health != TrajectorySnapshotHealth.live) return false;
    _health = TrajectorySnapshotHealth.compromised;
    _publish();
    return true;
  }

  int _evict(int foldHeadSeq) {
    final before = _rows.length;
    _rows.removeWhere(
      (_, row) =>
          foldHeadSeq - row.lastSeq > kProcessIdentityRetentionHorizon &&
          row.worktreeState != 'live',
    );
    return before - _rows.length;
  }

  void _replace(Iterable<ProcessIdentityRow> rows) {
    _rows
      ..clear()
      ..addEntries(rows.map((row) => MapEntry(row.attemptId, row)));
  }

  void _publish() {
    _snapshot = ProcessIdentitySnapshot(
      version: ++_version,
      health: _health,
      rows: _rows.values,
      seededAt: _seededAt,
      lastTickAt: _lastTickAt,
    );
    for (final listener in [..._listeners]) {
      _notify(listener, _snapshot);
    }
  }

  static void _notify(
    void Function(TrajectoryProcessIdentitySnapshot) listener,
    TrajectoryProcessIdentitySnapshot snapshot,
  ) {
    try {
      listener(snapshot);
    } on Object {
      // Emit-only: a subscriber cannot break the sole append writer.
    }
  }
}
