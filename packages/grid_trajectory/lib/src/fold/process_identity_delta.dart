/// THE process-identity fold delta — one pure function from an
/// attempt-lifecycle record to its P6 (`proj_process_identity`) effect,
/// shared by BOTH application modes (§6), built to `session_head_delta`'s
/// pattern:
///
///   * **incremental** — [processIdentitySqlFor] renders the delta as the SQL
///     the Stage-1 appender runs inside its append transaction (§5 step 5);
///   * **replay** — `foldProcessIdentities` applies the SAME delta to
///     in-memory rows, then writes them (the §5 rebuild path).
///
/// Per §4's DDL and §6 rows 3/10/13/32:
///   * `attempt.process.started` births (or corrects) the attempt's row —
///     ladder position, incarnation, pid/pgid, predecessor chain;
///   * `attempt.process.exited` clears the live pid/pgid — the row itself is
///     history and stays;
///   * `attempt.lease.acquired/.released/.swept` maintain `lease_state`
///     (acquired ⇒ 'held' — the DDL's ENUM names the held STATE, the record
///     names the acquiring TRANSITION);
///   * `worktree.provisioned` lands worktree/branch/base_sha/adopted and
///     `worktree_state='live'` (row 32's stale-adopt evidence); per-session
///     FIFO can deliver it BEFORE the spawn's `.started`, so it may birth a
///     provisional row when its envelope carries a session — corrected in
///     place by the `.started` that follows;
///   * `worktree.reaped`/`.held` carry session+worktree (no attempt_id), so
///     they advance `worktree_state` on every matching row;
///   * liveness records produce NO P6 delta (liveness reads `traj_pulse`,
///     §4), and `attempt.adopt.proved` adds no column fact — the continued
///     attempt's identity is already the row's (§2.1: no fresh mint on
///     adopt).
library;

import 'package:meta/meta.dart';

import '../codec/codec_registry.dart';
import '../codec/envelope.dart';
import '../codec/trajectory_record.dart';
import 'process_identity_row.dart';
import 'session_head_delta.dart' show SqlStatement;

/// One record's effect on P6.
@immutable
sealed class ProcessIdentityDelta {
  const ProcessIdentityDelta();
}

/// Update-or-create keyed `attempt_id`. The insert arm is the ladder fields
/// plus [columns]; the duplicate arm applies exactly [columns] (+ last_seq).
/// The SQL's ON DUPLICATE KEY UPDATE also absorbs a `uq_incarnation` conflict
/// (two rows may never share a ladder position, §3) — the in-memory applier
/// mirrors that arm so the modes cannot drift.
final class ProcessIdentityUpsert extends ProcessIdentityDelta {
  const ProcessIdentityUpsert({
    required this.attemptId,
    required this.sessionId,
    required this.round,
    required this.stepPath,
    required this.stepRound,
    required this.incarnation,
    required this.columns,
  });

  final String attemptId;
  final String sessionId;
  final int round;
  final String stepPath;
  final int stepRound;
  final int incarnation;
  final Map<String, Object?> columns;

  /// The insert-arm row at [lastSeq].
  ProcessIdentityRow rowAt(int lastSeq) => ProcessIdentityRow(
    attemptId: attemptId,
    sessionId: sessionId,
    round: round,
    stepPath: stepPath,
    stepRound: stepRound,
    incarnation: incarnation,
    lastSeq: lastSeq,
  ).applying(columns, lastSeq: lastSeq);
}

/// A column-map update keyed `attempt_id` — 0 matched rows is a fine outcome
/// (a lease/exit fact for an attempt whose row predates the log), never an
/// error.
final class ProcessIdentityUpdate extends ProcessIdentityDelta {
  const ProcessIdentityUpdate({required this.attemptId, required this.columns});

  final String attemptId;
  final Map<String, Object?> columns;
}

/// A worktree-state write keyed (session_id, worktree) — the reap/hold
/// records carry no attempt_id (§2.3), so the state advances on EVERY row the
/// worktree belongs to.
final class ProcessWorktreeStateUpdate extends ProcessIdentityDelta {
  const ProcessWorktreeStateUpdate({
    required this.sessionId,
    required this.worktree,
    required this.worktreeState,
  });

  final String sessionId;
  final String worktree;

  /// The §4 ENUM wire string — 'reaped' or 'held'.
  final String worktreeState;
}

