/// The Stage-1 obligation set — stage1-wiring §2.4, mechanically.
///
/// The tick's query list arms per schema §9's amendment: attempt/step-family
/// obligations ONLY, and **during the dual-write window an obligation must
/// never fight a live legacy writer.** The default queries are record-only or
/// legacy-idle repairs:
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
/// A cut owner may additionally supply an [AttemptLivenessLostHandler]. That
/// arms [LivenessLossRecoveryObligation] immediately after the detector. It is
/// the sole optional mutation callback in this set: the tick first durably
/// appends the loss, then invokes the handler for that unresolved loss before
/// advancing to the next query. The default and shadow posture stays
/// record-only.
///
/// **Default/shadow headline property: Stage 1 changes NOTHING about what
/// mounts.** Without the optional cut handler, nothing here writes bd, nothing
/// here writes the filesystem, and no eligibility clause is added. The only
/// writes are trajectory appends (through the tick's fenced appender) and
/// `traj_pulse` UPSERT/DELETE — the dolt_ignore'd working-set table the design
/// gives the detector. The cut handler is explicitly different: after a
/// durable liveness loss it delegates recovery to its station owner.
///
/// The records are built through [StationTrajectoryRecorder]'s builders, which
/// is what keeps the concrete record vocabulary in one library (§2) while the
/// tick keeps ownership of the fenced append (schema §5).
library;

import 'dart:io' as io;

import 'package:grid_trajectory/grid_trajectory.dart';
import 'package:path/path.dart' as p;

import '../git/git_ops.dart' show GateOutcome;
import '../git/station_git_service.dart';
import '../runtime/process_group.dart';
import 'station_trajectory_recorder.dart';
import 'worktree_pulse_scanner.dart';

/// The last-activity poll (`RuntimeProvider.lastActivity`) — liveness surface
/// (b) of §2.3. Keyed by the provider's session name, `<sessionId>/<stepPath>`
/// (`AllocationAddress.providerName`).
typedef LastActivityPoll = DateTime? Function(String providerName);

/// Handles one durable liveness loss for the attempt that still owns an active
/// session cursor.
///
/// Only a cut owner supplies this callback. A thrown error deliberately leaves
/// the durable loss unresolved so the next fenced tick retries it.
typedef AttemptLivenessLostHandler =
    Future<void> Function({
      required String attemptId,
      required String sessionId,
      required String workBeadId,
    });

/// What the LEDGER says about one session bead's closure — the one bd fact the
/// external-close obligation consumes (decision
/// `wave-2-flip-scope-soak-and-kill-date`, Q6: bd remains an input to terminal
/// truth). A null answer from a [SessionClosureProbe] means "open in the
/// ledger, or no snapshot to read yet" — nothing to heal. A session bead the
/// snapshot no longer HOLDS is a different fact ([SessionClosure.absent]): the
/// ledger lost it, and the probe says so rather than folding it into null.
///
/// [closedAt] is the bead's `closed_at` telemetry when the chokepoint stamped
/// one; a hand `bd close` carries none, which is why the obligation keys its
/// grace on its OWN first sighting rather than on this value.
///
/// [outcome] is the terminal outcome the LEDGER's own facts support — derived
/// by the caller from the same bead markers legacy's disposition reads (a
/// human marker ⇒ `escalated`, the engine's DONE marker ⇒ `succeeded`, a void
/// re-key ⇒ `lost`, anything else closed ⇒ `cancelled`), so a head healed from
/// it dispositions under `primary` exactly as the bead does under legacy. Null
/// means the caller could not say, and the heal falls back to
/// `unknown` / `external-close`. [reason] is the ledger's own close reason.
final class SessionClosure {
  const SessionClosure({
    this.closedAt,
    this.outcome,
    this.reason,
    this.retiredRound = false,
  }) : absentFromLedger = false;

  /// The ledger no longer holds this session bead at all (reaped or pruned):
  /// the trajectory's `lost`. Measured 2026-09-14 (tg-6uhz): 280 of 439
  /// candidate heads on one station were absent, and because the probe
  /// answered null for them — "open" — the oldest 64 held the window forever
  /// and the 151 closed heads behind them were never reached.
  const SessionClosure.absent()
    : closedAt = null,
      outcome = TerminalOutcome.lost,
      reason = kLedgerAbsentReason,
      retiredRound = false,
      absentFromLedger = true;

  final DateTime? closedAt;
  final TerminalOutcome? outcome;
  final String? reason;

  /// The ledger closed this bead because its round was RETIRED by rework
  /// (`#rN` key). The fold keeps such heads open by schema design (the round
  /// bump is the retirement); the obligation counts and skips them.
  final bool retiredRound;

