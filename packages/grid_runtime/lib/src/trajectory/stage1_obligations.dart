/// The Stage-1 obligation set — stage1-wiring §2.4, mechanically.
///
/// The tick's query list arms per schema §9's amendment: attempt/step-family
/// obligations ONLY, and **during the dual-write window an obligation must
/// never fight a live legacy writer.** Three queries arm here, all of them
/// record-only or legacy-idle repairs:
///
///   1. [UnknownTerminalSettlementObligation] — `attempt.terminal(unknown)`
///      rows with no settling successor: probe the process table / worktree,
///      append the settling terminal. No legacy counterpart exists; nothing to
///      fight.
///   2. [WorktreeReapedBackfillObligation] — P6 shows a provisioned worktree
///      whose session's P1 row is terminal and whose path is GONE from disk
///      (the legacy reap already ran) but no `worktree.reaped` record landed:
///      append the record. The filesystem action stays legacy-owned.
///   3. [LivenessDetectorObligation] — the pulse beats and their threshold
///      transitions, honouring `unknown` (current-epoch beats only).
///
/// **Headline property, restated where it is enforced: Stage 1 changes NOTHING
/// about what mounts.** Nothing here writes bd, nothing here writes the
/// filesystem, and no eligibility clause is added — the worktree-outstanding
/// barrier, the head re-stamp, and the live reap are CUT-package deliverables
/// (§2.4, r2 blocker 1). The only writes these obligations make are trajectory
/// appends (through the tick's fenced appender) and `traj_pulse` UPSERT/DELETE
/// — the dolt_ignore'd working-set table the design gives the detector.
///
/// The records are built through [StationTrajectoryRecorder]'s builders, which
/// is what keeps the concrete record vocabulary in one library (§2) while the
/// tick keeps ownership of the fenced append (schema §5).
library;

import 'dart:io' as io;

import 'package:grid_trajectory/grid_trajectory.dart';

import '../runtime/process_group.dart';
import 'station_trajectory_recorder.dart';
import 'worktree_pulse_scanner.dart';

/// The last-activity poll (`RuntimeProvider.lastActivity`) — liveness surface
/// (b) of §2.3. Keyed by the provider's session name, `<sessionId>/<stepPath>`
/// (`AllocationAddress.providerName`).
typedef LastActivityPoll = DateTime? Function(String providerName);

/// Obligation names — stable identifiers for the tick's telemetry and for the
/// stuck-obligation accounting (schema §5).
const String kUnknownTerminalSettlementObligation =
    'unknown-terminal-settlement';
const String kWorktreeReapedBackfillObligation = 'worktree-reaped-backfill';
const String kLivenessDetectorObligation = 'liveness-detector';

/// How stale a beat must be before the detector calls the attempt LOST. The
/// house's sustained-stall threshold (`kDefaultWedgeThreshold`), reused
/// deliberately: the two answer the same operator question at the same scale.
const Duration kDefaultLivenessThreshold = Duration(minutes: 10);

/// Beats coalesce per subject (schema §4: `traj_pulse` is `≥30s per subject`),
/// so a 30 s tick does not rewrite the same row on every pass.
const Duration kDefaultPulseCoalesce = Duration(seconds: 30);

/// Rows per obligation pass. A pass is bounded so one storm-sized backlog
/// cannot own the tick; the remainder rides the next pass (and `runToFixpoint`
/// keeps passing while a pass makes progress).
///
/// The windows are ordered oldest-first, so a row a repair declines (a live
/// process, a worktree still on disk) keeps its slot until the world changes.
/// That is the intended shape at Stage 1: both repairs are record-only, so a
/// declined row costs nothing but its place in a 64-wide window, against a
/// station whose whole storm is a handful of concurrent sessions.
const int kObligationBatchSize = 64;

