/// The station-side trajectory harness — stage1-wiring §1, mechanically.
///
/// [TrajectoryHarness] owns the fenced service's station-side lifecycle: the
/// [TrajectoryDb] connection (as the `trajectory` SQL user), the ONE
/// [TrajectoryAppender], the bounded append queue and its single writer loop
/// (§2.5), the [TrajectoryTick], and the gc cadence (M2). The derivation layer
/// (`StationTrajectoryRecorder`, chunk W3) hands the queue constructed records
/// through [enqueue]; nothing else ever touches the appender.
///
/// Binding constraints (stage1-wiring, restated where the code enforces them):
///
///   * **Non-blocking as well as non-fatal.** No engine hot path ever awaits
///     an append — [enqueue] is synchronous and returns immediately; the only
///     synchronous trajectory awaits in the whole system are at boot (belt
///     verify, epoch claim — [start]) and at clean-down (the fixpoint drain —
///     [shutdown]).
///   * **The trajectory can degrade; work cannot** (§3). [start] and
///     [shutdown] catch everything: a failed connect, verify, or claim
///     records a mode + cause and the station runs legacy-only. No mount, no
///     step, no close ever waits on the trajectory.
///   * **Sole appender.** One [TrajectoryAppender], driven only by the writer
///     loop and the tick — and every statement on the one SQL session
///     (writer-loop appends, tick passes, gc, the boundary commit) rides one
///     serial lane, because a `mysql_client` session cannot interleave
///     statements.
///   * **Verify-before-claim** (§1.2, r2 minor 17): a corrupt log must not
///     advance the fence — `verifyBeltAtBoot()` runs before `claimEpoch`, and
///     a halted verify means no claim, no fence advance, flare
///     `trajectory.halted`, boot continues legacy-only.
library;

import 'dart:async';
import 'dart:collection';
import 'dart:io' as io;

import 'package:grid_runtime/grid_runtime.dart'
    show StationTrajectoryRecorder, TrajectoryRecordSink;
import 'package:grid_trajectory/grid_trajectory.dart';
import 'package:meta/meta.dart';

import 'trajectory_config.dart';

/// The flare seam — shape-compatible with `ExplorationTransport.flare`.
typedef TrajectoryFlare = void Function(String name, Map<String, String> data);

/// The one database the harness dials — `CREATE DATABASE trajectory` beside
/// the ledger database (runbook step 2).
const String kTrajectoryDatabase = 'trajectory';

/// One derived record awaiting the single writer (§2.5). Constructed by the
/// engine-side derivation layer, never by the harness — the extraction
/// boundary keeps record vocabulary out of the mechanics.
@immutable
final class TrajectoryAppendRequest {
  const TrajectoryAppendRequest(
    this.record, {
    this.occurredAt,
    this.seat,
    this.provenance = TrajectoryProvenance.observed,
    this.provenanceBasis,
  });

  final TrajectoryRecord record;

  /// The observation instant (§2.2); null lets the appender stamp now.
  final DateTime? occurredAt;

  /// Recorder-derived seat (§2.2); null falls back to the appender's
  /// prefix derivation.
  final String? seat;

  final TrajectoryProvenance provenance;
  final String? provenanceBasis;
}

/// The harness's posture — what `/status` renders and the failure table in
/// stage1-wiring §3 maps to.
enum TrajectoryHarnessMode {
  /// Config said no (or dry-run forced it): no connection, no claim, silent.
  disabled,

  /// `auto` found no provisioning artifact: legacy-only with a one-line
  /// notice, not a warning storm (§1.3).
  unprovisioned,

  /// Built but not yet started.
  down,

  /// Claimed an epoch; the writer loop is draining.
  live,

  /// The trajectory is down (connect/claim failed at boot) — the station runs
  /// legacy-only; the shadow window is not counting.
  degraded,

  /// A successor holds the authority — latched quiet, flared once (§3).
  fencedOut,

  /// The corruption-halt alarm class — latched loud; the log is presumed
  /// damaged until a human looks (§3).
  halted,
}

