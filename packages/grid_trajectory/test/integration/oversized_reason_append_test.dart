/// tg-kzvs against a REAL hermetic dolt sql-server: the receipt reproduced.
/// An `attempt.terminal` carrying a 64 KiB reason used to answer
/// `MySQLServerException [1105]: string '…' is too large for column
/// 'work_terminal_reason'` from inside the append transaction, rolling the
/// `trajectory` row back with the projection update.
///
/// Hermetic only (temp dir, ephemeral port) — NEVER a real `.beads`/`.grid`
/// store. Fail-closed on a missing dolt, like every Stage-0 guard.
@Tags(['integration'])
@Timeout(Duration(minutes: 5))
library;

import 'package:grid_trajectory/grid_trajectory.dart';
import 'package:test/test.dart';

import 'support/hermetic_trajectory_server.dart';

void main() {
  late HermeticTrajectoryServer server;
  late TrajectoryConnection admin;
  late TrajectoryConnection db;

  setUpAll(() async {
    server = await HermeticTrajectoryServer.create();
    admin = await TrajectoryConnection.connect(server.serverEndpoint);
    await createTrajectoryDatabase(admin);
    db = await TrajectoryConnection.connect(server.endpointFor('trajectory'));
    await applyTrajectorySchema(db);
  });

  tearDownAll(() async {
    await admin.close();
    await db.close();
    await server.dispose();
  });

  test('a 64 KiB terminal reason lands: the ledger row survives and the head '
      'carries the bounded text', () async {
    final appender = TrajectoryAppender(
      db: db,
      station: 'kzvs',
      folds: kStage1FoldDeltas,
      onEvent: (_) {},
    );
    expect(
      await appender.claimEpoch(pid: 4242, pgid: 4242),
      isA<EpochClaimed>(),
    );

    const sessionId = 'kzvs-63cwup';
    const workBead = 'tg-kzvsit';
    final attemptId = mintUlid(now: DateTime.utc(2026, 9, 3, 5));
    final reason =
        'pow-26dd/deliver: delivery github-pr failed - pr open failed '
        '${'payload ' * 8192}';
    expect(reason.length, greaterThan(64 * 1024));

    expect(
      await appender.append(
        AttemptSessionStarted(
          sessionId: sessionId,
          grantId: mintUlid(now: DateTime.utc(2026, 9, 3, 4)),
          workBeadId: workBead,
          rig: 'operator',
          model: 'molecule',
        ),
      ),
      isA<Appended>(),
    );

    final landed = await appender.append(
      AttemptTerminal(
        attemptId: attemptId,
        sessionId: sessionId,
        workBeadId: workBead,
        outcome: TerminalOutcome.failed,
        reason: reason,
      ),
    );
    expect(
      landed,
      isA<Appended>(),
      reason: 'the ledger row must survive whatever the leg wrote: $landed',
    );

    final rows = await db.execute(
      'SELECT payload FROM trajectory '
      'WHERE session_id = :session AND record_type = :type',
      {'session': sessionId, 'type': 'attempt.terminal'},
    );
    expect(rows.rows, hasLength(1), reason: 'the terminal record EXISTS');
    expect(
      rows.rows.single['payload'],
      contains(reason),
      reason: 'the immutable payload keeps the complete failure text',
    );

    final head = await db.execute(
      'SELECT status, outcome, work_terminal_reason FROM proj_session_head '
      'WHERE session_id = :session',
      {'session': sessionId},
    );
    final stored = head.rows.single['work_terminal_reason']!;
    expect(head.rows.single['status'], 'closed');
    expect(head.rows.single['outcome'], 'failed');
    expect(stored.runes.length, 255);
    expect(stored, startsWith('pow-26dd/deliver: delivery github-pr failed'));
    expect(stored, contains('truncated from ${reason.runes.length}'));
  });
}
