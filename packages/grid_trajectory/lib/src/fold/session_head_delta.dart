/// THE Family-1 fold delta — one pure function from an attempt-lifecycle
/// record to its P1 (`proj_session_head`) effect, shared by BOTH application
/// modes (§6):
///
///   * **incremental** — [sessionHeadSqlFor] renders the delta as the SQL
///     upsert the Stage-1 appender adopts inside its append transaction
///     (§5 step 5);
///   * **replay** — `SessionHeadFold` applies the SAME delta to in-memory
///     rows, then writes them (the §5 rebuild path).
///
/// Per §6 row 1 and the §7 head fields:
///   * `attempt.session.started` INSERTS the row — work_bead_id, rig, model,
///     seat, started_at, round 0, status open;
///   * `attempt.terminal` sets outcome/closed_at/status; a SETTLING terminal
///     (resolves_record_id set) updates OUTCOME ONLY — closed_at stays the
///     original close instant, not the probe's;
///   * `attempt.round.retired` bumps `round`;
///   * `attempt.rework_declined` sets held + reason;
///   * `attempt.process.started`/`.exited` maintain pid/pgid/attempt_id (P1
///     carries no `incarnation` column — §4's DDL is the letter, so the
///     ordinal stays on P6);
///   * worktree/lease/liveness/adopt/mint/note records produce NO P1 delta —
///     their fields are P6's, and P1's DDL carries none of them.
library;

import 'package:meta/meta.dart';

import '../codec/codec_registry.dart';
import '../codec/envelope.dart';
import '../codec/trajectory_record.dart';
import 'session_head_row.dart';

/// One record's effect on P1. Sealed: an insert carries the full mint-time
/// row; an update carries the column map both modes apply verbatim.
@immutable
sealed class SessionHeadDelta {
  const SessionHeadDelta({required this.sessionId});

  final String sessionId;
}

/// `attempt.session.started` — the row is born (last_seq supplied by the
/// applier: replay reads it off the envelope, the Stage-1 appender knows it
/// only after its INSERT assigns `seq`).
final class SessionHeadInsert extends SessionHeadDelta {
  const SessionHeadInsert({
    required super.sessionId,
    required this.workBeadId,
    required this.rig,
    required this.model,
    required this.startedAt,
    required this.headEpoch,
    this.seat,
  });

  final String workBeadId;
  final String rig;
  final String model;
  final String? seat;
  final DateTime startedAt;
  final int headEpoch;

  /// The full mint-time row at [lastSeq].
  SessionHeadRow rowAt(int lastSeq) => SessionHeadRow(
    sessionId: sessionId,
    workBeadId: workBeadId,
    rig: rig,
    model: model,
    seat: seat,
    startedAt: startedAt,
    headEpoch: headEpoch,
    lastSeq: lastSeq,
  );
}

/// A column-map update. [columns] uses §4 DDL names; an EXPLICIT null value
/// means SET NULL. [guardAttemptId] narrows the update to the row whose
/// CURRENT `attempt_id` matches (the process-exited clear must not wipe a
/// successor incarnation's identity) — both modes honour it identically.
final class SessionHeadUpdate extends SessionHeadDelta {
  const SessionHeadUpdate({
    required super.sessionId,
    required this.columns,
    this.guardAttemptId,
  });

  final Map<String, Object?> columns;
  final String? guardAttemptId;
}

/// The one delta function. Returns null for every record with no P1 effect —
/// non-attempt families, session-less records, and the Family-1 types whose
/// facts live on P6 (worktree/lease/liveness/adopt) or P3 (mint) or nowhere
/// in P1's DDL (note).
///
/// [decoded] short-circuits the codec when the caller already holds the typed
/// record (the Stage-1 appender does); replay decodes from the envelope.
SessionHeadDelta? sessionHeadDeltaFor(
  TrajectoryEnvelope envelope, {
  TrajectoryRecord? decoded,
}) {
  if (envelope.family != TrajectoryFamily.attempt) return null;
  final record = decoded ?? TrajectoryCodec.decode(envelope);
  switch (record) {
    case AttemptSessionStarted():
      return SessionHeadInsert(
        sessionId: record.sessionId,
        // P1's work_bead_id is NOT NULL; a session started without a work
        // bead (synthetic/probe) mints an empty-string key rather than no
        // row — §7 pins the value immutable either way.
        workBeadId: record.workBeadId ?? '',
        rig: record.rig,
        model: record.model,
        seat: envelope.seat,
        startedAt: envelope.occurredAt,
        headEpoch: envelope.bootEpoch,
      );
    case AttemptTerminal(:final sessionId?):
      if (record.isSettling) {
        // The settlement chain heals OUTCOME only (§6 row 1 / task letter):
        // the original terminal's closed_at stands.
        return SessionHeadUpdate(
          sessionId: sessionId,
          columns: {'outcome': record.outcome.wire},
        );
      }
      return SessionHeadUpdate(
        sessionId: sessionId,
        columns: {
          'status': SessionHeadStatus.closed.wire,
          'outcome': record.outcome.wire,
          'closed_at': envelope.occurredAt,
          if (record.reason != null) 'work_terminal_reason': record.reason,
        },
      );
    case AttemptRoundRetired():
      return SessionHeadUpdate(
        sessionId: record.sessionId,
        columns: {'round': record.newRound},
      );
    case AttemptReworkDeclined():
      return SessionHeadUpdate(
        sessionId: record.sessionId,
        columns: {'held': 1, 'held_reason': record.reason},
      );
    case AttemptProcessStarted():
      return SessionHeadUpdate(
        sessionId: record.sessionId,
        columns: {
          'pid': record.pid,
          'pgid': record.pgid,
          'attempt_id': record.attemptId,
        },
      );
    case AttemptProcessExited(:final sessionId?):
      // The head's live process identity clears — but ONLY while this attempt
      // still owns it: a respawn successor's `.started` may have already
      // overwritten pid/pgid/attempt_id, and an unguarded clear would wipe
      // the successor. attempt_id itself survives as "last known attempt".
      return SessionHeadUpdate(
        sessionId: sessionId,
        columns: {'pid': null, 'pgid': null},
        guardAttemptId: record.attemptId,
      );
    // No P1 columns exist for these (the DDL is the letter): worktree/lease/
    // liveness/adopt facts are P6's, mint outcomes P3's, notes nobody's.
    case AttemptLivenessTransition() ||
        AttemptLeaseTransition() ||
        AttemptAdoptProved() ||
        AttemptMintOutcome() ||
        AttemptNote() ||
        WorktreeProvisioned() ||
        WorktreeReaped() ||
        WorktreeHeld() ||
        AttemptTerminal() || // terminal without a session_id: nothing to key
        AttemptProcessExited() ||
        OpaqueRecord():
      return null;
    // Non-attempt families carry TrajectoryFamily.attempt never; the guard at
    // the top already returned. The exhaustive switch still needs the arms:
    case AdmissionRecord() || VerificationRecord() || EffectRecord() ||
        StepRecord():
      return null;
  }
}

