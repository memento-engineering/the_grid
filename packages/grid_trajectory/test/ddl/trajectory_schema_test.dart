/// The §4 bootstrap's ordering and idempotency over a scripted connection —
/// the real dolt acceptance rides the integration suite.
library;

import 'package:grid_trajectory/grid_trajectory.dart';
import 'package:test/test.dart';

import '../support/scripted_db.dart';

void main() {
  test('createTrajectoryDatabase is IF NOT EXISTS', () async {
    final db = ScriptedDb();
    await createTrajectoryDatabase(db);
    expect(db.log.single.sql, 'CREATE DATABASE IF NOT EXISTS trajectory');
  });

  test('dolt_ignore registration is the FIRST DDL statement executed, then '
      'every §4 table in order', () async {
    final db = ScriptedDb();
    await applyTrajectorySchema(db);

    // Statement 0 probes, statement 1 seeds — before any CREATE TABLE.
    expect(db.log[0].sql, contains('FROM dolt_ignore'));
    expect(db.log[1].sql, doltIgnoreSeedSql);

    final creates = db
        .matching('CREATE TABLE')
        .map(
          (call) => RegExp(
            r'CREATE TABLE IF NOT EXISTS (\w+)',
          ).firstMatch(call.sql)!.group(1),
        )
        .toList();
    expect(creates, [
      'traj_epoch',
      'traj_fence',
      'trajectory',
      'traj_terminal_guard',
      'traj_pulse',
      'proj_meta',
      'proj_session_head',
      'proj_step_cursor',
      'proj_step_edges',
      'proj_verification',
      'proj_admission',
      'proj_admission_clause',
      'proj_gate',
      'proj_gate_cycles',
      'proj_process_identity',
      'proj_effects',
      'proj_leases',
      'proj_command_dedupe',
      'proj_telemetry',
    ]);

    // The bootstrap ends with its own schema commit — plain -A (never
    // --force), --skip-empty for the idempotent re-run.
    expect(db.log[db.log.length - 2].sql, "CALL DOLT_ADD('-A')");
    expect(db.log.last.sql, contains("'--skip-empty'"));
    expect(db.log.last.sql, isNot(contains('--force')));
  });

  test('an already-seeded dolt_ignore is tolerated, missing patterns are '
      'inserted individually', () async {
    final seeded = ScriptedDb();
    seeded.on(
      'FROM dolt_ignore',
      result: const SqlResult(
        rows: [
          {'pattern': 'proj_%'},
          {'pattern': 'traj_pulse'},
          {'pattern': 'traj_fence'},
        ],
      ),
    );
    await applyTrajectorySchema(seeded);
    expect(seeded.matching('INSERT INTO dolt_ignore'), isEmpty);

    final partial = ScriptedDb();
    partial.on(
      'FROM dolt_ignore',
      result: const SqlResult(
        rows: [
          {'pattern': 'proj_%'},
        ],
      ),
    );
    await applyTrajectorySchema(partial);
    final inserts = partial.matching('INSERT INTO dolt_ignore');
    expect(inserts, hasLength(2));
    expect(
      inserts.map((call) => call.params!['pattern']),
      containsAll(['traj_pulse', 'traj_fence']),
    );
  });

  group('the wave-1 P1 reshape (cut-wiring C0, r6/r7)', () {
    test('the bootstrap creates P1 at the CUT shape — a fresh home never '
        'needs the migration', () {
      expect(trajectoryTableDdl, contains(projSessionHeadDdl));
      for (final column in projSessionHeadCutColumns) {
        expect(projSessionHeadDdl, contains(column));
      }
      expect(
        projSessionHeadDdl,
        contains(
          "terminal_provenance ENUM('observed','inferred','reconstructed')",
        ),
        reason: "the provenance vocabulary is the log envelope's own",
      );
      expect(projSessionHeadDdl, contains('unknown_reason VARCHAR(32) NULL'));
    });

    test('a pre-cut home NEEDS the reshape; a current one does not', () async {
      final stale = ScriptedDb()
        ..on(
          'information_schema.columns',
          result: const SqlResult(
            rows: [
              {'name': 'session_id'},
              {'name': 'terminal_provenance'},
            ],
          ),
        );
      expect(await sessionHeadProjectionNeedsReshape(stale), isTrue);
      expect(
        stale.log.single.params!['table'],
        'proj_session_head',
        reason: 'DATABASE()-scoped, so a sibling schema cannot answer for us',
      );

      final current = ScriptedDb()
        ..on(
          'information_schema.columns',
          result: const SqlResult(
            rows: [
              {'name': 'TERMINAL_PROVENANCE'},
              {'name': 'unknown_reason'},
            ],
          ),
        );
      expect(
        await sessionHeadProjectionNeedsReshape(current),
        isFalse,
        reason: 'servers case column names differently; the check does not',
      );
    });

    test(
      'an absent table reads as needing the reshape (which creates it)',
      () async {
        expect(await sessionHeadProjectionNeedsReshape(ScriptedDb()), isTrue);
      },
    );

    test('the reshape is DROP + re-CREATE, never ALTER, and rides no '
        'transaction', () async {
      final db = ScriptedDb();
      await reshapeSessionHeadProjection(db);
      expect(db.log.map((call) => call.sql), [
        'DROP TABLE IF EXISTS proj_session_head',
        projSessionHeadDdl,
      ]);
      expect(db.matching('ALTER TABLE'), isEmpty);
      expect(db.matching('START TRANSACTION'), isEmpty);
    });
  });

  test('the trajectory DDL pins all seven named CHECK constraints', () {
    final trajectory = trajectoryTableDdl[2];
    for (final constraint in const [
      'ck_prov',
      'ck_terminal',
      'ck_unknown',
      'ck_provision',
      'ck_grant',
      'ck_grant_link',
      'ck_seat',
    ]) {
      expect(trajectory, contains('CONSTRAINT $constraint'));
    }
  });
}