/// Builds the Stage-1 obligation set, in §2.4's order.
///
/// [bootEpoch] is the CLAIMED epoch of the running process — the detector's
/// unknown rule is written against it (a beat from a prior epoch is not a beat
/// this epoch observed). [lastActivity] is the provider's poll; null (a station
/// with no provider wired, e.g. a dry arm) simply leaves surface (b) silent and
/// the scanner answering alone.
List<ObligationQuery> buildStage1ObligationQueries({
  required StationTrajectoryRecorder recorder,
  required TrajectoryDb db,
  required String station,
  required int Function() bootEpoch,
  LastActivityPoll? lastActivity,
  WorktreePulseScanner scanner = const WorktreePulseScanner(),
  ProcessGroupController? processes,
  Duration livenessThreshold = kDefaultLivenessThreshold,
  Duration pulseCoalesce = kDefaultPulseCoalesce,
  DateTime Function()? clock,
}) => [
  UnknownTerminalSettlementObligation(
    recorder: recorder,
    station: station,
    processes: processes ?? SystemProcessGroupController(),
  ),
  WorktreeReapedBackfillObligation(recorder: recorder),
  LivenessDetectorObligation(
    recorder: recorder,
    db: db,
    station: station,
    bootEpoch: bootEpoch,
    lastActivity: lastActivity,
    scanner: scanner,
    threshold: livenessThreshold,
    coalesce: pulseCoalesce,
    clock: clock ?? DateTime.now,
  ),
];

/// §2.4 obligation 1 — settle `attempt.terminal(outcome='unknown')` rows that
/// no settling successor has healed.
///
/// Keyed on EXTERNAL state (schema §5's invariant): the query finds the
/// unsettled unknown terminals, and the repair asks the PROCESS TABLE whether
/// the attempt's process is really gone. A still-live process settles nothing —
/// the obligation stays open and the next tick re-asks, which is exactly what
/// "keyed on the state it repairs" buys.
final class UnknownTerminalSettlementObligation extends ObligationQuery {
  UnknownTerminalSettlementObligation({
    required StationTrajectoryRecorder recorder,
    required String station,
    required ProcessGroupController processes,
    this.batch = kObligationBatchSize,
  }) : _recorder = recorder,
       _station = station,
       _processes = processes;

  final StationTrajectoryRecorder _recorder;
  final String _station;
  final ProcessGroupController _processes;
  final int batch;

  @override
  String get name => kUnknownTerminalSettlementObligation;

  /// The unsettled unknowns of THIS station, oldest first. `settled_by IS
  /// NULL` on the terminal guard is the authority on "no settling successor" —
  /// the appender's settling arm is what fills it (§5 step 4).
  @override
  String get sql =>
      'SELECT t.record_id AS record_id, t.attempt_id AS attempt_id, '
      't.session_id AS session_id, t.work_bead_id AS work_bead_id, '
      't.unknown_reason AS unknown_reason, p.pid AS pid, '
      'p.worktree AS worktree '
      'FROM trajectory t '
      'JOIN traj_terminal_guard g ON g.attempt_id = t.attempt_id '
      'LEFT JOIN proj_process_identity p ON p.attempt_id = t.attempt_id '
      "WHERE t.record_type = 'attempt.terminal' AND t.outcome = 'unknown' "
      'AND g.settled_by IS NULL AND t.station = :station '
      'ORDER BY t.seq LIMIT $batch';

  @override
  Map<String, Object?> get parameters => {'station': _station};

  @override
  Future<List<ObligationAppend>> repair(List<Map<String, String?>> rows) async {
    final appends = <ObligationAppend>[];
    for (final row in rows) {
      final attemptId = row['attempt_id'];
      final sessionId = row['session_id'];
      final recordId = row['record_id'];
      // An unknown terminal always carries attempt_id (the guard is keyed on
      // it) and record_id; a row missing either is not a settlement candidate.
      if (attemptId == null || sessionId == null || recordId == null) continue;
      final pid = int.tryParse(row['pid'] ?? '');
      if (pid != null && _processes.processAlive(pid)) {
        // Still running: the terminal is unknown because the outcome is
        // genuinely not decided yet. Leave the obligation OPEN.
        continue;
      }
      final worktree = row['worktree'];
      final worktreePresent =
          worktree != null && io.Directory(worktree).existsSync();
      final unknownReason = row['unknown_reason'];
      final derived = _recorder.buildSettledTerminal(
        sessionId: sessionId,
        attemptId: attemptId,
        resolvesRecordId: recordId,
        workBeadId: row['work_bead_id'],
        reason:
            'settled by tick probe: '
            '${pid == null ? 'no pid on record' : 'pid $pid gone'}, '
            'worktree ${worktreePresent ? 'present' : 'absent'}'
            '${unknownReason == null ? '' : ' (unknown_reason: $unknownReason)'}',
      );
      appends.add(
        ObligationAppend(
          derived.record,
          seat: derived.seat,
          provenance: TrajectoryProvenance.inferred,
          provenanceBasis: kTickUnknownSettlementBasis,
        ),
      );
    }
    return appends;
  }
}