  /// The session bead is gone from the state snapshot — see [absent].
  final bool absentFromLedger;
}

/// The [SessionClosure.reason] of an absent head.
const String kLedgerAbsentReason =
    'ledger absent: the session bead is no longer in the state store';

/// The engine-side answer to "is this session bead closed in bd?" — read off
/// the state snapshot the join bridge already holds in memory (one lookup per
/// row per tick, never a bd round trip). Null when the seam is unwired (a
/// bare harness), the bead is open, or there is no snapshot yet; a bead the
/// snapshot does not hold answers [SessionClosure.absent].
typedef SessionClosureProbe = SessionClosure? Function(String sessionId);

/// The harness's answer to "is an append for this attempt, or a terminal for
/// this session, still queued or mid-flight?" The heal must not race a
/// terminal record that is about to land (r8 — V2-B1) — and it must ask by
/// SESSION too, because the head's attempt id is the spawn's while an
/// observed session terminal carries the recorder's per-session id.
typedef AppendQueuedProbe =
    bool Function({required String sessionId, required String? attemptId});

/// Obligation names — stable identifiers for the tick's telemetry and for the
/// stuck-obligation accounting (schema §5).
const String kUnknownTerminalSettlementObligation =
    'unknown-terminal-settlement';
const String kExternalCloseTerminalObligation = 'external-close-terminal';
const String kWorktreeReapedBackfillObligation = 'worktree-reaped-backfill';
const String kLiveWorktreeReapObligation = 'live-worktree-reap';
const String kLivenessDetectorObligation = 'liveness-detector';
const String kLivenessLossRecoveryObligation = 'liveness-loss-recovery';
const String kAdmissionRestorationObligation = 'admission-restoration';

/// How long a ledger-closed session must stay closed-in-bd / open-in-P1 before
/// the external-close obligation appends its reconstructed terminal. Every
/// NORMAL terminal transits that state briefly — bd is written first and the
/// record appended after — so an eager heal would race the real record (r8 —
/// V2-B1). The comparator's heal uses the same 90 s.
const Duration kDefaultExternalCloseGrace = Duration(seconds: 90);

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
///
/// The one row that must NEVER keep its slot is a head whose session bead the
/// ledger no longer holds: it can never change, so the external-close
/// obligation heals it as `lost` after the grace instead of reading it as
/// open (tg-6uhz — 64 reaped heads held the window for a whole epoch).
const int kObligationBatchSize = 64;

/// Resolves the one registered root that strictly contains a P6 worktree.
typedef WorktreeRootSupplier = RootCheckout? Function(String worktreePath);

/// Builds the Stage-1 obligation set, in §2.4's order.
///
/// [bootEpoch] is the CLAIMED epoch of the running process — the detector's
/// unknown rule is written against it (a beat from a prior epoch is not a beat
/// this epoch observed). [lastActivity] is the provider's poll; null (a station
/// with no provider wired, e.g. a dry arm) simply leaves surface (b) silent and
/// the scanner answering alone. [sessionClosure] is the ledger's answer for the
/// external-close obligation; null (unwired) leaves that obligation inert, and
/// [appendQueued] is the harness's in-flight check it consults before healing.
/// [livenessLostHandler] is cut-only. When supplied, the recovery query follows
/// the detector so `TrajectoryTick`'s serial append-before-next-query ordering
/// makes the loss durable before recovery mutates station state.
List<ObligationQuery> buildStage1ObligationQueries({
  required StationTrajectoryRecorder recorder,
  required TrajectoryDb db,
  required String station,
  required int Function() bootEpoch,
  LastActivityPoll? lastActivity,
  SessionClosureProbe? sessionClosure,
  AppendQueuedProbe? appendQueued,
  WorktreePulseScanner scanner = const WorktreePulseScanner(),
  ProcessGroupController? processes,
  Duration livenessThreshold = kDefaultLivenessThreshold,
  Duration pulseCoalesce = kDefaultPulseCoalesce,
  Duration externalCloseGrace = kDefaultExternalCloseGrace,
  DateTime Function()? clock,
  ReapWorktree? reapWorktree,
  WorktreeRootSupplier? worktreeRoot,
  bool admissionRefusalsArmed = false,
  AttemptLivenessLostHandler? livenessLostHandler,
}) {
  final resolvedClock = clock ?? DateTime.now;
  return [
    UnknownTerminalSettlementObligation(
      recorder: recorder,
      station: station,
      processes: processes ?? SystemProcessGroupController(),
    ),
    ExternalCloseTerminalObligation(
      recorder: recorder,
      station: station,
      clock: resolvedClock,
      sessionClosure: sessionClosure,
      appendQueued: appendQueued,
      grace: externalCloseGrace,
    ),
    WorktreeReapedBackfillObligation(recorder: recorder),
    if (reapWorktree != null && worktreeRoot != null)
      LiveWorktreeReapObligation(
        recorder: recorder,
        sessionClosure: sessionClosure,
        reapWorktree: reapWorktree,
        worktreeRoot: worktreeRoot,
      ),
    LivenessDetectorObligation(
      recorder: recorder,
      db: db,
      station: station,
      bootEpoch: bootEpoch,
      lastActivity: lastActivity,
      scanner: scanner,
      threshold: livenessThreshold,
      coalesce: pulseCoalesce,
      clock: resolvedClock,
    ),
    if (livenessLostHandler != null)
      LivenessLossRecoveryObligation(
        handler: livenessLostHandler,
        station: station,
        bootEpoch: bootEpoch,
        threshold: livenessThreshold,
        clock: resolvedClock,
      ),
    // The barrier's restoration half (cut-wiring §W2.4 W2-B item 4), armed on
    // the SAME lever as its refusal: the cut. Under shadow the barrier appends
    // no refusal, so there is nothing for this query to clear and it stays out
    // of the set entirely.
    if (admissionRefusalsArmed)
      AdmissionRestorationObligation(recorder: recorder, station: station),
  ];
}

