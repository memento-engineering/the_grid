/// Family-1 fold at scale against a real hermetic dolt sql-server: 1,000
/// synthetic attempt-lifecycle records ride the REAL fenced appender, the
/// replay fold rebuilds `proj_session_head` + `proj_meta`, and the read
/// surfaces stay coherent — `foldStaleness` reports zero lag and `traj show`
/// renders a subject without the §5 staleness warning.
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

  test(
    '1k-record lifecycle storm: append, replay, and read coherently',
    () async {
      final appender = TrajectoryAppender(
        db: db,
        station: 'fold-it',
        onEvent: (_) {},
      );
      final claim = await appender.claimEpoch(pid: 4242, pgid: 4242);
      expect(claim, isA<EpochClaimed>());

      // 100 sessions x 10 family-1 records = 1,000 appends through the real
      // §5 write path (fence CAS, belt, terminal guard, idem keys).
      const sessions = 100;
      final outcomes = [
        TerminalOutcome.succeeded,
        TerminalOutcome.failed,
        TerminalOutcome.lost,
      ];
      var appended = 0;
      final base = DateTime.utc(2026, 8, 31, 8);
      for (var i = 0; i < sessions; i++) {
        final sessionId = 'tranquility-it$i';
        final workBead = 'tg-it$i';
        final attemptId = mintUlid(now: base.add(Duration(seconds: i)));
        final outcome = outcomes[i % outcomes.length];
        final at = base.add(Duration(minutes: i));
        final records = <TrajectoryRecord>[
          AttemptSessionStarted(
            sessionId: sessionId,
            grantId: mintUlid(now: base),
            workBeadId: workBead,
            rig: 'operator',
            model: 'molecule',
          ),
          AttemptProcessStarted(
            attemptId: attemptId,
            sessionId: sessionId,
            incarnation: 0,
            pid: 1000 + i,
            pgid: 1000 + i,
          ),
          WorktreeProvisioned(
            attemptId: attemptId,
            sessionId: sessionId,
            worktree: '/tmp/wt/$workBead',
            branch: 'grid/$workBead',
            baseSha: 'a' * 40,
            adoptedExisting: false,
          ),
          AttemptLeaseTransition(
            attemptId: attemptId,
            phase: LeasePhase.acquired,
            token: attemptId,
          ),
          AttemptLivenessTransition(
            attemptId: attemptId,
            crossing: LivenessCrossing.lost,
            lastBeatAt: at,
            thresholdMs: 90000,
          ),
          AttemptLivenessTransition(
            attemptId: attemptId,
            crossing: LivenessCrossing.regained,
            lastBeatAt: at.add(const Duration(seconds: 30)),
            thresholdMs: 90000,
          ),
          AttemptLeaseTransition(
            attemptId: attemptId,
            phase: LeasePhase.released,
            token: attemptId,
          ),
          AttemptProcessExited(
            attemptId: attemptId,
            sessionId: sessionId,
            pid: 1000 + i,
            exitCode: 0,
            exitKind: ExitKind.exited,
            inferred: false,
          ),
          AttemptTerminal(
            attemptId: attemptId,
            sessionId: sessionId,
            workBeadId: workBead,
            outcome: outcome,
          ),
          WorktreeReaped(
            sessionId: sessionId,
            worktree: '/tmp/wt/$workBead',
            branch: 'grid/$workBead',
          ),
        ];
        for (final (ordinal, record) in records.indexed) {
          final landed = await appender.append(
            record,
            occurredAt: at.add(Duration(seconds: ordinal)),
          );
          expect(
            landed,
            isA<Appended>(),
            reason: 'append $ordinal of $sessionId must land: $landed',
          );
          appended++;
        }
      }
      expect(appended, 1000);

      // ── replay: truncate + fold + proj_meta, on a fresh session ─────────
      final replayDb = await TrajectoryConnection.connect(
        server.endpointFor('trajectory'),
      );
      final result = await replaySessionHeads(replayDb);
      await replayDb.close();
      expect(result.rows, hasLength(sessions));
      expect(result.skipped, isEmpty);

      final maxSeq = await db.execute('SELECT MAX(seq) AS m FROM trajectory');
      expect(result.appliedSeq, int.parse(maxSeq.rows.first['m']!));

      // Every head reached its terminal shape; the fold matches the stream.
      final heads = await db.execute(
        'SELECT session_id, work_bead_id, status, outcome, round, held, '
        'pid, attempt_id, last_seq FROM proj_session_head',
      );
      expect(heads.rows, hasLength(sessions));
      for (final row in heads.rows) {
        final id = row['session_id']!;
        final i = int.parse(id.substring('tranquility-it'.length));
        expect(row['work_bead_id'], 'tg-it$i');
        expect(row['status'], 'closed');
        expect(row['outcome'], outcomes[i % outcomes.length].wire);
        expect(row['round'], '0');
        expect(row['held'], '0');
        expect(row['pid'], isNull, reason: 'the exit cleared live identity');
        expect(row['attempt_id'], isNotNull);
        final folded = result.rows[id]!;
        expect(int.parse(row['last_seq']!), folded.lastSeq);
      }

      // ── the read surfaces stay coherent ─────────────────────────────────
      final readDb = await TrajectoryConnection.connect(
        server.endpointFor('trajectory'),
      );
      final reader = SqlTrajectoryLogReader(readDb);
      try {
        final staleness = await reader.foldStaleness();
        expect(staleness, isNotNull);
        expect(staleness!.lag, 0, reason: 'replay drove applied_seq to head');

        // The session id keys the six session-scoped rows (lease/liveness
        // records ride attempt_id only).
        final subjectRows = await reader.rowsForSubject('tranquility-it7');
        expect(subjectRows, hasLength(6));
        expect(
          subjectRows.map((r) => r.seq).toList(),
          subjectRows.map((r) => r.seq).toList()..sort(),
          reason: 'seq order',
        );

        // The COMPLETE read the §9 comparator folds — the same rows, asserted
        // against the real server rather than assumed.
        final complete = await reader.allRecordsForSubject('tranquility-it7');
        expect(complete.isComplete, isTrue);
        expect(
          complete.records.map((r) => r.seq),
          subjectRows.map((r) => r.seq),
        );

        // A ceiling below the session's size is REPORTED, never silently
        // folded: that report is what stops a cut stream counting as clean.
        final cut = await reader.allRecordsForSubject(
          'tranquility-it7',
          ceiling: 4,
        );
        expect(cut.isComplete, isFalse);
        expect(cut.truncatedAt, 4);
        expect(cut.records, hasLength(4));
      } finally {
        await reader.close();
      }

      // traj show over the same store: renders, exits 0, and does NOT print
      // the §5 staleness warning (lag is 0).
      final out = <String>[];
      final code = await runTrajShow(
        gridHome: '/hermetic-unused',
        subject: 'tranquility-it7',
        open: (_) async {
          final showDb = await TrajectoryConnection.connect(
            server.endpointFor('trajectory'),
          );
          return TrajectoryOpened(SqlTrajectoryLogReader(showDb));
        },
        out: out.add,
        err: out.add,
      );
      expect(code, 0);
      expect(out.first, contains('6 records'));
      expect(out.join('\n'), isNot(contains('warning — the fold lags')));
    },
  );
}
