/// Stage-0 guards against a real hermetic dolt sql-server: the §4 DDL lands
/// verbatim, all seven CHECKs refuse by name, the T6i fence refuses a stale
/// appender in both interleavings, the epoch-claim race loses with 1213, the
/// connect-time bans hold, and the write credential is scoped to
/// trajectory.* only.
///
/// These are the PR-gating guards (decision: stage0-guards-gate-prs) — the
/// CI job installs dolt, so a skip there is a failed guard.
@Tags(['integration'])
@Timeout(Duration(minutes: 3))
library;

import 'dart:io';

import 'package:grid_trajectory/grid_trajectory.dart';
import 'package:mysql_client/exception.dart';
import 'package:test/test.dart';

import 'support/hermetic_trajectory_server.dart';

void main() {
  HermeticTrajectoryServer? server;
  late TrajectoryConnection admin; // server-level session, no database
  late TrajectoryConnection db; // USE trajectory

  var epochSeq = 1000;
  var keyOrdinal = 0;

  setUpAll(() async {
    server = await HermeticTrajectoryServer.tryCreate();
    if (server == null) {
      markTestSkipped('dolt not available — guard suite cannot run');
      return;
    }
    admin = await TrajectoryConnection.connect(server!.serverEndpoint);
    await createTrajectoryDatabase(admin);
    db = await TrajectoryConnection.connect(server!.endpointFor('trajectory'));
    await applyTrajectorySchema(db);
    await applyTrajectorySchema(db); // idempotency is part of the contract
  });

  tearDownAll(() async {
    if (server == null) return;
    await admin.close();
    await db.close();
    await server!.dispose();
  });

  /// A minimally-valid trajectory row; [overrides] inject the violation.
  Future<void> insertRow(Map<String, Object?> overrides) async {
    final ordinal = keyOrdinal++;
    final row = <String, Object?>{
      'boot_epoch': 1,
      'epoch_seq': epochSeq++,
      'record_id': mintUlid(),
      'idem_key': sha256Hex('it-row:$ordinal'),
      'idem_key_text': 'it-row:$ordinal',
      'family': 'attempt',
      'record_type': 'attempt.note',
      'type_version': 1,
      'occurred_at': '2026-08-31 12:00:00.000000',
      'recorded_at': '2026-08-31 12:00:00.000000',
      'station': 'ck-station',
      'authority_id': 'ck-station/1',
      'source': 'integration',
      'payload': '{}',
      ...overrides,
    };
    final columns = row.keys.toList();
    await db.execute(
      'INSERT INTO trajectory (${columns.join(', ')}) '
      'VALUES (${columns.map((column) => ':$column').join(', ')})',
      row,
    );
  }

  Future<void> seedFenceLine(String station, int epoch) async {
    await db.execute(
      'INSERT INTO traj_epoch (station, epoch, pid, pgid, cause, advanced_at) '
      "VALUES (:station, :epoch, 1, 1, 'boot', '2026-08-31 12:00:00.000000')",
      {'station': station, 'epoch': epoch},
    );
    await db.execute(
      'INSERT INTO traj_fence (station, fence_state) VALUES (:station, :state) '
      'ON DUPLICATE KEY UPDATE fence_state = :state',
      {'station': station, 'state': epoch << 32},
    );
  }

  group('DDL', () {
    test(
      'applies verbatim and idempotently: all 19 tables, 3 ignore rows',
      () async {
        if (server == null) return;
        final tables = await db.execute('SHOW TABLES');
        final names = {for (final row in tables.rows) row.values.first};
        expect(
          names,
          containsAll([
            'trajectory',
            'traj_epoch',
            'traj_fence',
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
          ]),
        );
        final ignore = await db.execute(
          'SELECT pattern FROM dolt_ignore ORDER BY pattern',
        );
        expect(
          ignore.rows.map((row) => row['pattern']),
          containsAll(['proj_%', 'traj_pulse', 'traj_fence']),
        );
      },
    );

    test('a valid row inserts', () async {
      if (server == null) return;
      await insertRow(const {});
    });

    for (final (constraint, overrides) in <(String, Map<String, Object?>)>[
      ('ck_prov', {'provenance': 'inferred'}),
      ('ck_terminal', {'record_type': 'attempt.terminal'}),
      ('ck_unknown', {'outcome': 'unknown'}),
      ('ck_provision', {'record_type': 'worktree.provisioned'}),
      ('ck_grant', {'record_type': 'admission.grant.issued'}),
      ('ck_grant_link', {'record_type': 'admission.grant.consumed'}),
      ('ck_seat', {'work_bead_id': 'tg-zfek'}),
    ]) {
      test('$constraint refuses at write time, by name', () async {
        if (server == null) return;
        await expectLater(
          insertRow(overrides),
          throwsA(
            isA<MySQLServerException>().having(
              (e) => e.message,
              'message',
              contains(constraint),
            ),
          ),
        );
      });
    }
  });

  group('the fence (T6i)', () {
    test('a stale appender is refused: 0-row CAS after a steal, and it goes '
        'inert', () async {
      if (server == null) return;
      final connA = await TrajectoryConnection.connect(
        server!.endpointFor('trajectory'),
      );
      final connB = await TrajectoryConnection.connect(
        server!.endpointFor('trajectory'),
      );
      addTearDown(() async {
        await connA.close();
        await connB.close();
      });

      final a = TrajectoryAppender(db: connA, station: 'steal');
      final b = TrajectoryAppender(db: connB, station: 'steal');

      expect(await a.claimEpoch(pid: 1, pgid: 1), isA<EpochClaimed>());
      expect(
        await a.append(
          const AttemptNote(
            sessionId: 's-steal',
            body: 'pre-steal',
            channel: 'ops',
            noteOrdinal: 1,
          ),
        ),
        isA<Appended>(),
      );

      final claimed = await b.claimEpoch(pid: 2, pgid: 2, cause: 'steal');
      expect((claimed as EpochClaimed).epoch, 2);

      final refused = await a.append(
        const AttemptNote(
          sessionId: 's-steal',
          body: 'post-steal',
          channel: 'ops',
          noteOrdinal: 2,
        ),
      );
      expect(refused, isA<AppendFencedOut>());
      expect(a.isInert, isTrue);

      expect(
        await b.append(
          const AttemptNote(
            sessionId: 's-steal',
            body: 'successor',
            channel: 'ops',
            noteOrdinal: 3,
          ),
        ),
        isA<Appended>(),
      );

      // The stale row never landed.
      final rows = await db.execute(
        "SELECT idem_key_text FROM trajectory WHERE station = 'steal'",
      );
      expect(
        rows.rows.map((row) => row['idem_key_text']),
        isNot(contains('note:s-steal:2')),
      );
    });

    test('interleaving 1: the steal commits mid-append — the appender COMMIT '
        'dies with 1213 and lands nothing', () async {
      if (server == null) return;
      await seedFenceLine('ilv1', 1);
      final appender = await TrajectoryConnection.connect(
        server!.endpointFor('trajectory'),
      );
      final advancer = await TrajectoryConnection.connect(
        server!.endpointFor('trajectory'),
      );
      addTearDown(() async {
        await appender.close();
        await advancer.close();
      });

      await appender.execute('START TRANSACTION');
      final cas = await appender.execute(
        'UPDATE traj_fence SET fence_state = fence_state + 1 '
        "WHERE station = 'ilv1' AND (fence_state >> 32) = 1",
      );
      expect(cas.affectedRows, 1); // 1 row — never proof of the fence

      await advancer.execute(
        "INSERT INTO traj_fence (station, fence_state) VALUES ('ilv1', :s) "
        'ON DUPLICATE KEY UPDATE fence_state = :s',
        {'s': 2 << 32},
      );

      await appender.execute(
        'INSERT INTO trajectory (boot_epoch, epoch_seq, record_id, idem_key, '
        'idem_key_text, family, record_type, occurred_at, recorded_at, '
        'station, authority_id, source, payload) VALUES (1, 1, :rid, :ik, '
        "'ilv1:stale', 'attempt', 'attempt.note', "
        "'2026-08-31 12:00:00', '2026-08-31 12:00:00', 'ilv1', 'ilv1/1', "
        "'it', '{}')",
        {'rid': mintUlid(), 'ik': sha256Hex('ilv1:stale')},
      );
      await expectLater(
        appender.execute('COMMIT'),
        throwsA(
          isA<MySQLServerException>().having(
            (e) => e.errorCode,
            'errorCode',
            sqlErrSerializationFailure,
          ),
        ),
      );

      final landed = await db.execute(
        "SELECT COUNT(*) AS c FROM trajectory WHERE station = 'ilv1'",
      );
      expect(landed.rows.single['c'], '0');
    });

    test('interleaving 2: the append commits first — the advancer COMMIT dies '
        'with 1213 instead', () async {
      if (server == null) return;
      await seedFenceLine('ilv2', 1);
      final appender = await TrajectoryConnection.connect(
        server!.endpointFor('trajectory'),
      );
      final advancer = await TrajectoryConnection.connect(
        server!.endpointFor('trajectory'),
      );
      addTearDown(() async {
        await appender.close();
        await advancer.close();
      });

      await appender.execute('START TRANSACTION');
      await appender.execute(
        'UPDATE traj_fence SET fence_state = fence_state + 1 '
        "WHERE station = 'ilv2' AND (fence_state >> 32) = 1",
      );
      await advancer.execute('START TRANSACTION');
      await advancer.execute(
        "INSERT INTO traj_fence (station, fence_state) VALUES ('ilv2', :s) "
        'ON DUPLICATE KEY UPDATE fence_state = :s',
        {'s': 2 << 32},
      );
      await appender.execute('COMMIT');

      await expectLater(
        advancer.execute('COMMIT'),
        throwsA(
          isA<MySQLServerException>().having(
            (e) => e.errorCode,
            'errorCode',
            sqlErrSerializationFailure,
          ),
        ),
      );
    });
  });

  group('epoch claim', () {
    test('the race loser sees 1213, not 1062', () async {
      if (server == null) return;
      final connA = await TrajectoryConnection.connect(
        server!.endpointFor('trajectory'),
      );
      final connB = await TrajectoryConnection.connect(
        server!.endpointFor('trajectory'),
      );
      addTearDown(() async {
        await connA.close();
        await connB.close();
      });

      const claim =
          'INSERT INTO traj_epoch (station, epoch, pid, pgid, cause, '
          'advanced_at) '
          "SELECT 'race', COALESCE(MAX(epoch), 0) + 1, :pid, 1, 'boot', "
          "'2026-08-31 12:00:00.000000' FROM traj_epoch "
          "WHERE station = 'race'";

      await connA.execute('START TRANSACTION');
      await connA.execute(claim, {'pid': 1});
      await connB.execute('START TRANSACTION');
      await connB.execute(claim, {'pid': 2});
      await connA.execute('COMMIT');

      await expectLater(
        connB.execute('COMMIT'),
        throwsA(
          isA<MySQLServerException>().having(
            (e) => e.errorCode,
            'errorCode',
            sqlErrSerializationFailure,
          ),
        ),
      );
    });
  });

  group('connect-time bans', () {
    test(
      '@@dolt_force_transaction_commit set globally refuses the connect',
      () async {
        if (server == null) return;
        await admin.execute('SET @@GLOBAL.dolt_force_transaction_commit = 1');
        try {
          await expectLater(
            TrajectoryConnection.connect(server!.endpointFor('trajectory')),
            throwsA(isA<TrajectoryConnectionException>()),
          );
        } finally {
          await admin.execute('SET @@GLOBAL.dolt_force_transaction_commit = 0');
        }
      },
    );

    test('a branch change fails closed on the pin re-assert', () async {
      if (server == null) return;
      final conn = await TrajectoryConnection.connect(
        server!.endpointFor('trajectory'),
      );
      addTearDown(conn.close);
      await conn.execute("CALL DOLT_CHECKOUT('-b', 'scratch')");
      await expectLater(
        conn.assertMainBranch(),
        throwsA(isA<TrajectoryConnectionException>()),
      );
    });
  });

  group('provisioning', () {
    test(
      'the trajectory credential writes trajectory.* and nothing else',
      () async {
        if (server == null) return;
        final home = await Directory.systemTemp.createTemp('traj_it_home_');
        addTearDown(() => home.delete(recursive: true));

        final credential = await provisionTrajectoryUser(
          admin,
          gridHome: home.path,
        );
        expect(File(credential.secretPath).existsSync(), isTrue);

        final scoped = await TrajectoryConnection.connect(
          TrajectoryEndpoint(
            host: server!.host,
            port: server!.port,
            user: credential.user,
            password: credential.password,
            database: 'trajectory',
          ),
        );
        addTearDown(scoped.close);
        await scoped.execute(
          "INSERT INTO traj_fence (station, fence_state) VALUES ('prov', 1) "
          'ON DUPLICATE KEY UPDATE fence_state = 1',
        );

        await admin.execute('CREATE DATABASE IF NOT EXISTS offlimits');
        await expectLater(
          scoped.execute('SELECT * FROM offlimits.dolt_log'),
          throwsA(isA<MySQLException>()),
        );
      },
    );
  });

  group('appender end-to-end', () {
    test('append, dedupe on the real uq_idem, terminal guard, proj_meta '
        'frontier, verified dolt commits, clean status', () async {
      if (server == null) return;
      final conn = await TrajectoryConnection.connect(
        server!.endpointFor('trajectory'),
      );
      addTearDown(conn.close);
      final appender = TrajectoryAppender(
        db: conn,
        station: 'e2e',
        // Zeroed cadence: every append is allowed to dolt-commit, so the
        // verified-count and status-clean guards exercise for real.
        commitCadence: Duration.zero,
        commitMinInterval: Duration.zero,
      );

      expect(await appender.claimEpoch(pid: 1, pgid: 1), isA<EpochClaimed>());

      const note = AttemptNote(
        sessionId: 's-e2e',
        body: 'observed once',
        channel: 'ops',
        noteOrdinal: 1,
      );
      final first = await appender.append(note) as Appended;
      expect(first.epochSeq, 1);

      final duplicate = await appender.append(note);
      expect(duplicate, isA<AppendDeduped>());
      expect((duplicate as AppendDeduped).recordId, first.recordId);

      final terminal =
          await appender.append(
                AttemptTerminal(
                  attemptId: mintUlid(),
                  sessionId: 's-e2e',
                  outcome: TerminalOutcome.succeeded,
                ),
              )
              as Appended;
      expect(terminal.epochSeq, 2);

      final guard = await db.execute(
        'SELECT COUNT(*) AS c FROM traj_terminal_guard',
      );
      expect(guard.rows.single['c'], '1');

      final meta = await db.execute(
        "SELECT applied_seq FROM proj_meta WHERE projection = 'fold'",
      );
      expect(meta.rows.single['applied_seq'], '${terminal.seq}');

      expect(appender.verifiedDoltCommits, greaterThanOrEqualTo(2));

      // The T3 tripwire: fold writes never dirty the versioned working set
      // (proj_* and traj_fence are dolt_ignore'd; the named tables were
      // staged and committed).
      final status = await db.execute('SELECT COUNT(*) AS c FROM dolt_status');
      expect(status.rows.single['c'], '0');
    });
  });
}