/// The worktree-outstanding barrier's RESTORATION (cut-wiring §W2.4 W2-B).
///
/// The barrier's refusal is appended at the mount boundary, synchronously and
/// fire-and-forget; its restoration cannot be, for one mechanical reason: the
/// `admission.restored` key is
/// `restored:<bead>:<clause>:<refusal_record_id>` and the refusal's record id
/// is minted INSIDE the appender, so the observation site never learns it. The
/// query below is the path that does — it reads the refusal row it clears, so
/// the record id is a column rather than an invention.
///
/// **Keyed on the external state it repairs** (schema §5's invariant): the
/// refusal stands while P6 still shows a live worktree under any session of
/// the bead, and clears the moment the tick reap flips that row to `reaped`
/// (or evicts it). Nothing here writes P6.
///
/// Only the LATEST refusal per (bead, clause) is restored: the level-shaped
/// key means an episode of refusals is a ladder of revisions, and P3's clause
/// level derives from the latest refusal/restore PAIR — restoring every
/// superseded rung would add rows that no level reads.
final class AdmissionRestorationObligation extends ObligationQuery {
  AdmissionRestorationObligation({
    required StationTrajectoryRecorder recorder,
    required String station,
    this.clause = kWorktreeOutstandingClause,
    this.batch = kObligationBatchSize,
  }) : _recorder = recorder,
       _station = station;

  final StationTrajectoryRecorder _recorder;
  final String _station;

  /// The refusal clause this obligation clears — the barrier's, never the
  /// authority's Stage-3 clause family.
  final String clause;
  final int batch;

  @override
  String get name => kAdmissionRestorationObligation;

  @override
  Map<String, Object?> get parameters => {
    'station': _station,
    'clause': clause,
  };

  @override
  String get sql =>
      'SELECT r.record_id AS record_id, r.work_bead_id AS work_bead_id '
      'FROM trajectory r '
      "WHERE r.record_type = 'admission.refused' "
      'AND r.station = :station '
      'AND r.work_bead_id IS NOT NULL '
      "AND JSON_UNQUOTE(JSON_EXTRACT(r.payload, '\$.clause')) = :clause "
      // Not already cleared.
      'AND NOT EXISTS (SELECT 1 FROM trajectory s '
      "WHERE s.record_type = 'admission.restored' "
      'AND s.resolves_record_id = r.record_id) '
      // Not superseded by a later refusal of the same bead on the same clause.
      'AND NOT EXISTS (SELECT 1 FROM trajectory n '
      "WHERE n.record_type = 'admission.refused' "
      'AND n.work_bead_id = r.work_bead_id AND n.seq > r.seq '
      "AND JSON_UNQUOTE(JSON_EXTRACT(n.payload, '\$.clause')) = :clause) "
      // THE EXTERNAL STATE: no live worktree left under any session of the
      // bead. P6 carries no work-bead column, so this is the same
      // P6 → P1 → work_bead_id join the clause evaluates in memory.
      'AND NOT EXISTS (SELECT 1 FROM proj_process_identity p '
      'JOIN proj_session_head h ON h.session_id = p.session_id '
      'WHERE h.work_bead_id = r.work_bead_id '
      "AND p.worktree_state = 'live' AND p.worktree IS NOT NULL) "
      'ORDER BY r.seq LIMIT $batch';

