/// THE P1 MIRROR — the fold's in-memory read surface (cut-wiring §0.2, C1).
///
/// `StationJoinBridge._join` is pure and synchronous; a P1 SQL read is async.
/// The dual-read is therefore served from PRE-FETCHED state: this mirror is
/// seeded once at boot with one SELECT over `proj_session_head`, maintained
/// POST-ACK from the appender's committed envelopes, and published as
/// immutable, versioned [TrajectoryHeadSnapshot]s. No engine hot path ever
/// awaits SQL, and nothing here writes anything.
///
/// Three invariants make it trustworthy, each from a ratified constraint:
///
///   * **POST-ACK, never at enqueue** (B-B7, constraint 1's corollary): the
///     delta applies only after the append's transaction COMMITTED, at the
///     ordinal that same transaction wrote as `proj_meta.applied_seq` — so
///     `mirrorOrdinal ≡ applied_seq` is earned, not reconstructed. A dropped,
///     failed, deduped, refused, or suppressed append never reaches the
///     mirror.
///   * **A stale seed is REFUSED** (constraint 6): under wave 1 that means
///     legacy-primary for the boot — loud, never quiet, never boot-blocking.
///   * **The winner rule is retirement-legible** (§0.2): the mirror keeps the
///     PK index for the overlay and comparator, and a partitioned bead index
///     for CLASSIFICATION only. The rule itself is the engine's pure
///     `sessionHeadWinnerOf`; this file only indexes.
library;

import 'package:grid_engine/grid_engine.dart';
import 'package:grid_trajectory/grid_trajectory.dart';
import 'package:meta/meta.dart';
// The house REMOVER type only. The mirror is deliberately NOT a
// `StateNotifier`: D-H bans re-surfacing notifier state synchronously, and a
// synchronous read is exactly what this mirror is FOR (`_join` is pure and
// sync — §0.2). A pre-fetched snapshot with a change seam is a different
// animal from tree-provided configuration, and the fence is what says so.
import 'package:state_notifier/state_notifier.dart' show RemoveListener;

/// One `SessionHeadRow` read as the engine's [SessionHeadView].
///
/// A pure adapter — the whole reason `grid_engine` needs no dependency on
/// `grid_trajectory` (§0.2's B-m2 homing). It maps the two enums name for
/// name; both vocabularies are the §4 DDL's, so a divergence would be a typo,
/// not a design question.
@immutable
final class SessionHeadRowView implements SessionHeadView {
  const SessionHeadRowView(this.row);

  final SessionHeadRow row;

  @override
  String get sessionId => row.sessionId;

  @override
  String get workBeadId => row.workBeadId;

  @override
  int get round => row.round;

  @override
  bool get isOpen => row.status == SessionHeadStatus.open;

  @override
  SessionHeadOutcome? get outcome => switch (row.outcome) {
    final TerminalOutcome value => SessionHeadOutcome.fromWire(value.wire),
    _ => null,
  };

  @override
  bool get held => row.held;

  @override
  String? get heldReason => row.heldReason;

  @override
  String? get workTerminalReason => row.workTerminalReason;

  @override
  int? get pgid => row.pgid;

  @override
  int? get pid => row.pid;

  @override
  String? get attemptId => row.attemptId;

  @override
  SessionHeadProvenance? get terminalProvenance =>
      switch (row.terminalProvenance) {
        final TrajectoryProvenance value => SessionHeadProvenance.fromWire(
          value.wire,
        ),
        _ => null,
      };

  @override
  String? get unknownReason => row.unknownReason;

  @override
  DateTime get startedAt => row.startedAt;

  @override
  DateTime? get closedAt => row.closedAt;

  @override
  int get lastSeq => row.lastSeq;

  @override
  String toString() => 'SessionHeadRowView($row)';
}

/// One immutable, versioned read of the P1 mirror.
@immutable
final class SessionHeadSnapshot implements TrajectoryHeadSnapshot {
  SessionHeadSnapshot({
    required this.version,
    required this.health,
    required Map<String, SessionHeadRow> rows,
    this.seededAt,
    this.firstEpochClaimedAt,
  }) : _bySessionId = {
         for (final entry in rows.entries)
           entry.key: SessionHeadRowView(entry.value),
       } {
    for (final view in _bySessionId.values) {
      (_byWorkBead[view.workBeadId] ??= <SessionHeadView>[]).add(view);
    }
  }

  /// The empty snapshot a harness publishes before (or instead of) a seed.
  /// Health [TrajectorySnapshotHealth.refused] is the honest reading: no seed
  /// ran, so nothing here may be served.
  SessionHeadSnapshot.unseeded()
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

  final Map<String, SessionHeadView> _bySessionId;
  final Map<String, List<SessionHeadView>> _byWorkBead =
      <String, List<SessionHeadView>>{};

  @override
  SessionHeadView? bySessionId(String sessionId) => _bySessionId[sessionId];

  @override
  SessionHeadWinner byWorkBead(String workBeadId) =>
      sessionHeadWinnerOf(_byWorkBead[workBeadId] ?? const <SessionHeadView>[]);

  @override
  Iterable<SessionHeadView> get rows => _bySessionId.values;

  /// Rows the mirror holds — a memory-bound read (§0.2's 1 KB/row budget is
  /// per row; P1 is bounded by sessions).
  int get length => _bySessionId.length;

  @override
  String toString() =>
      'SessionHeadSnapshot(v$version, ${health.name}, ${_bySessionId.length} '
      'rows)';
}