/// One status read — plain derived values for a runner's banner/`/status`
/// block (the rendering is a space_station edit, §1.1).
@immutable
final class TrajectoryHarnessStatus {
  const TrajectoryHarnessStatus({
    required this.mode,
    required this.cause,
    required this.epoch,
    required this.appended,
    required this.deduped,
    required this.dropped,
    required this.suppressed,
    required this.queueDepth,
  });

  final TrajectoryHarnessMode mode;

  /// Why the mode is what it is, when it is not [TrajectoryHarnessMode.live].
  final String? cause;

  /// The claimed boot epoch, once [TrajectoryHarness.start] claimed one.
  final int? epoch;

  final int appended;
  final int deduped;

  /// Appends lost to overflow, server errors, or failed reconnects — a round
  /// with any dropped append cannot count as a clean round (§3).
  final int dropped;

  /// Appends short-circuited to a count after a latch (fenced out / halted /
  /// degraded) — the "counting no-op" posture (§1.1).
  final int suppressed;

  final int queueDepth;

  @override
  String toString() =>
      'TrajectoryHarnessStatus(${mode.name}'
      '${cause == null ? '' : ' ($cause)'}, epoch: $epoch, '
      'appended: $appended, deduped: $deduped, dropped: $dropped, '
      'suppressed: $suppressed, queue: $queueDepth)';
}

/// The fenced service's station-side owner (stage1-wiring §1.1).
class TrajectoryHarness {
  TrajectoryHarness._({
    required this.config,
    required String gridHome,
    required String station,
    required this.seatPrefixes,
    required TrajectoryFlare? onFlare,
    required Future<TrajectoryDb> Function()? connect,
    required TrajectoryAppender Function(TrajectoryDb db)? appenderFactory,
    required List<ObligationQuery> tickQueries,
    required Timer Function(Duration, void Function()) scheduleTimer,
    required DateTime Function() clock,
    required ({int pid, int pgid}) identity,
    required TrajectoryHarnessMode mode,
    required String? cause,
  }) : _gridHome = gridHome,
       _station = station,
       _onFlare = onFlare,
       _connect = connect,
       _appenderFactory = appenderFactory,
       _tickQueries = tickQueries,
       _scheduleTimer = scheduleTimer,
       _clock = clock,
       _identity = identity,
       _mode = mode,
       _cause = cause;

  /// Builds the harness value — no I/O beyond the `auto`-mode artifact probe;
  /// connect/verify/claim happen in [start], after the stores are up (§1.2).
  ///
  /// [connect] / [appenderFactory] / [scheduleTimer] / [clock] / [identity]
  /// are TEST seams; production takes the defaults. The default connect path
  /// resolves the dolt listener FRESH on every call — which is what makes the
  /// reconnect rule (§4: re-resolve, never pin the boot-time port) hold by
  /// construction.
  static Future<TrajectoryHarness> build({
    required TrajectoryConfig config,
    required String gridHome,
    required String station,
    Set<String> seatPrefixes = const {},
    TrajectoryFlare? onFlare,
    Future<TrajectoryDb> Function()? connect,
    TrajectoryAppender Function(TrajectoryDb db)? appenderFactory,
    List<ObligationQuery> tickQueries = kStage0ObligationQueries,
    Timer Function(Duration, void Function())? scheduleTimer,
    DateTime Function()? clock,
    ({int pid, int pgid})? identity,
  }) async {
    var mode = TrajectoryHarnessMode.down;
    String? cause;
    switch (config.mode) {
      case TrajectoryConfigMode.disabled:
        mode = TrajectoryHarnessMode.disabled;
        cause = 'disabled by config';
      case TrajectoryConfigMode.auto:
        final secret = trajectorySecretPath(gridHome);
        if (!io.File(secret).existsSync()) {
          mode = TrajectoryHarnessMode.unprovisioned;
          cause = 'no provisioning artifact at $secret';
        }
      case TrajectoryConfigMode.required:
        // A missing artifact is not checked here: start()'s connect fails and
        // degrades LOUD, which is exactly required-mode's posture (§1.3).
        break;
    }
    return TrajectoryHarness._(
      config: config,
      gridHome: gridHome,
      station: station,
      seatPrefixes: Set<String>.unmodifiable(seatPrefixes),
      onFlare: onFlare,
      connect: connect,
      appenderFactory: appenderFactory,
      tickQueries: tickQueries,
      scheduleTimer: scheduleTimer ?? Timer.new,
      clock: clock ?? DateTime.now,
      // the_grid runs in its own process group; pid ≈ pgid here (the
      // SystemProcessGroupController.currentGroupId precedent).
      identity: identity ?? (pid: io.pid, pgid: io.pid),
      mode: mode,
      cause: cause,
    );
  }

