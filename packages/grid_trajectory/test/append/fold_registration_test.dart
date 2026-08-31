/// §5 step 5's registration seam: registered fold deltas run INSIDE the
/// append transaction — after the row INSERT assigns `seq`, before the
/// applied_seq cursor and COMMIT — in registration order, with the Stage-1
/// set (`kStage1FoldDeltas`) driving the real P1/P2/P6 statements.
library;

import 'package:grid_trajectory/grid_trajectory.dart';
import 'package:test/test.dart';

import '../support/scripted_db.dart';

class _Harness {
  _Harness(List<TrajectoryFoldDelta> folds) {
    appender = TrajectoryAppender(
      db: db,
      station: 'lunar',
      onEvent: (_) {},
      folds: folds,
    );
    db
      ..on('UPDATE traj_fence', result: const SqlResult(affectedRows: 1))
      ..on(
        'SELECT active_branch()',
        result: const SqlResult(
          rows: [
            {'b': 'main'},
          ],
        ),
      )
      ..on(
        'AS e FROM traj_epoch',
        result: const SqlResult(
          rows: [
            {'e': '1'},
          ],
        ),
      )
      ..on(
        'INSERT INTO trajectory (',
        respond: (_) => const SqlResult(affectedRows: 1, lastInsertId: 41),
      );
  }

  final db = ScriptedDb();
  late final TrajectoryAppender appender;
}

void main() {
  test('registered folds run between the row INSERT and the applied_seq '
      'cursor, in registration order, at the assigned seq', () async {
    final calls = <String>[];
    final h = _Harness([
      (envelope, record, {required seq}) {
        calls.add('first:${record.recordType}:$seq');
        return [
          (sql: 'UPDATE fake_projection_one', params: {'seq': seq}),
        ];
      },
      (envelope, record, {required seq}) {
        calls.add('second:${record.recordType}:$seq');
        return const [];
      },
    ]);
    await h.appender.claimEpoch(pid: 1, pgid: 1);
    final outcome = await h.appender.append(
      const AttemptNote(
        sessionId: 'tranquility-1',
        body: 'observed',
        channel: 'ops',
        noteOrdinal: 1,
      ),
    );
    expect(outcome, isA<Appended>());
    expect(calls, ['first:attempt.note:41', 'second:attempt.note:41']);

    final sql = [for (final call in h.db.log) call.sql];
    final insert = sql.indexWhere((s) => s.startsWith('INSERT INTO trajectory'));
    final fold = sql.indexWhere((s) => s.contains('fake_projection_one'));
    final meta = sql.indexWhere((s) => s.contains('INSERT INTO proj_meta'));
    final commit = sql.lastIndexOf('COMMIT');
    expect(insert, isNot(-1));
    expect(
      [insert, fold, meta, commit],
      orderedEquals(([insert, fold, meta, commit]..sort())),
      reason: 'INSERT → fold → applied_seq → COMMIT, one transaction',
    );
    expect(h.db.matching('fake_projection_one').single.params, {'seq': 41});
  });

  test('a record with no delta appends clean — the Stage-1 set returns empty '
      'lists, never a statement', () async {
    final h = _Harness(kStage1FoldDeltas);
    await h.appender.claimEpoch(pid: 1, pgid: 1);
    // attempt.note touches none of P1/P2/P6.
    final outcome = await h.appender.append(
      const AttemptNote(
        sessionId: 'tranquility-1',
        body: 'observed',
        channel: 'ops',
        noteOrdinal: 2,
      ),
    );
    expect(outcome, isA<Appended>());
    expect(h.db.matching('proj_session_head'), isEmpty);
    expect(h.db.matching('proj_step_cursor'), isEmpty);
    expect(h.db.matching('proj_process_identity'), isEmpty);
  });

  test('the Stage-1 set lands each projection\'s statements at the assigned '
      'seq', () async {
    final h = _Harness(kStage1FoldDeltas);
    await h.appender.claimEpoch(pid: 1, pgid: 1);
    final outcome = await h.appender.append(
      const AttemptProcessStarted(
        attemptId: '01J8ATTEMPT000000000000002',
        sessionId: 'tranquility-1',
        incarnation: 0,
        pid: 42,
        pgid: 43,
        round: 0,
        stepPath: 'work.build',
        stepRound: 0,
      ),
    );
    expect(outcome, isA<Appended>());
    // P1 stamps the head's live identity; P6 births the attempt row; P2 has
    // no delta for an attempt-family record.
    final head = h.db.matching('UPDATE proj_session_head').single;
    expect(head.params!['attempt_id'], '01J8ATTEMPT000000000000002');
    expect(head.params!['last_seq'], 41);
    final identity = h.db.matching('INSERT INTO proj_process_identity').single;
    expect(identity.params!['pid'], 42);
    expect(identity.params!['last_seq'], 41);
    expect(h.db.matching('proj_step_cursor'), isEmpty);
  });
}
