/// The P1 row's SQL round trip and the mirror's boot-seed scan (cut-wiring
/// C1).
///
/// `fromSqlRow` is the inverse of `toSqlParams`: a boot seed decodes exactly
/// what a replay wrote, so a mirror seeded from the fold and a fold rebuilt
/// from the log cannot disagree about a row's contents. The cut columns
/// (`terminal_provenance` / `unknown_reason`) ride the same round trip — they
/// are the durable carrier of the `reconstructedTerminal` suppressor, and a
/// column that failed to decode would silently re-expose every reconstructed
/// close to the overlay.
library;

import 'package:grid_trajectory/grid_trajectory.dart';
import 'package:test/test.dart';

import '../support/scripted_db.dart';

SessionHeadRow _row({
  String sessionId = 'tranquility-1',
  TerminalOutcome? outcome,
  TrajectoryProvenance? terminalProvenance,
  String? unknownReason,
  int round = 0,
  SessionHeadStatus status = SessionHeadStatus.open,
}) => SessionHeadRow(
  sessionId: sessionId,
  workBeadId: 'tg-9abc',
  round: round,
  status: status,
  outcome: outcome,
  workTerminalReason: 'gating rc 1',
  terminalProvenance: terminalProvenance,
  unknownReason: unknownReason,
  held: true,
  heldReason: 'declined',
  pgid: 4242,
  pid: 4243,
  attemptId: '01J8ATTEMPT000000000000002',
  rig: 'operator',
  model: 'molecule',
  substation: 'tg',
  startedAt: DateTime.utc(2026, 8, 31, 10, 15, 3, 4, 5),
  closedAt: DateTime.utc(2026, 8, 31, 11, 30),
  headEpoch: 7,
  lastSeq: 41,
);

void main() {
  group('SessionHeadRow.fromSqlRow', () {
    test('round-trips every column through toSqlParams', () {
      final row = _row(
        outcome: TerminalOutcome.unknown,
        terminalProvenance: TrajectoryProvenance.reconstructed,
        unknownReason: 'teardown-replay',
        status: SessionHeadStatus.closed,
        round: 2,
      );
      expect(SessionHeadRow.fromSqlRow(row.toSqlParams()), row);
    });

    test('round-trips the nullable columns as NULLs, not empty strings', () {
      final row = _row();
      final decoded = SessionHeadRow.fromSqlRow(row.toSqlParams());
      expect(decoded.outcome, isNull);
      expect(decoded.terminalProvenance, isNull);
      expect(decoded.unknownReason, isNull);
      expect(decoded.closedAt, isNotNull);
      expect(decoded, row);
    });

    test('decodes the `assoc()` STRING shape a real server returns', () {
      // Every value arrives as text off the wire — held as '1', datetimes as
      // DATETIME(6) literals with no zone (the fold writes UTC).
      final decoded = SessionHeadRow.fromSqlRow(const <String, Object?>{
        'session_id': 'tranquility-1',
        'work_bead_id': 'tg-9abc',
        'round': '3',
        'status': 'closed',
        'outcome': 'unknown',
        'work_terminal_reason': null,
        'terminal_provenance': 'reconstructed',
        'unknown_reason': 'external-close',
        'held': '0',
        'held_reason': null,
        'pgid': null,
        'pid': null,
        'attempt_id': '01J8ATTEMPT000000000000002',
        'rig': null,
        'model': null,
        'substation': 'tg',
        'started_at': '2026-08-31 10:15:03.000000',
        'closed_at': '2026-08-31 11:30:00.000000',
        'head_epoch': '7',
        'last_seq': '41',
      });
      expect(decoded.round, 3);
      expect(decoded.status, SessionHeadStatus.closed);
      expect(decoded.outcome, TerminalOutcome.unknown);
      expect(decoded.terminalProvenance, TrajectoryProvenance.reconstructed);
      expect(decoded.unknownReason, 'external-close');
      expect(decoded.held, isFalse);
      expect(decoded.startedAt, DateTime.utc(2026, 8, 31, 10, 15, 3));
      expect(decoded.startedAt.isUtc, isTrue, reason: 'the column has no zone');
      expect(decoded.closedAt, DateTime.utc(2026, 8, 31, 11, 30));
      expect(decoded.lastSeq, 41);
    });
  });

  group('scanSessionHeads', () {
    test('reads the whole projection in ONE deterministic statement', () async {
      final db = ScriptedDb()
        ..on(
          'FROM proj_session_head',
          result: const SqlResult(
            rows: [
              {
                'session_id': 'tranquility-1',
                'work_bead_id': 'tg-9abc',
                'round': '0',
                'status': 'open',
                'started_at': '2026-08-31 10:00:00.000000',
                'head_epoch': '7',
                'last_seq': '4',
              },
              {
                'session_id': 'tranquility-2',
                'work_bead_id': 'tg-9abc',
                'round': '1',
                'status': 'open',
                'started_at': '2026-08-31 10:05:00.000000',
                'head_epoch': '7',
                'last_seq': '9',
              },
            ],
          ),
        );

      final rows = await scanSessionHeads(db);

      expect(db.log, hasLength(1));
      expect(db.log.single.sql, scanSessionHeadsSql);
      expect(db.log.single.sql, contains('ORDER BY session_id'));
      expect(rows.map((row) => row.sessionId), [
        'tranquility-1',
        'tranquility-2',
      ]);
      expect(rows.last.round, 1, reason: 'the retired-into marker survives');
    });

    test('an empty projection is an empty seed, not a failure', () async {
      expect(await scanSessionHeads(ScriptedDb()), isEmpty);
    });
  });
}