/// The one delta function. Returns null for every record with no P6 effect —
/// non-attempt families, session-scoped lifecycle records (P1's), liveness
/// (traj_pulse's), mint outcomes (P3's), and adopt proofs (identity already
/// on the row).
///
/// [decoded] short-circuits the codec when the caller already holds the typed
/// record (the Stage-1 appender does); replay decodes from the envelope.
ProcessIdentityDelta? processIdentityDeltaFor(
  TrajectoryEnvelope envelope, {
  TrajectoryRecord? decoded,
}) {
  if (envelope.family != TrajectoryFamily.attempt) return null;
  final record = decoded ?? TrajectoryCodec.decode(envelope);
  switch (record) {
    case AttemptProcessStarted():
      return ProcessIdentityUpsert(
        attemptId: record.attemptId,
        sessionId: record.sessionId,
        // Session-scoped shape when the spawn carries no step key (§2.1: one
        // shape, no special case — step_path '', step_round 0).
        round: record.round ?? 0,
        stepPath: record.stepPath ?? '',
        stepRound: record.stepRound ?? 0,
        incarnation: record.incarnation,
        columns: {
          // The ladder rides the duplicate arm too: a provisional row born by
          // an earlier worktree.provisioned is corrected in place.
          'session_id': record.sessionId,
          'round': record.round ?? 0,
          'step_path': record.stepPath ?? '',
          'step_round': record.stepRound ?? 0,
          'incarnation': record.incarnation,
          'pid': record.pid,
          'pgid': record.pgid,
          if (record.worktree != null) 'worktree': record.worktree,
          if (record.branch != null) 'branch': record.branch,
          if (record.predecessorAttemptId != null)
            'predecessor_attempt_id': record.predecessorAttemptId,
        },
      );
    case AttemptProcessExited():
      // The live process identity clears; the row (ladder, lease, worktree
      // history) stays — P6 is identity, not liveness.
      return ProcessIdentityUpdate(
        attemptId: record.attemptId,
        columns: const {'pid': null, 'pgid': null},
      );
    case AttemptLeaseTransition():
      return ProcessIdentityUpdate(
        attemptId: record.attemptId,
        columns: {
          'lease_state': switch (record.phase) {
            LeasePhase.acquired => 'held',
            LeasePhase.released => 'released',
            LeasePhase.swept => 'swept',
          },
        },
      );
    case WorktreeProvisioned():
      final columns = <String, Object?>{
        'worktree': record.worktree,
        'branch': record.branch,
        'base_sha': record.baseSha,
        'adopted_existing': record.adoptedExisting,
        'worktree_state': 'live',
      };
      final sessionId = record.sessionId;
      if (sessionId == null) {
        // No session on the envelope ⇒ the NOT NULL insert arm has no
        // values: update-only, 0 rows fine.
        return ProcessIdentityUpdate(
          attemptId: record.attemptId,
          columns: columns,
        );
      }
      return ProcessIdentityUpsert(
        attemptId: record.attemptId,
        sessionId: sessionId,
        // Provisional ladder from the envelope where carried (the record's
        // correlation omits it); the spawn's `.started` corrects it.
        round: envelope.round ?? 0,
        stepPath: envelope.stepPath ?? '',
        stepRound: envelope.stepRound ?? 0,
        incarnation: envelope.incarnation ?? 0,
        columns: columns,
      );
    case WorktreeReaped():
      return ProcessWorktreeStateUpdate(
        sessionId: record.sessionId,
        worktree: record.worktree,
        worktreeState: 'reaped',
      );
    case WorktreeHeld():
      return ProcessWorktreeStateUpdate(
        sessionId: record.sessionId,
        worktree: record.worktree,
        worktreeState: 'held',
      );
    // No P6 columns exist for these (the DDL is the letter): session-scoped
    // lifecycle is P1's, mint outcomes P3's, liveness traj_pulse's, notes
    // nobody's; adopt.proved continues an attempt whose identity the row
    // already carries.
    case AttemptSessionStarted() ||
        AttemptTerminal() ||
        AttemptRoundRetired() ||
        AttemptReworkDeclined() ||
        AttemptLivenessTransition() ||
        AttemptAdoptProved() ||
        AttemptMintOutcome() ||
        AttemptNote() ||
        OpaqueRecord():
      return null;
    // Non-attempt families never pass the guard; the exhaustive switch still
    // needs the arms.
    case AdmissionRecord() ||
        VerificationRecord() ||
        EffectRecord() ||
        StepRecord():
      return null;
  }
}

