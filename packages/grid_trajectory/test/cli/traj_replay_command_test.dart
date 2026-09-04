/// `traj replay` — the QUIESCE FENCE, the P1 reshape step, `--check`
/// reporting, and per-projection selection, all over a scripted connection.
///
/// The load-bearing assertion in here is the fence's ORDERING: an armed home
/// must be refused before a single `proj_*` statement is issued. A replay
/// scans the whole log before its transaction and rewrites the table from that
/// pre-transaction fold, so a rebuild that starts against a live appender has
/// already lost — nothing downstream can detect the hole afterwards.
library;

import 'dart:convert';
import 'dart:io';

import 'package:args/command_runner.dart';
import 'package:grid_trajectory/grid_trajectory.dart';
import 'package:test/test.dart';

import '../support/scripted_db.dart';

void main() {
  late Directory home;
  late ScriptedDb db;
  late List<String> out;
  late List<String> err;

  DoltServerListener resolve(String gridHome) => const DoltServerListener(
    host: '127.0.0.1',
    port: 3306,
    configPath: '/dev/null',
  );

  /// The service credential the verb opens with — present unless a test
  /// removes it.
  void seedSecret() {
    final file = File(trajectorySecretPath(home.path));
    file.parent.createSync(recursive: true);
    file.writeAsStringSync('service-pw\n');
  }

  /// RS-2's lock file, holding [pid].
  void writeLock({required int pid, String? raw}) {
    final file = File(stationLockPath(home.path));
    file.parent.createSync(recursive: true);
    file.writeAsStringSync(
      raw ??
          jsonEncode({
            'pid': pid,
            'pgid': pid,
            'startedAt': DateTime.utc(2026, 9, 1).toIso8601String(),
          }),
    );
  }

  /// P1 already at the current projection shape (the reshape is a no-op).
  void seedCurrentShape() => db.on(
    'information_schema.columns',
    result: const SqlResult(
      rows: [
        {'name': 'terminal_provenance'},
        {'name': 'unknown_reason'},
        {'name': 'substation'},
      ],
    ),
  );

  Future<int> replay({
    List<String> projections = replayProjections,
    bool check = false,
    bool Function(int pid) isPidAlive = _neverAlive,
  }) => runTrajReplay(
    gridHome: home.path,
    projections: projections,
    check: check,
    connect: (_) async => db,
    resolve: resolve,
    isPidAlive: isPidAlive,
    clock: () => DateTime.utc(2026, 9, 1, 12),
    out: out.add,
    err: err.add,
  );

  setUp(() {
    home = Directory.systemTemp.createTempSync('traj-replay-');
    db = ScriptedDb();
    out = [];
    err = [];
    seedSecret();
  });

  tearDown(() => home.deleteSync(recursive: true));

  group('the quiesce fence (J8-B3 — replay is quiesce-only, no override)', () {
    test('a LIVE station lock refuses before any projection table is '
        'touched', () async {
      writeLock(pid: 4242);
      expect(await replay(isPidAlive: (_) => true), 1);
      expect(err.join('\n'), contains('REFUSED'));
      expect(err.join('\n'), contains('pid 4242'));
      expect(
        db.matching('proj_'),
        isEmpty,
        reason:
            'the fence must fire BEFORE the first proj_* statement — a '
            'started replay has already lost the write-write race',
      );
      expect(db.matching('DELETE FROM'), isEmpty);
      expect(db.matching('DROP TABLE'), isEmpty);
    });

    test('an UNREADABLE lock refuses too — a torn lock cannot prove the '
        'station is down', () async {
      writeLock(pid: 0, raw: '{not json');
      expect(await replay(), 1);
      expect(err.join('\n'), contains('no readable pid'));
      expect(db.matching('proj_'), isEmpty);
    });

    test('a STALE lock over a live epoch authority refuses — a harness can '
        'outlive its supervisor\'s lock', () async {
      writeLock(pid: 111);
      db.on(
        'FROM traj_epoch',
        result: const SqlResult(
          rows: [
            {
              'station': 'tranquility',
              'epoch': '7',
              'pid': '222',
              'pgid': '222',
            },
          ],
        ),
      );
      expect(await replay(isPidAlive: (pid) => pid == 222), 1);
      expect(err.join('\n'), contains('epoch 7'));
      expect(err.join('\n'), contains('pid 222'));
      expect(db.matching('proj_'), isEmpty);
    });

    test('no lock at all is QUIESCED — the epoch rows are history and their '
        'pids are recycled', () async {
      seedCurrentShape();
      // A live pid everywhere: with no lock file the epoch witness must not
      // even be consulted, or a long-provisioned home becomes unreplayable.
      expect(await replay(isPidAlive: (_) => true), 0);
      expect(db.matching('FROM traj_epoch'), isEmpty);
      expect(out.join('\n'), contains('quiesced: yes'));
    });

    test(
      'a stale lock with no live epoch authority proceeds, and says so',
      () async {
        seedCurrentShape();
        writeLock(pid: 111);
        expect(await replay(), 0);
        expect(out.join('\n'), contains('stale station.lock'));
        expect(db.matching('DELETE FROM proj_session_head'), hasLength(1));
      },
    );
  });

  group('the P1 reshape (r7 — V1-B1: DROP + re-CREATE, never ALTER)', () {
    test('a pre-cut home is reshaped, in order, before the replay', () async {
      db.on(
        'information_schema.columns',
        result: const SqlResult(
          rows: [
            {'name': 'session_id'},
            {'name': 'work_terminal_reason'},
          ],
        ),
      );
      expect(await replay(projections: const [sessionHeadProjection]), 0);

      final statements = db.log.map((call) => call.sql).toList();
      final drop = statements.indexWhere((s) => s.startsWith('DROP TABLE'));
      final create = statements.indexWhere(
        (s) => s.contains('CREATE TABLE IF NOT EXISTS proj_session_head'),
      );
      final scan = statements.indexWhere((s) => s.contains('FROM trajectory'));
      expect(drop, isNonNegative);
      expect(create, greaterThan(drop));
      expect(
        scan,
        greaterThan(create),
        reason: 'the replay that repopulates P1 runs after the new shape',
      );
      expect(
        statements.where((s) => s.contains('ALTER TABLE')),
        isEmpty,
        reason: 'an ALTER path is deliberately not built',
      );
      expect(out.join('\n'), contains('reshape: proj_session_head DROPped'));
    });

    test('a home already at the shape is not reshaped', () async {
      seedCurrentShape();
      expect(await replay(projections: const [sessionHeadProjection]), 0);
      expect(db.matching('DROP TABLE'), isEmpty);
      expect(out.join('\n'), isNot(contains('reshape:')));
    });

    test('the replay stamps the BUMPED fold_version', () async {
      seedCurrentShape();
      expect(await replay(projections: const [sessionHeadProjection]), 0);
      final meta = db.matching('INSERT INTO proj_meta').single;
      expect(meta.params!['fold_version'], sessionHeadFoldVersion);
      expect(sessionHeadFoldVersion, 2);
    });
  });

  group('the journal substation rename (tg-j1zn)', () {
    /// A journal still at the pre-tg-j1zn shape. Registered BEFORE
    /// [seedCurrentShape] so it wins for the journal probe only.
    void seedStaleJournal() => db.on(
      "table_name = 'trajectory'",
      result: const SqlResult(
        rows: [
          {'name': 'seat'},
        ],
      ),
    );

    test(
      'a stale journal is RENAMEd before any projection is replayed',
      () async {
        seedStaleJournal();
        seedCurrentShape();
        expect(await replay(), 0);

        final alters = db.matching('ALTER TABLE trajectory');
        expect(alters.map((call) => call.sql), [
          'ALTER TABLE trajectory DROP CHECK ck_seat',
          'ALTER TABLE trajectory RENAME COLUMN seat TO substation',
          'ALTER TABLE trajectory ADD CONSTRAINT ck_substation '
              'CHECK (work_bead_id IS NULL OR substation IS NOT NULL)',
        ]);
        expect(
          db.log.indexOf(alters.last),
          lessThan(db.log.indexWhere((call) => call.sql.contains('proj_'))),
          reason: 'the codec reads `substation`; every fold decodes through it',
        );
        expect(out.join('\n'), contains('trajectory.substation'));
      },
    );

    test('a current journal is left alone', () async {
      seedCurrentShape();
      expect(await replay(), 0);
      expect(db.matching('ALTER TABLE trajectory'), isEmpty);
    });

    test('--check reports the pending rename without performing it', () async {
      seedStaleJournal();
      seedCurrentShape();
      expect(await replay(check: true), 0);
      expect(out.join('\n'), contains('migrate: PENDING'));
      expect(db.matching('ALTER TABLE'), isEmpty);
    });
  });

  test('--check reports a stale projection before its first generation and '
      'does not migrate it', () async {
    db
      ..on("table_name = 'trajectory'")
      ..on(
        'information_schema.columns',
        result: const SqlResult(
          rows: [
            {'name': 'terminal_provenance'},
            {'name': 'unknown_reason'},
            {'name': 'seat'},
          ],
        ),
      );

    expect(await replay(check: true), 0);
    final report = out.join('\n');
    expect(report, contains('migrate: PENDING — proj_session_head'));
    expect(report, contains('generations: none'));
    expect(db.matching('ALTER TABLE'), isEmpty);
    expect(db.matching('DROP TABLE'), isEmpty);
  });

  group('projection selection (replay is per-projection in the tree)', () {
    test('the default rebuilds all three', () async {
      seedCurrentShape();
      expect(await replay(), 0);
      expect(db.matching('DELETE FROM proj_session_head'), hasLength(1));
      expect(db.matching('DELETE FROM proj_step_cursor'), hasLength(1));
      expect(db.matching('DELETE FROM proj_process_identity'), hasLength(1));
    });

    test('a partial rebuild touches only what it names', () async {
      seedCurrentShape();
      expect(await replay(projections: const [stepCursorProjection]), 0);
      expect(db.matching('DELETE FROM proj_step_cursor'), hasLength(1));
      expect(db.matching('proj_session_head'), isEmpty);
      expect(db.matching('proj_process_identity'), isEmpty);
    });

    test(
      'an unknown projection is refused before anything is rebuilt',
      () async {
        seedCurrentShape();
        expect(await replay(projections: const ['p4']), 1);
        expect(err.join('\n'), contains('unknown projection'));
        expect(db.matching('DELETE FROM'), isEmpty);
      },
    );
  });

  group('--check (read-only: lag + the full generation set)', () {
    setUp(() {
      db
        ..on(
          'AS max_seq',
          result: const SqlResult(
            rows: [
              {'max_seq': '900', 'applied_seq': '300'},
            ],
          ),
        )
        ..on(
          'MIN(recorded_at)',
          result: const SqlResult(
            rows: [
              {'oldest': '2026-09-01 11:00:00.000000'},
            ],
          ),
        )
        ..on(
          'FROM proj_meta ORDER BY projection',
          result: const SqlResult(
            rows: [
              {
                'projection': 'fold',
                'fold_version': '2',
                'applied_seq': '300',
                'skipped': null,
                'rebuilt_at': '2026-09-01 10:00:00.000000',
              },
              {
                'projection': 'step_cursor',
                'fold_version': '1',
                'applied_seq': '120',
                'skipped': '{"step.transition@v2":3}',
                'rebuilt_at': null,
              },
            ],
          ),
        );
    });

    test('reports lag, staleness, and every proj_meta generation without '
        'rebuilding', () async {
      seedCurrentShape();
      expect(await replay(check: true), 0);
      final report = out.join('\n');
      expect(report, contains('600 record(s) behind head 900'));
      expect(report, contains('STALE'));
      expect(report, contains('generation: fold fold_version=2'));
      expect(report, contains('generation: step_cursor fold_version=1'));
      expect(report, contains('skipped={"step.transition@v2":3}'));
      expect(report, isNot(contains('migrate: PENDING')));
      expect(db.matching('DELETE FROM'), isEmpty);
      expect(db.matching('DROP TABLE'), isEmpty);
    });

    test('runs against an ARMED station and says so — the rebuild is what '
        'refuses, not the report', () async {
      seedCurrentShape();
      writeLock(pid: 4242);
      expect(await replay(check: true, isPidAlive: (_) => true), 0);
      expect(out.join('\n'), contains('quiesced: NO'));
      expect(out.join('\n'), contains('600 record(s) behind'));
      expect(db.matching('DELETE FROM'), isEmpty);
    });

    test('names a PENDING projection migration', () async {
      db.on(
        'information_schema.columns',
        result: const SqlResult(
          rows: [
            {'name': 'session_id'},
          ],
        ),
      );
      expect(await replay(check: true), 0);
      expect(out.join('\n'), contains('migrate: PENDING — proj_session_head'));
    });
  });

  group('opening the log', () {
    test(
      'an unprovisioned home is a refusal, never a silent rebuild',
      () async {
        File(trajectorySecretPath(home.path)).deleteSync();
        expect(await replay(), 1);
        expect(err.join('\n'), contains('never provisioned'));
        expect(db.log, isEmpty);
      },
    );

    test('an empty secret refuses', () async {
      File(trajectorySecretPath(home.path)).writeAsStringSync('  \n');
      expect(await replay(), 1);
      expect(err.join('\n'), contains('empty trajectory secret'));
    });

    test(
      'a replay that throws is reported and the session is closed',
      () async {
        seedCurrentShape();
        db.on('DELETE FROM proj_session_head', throwing: StateError('boom'));
        expect(await replay(projections: const [sessionHeadProjection]), 1);
        expect(err.join('\n'), contains('boom'));
        expect(db.closed, isTrue);
      },
    );
  });

  group('argument surface', () {
    CommandRunner<int> runner() =>
        CommandRunner<int>('grid', 'test')..addCommand(
          TrajReplayCommand(
            connect: (_) async => ScriptedDb(),
            resolve: resolve,
            isPidAlive: _neverAlive,
          ),
        );

    test('the grid home is required and never guessed', () async {
      expect(await runner().run(['replay']), 64);
    });

    test('a positional argument is a usage refusal', () async {
      expect(
        await runner().run(['replay', 'stray', '--state-workspace', '/tmp']),
        64,
      );
    });

    test('--projection only accepts the three real projections', () async {
      await expectLater(
        runner().run([
          'replay',
          '--state-workspace',
          '/tmp',
          '--projection',
          'p4',
        ]),
        throwsA(isA<UsageException>()),
      );
    });
  });
}

bool _neverAlive(int pid) => false;