/// §2.4 obligation 2 — backfill the `worktree.reaped` record the non-atomic
/// crash class lost.
///
/// The legacy inline reap KEEPS RUNNING through the shadow window; this repair
/// never reaps. It appends the record for a reap that demonstrably already
/// happened: P6 still says `live`, P1 says the session is closed, and the path
/// is gone from disk. A path still on disk is the CUT's live-reap obligation,
/// not this one — such a row is skipped and the obligation stays open.
final class WorktreeReapedBackfillObligation extends ObligationQuery {
  WorktreeReapedBackfillObligation({
    required StationTrajectoryRecorder recorder,
    this.batch = kObligationBatchSize,
  }) : _recorder = recorder;

  final StationTrajectoryRecorder _recorder;
  final int batch;

  @override
  String get name => kWorktreeReapedBackfillObligation;

  /// P6's live worktrees under a closed P1 session. `worktree_state` flips to
  /// `reaped` when the record folds, so `= 'live'` IS the "no record landed"
  /// half of the condition, read off the projection the RECORD maintains — the
  /// disk check in [repair] is the external half schema §5 demands.
  @override
  String get sql =>
      'SELECT p.session_id AS session_id, p.worktree AS worktree, '
      'p.branch AS branch, p.last_seq AS last_seq '
      'FROM proj_process_identity p '
      'JOIN proj_session_head h ON h.session_id = p.session_id '
      'WHERE p.worktree IS NOT NULL '
      "AND p.worktree_state = 'live' AND h.status = 'closed' "
      'ORDER BY p.last_seq LIMIT $batch';

  @override
  Future<List<ObligationAppend>> repair(List<Map<String, String?>> rows) async {
    final appends = <ObligationAppend>[];
    // Several attempts of one session share a worktree (an incarnation ladder
    // provisions once): one record per (session, worktree) per pass. The idem
    // key would dedupe the repeat anyway; not appending it keeps the pass's
    // progress count honest.
    final seen = <String>{};
    for (final row in rows) {
      final sessionId = row['session_id'];
      final worktree = row['worktree'];
      if (sessionId == null || worktree == null) continue;
      if (!seen.add('$sessionId $worktree')) continue;
      if (io.Directory(worktree).existsSync()) continue;
      appends.add(
        ObligationAppend(
          _recorder
              .buildWorktreeReaped(
                sessionId: sessionId,
                worktree: worktree,
                branch: row['branch'],
              )
              .record,
          provenance: TrajectoryProvenance.inferred,
          provenanceBasis: kTickReapedBackfillBasis,
        ),
      );
    }
    return appends;
  }
}

/// §2.4 obligation 3 — the liveness detector: beats into `traj_pulse`,
/// threshold transitions into the log.
///
/// **The unknown rule is the load-bearing one** (schema §2 F1, major fix): the
/// detector may emit `lost` ONLY for a subject whose beat it observed within
/// the CURRENT epoch. Every path that empties or ages out the pulse table —
/// restore, rebuild, epoch advance, branch switch, `--force` trap recovery —
/// therefore yields `unknown`, and unknown emits NOTHING. A restored snapshot
/// can never mint terminals for live attempts.
///
/// The two observation surfaces are §2.3's r2 major 11: the worktree `.grid`
/// mtime scan and the provider's `lastActivity` poll. The newer of the two is
/// the beat. (The wedge monitor is NOT a surface here — it reads bead state;
/// and `RuntimeEvent.activityChanged` has no production emitter at all.)
final class LivenessDetectorObligation extends ObligationQuery {
  LivenessDetectorObligation({
    required StationTrajectoryRecorder recorder,
    required TrajectoryDb db,
    required String station,
    required int Function() bootEpoch,
    required DateTime Function() clock,
    this.lastActivity,
    this.scanner = const WorktreePulseScanner(),
    this.threshold = kDefaultLivenessThreshold,
    this.coalesce = kDefaultPulseCoalesce,
    this.batch = kObligationBatchSize,
  }) : _recorder = recorder,
       _db = db,
       _station = station,
       _bootEpoch = bootEpoch,
       _clock = clock;

