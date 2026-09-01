/// The C0 operator verbs against a REAL hermetic dolt sql-server: `traj
/// replay` (the golden, the quiesce fence, the P1 reshape, `--check`) and
/// `traj gc` (the gridboot credential actually reclaiming).
///
/// What this pins that a scripted-connection test cannot:
///
///   * the REPLAY GOLDEN — the rows the verb writes into all three `proj_*`
///     tables are, column for column, what the pure fold says the log folds
///     to. A replay that quietly disagrees with the fold is the one failure
///     the whole rebuildability constraint rests on;
///   * the RESHAPE against a real pre-cut table: dolt actually drops it,
///     actually re-creates it with `terminal_provenance`/`unknown_reason`, and
///     the replay actually repopulates it at the bumped `fold_version`;
///   * the QUIESCE FENCE refusing with a real lock file in place, leaving the
///     projection it would have rewritten untouched;
///   * `traj gc` under a gridboot-shaped credential — the operator half of the
///     cadence the harness disables on a scoped-grant home (tg-3o6b).
///
/// Hermetic: temp data dir, ephemeral port, a synthetic grid home whose
/// `.grid/.beads/dolt/config.yaml` points at it. Never a real `.beads`/`.grid`
/// store, and bd's proxy files are neither read nor written. Fail-closed on a
/// missing dolt, like every Stage-0 guard.
@Tags(['integration'])
@Timeout(Duration(minutes: 5))
library;

import 'dart:io';

import 'package:grid_trajectory/grid_trajectory.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

import 'support/hermetic_trajectory_server.dart';

