/// tg-kzvs — the receipt. An `attempt.terminal` whose failure reason outgrew
/// `proj_session_head.work_terminal_reason` (VARCHAR(255)) took the WHOLE
/// append down: dolt answered 1105 on the fold statement inside the append
/// transaction, so the `trajectory` row rolled back with it and the session had
/// no terminal record at all.
///
/// Offline half — the real §5 write path over a scripted connection. The real
/// column is exercised in `test/integration/oversized_reason_append_test.dart`.
library;

import 'package:grid_trajectory/grid_trajectory.dart';
import 'package:test/test.dart';

import '../support/scripted_db.dart';

void main() {
  // No quotes and no backslashes: the payload assertion below reads the
  // JSON-encoded column and must match the text verbatim.
  final oversized =
      'pow-26dd/deliver: delivery github-pr failed - pr open failed '
      '${'payload ' * 8192}';

  late ScriptedDb db;
  late TrajectoryAppender appender;

  setUp(() async {
    db = ScriptedDb()
      ..on(
        'AS e FROM traj_epoch',
        result: const SqlResult(
          rows: [
            {'e': '1'},
          ],
        ),
      )
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
        'FROM dolt_log',
        result: const SqlResult(
          rows: [
            {'c': '0'},
          ],
        ),
      )
      ..on(
        'INSERT INTO trajectory (',
        respond: (_) => const SqlResult(affectedRows: 1, lastInsertId: 1),
      );
    appender = TrajectoryAppender(
      db: db,
      station: 'lunar',
      folds: kStage1FoldDeltas,
      clock: () => DateTime.utc(2026, 9, 3, 5),
      onEvent: (_) {},
    );
    expect(await appender.claimEpoch(pid: 11, pgid: 12), isA<EpochClaimed>());
  });

  test('a 64 KiB terminal reason LANDS: the log row keeps it whole, the P1 '
      'fold statement fits VARCHAR(255)', () async {
    final outcome = await appender.append(
      AttemptTerminal(
        attemptId: '01J8ATTEMPT000000000000002',
        sessionId: 'tranquility-63cwup',
        workBeadId: 'tg-26dd',
        outcome: TerminalOutcome.failed,
        reason: oversized,
      ),
    );

    expect(
      outcome,
      isA<Appended>(),
      reason:
          'never AppendInternalError — that is the outcome grid_sdk renders '
          'as the trajectory.appendDropped flare: $outcome',
    );

    final row = db.matching('INSERT INTO trajectory (').single;
    expect(
      row.params!['payload'],
      contains(oversized),
      reason: 'the ledger keeps the whole text: payload is JSON, unbounded',
    );

    final fold = db.matching('UPDATE proj_session_head').single;
    final stored = fold.params!['work_terminal_reason']! as String;
    expect(stored.runes.length, 255);
    expect(stored, startsWith('pow-26dd/deliver: delivery github-pr failed'));
    expect(stored, contains('truncated from ${oversized.runes.length}'));
  });

  test('attempt.rework_declined bounds held_reason to VARCHAR(512)', () async {
    final outcome = await appender.append(
      AttemptReworkDeclined(
        sessionId: 'tranquility-63cwup',
        round: 2,
        reason: oversized,
      ),
    );
    expect(outcome, isA<Appended>());
    final fold = db.matching('UPDATE proj_session_head').single;
    expect((fold.params!['held_reason']! as String).runes.length, 512);
  });

  test('a reason that FITS is stored verbatim — no marker', () async {
    const short = 'gating rc 1';
    final outcome = await appender.append(
      AttemptTerminal(
        attemptId: '01J8ATTEMPT000000000000003',
        sessionId: 'tranquility-63cwup',
        outcome: TerminalOutcome.failed,
        reason: short,
      ),
    );
    expect(outcome, isA<Appended>());
    final fold = db.matching('UPDATE proj_session_head').single;
    expect(fold.params!['work_terminal_reason'], short);
  });
}
