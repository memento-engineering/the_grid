import 'dart:async';

import '../reactivity/dirty_signal.dart';

/// Observable counters for the controller's sync loop — surfaced by the
/// exploration `stats` tool.
class GraphSyncStats {
  GraphSyncStats({
    required this.signalCounts,
    required this.refreshCount,
    required this.lastRefresh,
    required this.lastReaction,
    required this.refreshing,
    required this.pendingFollowUp,
  });

  /// Signals seen, per origin.
  final Map<DirtyOrigin, int> signalCounts;

  /// Completed refreshes since start.
  final int refreshCount;

  /// Wall-clock duration of the most recent refresh's read+diff, or null before
  /// the first.
  final Duration? lastRefresh;

  /// End-to-end reaction latency of the most recent change: from the first
  /// dirty signal of the cycle to the refresh completing (includes the quiet
  /// period). Null before the first signal-driven refresh. This is the number
  /// the two-terminal demo reports against the ≤500ms budget (PDR §6.1).
  final Duration? lastReaction;

  /// True while a refresh is executing.
  final bool refreshing;

  /// True when a signal arrived during the in-flight refresh, so exactly one
  /// follow-up refresh is already queued.
  final bool pendingFollowUp;

  int get totalSignals =>
      signalCounts.values.fold(0, (sum, count) => sum + count);

  Map<String, Object?> toJson() => {
    'signalCounts': {
      for (final entry in signalCounts.entries) entry.key.name: entry.value,
    },
    'totalSignals': totalSignals,
    'refreshCount': refreshCount,
    'lastRefreshMs': lastRefresh?.inMilliseconds,
    'lastReactionMs': lastReaction?.inMilliseconds,
    'refreshing': refreshing,
    'pendingFollowUp': pendingFollowUp,
  };
}

/// Coalesces dirty signals into single-flight re-queries.
///
/// The reactive contract (ADR-0001 Decision 5):
/// * A burst of signals within [quietPeriod] triggers exactly **one** refresh
///   (trailing debounce — refresh fires once the stream goes quiet).
/// * Signals that arrive *during* a refresh set the dirty bit again, so
///   exactly **one** follow-up refresh runs afterward — never zero (a real
///   change would be lost), never N (write amplification).
/// * [start] performs an immediate baseline refresh, then debounces.
///
/// Holds no knowledge of *what* is read — it only decides *when*. The actual
/// snapshot composition + diff is [onRefresh] (the repository).
class GraphSyncInteractor {
  GraphSyncInteractor({
    required Stream<DirtySignal> signals,
    required Future<void> Function() onRefresh,
    this.quietPeriod = const Duration(milliseconds: 150),
  }) : _signals = signals,
       _onRefresh = onRefresh;

  final Stream<DirtySignal> _signals;
  final Future<void> Function() _onRefresh;
  final Duration quietPeriod;

  StreamSubscription<DirtySignal>? _sub;
  Timer? _quietTimer;
  bool _dirty = false;
  bool _refreshing = false;
  Future<void>? _pump;

  final _signalCounts = <DirtyOrigin, int>{};
  int _refreshCount = 0;
  Duration? _lastRefresh;
  Duration? _lastReaction;
  Stopwatch? _cycle;
  bool _started = false;
  bool _disposed = false;

  /// Subscribes to the signal stream and performs the baseline refresh.
  /// Returns once the baseline refresh completes.
  Future<void> start() async {
    if (_started) return;
    _started = true;
    _sub = _signals.listen(_onSignal);
    _dirty = true;
    await _runPump();
  }

  void _onSignal(DirtySignal signal) {
    if (_disposed) return;
    _signalCounts.update(signal.origin, (n) => n + 1, ifAbsent: () => 1);
    // The poll ticker is a coarse backstop (a "maybe re-query" nudge on the
    // CLI path), not a known change. A tick that lands while a refresh is
    // already in flight is already satisfied by that refresh, so it must NOT
    // re-dirty the pump: re-dirtying on it livelocks start() for any store
    // whose refresh outlasts the poll interval (ADR-0001 Decision 5 — "never
    // N"). Real signals (watch/probe/manual) keep single-flight semantics: a
    // mutation mid-refresh still schedules exactly one follow-up.
    if (signal.origin == DirtyOrigin.pollTicker && _refreshing) return;
    // Start timing the reaction at the leading edge of a fresh cycle.
    _cycle ??= Stopwatch()..start();
    _dirty = true;
    _quietTimer?.cancel();
    _quietTimer = Timer(quietPeriod, _runPump);
  }

  /// Forces a re-query now, bypassing the quiet period, and completes once a
  /// refresh that observed this call has finished. Used by the `requery` tool.
  Future<void> refreshNow() {
    if (_disposed) return Future.value();
    _quietTimer?.cancel();
    _cycle ??= Stopwatch()..start();
    _dirty = true;
    return _runPump();
  }

  Future<void> _runPump() {
    if (_disposed) return _pump ?? Future.value();
    if (_refreshing) return _pump ?? Future.value();
    return _pump = _pumpLoop();
  }

  Future<void> _pumpLoop() async {
    _refreshing = true;
    try {
      while (_dirty) {
        _dirty = false;
        final sw = Stopwatch()..start();
        await _onRefresh();
        sw.stop();
        _lastRefresh = sw.elapsed;
        _refreshCount++;
      }
    } finally {
      _refreshing = false;
      _pump = null;
      // Close out the reaction-latency cycle (null for the start() baseline,
      // which has no triggering signal).
      if (_cycle != null) {
        _lastReaction = _cycle!.elapsed;
        _cycle = null;
      }
    }
  }

  GraphSyncStats get stats => GraphSyncStats(
    signalCounts: Map.unmodifiable(_signalCounts),
    refreshCount: _refreshCount,
    lastRefresh: _lastRefresh,
    lastReaction: _lastReaction,
    refreshing: _refreshing,
    pendingFollowUp: _refreshing && _dirty,
  );

  /// Stops scheduling and **drains any in-flight refresh** before returning,
  /// so a caller can safely tear down the repository's streams afterward
  /// without a "add after close" race.
  Future<void> dispose() async {
    _disposed = true;
    _quietTimer?.cancel();
    await _sub?.cancel();
    await _pump; // null-safe await: completes immediately if idle
  }
}
