/// Fakes for the tick: a hand-fired timer, a fake clock, a scripted
/// [TickAppender], and a stub obligation — so interval firing, the fenced-out
/// skip, and fixpoint termination are all drivable without a socket or a wall
/// clock.
library;

import 'dart:async';

import 'package:grid_trajectory/grid_trajectory.dart';

/// A clock the test steps by hand.
class FakeClock {
  DateTime now = DateTime.utc(2026, 8, 31, 12);

  DateTime call() => now;

  void advance(Duration by) => now = now.add(by);
}

/// Captures the tick's one-shot timers and fires them on demand.
class ManualTimers {
  final List<Duration> scheduled = [];
  _ManualTimer? _pending;

  bool get isArmed => _pending != null;

  Timer schedule(Duration duration, void Function() callback) {
    scheduled.add(duration);
    return _pending = _ManualTimer(this, callback);
  }

  /// Fires the armed timer and lets the pass it starts run to completion.
  Future<void> fire() async {
    final timer = _pending;
    if (timer == null) throw StateError('no timer armed');
    _pending = null;
    timer.run();
    await pump();
  }

  /// Drains the microtask/event queues the async pass rides on.
  Future<void> pump() async {
    for (var i = 0; i < 8; i++) {
      await Future<void>.delayed(Duration.zero);
    }
  }
}

class _ManualTimer implements Timer {
  _ManualTimer(this._owner, this._callback);

  final ManualTimers _owner;
  final void Function() _callback;
  bool _active = true;

  void run() {
    _active = false;
    _callback();
  }

  @override
  void cancel() {
    _active = false;
    if (identical(_owner._pending, this)) _owner._pending = null;
  }

  @override
  bool get isActive => _active;

  @override
  int get tick => 0;
}

/// A [TickAppender] whose disposition and per-append outcomes the test writes.
class FakeTickAppender implements TickAppender {
  FakeTickAppender({List<AppendOutcome> outcomes = const []})
    : outcomes = [...outcomes];

  @override
  bool isInert = false;

  @override
  bool isHalted = false;

  /// Outcomes handed back in order; the default is a landed row.
  List<AppendOutcome> outcomes;

  final List<TrajectoryRecord> appended = [];
  int doltCommits = 0;

  /// Thrown out of [doltCommitIfDue] — the branch-pin fail-closed shape.
  Object? commitThrows;

  @override
  Future<AppendOutcome> append(
    TrajectoryRecord record, {
    TrajectoryProvenance provenance = TrajectoryProvenance.observed,
    String? provenanceBasis,
  }) async {
    appended.add(record);
    if (outcomes.isEmpty) {
      return Appended(
        recordId: 'r${appended.length}',
        seq: appended.length,
        epochSeq: appended.length,
      );
    }
    return outcomes.removeAt(0);
  }

  @override
  Future<void> doltCommitIfDue() async {
    doltCommits += 1;
    final error = commitThrows;
    if (error != null) throw error; // ignore: only_throw_errors
  }
}

/// An obligation whose rows and repair the test supplies.
class StubObligationQuery extends ObligationQuery {
  StubObligationQuery({
    this.name = 'stub',
    this.sql = 'SELECT 1 AS x',
    required this.onRepair,
  });

  @override
  final String name;

  @override
  final String sql;

  final Future<List<ObligationAppend>> Function(List<Map<String, String?>> rows)
  onRepair;

  int runs = 0;

  @override
  Future<List<ObligationAppend>> repair(List<Map<String, String?>> rows) async {
    runs += 1;
    return onRepair(rows);
  }
}