  final TrajectoryConfig config;

  /// The seat-derivation input (§2.2's seat row) — carried for the derivation
  /// layer; the harness itself never derives a seat.
  final Set<String> seatPrefixes;

  /// The derivation layer (§2) — one of the five things the harness owns
  /// (§1.1). Its sink is THIS harness's bounded queue, so every derived
  /// record rides the single writer loop; under any non-accepting posture
  /// (disabled / unprovisioned / degraded / latched) the recorder is a
  /// counting no-op and no call site ever branches on "is the trajectory up".
  late final StationTrajectoryRecorder recorder = StationTrajectoryRecorder(
    sink: _HarnessRecordSink(this),
    seatPrefixes: seatPrefixes,
    clock: _clock,
    // Derivation-failure flares ride the harness's standing 30 s bucket.
    onFlare: _flareLimited,
  );

  final String _gridHome;
  final String _station;
  final TrajectoryFlare? _onFlare;

  /// The connect TEST seam; null selects the default resolve+secret+socket
  /// path in [_openConnection].
  final Future<TrajectoryDb> Function()? _connect;
  final TrajectoryAppender Function(TrajectoryDb db)? _appenderFactory;
  final List<ObligationQuery> _tickQueries;
  final Timer Function(Duration, void Function()) _scheduleTimer;
  final DateTime Function() _clock;
  final ({int pid, int pgid}) _identity;

  TrajectoryHarnessMode _mode;
  String? _cause;
  int? _epoch;
  bool _started = false;
  bool _isShutdown = false;

  TrajectoryDb? _db;
  TrajectoryAppender? _appender;
  TrajectoryTick? _tick;
  Timer? _gcTimer;
  bool _needsReconnect = false;

  final Queue<TrajectoryAppendRequest> _queue =
      Queue<TrajectoryAppendRequest>();
  bool _writerActive = false;
  Future<void> _writerDone = Future<void>.value();

  /// The one serial lane every statement on the SQL session rides — the
  /// writer loop, the tick's passes, gc, and the boundary commit never
  /// interleave on the single `mysql_client` session.
  Future<void> _serialTail = Future<void>.value();

  int _appended = 0;
  int _deduped = 0;
  int _dropped = 0;
  int _suppressed = 0;

  final Map<String, DateTime> _lastFlareAt = <String, DateTime>{};

  TrajectoryHarnessMode get mode => _mode;

  /// A fresh status read (plain derived values, never cached).
  TrajectoryHarnessStatus get status => TrajectoryHarnessStatus(
    mode: _mode,
    cause: _cause,
    epoch: _epoch,
    appended: _appended,
    deduped: _deduped,
    dropped: _dropped,
    suppressed: _suppressed,
    queueDepth: _queue.length,
  );

  /// The tick, for a status surface's `lastPass` — null until live.
  TrajectoryTick? get tick => _tick;

  // ── boot (§1.2 step 2) ───────────────────────────────────────────────────

