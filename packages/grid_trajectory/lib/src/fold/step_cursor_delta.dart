/// THE Family-5 fold delta — one pure function from a step-transition record
/// to its P2 (`proj_step_cursor`) effect, shared by BOTH application modes
/// (§6), built to `session_head_delta`'s pattern:
///
///   * **incremental** — [stepCursorSqlFor] renders the delta as the SQL the
///     Stage-1 appender runs inside its append transaction (§5 step 5);
///   * **replay** — `foldStepCursors` applies the SAME delta to in-memory
///     rows, then writes them (the §5 rebuild path).
///
/// Per schema §2 F5 / §4 / §6 rows 14–16:
///   * `step.transition` UPSERTs the two-ladder-keyed row — P2 has no mint
///     record, so the FIRST transition on a (session, round, step_path,
///     step_round) key is what births the cursor row, and every later one
///     advances exactly the columns it carries;
///   * **the step_round chain rule** (fatal 4 / audit round 2): EVERY
///     step_round bump writes the PREDECESSOR row's
///     `superseded_by_step_round` — the `step.superseded` record carries the
///     old/new pair explicitly, and a gate-cleared rearm (`cause =
///     'gate_cleared'`, the bumped step_round on the envelope) links
///     `step_round - 1` implicitly, cause on the record's payload (P2 carries
///     no cause column);
///   * gate/molecule records produce NO P2 delta — `gate.*` folds to P4 and
///     `molecule.poured` flattens to `proj_step_edges`, and P2's DDL carries
///     none of their fields.
library;

import 'package:meta/meta.dart';

import '../codec/codec_registry.dart';
import '../codec/envelope.dart';
import '../codec/trajectory_record.dart';
import 'session_head_delta.dart' show SqlStatement;
import 'step_cursor_row.dart';

/// One record's effect on P2. Sealed: an upsert carries the carried-column
/// map (and, on a bump, the implicit chain link); a supersede carries the
/// explicit chain write.
@immutable
sealed class StepCursorDelta {
  const StepCursorDelta({
    required this.sessionId,
    required this.round,
    required this.stepPath,
  });

  final String sessionId;
  final int round;
  final String stepPath;
}

/// `step.transition` — update-or-create on the two-ladder key. [columns] uses
/// §4 DDL names and is what the duplicate arm (and the in-memory applier)
/// applies verbatim; the insert arm is the same columns over a fresh row.
///
/// [chainPredecessorStepRound] is non-null exactly when this transition IS a
/// step_round bump (the gate-cleared rearm): the predecessor row at that
/// step_round gets `superseded_by_step_round = stepRound` — the chain has no
/// holes regardless of which writer bumped (schema §4).
final class StepCursorUpsert extends StepCursorDelta {
  const StepCursorUpsert({
    required super.sessionId,
    required super.round,
    required super.stepPath,
    required this.stepRound,
    required this.columns,
    this.chainPredecessorStepRound,
  });

  final int stepRound;
  final Map<String, Object?> columns;
  final int? chainPredecessorStepRound;

  StepCursorKey get key => (
    sessionId: sessionId,
    round: round,
    stepPath: stepPath,
    stepRound: stepRound,
  );

  /// The insert-arm row at [lastSeq]: the DDL defaults with [columns] applied.
  StepCursorRow rowAt(int lastSeq) => StepCursorRow(
    sessionId: sessionId,
    round: round,
    stepPath: stepPath,
    stepRound: stepRound,
    // Both NOT NULL columns are always present in [columns]; these values
    // never survive `applying` below.
    state: 'pending',
    incarnation: 0,
    lastSeq: lastSeq,
  ).applying(columns, lastSeq: lastSeq);
}

/// `step.superseded` — the explicit chain write: the predecessor row at
/// [oldStepRound] gets `superseded_by_step_round = newStepRound`. The
/// SUCCESSOR row is not invented here — it is born by its own first
/// `step.transition` (the record bumps the envelope step_round only).
final class StepCursorSupersede extends StepCursorDelta {
  const StepCursorSupersede({
    required super.sessionId,
    required super.round,
    required super.stepPath,
    required this.oldStepRound,
    required this.newStepRound,
  });

  final int oldStepRound;
  final int newStepRound;
}

/// The one delta function. Returns null for every record with no P2 effect —
/// non-step families, and the Family-5 types whose facts live on P4
/// (`gate.*`) or `proj_step_edges` (`molecule.poured`).
///
/// [decoded] short-circuits the codec when the caller already holds the typed
/// record (the Stage-1 appender does); replay decodes from the envelope.
StepCursorDelta? stepCursorDeltaFor(
  TrajectoryEnvelope envelope, {
  TrajectoryRecord? decoded,
}) {
  if (envelope.family != TrajectoryFamily.step) return null;
  final record = decoded ?? TrajectoryCodec.decode(envelope);
  switch (record) {
    case StepTransition():
      return StepCursorUpsert(
        sessionId: record.sessionId,
        round: record.round,
        stepPath: record.stepPath,
        stepRound: record.stepRound,
        columns: {
          'state': record.state.wire,
          'incarnation': record.incarnation,
          if (record.attemptId != null) 'attempt_id': record.attemptId,
          if (record.startedAt != null) 'started_at': record.startedAt,
          if (record.readyAt != null) 'ready_at': record.readyAt,
          if (record.completedAt != null) 'completed_at': record.completedAt,
          if (record.cooldownUntil != null)
            'cooldown_until': record.cooldownUntil,
          if (record.restartBudget != null)
            'restart_budget': record.restartBudget,
          if (record.failureClass != null)
            'failure_class': record.failureClass!.wire,
          if (record.result != null) 'result': record.result,
        },
        // The chain rule's implicit half: ONLY a gate-cleared rearm bumps
        // step_round via this record (schema §2 F5 names exactly two bump
        // writers), and a bump is always +1 chain depth. step_round 0 has no
        // predecessor to link.
        chainPredecessorStepRound:
            record.cause == StepCause.gateCleared && record.stepRound > 0
            ? record.stepRound - 1
            : null,
      );
    case StepSuperseded():
      return StepCursorSupersede(
        sessionId: record.sessionId,
        round: record.round,
        stepPath: record.stepPath,
        oldStepRound: record.oldStepRound,
        newStepRound: record.newStepRound,
      );
    // No P2 columns exist for these (the DDL is the letter): gate facts are
    // P4's, pour edges proj_step_edges'.
    case MoleculePoured() ||
        GateOpened() ||
        GateRegated() ||
        GateClosed() ||
        OpaqueRecord():
      return null;
    // Non-step families never pass the guard; the exhaustive switch still
    // needs the arms.
    case AttemptRecord() ||
        AdmissionRecord() ||
        VerificationRecord() ||
        EffectRecord():
      return null;
  }
}

