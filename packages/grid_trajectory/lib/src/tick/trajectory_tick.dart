/// The service tick (§5) — the fenced transition service's repair loop.
///
/// Every [interval] (30 s, aligned with the dolt-commit cadence) the tick runs
/// a FIXED, ordered list of derived-obligation queries, each keyed on the
/// external state it repairs, and appends the repair records through the same
/// counter-CAS fence as any other append. A fenced-out tick repairs nothing —
/// the skip is the correct behavior, not a degradation.
///
/// **Stage 0 wires NO obligations.** The obligation table in §5 arrives with
/// its record families: the attempt/step queries at Stage 1, the admission
/// authority's eligibility re-evaluation and the grant queries at Stage 3
/// (§9). Stage 0 is the skeleton — the loop, the fence skip, the fixpoint, and
/// the telemetry — so the families have somewhere to arm.
///
/// Lifecycle mirrors `WedgeMonitor`: an injected timer seam (no top-level
/// timers), a self-re-arming one-shot rather than a periodic (an async pass
/// must finish before the next is scheduled, so passes never stack), and a
/// [dispose] that cancels the timer and makes further passes no-ops.
///
/// The tick does NOT own the down verb: [runToFixpoint] is the primitive the
/// station's `down` runs before appending `authority.epoch.closed`, and the
/// caller decides what a non-reached fixpoint means for that record's payload.
library;

import 'dart:async';

import '../append/append_outcome.dart';
import '../connect/trajectory_db.dart';
import 'obligation_query.dart';
import 'tick_appender.dart';
import 'tick_telemetry.dart';

/// §5's interval: every 30 s while resident, plus at boot and immediately
/// after any terminal append (both are [runPass] calls by the owner).
const Duration kDefaultTickInterval = Duration(seconds: 30);

/// The pass cap on [TrajectoryTick.runToFixpoint] — a repair that keeps
/// re-arming its own obligation must bound the down, not block it.
const int kDefaultFixpointPasses = 8;

/// Runs the derived-obligation queries on an interval and to fixpoint.
class TrajectoryTick {
  /// Creates a tick over [appender]'s fence and [db]'s read path.
  ///
  /// [queries] defaults to Stage 0's empty set. [onPass] is an emit-only
  /// telemetry sink (the flare convention: a throwing sink never breaks the
  /// loop); [lastPass] serves the same value to a status surface.
  TrajectoryTick({
    required TickAppender appender,
    required TrajectoryDb db,
    List<ObligationQuery> queries = kStage0ObligationQueries,
    this.interval = kDefaultTickInterval,
    this.maxFixpointPasses = kDefaultFixpointPasses,
    DateTime Function()? clock,
    Timer Function(Duration, void Function())? scheduleTimer,
    void Function(TrajectoryTickPass pass)? onPass,
  }) : _appender = appender,
       _db = db,
       _queries = List.unmodifiable(queries),
       _clock = clock ?? DateTime.now,
       _scheduleTimer = scheduleTimer ?? Timer.new,
       _onPass = onPass;

  /// How often a resident station re-runs the obligation set.
  final Duration interval;

  /// The cap [runToFixpoint] stops at.
  final int maxFixpointPasses;

  final TickAppender _appender;
  final TrajectoryDb _db;
  final List<ObligationQuery> _queries;
  final DateTime Function() _clock;
  final Timer Function(Duration, void Function()) _scheduleTimer;
  final void Function(TrajectoryTickPass pass)? _onPass;

  Timer? _timer;
  bool _running = false;
  bool _disposed = false;
  TrajectoryTickPass? _lastPass;

  /// The obligations this tick runs, in order. Empty at Stage 0.
  List<ObligationQuery> get queries => _queries;

  /// The most recent pass — a plain derived value the status view reads fresh.
  TrajectoryTickPass? get lastPass => _lastPass;

  bool get isArmed => _timer != null;

  /// Runs the boot pass and arms the interval. The timer arms even when the
  /// boot pass skips: an inert appender is not permanently inert (a successor
  /// `claimEpoch` clears it), so the loop keeps looking.
  Future<TrajectoryTickPass> start() async {
    if (_disposed) {
      return _record(_skipped(TickPassDisposition.skippedDisposed));
    }
    try {
      return await runPass();
    } finally {
      _arm();
    }
  }

  /// Runs one pass. Called by the timer, by [start], and by the owner
  /// immediately after a terminal append (§5's post-terminal trigger).
  Future<TrajectoryTickPass> runPass() async {
    if (_disposed) {
      return _record(_skipped(TickPassDisposition.skippedDisposed));
    }
    // Passes never stack: an interval that fires into a long pass is dropped,
    // not queued — the next one re-reads the same external state anyway.
    if (_running) return _record(_skipped(TickPassDisposition.skippedBusy));
    _running = true;
    try {
      return _record(await _pass());
    } finally {
      _running = false;
    }
  }

