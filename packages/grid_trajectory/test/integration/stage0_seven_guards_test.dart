/// The seven Stage-0 guard tests, the ones §9 names as stage-cut evidence:
/// status-clean after fold writes, the `dolt add --force` ban, dolt_log commit
/// counting, `--doltcfg-dir` discipline, branch-change fail-closed, the
/// session-variable ban, and the CHECK-refusal pin across all seven named
/// constraints.
///
/// They run against a real hermetic dolt sql-server and FAIL CLOSED when dolt
/// is absent (decision: stage0-guards-gate-prs — a skipped guard is a failed
/// guard). The PR-gating `trajectory-guards` CI job installs dolt and runs
/// exactly this tag; the general Dart job excludes it.
///
/// Each guard owns its own database on the shared server: guard 2 deliberately
/// springs a permanent trap, and no other guard may inherit it.
@Tags(['integration'])
@Timeout(Duration(minutes: 5))
library;

import 'dart:io';

import 'package:grid_trajectory/grid_trajectory.dart';
import 'package:mysql_client/exception.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

import 'support/hermetic_trajectory_server.dart';

void main() {
  late HermeticTrajectoryServer server;
  late TrajectoryConnection admin; // server-level session, no database

  setUpAll(() async {
    server = await HermeticTrajectoryServer.create();
    admin = await TrajectoryConnection.connect(server.serverEndpoint);
  });

  tearDownAll(() async {
    await admin.close();
    await server.dispose();
  });

  /// A database of its own, schema applied, closed at test end.
  Future<TrajectoryConnection> openDatabase(String name) async {
    await admin.execute('CREATE DATABASE IF NOT EXISTS $name');
    final conn = await TrajectoryConnection.connect(server.endpointFor(name));
    addTearDown(conn.close);
    await applyTrajectorySchema(conn);
    return conn;
  }

  /// The status-clean predicate itself, shared by guards 1 and 2: the table
  /// names dolt reports as dirty. `dolt_ignore`'d tables (proj_%, traj_fence,
  /// traj_pulse) never appear here — that is exactly what makes fold writes
  /// invisible to it, and what a force-add destroys.
  Future<List<String>> dirtyTables(TrajectoryConnection conn) async {
    final result = await conn.execute(
      'SELECT table_name FROM dolt_status ORDER BY table_name',
    );
    return [for (final row in result.rows) row['table_name']!];
  }

  Future<int> doltLogCount(TrajectoryConnection conn) async {
    final result = await conn.execute('SELECT COUNT(*) AS c FROM dolt_log');
    return int.parse(result.rows.single['c']!);
  }

  // ── guard 1 ───────────────────────────────────────────────────────────────

  test('guard 1 — status-clean: schema, appends and a fold write leave '
      '`dolt status` clean inside the database dir', () async {
    const database = 'g1_status';
    final conn = await openDatabase(database);
    final appender = TrajectoryAppender(
      db: conn,
      station: 'g1',
      // Zeroed cadence: every append may dolt-commit, so the guard measures
      // the committing path, not a lucky quiet one.
      commitCadence: Duration.zero,
      commitMinInterval: Duration.zero,
    );

    expect(await appender.claimEpoch(pid: 1, pgid: 1), isA<EpochClaimed>());
    expect(
      await appender.append(
        const AttemptNote(
          sessionId: 's-g1',
          body: 'observed',
          channel: 'ops',
          noteOrdinal: 1,
        ),
      ),
      isA<Appended>(),
    );
    expect(
      await appender.append(
        AttemptTerminal(
          attemptId: mintUlid(),
          sessionId: 's-g1',
          outcome: TerminalOutcome.succeeded,
        ),
      ),
      isA<Appended>(),
    );

    // The writes the guard is about actually happened: a fold row, a moved
    // fence cell, a terminal guard row.
    final fold = await conn.execute(
      "SELECT applied_seq FROM proj_meta WHERE projection = 'fold'",
    );
    expect(fold.rows, hasLength(1));
    final fence = await conn.execute('SELECT COUNT(*) AS c FROM traj_fence');
    expect(fence.rows.single['c'], '1');

    expect(
      await dirtyTables(conn),
      isEmpty,
      reason:
          'fold and fence writes are dolt_ignore\'d; the named tables were '
          'staged and committed by the cadence',
    );

    final status = await server.runDolt([
      'status',
    ], cwd: server.databaseDir(database));
    expect(status.exitCode, 0, reason: '${status.stderr}');
    expect(status.stdout, contains('working tree clean'));
  });

  // ── guard 2 ───────────────────────────────────────────────────────────────

  test('guard 2 — force-ban: no source force-adds, and the sprung trap is '
      'caught by guard 1\'s own check', () async {
    // (a) The ban, in source. Comments discuss `dolt add --force` at length —
    // strip them, then no executable text may carry it.
    final lib = Directory('lib');
    expect(
      lib.existsSync(),
      isTrue,
      reason: 'run from the package root (dart test does)',
    );
    final sources = lib
        .listSync(recursive: true)
        .whereType<File>()
        .where((file) => file.path.endsWith('.dart'));
    expect(sources, isNotEmpty);
    for (final file in sources) {
      final code = _stripComments(file.readAsStringSync());
      expect(
        code,
        isNot(contains('--force')),
        reason: '${file.path} force-adds — banned in all grid tooling (T3)',
      );
      expect(
        code.toLowerCase(),
        isNot(contains('dolt add -f')),
        reason: '${file.path} force-adds under the short flag',
      );
      // A `-f` anywhere in a CLI add's argument list, not only adjacent.
      expect(
        RegExp(
          r'dolt\s+add\b[^\n]*\s-f\b',
          caseSensitive: false,
        ).hasMatch(code),
        isFalse,
        reason: '${file.path} force-adds via -f in dolt add args',
      );
      // The SQL procedure form — the spelling this package actually uses.
      for (final call in RegExp(
        r'DOLT_ADD\s*\(([^)]*)',
        caseSensitive: false,
      ).allMatches(code)) {
        expect(
          RegExp(r'''['"]\s*(--force|-f)\b''').hasMatch(call.group(1) ?? ''),
          isFalse,
          reason:
              '${file.path} calls DOLT_ADD with a force argument — banned in '
              'all grid tooling (T3)',
        );
      }
    }

    // (b) The trap, sprung on a scratch database: force-adding an ignored
    // table tracks it forever. Every later fold write then reads as dirt,
    // `DOLT_ADD('-A')` refuses to stage it (so `-Am`-shaped commits silently
    // stop capturing it), and the working set never returns to clean.
    const database = 'g2_force';
    final conn = await openDatabase(database);
    final appender = TrajectoryAppender(
      db: conn,
      station: 'g2',
      commitCadence: Duration.zero,
      commitMinInterval: Duration.zero,
    );
    expect(await appender.claimEpoch(pid: 1, pgid: 1), isA<EpochClaimed>());
    expect(
      await appender.append(
        const AttemptNote(
          sessionId: 's-g2',
          body: 'before the trap',
          channel: 'ops',
          noteOrdinal: 1,
        ),
      ),
      isA<Appended>(),
    );
    expect(await dirtyTables(conn), isEmpty);

    await conn.execute("CALL DOLT_ADD('--force', 'proj_meta')");
    expect(
      await dirtyTables(conn),
      contains('proj_meta'),
      reason: 'the status-clean check must SEE the force-add',
    );
    await conn.execute("CALL DOLT_COMMIT('-m', 'the sprung trap')");
    expect(await dirtyTables(conn), isEmpty); // clean for exactly one moment

    expect(
      await appender.append(
        const AttemptNote(
          sessionId: 's-g2',
          body: 'after the trap',
          channel: 'ops',
          noteOrdinal: 2,
        ),
      ),
      isA<Appended>(),
    );
    expect(
      await dirtyTables(conn),
      contains('proj_meta'),
      reason: 'a tracked projection dirties on every fold write, forever',
    );

    await conn.execute("CALL DOLT_ADD('-A')");
    final staged = await conn.execute(
      "SELECT staged FROM dolt_status WHERE table_name = 'proj_meta'",
    );
    expect(
      staged.rows.single['staged'],
      '0',
      reason:
          'plain -A never stages an ignored table — the sprung form '
          'silently stops -Am-shaped commits from capturing it',
    );

    final status = await server.runDolt([
      'status',
    ], cwd: server.databaseDir(database));
    expect(status.stdout, isNot(contains('working tree clean')));
  });

  // ── guard 3 ───────────────────────────────────────────────────────────────

  test('guard 3 — dolt commits are counted from dolt_log, and an empty '
      'DOLT_COMMIT does not inflate the count', () async {
    const database = 'g3_commits';
    final conn = await openDatabase(database);
    var now = DateTime.utc(2026, 8, 31, 12);
    final appender = TrajectoryAppender(
      db: conn,
      station: 'g3',
      clock: () => now,
      // The shipped cadence, driven by a controlled clock.
    );
    expect(await appender.claimEpoch(pid: 1, pgid: 1), isA<EpochClaimed>());
    final baseline = await doltLogCount(conn);

    Future<void> note(int ordinal) async {
      final outcome = await appender.append(
        AttemptNote(
          sessionId: 's-g3',
          body: 'note $ordinal',
          channel: 'ops',
          noteOrdinal: ordinal,
        ),
      );
      expect(outcome, isA<Appended>());
    }

    // Inside the hard minimum interval: rows land, no commit.
    await note(1);
    now = now.add(const Duration(seconds: 5));
    await note(2);
    expect(await doltLogCount(conn), baseline);
    expect(appender.verifiedDoltCommits, 0);
    expect(appender.pendingRows, 2);

    // Past the minimum but inside the cadence: still no commit.
    now = now.add(const Duration(seconds: 6));
    await note(3);
    expect(await doltLogCount(conn), baseline);

    // Cadence elapsed: exactly one commit for the whole batch — commit COUNT,
    // not row count, is the storage lever (probe T7b).
    now = now.add(const Duration(seconds: 31));
    await note(4);
    expect(await doltLogCount(conn), baseline + 1);
    expect(appender.verifiedDoltCommits, 1);
    expect(appender.pendingRows, 0);

    // A boundary event inside the hard minimum does NOT commit.
    now = now.add(const Duration(seconds: 2));
    expect(
      await appender.append(
        AttemptTerminal(
          attemptId: mintUlid(),
          sessionId: 's-g3',
          outcome: TerminalOutcome.succeeded,
        ),
      ),
      isA<Appended>(),
    );
    expect(await doltLogCount(conn), baseline + 1);

    // Past the minimum, the pending boundary fires without waiting out the
    // 30 s cadence.
    now = now.add(const Duration(seconds: 11));
    await appender.doltCommitIfDue();
    expect(await doltLogCount(conn), baseline + 2);
    expect(appender.verifiedDoltCommits, 2);

    // The T7 measurement trap: DOLT_COMMIT with nothing staged is a silent
    // no-op under --skip-empty. Its return says nothing; dolt_log arbitrates.
    await conn.execute("CALL DOLT_COMMIT('--skip-empty', '-m', 'nothing')");
    expect(await doltLogCount(conn), baseline + 2);
    expect(appender.verifiedDoltCommits, 2);

    // And a due-check with nothing pending never even reaches the server.
    await appender.doltCommitIfDue();
    expect(await doltLogCount(conn), baseline + 2);
  });

  // ── guard 4 ───────────────────────────────────────────────────────────────

  test('guard 4 — a CLI op inside the database dir runs under --doltcfg-dir '
      'discipline without a multiple-.doltcfg abort', () async {
    const database = 'g4_cfg';
    await openDatabase(database);
    final databaseDir = server.databaseDir(database);

    Future<void> expectDisciplinedOpSucceeds(String label) async {
      final result = await server.runDolt(
        ['sql', '-q', 'SELECT COUNT(*) FROM dolt_log'],
        cwd: databaseDir,
        doltcfgDir: server.doltcfgDirPath,
      );
      final output = '${result.stdout}${result.stderr}';
      expect(result.exitCode, 0, reason: '$label: $output');
      expect(
        output,
        isNot(contains('multiple .doltcfg')),
        reason: '$label: the T1 trap fired despite --doltcfg-dir',
      );
    }

    await expectDisciplinedOpSucceeds('single cfg dir');
    expect(
      Directory(p.join(databaseDir, '.doltcfg')).existsSync(),
      isFalse,
      reason: 'a disciplined op must not mint a second .doltcfg to trip over',
    );

    // Now the trap layout itself — a .doltcfg in the database dir as well as
    // the data dir — which is what --doltcfg-dir exists to disambiguate.
    final second = Directory(p.join(databaseDir, '.doltcfg'))
      ..createSync(recursive: true);
    addTearDown(() => second.deleteSync(recursive: true));
    final privileges = File(p.join(server.doltcfgDirPath, 'privileges.db'));
    if (privileges.existsSync()) {
      privileges.copySync(p.join(second.path, 'privileges.db'));
    }
    await expectDisciplinedOpSucceeds('two cfg dirs');
  });

  // ── guard 5 ───────────────────────────────────────────────────────────────

  test('guard 5 — a branch change fails closed: the pin refuses and the '
      'appender halts instead of committing off main', () async {
    const database = 'g5_branch';
    final conn = await openDatabase(database);
    var now = DateTime.utc(2026, 8, 31, 12);
    final appender = TrajectoryAppender(
      db: conn,
      station: 'g5',
      clock: () => now,
    );
    expect(await appender.claimEpoch(pid: 1, pgid: 1), isA<EpochClaimed>());
    expect(
      await appender.append(
        const AttemptNote(
          sessionId: 's-g5',
          body: 'on main',
          channel: 'ops',
          noteOrdinal: 1,
        ),
      ),
      isA<Appended>(),
    );
    expect(appender.pendingRows, 1); // inside the hard minimum: nothing staged

    await conn.execute("CALL DOLT_CHECKOUT('-b', 'g5_scratch')");

    // The connect-time invariant, re-asserted on the live session.
    await expectLater(
      conn.assertMainBranch(),
      throwsA(isA<TrajectoryConnectionException>()),
    );

    // Probe T3's consequence, the reason the pin exists: each branch has its
    // own working set, so every dolt_ignore'd projection vanishes off main.
    await expectLater(
      conn.execute('SELECT * FROM proj_meta'),
      throwsA(isA<MySQLServerException>()),
    );

    // The next commit-due check refuses rather than committing to the new
    // branch, and the appender is halted from then on.
    now = now.add(const Duration(seconds: 61));
    await expectLater(appender.doltCommitIfDue(), throwsA(isA<StateError>()));
    expect(appender.isHalted, isTrue);
    expect(
      await appender.append(
        const AttemptNote(
          sessionId: 's-g5',
          body: 'after the branch change',
          channel: 'ops',
          noteOrdinal: 2,
        ),
      ),
      isA<AppendCorruptionHalt>(),
    );
  });

  // ── guard 6 ───────────────────────────────────────────────────────────────

  test('guard 6 — @@dolt_force_transaction_commit is refused on a live '
      'session and at connect', () async {
    const database = 'g6_sessionvar';
    final conn = await openDatabase(database);

    // Connect pinned the session to 0.
    final pinned = await conn.execute(
      'SELECT @@dolt_force_transaction_commit AS v',
    );
    expect(pinned.rows.single['v'], anyOf('0', 'false'));

    // Set mid-life by anyone at all: the layer refuses.
    await conn.execute('SET @@dolt_force_transaction_commit = 1');
    await expectLater(
      conn.assertForceCommitUnset(),
      throwsA(isA<TrajectoryConnectionException>()),
    );

    // Set globally, so a fresh session inherits it: connect refuses, and the
    // session never becomes usable.
    await admin.execute('SET @@GLOBAL.dolt_force_transaction_commit = 1');
    try {
      await expectLater(
        TrajectoryConnection.connect(server.endpointFor(database)),
        throwsA(isA<TrajectoryConnectionException>()),
      );
    } finally {
      await admin.execute('SET @@GLOBAL.dolt_force_transaction_commit = 0');
    }

    // With the global cleared, a fresh session connects and reads 0 again.
    final reconnected = await TrajectoryConnection.connect(
      server.endpointFor(database),
    );
    addTearDown(reconnected.close);
    final reset = await reconnected.execute(
      'SELECT @@dolt_force_transaction_commit AS v',
    );
    expect(reset.rows.single['v'], anyOf('0', 'false'));
  });

  // ── guard 7 ───────────────────────────────────────────────────────────────

  group('guard 7 — the CHECK-refusal pin', () {
    late TrajectoryConnection conn;
    var epochSeq = 1000;
    var ordinal = 0;

    setUp(() async {
      conn = await openDatabase('g7_checks');
    });

    /// A minimally-valid trajectory row; [overrides] inject the violation.
    Future<void> insertRow(Map<String, Object?> overrides) async {
      final key = 'ck-row:${ordinal++}';
      final row = <String, Object?>{
        'boot_epoch': 1,
        'epoch_seq': epochSeq++,
        'record_id': mintUlid(),
        'idem_key': sha256Hex(key),
        'idem_key_text': key,
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
      await conn.execute(
        'INSERT INTO trajectory (${columns.join(', ')}) '
        'VALUES (${columns.map((column) => ':$column').join(', ')})',
        row,
      );
    }

    test('the baseline row inserts', () async {
      await insertRow(const {});
    });

    // All seven §4 CHECKs, including the two post-probe additions
    // (ck_grant_link, ck_seat) the cert round added.
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
}

/// Dart source with comments removed — the force-ban grep asserts on
/// executable text only, since the ban is itself documented in comments.
String _stripComments(String source) => source
    .replaceAll(RegExp(r'/\*.*?\*/', dotAll: true), '')
    .replaceAll(RegExp(r'//[^\n]*'), '');
