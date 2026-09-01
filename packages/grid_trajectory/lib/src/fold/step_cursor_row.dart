/// One in-memory image of a `proj_step_cursor` row — P2, the round-bearing
/// step cursor on the TWO-ladder key (session_id, round, step_path,
/// step_round).
///
/// Column vocabulary is the §4 DDL verbatim; the DDL is the letter. The
/// supersedes CHAIN lives here as `superseded_by_step_round` — linear per
/// path, ordered by step_round, no edge rows (schema §2 F5 / fatal 4) — and is
/// written on EVERY step_round bump: `step.superseded` AND the gate-cleared
/// rearm (audit round 2).
library;

import 'dart:convert';

import 'package:meta/meta.dart';

import '../connect/trajectory_db.dart';
import 'session_head_row.dart' show parseSqlDateTime6, sqlDateTime6;

/// The two-ladder key — P2's PRIMARY KEY, and the in-memory map key both
/// application modes share.
typedef StepCursorKey = ({
  String sessionId,
  int round,
  String stepPath,
  int stepRound,
});

/// One P2 row. Immutable; the fold advances a cursor by [applying] a column
/// map — the SAME column vocabulary the incremental SQL uses, so the two
/// application modes cannot drift on semantics.
@immutable
class StepCursorRow {
  const StepCursorRow({
    required this.sessionId,
    required this.round,
    required this.stepPath,
    required this.stepRound,
    required this.state,
    required this.incarnation,
    required this.lastSeq,
    this.attemptId,
    this.supersededByStepRound,
    this.cooldownUntil,
    this.restartBudget,
    this.startedAt,
    this.readyAt,
    this.completedAt,
    this.failureClass,
    this.result,
  });

  /// One `SELECT * FROM proj_step_cursor` row, read back — the inverse of
  /// [toSqlParams], and the P2 mirror's BOOT SEED decoder (cut-wiring C4).
  ///
  /// Same contract as `SessionHeadRow.fromSqlRow`: values arrive as the
  /// `assoc()` shape's strings from a real server, but the map is typed
  /// [Object?] so the in-memory params map round-trips directly (an `int`
  /// `step_round`, a DATETIME(6) literal, the `result` JSON as text). Every
  /// non-null value is therefore read through its own string form.
  factory StepCursorRow.fromSqlRow(Map<String, Object?> row) {
    String? text(String column) {
      final value = row[column];
      return value == null ? null : '$value';
    }

    int? number(String column) {
      final raw = text(column);
      return raw == null ? null : int.parse(raw);
    }

    final rawResult = row['result'];
    return StepCursorRow(
      sessionId: text('session_id') ?? '',
      round: number('round') ?? 0,
      stepPath: text('step_path') ?? '',
      stepRound: number('step_round') ?? 0,
      // NOT NULL in the DDL; a row without either is unreadable, not
      // defaultable — the same rule `started_at` gets on P1.
      state: text('state') ?? '',
      incarnation: number('incarnation') ?? 0,
      attemptId: text('attempt_id'),
      supersededByStepRound: number('superseded_by_step_round'),
      cooldownUntil: parseSqlDateTime6(text('cooldown_until')),
      restartBudget: number('restart_budget'),
      startedAt: parseSqlDateTime6(text('started_at')),
      readyAt: parseSqlDateTime6(text('ready_at')),
      completedAt: parseSqlDateTime6(text('completed_at')),
      failureClass: text('failure_class'),
      // The in-memory params map carries the decoded map; a real server hands
      // back the encoded JSON text. Both decode to the same value, and a
      // malformed payload reads as NULL rather than failing the whole seed —
      // one unreadable result column must not cost the mirror its rows.
      result: switch (rawResult) {
        final Map<String, Object?> map => map,
        final String json => _decodeResult(json),
        _ => null,
      },
      lastSeq: number('last_seq') ?? 0,
    );
  }

  final String sessionId;
  final int round;
  final String stepPath;
  final int stepRound;

  /// The §4 ENUM wire string — pending/running/ready/complete/failed/gated.
  final String state;
  final int incarnation;
  final String? attemptId;

  /// The step_round CHAIN (schema §4): written on the PREDECESSOR row by
  /// every bump — never by a row's own transition.
  final int? supersededByStepRound;
  final DateTime? cooldownUntil;
  final int? restartBudget;
  final DateTime? startedAt;
  final DateTime? readyAt;
  final DateTime? completedAt;

  /// VARCHAR(24) wire — the tg-7ux split (work / store_unavailable / unknown).
  final String? failureClass;
  final Map<String, Object?>? result;
  final int lastSeq;

  StepCursorKey get key => (
    sessionId: sessionId,
    round: round,
    stepPath: stepPath,
    stepRound: stepRound,
  );

