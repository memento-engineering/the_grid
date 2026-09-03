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
    show
        Died,
        Exited,
        LastActivityPoll,
        RuntimeEvent,
        SessionStarted,
        StationTrajectoryRecorder,
        StuckObligationAccountant,
        TrajectoryRecordSink,
        buildStage1ObligationQueries;
import 'package:grid_engine/grid_engine.dart'
    show
        DualReadMode,
        TerminalReconcileOutcome,
        TerminalReconcileRequest,
        TrajectoryHeadSnapshot,
        TrajectoryStepSnapshot;
import 'package:grid_trajectory/grid_trajectory.dart';
import 'package:meta/meta.dart';
import 'package:state_notifier/state_notifier.dart' show RemoveListener;

import 'session_head_mirror.dart';
import 'step_cursor_mirror.dart';
import 'trajectory_config.dart';

/// The flare seam — shape-compatible with `ExplorationTransport.flare`.
typedef TrajectoryFlare = void Function(String name, Map<String, String> data);

/// The one database the harness dials — `CREATE DATABASE trajectory` beside
/// the ledger database (runbook step 2).
const String kTrajectoryDatabase = 'trajectory';

/// The floor between eager-reconnect ATTEMPTS (§3's `AppendInternalError`
/// row, hardened): the reconnect stays eager — the first append after a
/// failure tries — but with the server down and a filled queue, retrying the
/// whole resolve+dial per queued record would storm the filesystem and the
/// dead listener up to `queueBound` times per drain. Appends inside the
/// window drop-and-count exactly like a failed reconnect.
const Duration kReconnectDebounce = Duration(seconds: 5);

/// One derived record awaiting the single writer (§2.5). Constructed by the
/// engine-side derivation layer, never by the harness — the extraction
/// boundary keeps record vocabulary out of the mechanics.
@immutable
final class TrajectoryAppendRequest {
  const TrajectoryAppendRequest(
    this.record, {
    this.occurredAt,
    this.substation,
    this.provenance = TrajectoryProvenance.observed,
    this.provenanceBasis,
  });

  final TrajectoryRecord record;

  /// The observation instant (§2.2); null lets the appender stamp now.
  final DateTime? occurredAt;

  /// Recorder-derived substation (§2.2); null falls back to the appender's
  /// prefix derivation.
  final String? substation;

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
    this.exitJoinGaps = 0,
    this.refusedTestimony = 0,
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

  /// Runtime-event exit joins the subscriber REFUSED rather than derived a
  /// wrong record from: a pid mismatch under a reused session name, or a
  /// start that overwrote a live entry whose exit never arrived. Zero is the
  /// healthy read; a non-zero one names the stop-races-spawn gap class, whose
  /// terminals the tick's unknown-terminal settlement settles.
  final int exitJoinGaps;

  /// Reconstructed terminals the appender refused because the attempt's REAL
  /// terminal had already landed (cut-wiring §0.3's TESTIMONY YIELDS TO
  /// OBSERVATION). Benign by construction — the refused record would have been
  /// redundant — but counted, because the round summary reports it and a
  /// rising count means the heal is racing something it should not be.
  final int refusedTestimony;

  @override
  String toString() =>
      'TrajectoryHarnessStatus(${mode.name}'
      '${cause == null ? '' : ' ($cause)'}, epoch: $epoch, '
      'appended: $appended, deduped: $deduped, dropped: $dropped, '
      'suppressed: $suppressed, queue: $queueDepth'
      '${exitJoinGaps == 0 ? '' : ', exitJoinGaps: $exitJoinGaps'}'
      '${refusedTestimony == 0 ? '' : ', refusedTestimony: $refusedTestimony'})';
}