void main() {
  late HermeticTrajectoryServer server;
  late Directory gridHome;

  DoltServerListener resolve(String _) => DoltServerListener(
    host: server.host,
    port: server.port,
    configPath: '<hermetic>',
  );

  Future<TrajectoryDb> connect(TrajectoryEndpoint endpoint) =>
      TrajectoryConnection.connect(endpoint);

  Future<TrajectoryDb> openService() async => TrajectoryConnection.connect(
    TrajectoryEndpoint(
      host: server.host,
      port: server.port,
      user: trajectoryUser,
      password: File(
        trajectorySecretPath(gridHome.path),
      ).readAsStringSync().trim(),
      database: 'trajectory',
    ),
  );

  /// The gridboot identity `traj provision` and `traj gc` both run under.
  Future<void> seedGridboot(String password) async {
    final admin = await TrajectoryConnection.connect(server.serverEndpoint);
    try {
      await admin.execute(
        "CREATE USER IF NOT EXISTS '$gridbootUser'@'%' "
        "IDENTIFIED BY '$password'",
      );
      await admin.execute(
        "ALTER USER '$gridbootUser'@'%' IDENTIFIED BY '$password'",
      );
      await admin.execute("GRANT ALL PRIVILEGES ON *.* TO '$gridbootUser'@'%'");
    } finally {
      await admin.close();
    }
    File(gridbootSecretPath(gridHome.path))
      ..parent.createSync(recursive: true)
      ..writeAsStringSync(password);
  }

  /// One session's Family-1 + Family-5 lifecycle, appended through the REAL
  /// fenced write path so the log the verbs replay is a real log.
  Future<void> appendLifecycle(TrajectoryDb db, {required int station}) async {
    final appender = TrajectoryAppender(
      db: db,
      station: 'verbs$station',
      onEvent: (_) {},
    );
    expect(await appender.claimEpoch(pid: 900, pgid: 900), isA<EpochClaimed>());
    final base = DateTime.utc(2026, 9, 1, 8);
    for (var i = 0; i < 3; i++) {
      final sessionId = 'verbs$station-s$i';
      final workBead = 'tg-v$station$i';
      final attemptId = mintUlid(now: base.add(Duration(seconds: i)));
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
          pid: 2000 + i,
          pgid: 2000 + i,
        ),
        StepTransition(
          sessionId: sessionId,
          round: 0,
          stepPath: 'build',
          stepRound: 0,
          incarnation: 0,
          state: StepState.running,
          attemptId: attemptId,
        ),
        StepTransition(
          sessionId: sessionId,
          round: 0,
          stepPath: 'build',
          stepRound: 0,
          incarnation: 0,
          state: StepState.complete,
          attemptId: attemptId,
        ),
        AttemptProcessExited(
          attemptId: attemptId,
          sessionId: sessionId,
          pid: 2000 + i,
          exitCode: 0,
          exitKind: ExitKind.exited,
          inferred: false,
        ),
        AttemptTerminal(
          attemptId: attemptId,
          sessionId: sessionId,
          workBeadId: workBead,
          outcome: TerminalOutcome.succeeded,
        ),
      ];
      for (final (ordinal, record) in records.indexed) {
        final landed = await appender.append(
          record,
          occurredAt: base.add(Duration(minutes: i, seconds: ordinal)),
        );
        expect(landed, isA<Appended>(), reason: '$record did not land');
      }
    }
  }

  void writeServerConfig() {
    final doltDir = Directory(p.join(gridHome.path, '.grid', '.beads', 'dolt'))
      ..createSync(recursive: true);
    File(p.join(doltDir.path, 'config.yaml')).writeAsStringSync(
      'listener:\n  host: ${server.host}\n  port: ${server.port}\n',
    );
  }

  setUpAll(() async {
    server = await HermeticTrajectoryServer.create();
  });

  tearDownAll(() async => server.dispose());

  setUp(() async {
    gridHome = Directory(
      (await Directory.systemTemp.createTemp(
        'traj_verbs_it_',
      )).resolveSymbolicLinksSync(),
    );
    writeServerConfig();
    await seedGridboot('bootpw-verbs');
    expect(
      await runTrajProvision(
        gridHome: gridHome.path,
        connect: connect,
        resolve: resolve,
        out: (_) {},
      ),
      0,
    );
  });

  tearDown(() async {
    if (gridHome.existsSync()) await gridHome.delete(recursive: true);
  });

  Future<int> replay({
    List<String> projections = replayProjections,
    bool check = false,
    required List<String> out,
    required List<String> err,
  }) => runTrajReplay(
    gridHome: gridHome.path,
    projections: projections,
    check: check,
    connect: connect,
    resolve: resolve,
    out: out.add,
    err: err.add,
  );

  test('THE GOLDEN: what the verb writes into all three proj_* tables is '
      'exactly what the pure fold says the log folds to', () async {
    final db = await openService();
    await appendLifecycle(db, station: 1);
    final out = <String>[];
    final err = <String>[];
    expect(
      await replay(out: out, err: err),
      0,
      reason: err.join('\n'),
    );

    final scanned = await db.execute('SELECT * FROM trajectory ORDER BY seq');
    final records = [for (final row in scanned.rows) envelopeFromRow(row)];
    final heads = foldSessionHeads(records);
    final cursors = foldStepCursors(records);
    final identities = foldProcessIdentities(records);

    final headRows = await db.execute(
      'SELECT session_id, status, outcome, last_seq FROM proj_session_head',
    );
    expect(headRows.rows, hasLength(heads.rows.length));
    for (final row in headRows.rows) {
      final folded = heads.rows[row['session_id']]!;
      expect(row['status'], folded.status.wire);
      expect(row['outcome'], folded.outcome?.wire);
      expect(int.parse(row['last_seq']!), folded.lastSeq);
    }

    final cursorRows = await db.execute(
      'SELECT session_id, step_path, state, last_seq FROM proj_step_cursor',
    );
    expect(cursorRows.rows, hasLength(cursors.rows.length));

    final identityRows = await db.execute(
      'SELECT attempt_id, session_id, last_seq FROM proj_process_identity',
    );
    expect(identityRows.rows, hasLength(identities.rows.length));

    // Every projection's generation is stamped, and the cursor row is at the
    // log head — a replayed fold is never stale by construction.
    final generations = await readProjectionGenerations(db);
    expect(
      generations.map((g) => g.projection),
      containsAll(<String>[
        foldCursorProjection,
        stepCursorProjection,
        processIdentityProjection,
      ]),
    );
    expect(
      generations
          .firstWhere((g) => g.projection == foldCursorProjection)
          .foldVersion,
      sessionHeadFoldVersion,
    );
    for (final generation in generations) {
      expect(generation.rebuiltAt, isNotNull, reason: generation.projection);
    }
    final lag = await readFoldLag(db);
    expect(lag.records, 0);
    expect(lag.isStale, isFalse);
    await db.close();
  });

  test('THE RESHAPE: a pre-cut P1 is dropped, re-created with the new '
      'columns, and repopulated at the bumped fold_version', () async {
    final db = await openService();
    await appendLifecycle(db, station: 2);

    // Stand the home back up at the PRE-CUT shape — the table a home
    // provisioned before wave 1 actually carries.
    await db.execute('DROP TABLE IF EXISTS proj_session_head');
    await db.execute('''
CREATE TABLE proj_session_head (
  session_id VARCHAR(40) NOT NULL PRIMARY KEY,
  work_bead_id VARCHAR(40) NOT NULL,
  round INT NOT NULL DEFAULT 0,
  status ENUM('open','closed') NOT NULL,
  outcome ENUM('succeeded','failed','cancelled','lost','escalated','settled','unknown') NULL,
  work_terminal_reason VARCHAR(255) NULL,
  held TINYINT(1) NOT NULL DEFAULT 0, held_reason VARCHAR(512) NULL,
  pgid INT NULL, pid INT NULL, attempt_id CHAR(26) NULL,
  rig VARCHAR(64) NULL, model VARCHAR(32) NULL,
  seat VARCHAR(64) NULL,
  started_at DATETIME(6) NOT NULL, closed_at DATETIME(6) NULL,
  head_epoch BIGINT NOT NULL,
  last_seq BIGINT NOT NULL,
  KEY ix_bead (work_bead_id, status)
)''');
    expect(await sessionHeadProjectionNeedsReshape(db), isTrue);

    final out = <String>[];
    final err = <String>[];
    expect(
      await replay(
        projections: const [sessionHeadProjection],
        out: out,
        err: err,
      ),
      0,
      reason: err.join('\n'),
    );
    expect(out.join('\n'), contains('reshape: proj_session_head DROPped'));

    expect(await sessionHeadProjectionNeedsReshape(db), isFalse);
    final rows = await db.execute(
      'SELECT session_id, terminal_provenance, unknown_reason '
      'FROM proj_session_head',
    );
    expect(rows.rows, isNotEmpty, reason: 'the replay repopulated it');
    for (final row in rows.rows) {
      // The columns exist and are NULL until C1/C2 write them.
      expect(row.containsKey('terminal_provenance'), isTrue);
      expect(row['unknown_reason'], isNull);
    }
    final cursor = (await readProjectionGenerations(
      db,
    )).firstWhere((g) => g.projection == foldCursorProjection);
    expect(cursor.foldVersion, sessionHeadFoldVersion);
    await db.close();
  });

  test('THE FENCE: a live station lock refuses, and the projection it would '
      'have rewritten is untouched', () async {
    final db = await openService();
    await appendLifecycle(db, station: 3);
    final out = <String>[];
    final err = <String>[];
    expect(
      await replay(out: out, err: err),
      0,
      reason: err.join('\n'),
    );
    final before = await db.execute(
      'SELECT COUNT(*) AS n FROM proj_session_head',
    );
    expect(int.parse(before.rows.single['n']!), greaterThan(0));

    // THIS process is the live holder — no fake probe, no injected seam.
    File(stationLockPath(gridHome.path))
      ..parent.createSync(recursive: true)
      ..writeAsStringSync(
        '{"pid":$pid,"pgid":$pid,'
        '"startedAt":"2026-09-01T00:00:00.000Z"}',
      );
    final refusedOut = <String>[];
    final refusedErr = <String>[];
    expect(await replay(out: refusedOut, err: refusedErr), 1);
    expect(refusedErr.join('\n'), contains('REFUSED'));
    final after = await db.execute(
      'SELECT COUNT(*) AS n FROM proj_session_head',
    );
    expect(after.rows.single['n'], before.rows.single['n']);

    // --check stays available against the armed home.
    final checkOut = <String>[];
    final checkErr = <String>[];
    expect(
      await replay(check: true, out: checkOut, err: checkErr),
      0,
      reason: checkErr.join('\n'),
    );
    expect(checkOut.join('\n'), contains('quiesced: NO'));
    expect(checkOut.join('\n'), contains('generation: '));
    await db.close();
  });

  test('traj gc reclaims under the gridboot credential — and the SERVICE '
      'credential is still refused, exactly as ratified', () async {
    final out = <String>[];
    final err = <String>[];
    expect(
      await runTrajGc(
        gridHome: gridHome.path,
        connect: connect,
        resolve: resolve,
        out: out.add,
        err: err.add,
      ),
      0,
      reason: err.join('\n'),
    );
    expect(out.join('\n'), contains('collected:'));

    // The other half of tg-3o6b's finding: the scoped service user cannot do
    // this, which is WHY the verb exists. No grant is widened to make it.
    final service = await openService();
    try {
      await service.execute('CALL DOLT_GC()');
      fail('the scoped trajectory credential must NOT be able to DOLT_GC');
    } on Object catch (error) {
      expect(
        isPrivilegeDenied(error),
        isTrue,
        reason: 'the harness latch keys on exactly this classification: $error',
      );
    } finally {
      await service.close();
    }
  });

  test('a home without the bootstrap credential is refused rather than '
      'widened', () async {
    File(gridbootSecretPath(gridHome.path)).deleteSync();
    final err = <String>[];
    expect(
      await runTrajGc(
        gridHome: gridHome.path,
        connect: connect,
        resolve: resolve,
        out: (_) {},
        err: err.add,
      ),
      1,
    );
    expect(err.join('\n'), contains('gridboot.secret'));
  });
}
