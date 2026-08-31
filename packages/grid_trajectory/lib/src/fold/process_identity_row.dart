/// One in-memory image of a `proj_process_identity` row — P6, live
/// leases/fences/worktrees keyed by `attempt_id` (§6 rows 1/3/10/13/32).
///
/// Column vocabulary is the §4 DDL verbatim; the DDL is the letter. Liveness
/// is deliberately NOT a column here — it reads `traj_pulse`, is `unknown`
/// after restore/epoch-advance, and is never an admission input (§4). The
/// ladder-uniqueness constraint (`uq_incarnation` on session_id, round,
/// step_path, step_round, incarnation) is §3's one-attempt-one-incarnation
/// rule, enforced by this table.
library;

import 'package:meta/meta.dart';

/// One P6 row. Immutable; the fold advances an attempt by [applying] a column
/// map — the SAME column vocabulary the incremental SQL uses, so the two
/// application modes cannot drift on semantics.
@immutable
class ProcessIdentityRow {
  const ProcessIdentityRow({
    required this.attemptId,
    required this.sessionId,
    required this.round,
    required this.stepPath,
    required this.stepRound,
    required this.incarnation,
    required this.lastSeq,
    this.pid,
    this.pgid,
    this.leaseState,
    this.worktree,
    this.branch,
    this.baseSha,
    this.adoptedExisting,
    this.worktreeState,
    this.predecessorAttemptId,
  });

  final String attemptId;
  final String sessionId;
  final int round;
  final String stepPath;
  final int stepRound;
  final int incarnation;
  final int? pid;
  final int? pgid;

  /// The §4 ENUM wire string — held/released/swept.
  final String? leaseState;
  final String? worktree;
  final String? branch;
  final String? baseSha;
  final bool? adoptedExisting;

  /// The §4 ENUM wire string — live/reaped/held.
  final String? worktreeState;

  /// Set on a respawn successor — the chain is walkable in both directions.
  final String? predecessorAttemptId;
  final int lastSeq;

  /// The `uq_incarnation` ladder tuple — what the in-memory applier mirrors
  /// the SQL upsert's unique-conflict arm against.
  (String, int, String, int, int) get ladder => (
    sessionId,
    round,
    stepPath,
    stepRound,
    incarnation,
  );

  /// The row with [columns] applied — DDL column names, an EXPLICIT null
  /// value means SET NULL (absent keys are untouched), mirroring the
  /// incremental SQL exactly. Unknown column names throw: a delta naming a
  /// column this row cannot hold is a fold bug, never data.
  ProcessIdentityRow applying(
    Map<String, Object?> columns, {
    required int lastSeq,
  }) {
    var sessionId = this.sessionId;
    var round = this.round;
    var stepPath = this.stepPath;
    var stepRound = this.stepRound;
    var incarnation = this.incarnation;
    var pid = this.pid;
    var pgid = this.pgid;
    var leaseState = this.leaseState;
    var worktree = this.worktree;
    var branch = this.branch;
    var baseSha = this.baseSha;
    var adoptedExisting = this.adoptedExisting;
    var worktreeState = this.worktreeState;
    var predecessorAttemptId = this.predecessorAttemptId;
    for (final entry in columns.entries) {
      final value = entry.value;
      switch (entry.key) {
        case 'session_id':
          sessionId = value! as String;
        case 'round':
          round = value! as int;
        case 'step_path':
          stepPath = value! as String;
        case 'step_round':
          stepRound = value! as int;
        case 'incarnation':
          incarnation = value! as int;
        case 'pid':
          pid = value as int?;
        case 'pgid':
          pgid = value as int?;
        case 'lease_state':
          leaseState = value as String?;
        case 'worktree':
          worktree = value as String?;
        case 'branch':
          branch = value as String?;
        case 'base_sha':
          baseSha = value as String?;
        case 'adopted_existing':
          adoptedExisting = switch (value) {
            null => null,
            final int tinyint => tinyint != 0,
            final bool flag => flag,
            _ => throw ArgumentError(
              'adopted_existing takes TINYINT/bool, got $value',
            ),
          };
        case 'worktree_state':
          worktreeState = value as String?;
        case 'predecessor_attempt_id':
          predecessorAttemptId = value as String?;
        default:
          throw ArgumentError(
            'proj_process_identity has no fold-updatable column ${entry.key}',
          );
      }
    }
    return ProcessIdentityRow(
      attemptId: attemptId,
      sessionId: sessionId,
      round: round,
      stepPath: stepPath,
      stepRound: stepRound,
      incarnation: incarnation,
      pid: pid,
      pgid: pgid,
      leaseState: leaseState,
      worktree: worktree,
      branch: branch,
      baseSha: baseSha,
      adoptedExisting: adoptedExisting,
      worktreeState: worktreeState,
      predecessorAttemptId: predecessorAttemptId,
      lastSeq: lastSeq,
    );
  }

  /// The full-row INSERT parameter map — §4 column names, SQL-typed values
  /// (`adopted_existing` as TINYINT).
  Map<String, Object?> toSqlParams() => {
    'attempt_id': attemptId,
    'session_id': sessionId,
    'round': round,
    'step_path': stepPath,
    'step_round': stepRound,
    'incarnation': incarnation,
    'pid': pid,
    'pgid': pgid,
    'lease_state': leaseState,
    'worktree': worktree,
    'branch': branch,
    'base_sha': baseSha,
    'adopted_existing': adoptedExisting == null
        ? null
        : (adoptedExisting! ? 1 : 0),
    'worktree_state': worktreeState,
    'predecessor_attempt_id': predecessorAttemptId,
    'last_seq': lastSeq,
  };

  @override
  bool operator ==(Object other) =>
      other is ProcessIdentityRow &&
      other.attemptId == attemptId &&
      other.sessionId == sessionId &&
      other.round == round &&
      other.stepPath == stepPath &&
      other.stepRound == stepRound &&
      other.incarnation == incarnation &&
      other.pid == pid &&
      other.pgid == pgid &&
      other.leaseState == leaseState &&
      other.worktree == worktree &&
      other.branch == branch &&
      other.baseSha == baseSha &&
      other.adoptedExisting == adoptedExisting &&
      other.worktreeState == worktreeState &&
      other.predecessorAttemptId == predecessorAttemptId &&
      other.lastSeq == lastSeq;

  @override
  int get hashCode => Object.hash(
    attemptId,
    sessionId,
    round,
    stepPath,
    stepRound,
    incarnation,
    pid,
    pgid,
    leaseState,
    worktree,
    branch,
    baseSha,
    adoptedExisting,
    worktreeState,
    predecessorAttemptId,
    lastSeq,
  );

  @override
  String toString() => 'ProcessIdentityRow(${toSqlParams()})';
}