/// One parameterized SQL statement — the incremental mode's unit.
typedef SqlStatement = ({String sql, Map<String, Object?> params});

/// The §4 `proj_session_head` column list an insert writes, in DDL order.
const List<String> _insertColumns = [
  'session_id',
  'work_bead_id',
  'round',
  'status',
  'outcome',
  'work_terminal_reason',
  'held',
  'held_reason',
  'pgid',
  'pid',
  'attempt_id',
  'rig',
  'model',
  'seat',
  'started_at',
  'closed_at',
  'head_epoch',
  'last_seq',
];

/// Renders [delta] as the SQL the Stage-1 appender runs inside its append
/// transaction (§5 step 5). [lastSeq] is the just-assigned `trajectory.seq`.
///
/// * An insert is an UPSERT whose duplicate arm refreshes `last_seq` ONLY:
///   the §5 at-least-once dedupe can legitimately re-present a
///   `session.started`, and §7 pins every mint-time column immutable.
/// * An update touches exactly the delta's columns plus `last_seq`, guarded
///   by `attempt_id` when the delta says so — 0 matched rows is a fine
///   outcome (out-of-order fact, or a guard miss), never an error.
SqlStatement sessionHeadSqlFor(SessionHeadDelta delta, {required int lastSeq}) {
  switch (delta) {
    case SessionHeadInsert():
      final params = delta.rowAt(lastSeq).toSqlParams();
      return (
        sql:
            'INSERT INTO proj_session_head (${_insertColumns.join(', ')}) '
            'VALUES (${_insertColumns.map((c) => ':$c').join(', ')}) '
            'ON DUPLICATE KEY UPDATE last_seq = :last_seq',
        params: params,
      );
    case SessionHeadUpdate():
      final params = <String, Object?>{
        for (final entry in delta.columns.entries)
          entry.key: switch (entry.value) {
            final DateTime instant => sqlDateTime6(instant),
            final other => other,
          },
        'last_seq': lastSeq,
        'session_id': delta.sessionId,
      };
      final sets = [
        for (final column in delta.columns.keys) '$column = :$column',
        'last_seq = :last_seq',
      ];
      var sql =
          'UPDATE proj_session_head SET ${sets.join(', ')} '
          'WHERE session_id = :session_id';
      if (delta.guardAttemptId != null) {
        sql += ' AND attempt_id = :guard_attempt_id';
        params['guard_attempt_id'] = delta.guardAttemptId;
      }
      return (sql: sql, params: params);
  }
}

/// Applies [delta] to the in-memory [rows] — the replay mode's applier, with
/// EXACTLY the incremental SQL's semantics:
///
/// * insert on an existing key refreshes `last_seq` only (the upsert's
///   duplicate arm);
/// * an update for an absent session matches 0 rows and does nothing (the
///   fold never invents a head from a mid-life record);
/// * a guarded update whose `attempt_id` no longer matches does nothing.
void applySessionHeadDelta(
  Map<String, SessionHeadRow> rows,
  SessionHeadDelta delta, {
  required int lastSeq,
}) {
  switch (delta) {
    case SessionHeadInsert():
      final existing = rows[delta.sessionId];
      rows[delta.sessionId] = existing == null
          ? delta.rowAt(lastSeq)
          : existing.applying(const {}, lastSeq: lastSeq);
    case SessionHeadUpdate():
      final row = rows[delta.sessionId];
      if (row == null) return;
      if (delta.guardAttemptId != null &&
          row.attemptId != delta.guardAttemptId) {
        return;
      }
      // DateTime column values arrive typed here; `applying` stores them
      // typed (the SQL renderer is where DATETIME(6) formatting lives).
      rows[delta.sessionId] = row.applying(delta.columns, lastSeq: lastSeq);
  }
}