  /// Trajectory up: connect as `trajectory` user → `verifyBeltAtBoot()`
  /// FIRST → `claimEpoch(cause:'boot')` → `tick.start()` → gc cadence armed.
  ///
  /// NEVER throws and never fails the boot: every failure records a mode +
  /// cause and the station continues legacy-only (§3). The caller holds the
  /// station lock (the claim's mutual-exclusion precondition, §1.2) — `up`
  /// acquires it before `StationWorkRuntime.start()` runs.
  Future<void> start() async {
    if (_started || _isShutdown || _mode != TrajectoryHarnessMode.down) return;
    _started = true;
    try {
      final db = await _openConnection();
      _db = db;
      final appender = _appenderFactory?.call(db) ?? _defaultAppender(db);
      _appender = appender;

      // Verify-before-claim (r2, minor 17): a corrupt log must not advance
      // the fence. verifyBeltAtBoot consults no claimed-epoch state, and a
      // halted verify means no claim happened at all.
      final halt = await appender.verifyBeltAtBoot();
      if (halt != null) {
        _latchHalted(halt.reason);
        await _closeDbQuietly();
        return;
      }

      final claim = await appender.claimEpoch(
        pid: _identity.pid,
        pgid: _identity.pgid,
      );
      switch (claim) {
        case EpochClaimed(:final epoch):
          _epoch = epoch;
        case EpochClaimRefused(:final attempts):
          _degrade('epoch claim refused after $attempts attempts');
          await _closeDbQuietly();
          return;
      }

      _tick = TrajectoryTick(
        appender: _SerializedTickAppender(this, appender),
        db: _SerializedDb(this),
        queries: _tickQueries,
        interval: config.tickInterval,
        clock: _clock,
        scheduleTimer: _scheduleTimer,
      );
      _mode = TrajectoryHarnessMode.live;
      _cause = null;
      // Boot pass + interval arm (§1.2 step 2). start() cannot throw past the
      // tick's own telemetry swallow, but the enclosing catch holds anyway.
      await _tick!.start();
      _armGc();
      // Anything enqueued before the claim drains now.
      _pump();
    } on Object catch (error) {
      _degrade('$error');
      await _closeDbQuietly();
    }
  }

  // ── the append queue + single writer (§2.5) ──────────────────────────────

  /// Enqueue, never await: hands [request] to the single writer and returns.
  /// On overflow the INCOMING append is dropped and counted (§2.5); after a
  /// latch (fenced out / halted) or under degraded/disabled postures every
  /// call short-circuits to a count — no call site ever branches on "is the
  /// trajectory up".
  void enqueue(TrajectoryAppendRequest request) {
    switch (_mode) {
      case TrajectoryHarnessMode.disabled:
      case TrajectoryHarnessMode.unprovisioned:
        return; // silent no-op — the station chose legacy-only.
      case TrajectoryHarnessMode.degraded:
      case TrajectoryHarnessMode.fencedOut:
      case TrajectoryHarnessMode.halted:
        _suppressed += 1;
        return;
      case TrajectoryHarnessMode.down:
      case TrajectoryHarnessMode.live:
        if (_isShutdown) {
          _suppressed += 1;
          return;
        }
        if (_queue.length >= config.queueBound) {
          _dropped += 1;
          _flareLimited('trajectory.queueOverflow', {
            'queueBound': '${config.queueBound}',
            'dropped': '$_dropped',
          });
          return;
        }
        _queue.add(request);
        _pump();
    }
  }

  void _pump() {
    if (_mode != TrajectoryHarnessMode.live) return;
    if (_writerActive || _queue.isEmpty) return;
    _writerActive = true;
    _writerDone = _drainQueue();
  }

  /// The single writer loop: global FIFO (which subsumes the per-session FIFO
  /// guarantee, §2.5) — the sole code that reaches the appender for derived
  /// records. The tick's obligation appends ride the same serial lane between
  /// queued entries.
  Future<void> _drainQueue() async {
    try {
      while (_mode == TrajectoryHarnessMode.live && _queue.isNotEmpty) {
        await _appendOne(_queue.removeFirst());
      }
    } finally {
      _writerActive = false;
      // A request enqueued between the loop's last check and this finally
      // re-arms rather than stranding in the queue.
      if (_mode == TrajectoryHarnessMode.live && _queue.isNotEmpty) _pump();
    }
  }