/// The §4 `proj_step_cursor` column list an insert writes, in DDL order.
const List<String> _insertColumns = [
  'session_id',
  'round',
  'step_path',
  'step_round',
  'state',
  'incarnation',
  'attempt_id',
  'superseded_by_step_round',
  'cooldown_until',
  'restart_budget',
  'started_at',
  'ready_at',
  'completed_at',
  'failure_class',
  'result',
  'last_seq',
];

/// The chain write both delta shapes share: 0 matched rows is a fine outcome
/// (the predecessor may predate the log or ride another station), never an
/// error — and a re-applied link writes the value it already holds.
SqlStatement _chainSql({
  required String sessionId,
  required int round,
  required String stepPath,
  required int predecessorStepRound,
  required int newStepRound,
  required int lastSeq,
}) => (
  sql:
      'UPDATE proj_step_cursor '
      'SET superseded_by_step_round = :superseded_by_step_round, '
      'last_seq = :last_seq '
      'WHERE session_id = :session_id AND round = :round '
      'AND step_path = :step_path AND step_round = :step_round',
  params: {
    'superseded_by_step_round': newStepRound,
    'last_seq': lastSeq,
    'session_id': sessionId,
    'round': round,
    'step_path': stepPath,
    'step_round': predecessorStepRound,
  },
);

/// Renders [delta] as the SQL the Stage-1 appender runs inside its append
/// transaction (§5 step 5). [lastSeq] is the just-assigned `trajectory.seq`.
///
/// * An upsert's duplicate arm advances exactly the carried columns plus
///   `last_seq` — P2 has no mint record, so update-or-create IS the designed
///   semantics (unlike P1's refresh-last_seq-only insert dedupe).
/// * A bump additionally renders the predecessor chain write (one record, two
///   statements — the chain has no holes).
List<SqlStatement> stepCursorSqlFor(
  StepCursorDelta delta, {
  required int lastSeq,
}) {
  switch (delta) {
    case StepCursorUpsert():
      final params = delta.rowAt(lastSeq).toSqlParams();
      final duplicateSets = [
        for (final column in delta.columns.keys) '$column = :$column',
        'last_seq = :last_seq',
      ];
      final upsert = (
        sql:
            'INSERT INTO proj_step_cursor (${_insertColumns.join(', ')}) '
            'VALUES (${_insertColumns.map((c) => ':$c').join(', ')}) '
            'ON DUPLICATE KEY UPDATE ${duplicateSets.join(', ')}',
        params: params,
      );
      final predecessor = delta.chainPredecessorStepRound;
      if (predecessor == null) return [upsert];
      return [
        upsert,
        _chainSql(
          sessionId: delta.sessionId,
          round: delta.round,
          stepPath: delta.stepPath,
          predecessorStepRound: predecessor,
          newStepRound: delta.stepRound,
          lastSeq: lastSeq,
        ),
      ];
    case StepCursorSupersede():
      return [
        _chainSql(
          sessionId: delta.sessionId,
          round: delta.round,
          stepPath: delta.stepPath,
          predecessorStepRound: delta.oldStepRound,
          newStepRound: delta.newStepRound,
          lastSeq: lastSeq,
        ),
      ];
  }
}

/// Applies [delta] to the in-memory [rows] — the replay mode's applier, with
/// EXACTLY the incremental SQL's semantics:
///
/// * an upsert creates the row or advances exactly its carried columns;
/// * a chain write for an absent predecessor matches 0 rows and does nothing;
/// * DateTime/result values arrive typed here; the SQL renderer is where
///   DATETIME(6)/JSON formatting lives.
void applyStepCursorDelta(
  Map<StepCursorKey, StepCursorRow> rows,
  StepCursorDelta delta, {
  required int lastSeq,
}) {
  void chain(int predecessorStepRound, int newStepRound) {
    final key = (
      sessionId: delta.sessionId,
      round: delta.round,
      stepPath: delta.stepPath,
      stepRound: predecessorStepRound,
    );
    final predecessor = rows[key];
    if (predecessor == null) return;
    rows[key] = predecessor.applying({
      'superseded_by_step_round': newStepRound,
    }, lastSeq: lastSeq);
  }

  switch (delta) {
    case StepCursorUpsert():
      final existing = rows[delta.key];
      rows[delta.key] = existing == null
          ? delta.rowAt(lastSeq)
          : existing.applying(delta.columns, lastSeq: lastSeq);
      final predecessor = delta.chainPredecessorStepRound;
      if (predecessor != null) chain(predecessor, delta.stepRound);
    case StepCursorSupersede():
      chain(delta.oldStepRound, delta.newStepRound);
  }
}