  /// The row with [columns] applied — DDL column names, an EXPLICIT null
  /// value means SET NULL (absent keys are untouched), mirroring the
  /// incremental UPSERT's duplicate arm exactly. Unknown column names throw:
  /// a delta naming a column this row cannot hold is a fold bug, never data.
  StepCursorRow applying(Map<String, Object?> columns, {required int lastSeq}) {
    var state = this.state;
    var incarnation = this.incarnation;
    var attemptId = this.attemptId;
    var supersededByStepRound = this.supersededByStepRound;
    var cooldownUntil = this.cooldownUntil;
    var restartBudget = this.restartBudget;
    var startedAt = this.startedAt;
    var readyAt = this.readyAt;
    var completedAt = this.completedAt;
    var failureClass = this.failureClass;
    var result = this.result;
    for (final entry in columns.entries) {
      final value = entry.value;
      switch (entry.key) {
        case 'state':
          state = value! as String;
        case 'incarnation':
          incarnation = value! as int;
        case 'attempt_id':
          attemptId = value as String?;
        case 'superseded_by_step_round':
          supersededByStepRound = value as int?;
        case 'cooldown_until':
          cooldownUntil = value as DateTime?;
        case 'restart_budget':
          restartBudget = value as int?;
        case 'started_at':
          startedAt = value as DateTime?;
        case 'ready_at':
          readyAt = value as DateTime?;
        case 'completed_at':
          completedAt = value as DateTime?;
        case 'failure_class':
          failureClass = value as String?;
        case 'result':
          result = (value as Map<String, Object?>?);
        default:
          throw ArgumentError(
            'proj_step_cursor has no fold-updatable column ${entry.key}',
          );
      }
    }
    return StepCursorRow(
      sessionId: sessionId,
      round: round,
      stepPath: stepPath,
      stepRound: stepRound,
      state: state,
      incarnation: incarnation,
      attemptId: attemptId,
      supersededByStepRound: supersededByStepRound,
      cooldownUntil: cooldownUntil,
      restartBudget: restartBudget,
      startedAt: startedAt,
      readyAt: readyAt,
      completedAt: completedAt,
      failureClass: failureClass,
      result: result,
      lastSeq: lastSeq,
    );
  }

  /// The full-row INSERT parameter map — §4 column names, SQL-typed values
  /// (datetimes as DATETIME(6) literals, `result` as encoded JSON).
  Map<String, Object?> toSqlParams() => {
    'session_id': sessionId,
    'round': round,
    'step_path': stepPath,
    'step_round': stepRound,
    'state': state,
    'incarnation': incarnation,
    'attempt_id': attemptId,
    'superseded_by_step_round': supersededByStepRound,
    'cooldown_until': cooldownUntil == null
        ? null
        : sqlDateTime6(cooldownUntil!),
    'restart_budget': restartBudget,
    'started_at': startedAt == null ? null : sqlDateTime6(startedAt!),
    'ready_at': readyAt == null ? null : sqlDateTime6(readyAt!),
    'completed_at': completedAt == null ? null : sqlDateTime6(completedAt!),
    'failure_class': failureClass,
    'result': result == null ? null : jsonEncode(result),
    'last_seq': lastSeq,
  };

  @override
  bool operator ==(Object other) =>
      other is StepCursorRow &&
      other.sessionId == sessionId &&
      other.round == round &&
      other.stepPath == stepPath &&
      other.stepRound == stepRound &&
      other.state == state &&
      other.incarnation == incarnation &&
      other.attemptId == attemptId &&
      other.supersededByStepRound == supersededByStepRound &&
      other.cooldownUntil == cooldownUntil &&
      other.restartBudget == restartBudget &&
      other.startedAt == startedAt &&
      other.readyAt == readyAt &&
      other.completedAt == completedAt &&
      other.failureClass == failureClass &&
      _jsonEquals(other.result, result) &&
      other.lastSeq == lastSeq;

  @override
  int get hashCode => Object.hash(
    sessionId,
    round,
    stepPath,
    stepRound,
    state,
    incarnation,
    attemptId,
    supersededByStepRound,
    cooldownUntil,
    restartBudget,
    startedAt,
    readyAt,
    completedAt,
    failureClass,
    // Structurally equal maps may order keys differently; length keeps the
    // hash consistent with the deep ==.
    result?.length,
    lastSeq,
  );

  @override
  String toString() => 'StepCursorRow(${toSqlParams()})';
}

/// The whole of P2, read in one SELECT — the P2 mirror's BOOT SEED
/// (cut-wiring C4 / §0.2).
///
/// One statement on the caller's already-serialized connection. The order is
/// the two-ladder key's own, so the seed is deterministic AND the supersedes
/// ladder arrives in ascending order per path — the collapse rule's input in
/// the shape it wants it.
const String scanStepCursorsSql =
    'SELECT * FROM proj_step_cursor '
    'ORDER BY session_id, step_path, round, step_round';

/// Reads every `proj_step_cursor` row off [db] via [scanStepCursorsSql].
Future<List<StepCursorRow>> scanStepCursors(TrajectoryDb db) async {
  final result = await db.execute(scanStepCursorsSql);
  return [for (final row in result.rows) StepCursorRow.fromSqlRow(row)];
}

Map<String, Object?>? _decodeResult(String json) {
  if (json.trim().isEmpty) return null;
  try {
    final decoded = jsonDecode(json);
    return decoded is Map<String, Object?> ? decoded : null;
  } on FormatException {
    return null;
  }
}

/// Structural equality for the `result` JSON column — value semantics without
/// a collection-package dependency (the leaf stays lean).
bool _jsonEquals(Object? a, Object? b) {
  if (identical(a, b)) return true;
  if (a is Map && b is Map) {
    if (a.length != b.length) return false;
    for (final key in a.keys) {
      if (!b.containsKey(key) || !_jsonEquals(a[key], b[key])) return false;
    }
    return true;
  }
  if (a is List && b is List) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (!_jsonEquals(a[i], b[i])) return false;
    }
    return true;
  }
  return a == b;
}