  @override
  Future<List<ObligationAppend>> repair(List<Map<String, String?>> rows) async {
    final appends = <ObligationAppend>[];
    final seen = <String>{};
    for (final row in rows) {
      final recordId = row['record_id'];
      final workBeadId = row['work_bead_id'];
      if (recordId == null || workBeadId == null) continue;
      if (!seen.add(recordId)) continue;
      final derived = _recorder.buildAdmissionRestored(
        workBeadId: workBeadId,
        clause: clause,
        refusalRecordId: recordId,
      );
      appends.add(
        ObligationAppend(derived.record, substation: derived.substation),
      );
    }
    return appends;
  }
}

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
  ///
  /// **`t.provenance != 'reconstructed'` — the SETTLEMENT EXCLUSION** (r9 —
  /// V3-B2, re-keyed off the IMMUTABLE RECORD after r7's head-column form was
  /// found displaceable). A reconstructed unknown is final testimony: the
  /// teardown-replay append and the `terminal-reconcile` heal both write one
  /// about a terminal this station never observed, and settling it would
  /// probe a long-dead pid, call it `settled`, and read `done` on a session
  /// nobody finished. Keying the exclusion on the record — not on the head's
  /// mutable `terminal_provenance` mark — makes it PERMANENT: truth
  /// monotonicity clears that mark when a real observed terminal lands, and
  /// with a head-keyed exclusion the stale reconstructed RECORD would be
  /// re-exposed and clobber the observed outcome back to `settled`.
  @override
  String get sql =>
      'SELECT t.record_id AS record_id, t.attempt_id AS attempt_id, '
      't.session_id AS session_id, t.work_bead_id AS work_bead_id, '
      't.unknown_reason AS unknown_reason, p.pid AS pid, '
      'p.worktree AS worktree '
      'FROM trajectory t '
      "JOIN traj_terminal_guard g ON g.subject_kind = 'attempt' "
      'AND g.subject_id = t.attempt_id '
      'LEFT JOIN proj_process_identity p ON p.attempt_id = t.attempt_id '
      "WHERE t.record_type = 'attempt.terminal' AND t.outcome = 'unknown' "
      "AND t.provenance != 'reconstructed' "
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
          substation: derived.substation,
          provenance: TrajectoryProvenance.inferred,
          provenanceBasis: kTickUnknownSettlementBasis,
        ),
      );
    }
    return appends;
  }
}

/// The external-close obligation (tg-ffl6; decision
/// `wave-2-flip-scope-soak-and-kill-date`, Q6) — every session bead the LEDGER
/// closed gets exactly one `attempt.terminal`, whatever the dual-read posture.
///
/// This is the `terminal-reconcile` heal, RE-HOMED. On main the heal fires only
/// from the comparator's `terminalLag` tracker, which exists only under
/// `DualReadMode.observe`/`primary`; at the default `off` posture no externally
/// closed session ever gets a terminal, and lunar carried 267 of them. The
/// obligation keys on the projection instead: an OPEN P1 head whose attempt has
/// no `traj_terminal_guard` row is "no terminal ever landed", and the ledger's
/// closure — read through [SessionClosureProbe] off the in-memory state
/// snapshot, never a bd round trip — is the external half schema §5 demands.
///
/// Three guards keep it from racing the real record:
///
///   * a row is healed only after it has read closed-in-bd / open-in-P1 for
///     [grace] measured from this obligation's OWN first sighting (bd is
///     written first and the observed terminal appended after, so every
///     normal terminal transits this state briefly);
///   * a queued or in-flight append for the attempt ([AppendQueuedProbe])
///     defers the heal to the next pass;
///   * the appender's resolving pre-read refuses the reconstructed record
///     outright if an observed terminal landed between the scan and the
///     append (TESTIMONY YIELDS TO OBSERVATION), and the record's idem key is
///     the heal's own (`terminal-reconcile:<attemptId>`), so the comparator's
///     heal and this one dedupe against each other.
///
/// A head with no `attempt_id` predates process start. A second, independently
/// bounded arm sees only those heads; it heals one only when the ledger still
/// holds the session and classifies its close as the void disposition `lost`.
/// Live pre-spawn heads, absent beads, retired rounds, and non-void closes are
/// untouched.
///
/// The bd write this record is ABOUT already happened; nothing here writes bd
/// or the filesystem (the wave-1 invariant). A settled successor is never
/// derived for it: the settlement obligation excludes reconstructed testimony
/// on the record, so the head reads `unknown` until an observed terminal lands
/// and truth monotonicity clears the mark.
final class ExternalCloseTerminalObligation extends ObligationQuery {
  ExternalCloseTerminalObligation({
    required StationTrajectoryRecorder recorder,
    required String station,
    required DateTime Function() clock,
    SessionClosureProbe? sessionClosure,
    AppendQueuedProbe? appendQueued,
    this.grace = kDefaultExternalCloseGrace,
    this.batch = kObligationBatchSize,
  }) : _recorder = recorder,
       _station = station,
       _clock = clock,
       _sessionClosure = sessionClosure,
       _appendQueued = appendQueued;

