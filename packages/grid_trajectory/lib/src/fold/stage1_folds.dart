/// The Stage-1 synchronous fold registration (stage1-wiring §2.4 / W6): the
/// P2 (`proj_step_cursor`) and P6 (`proj_process_identity`) incremental
/// deltas JOIN P1 (`proj_session_head`) in the appender's synchronous step 5.
///
/// Each entry adapts one shared delta function to the appender's registration
/// seam ([TrajectoryFoldDelta]): decode is short-circuited with the typed
/// record the appender already holds, and the just-assigned `seq` becomes the
/// projection's `last_seq`. The vocabulary dispatch stays HERE, on the fold
/// side — the mechanics execute handed-in statements and never name a record
/// type (the extraction boundary).
library;

import '../append/trajectory_appender.dart' show TrajectoryFoldDelta;
import '../codec/envelope.dart';
import '../codec/trajectory_record.dart';
import 'process_identity_delta.dart';
import 'session_head_delta.dart';
import 'step_cursor_delta.dart';

/// P1 — `proj_session_head` (§6 row 1 / §7).
List<SqlStatement> sessionHeadFoldStep(
  TrajectoryEnvelope envelope,
  TrajectoryRecord record, {
  required int seq,
}) {
  final delta = sessionHeadDeltaFor(envelope, decoded: record);
  if (delta == null) return const [];
  return [sessionHeadSqlFor(delta, lastSeq: seq)];
}

/// P1 in the PRE-CUT SHAPE (cut-wiring, r13) — the SAME delta, rendered
/// without every column in [projSessionHeadCutColumns].
///
/// This is the fold half of `DualReadMode.off`. The rollback posture must
/// append without naming any column that requires a projection migration, so
/// an existing home that has not run the quiesced `traj replay` keeps
/// appending rather than dying on an unknown column.
List<SqlStatement> preCutSessionHeadFoldStep(
  TrajectoryEnvelope envelope,
  TrajectoryRecord record, {
  required int seq,
}) {
  final delta = sessionHeadDeltaFor(envelope, decoded: record);
  if (delta == null) return const [];
  return [sessionHeadSqlFor(delta, lastSeq: seq, cutShape: false)];
}

/// P2 — `proj_step_cursor` (§6 rows 14–16, the step_round chain rule).
List<SqlStatement> stepCursorFoldStep(
  TrajectoryEnvelope envelope,
  TrajectoryRecord record, {
  required int seq,
}) {
  final delta = stepCursorDeltaFor(envelope, decoded: record);
  if (delta == null) return const [];
  return stepCursorSqlFor(delta, lastSeq: seq);
}

/// P6 — `proj_process_identity` (§6 rows 3/10/13/32).
List<SqlStatement> processIdentityFoldStep(
  TrajectoryEnvelope envelope,
  TrajectoryRecord record, {
  required int seq,
}) {
  final delta = processIdentityDeltaFor(envelope, decoded: record);
  if (delta == null) return const [];
  return [processIdentitySqlFor(delta, lastSeq: seq)];
}

/// The Stage-1 set, in registration order — hand this to
/// `TrajectoryAppender(folds: ...)` (the harness's default appender does when
/// the dual read is ARMED).
const List<TrajectoryFoldDelta> kStage1FoldDeltas = [
  sessionHeadFoldStep,
  stepCursorFoldStep,
  processIdentityFoldStep,
];

/// The ROLLBACK set (`DualReadMode.off`): identical to [kStage1FoldDeltas]
/// except that P1 renders without [projSessionHeadCutColumns]. P2 and P6 are
/// unchanged, so they remain the same entries.
const List<TrajectoryFoldDelta> kPreCutFoldDeltas = [
  preCutSessionHeadFoldStep,
  stepCursorFoldStep,
  processIdentityFoldStep,
];
