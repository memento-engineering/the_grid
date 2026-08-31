/// The replay mode: determinism, §5 ordering (reconstructed rows re-sorted
/// by occurred_at — §8 Q18), skip accounting, and the truncate-and-rewrite
/// SQL against a scripted db.
library;

import 'dart:convert';

import 'package:grid_trajectory/grid_trajectory.dart';
import 'package:test/test.dart';

import '../support/scripted_db.dart';
import '../support/scripted_reader.dart';

void main() {
  List<TrajectoryEnvelope> lifecycle(
    String sessionId, {
    required int baseSeq,
    TerminalOutcome outcome = TerminalOutcome.succeeded,
  }) {
    final attempt = '01J8ATTEMPT0000000000${baseSeq.toString().padLeft(5, '0')}';
    return [
      envelope(
        recordType: 'attempt.session.started',
        family: TrajectoryFamily.attempt,
        seq: baseSeq,
        sessionId: sessionId,
        workBeadId: 'tg-$sessionId',
        grantId: '01J8GRANT00000000000000001',
        occurredAt: DateTime.utc(2026, 8, 31, 10),
        payload: const {'rig': 'operator', 'model': 'molecule'},
      ),
      envelope(
        recordType: 'attempt.process.started',
        family: TrajectoryFamily.attempt,
        seq: baseSeq + 1,
        sessionId: sessionId,
        attemptId: attempt,
        incarnation: 0,
        payload: const {'pid': 42, 'pgid': 42},
      ),
      envelope(
        recordType: 'attempt.process.exited',
        family: TrajectoryFamily.attempt,
        seq: baseSeq + 2,
        sessionId: sessionId,
        attemptId: attempt,
        payload: const {'pid': 42, 'exit_kind': 'exited', 'inferred': false},
      ),
      envelope(
        recordType: 'attempt.terminal',
        family: TrajectoryFamily.attempt,
        seq: baseSeq + 3,
        sessionId: sessionId,
        attemptId: attempt,
        outcome: outcome,
        unknownReason:
            outcome == TerminalOutcome.unknown ? 'write_timeout' : null,
        occurredAt: DateTime.utc(2026, 8, 31, 12),
      ),
    ];
  }

  group('foldSessionHeads', () {
    test('a full lifecycle folds to the §7 head', () {
      final result = foldSessionHeads(lifecycle('s1', baseSeq: 1));
      final row = result.rows['s1']!;
      expect(row.status, SessionHeadStatus.closed);
      expect(row.outcome, TerminalOutcome.succeeded);
      expect(row.closedAt, DateTime.utc(2026, 8, 31, 12));
      expect(row.pid, isNull, reason: 'exit cleared the live identity');
      expect(row.attemptId, isNotNull, reason: 'last attempt survives');
      expect(row.lastSeq, 4);
      expect(result.appliedSeq, 4);
      expect(result.skipped, isEmpty);
    });

    test('same stream twice folds to IDENTICAL rows (replay determinism)', () {
      final stream = [
        ...lifecycle('s1', baseSeq: 1),
        ...lifecycle('s2', baseSeq: 10, outcome: TerminalOutcome.failed),
        envelope(
          recordType: 'attempt.round.retired',
          family: TrajectoryFamily.attempt,
          seq: 20,
          sessionId: 's2',
          round: 1,
          payload: const {'old_round': 0, 'new_round': 1, 'cause': 'rework'},
        ),
      ];
      final first = foldSessionHeads(stream);
      final second = foldSessionHeads(stream);
      expect(second.rows, first.rows);
      expect(second.appliedSeq, first.appliedSeq);
      expect(second.skipped, first.skipped);
    });

    test(
      'out-of-order RECONSTRUCTED rows fold by occurred_at (§8 Q18) — the '
      'terminal appended before the start still closes the session',
      () {
        // A backfill import appended the terminal FIRST (lower epoch_seq)
        // and the session start SECOND; occurred_at carries the true order.
        final reconstructedTerminal = envelope(
          recordType: 'attempt.terminal',
          family: TrajectoryFamily.attempt,
          seq: 1,
          sessionId: 'sr',
          attemptId: '01J8ATTEMPT000000000000009',
          outcome: TerminalOutcome.lost,
          occurredAt: DateTime.utc(2026, 8, 30, 23),
          provenance: TrajectoryProvenance.reconstructed,
        );
        final reconstructedStart = envelope(
          recordType: 'attempt.session.started',
          family: TrajectoryFamily.attempt,
          seq: 2,
          sessionId: 'sr',
          workBeadId: 'tg-sr',
          grantId: '01J8GRANT00000000000000001',
          occurredAt: DateTime.utc(2026, 8, 30, 20),
          provenance: TrajectoryProvenance.reconstructed,
          payload: const {'rig': 'operator', 'model': 'molecule'},
        );
        final result = foldSessionHeads([
          reconstructedTerminal,
          reconstructedStart,
        ]);
        final row = result.rows['sr']!;
        expect(
          row.status,
          SessionHeadStatus.closed,
          reason: 'append order would have dropped the terminal on a '
              'missing row; occurred_at order must win for reconstructed',
        );
        expect(row.outcome, TerminalOutcome.lost);
      },
    );

    test('observed rows keep (boot_epoch, epoch_seq) order regardless of '
        'occurred_at testimony', () {
      // Same shape as above but OBSERVED: append order is authoritative, so
      // the early terminal hits no row and the session stays open.
      final result = foldSessionHeads([
        envelope(
          recordType: 'attempt.terminal',
          family: TrajectoryFamily.attempt,
          seq: 1,
          sessionId: 'so',
          attemptId: '01J8ATTEMPT000000000000008',
          outcome: TerminalOutcome.lost,
          occurredAt: DateTime.utc(2026, 8, 30, 23),
        ),
        envelope(
          recordType: 'attempt.session.started',
          family: TrajectoryFamily.attempt,
          seq: 2,
          sessionId: 'so',
          workBeadId: 'tg-so',
          grantId: '01J8GRANT00000000000000001',
          occurredAt: DateTime.utc(2026, 8, 30, 20),
          payload: const {'rig': 'operator', 'model': 'molecule'},
        ),
      ]);
      expect(result.rows['so']!.status, SessionHeadStatus.open);
    });

    test('unknown attempt-family (type, version) counts into skipped', () {
      final result = foldSessionHeads([
        ...lifecycle('s1', baseSeq: 1),
        envelope(
          recordType: 'attempt.session.started',
          family: TrajectoryFamily.attempt,
          seq: 9,
          typeVersion: 99,
          sessionId: 's9',
          payload: const {},
        ),
      ]);
      expect(result.skipped, {'attempt.session.started@v99': 1});
      expect(result.appliedSeq, 9, reason: 'scanned, even though skipped');
    });

    test('an unknown terminal settles: the chain heals outcome only', () {
      final result = foldSessionHeads([
        ...lifecycle('s1', baseSeq: 1, outcome: TerminalOutcome.unknown),
        envelope(
          recordType: 'attempt.terminal',
          family: TrajectoryFamily.attempt,
          seq: 8,
          sessionId: 's1',
          attemptId: '01J8ATTEMPT000000000000001',
          outcome: TerminalOutcome.settled,
          resolvesRecordId: '01JAAAAAAAAAAAAAAAAAAAAA04',
          occurredAt: DateTime.utc(2026, 8, 31, 15),
        ),
      ]);
      final row = result.rows['s1']!;
      expect(row.outcome, TerminalOutcome.settled);
      expect(
        row.closedAt,
        DateTime.utc(2026, 8, 31, 12),
        reason: 'the settling probe must not move the close instant',
      );
    });
  });

  group('replaySessionHeads', () {
    test('truncates, rewrites, and drives proj_meta in one transaction',
        () async {
      final db = ScriptedDb();
      final scanned = [
        ...lifecycle('s1', baseSeq: 1),
        ...lifecycle('s2', baseSeq: 10),
      ];
      db.on(
        'SELECT * FROM trajectory',
        respond: (_) => SqlResult(
          rows: [
            for (final record in scanned)
              {
                for (final entry in record.toJson().entries)
                  entry.key: entry.key == 'payload'
                      ? jsonEncode(entry.value)
                      : entry.value?.toString(),
              },
          ],
        ),
      );
      final result = await replaySessionHeads(
        db,
        clock: () => DateTime.utc(2026, 8, 31, 16),
      );
      expect(result.rows.keys, unorderedEquals(['s1', 's2']));

      final sql = [for (final call in db.log) call.sql];
      final begin = sql.indexOf('START TRANSACTION');
      final commit = sql.indexOf('COMMIT');
      expect(begin, isNot(-1));
      expect(commit, greaterThan(begin));
      expect(
        sql.indexWhere((s) => s.contains('DELETE FROM proj_session_head')),
        inInclusiveRange(begin, commit),
      );
      expect(db.matching('INSERT INTO proj_session_head'), hasLength(2));
      final meta = db.matching('INSERT INTO proj_meta').single;
      expect(meta.params!['fold_version'], sessionHeadFoldVersion);
      expect(meta.params!['applied_seq'], 13);
      expect(meta.params!['skipped'], isNull);
      expect(meta.params!['rebuilt_at'], '2026-08-31 16:00:00.000000');
    });

    test('a failed write rolls back and rethrows', () async {
      final db = ScriptedDb();
      db.on(
        'SELECT * FROM trajectory',
        respond: (_) => SqlResult(
          rows: [
            for (final record in lifecycle('s1', baseSeq: 1))
              {
                for (final entry in record.toJson().entries)
                  entry.key: entry.key == 'payload'
                      ? jsonEncode(entry.value)
                      : entry.value?.toString(),
              },
          ],
        ),
      );
      db.on('INSERT INTO proj_session_head', throwing: StateError('boom'));
      await expectLater(
        replaySessionHeads(db),
        throwsA(isA<StateError>()),
      );
      expect(db.matching('ROLLBACK'), hasLength(1));
      expect(db.matching('COMMIT'), isEmpty);
    });
  });
}