  final StationTrajectoryRecorder _recorder;
  final String _station;
  final DateTime Function() _clock;
  final SessionClosureProbe? _sessionClosure;
  final AppendQueuedProbe? _appendQueued;
  final Duration grace;
  final int batch;

  /// When each candidate was FIRST seen closed in bd while open in P1 — the
  /// grace clock. An entry leaves when the row heals, or when the ledger reads
  /// the session open again (a reopened bead restarts the wait).
  final Map<String, DateTime> _firstSeenClosed = {};

  /// Heads this boot has already classified as the OPEN-RETIRED shape (Q9):
  /// closed in bd by a round retire, open in the fold by design, never healed
  /// here. They are excluded from the NEXT window's query so the window keeps
  /// advancing (tg-nxov): measured on lunar, 114 retired heads older than every
  /// heal candidate filled the 64-row window on every tick, and the 41
  /// void-rekeyed closes behind them were never reached. In-memory and per
  /// boot on purpose — a fresh boot re-derives it in a couple of ticks, and
  /// nothing durable is written for a head the schema says stays open.
  final Set<String> _skippedRetired = <String>{};

  /// Consecutive passes whose whole window was retired-round skips with no
  /// append — the starvation shape, observable rather than silent.
  int _skipOnlyWindows = 0;
  int get skipOnlyWindows => _skipOnlyWindows;

  /// Rows this obligation declined on its last pass because the ledger still
  /// read them OPEN, and rows still inside [grace] — telemetry for the
  /// operator's "why is this head still open" question.
  int lastOpenInLedger = 0;

  /// Rows whose session bead the snapshot no longer holds — counted APART from
  /// open, because they heal (as `lost`) where an open head waits.
  int lastAbsentInLedger = 0;
  int lastWithinGrace = 0;
  int lastAppendQueued = 0;
  int lastRetiredRound = 0;

  @override
  String get name => kExternalCloseTerminalObligation;

  /// Two independently bounded windows. The first is the existing
  /// attempt-bearing scan. The second admits only never-spawned heads and
  /// excludes session-subject guard rows; the ledger probe narrows that arm to
  /// void closes in [repair].
  @override
  String get sql =>
      'SELECT candidates.session_id AS session_id, '
      'candidates.work_bead_id AS work_bead_id, '
      'candidates.attempt_id AS attempt_id, '
      'candidates.last_seq AS last_seq FROM ('
      '('
      'SELECT h.session_id AS session_id, h.work_bead_id AS work_bead_id, '
      'h.attempt_id AS attempt_id, h.last_seq AS last_seq '
      'FROM proj_session_head h '
      "LEFT JOIN traj_terminal_guard g ON g.subject_kind = 'attempt' "
      'AND g.subject_id = h.attempt_id '
      "WHERE h.status = 'open' AND h.attempt_id IS NOT NULL "
      'AND g.subject_id IS NULL AND h.rig = :station '
      '${_skipClause()}'
      'ORDER BY h.last_seq LIMIT $batch'
      ') UNION ALL ('
      'SELECT h.session_id AS session_id, h.work_bead_id AS work_bead_id, '
      'h.attempt_id AS attempt_id, h.last_seq AS last_seq '
      'FROM proj_session_head h '
      "LEFT JOIN traj_terminal_guard g ON g.subject_kind = 'session' "
      'AND g.subject_id = h.session_id '
      "WHERE h.status = 'open' AND h.attempt_id IS NULL "
      'AND g.subject_id IS NULL AND h.rig = :station '
      '${_skipClause()}'
      'ORDER BY h.last_seq LIMIT $batch'
      ')'
      ') candidates';

  /// `AND h.session_id NOT IN (:skip0, ...)` over [_skippedRetired], empty
  /// until the first retired head is seen. Bound so a pathological store can
  /// never grow the statement without limit; beyond the bound the starvation
  /// counter is the signal.
  static const int _skipBound = 1024;
  List<String> get _skipIds => (_skippedRetired.toList()..sort())
      .take(_skipBound)
      .toList(growable: false);
  String _skipClause() {
    final ids = _skipIds;
    if (ids.isEmpty) return '';
    final marks = [for (var i = 0; i < ids.length; i++) ':skip$i'].join(', ');
    return 'AND h.session_id NOT IN ($marks) ';
  }

  @override
  Map<String, Object?> get parameters => {
    'station': _station,
    for (final (i, id) in _skipIds.indexed) 'skip$i': id,
  };

