import 'dart:async';
import 'dart:collection';

/// A STATION-SCOPED bound on how many state-store lifecycle writes of one
/// class are in flight at once (tg-66w8).
///
/// The bound this replaces lived on each substation `WorkList` — one drain,
/// [bound] workers — so the effective station-wide concurrency was the bound
/// TIMES the substations holding terminal sessions. Lunar composes thirteen
/// substations; at two per WorkList that re-formed the very boot burst the
/// bound existed to prevent (up to twenty-six simultaneous terminal writes
/// against one serialising Dolt store), and every terminal gate close in the
/// burst died at `DoltQueryService.queryTimeout`. This governor is owned by
/// `StationServices` — one per station, one per write class — and every
/// WorkList shares it, so the station-wide count can never exceed [bound]
/// however many substations are draining.
///
/// This is a bound, not a deadline: a write queued here waits for a permit
/// and only then starts its own store call under the store's own deadline.
/// Queue residence never eats into that deadline, which is what turns a burst
/// of twenty-six simultaneous writes into a stream of [bound] at a time.
/// Giving the terminal write its own progress-following deadline was
/// considered against `the_grid#the-pour-gets-its-own-bd-deadline` and
/// `the_grid#trajectory-queue-deadline-follows-writer-progress` and NOT
/// chosen (tg-66w8's decided approach); if this bound alone proves
/// insufficient, those two decisions govern the next change on this surface.
final class StateStoreWriteGovernor {
  /// Creates a governor admitting at most [bound] writes at once, reported on
  /// diagnostics as [lane].
  StateStoreWriteGovernor({required this.bound, required this.lane})
    : assert(bound > 0, 'a write bound must admit at least one write');

  /// The station-wide ceiling on simultaneously in-flight writes.
  final int bound;

  /// The write class this governor bounds, for diagnostics.
  final String lane;

  int _inFlight = 0;
  int _peakInFlight = 0;
  final Queue<Completer<void>> _waiters = Queue<Completer<void>>();

  /// Writes running right now.
  int get inFlight => _inFlight;

  /// Writes parked waiting for a permit.
  int get queued => _waiters.length;

  /// The high-water mark of simultaneously in-flight writes since
  /// construction. Diagnostics and tests.
  int get peakInFlight => _peakInFlight;

  /// Runs [write] once a permit is free, and returns its result. A write that
  /// throws still releases its permit; the error propagates to the caller.
  Future<T> run<T>(Future<T> Function() write) async {
    await _acquire();
    try {
      return await write();
    } finally {
      _release();
    }
  }

  Future<void> _acquire() {
    if (_inFlight < bound) {
      _inFlight += 1;
      if (_inFlight > _peakInFlight) _peakInFlight = _inFlight;
      return Future<void>.value();
    }
    final waiter = Completer<void>();
    _waiters.add(waiter);
    return waiter.future;
  }

  void _release() {
    if (_waiters.isNotEmpty) {
      // Hand the permit straight to the next waiter in FIFO order; the
      // in-flight count is unchanged.
      _waiters.removeFirst().complete();
      return;
    }
    _inFlight -= 1;
  }
}
