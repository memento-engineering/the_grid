import 'dart:convert';

import 'package:beads_dart/beads_dart.dart';
import 'package:mysql_client/exception.dart';
import 'package:test/test.dart';

import '../support/schema_probe_rows.dart';

void main() {
  const allStatuses =
      'status=open OR status=in_progress OR status=blocked OR '
      'status=deferred OR status=closed';
  test('CLI snapshot uses one broad graph query', () async {
    final runner = _SnapshotRunner();
    final snapshot = await CliSnapshotReader(BdCliService(runner)).read();

    expect(snapshot.beadsById['tg-gate']?.issueType, const IssueType('gate'));
    expect(snapshot.beadsById['tg-task']?.status, BeadStatus.closed);
    expect(snapshot.dependencies.single.type, DependencyType.blocks);
    expect(snapshot.readyIds, contains('tg-gate'));
    expect(runner.calls, [
      ['query', allStatuses, '--all', '--json', '--limit', '0'],
      ['ready', '--json', '--limit', '0'],
      ['dep', 'list', 'tg-gate', 'tg-task', '--json'],
    ]);
    expect(
      runner.calls.any(
        (args) => const {
          'export',
          'show',
          'statuses',
          'types',
          'list',
        }.contains(args.first),
      ),
      isFalse,
    );
  });

  test('CLI snapshot skips dependency subprocess for an empty graph', () async {
    final runner = _SnapshotRunner()..empty = true;
    final snapshot = await CliSnapshotReader(BdCliService(runner)).read();
    expect(snapshot.beadsById, isEmpty);
    expect(runner.calls, [
      ['query', allStatuses, '--all', '--json', '--limit', '0'],
      ['ready', '--json', '--limit', '0'],
    ]);
  });

  test('CLI snapshot propagates broad-query command failures', () async {
    final runner = _SnapshotRunner()..failQuery = true;
    await expectLater(
      CliSnapshotReader(BdCliService(runner)).read(),
      throwsA(isA<BdCommandFailed>()),
    );
    expect(runner.calls, [
      ['query', allStatuses, '--all', '--json', '--limit', '0'],
    ]);
  });

  test('CLI snapshot reads and derives dependencies for 120 beads', () async {
    final runner = _SnapshotRunner()..largeGraph = true;
    final snapshot = await CliSnapshotReader(BdCliService(runner)).read();

    expect(snapshot.beadsById, hasLength(120));
    expect(snapshot.beadsById.keys, containsAll(['tg-0', 'tg-119']));
    expect(runner.calls.first, [
      'query',
      allStatuses,
      '--all',
      '--json',
      '--limit',
      '0',
    ]);
    final dependencyCalls = runner.calls
        .where(
          (args) => args.length >= 2 && args[0] == 'dep' && args[1] == 'list',
        )
        .toList(growable: false);
    expect(dependencyCalls, hasLength(3));
    final derivedIds = dependencyCalls
        .expand((args) => args.skip(2).takeWhile((arg) => arg != '--json'))
        .toSet();
    expect(derivedIds, hasLength(120));
    expect(derivedIds, containsAll(['tg-0', 'tg-119']));
  });

  // tg-xh5d RULING 2026-09-13: BOTH read paths surface bd's native `external:`
  // rows. bd stores them and resolves nothing against them, so a path that
  // cannot see one would admit the work it blocks.
  test('the CLI path carries the external rows bd\'s RESOLVING read '
      'drops', () async {
    final runner = _SnapshotRunner(
      queryRows: const [
        {
          'id': 'tg-consumer',
          'issue_type': 'task',
          'status': 'open',
          'dependencies': [
            {
              'issue_id': 'tg-consumer',
              'depends_on_id': 'external:power_station:pow-cap',
              'type': 'blocks',
            },
            {
              'issue_id': 'tg-consumer',
              'depends_on_id': 'tg-local',
              'type': 'blocks',
            },
          ],
        },
      ],
      // bd's resolving read answers with the ISSUE each dependency points at,
      // so only the LOCAL edge comes back here — the external row has no issue
      // in this store to resolve to.
      dependencyRows: const [
        {
          'issue_id': 'tg-consumer',
          'depends_on_id': 'tg-local',
          'type': 'blocks',
        },
      ],
      readyRows: const [],
    );

    final snapshot = await CliSnapshotReader(BdCliService(runner)).read();

    expect(
      snapshot.dependencies.map((dep) => dep.dependsOnId),
      containsAll(['tg-local', 'external:power_station:pow-cap']),
      reason:
          'the external row rides in from the RECORD surface beside the '
          'local edges bd resolved',
    );
    expect(
      snapshot.dependencies.where((dep) => dep.dependsOnId == 'tg-local'),
      hasLength(1),
      reason: 'a row both surfaces return lands once',
    );
  });

  test(
    'the CLI path REFUSES when the record surface stops carrying rows',
    () async {
      // The control: bd RESOLVED edges for these beads, so the store has
      // dependency rows — a record surface that returns none is dropping them,
      // and a dropped cross-project row silently admits the work it blocks.
      final runner = _SnapshotRunner(
        queryRows: const [
          {'id': 'tg-consumer', 'issue_type': 'task', 'status': 'open'},
        ],
        dependencyRows: const [
          {
            'issue_id': 'tg-consumer',
            'depends_on_id': 'tg-local',
            'type': 'blocks',
          },
        ],
        readyRows: const [],
      );

      await expectLater(
        CliSnapshotReader(BdCliService(runner)).read(),
        throwsA(
          isA<BdExternalDepSurfaceUnavailable>().having(
            (e) => e.message,
            'message',
            allOf(
              contains('no bd surface carried its `external:` dependency rows'),
              contains('depends_on_external'),
            ),
          ),
        ),
        reason:
            'never fail open: no snapshot at all beats a snapshot that '
            'cannot see the blocker',
      );
    },
  );

  test('the refusal is REPORTED once per episode, then rethrown', () async {
    // A thrown refusal lands on BeadsRepository.errors, which nothing in the
    // resident listens to — so the composer hands the reader the station's
    // cross-store sink and the operator sees WHICH store went unreadable.
    final runner = _SnapshotRunner(
      queryRows: const [
        {'id': 'tg-consumer', 'issue_type': 'task', 'status': 'open'},
      ],
      dependencyRows: const [
        {
          'issue_id': 'tg-consumer',
          'depends_on_id': 'tg-local',
          'type': 'blocks',
        },
      ],
      readyRows: const [],
    );
    final reported = <String>[];
    final reader = CliSnapshotReader(
      BdCliService(runner),
      onRefusal: reported.add,
    );

    await expectLater(reader.read(), throwsA(isA<BdException>()));
    await expectLater(reader.read(), throwsA(isA<BdException>()));
    expect(reported, hasLength(1), reason: 'rising edge, not once per refresh');
    expect(reported.single, contains('REFUSED to read this store'));

    // A bd that starts carrying rows again recovers, and a later relapse is
    // reported anew rather than remembered as already-said.
    runner.queryRows = const [
      {
        'id': 'tg-consumer',
        'issue_type': 'task',
        'status': 'open',
        'dependencies': [
          {
            'issue_id': 'tg-consumer',
            'depends_on_id': 'tg-local',
            'type': 'blocks',
          },
        ],
      },
    ];
    expect((await reader.read()).dependencies, hasLength(1));
    runner.queryRows = const [
      {'id': 'tg-consumer', 'issue_type': 'task', 'status': 'open'},
    ];
    await expectLater(reader.read(), throwsA(isA<BdException>()));
    expect(reported, hasLength(2));
  });

  test(
    'a ready-only bead\'s edges are not evidence the surface dropped rows',
    () async {
      // `bd ready` can fall back a bead the broad record query did not carry.
      // Its resolved edges say nothing about what the RECORD surface carries, so
      // they must not trip the refusal.
      final runner = _SnapshotRunner(
        queryRows: const [
          {'id': 'tg-plain', 'issue_type': 'task', 'status': 'open'},
        ],
        readyRows: const [
          {'id': 'tg-wisp.1', 'issue_type': 'task', 'status': 'open'},
        ],
        dependencyRows: const [
          {
            'issue_id': 'tg-wisp.1',
            'depends_on_id': 'tg-wisp',
            'type': 'parent-child',
          },
        ],
      );

      final snapshot = await CliSnapshotReader(BdCliService(runner)).read();

      expect(snapshot.beadsById.keys, containsAll(['tg-plain', 'tg-wisp.1']));
      expect(snapshot.dependencies.single.issueId, 'tg-wisp.1');
    },
  );

  test('a store with no dependency rows at all is not a refusal', () async {
    final runner = _SnapshotRunner(
      queryRows: const [
        {'id': 'tg-alone', 'issue_type': 'task', 'status': 'open'},
      ],
      dependencyRows: const [],
      readyRows: const [],
    );

    final snapshot = await CliSnapshotReader(BdCliService(runner)).read();

    expect(snapshot.dependencies, isEmpty);
    expect(snapshot.beadsById.keys, ['tg-alone']);
  });

  const endpoint = DoltEndpoint(
    host: '127.0.0.1',
    port: 34947,
    database: 'tg',
    user: 'root',
    password: 'fake',
  );

  test(
    'the SQL path carries an external row through depends_on_external',
    () async {
      // The target expression COALESCEs the three typed target columns, so a row
      // whose target lives in `depends_on_external` reaches the frontier as the
      // `external:` wire string the consumer was blocked on. The column is
      // REQUIRED by the connect-time shape probe, so a store that cannot express
      // one stands this path down rather than dropping the edges.
      final dolt = DoltQueryService(
        endpoint,
        connectionFactory: (_) async => _SnapshotDoltConnection(
          failOnQuery: null,
          failure: StateError('unused'),
          closeOnFailure: false,
          issueRows: const [
            {
              'id': 'tg-consumer',
              'title': 'held by a capability',
              'issue_type': 'task',
              'status': 'open',
            },
          ],
          dependencyRows: const [
            {
              'issue_id': 'tg-consumer',
              'depends_on_id': 'external:power_station:pow-cap',
              'type': 'blocks',
            },
          ],
        ),
      );
      addTearDown(dolt.close);
      await dolt.connect();

      expect(
        dolt.dependenciesSelect,
        contains('depends_on_external'),
        reason: 'ADR-0000 A44: the cross-store edge lives in that column',
      );
      final snapshot = await SqlSnapshotReader(
        dolt: dolt,
        bd: BdCliService(_SnapshotRunner()..empty = true),
      ).read();
      expect(
        snapshot.dependencies.single.dependsOnId,
        'external:power_station:pow-cap',
      );
    },
  );

  test('SQL snapshot absorbs a reaped connection below the reader', () async {
    var opened = 0;
    final dolt = DoltQueryService(
      endpoint,
      poolSize: 1,
      connectionFactory: (_) async {
        opened++;
        return _SnapshotDoltConnection(
          failOnQuery: opened == 1 ? 3 : null,
          failure: const MySQLClientException(
            'Can not execute query: connection closed',
          ),
          closeOnFailure: true,
        );
      },
    );
    addTearDown(dolt.close);
    await dolt.connect();
    final runner = _SnapshotRunner()..empty = true;

    final snapshot = await SqlSnapshotReader(
      dolt: dolt,
      bd: BdCliService(runner),
    ).read();

    expect(snapshot.beadsById, isEmpty);
    expect(opened, 2);
    expect(runner.calls, [
      ['ready', '--json', '--limit', '0'],
    ]);
  });

  test(
    'SQL snapshot propagates a persistent error without CLI degrade',
    () async {
      final persistentError = StateError('persistent SQL failure');
      final dolt = DoltQueryService(
        endpoint,
        connectionFactory: (_) async => _SnapshotDoltConnection(
          failOnQuery: 3,
          failure: persistentError,
          closeOnFailure: false,
        ),
      );
      addTearDown(dolt.close);
      await dolt.connect();
      final runner = _SnapshotRunner()..empty = true;

      await expectLater(
        SqlSnapshotReader(dolt: dolt, bd: BdCliService(runner)).read(),
        throwsA(same(persistentError)),
      );
      expect(runner.calls, isEmpty);
    },
  );

  test('ready-only fallback materializes rows and broad rows win for both '
      'snapshot readers', () async {
    const broad = [
      {
        'id': 'tg-shared',
        'title': 'broad-row',
        'issue_type': 'task',
        'status': 'open',
      },
    ];
    const ready = [
      {
        'id': 'tg-shared',
        'title': 'ready-fallback',
        'issue_type': 'task',
        'status': 'open',
      },
      {
        'id': 'tg-ready-only',
        'title': 'ready-only',
        'issue_type': 'task',
        'status': 'open',
      },
    ];

    void expectMerged(GraphSnapshot snapshot) {
      expect(
        snapshot.beadsById.keys,
        containsAll(['tg-shared', 'tg-ready-only']),
      );
      expect(snapshot.readyIds, {'tg-shared', 'tg-ready-only'});
      expect(snapshot.beadsById['tg-shared']!.title, 'broad-row');
      expect(snapshot.beadsById['tg-ready-only']!.title, 'ready-only');
    }

    final cliRunner = _SnapshotRunner(
      queryRows: broad,
      readyRows: ready,
      dependencyRows: const [],
    );
    expectMerged(await CliSnapshotReader(BdCliService(cliRunner)).read());
    expect(cliRunner.calls, [
      ['query', allStatuses, '--all', '--json', '--limit', '0'],
      ['ready', '--json', '--limit', '0'],
      ['dep', 'list', 'tg-shared', 'tg-ready-only', '--json'],
    ]);

    final dolt = DoltQueryService(
      endpoint,
      connectionFactory: (_) async => _SnapshotDoltConnection(
        failOnQuery: null,
        failure: StateError('unused'),
        closeOnFailure: false,
        issueRows: const [
          {
            'id': 'tg-shared',
            'title': 'broad-row',
            'issue_type': 'task',
            'status': 'open',
          },
        ],
      ),
    );
    addTearDown(dolt.close);
    await dolt.connect();
    final sqlRunner = _SnapshotRunner(readyRows: ready);

    expectMerged(
      await SqlSnapshotReader(dolt: dolt, bd: BdCliService(sqlRunner)).read(),
    );
    expect(sqlRunner.calls, [
      ['ready', '--json', '--limit', '0'],
    ]);
  });
}