  @override
  Future<List<ObligationAppend>> repair(List<Map<String, String?>> rows) async {
    final probe = _sessionClosure;
    lastOpenInLedger = 0;
    lastAbsentInLedger = 0;
    lastWithinGrace = 0;
    lastAppendQueued = 0;
    lastRetiredRound = 0;
    // Unwired seam (a bare harness, a test without a state snapshot): the
    // obligation is inert, never a guess. Nothing is healed on no evidence.
    if (probe == null) return const [];
    final appends = <ObligationAppend>[];
    final now = _clock();
    for (final row in rows) {
      final sessionId = row['session_id'];
      final attemptId = row['attempt_id'];
      if (sessionId == null) continue;
      final closure = probe(sessionId);
      if (closure == null) {
        // Open in bd, or no snapshot to read yet: a live round, or a head the
        // ledger has not caught up with. Forget any earlier sighting — a
        // reopened bead restarts the grace.
        _firstSeenClosed.remove(sessionId);
        lastOpenInLedger += 1;
        continue;
      }
      if (closure.absentFromLedger) {
        if (attemptId == null) {
          _firstSeenClosed.remove(sessionId);
          lastAbsentInLedger += 1;
          continue;
        }
        // The ledger LOST this bead (reaped, pruned): nothing will ever close
        // it, so it takes the same grace as a closed bead and heals as `lost`
        // — the only way it leaves the window (tg-6uhz).
        lastAbsentInLedger += 1;
      }
      if (closure.retiredRound) {
        // The fold's own model: a retired round is an open head with its
        // round bumped, not a terminal. Closing it is a schema decision
        // (worksheet E9 / Q9), not a heal — count it and leave it.
        _firstSeenClosed.remove(sessionId);
        _skippedRetired.add(sessionId);
        lastRetiredRound += 1;
        continue;
      }
      if (attemptId == null && closure.outcome != TerminalOutcome.lost) {
        _firstSeenClosed.remove(sessionId);
        continue;
      }
      final firstSeen = _firstSeenClosed.putIfAbsent(sessionId, () => now);
      if (now.difference(firstSeen) < grace) {
        lastWithinGrace += 1;
        continue;
      }
      if (_appendQueued?.call(sessionId: sessionId, attemptId: attemptId) ??
          false) {
        // The real record is about to land; the guard row will exclude this
        // head from the next scan.
        lastAppendQueued += 1;
        continue;
      }
      final closedAt = closure.closedAt;
      final ledgerReason = closure.reason;
      final derived = _recorder.buildTerminalReconciled(
        sessionId: sessionId,
        attemptId: attemptId,
        mintAttemptIfMissing: attemptId != null,
        workBeadId: row['work_bead_id'],
        outcome: closure.outcome ?? TerminalOutcome.unknown,
        reason: attemptId == null
            ? 'terminal-reconcile: the ledger void-closed this pre-spawn '
                  'session before any attempt started'
            : closure.absentFromLedger
            ? 'terminal-reconcile: the ledger no longer holds this session '
                  'bead (absent from the state snapshot) and no terminal '
                  'record was ever observed for its attempt '
                  '(tick obligation, posture-independent)'
            : 'terminal-reconcile: the ledger closed this session'
                  '${closedAt == null ? '' : ' at ${closedAt.toUtc().toIso8601String()}'}'
                  '${ledgerReason == null || ledgerReason.isEmpty ? '' : ' ($ledgerReason)'}'
                  ' and no terminal record was ever observed for its attempt '
                  '(tick obligation, posture-independent)',
      );
      _firstSeenClosed.remove(sessionId);
      appends.add(
        ObligationAppend(
          derived.record,
          substation: derived.substation,
          provenance: TrajectoryProvenance.reconstructed,
          provenanceBasis: kTerminalReconcileBasis,
          // The head's `closed_at` is served under `primary`: it must be the
          // ledger's instant, never the heal's (a backlog heal is days late).
          occurredAt: closedAt,
        ),
      );
    }
    // STARVATION IS A FACT, NOT SILENCE. A window that was nothing but
    // retired-round skips and produced no append is the shape that hid the 41
    // unhealed voids behind 114 skips; with the exclusion above it can only
    // persist past the bound, and then it is said once per streak through the
    // existing stuck-obligation note rather than swallowed.
    if (rows.isNotEmpty && appends.isEmpty && lastRetiredRound == rows.length) {
      _skipOnlyWindows += 1;
      if (_skipOnlyWindows == _skipOnlyWindowsThreshold) {
        _recorder.obligationStuckNoted(
          sessionId: rows.first['session_id']!,
          body:
              'external-close-terminal: $_skipOnlyWindows consecutive windows '
              'of ${rows.length} retired-round skips and no append; '
              '${_skippedRetired.length} retired heads excluded so far '
              '(bound $_skipBound). The heal candidates behind them are not '
              'being reached (tg-nxov).',
        );
      }
    } else {
      _skipOnlyWindows = 0;
    }
    return appends;
  }