  Future<void> _appendOne(TrajectoryAppendRequest request) async {
    try {
      if (_needsReconnect && !await _reconnect()) {
        _dropped += 1;
        _flareLimited('trajectory.appendDropped', {
          'reason': 'reconnect failed; listener re-resolved next append',
          'recordType': request.record.recordType,
          'dropped': '$_dropped',
        });
        return;
      }
      final outcome = await _serialize(
        () => _appender!.append(
          request.record,
          occurredAt: request.occurredAt,
          seat: request.seat,
          provenance: request.provenance,
          provenanceBasis: request.provenanceBasis,
        ),
      );
      switch (outcome) {
        case Appended():
          _appended += 1;
        case AppendDeduped():
          _deduped += 1;
        case AppendFencedOut(:final reason):
          _latchFencedOut(reason);
        case AppendCorruptionHalt(:final reason):
          _latchHalted(reason);
        case AppendGrantRefused(:final reason):
          // Cannot occur at Stage 1 (no grant-scoped appends) — counted as
          // dropped if it ever does (§3).
          _dropped += 1;
          _flareLimited('trajectory.appendDropped', {
            'reason': reason,
            'recordType': request.record.recordType,
            'dropped': '$_dropped',
          });
        case AppendInternalError(:final cause):
          // Server hiccup / dead socket: count, flare rate-limited, keep
          // draining, and drive the guarded reconnect eagerly on the next
          // append (§3; M4: a typed ~20 ms outcome, no hang).
          _dropped += 1;
          _needsReconnect = true;
          _flareLimited('trajectory.appendDropped', {
            'reason': '$cause',
            'recordType': request.record.recordType,
            'dropped': '$_dropped',
          });
      }
    } on Object catch (error) {
      // §5's sealed contract says append() never throws — belt and braces: a
      // throw is counted like any dropped append, never an unhandled zone
      // error out of the writer loop.
      _dropped += 1;
      _needsReconnect = true;
      _flareLimited('trajectory.appendDropped', {
        'reason': '$error',
        'recordType': request.record.recordType,
        'dropped': '$_dropped',
      });
    }
  }

  /// Guarded reconnect: RE-RESOLVES the listener first (§4's reconnect rule —
  /// bd rewrites the child server's port on its own terms), dials fresh, and
  /// lets the appender's own guard decide resumed vs inert.
  Future<bool> _reconnect() async {
    final TrajectoryDb fresh;
    try {
      fresh = await _openConnection();
    } on Object {
      return false; // caller counts + flares; the flag stays set.
    }
    try {
      final outcome = await _serialize(() => _appender!.reconnect(fresh));
      switch (outcome) {
        case ReconnectResumed():
          await _closeDbQuietly(); // the dead session
          _db = fresh;
          _needsReconnect = false;
          return true;
        case ReconnectInert(:final staleEpoch, :final liveEpoch):
          await _closeQuietly(fresh);
          _latchFencedOut('stale epoch $staleEpoch (live $liveEpoch)');
          return false;
      }
    } on Object {
      await _closeQuietly(fresh);
      return false;
    }
  }

  // ── clean-down (§1.2 shutdown order) ─────────────────────────────────────

  /// §2.5's drain contract: drains the append queue to empty FIRST, then runs
  /// obligation passes to fixpoint. Null when the trajectory never came up.
  Future<TrajectoryTickFixpoint?> runToFixpoint() async {
    await _quiesceQueue();
    return _tick?.runToFixpoint();
  }

  Future<void> _quiesceQueue() async {
    _pump();
    while (_writerActive) {
      await _writerDone;
    }
  }

  /// Trajectory down, before the stores it reads — with the hard ordering
  /// guarantee (r2, major 9): NEVER throws, so it can never block sources
  /// shutdown. Every step is individually guarded in the settle style; a
  /// throw is caught, counted, and flared as the Stage-0 non-fatal signal
  /// class.
  Future<void> shutdown() async {
    if (_isShutdown) return;
    _isShutdown = true;
    _gcTimer?.cancel();
    _gcTimer = null;
    final neverCameUp = _appender == null;
    // 1 (guarded) — drain the queue, then the fixpoint (§1.2 step 1). A
    // fixpoint not reached rides the outstanding count in the final status
    // flare; the successor boot's tick inherits the remainder.
    TrajectoryTickFixpoint? fixpoint;
    try {
      fixpoint = await runToFixpoint();
    } on Object catch (error) {
      _flare('trajectory.shutdownDrainFailed', {'reason': '$error'});
    }
    // 2 — NO authority.epoch.closed record at Stage 1 (§1.2 step 2): the
    // clean-down receipt is the fixpoint telemetry plus the boundary commit.
    // 3 (guarded) — force a boundary dolt commit; a throw here is the
    // cadence-failure signal: caught, counted, flared — never propagated.
    try {
      final appender = _appender;
      if (appender != null) {
        await _serialize(appender.doltCommitIfDue);
      }
    } on Object catch (error) {
      _flare('trajectory.cadenceFailure', {'reason': '$error'});
    }
    try {
      _tick?.dispose();
    } on Object catch (error) {
      _flare('trajectory.shutdownDisposeFailed', {'reason': '$error'});
    }
    await _closeDbQuietly();
    // The final status flare — the §1.2 receipt (skipped when the harness
    // was a silent no-op all along).
    if (neverCameUp && _mode != TrajectoryHarnessMode.degraded) return;
    _flare('trajectory.shutdown', {
      'mode': _mode.name,
      'epoch': '${_epoch ?? ''}',
      'appended': '$_appended',
      'deduped': '$_deduped',
      'dropped': '$_dropped',
      'suppressed': '$_suppressed',
      'fixpointReached': '${fixpoint?.reached ?? false}',
      'outstanding': '${fixpoint?.outstanding ?? 0}',
      'unflushed': '${_queue.length}',
    });
  }