class _SnapshotRunner implements BdRunner {
  _SnapshotRunner({this.queryRows, this.readyRows, this.dependencyRows});

  final List<List<String>> calls = [];
  List<Map<String, dynamic>>? queryRows;
  final List<Map<String, dynamic>>? readyRows;
  final List<Map<String, dynamic>>? dependencyRows;
  bool empty = false;
  bool failQuery = false;
  bool largeGraph = false;

  @override
  Future<BdResult> run(
    List<String> args, {
    Duration? timeout,
    String? stdin,
  }) async {
    calls.add(List.unmodifiable(args));
    if (args.first == 'query') {
      if (failQuery) {
        return const BdResult(exitCode: 1, stdout: '', stderr: 'query failed');
      }
      if (largeGraph) {
        return _list([
          for (var i = 0; i < 120; i++)
            {'id': 'tg-$i', 'issue_type': 'task', 'status': 'open'},
        ]);
      }
      if (queryRows != null) return _list(queryRows!);
      return _list(
        empty
            ? const []
            // bd's RECORD surface embeds each bead's dependency ROWS beside
            // the bead, which is where a cross-project row arrives.
            : const [
                {
                  'id': 'tg-gate',
                  'issue_type': 'gate',
                  'status': 'open',
                  'dependencies': [
                    {
                      'issue_id': 'tg-gate',
                      'depends_on_id': 'tg-task',
                      'type': 'blocks',
                    },
                  ],
                },
                {'id': 'tg-task', 'issue_type': 'task', 'status': 'closed'},
              ],
      );
    }
    if (args.first == 'dep') {
      if (largeGraph) return _list(const []);
      if (dependencyRows != null) return _list(dependencyRows!);
      return _list(const [
        {'issue_id': 'tg-gate', 'depends_on_id': 'tg-task', 'type': 'blocks'},
      ]);
    }
    if (args.first == 'ready') {
      if (largeGraph) return _list(const []);
      if (readyRows != null) return _list(readyRows!);
      return _list(
        empty
            ? const []
            : const [
                {'id': 'tg-gate', 'issue_type': 'gate', 'status': 'open'},
              ],
      );
    }
    throw StateError('unexpected call: $args');
  }