  static const int _skipOnlyWindowsThreshold = 3;
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
      if (!seen.add('$sessionId\u0000$worktree')) continue;
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

/// Cut's sole filesystem owner for live P6 worktrees of terminal sessions.
final class LiveWorktreeReapObligation extends ObligationQuery {
  LiveWorktreeReapObligation({
    required StationTrajectoryRecorder recorder,
    required SessionClosureProbe? sessionClosure,
    required ReapWorktree reapWorktree,
    required WorktreeRootSupplier worktreeRoot,
    this.batch = kObligationBatchSize,
  }) : _recorder = recorder,
       _sessionClosure = sessionClosure,
       _reapWorktree = reapWorktree,
       _worktreeRoot = worktreeRoot;

  final StationTrajectoryRecorder _recorder;
  final SessionClosureProbe? _sessionClosure;
  final ReapWorktree _reapWorktree;
  final WorktreeRootSupplier _worktreeRoot;
  final int batch;

  @override
  String get name => kLiveWorktreeReapObligation;

  @override
  String get sql =>
      'SELECT p.session_id AS session_id, p.worktree AS worktree, '
      'p.branch AS branch, p.last_seq AS last_seq, h.status AS head_status '
      'FROM proj_process_identity p '
      'LEFT JOIN proj_session_head h ON h.session_id = p.session_id '
      "WHERE p.worktree IS NOT NULL AND p.worktree_state = 'live' "
      'ORDER BY p.last_seq LIMIT $batch';

  @override
  Future<List<ObligationAppend>> repair(List<Map<String, String?>> rows) async {
    final appends = <ObligationAppend>[];
    final seen = <String>{};
    for (final row in rows) {
      final sessionId = row['session_id'];
      final path = row['worktree'];
      if (sessionId == null || path == null) continue;
      if (!seen.add('$sessionId\u0000$path')) continue;
      final terminal =
          row['head_status'] == 'closed' ||
          _sessionClosure?.call(sessionId) != null;
      if (!terminal) continue;

      final diskType = io.FileSystemEntity.typeSync(path, followLinks: true);
      if (diskType == io.FileSystemEntityType.notFound) {
        appends.add(
          ObligationAppend(
            _recorder
                .buildWorktreeReaped(
                  sessionId: sessionId,
                  worktree: path,
                  branch: row['branch'],
                )
                .record,
          ),
        );
        continue;
      }
      if (diskType != io.FileSystemEntityType.directory) {
        throw StateError('live worktree "$path" is not a directory');
      }

      final root = _worktreeRoot(path);
      if (root == null) {
        throw StateError('no registered root contains live worktree "$path"');
      }
      final worktreesRoot = WorktreeLayout.worktreesRoot(root.path);
      if (!isStrictlyUnderDir(worktreesRoot, path)) {
        throw StateError(
          'live worktree "$path" is not strictly under "$worktreesRoot"',
        );
      }
      final beadId = WorktreeLayout.beadIdFromName(p.basename(path));
      if (beadId == null || beadId.isEmpty) {
        throw StateError('live worktree "$path" has no bead-shaped basename');
      }
      final outcome = await _reapWorktree(
        root: root,
        worktree: BeadWorktree(
          beadId: beadId,
          path: path,
          branch: row['branch'] ?? '',
        ),
      );
      appends.add(
        ObligationAppend(
          (outcome.removed
                  ? _recorder.buildWorktreeReaped(
                      sessionId: sessionId,
                      worktree: path,
                      branch: row['branch'],
                    )
                  : _recorder.buildWorktreeHeld(
                      sessionId: sessionId,
                      worktree: path,
                      branch: row['branch'],
                      uncommitted: _gateEvidence(outcome.uncommitted),
                      unpushed: _gateEvidence(outcome.unpushed),
                      stashes: _gateEvidence(outcome.stashed),
                    ))
              .record,
        ),
      );
    }
    return appends;
  }

  static int? _gateEvidence(GateOutcome outcome) => switch (outcome) {
    GateOutcome.clear => 0,
    GateOutcome.present => 1,
    GateOutcome.probeError => null,
  };
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