  final StationTrajectoryRecorder _recorder;
  final TrajectoryDb _db;
  final String _station;
  final int Function() _bootEpoch;
  final DateTime Function() _clock;

  /// Rows per pass — the doc-comment invariant at the top of this file, which
  /// this query previously opted out of silently. Bounding the subject window
  /// also bounds the pass's worktree scan and per-row pulse round-trips.
  final int batch;

  /// Liveness surface (b). Null leaves the scanner answering alone.
  final LastActivityPoll? lastActivity;

  /// Liveness surface (a).
  final WorktreePulseScanner scanner;

  final Duration threshold;
  final Duration coalesce;

  /// attempt_id → whether this detector has already called it lost. In-memory
  /// per boot, and legitimately so: the record's idem key is the observed
  /// crossing (`liveness:<attempt>:<beat µs>:<lost|regained>`), so a restart
  /// that re-emits the same crossing dedupes at the appender rather than
  /// double-counting a flap. FIFO-bounded ([_kLostBound]) so a long-lived
  /// resident cannot accrete it forever: a session's attempts stop appearing
  /// in the query once it closes, and an evicted entry costs at worst one
  /// re-emitted crossing the appender dedupes.
  final Set<String> _lost = <String>{};

  static const int _kLostBound = 4096;

  /// The last pass's scan cost — the in-budget number an operator (and the W7
  /// measurement test) reads.
  WorktreeScanCost? lastScanCost;

  /// Subjects the last pass could not observe at all (the `unknown` state,
  /// counted rather than guessed at).
  int lastUnknownSubjects = 0;

  @override
  String get name => kLivenessDetectorObligation;

  /// Every attempt of an OPEN session of THIS station whose lease is not
  /// released/swept, with its CURRENT-EPOCH pulse row if it has one. The epoch
  /// predicate is the unknown rule in SQL: a beat stamped by a prior epoch
  /// does not join, so it reads exactly like no beat at all.
  ///
  /// Scoped + bounded like its two siblings: `h.rig` is the station name the
  /// mint stamped (§2.2's rig source is `stateSubstation`), so a head row born
  /// without a `.started` (rig NULL) drops out — conservative, since with no
  /// P1 mint the detector could only ever read it `unknown` anyway. `LIMIT` is
  /// the standing per-pass batch bound.
  @override
  String get sql =>
      'SELECT p.attempt_id AS attempt_id, p.session_id AS session_id, '
      'p.step_path AS step_path, p.worktree AS worktree, '
      'u.beat_at AS beat_at '
      'FROM proj_process_identity p '
      'JOIN proj_session_head h ON h.session_id = p.session_id '
      'LEFT JOIN traj_pulse u ON u.subject_id = p.attempt_id '
      "AND u.kind = 'attempt' AND u.boot_epoch = :boot_epoch "
      "WHERE h.status = 'open' AND h.rig = :station "
      "AND (p.lease_state IS NULL OR p.lease_state = 'held') "
      'ORDER BY p.attempt_id LIMIT $batch';

  @override
  Map<String, Object?> get parameters => {
    'boot_epoch': _bootEpoch(),
    'station': _station,
  };

