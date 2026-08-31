/// The Stage-1 replay modes for P2 and P6: determinism (same stream, same
/// rows — and order restored by the §5 replay rule), skip accounting, and the
/// truncate-and-rewrite SQL against a scripted db — mirroring
/// `session_head_fold_test` for the two new projections.
library;

import 'dart:convert';

import 'package:grid_trajectory/grid_trajectory.dart';
import 'package:test/test.dart';

import '../support/scripted_db.dart';
import '../support/scripted_reader.dart';

const _attempt = '01J8ATTEMPT000000000000002';

void main() {
  /// One session's step + process stream: spawn, worktree, a gated step whose
  /// rearm bumps step_round, the successor completing, exit, reap.
  List<TrajectoryEnvelope> storm(String sessionId, {required int baseSeq}) {
    TrajectoryEnvelope step(
      int offset,
      String state, {
      int stepRound = 0,
      String? cause,
      Map<String, Object?> extra = const {},
    }) => envelope(
      recordType: 'step.transition',
      family: TrajectoryFamily.step,
      seq: baseSeq + offset,
      sessionId: sessionId,
      round: 0,
      stepPath: 'work.build',
      stepRound: stepRound,
      incarnation: 0,
      attemptId: _attempt,
      payload: {'state': state, if (cause != null) 'cause': cause, ...extra},
    );

    return [
      envelope(
        recordType: 'attempt.process.started',
        family: TrajectoryFamily.attempt,
        seq: baseSeq,
        sessionId: sessionId,
        attemptId: _attempt,
        incarnation: 0,
        round: 0,
        stepPath: 'work.build',
        stepRound: 0,
        payload: const {'pid': 42, 'pgid': 43},
      ),
      envelope(
        recordType: 'worktree.provisioned',
        family: TrajectoryFamily.attempt,
        seq: baseSeq + 1,
        sessionId: sessionId,
        attemptId: _attempt,
        worktree: '/tmp/wt/$sessionId',
        branch: 'grid/$sessionId',
        commitSha: 'a' * 40,
        payload: const {'adopted_existing': false},
      ),
      step(2, 'running'),
      step(3, 'gated'),
      step(4, 'pending', stepRound: 1, cause: 'gate_cleared'),
      step(
        5,
        'complete',
        stepRound: 1,
        extra: {
          'result': {'rc': 0},
        },
      ),
      envelope(
        recordType: 'attempt.process.exited',
        family: TrajectoryFamily.attempt,
        seq: baseSeq + 6,
        sessionId: sessionId,
        attemptId: _attempt,
        payload: const {'pid': 42, 'exit_kind': 'exited', 'inferred': false},
      ),
      envelope(
        recordType: 'worktree.reaped',
        family: TrajectoryFamily.attempt,
        seq: baseSeq + 7,
        sessionId: sessionId,
        worktree: '/tmp/wt/$sessionId',
        payload: const {},
      ),
    ];
  }

  group('foldStepCursors', () {
    test('the storm folds to the two-ladder chain: predecessor gated + '
        'linked, successor complete', () {
      final result = foldStepCursors(storm('s1', baseSeq: 1));
      expect(result.rows, hasLength(2));
      final predecessor =
          result.rows[(
            sessionId: 's1',
            round: 0,
            stepPath: 'work.build',
            stepRound: 0,
          )]!;
      expect(predecessor.state, 'gated');
      expect(predecessor.supersededByStepRound, 1);
      final successor =
          result.rows[(
            sessionId: 's1',
            round: 0,
            stepPath: 'work.build',
            stepRound: 1,
          )]!;
      expect(successor.state, 'complete');
      expect(successor.result, {'rc': 0});
      expect(result.appliedSeq, 8);
      expect(result.skipped, isEmpty);
    });

    test('same stream twice folds to IDENTICAL rows, and the §5 replay rule '
        'restores a shuffled input (replay determinism)', () {
      final stream = [...storm('s1', baseSeq: 1), ...storm('s2', baseSeq: 10)];
      final first = foldStepCursors(stream);
      final second = foldStepCursors(stream);
      expect(second.rows, first.rows);
      final shuffled = foldStepCursors([...stream.reversed]);
      expect(
        shuffled.rows,
        first.rows,
        reason: 'orderForReplay re-establishes (station, epoch, epoch_seq)',
      );
    });

    test('unknown step-family (type, version) counts into skipped', () {
      final result = foldStepCursors([
        ...storm('s1', baseSeq: 1),
        envelope(
          recordType: 'step.transition',
          family: TrajectoryFamily.step,
          seq: 20,
          typeVersion: 99,
          sessionId: 's1',
          round: 0,
          stepPath: 'work.build',
          stepRound: 0,
          incarnation: 0,
          payload: const {'state': 'running'},
        ),
      ]);
      expect(result.skipped, {'step.transition@v99': 1});
      expect(result.appliedSeq, 20, reason: 'scanned, even though skipped');
    });
  });

  group('foldProcessIdentities', () {
    test('the storm folds to one attempt row with the full identity', () {
      final result = foldProcessIdentities(storm('s1', baseSeq: 1));
      final row = result.rows[_attempt]!;
      expect(row.sessionId, 's1');
      expect(row.round, 0);
      expect(row.stepPath, 'work.build');
      expect(row.pid, isNull, reason: 'exit cleared the live identity');
      expect(row.worktree, '/tmp/wt/s1');
      expect(row.baseSha, 'a' * 40);
      expect(row.worktreeState, 'reaped');
      expect(result.appliedSeq, 8);
    });

    test('same stream twice folds to IDENTICAL rows, shuffled input '
        'restored (replay determinism)', () {
      final stream = storm('s1', baseSeq: 1);
      final first = foldProcessIdentities(stream);
      expect(foldProcessIdentities(stream).rows, first.rows);
      expect(foldProcessIdentities([...stream.reversed]).rows, first.rows);
    });
  });

  group('replay (truncate-and-rewrite, per projection)', () {
    List<Map<String, String?>> asRows(Iterable<TrajectoryEnvelope> records) => [
      for (final record in records)
        {
          for (final entry in record.toJson().entries)
            entry.key: entry.key == 'payload'
                ? jsonEncode(entry.value)
                : entry.value?.toString(),
        },
    ];

    test('replayStepCursors truncates, rewrites, and drives its OWN proj_meta '
        'row in one transaction', () async {
      final db = ScriptedDb();
      db.on(
        'SELECT * FROM trajectory',
        respond: (_) => SqlResult(rows: asRows(storm('s1', baseSeq: 1))),
      );
      final result = await replayStepCursors(
        db,
        clock: () => DateTime.utc(2026, 8, 31, 16),
      );
      expect(result.rows, hasLength(2));

      final sql = [for (final call in db.log) call.sql];
      final begin = sql.indexOf('START TRANSACTION');
      final commit = sql.indexOf('COMMIT');
      expect(begin, isNot(-1));
      expect(commit, greaterThan(begin));
      expect(
        sql.indexWhere((s) => s.contains('DELETE FROM proj_step_cursor')),
        inInclusiveRange(begin, commit),
      );
      expect(db.matching('INSERT INTO proj_step_cursor'), hasLength(2));
      final meta = db.matching('INSERT INTO proj_meta').single;
      expect(meta.params!['projection'], stepCursorProjection);
      expect(meta.params!['fold_version'], stepCursorFoldVersion);
      expect(meta.params!['applied_seq'], 8);
      expect(meta.params!['skipped'], isNull);
    });

    test('replayProcessIdentities does the same for P6', () async {
      final db = ScriptedDb();
      db.on(
        'SELECT * FROM trajectory',
        respond: (_) => SqlResult(rows: asRows(storm('s1', baseSeq: 1))),
      );
      final result = await replayProcessIdentities(
        db,
        clock: () => DateTime.utc(2026, 8, 31, 16),
      );
      expect(result.rows, hasLength(1));
      expect(db.matching('DELETE FROM proj_process_identity'), hasLength(1));
      expect(db.matching('INSERT INTO proj_process_identity'), hasLength(1));
      final meta = db.matching('INSERT INTO proj_meta').single;
      expect(meta.params!['projection'], processIdentityProjection);
      expect(meta.params!['fold_version'], processIdentityFoldVersion);
      expect(meta.params!['applied_seq'], 8);
    });

    test('a failed write rolls back and rethrows', () async {
      final db = ScriptedDb();
      db.on(
        'SELECT * FROM trajectory',
        respond: (_) => SqlResult(rows: asRows(storm('s1', baseSeq: 1))),
      );
      db.on('INSERT INTO proj_step_cursor', throwing: StateError('boom'));
      await expectLater(replayStepCursors(db), throwsA(isA<StateError>()));
      expect(db.matching('ROLLBACK'), hasLength(1));
      expect(db.matching('COMMIT'), isEmpty);
    });
  });
}
