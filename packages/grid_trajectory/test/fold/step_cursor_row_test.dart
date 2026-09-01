/// The P2 row's SQL round trip and the mirror's boot-seed scan (cut-wiring
/// C4).
///
/// `fromSqlRow` is the inverse of `toSqlParams`: a boot seed decodes exactly
/// what a replay wrote, so a mirror seeded from the fold and a fold rebuilt
/// from the log cannot disagree about a row's contents. P2's own hazard is the
/// `result` JSON column — it round-trips through TEXT on a real server and
/// through a live Map in memory, and both have to decode to the same value or
/// the two application modes drift on exactly the payload a shadow-diff
/// compares field by field.
library;

import 'package:grid_trajectory/grid_trajectory.dart';
import 'package:test/test.dart';

import '../support/scripted_db.dart';

StepCursorRow _row({
  String sessionId = 'tranquility-1',
  int round = 0,
  String stepPath = 'tg-9abc/build',
  int stepRound = 0,
  String state = 'running',
  Map<String, Object?>? result,
  int? supersededByStepRound,
}) => StepCursorRow(
  sessionId: sessionId,
  round: round,
  stepPath: stepPath,
  stepRound: stepRound,
  state: state,
  incarnation: 2,
  attemptId: '01J8ATTEMPT000000000000002',
  supersededByStepRound: supersededByStepRound,
  cooldownUntil: DateTime.utc(2026, 8, 31, 11),
  restartBudget: 3,
  startedAt: DateTime.utc(2026, 8, 31, 10, 15, 3, 4, 5),
  readyAt: DateTime.utc(2026, 8, 31, 10, 20),
  completedAt: DateTime.utc(2026, 8, 31, 10, 25),
  failureClass: 'work',
  result: result,
  lastSeq: 41,
);

void main() {
  group('StepCursorRow.fromSqlRow', () {
    test('round-trips every column through toSqlParams', () {
      final row = _row(
        round: 2,
        stepRound: 3,
        state: 'complete',
        supersededByStepRound: 4,
        result: const {'grade': 'A', 'pr_url': 'https://example/1'},
      );
      expect(StepCursorRow.fromSqlRow(row.toSqlParams()), row);
    });

    test('round-trips the nullable columns as NULLs, not empty strings', () {
      final row = StepCursorRow(
        sessionId: 'tranquility-1',
        round: 0,
        stepPath: 'tg-9abc/build',
        stepRound: 0,
        state: 'pending',
        incarnation: 0,
        lastSeq: 1,
      );
      final decoded = StepCursorRow.fromSqlRow(row.toSqlParams());
      expect(decoded.attemptId, isNull);
      expect(decoded.supersededByStepRound, isNull);
      expect(decoded.cooldownUntil, isNull);
      expect(decoded.result, isNull);
      expect(decoded, row);
    });

    test('decodes the `assoc()` STRING shape a real server returns', () {
      // Every value arrives as text off the wire — ints as digits, datetimes
      // as DATETIME(6) literals with no zone (the fold writes UTC), and the
      // result column as encoded JSON.
      final decoded = StepCursorRow.fromSqlRow(const <String, Object?>{
        'session_id': 'tranquility-1',
        'round': '2',
        'step_path': 'tg-9abc/build',
        'step_round': '3',
        'state': 'complete',
        'incarnation': '1',
        'attempt_id': '01J8ATTEMPT000000000000002',
        'superseded_by_step_round': '4',
        'cooldown_until': null,
        'restart_budget': '3',
        'started_at': '2026-08-31 10:15:03.004005',
        'ready_at': null,
        'completed_at': '2026-08-31 10:25:00.000000',
        'failure_class': null,
        'result': '{"grade":"A"}',
        'last_seq': '41',
      });

      expect(decoded.round, 2);
      expect(decoded.stepRound, 3);
      expect(decoded.supersededByStepRound, 4);
      expect(decoded.startedAt, DateTime.utc(2026, 8, 31, 10, 15, 3, 4, 5));
      expect(decoded.startedAt!.isUtc, isTrue);
      expect(decoded.readyAt, isNull);
      expect(decoded.result, {'grade': 'A'});
      expect(decoded.lastSeq, 41);
    });

    test('a MALFORMED result payload reads as null rather than failing the '
        'whole seed', () {
      // One unreadable JSON column must not cost the mirror every row it was
      // seeding — the miss is visible (a null result) and bounded to its row.
      final decoded = StepCursorRow.fromSqlRow(const <String, Object?>{
        'session_id': 'tranquility-1',
        'round': '0',
        'step_path': 'tg-9abc/build',
        'step_round': '0',
        'state': 'complete',
        'incarnation': '0',
        'result': '{not json',
        'last_seq': '4',
      });
      expect(decoded.result, isNull);
      expect(decoded.state, 'complete');
    });
  });

  group('scanStepCursors', () {
    test('reads the whole projection in ONE statement, ordered by the '
        'two-ladder key', () async {
      final db = ScriptedDb()
        ..on(
          'FROM proj_step_cursor',
          result: const SqlResult(
            rows: [
              {
                'session_id': 'tranquility-1',
                'round': '0',
                'step_path': 'tg-9abc/build',
                'step_round': '0',
                'state': 'complete',
                'incarnation': '0',
                'last_seq': '4',
              },
              {
                'session_id': 'tranquility-1',
                'round': '0',
                'step_path': 'tg-9abc/build',
                'step_round': '1',
                'state': 'pending',
                'incarnation': '0',
                'last_seq': '9',
              },
            ],
          ),
        );

      final rows = await scanStepCursors(db);

      expect(db.log, hasLength(1));
      expect(db.log.single.sql, scanStepCursorsSql);
      // The order matters to the COLLAPSE: the ladder arrives ascending per
      // path, so the newest rung is the last one seen.
      expect(
        db.log.single.sql,
        contains('ORDER BY session_id, step_path, round, step_round'),
      );
      expect(rows.map((row) => row.stepRound), [0, 1]);
      expect(rows.last.state, 'pending');
    });

    test('an empty projection is an empty seed, not a failure', () async {
      expect(await scanStepCursors(ScriptedDb()), isEmpty);
    });
  });
}