/// The §4 `proj_process_identity` column list an insert writes, in DDL order.
const List<String> _insertColumns = [
  'attempt_id',
  'session_id',
  'round',
  'step_path',
  'step_round',
  'incarnation',
  'pid',
  'pgid',
  'lease_state',
  'worktree',
  'branch',
  'base_sha',
  'adopted_existing',
  'worktree_state',
  'predecessor_attempt_id',
  'last_seq',
];

/// Renders [delta] as the SQL the Stage-1 appender runs inside its append
/// transaction (§5 step 5). [lastSeq] is the just-assigned `trajectory.seq`.
SqlStatement processIdentitySqlFor(
  ProcessIdentityDelta delta, {
  required int lastSeq,
}) {
  switch (delta) {
    case ProcessIdentityUpsert():
      final params = delta.rowAt(lastSeq).toSqlParams();
      final duplicateSets = [
        for (final column in delta.columns.keys) '$column = :$column',
        'last_seq = :last_seq',
      ];
      return (
        sql:
            'INSERT INTO proj_process_identity '
            '(${_insertColumns.join(', ')}) '
            'VALUES (${_insertColumns.map((c) => ':$c').join(', ')}) '
            'ON DUPLICATE KEY UPDATE ${duplicateSets.join(', ')}',
        params: params,
      );
    case ProcessIdentityUpdate():
      final params = <String, Object?>{
        for (final entry in delta.columns.entries)
          entry.key: switch (entry.value) {
            final bool flag => flag ? 1 : 0,
            final other => other,
          },
        'last_seq': lastSeq,
        'attempt_id': delta.attemptId,
      };
      final sets = [
        for (final column in delta.columns.keys) '$column = :$column',
        'last_seq = :last_seq',
      ];
      return (
        sql:
            'UPDATE proj_process_identity SET ${sets.join(', ')} '
            'WHERE attempt_id = :attempt_id',
        params: params,
      );
    case ProcessWorktreeStateUpdate():
      return (
        sql:
            'UPDATE proj_process_identity '
            'SET worktree_state = :worktree_state, last_seq = :last_seq '
            'WHERE session_id = :session_id AND worktree = :worktree',
        params: {
          'worktree_state': delta.worktreeState,
          'last_seq': lastSeq,
          'session_id': delta.sessionId,
          'worktree': delta.worktree,
        },
      );
  }
}

/// Applies [delta] to the in-memory [rows] (keyed by attempt_id) — the replay
/// mode's applier, with EXACTLY the incremental SQL's semantics:
///
/// * an upsert creates the row, advances exactly its carried columns on a PK
///   hit — or, mirroring ON DUPLICATE KEY UPDATE's unique-conflict arm,
///   advances the row its insert arm would collide with on `uq_incarnation`;
/// * an update for an absent attempt matches 0 rows and does nothing;
/// * a worktree-state write advances every (session, worktree) match.
void applyProcessIdentityDelta(
  Map<String, ProcessIdentityRow> rows,
  ProcessIdentityDelta delta, {
  required int lastSeq,
}) {
  switch (delta) {
    case ProcessIdentityUpsert():
      final existing = rows[delta.attemptId];
      if (existing != null) {
        rows[delta.attemptId] = existing.applying(
          delta.columns,
          lastSeq: lastSeq,
        );
        return;
      }
      final inserted = delta.rowAt(lastSeq);
      for (final entry in rows.entries) {
        if (entry.value.ladder == inserted.ladder) {
          // The uq_incarnation arm: the conflicting row absorbs the update —
          // never a fold failure inside the append transaction.
          rows[entry.key] = entry.value.applying(
            delta.columns,
            lastSeq: lastSeq,
          );
          return;
        }
      }
      rows[delta.attemptId] = inserted;
    case ProcessIdentityUpdate():
      final row = rows[delta.attemptId];
      if (row == null) return;
      rows[delta.attemptId] = row.applying(delta.columns, lastSeq: lastSeq);
    case ProcessWorktreeStateUpdate():
      for (final entry in rows.entries.toList()) {
        if (entry.value.sessionId != delta.sessionId ||
            entry.value.worktree != delta.worktree) {
          continue;
        }
        rows[entry.key] = entry.value.applying({
          'worktree_state': delta.worktreeState,
        }, lastSeq: lastSeq);
      }
  }
}
