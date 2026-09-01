/// THE P2 MIRROR — the step fold's in-memory read surface (cut-wiring C4).
///
/// `SessionHeadMirror`'s twin, one ladder down, with the SAME three
/// invariants and for the same reasons: seeded once at boot with one SELECT
/// over `proj_step_cursor`, maintained POST-ACK from the appender's committed
/// envelopes, published as immutable versioned [TrajectoryStepSnapshot]s. No
/// engine hot path ever awaits SQL and nothing here writes anything.
///
/// Two things are P2's own:
///
///   * **`byP2SessionId`** (r7 — V1-M5) — the step axis's identity index,
///     distinctly named because the two mirrors are separate objects and the
///     OVERLAY IDENTITY RULE has to be readable at the call site: a
///     `bySessionId` on either would invite the assumption that they are the
///     same lookup. P2 is keyed by the TWO-LADDER key, so one session holds
///     MANY rows and this index returns a list — the per-`step_path` collapse
///     to the newest `(round, step_round)` is the engine's pure
///     `collapseStepCursors`, not something this file decides.
///   * **EVICTION** (§0.2's memory bound) — rows for sessions CLOSED in P1
///     evict. P2 is bounded by live steps rather than by sessions, so unlike
///     P1 it needs a floor: the SQL fold keeps the history and `traj replay`
///     rebuilds it, so nothing durable is lost by forgetting a closed
///     session's ladder.
library;

import 'package:grid_engine/grid_engine.dart';
import 'package:grid_trajectory/grid_trajectory.dart';
import 'package:meta/meta.dart';
// The house REMOVER type only — the mirror is deliberately NOT a
// `StateNotifier`, for the reason `session_head_mirror.dart` states at length.
import 'package:state_notifier/state_notifier.dart' show RemoveListener;

/// One `StepCursorRow` read as the engine's [StepCursorView].
///
/// A pure adapter — the whole reason `grid_engine` needs no dependency on
/// `grid_trajectory`. The `state` column stays a WIRE STRING here: the engine
/// maps it to its own `StepState` (`stepStateFromWire`), so an unknown word is
/// a miss rather than a default, and the two enums never have to be declared
/// equal by an adapter that could get it wrong silently.
@immutable
final class StepCursorRowView implements StepCursorView {
  const StepCursorRowView(this.row);

  final StepCursorRow row;

  @override
  String get sessionId => row.sessionId;

  @override
  int get round => row.round;

  @override
  String get stepPath => row.stepPath;

  @override
  int get stepRound => row.stepRound;

  @override
  String get stepState => row.state;

  @override
  int get incarnation => row.incarnation;

  @override
  String? get attemptId => row.attemptId;

  @override
  int? get supersededByStepRound => row.supersededByStepRound;

  @override
  DateTime? get cooldownUntil => row.cooldownUntil;

  @override
  int? get restartBudget => row.restartBudget;

  @override
  DateTime? get startedAt => row.startedAt;

  @override
  DateTime? get readyAt => row.readyAt;

  @override
  DateTime? get completedAt => row.completedAt;

  @override
  String? get failureClass => row.failureClass;

  @override
  int get lastSeq => row.lastSeq;

  @override
  String toString() => 'StepCursorRowView($row)';
}

/// One immutable, versioned read of the P2 mirror.
@immutable
final class StepCursorSnapshot implements TrajectoryStepSnapshot {
  StepCursorSnapshot({
    required this.version,
    required this.health,
    required Map<StepCursorKey, StepCursorRow> rows,
    this.seededAt,
    this.firstEpochClaimedAt,
  }) {
    for (final row in rows.values) {
      (_bySessionId[row.sessionId] ??= <StepCursorView>[]).add(
        StepCursorRowView(row),
      );
    }
  }

  /// The empty snapshot a harness publishes before (or instead of) a seed.
  /// Health `refused` is the honest reading: no seed ran, so nothing here may
  /// be served.
  StepCursorSnapshot.unseeded()
    : this(
        version: 0,
        health: TrajectorySnapshotHealth.refused,
        rows: const {},
      );

  @override
  final int version;

  @override
  final TrajectorySnapshotHealth health;

  @override
  final DateTime? seededAt;

  @override
  final DateTime? firstEpochClaimedAt;

  final Map<String, List<StepCursorView>> _bySessionId =
      <String, List<StepCursorView>>{};

  @override
  Iterable<StepCursorView> byP2SessionId(String sessionId) =>
      _bySessionId[sessionId] ?? const <StepCursorView>[];

  /// Rows the mirror holds — the memory-bound read the eviction rule exists
  /// for.
  int get length => _bySessionId.values.fold(0, (sum, l) => sum + l.length);

  /// Sessions with at least one row.
  int get sessions => _bySessionId.length;

  @override
  String toString() =>
      'StepCursorSnapshot(v$version, ${health.name}, $length rows across '
      '$sessions sessions)';
}

/// The mutable owner of the P2 mirror — the harness holds ONE.
class StepCursorMirror {
  final Map<StepCursorKey, StepCursorRow> _rows =
      <StepCursorKey, StepCursorRow>{};

  final List<void Function(TrajectoryStepSnapshot)> _listeners =
      <void Function(TrajectoryStepSnapshot)>[];