  // ── the gc cadence (§1.2 / M2) ───────────────────────────────────────────

  void _armGc() {
    if (_isShutdown || _gcTimer != null) return;
    _gcTimer = _scheduleTimer(config.gcInterval, _onGcTimer);
  }

  void _onGcTimer() {
    _gcTimer = null;
    if (_isShutdown) return;
    unawaited(_runGc());
  }

  Future<void> _runGc() async {
    try {
      if (_mode == TrajectoryHarnessMode.live && !_needsReconnect) {
        // Online, ~120 ms, reclaims ~98% — never touches bd's proxy (M2).
        await _serialize(() => _db!.execute('CALL DOLT_GC()'));
      }
    } on Object catch (error) {
      _flareLimited('trajectory.gcFailed', {'reason': '$error'});
    } finally {
      _armGc();
    }
  }

  // ── internals ────────────────────────────────────────────────────────────

  Future<TrajectoryDb> _openConnection() {
    final connect = _connect;
    if (connect != null) return connect();
    // Resolved FRESH on every call — boot and reconnect alike (§4).
    final listener = resolveDoltServerListener(_gridHome);
    final secretFile = io.File(trajectorySecretPath(_gridHome));
    final secret = secretFile.readAsStringSync().trim();
    if (secret.isEmpty) {
      throw StateError('empty trajectory secret: ${secretFile.path}');
    }
    return TrajectoryConnection.connect(
      TrajectoryEndpoint(
        host: listener.host,
        port: listener.port,
        user: trajectoryUser,
        password: secret,
        database: kTrajectoryDatabase,
      ),
    );
  }

  TrajectoryAppender _defaultAppender(TrajectoryDb db) => TrajectoryAppender(
    db: db,
    station: _station,
    commitCadence: config.commitCadence,
    // §5 step 5's Stage-1 registration (stage1-wiring §2.4 / W6): the
    // P1+P2+P6 incremental fold deltas ride every append's transaction.
    folds: kStage1FoldDeltas,
    // The Stage-0 notification seam rides the same flare transport as every
    // other engine LOUD signal, rate-limited under the standing 30 s bucket.
    onEvent: (event) => _flareLimited('trajectory.service.${event.kind.wire}', {
      'reason': event.reason,
    }),
  );

  Future<T> _serialize<T>(Future<T> Function() action) {
    final result = _serialTail.then((_) => action());
    _serialTail = result.then<void>((_) {}, onError: (_) {});
    return result;
  }

  void _latchFencedOut(String reason) {
    if (_latched) return;
    _mode = TrajectoryHarnessMode.fencedOut;
    _cause = reason;
    _suppressed += _queue.length;
    _queue.clear();
    // ONCE, by the latch (§3): mirrors the appender's inert latch — quiet.
    _flare('trajectory.fencedOut', {
      'reason': reason,
      'epoch': '${_epoch ?? ''}',
    });
  }

  void _latchHalted(String reason) {
    if (_latched) return;
    _mode = TrajectoryHarnessMode.halted;
    _cause = reason;
    _suppressed += _queue.length;
    _queue.clear();
    // Loud on every status read is the /status surface's job; the flare fires
    // once at the latch (§3): the log is presumed damaged until a human looks.
    _flare('trajectory.halted', {'reason': reason});
  }