  /// Every attempt that still owns the unsuperseded running/ready cursor of an
  /// OPEN session of THIS station, with its CURRENT-EPOCH pulse row if it has
  /// one. The epoch predicate is the unknown rule in SQL: a beat stamped by a
  /// prior epoch does not join, so it reads exactly like no beat at all.
  ///
  /// P2, not the P6 lease state, is the liveness authority. Released and swept
  /// process identities remain subjects while their exact attempt identity is
  /// still the active cursor; this is the restart-adoption shape the lease-only
  /// predicate used to silence.
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
      'JOIN proj_step_cursor c ON c.session_id = p.session_id '
      'AND c.round = p.round AND c.step_path = p.step_path '
      'AND c.step_round = p.step_round AND c.incarnation = p.incarnation '
      'AND c.attempt_id = p.attempt_id '
      'JOIN proj_session_head h ON h.session_id = p.session_id '
      'LEFT JOIN traj_pulse u ON u.subject_id = p.attempt_id '
      "AND u.kind = 'attempt' AND u.boot_epoch = :boot_epoch "
      "WHERE h.status = 'open' AND h.rig = :station "
      'AND c.superseded_by_step_round IS NULL '
      "AND c.state IN ('running', 'ready') "
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

/// Recovers a durable liveness loss whose exact attempt still owns an active
/// cursor in an open session.
///
/// This is deliberately a separate query immediately after
/// [LivenessDetectorObligation]. The tick appends the detector's loss before it
/// executes this query. A current-epoch pulse must also be strictly older than
/// [threshold], so an unknown subject or a subject that beat again after its
/// loss stays inert even before a durable `attempt.liveness.regained` lands.
///
/// The handler is sequential and errors are not swallowed: the tick reports
/// its existing query-failure refusal, while the unresolved loss remains
/// eligible on the next pass.
final class LivenessLossRecoveryObligation extends ObligationQuery {
  LivenessLossRecoveryObligation({
    required AttemptLivenessLostHandler handler,
    required String station,
    required int Function() bootEpoch,
    required DateTime Function() clock,
    this.threshold = kDefaultLivenessThreshold,
    this.batch = kObligationBatchSize,
  }) : _handler = handler,
       _station = station,
       _bootEpoch = bootEpoch,
       _clock = clock;

  final AttemptLivenessLostHandler _handler;
  final String _station;
  final int Function() _bootEpoch;
  final DateTime Function() _clock;

  /// The no-pulse interval after which recovery may act.
  final Duration threshold;

  /// Rows per pass, under the shared Stage-1 bound.
  final int batch;

  @override
  String get name => kLivenessLossRecoveryObligation;

  @override
  Map<String, Object?> get parameters => {
    'station': _station,
    'boot_epoch': _bootEpoch(),
    'stale_before': sqlDateTime6(_clock().toUtc().subtract(threshold)),
  };

  @override
  String get sql =>
      'SELECT h.work_bead_id AS work_bead_id, '
      'p.session_id AS session_id, p.attempt_id AS attempt_id '
      'FROM trajectory l '
      'JOIN proj_process_identity p ON p.attempt_id = l.attempt_id '
      'JOIN proj_step_cursor c ON c.session_id = p.session_id '
      'AND c.round = p.round AND c.step_path = p.step_path '
      'AND c.step_round = p.step_round AND c.incarnation = p.incarnation '
      'AND c.attempt_id = p.attempt_id '
      'JOIN proj_session_head h ON h.session_id = p.session_id '
      'JOIN traj_pulse u ON u.subject_id = p.attempt_id '
      "AND u.kind = 'attempt' AND u.boot_epoch = :boot_epoch "
      "WHERE l.record_type = 'attempt.liveness.lost' "
      'AND l.station = :station AND h.rig = :station '
      "AND h.status = 'open' AND h.work_bead_id IS NOT NULL "
      'AND c.superseded_by_step_round IS NULL '
      "AND c.state IN ('running', 'ready') "
      'AND u.beat_at < :stale_before '
      'AND NOT EXISTS (SELECT 1 FROM trajectory n '
      'WHERE n.attempt_id = l.attempt_id AND n.seq > l.seq '
      "AND n.record_type IN ('attempt.liveness.regained', "
      "'attempt.terminal')) "
      'ORDER BY l.seq LIMIT $batch';

  @override
  Future<List<ObligationAppend>> repair(List<Map<String, String?>> rows) async {
    final seen = <String>{};
    for (final row in rows) {
      final attemptId = row['attempt_id'];
      final sessionId = row['session_id'];
      final workBeadId = row['work_bead_id'];
      if (attemptId == null || sessionId == null || workBeadId == null) {
        continue;
      }
      if (!seen.add(attemptId)) continue;
      await _handler(
        attemptId: attemptId,
        sessionId: sessionId,
        workBeadId: workBeadId,
      );
    }
    return const <ObligationAppend>[];
  }
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