  BdResult _list(List<Map<String, dynamic>> data) => BdResult(
    exitCode: 0,
    stdout: jsonEncode({'schema_version': 1, 'data': data}),
    stderr: '',
  );
}

class _SnapshotDoltConnection implements DoltConnection {
  _SnapshotDoltConnection({
    required this.failOnQuery,
    required this.failure,
    required this.closeOnFailure,
    this.issueRows = const [],
    this.dependencyRows = const [],
  });

  final int? failOnQuery;
  final Object failure;
  final bool closeOnFailure;
  final List<Map<String, Object?>> issueRows;
  final List<Map<String, Object?>> dependencyRows;
  var _open = true;
  var _queryCount = 0;

  @override
  bool get connected => _open;

  @override
  Future<List<Map<String, Object?>>> query(String sql) async {
    _queryCount++;
    if (_queryCount == failOnQuery) {
      if (closeOnFailure) _open = false;
      throw failure;
    }
    if (sql == 'SELECT COALESCE(MAX(version), 0) AS v FROM schema_migrations') {
      return const [
        {'v': 53},
      ];
    }
    if (sql == DoltSchemaShape.probeSql) return kV53ProbeRows;
    if (sql == DoltQueryService.issuesSelect) return issueRows;
    if (sql.contains('FROM dependencies')) return dependencyRows;
    return const [];
  }

  @override
  Future<void> close() async {
    _open = false;
  }
}