  @override
  Future<List<ObligationAppend>> repair(List<Map<String, String?>> rows) async {
    final now = _clock().toUtc();
    final epoch = _bootEpoch();
    final scan = await scanner.scan([
      for (final row in rows)
        if (row['worktree'] != null) row['worktree']!,
    ]);
    lastScanCost = scan.cost;
    var unknown = 0;

    final appends = <ObligationAppend>[];
    for (final row in rows) {
      final attemptId = row['attempt_id'];
      final sessionId = row['session_id'];
      if (attemptId == null || sessionId == null) continue;

      final worktree = row['worktree'];
      final mtimeBeat = worktree == null ? null : scan.beats[worktree];
      final activityBeat = lastActivity?.call(
        '$sessionId/${row['step_path'] ?? ''}',
      );
      // The newer surface wins; a tie goes to the provider, which observed the
      // process itself rather than a file it wrote.
      final (DateTime?, String?) observed = switch ((activityBeat, mtimeBeat)) {
        (null, null) => (null, null),
        (final DateTime a, null) => (a.toUtc(), kPulseViaRuntime),
        (null, final DateTime m) => (m, kPulseViaWorktreeMtime),
        (final DateTime a, final DateTime m) =>
          m.isAfter(a)
              ? (m, kPulseViaWorktreeMtime)
              : (a.toUtc(), kPulseViaRuntime),
      };
      final observedBeat = observed.$1;
      final storedBeat = _parseServerInstant(row['beat_at']);

      if (observedBeat != null &&
          (storedBeat == null ||
              observedBeat.difference(storedBeat) >= coalesce)) {
        await _upsertPulse(
          subjectId: attemptId,
          epoch: epoch,
          beatAt: observedBeat,
          observedVia: observed.$2!,
        );
      }

      final beat = switch ((observedBeat, storedBeat)) {
        (null, null) => null,
        (final DateTime o, null) => o,
        (null, final DateTime s) => s,
        (final DateTime o, final DateTime s) => o.isAfter(s) ? o : s,
      };
      if (beat == null) {
        // UNKNOWN — no beat observed under this epoch. Emit nothing; a
        // detector that guessed here is exactly the restore-mints-terminals
        // failure the schema's major fix closed.
        unknown += 1;
        continue;
      }

      final stale = now.difference(beat) > threshold;
      while (_lost.length > _kLostBound) {
        _lost.remove(_lost.first);
      }
      if (stale && _lost.add(attemptId)) {
        appends.add(
          ObligationAppend(
            _recorder
                .buildLivenessTransition(
                  attemptId: attemptId,
                  crossing: LivenessCrossing.lost,
                  lastBeatAt: beat,
                  thresholdMs: threshold.inMilliseconds,
                )
                .record,
          ),
        );
      } else if (!stale && _lost.remove(attemptId)) {
        appends.add(
          ObligationAppend(
            _recorder
                .buildLivenessTransition(
                  attemptId: attemptId,
                  crossing: LivenessCrossing.regained,
                  lastBeatAt: beat,
                  thresholdMs: threshold.inMilliseconds,
                )
                .record,
          ),
        );
      }
    }
    lastUnknownSubjects = unknown;
    await _prunePulses();
    return appends;
  }

  /// One row per subject (the §4 PK) — an UPSERT, never history.
  Future<void> _upsertPulse({
    required String subjectId,
    required int epoch,
    required DateTime beatAt,
    required String observedVia,
  }) => _db.execute(
    'INSERT INTO traj_pulse '
    '(subject_id, kind, boot_epoch, beat_at, observed_via) '
    "VALUES (:subject_id, 'attempt', :boot_epoch, :beat_at, :observed_via) "
    'ON DUPLICATE KEY UPDATE boot_epoch = :boot_epoch, beat_at = :beat_at, '
    'observed_via = :observed_via',
    {
      'subject_id': subjectId,
      'boot_epoch': epoch,
      'beat_at': sqlDateTime6(beatAt),
      'observed_via': observedVia,
    },
  );

  /// Schema §4's prune rule: pulse rows DIE when their subject's session
  /// reaches a terminal. `traj_pulse` is `dolt_ignore`'d working-set state, so
  /// this is not a durable write — and it is the only DELETE Stage 1 arms.
  Future<void> _prunePulses() => _db.execute(
    "DELETE FROM traj_pulse WHERE kind = 'attempt' AND subject_id IN ("
    'SELECT p.attempt_id FROM proj_process_identity p '
    'JOIN proj_session_head h ON h.session_id = p.session_id '
    "WHERE h.status = 'closed')",
  );
}

/// `traj_pulse.observed_via` for the provider's activity poll.
///
/// The design's §2.3 prose names this `'provider-activity'`; the §4 DDL ENUM
/// — which is the letter — has no such member, and its `'runtime'` member IS
/// the runtime provider's surface. `'runtime'` it is.
const String kPulseViaRuntime = 'runtime';

/// `traj_pulse.observed_via` for the worktree `.grid` mtime scan.
const String kPulseViaWorktreeMtime = 'worktree-mtime';

/// DATETIME(6) text (no zone) → UTC instant — the appender's own convention
/// (`_parseServerInstant`), applied to the pulse read path.
DateTime? _parseServerInstant(String? value) {
  if (value == null || value.isEmpty) return null;
  return DateTime.parse('${value.replaceFirst(' ', 'T')}Z');
}