  TrajectoryStepSnapshot _snapshot = StepCursorSnapshot.unseeded();

  int _version = 0;
  DateTime? _seededAt;
  DateTime? _firstEpochClaimedAt;

  /// Wave-1 health, LATCHED downward for the boot — the same rule P1 has: a
  /// reseed replaces the rows and leaves the latch alone, because an append
  /// that was dropped stays dropped whatever the fold does afterwards.
  TrajectorySnapshotHealth _health = TrajectorySnapshotHealth.refused;

  TrajectoryStepSnapshot get snapshot => _snapshot;

  bool get isSeeded => _seededAt != null;

  /// Subscribes to published snapshots; returns the remover (house
  /// convention).
  RemoveListener addListener(
    void Function(TrajectoryStepSnapshot snapshot) listener, {
    bool fireImmediately = true,
  }) {
    _listeners.add(listener);
    if (fireImmediately) _notify(listener, _snapshot);
    return () => _listeners.remove(listener);
  }

  /// THE BOOT SEED — one SELECT's rows plus the era boundary.
  ///
  /// [stale] is the lag rule's verdict, computed by the caller from the shared
  /// `'fold'` `proj_meta` row (never P2's own `'step_cursor'` row, whose
  /// `applied_seq` freezes at replay time and is not a lag signal). A seed
  /// never CLEARS an existing latch.
  void seed({
    required Iterable<StepCursorRow> rows,
    required DateTime seededAt,
    required bool stale,
    DateTime? firstEpochClaimedAt,
  }) {
    final firstSeed = _seededAt == null;
    _replace(rows);
    _seededAt = seededAt;
    _firstEpochClaimedAt = firstEpochClaimedAt ?? _firstEpochClaimedAt;
    if (stale) {
      _health = TrajectorySnapshotHealth.refused;
    } else if (firstSeed && _health == TrajectorySnapshotHealth.refused) {
      _health = TrajectorySnapshotHealth.live;
    }
    _publish();
  }

  /// THE FOLD-GENERATION RESEED — the whole row set is replaced because a
  /// `(projection, fold_version, rebuilt_at)` triple moved under us. Health is
  /// untouched: a reseed is a re-read, not absolution.
  void reseed({
    required Iterable<StepCursorRow> rows,
    required DateTime seededAt,
  }) {
    _replace(rows);
    _seededAt = seededAt;
    _publish();
  }

  /// THE POST-ACK APPLY: the same pure delta the SQL fold just applied inside
  /// the committed transaction, at the same ordinal.
  ///
  /// A `step.superseded` record whose predecessor row is not in the mirror
  /// matches nothing and changes nothing — exactly what its SQL twin does with
  /// zero matched rows, which is what keeps the two application modes honest
  /// after an eviction.
  void applyAppended(
    TrajectoryEnvelope envelope, {
    required int seq,
    TrajectoryRecord? decoded,
  }) {
    final delta = stepCursorDeltaFor(envelope, decoded: decoded);
    if (delta == null) return;
    applyStepCursorDelta(_rows, delta, lastSeq: seq);
    _publish();
  }

  /// EVICTION (§0.2's memory bound): drop every row belonging to a session in
  /// [closedSessionIds].
  ///
  /// Called with the sessions P1 reports CLOSED — P1 is the terminality
  /// carrier and P2 has no status column of its own, so this is the one
  /// direction the eviction can be driven from. Returns the number of rows
  /// dropped, and publishes only when something actually went.
  int evictClosedSessions(Set<String> closedSessionIds) {
    if (closedSessionIds.isEmpty) return 0;
    final before = _rows.length;
    _rows.removeWhere((key, _) => closedSessionIds.contains(key.sessionId));
    final dropped = before - _rows.length;
    if (dropped > 0) _publish();
    return dropped;
  }

  /// The COMPROMISED latch — returns true on the transition, so the caller
  /// flares exactly once.
  bool latchCompromised() {
    if (_health != TrajectorySnapshotHealth.live) return false;
    _health = TrajectorySnapshotHealth.compromised;
    _publish();
    return true;
  }

  /// The era boundary, learned separately from the row seed.
  void noteFirstEpochClaimedAt(DateTime? instant) {
    if (instant == null || _firstEpochClaimedAt == instant) return;
    _firstEpochClaimedAt = instant;
    _publish();
  }

  void _replace(Iterable<StepCursorRow> rows) {
    _rows
      ..clear()
      ..addEntries([for (final row in rows) MapEntry(row.key, row)]);
  }

  void _publish() {
    _version += 1;
    _snapshot = StepCursorSnapshot(
      version: _version,
      health: _health,
      rows: _rows,
      seededAt: _seededAt,
      firstEpochClaimedAt: _firstEpochClaimedAt,
    );
    // Iterate a COPY: a listener that removes itself mid-notify must not
    // mutate the list under the loop.
    for (final listener in [..._listeners]) {
      _notify(listener, _snapshot);
    }
  }

  static void _notify(
    void Function(TrajectoryStepSnapshot) listener,
    TrajectoryStepSnapshot snapshot,
  ) {
    try {
      listener(snapshot);
    } on Object {
      // Emit-only, the flare convention: a throwing subscriber never breaks
      // the writer loop that published.
    }
  }
}
