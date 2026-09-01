/// The Family-1 delta function, per record type (§6 row 1 / §7): what each
/// attempt-lifecycle record does to P1 — and, just as load-bearing, what
/// produces NO delta because P1's DDL carries no column for it.
library;

import 'package:grid_trajectory/grid_trajectory.dart';
import 'package:test/test.dart';

import '../support/scripted_reader.dart';

void main() {
  final start = DateTime.utc(2026, 8, 31, 10);

  TrajectoryEnvelope started({int seq = 1}) => envelope(
    recordType: 'attempt.session.started',
    family: TrajectoryFamily.attempt,
    seq: seq,
    sessionId: 'tranquility-1',
    workBeadId: 'tg-9abc',
    grantId: '01J8GRANT00000000000000001',
    occurredAt: start,
    payload: const {'rig': 'operator', 'model': 'molecule'},
  );

  group('sessionHeadDeltaFor', () {
    test('attempt.session.started inserts the §7 mint-time row', () {
      final delta = sessionHeadDeltaFor(started(seq: 7));
      final insert = delta! as SessionHeadInsert;
      final row = insert.rowAt(7);
      expect(row.sessionId, 'tranquility-1');
      expect(row.workBeadId, 'tg-9abc');
      expect(row.rig, 'operator');
      expect(row.model, 'molecule');
      expect(row.seat, 'the_grid');
      expect(row.round, 0);
      expect(row.status, SessionHeadStatus.open);
      expect(row.startedAt, start);
      expect(row.headEpoch, 1);
      expect(row.lastSeq, 7);
      expect(row.outcome, isNull);
      expect(row.held, isFalse);
    });

    test('attempt.terminal closes: status/outcome/closed_at (+reason)', () {
      final closedAt = DateTime.utc(2026, 8, 31, 11, 30);
      final delta = sessionHeadDeltaFor(
        envelope(
          recordType: 'attempt.terminal',
          family: TrajectoryFamily.attempt,
          sessionId: 'tranquility-1',
          attemptId: '01J8ATTEMPT000000000000002',
          outcome: TerminalOutcome.failed,
          occurredAt: closedAt,
          payload: const {'reason': 'gating rc 1'},
        ),
      );
      final update = delta! as SessionHeadUpdate;
      expect(update.sessionId, 'tranquility-1');
      expect(update.guardAttemptId, isNull);
      expect(update.columns, {
        'status': 'closed',
        'outcome': 'failed',
        'closed_at': closedAt,
        // An OBSERVED terminal states both cut columns explicitly: no
        // explicit-unknown word, and no reconstructed mark — truth
        // supersedes testimony (cut-wiring §0.3, r9–r11).
        'unknown_reason': null,
        'terminal_provenance': null,
        'work_terminal_reason': 'gating rc 1',
      });
      expect(update.guardTerminalLess, isFalse);
    });

    test('a SETTLING terminal updates OUTCOME only — closed_at stands', () {
      final delta = sessionHeadDeltaFor(
        envelope(
          recordType: 'attempt.terminal',
          family: TrajectoryFamily.attempt,
          sessionId: 'tranquility-1',
          attemptId: '01J8ATTEMPT000000000000002',
          outcome: TerminalOutcome.settled,
          resolvesRecordId: '01J8UNKNOWNTERMINAL0000001',
        ),
      );
      final update = delta! as SessionHeadUpdate;
      expect(update.columns, {
        'outcome': 'settled',
        'unknown_reason': null,
        // OBSERVED settlement ⇒ the reconstructed mark clears with it.
        'terminal_provenance': null,
      });
    });

    test('a terminal without a session_id has nothing to key: no delta', () {
      expect(
        sessionHeadDeltaFor(
          envelope(
            recordType: 'attempt.terminal',
            family: TrajectoryFamily.attempt,
            attemptId: '01J8ATTEMPT000000000000002',
            outcome: TerminalOutcome.lost,
          ),
        ),
        isNull,
      );
    });

    test('attempt.round.retired bumps round', () {
      final delta = sessionHeadDeltaFor(
        envelope(
          recordType: 'attempt.round.retired',
          family: TrajectoryFamily.attempt,
          sessionId: 'tranquility-1',
          round: 2,
          payload: const {'old_round': 1, 'new_round': 2, 'cause': 'rework'},
        ),
      );
      expect((delta! as SessionHeadUpdate).columns, {'round': 2});
    });

    test('attempt.rework_declined sets held + reason', () {
      final delta = sessionHeadDeltaFor(
        envelope(
          recordType: 'attempt.rework_declined',
          family: TrajectoryFamily.attempt,
          sessionId: 'tranquility-1',
          round: 1,
          payload: const {'reason': 'operator declined'},
        ),
      );
      expect((delta! as SessionHeadUpdate).columns, {
        'held': 1,
        'held_reason': 'operator declined',
      });
    });

    test('attempt.process.started stamps pid/pgid/attempt_id', () {
      final delta = sessionHeadDeltaFor(
        envelope(
          recordType: 'attempt.process.started',
          family: TrajectoryFamily.attempt,
          sessionId: 'tranquility-1',
          attemptId: '01J8ATTEMPT000000000000002',
          incarnation: 0,
          payload: const {'pid': 42, 'pgid': 42},
        ),
      );
      final update = delta! as SessionHeadUpdate;
      expect(update.columns, {
        'pid': 42,
        'pgid': 42,
        'attempt_id': '01J8ATTEMPT000000000000002',
      });
      expect(update.guardAttemptId, isNull);
    });

    test('attempt.process.exited clears pid/pgid GUARDED by attempt_id', () {
      final delta = sessionHeadDeltaFor(
        envelope(
          recordType: 'attempt.process.exited',
          family: TrajectoryFamily.attempt,
          sessionId: 'tranquility-1',
          attemptId: '01J8ATTEMPT000000000000002',
          payload: const {'pid': 42, 'exit_kind': 'exited', 'inferred': false},
        ),
      );
      final update = delta! as SessionHeadUpdate;
      expect(update.columns.keys, unorderedEquals(['pid', 'pgid']));
      expect(update.columns['pid'], isNull);
      expect(update.columns['pgid'], isNull);
      expect(update.guardAttemptId, '01J8ATTEMPT000000000000002');
    });

    test('worktree/lease/liveness/adopt/mint/note produce NO P1 delta — the '
        'DDL is the letter (their fields are P6/P3\'s)', () {
      final noOps = [
        envelope(
          recordType: 'worktree.provisioned',
          family: TrajectoryFamily.attempt,
          sessionId: 'tranquility-1',
          attemptId: '01J8ATTEMPT000000000000002',
          worktree: '/tmp/wt',
          branch: 'grid/tg-9abc',
          commitSha: 'a' * 40,
          payload: const {'adopted_existing': false},
        ),
        envelope(
          recordType: 'worktree.reaped',
          family: TrajectoryFamily.attempt,
          sessionId: 'tranquility-1',
          worktree: '/tmp/wt',
          payload: const {},
        ),
        envelope(
          recordType: 'worktree.held',
          family: TrajectoryFamily.attempt,
          sessionId: 'tranquility-1',
          worktree: '/tmp/wt',
          payload: const {'uncommitted': 3},
        ),
        envelope(
          recordType: 'attempt.lease.acquired',
          family: TrajectoryFamily.attempt,
          attemptId: '01J8ATTEMPT000000000000002',
          payload: const {'token': '01J8ATTEMPT000000000000002'},
        ),
        envelope(
          recordType: 'attempt.liveness.lost',
          family: TrajectoryFamily.attempt,
          attemptId: '01J8ATTEMPT000000000000002',
          payload: {
            'last_beat_at': DateTime.utc(2026).toIso8601String(),
            'threshold_ms': 90000,
          },
        ),
        envelope(
          recordType: 'attempt.adopt.proved',
          family: TrajectoryFamily.attempt,
          attemptId: '01J8ATTEMPT000000000000002',
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
        // Each envelope decodes to its REAL typed record (never an opaque
        // fallback) — the null delta is a modelled fact, not a decode miss.
        expect(
          TrajectoryCodec.decode(record),
          isNot(isA<OpaqueRecord>()),
          reason: '${record.recordType} must decode',
        );
        expect(
          sessionHeadDeltaFor(record),
          isNull,
          reason: '${record.recordType} must not touch P1',
        );
      }
    });

    test('non-attempt families are refused at the door', () {
      expect(
        sessionHeadDeltaFor(
          envelope(
            recordType: 'step.transition',
            family: TrajectoryFamily.step,
            sessionId: 'tranquility-1',
            payload: const {'state': 'running'},
          ),
        ),
        isNull,
      );
    });
  });

  group('sessionHeadSqlFor (the incremental mode)', () {
    test(
      'insert renders the UPSERT whose duplicate arm bumps last_seq only',
      () {
        final delta = sessionHeadDeltaFor(started())! as SessionHeadInsert;
        final statement = sessionHeadSqlFor(delta, lastSeq: 9);
        expect(statement.sql, startsWith('INSERT INTO proj_session_head'));
        expect(
          statement.sql,
          endsWith('ON DUPLICATE KEY UPDATE last_seq = :last_seq'),
        );
        expect(statement.params['session_id'], 'tranquility-1');
        expect(statement.params['work_bead_id'], 'tg-9abc');
        expect(statement.params['status'], 'open');
        expect(statement.params['held'], 0);
        expect(statement.params['last_seq'], 9);
        expect(statement.params['started_at'], '2026-08-31 10:00:00.000000');
      },
    );

    test('update renders exactly the delta columns + last_seq + the guard', () {
      final delta = SessionHeadUpdate(
        sessionId: 'tranquility-1',
        columns: const {'pid': null, 'pgid': null},
        guardAttemptId: '01J8ATTEMPT000000000000002',
      );
      final statement = sessionHeadSqlFor(delta, lastSeq: 11);
      expect(
        statement.sql,
        'UPDATE proj_session_head SET pid = :pid, pgid = :pgid, '
        'last_seq = :last_seq WHERE session_id = :session_id '
        'AND attempt_id = :guard_attempt_id',
      );
      expect(statement.params, {
        'pid': null,
        'pgid': null,
        'last_seq': 11,
        'session_id': 'tranquility-1',
        'guard_attempt_id': '01J8ATTEMPT000000000000002',
      });
    });

    test('DateTime column values render as DATETIME(6) literals', () {
      final closedAt = DateTime.utc(2026, 8, 31, 11, 30, 2, 1, 5);
      final statement = sessionHeadSqlFor(
        SessionHeadUpdate(
          sessionId: 'tranquility-1',
          columns: {'status': 'closed', 'closed_at': closedAt},
        ),
        lastSeq: 3,
      );
      expect(statement.params['closed_at'], '2026-08-31 11:30:02.001005');
    });
  });

  group('applySessionHeadDelta (the replay mode, same semantics)', () {
    test('update for an absent session matches 0 rows: no row invented', () {
      final rows = <String, SessionHeadRow>{};
      applySessionHeadDelta(
        rows,
        const SessionHeadUpdate(sessionId: 'ghost', columns: {'round': 1}),
        lastSeq: 5,
      );
      expect(rows, isEmpty);
    });

    test('guarded clear skips when a successor already owns the head', () {
      final rows = <String, SessionHeadRow>{};
      applySessionHeadDelta(rows, sessionHeadDeltaFor(started())!, lastSeq: 1);
      applySessionHeadDelta(
        rows,
        const SessionHeadUpdate(
          sessionId: 'tranquility-1',
          columns: {'pid': 1, 'pgid': 1, 'attempt_id': 'successor'},
        ),
        lastSeq: 2,
      );
      applySessionHeadDelta(
        rows,
        const SessionHeadUpdate(
          sessionId: 'tranquility-1',
          columns: {'pid': null, 'pgid': null},
          guardAttemptId: 'predecessor',
        ),
        lastSeq: 3,
      );
      final row = rows['tranquility-1']!;
      expect(row.pid, 1, reason: 'the guard must protect the successor');
      expect(row.lastSeq, 2, reason: '0 matched rows bumps nothing');
    });

    test(
      're-applied insert (the at-least-once dedupe) bumps last_seq only',
      () {
        final rows = <String, SessionHeadRow>{};
        final insert = sessionHeadDeltaFor(started())!;
        applySessionHeadDelta(rows, insert, lastSeq: 1);
        applySessionHeadDelta(
          rows,
          const SessionHeadUpdate(
            sessionId: 'tranquility-1',
            columns: {'round': 2},
          ),
          lastSeq: 2,
        );
        applySessionHeadDelta(rows, insert, lastSeq: 3);
        final row = rows['tranquility-1']!;
        expect(row.round, 2, reason: 'the duplicate arm must not reset state');
        expect(row.lastSeq, 3);
      },
    );
  });

  // ── the wave-1 cut columns (cut-wiring §0.3, r9–r11) ─────────────────────

  group('TRUTH MONOTONICITY — terminal_provenance', () {
    TrajectoryEnvelope terminal({
      required TerminalOutcome outcome,
      TrajectoryProvenance provenance = TrajectoryProvenance.observed,
      String? unknownReason,
      String? resolvesRecordId,
      int seq = 2,
    }) => envelope(
      recordType: 'attempt.terminal',
      family: TrajectoryFamily.attempt,
      seq: seq,
      sessionId: 'tranquility-1',
      attemptId: '01J8ATTEMPT000000000000002',
      outcome: outcome,
      unknownReason: unknownReason,
      resolvesRecordId: resolvesRecordId,
      provenance: provenance,
    );

    SessionHeadRow fold(List<TrajectoryEnvelope> stream) {
      final rows = <String, SessionHeadRow>{};
      var seq = 0;
      for (final record in [started(), ...stream]) {
        seq += 1;
        final delta = sessionHeadDeltaFor(record);
        if (delta != null) applySessionHeadDelta(rows, delta, lastSeq: seq);
      }
      return rows['tranquility-1']!;
    }

    test('a RECONSTRUCTED terminal marks a terminal-less head and carries the '
        'explicit-unknown word', () {
      final update =
          sessionHeadDeltaFor(
                terminal(
                  outcome: TerminalOutcome.unknown,
                  unknownReason: 'teardown-replay',
                  provenance: TrajectoryProvenance.reconstructed,
                ),
              )!
              as SessionHeadUpdate;
      expect(update.columns['terminal_provenance'], 'reconstructed');
      expect(update.columns['unknown_reason'], 'teardown-replay');
      expect(
        update.guardTerminalLess,
        isTrue,
        reason: 'testimony closes ONLY a head with no terminal yet',
      );
    });

    test('reconstructed testimony NEVER rewrites a head that already carries '
        'an outcome — the guard is part of the delta, so live and replay '
        'agree', () {
      final row = fold([
        terminal(outcome: TerminalOutcome.escalated),
        terminal(
          outcome: TerminalOutcome.unknown,
          unknownReason: 'teardown-replay',
          provenance: TrajectoryProvenance.reconstructed,
          seq: 3,
        ),
      ]);
      expect(row.outcome, TerminalOutcome.escalated);
      expect(row.terminalProvenance, isNull);
    });

    test('an OBSERVED settlement over a reconstructed close writes the real '
        'outcome AND clears the mark', () {
      final row = fold([
        terminal(
          outcome: TerminalOutcome.unknown,
          unknownReason: 'external-close',
          provenance: TrajectoryProvenance.reconstructed,
        ),
        // The appender's resolving pre-read authors the observed terminal in
        // settling form; this is what lands in the log.
        terminal(
          outcome: TerminalOutcome.succeeded,
          resolvesRecordId: '01J8RECONSTRUCTED000000001',
          seq: 3,
        ),
      ]);
      expect(row.outcome, TerminalOutcome.succeeded);
      expect(row.terminalProvenance, isNull, reason: 'truth supersedes');
      expect(row.unknownReason, isNull);
    });

    test('an INFERRED settlement writes the outcome and LEAVES the mark — the '
        'session stays in the reconstructedTerminal adjudication class', () {
      final row = fold([
        terminal(
          outcome: TerminalOutcome.unknown,
          unknownReason: 'external-close',
          provenance: TrajectoryProvenance.reconstructed,
        ),
        terminal(
          outcome: TerminalOutcome.settled,
          provenance: TrajectoryProvenance.inferred,
          resolvesRecordId: '01J8RECONSTRUCTED000000001',
          seq: 3,
        ),
      ]);
      expect(row.outcome, TerminalOutcome.settled);
      expect(
        row.terminalProvenance,
        TrajectoryProvenance.reconstructed,
        reason: 'the discriminator is the RECORD provenance, not the outcome',
      );
    });

    test('the settling branch still heals OUTCOME only — closed_at stands', () {
      final closedAt = DateTime.utc(2026, 8, 31, 11, 30);
      final row = fold([
        envelope(
          recordType: 'attempt.terminal',
          family: TrajectoryFamily.attempt,
          seq: 2,
          sessionId: 'tranquility-1',
          attemptId: '01J8ATTEMPT000000000000002',
          outcome: TerminalOutcome.unknown,
          unknownReason: 'process-vanished',
          occurredAt: closedAt,
        ),
        terminal(
          outcome: TerminalOutcome.succeeded,
          resolvesRecordId: '01J8UNKNOWNTERMINAL0000001',
          seq: 3,
        ),
      ]);
      expect(row.closedAt, closedAt);
      expect(row.outcome, TerminalOutcome.succeeded);
    });

    test('an INFERRED non-settling terminal touches the mark neither way', () {
      final update =
          sessionHeadDeltaFor(
                terminal(
                  outcome: TerminalOutcome.lost,
                  provenance: TrajectoryProvenance.inferred,
                ),
              )!
              as SessionHeadUpdate;
      expect(update.columns.containsKey('terminal_provenance'), isFalse);
      expect(update.guardTerminalLess, isFalse);
    });

    test('the terminal-less guard renders as `AND outcome IS NULL`, and only '
        'for testimony', () {
      final testimony = sessionHeadSqlFor(
        sessionHeadDeltaFor(
          terminal(
            outcome: TerminalOutcome.unknown,
            unknownReason: 'teardown-replay',
            provenance: TrajectoryProvenance.reconstructed,
          ),
        )!,
        lastSeq: 9,
      );
      expect(testimony.sql, contains('AND outcome IS NULL'));
      final observed = sessionHeadSqlFor(
        sessionHeadDeltaFor(terminal(outcome: TerminalOutcome.succeeded))!,
        lastSeq: 9,
      );
      expect(observed.sql, isNot(contains('outcome IS NULL')));
    });

    // THE ROLLBACK SHAPE (cut-wiring, r13): `DualReadMode.off` registers
    // `kPreCutFoldDeltas`, which renders P1 without the two columns the wave-1
    // reshape added. An existing home that upgraded WITHOUT running the
    // quiesced `traj replay` must keep appending rather than die on an unknown
    // column — which is what lets the harness skip the boot reshape probe.
    test('cutShape: false drops the wave-1 columns from the UPDATE — the '
        'pre-cut home keeps appending', () {
      final statement = sessionHeadSqlFor(
        sessionHeadDeltaFor(
          terminal(
            outcome: TerminalOutcome.unknown,
            unknownReason: 'teardown-replay',
            provenance: TrajectoryProvenance.reconstructed,
          ),
        )!,
        lastSeq: 9,
        cutShape: false,
      );
      for (final column in projSessionHeadCutColumns) {
        expect(statement.sql, isNot(contains(column)), reason: column);
        expect(statement.params.containsKey(column), isFalse, reason: column);
      }
      // Everything the pre-cut shape DOES carry still rides.
      expect(statement.sql, contains('status = :status'));
      expect(statement.sql, contains('outcome = :outcome'));
      expect(statement.sql, contains('closed_at = :closed_at'));
    });

    test('cutShape: false drops them from the INSERT column list too', () {
      final statement = sessionHeadSqlFor(
        sessionHeadDeltaFor(started(seq: 7))!,
        lastSeq: 7,
        cutShape: false,
      );
      for (final column in projSessionHeadCutColumns) {
        expect(statement.sql, isNot(contains(column)), reason: column);
        expect(statement.params.containsKey(column), isFalse, reason: column);
      }
      expect(statement.sql, contains('INSERT INTO proj_session_head'));
      expect(statement.params['session_id'], 'tranquility-1');
    });

    test('cutShape: true (the default) still writes them — the armed posture '
        'is unchanged', () {
      final statement = sessionHeadSqlFor(
        sessionHeadDeltaFor(started(seq: 7))!,
        lastSeq: 7,
      );
      for (final column in projSessionHeadCutColumns) {
        expect(statement.sql, contains(column), reason: column);
      }
    });
  });
}