/// The fenced service's station-side owner (stage1-wiring §1.1).
class TrajectoryHarness {
  TrajectoryHarness._({
    required this.config,
    required String gridHome,
    required String station,
    required this.substationPrefixes,
    required TrajectoryFlare? onFlare,
    required Future<TrajectoryDb> Function()? connect,
    required TrajectoryAppender Function(TrajectoryDb db)? appenderFactory,
    required List<ObligationQuery>? tickQueries,
    required LastActivityPoll? lastActivity,
    required Stream<RuntimeEvent>? runtimeEvents,
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
       _lastActivity = lastActivity,
       _runtimeEvents = runtimeEvents,
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
    Set<String> substationPrefixes = const {},
    TrajectoryFlare? onFlare,
    Future<TrajectoryDb> Function()? connect,
    TrajectoryAppender Function(TrajectoryDb db)? appenderFactory,
    List<ObligationQuery>? tickQueries,
    LastActivityPoll? lastActivity,
    Stream<RuntimeEvent>? runtimeEvents,
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
      substationPrefixes: Set<String>.unmodifiable(substationPrefixes),
      onFlare: onFlare,
      connect: connect,
      appenderFactory: appenderFactory,
      tickQueries: tickQueries,
      lastActivity: lastActivity,
      runtimeEvents: runtimeEvents,
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

  /// THE POSTURE, THREADED (cut-wiring, r13). The dual read is a whole-station
  /// posture, not a bridge-local one: under [DualReadMode.off] this harness
  /// must be byte-equivalent to pre-cut mainline, which means the FOLD-SIDE
  /// machinery has to be off too — no mirror seed, no generation re-read, no
  /// post-ACK apply, no boot reshape probe, and no resolving pre-read in the
  /// appender. Gating only the comparator would leave every new SELECT and
  /// every new subscription armed on a station that asked for none of it.
  ///
  /// Read it as ONE predicate everywhere so the arms can never drift apart:
  /// a mirror that seeds but never applies is worse than either posture.
  bool get _dualReadArmed => config.dualRead != DualReadMode.off;

  /// The substation-derivation input (§2.2's substation row) — carried for the
  /// derivation layer; the harness itself never derives a substation.
  final Set<String> substationPrefixes;

  /// The derivation layer (§2) — one of the five things the harness owns
  /// (§1.1). Its sink is THIS harness's bounded queue, so every derived
  /// record rides the single writer loop; under any non-accepting posture
  /// (disabled / unprovisioned / degraded / latched) the recorder is a
  /// counting no-op and no call site ever branches on "is the trajectory up".
  late final StationTrajectoryRecorder recorder = StationTrajectoryRecorder(
    sink: _HarnessRecordSink(this),
    substationPrefixes: substationPrefixes,
    clock: _clock,
    // Derivation-failure flares ride the harness's standing 30 s bucket.
    onFlare: _flareLimited,
  );

  /// Schema §5's stuck-obligation accountant (§2.4 obligation 4), fed by the
  /// tick's per-pass telemetry.
  late final StuckObligationAccountant _accountant = StuckObligationAccountant(
    recorder: recorder,
    station: _station,
    onFlare: _flareLimited,
  );

  final String _gridHome;
  final String _station;
  final TrajectoryFlare? _onFlare;

  /// The connect TEST seam; null selects the default resolve+secret+socket
  /// path in [_openConnection].
  final Future<TrajectoryDb> Function()? _connect;
  final TrajectoryAppender Function(TrajectoryDb db)? _appenderFactory;

  /// An EXPLICIT obligation set (tests, and a station that wants Stage 0's
  /// empty one); null composes the Stage-1 set at [start], once the epoch the
  /// detector's unknown rule keys on has actually been claimed (§2.4).
  final List<ObligationQuery>? _tickQueries;

  /// `RuntimeProvider.lastActivity` — liveness surface (b) of §2.3. Null (no
  /// provider wired, e.g. a dry arm) leaves the worktree mtime scanner
  /// answering alone.
  final LastActivityPoll? _lastActivity;

  /// `RuntimeProvider.events` — §1.1's runtime-event subscriber (harness-
  /// internal): the observation surface for §2.3's `attempt.process.started`
  /// (`SessionStarted`, whose `attemptId` is the breadcrumb-backed field) and
  /// `attempt.process.exited` (`_emitExit`'s two shapes — `Exited`, inferred
  /// or read, and `Died`). Null (no provider wired) derives neither.
  final Stream<RuntimeEvent>? _runtimeEvents;
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

  /// The gc POSTURE latch (tg-3o6b): set when the server refuses `DOLT_GC` on
  /// PRIVILEGE. The service credential is granted `trajectory.*` only by
  /// ratified design (stage1-wiring §4 / r2 minor 15), so a denial is a
  /// standing fact about this home, not a transient failure — the cadence
  /// stops for the process lifetime after ONE flare and reclamation becomes
  /// `traj gc`, run by the operator under the gridboot credential. Never
  /// cleared: nothing this process does can widen its own grant.
  bool _gcDisabled = false;
  bool _needsReconnect = false;

  /// The last eager-reconnect ATTEMPT instant — the debounce anchor
  /// ([kReconnectDebounce]): with the server down and a filled queue, one
  /// resolve+dial per drained record would be a reconnect storm; one per
  /// window is the whole point of "eager" without the storm.
  DateTime? _lastReconnectAttemptAt;

  /// §1.1's runtime-event subscription — opened at [start] once live,
  /// cancelled FIRST in [shutdown].
  StreamSubscription<RuntimeEvent>? _eventsSub;

  /// session name → the identity its `SessionStarted` carried, held so the
  /// exit events can join (§2.1: "exit events join by session name"). A warm
  /// cache; an entry retires on the exit that JOINS it, and the FIFO bound
  /// covers names whose exit was never observed or never matched.
  ///
  /// The NAME is a slot, not an identity: a stop that races a respawn can put
  /// a second process behind it, so a name-only join can attribute one
  /// process's exit to another process's attempt. The stored `pid` is the
  /// discriminator — [_onRuntimeEvent] requires the exit event's pid to match
  /// when the emitter carried one, and refuses the join rather than deriving
  /// a wrong `attempt.process.exited` when it does not.
  final Map<String, ({String attemptId, int pid})> _liveProcesses =
      <String, ({String attemptId, int pid})>{};

  static const int _kLiveProcessBound = 4096;

  /// Exit joins the subscriber REFUSED (§2.1's named-gap class): a pid
  /// mismatch between an exit and the start held under its name, plus a
  /// `SessionStarted` that overwrote a live entry whose exit was never
  /// observed. A plain `/status` counter — nothing here changes what the
  /// station does, and the tick's unknown-terminal settlement owns the rows
  /// these gaps leave behind.
  int _exitJoinGaps = 0;

  final Queue<TrajectoryAppendRequest> _queue =
      Queue<TrajectoryAppendRequest>();
  bool _writerActive = false;
  Future<void> _writerDone = Future<void>.value();

  /// The attempt id of the request the writer loop is CURRENTLY appending —
  /// the hole a queue-only "is an append pending" read would have, because the
  /// loop dequeues before it awaits ([hasQueuedAppendFor]).
  String? _inFlightAttemptId;

  /// The one serial lane every statement on the SQL session rides — the
  /// writer loop, the tick's passes, gc, and the boundary commit never
  /// interleave on the single `mysql_client` session.
  Future<void> _serialTail = Future<void>.value();

  int _appended = 0;
  int _deduped = 0;
  int _dropped = 0;
  int _suppressed = 0;
  int _refusedTestimony = 0;

  final Map<String, DateTime> _lastFlareAt = <String, DateTime>{};

  /// THE P1 MIRROR (cut-wiring C1 / §0.2) — seeded at boot, maintained
  /// POST-ACK, published as immutable versioned snapshots. Nothing consumes it
  /// in C1: the dual-read that reads it is C2's, and until then this is inert
  /// plumbing that changes no behavior.
  final SessionHeadMirror _sessionHeads = SessionHeadMirror();

  /// THE P2 MIRROR (cut-wiring C4 / §0.2) — the step axis's twin of the P1
  /// mirror, on identical terms: seeded at boot from the same serialized
  /// connection, maintained POST-ACK from the same committed envelopes,
  /// re-seeded by the same generation guard, latched by the same health rule.
  /// It carries the FULL P2 column set (r3 — C-m3) so wave-2 design starts
  /// from an honest inventory; wave-1 consumers read only the cursor state.
  final StepCursorMirror _stepCursors = StepCursorMirror();

  /// The reseed guard's watched set: every `proj_meta` row's
  /// `(projection, fold_version, rebuilt_at)` triple as of the seed. The
  /// appender never writes `rebuilt_at` and all three in-tree replays do, so
  /// ANY difference means a replay ran against this store — which
  /// `traj replay` refuses to be. Defense in depth, never a sanctioned path.
  Set<(String, int, DateTime?)>? _foldGenerations;

  /// When the generation set was last READ — the boot seed reads it, so the
  /// boot pass has nothing to re-read. The guard runs at most once per
  /// [TrajectoryConfig.tickInterval], which is the cadence it is specified at
  /// ("re-reads all rows on its existing timer tick"), not once per pass.
  DateTime? _generationsReadAt;

  /// The current P1 snapshot — a plain derived read for the join bridge, the
  /// reconciler, and `/status`.
  TrajectoryHeadSnapshot get sessionHeads => _sessionHeads.snapshot;

  /// The change seam: a fold-side fact re-joins promptly rather than waiting
  /// for the next poll. Returns the remover, house convention.
  RemoveListener onSessionHeadsChanged(
    void Function(TrajectoryHeadSnapshot snapshot) listener, {
    bool fireImmediately = false,
  }) => _sessionHeads.addListener(listener, fireImmediately: fireImmediately);

  /// The current P2 snapshot — the step axis's plain derived read for the join
  /// bridge and `/status`.
  TrajectoryStepSnapshot get stepCursors => _stepCursors.snapshot;

  /// The step axis's change seam, on the same terms as [onSessionHeadsChanged].
  RemoveListener onStepCursorsChanged(
    void Function(TrajectoryStepSnapshot snapshot) listener, {
    bool fireImmediately = false,
  }) => _stepCursors.addListener(listener, fireImmediately: fireImmediately);

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
    exitJoinGaps: _exitJoinGaps,
    refusedTestimony: _refusedTestimony,
  );

  /// The tick, for a status surface's `lastPass` — null until live.
  TrajectoryTick? get tick => _tick;

  /// Obligations currently refusing tick after tick, and how far into schema
  /// §5's N (§2.4 obligation 4) — a plain derived `/status` read.
  Map<String, int> get stuckObligations => _accountant.streaks;

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

      // THE STALE-FOLD REFUSAL (cut-wiring C0, r12) — before the claim,
      // because a boot that will not run must not advance the fence.
      //
      // The wave-1 cut widened `proj_session_head`, and the migration is a
      // named, QUIESCED operator step (`traj replay`), never a boot-time
      // auto-migrate: the reshape DROPs and rebuilds the projection, which is
      // safe only with no writer running. But the boot seed reads `SELECT *`
      // and `SessionHeadRow.fromSqlRow` nulls absent columns, so an
      // un-reshaped home SEEDS CLEAN and reads `live` — and then every single
      // terminal append dies inside its transaction on an unknown column,
      // rolls back whole, and lands as a counted drop behind a rate-limited
      // flare. The trajectory is dead for that home and nothing says why.
      //
      // So: fail CLOSED and LOUD. The harness refuses the live arm, the
      // station runs legacy-only exactly as it does for any other degraded
      // boot, and the cause names the operator action.
      //
      // POSTURE-GATED (r13). The refusal exists to protect the FOLD, and at
      // `off` there is no fold to protect: no mirror seeds, nothing reads
      // `proj_session_head`, and the terminal branch of the delta writes the
      // cut columns only when the projection carries them. Probing anyway
      // would make `off` refuse to arm on every home provisioned before this
      // cut — which is the exact population the rollback is FOR. An existing
      // home upgrading with `off` arms exactly as it does on main.
      if (_dualReadArmed && await sessionHeadProjectionNeedsReshape(db)) {
        _degrade(
          'proj_session_head predates the wave-1 cut shape (missing '
          '${projSessionHeadCutColumns.join(', ')}) — the trajectory refuses '
          'to arm rather than drop every terminal append on an unknown '
          'column. Run the QUIESCED migration first: `traj replay` (station '
          'down), which reshapes the projection and rebuilds it from the log.',
        );
        await _closeDbQuietly();
        return;
      }

      // THE STALE-JOURNAL REFUSAL (tg-j1zn) — the same fail-closed posture as
      // the reshape above, but NOT posture-gated. The P1 refusal protects the
      // FOLD, so `dualRead: off` may skip it; `trajectory.substation` is
      // written by EVERY append at EVERY posture, so an un-migrated home would
      // lose the whole log to an unknown column behind a rate-limited flare.
      // Placed after the P1 probe so the projection probe stays the first
      // statement a boot issues.
      if (await journalNeedsSubstationRename(db)) {
        _degrade(
          'the trajectory journal still carries the pre-tg-j1zn `seat` column '
          '— the trajectory refuses to arm rather than lose every append to '
          'an unknown column. Run the QUIESCED migration first: `traj replay` '
          '(station down), which renames the column and rebuilds the '
          'projections from the log.',
        );
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
        // §2.4: the Stage-1 set is built HERE, after the claim — the liveness
        // detector's unknown rule keys on the epoch this process holds, and
        // there is no such epoch before `claimEpoch` returned.
        queries: _tickQueries ?? _stage1Obligations(),
        interval: config.tickInterval,
        clock: _clock,
        scheduleTimer: _scheduleTimer,
        // Schema §5's N-consecutive-failure accounting reads the pass
        // telemetry; the note it files rides the queue, not the pass.
        // The mirror's guards ride the SAME tick (§0.2: "re-reads all rows on
        // its existing timer tick") rather than arming a timer of their own.
        onPass: _onTickPass,
      );
      // The P1 boot seed (§0.2): ONE SELECT on the serialized connection,
      // after the epoch claim and BEFORE the mode goes live — so no post-ACK
      // delta can ever race ahead of the rows it applies to. Guarded like
      // everything else here: a failed seed refuses the snapshot, it never
      // fails the boot.
      //
      // POSTURE-GATED (r13): at `off` nothing reads the mirrors, so seeding
      // them would be five boot SELECTs (`readFoldLag`,
      // `readProjectionGenerations`, both scans, and the epoch-era read) spent
      // on state no consumer is wired to. The snapshots stay at their
      // never-seeded `refused` health, which is the honest reading.
      if (_dualReadArmed) await _seedSessionHeads();
      _mode = TrajectoryHarnessMode.live;
      _cause = null;
      // §1.1's runtime-event subscriber — armed only once live (a disabled/
      // unprovisioned/degraded harness derives nothing), torn down FIRST at
      // shutdown. Fully guarded: a derivation throw is counted + flared and
      // NEVER reaches the provider's stream (fidelity B1).
      _eventsSub = _runtimeEvents?.listen(_onRuntimeEvent);
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

  /// §2.4's shadow-posture set: unknown-terminal settlement, worktree.reaped
  /// backfill, and the liveness detector. Nothing in it writes bd or the
  /// filesystem — Stage 1 changes NOTHING about what mounts.
  List<ObligationQuery> _stage1Obligations() => buildStage1ObligationQueries(
    recorder: recorder,
    // The tick's own read path: serialized on the harness's one lane and
    // resolved through the harness, so a reconnect's fresh session is picked
    // up rather than a stale captured one.
    db: _SerializedDb(this),
    station: _station,
    // Read per pass, never captured: the epoch is claimed before this list is
    // ever consulted, and a successor claim leaves this process fenced out
    // (the tick skips) rather than reading a stale value.
    bootEpoch: () => _epoch ?? 0,
    lastActivity: _lastActivity,
    livenessThreshold: config.livenessThreshold,
    pulseCoalesce: config.pulseCoalesce,
    clock: _clock,
  );

  // ── the dual read's harness surfaces (cut-wiring C2) ─────────────────────

  /// Is an append for [attemptId] still QUEUED (or mid-flight)?
  ///
  /// The `terminal-reconcile` heal's trigger asks this before it fires (r8 —
  /// V2-B1): every NORMAL terminal transits `terminalLag` briefly because bd
  /// is written first and the record appended after, and a heal that fired
  /// while the real record was still in this queue would race it. The
  /// in-flight request counts too — the writer loop removes it from the queue
  /// BEFORE awaiting the append, so a queue-only read has a real hole.
  bool hasQueuedAppendFor(String attemptId) {
    if (_inFlightAttemptId == attemptId) return true;
    for (final request in _queue) {
      if (_attemptIdOf(request.record) == attemptId) return true;
    }
    return false;
  }

  /// THE HEAL (cut-wiring §C2, r9 — V3-B1's guard contract).
  ///
  /// The append PRECONDITION is a `traj_terminal_guard` check: a terminal row
  /// already existing for the attempt means the real record LANDED and the
  /// head is merely folding — pure lag, so SKIP and count, no append. The
  /// residual check-append race is closed inside the single fenced appender by
  /// TESTIMONY YIELDS TO OBSERVATION (C1's resolving pre-read), so this
  /// pre-check is the cheap arm, never the only one.
  ///
  /// Fire-and-forget, like every other append path: the request's `report` is
  /// how the bridge's tracker learns what happened, and an enqueued append is
  /// reported as attempted — a silent failure afterwards is caught by the
  /// entry SURVIVING one further comparator pass, which is exactly what the
  /// escalation rule keys on.
  void requestTerminalReconcile(TerminalReconcileRequest request) {
    if (_mode != TrajectoryHarnessMode.live || _isShutdown) {
      // Nothing may be appended and nothing was: report a skip rather than a
      // failure, so a down/degraded harness never manufactures an escalation.
      //
      // THE TRANSIENT MEMBER (r13), not `skippedGuard`: no guard row was read
      // here, and this says nothing about the entry — only about the harness
      // at this instant. Reporting it as a guard fact latched the tracker and
      // silently forwent the repair for the rest of the boot.
      request.report(TerminalReconcileOutcome.skippedUnavailable);
      return;
    }
    unawaited(_reconcileTerminal(request));
  }

  Future<void> _reconcileTerminal(TerminalReconcileRequest request) async {
    try {
      final existing = await _serialize(
        () => _requireDb().execute(
          'SELECT attempt_id FROM traj_terminal_guard '
          'WHERE attempt_id = :attempt_id LIMIT 1',
          {'attempt_id': request.attemptId},
        ),
      );
      if (existing.rows.isNotEmpty) {
        request.report(TerminalReconcileOutcome.skippedGuard);
        return;
      }
      recorder.sessionTerminalReconciled(
        sessionId: request.sessionId,
        attemptId: request.attemptId,
        workBeadId: request.workBeadId.isEmpty ? null : request.workBeadId,
        reason:
            'terminal-reconcile: the ledger closed this session and no '
            'terminal record was ever observed for its attempt',
      );
      request.report(TerminalReconcileOutcome.appended);
    } on Object catch (error) {
      request.report(TerminalReconcileOutcome.failed);
      _flareLimited('trajectory.terminalReconcileFailed', {
        'session_id': request.sessionId,
        'attempt_id': request.attemptId,
        'reason': '$error',
      });
    }
  }

  /// One promoted correlation column off a record's CORRELATION map (a column
  /// name), never a concrete record class — the same discipline the append
  /// mechanics keep.
  static String? _correlationOf(TrajectoryRecord record, String column) {
    final value = record.correlationToJson()[column];
    return value is String ? value : null;
  }

  /// The attempt id a record correlates to, or null.
  static String? _attemptIdOf(TrajectoryRecord record) =>
      _correlationOf(record, 'attempt_id');

  /// The `trajectory.appendDropped` payload (tg-kzvs). A drop must name the
  /// SUBJECT it lost, not only the record type: the receipt's flare left an
  /// operator reading the boot log to find which session lost its terminal.
  /// A record carrying neither key simply omits it.
  Map<String, String> _appendDroppedData(
    TrajectoryAppendRequest request,
    String reason,
  ) {
    final record = request.record;
    final sessionId = _correlationOf(record, 'session_id');
    final stepPath = _correlationOf(record, 'step_path');
    return {
      'reason': reason,
      'recordType': record.recordType,
      if (sessionId != null) 'sessionId': sessionId,
      if (stepPath != null) 'stepPath': stepPath,
      'dropped': '$_dropped',
    };
  }

  // ── the fold mirrors (cut-wiring C1 + C4 / §0.2) ─────────────────────────

  /// The boot seed: the lag rule, the generation set, the era boundary, and
  /// one scan EACH of `proj_session_head` (P1) and `proj_step_cursor` (P2) —
  /// all on the serialized connection, both under one verdict.
  ///
  /// The lag rule reads the shared `'fold'` `proj_meta` row ONLY (the
  /// appender's live cursor); the `'step_cursor'`/`'process_identity'` rows
  /// carry a replay-time `applied_seq` frozen where their rebuild left it,
  /// which is not a lag signal. Stale ⇒ health `refused` + one
  /// `trajectory.staleFold` flare, which under wave 1 means legacy-primary for
  /// the boot: loud, never quiet, never boot-blocking, because the incumbent
  /// is still a full oracle.
  Future<void> _seedSessionHeads() async {
    try {
      final lag = await _serialize(
        () => readFoldLag(_requireDb(), clock: _clock),
      );
      final generations = await _serialize(
        () => readProjectionGenerations(_requireDb()),
      );
      final rows = await _serialize(() => scanSessionHeads(_requireDb()));
      // The P2 seed rides the SAME lag verdict, the SAME generation set, and
      // the SAME serialized lane — one boot read, two mirrors. Reading the
      // step rows here rather than on their own pass is what keeps the two
      // snapshots consistent with each other at the instant the mode goes
      // live: a step row can never describe a session the head seed missed.
      final stepRows = await _serialize(() => scanStepCursors(_requireDb()));
      final firstEpochAt = await _serialize(_readFirstEpochClaimedAt);
      _foldGenerations = {for (final row in generations) row.generation};
      _generationsReadAt = _clock();
      final seededAt = _clock().toUtc();
      _sessionHeads.seed(
        rows: rows,
        seededAt: seededAt,
        stale: lag.isStale,
        firstEpochClaimedAt: firstEpochAt,
      );
      _stepCursors.seed(
        rows: stepRows,
        seededAt: seededAt,
        stale: lag.isStale,
        firstEpochClaimedAt: firstEpochAt,
      );
      if (lag.isStale) {
        _flare('trajectory.staleFold', {
          'appliedSeq': '${lag.appliedSeq}',
          'headSeq': '${lag.maxSeq}',
          'records': '${lag.records}',
          'ageMs': '${lag.age.inMilliseconds}',
          'effect':
              'P1/P2 snapshots refused for this boot; legacy stays primary',
        });
      }
    } on Object catch (error) {
      // No seed ⇒ the snapshots stay `refused`, which is the honest reading:
      // nothing may be served from a mirror that never read the fold.
      _flare('trajectory.staleFold', {
        'reason': '$error',
        'effect': 'fold seed failed; snapshots refused, legacy stays primary',
      });
    }
  }

  /// The era boundary the miss classifier splits on: when this station FIRST
  /// claimed an epoch. A session that started before it — or with a null
  /// `startedAt` — is legacy-era, and its missing head is not a defect.
  Future<DateTime?> _readFirstEpochClaimedAt() async {
    final result = await _requireDb().execute(
      'SELECT MIN(advanced_at) AS first_at FROM traj_epoch '
      'WHERE station = :station',
      {'station': _station},
    );
    if (result.rows.isEmpty) return null;
    return parseSqlDateTime6(result.rows.first['first_at']);
  }

  /// The tick's telemetry hook, extended with the mirror's two per-pass
  /// guards. Emit-only, like every flare seam: a throw here never breaks the
  /// tick's loop.
  void _onTickPass(TrajectoryTickPass pass) {
    _accountant.observe(pass);
    // POSTURE FIRST (r13): at `off` the mirrors were never seeded and nothing
    // reads them, so the tick keeps exactly its pre-cut shape — no generation
    // SELECT per interval, no eviction scan, no health latch.
    if (!_dualReadArmed) return;
    // The mode latch (§0.2's wave-1 health): a harness that has left `live`
    // freezes the mirror, and a frozen fold must not keep reading `live`.
    if (_mode != TrajectoryHarnessMode.live) {
      _latchMirrorCompromised('harness mode ${_mode.name}');
      return;
    }
    _evictClosedStepCursors();
    unawaited(_checkFoldGeneration());
  }

  /// P2's EVICTION (§0.2's memory bound), driven off P1: rows for sessions
  /// CLOSED in the head mirror go.
  ///
  /// P1 is the terminality carrier — P2 has no status column — so this is the
  /// only direction the rule can be driven from, and it rides the tick rather
  /// than the writer loop because a scan of the head rows is a per-interval
  /// cost, not a per-append one. Nothing durable is lost: the SQL fold keeps
  /// the whole ladder and `traj replay` rebuilds it.
  void _evictClosedStepCursors() {
    final closed = <String>{
      for (final row in _sessionHeads.snapshot.rows)
        if (!row.isOpen) row.sessionId,
    };
    _stepCursors.evictClosedSessions(closed);
  }

  /// THE FOLD-GENERATION RESEED GUARD (§0.2, r4 — J7-B2): re-reads the full
  /// `proj_meta` row set and re-seeds the mirror when ANY
  /// `(projection, fold_version, rebuilt_at)` triple moved.
  ///
  /// Every in-tree replay stamps `rebuilt_at` and the appender never does, so
  /// a moved triple means a rebuild ran under a live reader. `traj replay` is
  /// QUIESCE-ONLY and refuses while the harness is armed, which makes this the
  /// DETECTOR for an out-of-contract replay — never a licence for one.
  Future<void> _checkFoldGeneration() async {
    final seeded = _foldGenerations;
    if (seeded == null || _mode != TrajectoryHarnessMode.live) return;
    // At most once per tick interval, anchored on the LAST read — which the
    // boot seed performed, so the boot pass re-reads nothing.
    final lastRead = _generationsReadAt;
    if (lastRead != null &&
        _clock().difference(lastRead) < config.tickInterval) {
      return;
    }
    _generationsReadAt = _clock();
    try {
      final generations = await _serialize(
        () => readProjectionGenerations(_requireDb()),
      );
      final current = {for (final row in generations) row.generation};
      if (_setsEqual(current, seeded)) return;
      final rows = await _serialize(() => scanSessionHeads(_requireDb()));
      final stepRows = await _serialize(() => scanStepCursors(_requireDb()));
      _foldGenerations = current;
      final seededAt = _clock().toUtc();
      // BOTH mirrors re-seed on ANY moved triple, deliberately: the guard
      // watches the full `proj_meta` row set precisely because a per-projection
      // replay is expressible, and a mirror left on the old generation while
      // its sibling adopted the new one is two folds in one process.
      _sessionHeads.reseed(rows: rows, seededAt: seededAt);
      _stepCursors.reseed(rows: stepRows, seededAt: seededAt);
      _flare('trajectory.mirrorReseeded', {
        'seeded': _renderGenerations(seeded),
        'observed': _renderGenerations(current),
        'rows': '${rows.length}',
        'stepRows': '${stepRows.length}',
      });
    } on Object catch (error) {
      // A failed generation read is a transient, not a fold fact: flare
      // rate-limited and try again on the next pass.
      _flareLimited('trajectory.mirrorReseedFailed', {'reason': '$error'});
    }
  }

  /// The COMPROMISED latch — one flare on the transition, by the latch.
  ///
  /// BOTH mirrors latch together and the flare fires if EITHER transitioned:
  /// an append that was dropped is a hole in the fold, and which projection
  /// the lost record would have touched is exactly what the harness cannot
  /// know. One station, one health.
  void _latchMirrorCompromised(String reason) {
    // Nothing to compromise at `off`: no mirror was seeded and no reader is
    // wired, so the flare would report a health nobody consults (r13).
    if (!_dualReadArmed) return;
    final head = _sessionHeads.latchCompromised();
    final step = _stepCursors.latchCompromised();
    if (!head && !step) return;
    _flare('trajectory.dualReadCompromised', {
      'reason': reason,
      'dropped': '$_dropped',
      'suppressed': '$_suppressed',
      'effect': 'P1/P2 overlays disengaged for this boot; legacy stays primary',
    });
  }

  TrajectoryDb _requireDb() {
    final db = _db;
    if (db == null) throw StateError('trajectory connection is closed');
    return db;
  }

  static bool _setsEqual(
    Set<(String, int, DateTime?)> a,
    Set<(String, int, DateTime?)> b,
  ) => a.length == b.length && a.containsAll(b);

  static String _renderGenerations(Set<(String, int, DateTime?)> set) {
    final rendered = [
      for (final (projection, version, rebuiltAt) in set)
        '$projection@v$version/${rebuiltAt?.toIso8601String() ?? 'never'}',
    ]..sort();
    return rendered.join(',');
  }

  // ── the runtime-event subscriber (§1.1 / §2.3 rows 2–3) ──────────────────

  /// Derives `attempt.process.started` / `attempt.process.exited` from the
  /// provider's event stream — the harness-internal subscriber §1.1 names.
  ///
  /// Wholly guarded (fidelity B1's law): the recorder's own `_observe` wrap
  /// already contains derivation throws, and this outer catch contains the
  /// subscriber's OWN parsing, so nothing can ever propagate an error into
  /// the provider's broadcast stream (an unhandled listener error would be a
  /// zone error out of the engine's spawn path).
  void _onRuntimeEvent(RuntimeEvent event) {
    try {
      switch (event) {
        case SessionStarted(
          :final name,
          :final pid,
          :final pgid,
          :final attemptId,
        ):
          // An empty attempt id is a spawn outside the engine's allocation
          // path (or pre-Stage-1): the record READS the attempt id, it never
          // invents one (§2.1) — no record, and no exit join either.
          if (attemptId.isEmpty) return;
          // A start overwriting a LIVE entry means the previous process
          // behind this name never had its exit observed — the
          // stop-races-spawn gap. The entry is orphaned either way (the name
          // is the only key the exit events carry), so count it rather than
          // let it vanish: the tick's unknown-terminal settlement is what
          // closes the row it leaves behind.
          if (_liveProcesses.containsKey(name)) _countExitJoinGap('overwrite');
          _liveProcesses[name] = (attemptId: attemptId, pid: pid);
          while (_liveProcesses.length > _kLiveProcessBound) {
            _liveProcesses.remove(_liveProcesses.keys.first);
          }
          // The provider name is `<sessionId>/<nodePath>`
          // (`AllocationAddress.providerName`) — split at the FIRST slash;
          // the step path itself may contain more.
          final slash = name.indexOf('/');
          // `pgid ?? pid` mirrors the spawner's own handle mint
          // (`station_process_transport.dart`: `pgid: pgid ?? pid`).
          recorder.processStarted(
            attemptId: attemptId,
            sessionId: slash <= 0 ? name : name.substring(0, slash),
            stepPath: slash <= 0 ? null : name.substring(slash + 1),
            pid: pid,
            pgid: pgid ?? pid,
          );
        case Exited(:final name, :final exitCode, :final inferred, :final pid):
          final proc = _joinExit(name, pid);
          if (proc == null) return;
          recorder.processExited(
            attemptId: proc.attemptId,
            pid: proc.pid,
            exitKind: ExitKind.exited,
            // `inferred` (the oneTurn vanish) maps to envelope
            // `provenance='inferred'` inside the recorder (§2.3 row 3).
            inferred: inferred,
            sessionId: _sessionIdOf(name),
            exitCode: exitCode,
          );
        case Died(:final name, :final reason, :final pid):
          final proc = _joinExit(name, pid);
          if (proc == null) return;
          recorder.processExited(
            attemptId: proc.attemptId,
            pid: proc.pid,
            exitKind: ExitKind.died,
            inferred: false,
            sessionId: _sessionIdOf(name),
            reason: reason.isEmpty ? null : reason,
          );
        default:
          // `Respawned` has zero production emitters (r2 major 7) and
          // `ActivityChanged` rides the liveness poll, not the log.
          break;
      }
    } on Object catch (error) {
      _flareLimited('trajectory.deriveFailed', {
        'site': 'runtime-events',
        'reason': '$error',
      });
    }
  }

  /// Resolves the start an exit event joins back to, and REFUSES the join
  /// rather than deriving a wrong record.
  ///
  /// The session name is a slot: `_liveProcesses` is keyed by it, but a stop
  /// that races a respawn can put a second process behind the same name, so
  /// the name alone does not prove the exit belongs to the start held under
  /// it. [eventPid] is the discriminator when the emitter carried one —
  /// mismatched, the join is dropped, counted, and flared once per window;
  /// null (an emitter that never learned a pid) means "cannot check", which
  /// is not evidence of a mismatch and joins as before.
  ///
  /// A null return is not an error in either shape: with no `.started`
  /// observed this boot (a prior boot's process, an unattributed spawn) there
  /// is no attempt to key a record on, and the tick's unknown-terminal
  /// settlement owns every terminal these gaps leave unwritten.
  ({String attemptId, int pid})? _joinExit(String name, int? eventPid) {
    final proc = _liveProcesses[name];
    if (proc == null) return null;
    if (eventPid != null && eventPid != proc.pid) {
      // NOT removed: the entry belongs to a process whose own exit may still
      // be coming, and dropping it here would turn one refused join into two.
      _countExitJoinGap('pid-mismatch', expected: proc.pid, observed: eventPid);
      return null;
    }
    _liveProcesses.remove(name);
    return proc;
  }

  void _countExitJoinGap(String reason, {int? expected, int? observed}) {
    _exitJoinGaps += 1;
    _flareLimited('trajectory.exitJoinGap', {
      'reason': reason,
      'gaps': '$_exitJoinGaps',
      if (expected != null) 'expectedPid': '$expected',
      if (observed != null) 'observedPid': '$observed',
    });
  }

  static String _sessionIdOf(String providerName) {
    final slash = providerName.indexOf('/');
    return slash <= 0 ? providerName : providerName.substring(0, slash);
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
        // SUPPRESSION IS NOT A DROP (§0.2, r4 — J6-B3): a fenced-out or
        // halted harness freezes the mirror while `_dropped` never moves, so
        // a drops-only latch would keep serving a frozen fold as `live`.
        _suppressed += 1;
        _latchMirrorCompromised('append suppressed: mode ${_mode.name}');
        return;
      case TrajectoryHarnessMode.down:
      case TrajectoryHarnessMode.live:
        if (_isShutdown) {
          _suppressed += 1;
          _latchMirrorCompromised('append suppressed: shutting down');
          return;
        }
        if (_queue.length >= config.queueBound) {
          _dropped += 1;
          _latchMirrorCompromised('append dropped: queue overflow');
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
    _inFlightAttemptId = _attemptIdOf(request.record);
    try {
      if (_needsReconnect) {
        // Debounced (quality M3): eager on the first append after the
        // failure, then at most one resolve+dial per [kReconnectDebounce]
        // window — never one per queued record. Appends inside the window
        // drop-and-count like any reconnect failure.
        final last = _lastReconnectAttemptAt;
        final debounced =
            last != null && _clock().difference(last) < kReconnectDebounce;
        if (debounced || !await _reconnect()) {
          _dropped += 1;
          _latchMirrorCompromised('append dropped: reconnect');
          _flareLimited(
            'trajectory.appendDropped',
            _appendDroppedData(
              request,
              debounced
                  ? 'reconnect debounced (retry within '
                        '${kReconnectDebounce.inSeconds}s)'
                  : 'reconnect failed; listener re-resolved next attempt',
            ),
          );
          return;
        }
      }
      final outcome = await _serialize(
        () => _appender!.append(
          request.record,
          occurredAt: request.occurredAt,
          substation: request.substation,
          provenance: request.provenance,
          provenanceBasis: request.provenanceBasis,
        ),
      );
      switch (outcome) {
        case Appended(:final envelope, :final seq):
          _appended += 1;
          // POST-ACK, never at enqueue (B-B7): the transaction has COMMITTED,
          // and `seq` is the ordinal that same transaction wrote as
          // `proj_meta.applied_seq` — so the mirror's ordinal is earned.
          //
          // `decoded` short-circuits the codec only when the record provably
          // describes THIS envelope: the appender's resolving pre-read can
          // rebuild a terminal into settling form, and the request still holds
          // the pre-conversion record. Folding that pair would apply the
          // non-settling branch to a settling row — so on any mismatch the
          // envelope decodes itself.
          //
          // POSTURE-GATED (r13): at `off` the mirrors were never seeded, so
          // applying a delta to them would be maintaining a fold nobody reads
          // — one more per-append cost the rollback posture must not pay.
          if (_dualReadArmed) {
            final converted =
                request.record.isSettling !=
                (envelope.resolvesRecordId != null);
            final decoded = converted ? null : request.record;
            _sessionHeads.applyAppended(envelope, seq: seq, decoded: decoded);
            // The step delta rides the SAME acked envelope at the SAME
            // ordinal. It is a second pure fold over one record, never a
            // second write: `stepCursorDeltaFor` returns null for every
            // non-step family, so a session record costs one family check.
            _stepCursors.applyAppended(envelope, seq: seq, decoded: decoded);
          }
        case AppendDeduped():
          // Applies NOTHING: the original row either landed this boot (already
          // applied) or predates it and rode the seed.
          _deduped += 1;
        case AppendRefusedTestimony():
          // Benign and COUNTED (§0.3): the attempt's real terminal already
          // landed, so the refused record has no fold effect to apply and no
          // health consequence — it is not a drop, not a failure, and not a
          // dedupe. Its own counter is what the round summary reports.
          _refusedTestimony += 1;
        case AppendFencedOut(:final reason):
          _latchFencedOut(reason);
        case AppendCorruptionHalt(:final reason):
          _latchHalted(reason);
        case AppendGrantRefused(:final reason):
          // Cannot occur at Stage 1 (no grant-scoped appends) — counted as
          // dropped if it ever does (§3).
          _dropped += 1;
          _latchMirrorCompromised('append dropped: grant refused');
          _flareLimited(
            'trajectory.appendDropped',
            _appendDroppedData(request, reason),
          );
        case AppendInternalError(:final cause):
          // Server hiccup / dead socket: count, flare rate-limited, keep
          // draining, and drive the guarded reconnect eagerly on the next
          // append (§3; M4: a typed ~20 ms outcome, no hang).
          _dropped += 1;
          _needsReconnect = true;
          _latchMirrorCompromised('append failed: $cause');
          _flareLimited(
            'trajectory.appendDropped',
            _appendDroppedData(request, '$cause'),
          );
      }
    } on Object catch (error) {
      // §5's sealed contract says append() never throws — belt and braces: a
      // throw is counted like any dropped append, never an unhandled zone
      // error out of the writer loop.
      _dropped += 1;
      _needsReconnect = true;
      _latchMirrorCompromised('append threw: $error');
      _flareLimited(
        'trajectory.appendDropped',
        _appendDroppedData(request, '$error'),
      );
    } finally {
      _inFlightAttemptId = null;
    }
  }

  /// Guarded reconnect: RE-RESOLVES the listener first (§4's reconnect rule —
  /// bd rewrites the child server's port on its own terms), dials fresh, and
  /// lets the appender's own guard decide resumed vs inert. Runs only in the
  /// writer loop's async context — [_openConnection] suspends before any
  /// filesystem read, so no engine enqueue path ever pays the resolve.
  Future<bool> _reconnect() async {
    _lastReconnectAttemptAt = _clock();
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
          // PUBLISH FIRST, then retire the dead session. `_closeDbQuietly`
          // nulls `_db` and then AWAITS the close, and the tick's read path
          // (`_SerializedDb`) rides the same serial lane this method just
          // yielded — so with the close first, a tick query landing inside
          // that window reads a null `_db` and throws
          // `trajectory connection is closed` against a harness that is in
          // fact healthy. Assigning the fresh handle first leaves no instant
          // where the lane can observe no connection; the close stays
          // guarded, so a refusing dead session still cannot throw here.
          final dead = _db;
          _db = fresh;
          _needsReconnect = false;
          if (dead != null) await _closeQuietly(dead);
          _lastReconnectAttemptAt = null; // a NEW failure retries eagerly
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
  /// guarantee (r2, major 9): NEVER throws AND never hangs, so it can never
  /// block sources shutdown. Every step is individually guarded in the settle
  /// style, and every step that awaits SQL is BOUNDED by
  /// [TrajectoryConfig.shutdownDrainTimeout] — the guarantee covers a wedged
  /// socket, not just a throwing one (quality M2). A throw or an expiry is
  /// caught, counted, and flared as the Stage-0 non-fatal signal class.
  Future<void> shutdown() async {
    if (_isShutdown) return;
    _isShutdown = true;
    _gcTimer?.cancel();
    _gcTimer = null;
    // 0 — the runtime-event subscriber dies first: no new derivations enter
    // the queue while it drains.
    try {
      await _eventsSub?.cancel();
    } on Object {
      // A closed provider stream cancels trivially; belt and braces.
    }
    _eventsSub = null;
    final neverCameUp = _appender == null;
    // 1 (guarded, BOUNDED) — drain the queue, then the fixpoint (§1.2 step
    // 1). A fixpoint not reached rides the outstanding count in the final
    // status flare; the successor boot's tick inherits the remainder. On
    // expiry the queue remainder is counted as dropped (crash-loss physics,
    // §2.5), flared, and shutdown PROCEEDS to dispose — a wedged writer can
    // delay `down` by the timeout, never hold it.
    TrajectoryTickFixpoint? fixpoint;
    var drainTimedOut = false;
    try {
      fixpoint = await runToFixpoint().timeout(config.shutdownDrainTimeout);
    } on TimeoutException {
      drainTimedOut = true;
      _dropped += _queue.length;
      _flare('trajectory.shutdownDrainTimeout', {
        'timeoutMs': '${config.shutdownDrainTimeout.inMilliseconds}',
        'unflushed': '${_queue.length}',
        'dropped': '$_dropped',
      });
      _queue.clear();
    } on Object catch (error) {
      _flare('trajectory.shutdownDrainFailed', {'reason': '$error'});
    }
    // 2 — NO authority.epoch.closed record at Stage 1 (§1.2 step 2): the
    // clean-down receipt is the fixpoint telemetry plus the boundary commit.
    // 3 (guarded, BOUNDED) — force a boundary dolt commit; a throw here is
    // the cadence-failure signal: caught, counted, flared — never propagated.
    // SKIPPED after a drain timeout: the serial lane is wedged, so the commit
    // would queue behind the wedge and only spend a second timeout.
    if (!drainTimedOut) {
      try {
        final appender = _appender;
        if (appender != null) {
          await _serialize(
            appender.doltCommitIfDue,
          ).timeout(config.shutdownDrainTimeout);
        }
      } on Object catch (error) {
        _flare('trajectory.cadenceFailure', {'reason': '$error'});
      }
    }
    try {
      _tick?.dispose();
    } on Object catch (error) {
      _flare('trajectory.shutdownDisposeFailed', {'reason': '$error'});
    }
    // Bounded too: closing a half-open socket can itself hang on the wire.
    try {
      await _closeDbQuietly().timeout(config.shutdownDrainTimeout);
    } on TimeoutException {
      _db = null; // abandoned; the process exit reaps the socket.
    }
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
      'refusedTestimony': '$_refusedTestimony',
      'fixpointReached': '${fixpoint?.reached ?? false}',
      'outstanding': '${fixpoint?.outstanding ?? 0}',
      'unflushed': '${_queue.length}',
    });
  }

  // ── the gc cadence (§1.2 / M2) ───────────────────────────────────────────

  void _armGc() {
    if (_isShutdown || _gcDisabled || _gcTimer != null) return;
    _gcTimer = _scheduleTimer(config.gcInterval, _onGcTimer);
  }

  void _onGcTimer() {
    _gcTimer = null;
    if (_isShutdown) return;
    unawaited(_runGc());
  }

  Future<void> _runGc() async {
    // The latch is checked HERE too, not only in `_armGc`: "disabled" has to
    // mean the collection does not run, whatever fired the callback.
    if (_gcDisabled) return;
    try {
      if (_mode == TrajectoryHarnessMode.live && !_needsReconnect) {
        // Online, ~120 ms, reclaims ~98% — never touches bd's proxy (M2).
        await _serialize(() => _db!.execute('CALL DOLT_GC()'));
      }
    } on Object catch (error) {
      // PRIVILEGE-denied is a posture, not a failure (tg-3o6b): latch, flare
      // ONCE — the latch is what makes it once — and never re-arm. Every
      // other gc error keeps the old flare-and-rearm loop: those are
      // transient and the cadence is how they recover.
      if (isPrivilegeDenied(error)) {
        _gcDisabled = true;
        _flare('trajectory.gcDisabled', {
          'reason': '$error',
          'remedy': 'operator-run `traj gc` (gridboot credential)',
        });
      } else {
        _flareLimited('trajectory.gcFailed', {'reason': '$error'});
      }
    } finally {
      _armGc();
    }
  }

  // ── internals ────────────────────────────────────────────────────────────

  Future<TrajectoryDb> _openConnection() async {
    final connect = _connect;
    if (connect != null) return connect();
    // Suspend BEFORE any filesystem read (quality M3): this method is reached
    // from the writer loop's reconnect (and from boot), and the loop's first
    // iteration runs synchronously on the enqueue caller's stack — an engine
    // hot path. The yield moves the listener re-resolution and the secret
    // read into the writer loop's async context, so no enqueue path ever
    // performs filesystem I/O synchronously (§2.5's non-blocking rule).
    await null;
    // Resolved FRESH on every call — boot and reconnect alike (§4).
    final listener = resolveDoltServerListener(_gridHome);
    final secretFile = io.File(trajectorySecretPath(_gridHome));
    final secret = (await secretFile.readAsString()).trim();
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
    // P1+P2+P6 incremental fold deltas ride every append's transaction. At
    // `off` the P1 entry renders the PRE-CUT column shape, so a home that
    // never ran the quiesced reshape appends exactly as it did on main (r13).
    folds: _dualReadArmed ? kStage1FoldDeltas : kPreCutFoldDeltas,
    // THE RESOLVING PRE-READ IS THE POSTURE'S TOO (r13): it exists to convert
    // a reconstructed terminal into its settling form, and reconstructed
    // terminals are appended only when the dual read is armed. At `off` it
    // would be a pure added in-transaction SELECT on the serialized writer
    // lane, per session terminal, whose answer is structurally always null —
    // so `off` takes the pre-Stage-1 collision semantics instead.
    resolveTerminals: _dualReadArmed,
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
    // The mirror is frozen from here: a successor holds the authority.
    _latchMirrorCompromised('harness fenced out: $reason');
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
    _latchMirrorCompromised('harness halted: $reason');
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
    _latchMirrorCompromised('harness degraded: $cause');
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
    String? substation,
    TrajectoryProvenance provenance = TrajectoryProvenance.observed,
    String? provenanceBasis,
  }) => _harness._serialize(
    () => _appender.append(
      record,
      substation: substation,
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
    String? substation,
    TrajectoryProvenance provenance = TrajectoryProvenance.observed,
    String? provenanceBasis,
  }) => _harness.enqueue(
    TrajectoryAppendRequest(
      record,
      occurredAt: occurredAt,
      substation: substation,
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