/// The mutable owner of the P1 mirror — the harness holds ONE.
///
/// It publishes immutable versioned snapshots and offers a change seam
/// ([addListener]) so a fold-side fact re-joins promptly rather than waiting
/// for a poll. It is NOT a `StateNotifier`: the read here is SYNCHRONOUS by
/// design (`StationJoinBridge._join` is pure and sync), which is precisely
/// what D-H forbids for notifier state. Pre-fetched fold state is not
/// tree-provided configuration, and keeping the two shapes distinct is what
/// keeps that fence meaningful.
class SessionHeadMirror {
  final Map<String, SessionHeadRow> _rows = <String, SessionHeadRow>{};

  final List<void Function(TrajectoryHeadSnapshot)> _listeners =
      <void Function(TrajectoryHeadSnapshot)>[];

  TrajectoryHeadSnapshot _snapshot = SessionHeadSnapshot.unseeded();

  int _version = 0;
  DateTime? _seededAt;
  DateTime? _firstEpochClaimedAt;

  /// Wave-1 health, LATCHED downward for the boot: `live` may become
  /// `compromised` or `refused`, never the reverse. A reseed replaces the rows
  /// and leaves the latch alone — an append that was dropped stays dropped
  /// whatever the fold does afterwards.
  TrajectorySnapshotHealth _health = TrajectorySnapshotHealth.refused;

  /// The snapshot every reader sees — the last published value.
  TrajectoryHeadSnapshot get snapshot => _snapshot;

  /// True once a seed (or reseed) has run.
  bool get isSeeded => _seededAt != null;

  /// Subscribes to published snapshots; returns the remover (house
  /// convention). [fireImmediately] hands the current snapshot straight away.
  RemoveListener addListener(
    void Function(TrajectoryHeadSnapshot snapshot) listener, {
    bool fireImmediately = true,
  }) {
    _listeners.add(listener);
    if (fireImmediately) _notify(listener, _snapshot);
    return () => _listeners.remove(listener);
  }

  /// THE BOOT SEED (§0.2): one SELECT's rows, plus the era boundary the miss
  /// classifier splits on.
  ///
  /// [stale] is the lag rule's verdict, computed by the caller from the
  /// `'fold'` `proj_meta` row: a stale fold means health `refused` — under
  /// wave 1, legacy-primary for the boot, with the incumbent still a full
  /// oracle. A seed never CLEARS an existing latch.
  void seed({
    required Iterable<SessionHeadRow> rows,
    required DateTime seededAt,
    required bool stale,
    DateTime? firstEpochClaimedAt,
  }) {
    // Health only ever moves DOWN after the first seed. The pre-seed value
    // `refused` means "no seed ran", so the FIRST clean seed lifts it to
    // `live`; a stale one keeps `refused` for the boot, and an already-latched
    // `compromised` survives — a drop is not undone by a fresh read.
    final firstSeed = _seededAt == null;
    _rows
      ..clear()
      ..addEntries([for (final row in rows) MapEntry(row.sessionId, row)]);
    _seededAt = seededAt;
    _firstEpochClaimedAt = firstEpochClaimedAt ?? _firstEpochClaimedAt;
    if (stale) {
      _health = TrajectorySnapshotHealth.refused;
    } else if (firstSeed && _health == TrajectorySnapshotHealth.refused) {
      _health = TrajectorySnapshotHealth.live;
    }
    _publish();
  }

  /// THE FOLD-GENERATION RESEED (§0.2, r4 — J7-B2): the whole row set is
  /// replaced because a `(projection, fold_version, rebuilt_at)` triple moved
  /// under us. Health is untouched — a reseed is a re-read, not absolution.
  void reseed({
    required Iterable<SessionHeadRow> rows,
    required DateTime seededAt,
  }) {
    _rows
      ..clear()
      ..addEntries([for (final row in rows) MapEntry(row.sessionId, row)]);
    _seededAt = seededAt;
    _publish();
  }

  /// THE POST-ACK APPLY: the same pure delta the SQL fold just applied inside
  /// the committed transaction, at the same ordinal.
  ///
  /// [envelope] is the COMMITTED envelope handed back on `Appended` — which is
  /// the rebuilt one when the appender's resolving pre-read converted a
  /// terminal to settling form, so the mirror folds exactly what the log
  /// holds. [decoded] short-circuits the codec only when it provably describes
  /// that envelope.
  void applyAppended(
    TrajectoryEnvelope envelope, {
    required int seq,
    TrajectoryRecord? decoded,
  }) {
    final delta = sessionHeadDeltaFor(envelope, decoded: decoded);
    if (delta == null) return;
    applySessionHeadDelta(_rows, delta, lastSeq: seq);
    _publish();
  }

  /// The COMPROMISED latch (§0.2's wave-1 health): any append drop, failure,
  /// or SUPPRESSION since boot, or the harness leaving `live` mode. Under
  /// wave 1 this disengages the overlay for the boot — decisions ride pure
  /// legacy, which is still fully written. Returns true on the transition, so
  /// the caller flares exactly once.
  bool latchCompromised() {
    if (_health != TrajectorySnapshotHealth.live) return false;
    _health = TrajectorySnapshotHealth.compromised;
    _publish();
    return true;
  }

  /// The era boundary, learned separately from the row seed (the first epoch
  /// this station ever claimed).
  void noteFirstEpochClaimedAt(DateTime? instant) {
    if (instant == null || _firstEpochClaimedAt == instant) return;
    _firstEpochClaimedAt = instant;
    _publish();
  }

  void _publish() {
    _version += 1;
    _snapshot = SessionHeadSnapshot(
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
    void Function(TrajectoryHeadSnapshot) listener,
    TrajectoryHeadSnapshot snapshot,
  ) {
    try {
      listener(snapshot);
    } on Object {
      // Emit-only, the flare convention: a throwing subscriber never breaks
      // the writer loop that published.
    }
  }
}