  bool get _latched =>
      _mode == TrajectoryHarnessMode.fencedOut ||
      _mode == TrajectoryHarnessMode.halted;

  void _degrade(String cause) {
    _mode = TrajectoryHarnessMode.degraded;
    _cause = cause;
    _suppressed += _queue.length;
    _queue.clear();
    _flare('trajectory.degraded', {'reason': cause});
  }

  void _flare(String name, Map<String, String> data) {
    try {
      _onFlare?.call(name, data);
    } on Object {
      // Emit-only: a throwing transport never breaks the harness (the same
      // swallow convention the engine's flares use).
    }
  }

  /// Rate-limited flare — one per name per 30 s bucket (the standing reporter
  /// convention, §3).
  void _flareLimited(String name, Map<String, String> data) {
    final now = _clock();
    final last = _lastFlareAt[name];
    if (last != null && now.difference(last) < const Duration(seconds: 30)) {
      return;
    }
    _lastFlareAt[name] = now;
    _flare(name, data);
  }

  Future<void> _closeDbQuietly() async {
    final db = _db;
    _db = null;
    if (db != null) await _closeQuietly(db);
  }

  Future<void> _closeQuietly(TrajectoryDb db) async {
    try {
      await db.close();
    } on Object {
      // The session may already be gone.
    }
  }
}

/// The tick's appender port, routed through the harness's serial lane so tick
/// appends interleave BETWEEN queued entries, never inside one (§2.5).
final class _SerializedTickAppender implements TickAppender {
  _SerializedTickAppender(this._harness, this._appender);

  final TrajectoryHarness _harness;
  final TrajectoryAppender _appender;

  @override
  bool get isInert => _appender.isInert;

  @override
  bool get isHalted => _appender.isHalted;

  @override
  Future<AppendOutcome> append(
    TrajectoryRecord record, {
    TrajectoryProvenance provenance = TrajectoryProvenance.observed,
    String? provenanceBasis,
  }) => _harness._serialize(
    () => _appender.append(
      record,
      provenance: provenance,
      provenanceBasis: provenanceBasis,
    ),
  );

  @override
  Future<void> doltCommitIfDue() =>
      _harness._serialize(_appender.doltCommitIfDue);
}

/// The recorder's enqueue-only handle to the harness's queue (§2.5): the
/// derivation layer holds THIS, never the appender, so the sole-appender and
/// never-await invariants hold by construction.
final class _HarnessRecordSink implements TrajectoryRecordSink {
  _HarnessRecordSink(this._harness);

  final TrajectoryHarness _harness;

  /// Mirrors [TrajectoryHarness.enqueue]'s accepting postures — `down` counts
  /// as accepting because records enqueued before the claim drain after it
  /// (§1.2 step 2's `_pump()`).
  @override
  bool get accepting => switch (_harness._mode) {
    TrajectoryHarnessMode.down ||
    TrajectoryHarnessMode.live => !_harness._isShutdown,
    _ => false,
  };

  @override
  void enqueue(
    TrajectoryRecord record, {
    DateTime? occurredAt,
    String? seat,
    TrajectoryProvenance provenance = TrajectoryProvenance.observed,
    String? provenanceBasis,
  }) => _harness.enqueue(
    TrajectoryAppendRequest(
      record,
      occurredAt: occurredAt,
      seat: seat,
      provenance: provenance,
      provenanceBasis: provenanceBasis,
    ),
  );
}

/// The tick's read path, serialized on the same lane — and resolved through
/// the harness so a reconnect's fresh session is picked up, never a stale
/// captured one.
final class _SerializedDb implements TrajectoryDb {
  _SerializedDb(this._harness);

  final TrajectoryHarness _harness;

  @override
  Future<SqlResult> execute(String sql, [Map<String, dynamic>? params]) =>
      _harness._serialize(() {
        final db = _harness._db;
        if (db == null) {
          throw StateError('trajectory connection is closed');
        }
        return db.execute(sql, params);
      });

  @override
  Future<void> close() async {
    // The harness owns the real session's lifecycle; the tick never closes it.
  }
}