  /// Runs passes until one finds no work — §5's clean-down contract: `down`
  /// drives this BEFORE appending `authority.epoch.closed`, and that record is
  /// the receipt that no obligation was left open.
  ///
  /// Stops early — [TrajectoryTickFixpoint.reached] false — on a skipped pass
  /// (fenced out, halted) or at [maxFixpointPasses]; the caller reports
  /// [TrajectoryTickFixpoint.outstanding] and lets the successor's boot tick
  /// inherit the remainder.
  Future<TrajectoryTickFixpoint> runToFixpoint({int? maxPasses}) async {
    final limit = maxPasses ?? maxFixpointPasses;
    final passes = <TrajectoryTickPass>[];
    while (passes.length < limit) {
      final pass = await runPass();
      passes.add(pass);
      if (!pass.ran) {
        return TrajectoryTickFixpoint(passes: passes, reached: false);
      }
      if (pass.quiet) {
        return TrajectoryTickFixpoint(passes: passes, reached: true);
      }
    }
    return TrajectoryTickFixpoint(passes: passes, reached: false);
  }

  /// Cancels the interval and makes further passes no-ops. Idempotent. Does
  /// NOT close [db] or quiesce the appender — the owner built those, the owner
  /// tears them down (storage-call.md's stop order).
  void dispose() {
    _disposed = true;
    _timer?.cancel();
    _timer = null;
  }

  // ── the pass ─────────────────────────────────────────────────────────────

  Future<TrajectoryTickPass> _pass() async {
    final startedAt = _clock();
    if (_appender.isHalted) {
      return _skipped(TickPassDisposition.skippedHalted, at: startedAt);
    }
    if (_appender.isInert) {
      return _skipped(TickPassDisposition.skippedFencedOut, at: startedAt);
    }

    var queriesRun = 0;
    var appended = 0;
    var deduped = 0;
    final refusals = <TickRefusal>[];

    obligations:
    for (final query in _queries) {
      // Re-checked per query: the fence can change hands mid-pass, and a
      // fenced-out service must stop repairing at that instant.
      if (_appender.isInert || _appender.isHalted) break;
      queriesRun += 1;

      final List<ObligationAppend> repairs;
      try {
        final result = await _db.execute(query.sql, query.parameters);
        repairs = await query.repair(result.rows);
      } on Object catch (error) {
        // One obligation's failure never ends the pass: the query is keyed on
        // external state, so it stays open and the next tick retries it
        // (§5's N-consecutive-failure accounting arrives with Stage 1).
        refusals.add(
          TickRefusal(
            kind: TickRefusalKind.queryFailed,
            query: query.name,
            reason: '$error',
          ),
        );
        continue;
      }

      for (final repair in repairs) {
        final outcome = await _appender.append(
          repair.record,
          provenance: repair.provenance,
          provenanceBasis: repair.provenanceBasis,
        );
        switch (outcome) {
          case Appended():
            appended += 1;
          case AppendDeduped():
            deduped += 1;
          case AppendFencedOut(:final reason):
            refusals.add(
              TickRefusal(
                kind: TickRefusalKind.fencedOut,
                query: query.name,
                reason: reason,
                recordType: repair.record.recordType,
              ),
            );
            break obligations;
          case AppendCorruptionHalt(:final reason):
            refusals.add(
              TickRefusal(
                kind: TickRefusalKind.corruptionHalt,
                query: query.name,
                reason: reason,
                recordType: repair.record.recordType,
              ),
            );
            break obligations;
        }
      }
    }

    // The cadence commit fires on the interval even when the pass appended
    // nothing (§5); a branch-pin violation throws out of here, deliberately —
    // fail closed.
    await _appender.doltCommitIfDue();

    return TrajectoryTickPass(
      startedAt: startedAt,
      disposition: TickPassDisposition.ran,
      queriesRun: queriesRun,
      recordsAppended: appended,
      recordsDeduped: deduped,
      refusals: List.unmodifiable(refusals),
    );
  }

  TrajectoryTickPass _skipped(
    TickPassDisposition disposition, {
    DateTime? at,
  }) => TrajectoryTickPass(startedAt: at ?? _clock(), disposition: disposition);

  TrajectoryTickPass _record(TrajectoryTickPass pass) {
    _lastPass = pass;
    try {
      _onPass?.call(pass);
    } catch (_) {
      // A throwing telemetry sink never breaks the loop — the same swallow
      // convention the engine's flares use.
    }
    return pass;
  }

  // ── the interval ─────────────────────────────────────────────────────────

  void _arm() {
    if (_disposed || _timer != null) return;
    _timer = _scheduleTimer(interval, _onTimer);
  }

  void _onTimer() {
    _timer = null;
    if (_disposed) return;
    unawaited(_timerPass());
  }

  Future<void> _timerPass() async {
    try {
      await runPass();
    } on Object catch (error) {
      // The timer is nobody's caller: a throwing pass (the branch-pin
      // fail-closed, a dropped session) must surface as telemetry, not as an
      // unhandled async error. The appender has already latched its own halt.
      _record(
        TrajectoryTickPass(
          startedAt: _clock(),
          disposition: TickPassDisposition.ran,
          refusals: [
            TickRefusal(
              kind: TickRefusalKind.passFailed,
              query: '<pass>',
              reason: '$error',
            ),
          ],
        ),
      );
    } finally {
      _arm();
    }
  }
}
