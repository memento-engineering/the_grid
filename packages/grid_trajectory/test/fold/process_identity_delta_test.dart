/// The process-identity delta function, per record type (§6 rows 3/10/13/32):
/// what each attempt-lifecycle record does to P6 — the attempt-keyed row, the
/// lease state machine, the worktree facts, and the uq_incarnation
/// ladder-uniqueness mirror.
library;

import 'package:grid_trajectory/grid_trajectory.dart';
import 'package:test/test.dart';

import '../support/scripted_reader.dart';

const _attempt = '01J8ATTEMPT000000000000002';

void main() {
  TrajectoryEnvelope processStarted({
    int seq = 1,
    String attemptId = _attempt,
    int incarnation = 0,
    int? round = 1,
    String? stepPath = 'work.build',
    int? stepRound = 0,
    String? predecessor,
  }) => envelope(
    recordType: 'attempt.process.started',
    family: TrajectoryFamily.attempt,
    seq: seq,
    sessionId: 'tranquility-1',
    attemptId: attemptId,
    incarnation: incarnation,
    round: round,
    stepPath: stepPath,
    stepRound: stepRound,
    payload: {
      'pid': 42,
      'pgid': 43,
      if (predecessor != null) 'predecessor_attempt_id': predecessor,
    },
  );

  TrajectoryEnvelope provisioned({int seq = 1, String? sessionId}) => envelope(
    recordType: 'worktree.provisioned',
    family: TrajectoryFamily.attempt,
    seq: seq,
    sessionId: sessionId,
    attemptId: _attempt,
    worktree: '/tmp/wt/tg-9abc',
    branch: 'grid/tg-9abc',
    commitSha: 'a' * 40,
    payload: const {'adopted_existing': false},
  );

  group('processIdentityDeltaFor', () {
    test('attempt.process.started births the attempt-keyed row at its ladder '
        'position', () {
      final delta = processIdentityDeltaFor(
        processStarted(predecessor: '01J8ATTEMPT000000000000001'),
      );
      final upsert = delta! as ProcessIdentityUpsert;
      expect(upsert.attemptId, _attempt);
      final row = upsert.rowAt(5);
      expect(row.sessionId, 'tranquility-1');
      expect(row.round, 1);
      expect(row.stepPath, 'work.build');
      expect(row.stepRound, 0);
      expect(row.incarnation, 0);
      expect(row.pid, 42);
      expect(row.pgid, 43);
      expect(row.predecessorAttemptId, '01J8ATTEMPT000000000000001');
      expect(row.lastSeq, 5);
    });

    test('a session-scoped spawn takes the one-shape default: step_path \'\', '
        'step_round 0 (§2.1)', () {
      final delta = processIdentityDeltaFor(
        processStarted(round: null, stepPath: null, stepRound: null),
      );
      final upsert = delta! as ProcessIdentityUpsert;
      expect(upsert.round, 0);
      expect(upsert.stepPath, '');
      expect(upsert.stepRound, 0);
    });

    test('attempt.process.exited clears the live pid/pgid; the row stays', () {
      final delta = processIdentityDeltaFor(
        envelope(
          recordType: 'attempt.process.exited',
          family: TrajectoryFamily.attempt,
          sessionId: 'tranquility-1',
          attemptId: _attempt,
          payload: const {'pid': 42, 'exit_kind': 'exited', 'inferred': false},
        ),
      );
      final update = delta! as ProcessIdentityUpdate;
      expect(update.attemptId, _attempt);
      expect(update.columns.keys, unorderedEquals(['pid', 'pgid']));
      expect(update.columns['pid'], isNull);
      expect(update.columns['pgid'], isNull);
    });

    test('lease transitions map onto the DDL\'s STATE enum — acquired means '
        'held', () {
      const wires = {
        'attempt.lease.acquired': 'held',
        'attempt.lease.released': 'released',
        'attempt.lease.swept': 'swept',
      };
      wires.forEach((recordType, expected) {
        final delta = processIdentityDeltaFor(
          envelope(
            recordType: recordType,
            family: TrajectoryFamily.attempt,
            attemptId: _attempt,
            payload: const {'token': _attempt},
          ),
        );
        final update = delta! as ProcessIdentityUpdate;
        expect(update.columns, {'lease_state': expected}, reason: recordType);
      });
    });

    test('worktree.provisioned lands the row-32 evidence and marks the '
        'worktree live', () {
      final delta = processIdentityDeltaFor(
        provisioned(sessionId: 'tranquility-1'),
      );
      final upsert = delta! as ProcessIdentityUpsert;
      expect(upsert.columns, {
        'worktree': '/tmp/wt/tg-9abc',
        'branch': 'grid/tg-9abc',
        'base_sha': 'a' * 40,
        'adopted_existing': false,
        'worktree_state': 'live',
      });
    });

    test('worktree.provisioned WITHOUT a session cannot birth a row — '
        'update-only, 0 rows fine', () {
      final delta = processIdentityDeltaFor(provisioned());
      expect(delta, isA<ProcessIdentityUpdate>());
    });

    test('worktree.reaped/.held key (session, worktree) — no attempt_id on '
        'the record', () {
      final reaped = processIdentityDeltaFor(
        envelope(
          recordType: 'worktree.reaped',
          family: TrajectoryFamily.attempt,
          sessionId: 'tranquility-1',
          worktree: '/tmp/wt/tg-9abc',
          payload: const {},
        ),
      );
      final update = reaped! as ProcessWorktreeStateUpdate;
      expect(update.sessionId, 'tranquility-1');
      expect(update.worktree, '/tmp/wt/tg-9abc');
      expect(update.worktreeState, 'reaped');

      final held = processIdentityDeltaFor(
        envelope(
          recordType: 'worktree.held',
          family: TrajectoryFamily.attempt,
          sessionId: 'tranquility-1',
          worktree: '/tmp/wt/tg-9abc',
          payload: const {'uncommitted': 3},
        ),
      );
      expect((held! as ProcessWorktreeStateUpdate).worktreeState, 'held');
    });

    test('session-lifecycle/liveness/adopt/mint/note records produce NO P6 '
        'delta — the DDL is the letter', () {
      final noOps = [
        envelope(
          recordType: 'attempt.session.started',
          family: TrajectoryFamily.attempt,
          sessionId: 'tranquility-1',
          workBeadId: 'tg-9abc',
          grantId: '01J8GRANT00000000000000001',
          payload: const {'rig': 'operator', 'model': 'molecule'},
        ),
        envelope(
          recordType: 'attempt.terminal',
          family: TrajectoryFamily.attempt,
          sessionId: 'tranquility-1',
          attemptId: _attempt,
          outcome: TerminalOutcome.succeeded,
        ),
        envelope(
          recordType: 'attempt.round.retired',
          family: TrajectoryFamily.attempt,
          sessionId: 'tranquility-1',
          round: 1,
          payload: const {'old_round': 0, 'new_round': 1, 'cause': 'rework'},
        ),
        envelope(
          recordType: 'attempt.liveness.lost',
          family: TrajectoryFamily.attempt,
          attemptId: _attempt,
          payload: {
            'last_beat_at': DateTime.utc(2026).toIso8601String(),
            'threshold_ms': 90000,
          },
        ),
        envelope(
          recordType: 'attempt.adopt.proved',
          family: TrajectoryFamily.attempt,
          attemptId: _attempt,
          payload: const {'outcome': 'adopted'},
        ),
        envelope(
          recordType: 'attempt.mint.outcome',
          family: TrajectoryFamily.attempt,
          workBeadId: 'tg-9abc',
          mountAttemptId: '01J8MOUNT00000000000000001',
          payload: const {'phase': 'failed', 'mint_attempt': 1},
        ),
        envelope(
          recordType: 'attempt.note',
          family: TrajectoryFamily.attempt,
          sessionId: 'tranquility-1',
          payload: const {'body': 'b', 'channel': 'c', 'note_ordinal': 1},
        ),
      ];
      for (final record in noOps) {
        expect(
          TrajectoryCodec.decode(record),
          isNot(isA<OpaqueRecord>()),
          reason: '${record.recordType} must decode',
        );
        expect(
          processIdentityDeltaFor(record),
          isNull,
          reason: '${record.recordType} must not touch P6',
        );
      }
    });

    test('non-attempt families are refused at the door', () {
      expect(
        processIdentityDeltaFor(
          envelope(
            recordType: 'step.transition',
            family: TrajectoryFamily.step,
            sessionId: 'tranquility-1',
            round: 1,
            stepPath: 'work.build',
            stepRound: 0,
            incarnation: 0,
            payload: const {'state': 'running'},
          ),
        ),
        isNull,
      );
    });
  });

  group('processIdentitySqlFor (the incremental mode)', () {
    test('upsert renders the INSERT whose duplicate arm advances exactly the '
        'carried columns + last_seq', () {
      final delta =
          processIdentityDeltaFor(processStarted())! as ProcessIdentityUpsert;
      final statement = processIdentitySqlFor(delta, lastSeq: 7);
      expect(statement.sql, startsWith('INSERT INTO proj_process_identity'));
      expect(statement.sql, contains('ON DUPLICATE KEY UPDATE'));
      expect(statement.sql, contains('session_id = :session_id'));
      expect(statement.sql, contains('pid = :pid'));
      expect(statement.sql, endsWith('last_seq = :last_seq'));
      expect(statement.params['attempt_id'], _attempt);
      expect(statement.params['pid'], 42);
      expect(statement.params['pgid'], 43);
      expect(statement.params['lease_state'], isNull);
      expect(statement.params['last_seq'], 7);
    });

    test('adopted_existing renders as TINYINT', () {
      final delta =
          processIdentityDeltaFor(provisioned(sessionId: 'tranquility-1'))!
              as ProcessIdentityUpsert;
      final statement = processIdentitySqlFor(delta, lastSeq: 2);
      expect(statement.params['adopted_existing'], 0);
      expect(statement.params['worktree_state'], 'live');
    });

    test('update renders exactly the delta columns + last_seq keyed '
        'attempt_id', () {
      final statement = processIdentitySqlFor(
        const ProcessIdentityUpdate(
          attemptId: _attempt,
          columns: {'pid': null, 'pgid': null},
        ),
        lastSeq: 11,
      );
      expect(
        statement.sql,
        'UPDATE proj_process_identity SET pid = :pid, pgid = :pgid, '
        'last_seq = :last_seq WHERE attempt_id = :attempt_id',
      );
      expect(statement.params, {
        'pid': null,
        'pgid': null,
        'last_seq': 11,
        'attempt_id': _attempt,
      });
    });

    test('a worktree-state write keys (session_id, worktree)', () {
      final statement = processIdentitySqlFor(
        const ProcessWorktreeStateUpdate(
          sessionId: 'tranquility-1',
          worktree: '/tmp/wt/tg-9abc',
          worktreeState: 'reaped',
        ),
        lastSeq: 13,
      );
      expect(
        statement.sql,
        'UPDATE proj_process_identity SET worktree_state = :worktree_state, '
        'last_seq = :last_seq WHERE session_id = :session_id '
        'AND worktree = :worktree',
      );
      expect(statement.params['worktree_state'], 'reaped');
    });
  });

  group('applyProcessIdentityDelta (the replay mode, same semantics)', () {
    test('per-session FIFO can deliver worktree.provisioned FIRST: the '
        'provisional row is corrected in place by the spawn', () {
      final rows = <String, ProcessIdentityRow>{};
      applyProcessIdentityDelta(
        rows,
        processIdentityDeltaFor(provisioned(sessionId: 'tranquility-1'))!,
        lastSeq: 1,
      );
      expect(rows[_attempt]!.round, 0, reason: 'provisional ladder');
      applyProcessIdentityDelta(
        rows,
        processIdentityDeltaFor(processStarted())!,
        lastSeq: 2,
      );
      final row = rows[_attempt]!;
      expect(row.round, 1, reason: 'the spawn corrected the ladder');
      expect(row.stepPath, 'work.build');
      expect(row.pid, 42);
      expect(row.worktree, '/tmp/wt/tg-9abc', reason: 'worktree facts kept');
      expect(row.worktreeState, 'live');
      expect(row.lastSeq, 2);
    });

    test('the uq_incarnation arm: an insert colliding on the ladder advances '
        'the conflicting row instead of failing the fold', () {
      final rows = <String, ProcessIdentityRow>{};
      applyProcessIdentityDelta(
        rows,
        processIdentityDeltaFor(processStarted())!,
        lastSeq: 1,
      );
      // A different attempt_id at the SAME (session, round, path, step_round,
      // incarnation) — §3 forbids the pair; ON DUPLICATE KEY UPDATE absorbs
      // it, and so must the applier.
      applyProcessIdentityDelta(
        rows,
        processIdentityDeltaFor(
          processStarted(attemptId: '01J8ATTEMPT000000000000003', seq: 2),
        )!,
        lastSeq: 2,
      );
      expect(rows, hasLength(1), reason: 'no second row on a ladder conflict');
      expect(rows.keys.single, _attempt);
      expect(rows[_attempt]!.lastSeq, 2);
    });

    test('a full lifecycle: spawn, lease held/released, exit, reap', () {
      final rows = <String, ProcessIdentityRow>{};
      final deltas = [
        processIdentityDeltaFor(processStarted())!,
        processIdentityDeltaFor(
          envelope(
            recordType: 'attempt.lease.acquired',
            family: TrajectoryFamily.attempt,
            seq: 2,
            attemptId: _attempt,
            payload: const {'token': _attempt},
          ),
        )!,
        processIdentityDeltaFor(
          provisioned(seq: 3, sessionId: 'tranquility-1'),
        )!,
        processIdentityDeltaFor(
          envelope(
            recordType: 'attempt.lease.released',
            family: TrajectoryFamily.attempt,
            seq: 4,
            attemptId: _attempt,
            payload: const {'token': _attempt},
          ),
        )!,
        processIdentityDeltaFor(
          envelope(
            recordType: 'attempt.process.exited',
            family: TrajectoryFamily.attempt,
            seq: 5,
            attemptId: _attempt,
            payload: const {
              'pid': 42,
              'exit_kind': 'exited',
              'inferred': false,
            },
          ),
        )!,
        processIdentityDeltaFor(
          envelope(
            recordType: 'worktree.reaped',
            family: TrajectoryFamily.attempt,
            seq: 6,
            sessionId: 'tranquility-1',
            worktree: '/tmp/wt/tg-9abc',
            payload: const {},
          ),
        )!,
      ];
      for (final (index, delta) in deltas.indexed) {
        applyProcessIdentityDelta(rows, delta, lastSeq: index + 1);
      }
      final row = rows[_attempt]!;
      expect(row.pid, isNull, reason: 'exit cleared the live identity');
      expect(row.leaseState, 'released');
      expect(row.worktreeState, 'reaped');
      expect(row.baseSha, 'a' * 40, reason: 'row-32 evidence survives reap');
      expect(row.lastSeq, 6);
    });

    test('updates for an absent attempt match 0 rows: no row invented', () {
      final rows = <String, ProcessIdentityRow>{};
      applyProcessIdentityDelta(
        rows,
        const ProcessIdentityUpdate(
          attemptId: _attempt,
          columns: {'lease_state': 'held'},
        ),
        lastSeq: 1,
      );
      applyProcessIdentityDelta(
        rows,
        const ProcessWorktreeStateUpdate(
          sessionId: 'ghost',
          worktree: '/tmp/none',
          worktreeState: 'reaped',
        ),
        lastSeq: 2,
      );
      expect(rows, isEmpty);
    });

    test('applying an unknown column is a fold bug and throws', () {
      final row = ProcessIdentityRow(
        attemptId: _attempt,
        sessionId: 's',
        round: 0,
        stepPath: '',
        stepRound: 0,
        incarnation: 0,
        lastSeq: 1,
      );
      expect(
        () => row.applying(const {'ghost': 1}, lastSeq: 2),
        throwsArgumentError,
      );
    });
  });
}
