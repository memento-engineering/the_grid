import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:grid_controller/grid_controller.dart';
import 'package:test/test.dart';

import '../support/fake_bd_runner.dart';
import '../support/fixtures.dart';

void main() {
  group('BdCliService reads (FakeBdRunner + pinned fixtures)', () {
    test('ready() parses the ready envelope into Beads', () async {
      final runner = FakeBdRunner()
        ..stubCommand(
          'ready',
          BdReply(stdout: fixtureText('hq-ready-sample.json')),
        );
      final service = BdCliService(runner);

      final beads = await service.ready();

      expect(beads, hasLength(5));
      expect(beads.first.id, 'ga-bdzf');
      // argv: exactly `ready --json`.
      expect(runner.calls.single, ['ready', '--json']);
    });

    test('exportAll() parses all 25 export records from raw JSONL', () async {
      final runner = FakeBdRunner()
        ..stubCommand(
          'export',
          BdReply(stdout: fixtureText('hq-export-sample.jsonl')),
        );
      final service = BdCliService(runner);

      final snapshot = await service.exportAll();

      expect(snapshot.beads, hasLength(25));
      expect(snapshot.beads.first.id, 'ga-bdzf');
      // This HQ sample carries no edges; the parse-path for edges is covered
      // by the synthetic-dependencies test below.
      expect(snapshot.dependencies, isEmpty);
      // export is the single-spawn snapshot read: `export --all` (the
      // complete graph — `--all` subsumes `--include-infra` and lifts the
      // default template + ephemeral-wisp exclusions, export.go:96-126).
      expect(runner.calls.single, ['export', '--all']);
    });

    test(
      'exportAll() gathers inline dependency edges and skips non-issues',
      () async {
        // Built locally (not a pinned fixture): one issue with a dependencies
        // array, plus a memory record that must be skipped.
        final lines = [
          jsonEncode({
            '_type': 'issue',
            'id': 'tg-a',
            'title': 'A',
            'dependencies': [
              {'issue_id': 'tg-a', 'depends_on_id': 'tg-b', 'type': 'blocks'},
            ],
          }),
          jsonEncode({'_type': 'issue', 'id': 'tg-b', 'title': 'B'}),
          jsonEncode({'_type': 'memory', 'id': 'mem-1'}),
        ].join('\n');

        final runner = FakeBdRunner()
          ..stubCommand('export', BdReply(stdout: lines));
        final service = BdCliService(runner);

        final snapshot = await service.exportAll();

        expect(snapshot.beads.map((b) => b.id), ['tg-a', 'tg-b']);
        expect(snapshot.dependencies, hasLength(1));
        expect(snapshot.dependencies.single.issueId, 'tg-a');
        expect(snapshot.dependencies.single.dependsOnId, 'tg-b');
        expect(snapshot.dependencies.single.type, DependencyType.blocks);
      },
    );

    test(
      'exportAll() surfaces ephemeral wisp records (A15 pour shape: '
      'ephemeral root with idempotency_key, gate-typed step, parent edge)',
      () async {
        // `bd export --all` includes ephemeral wisps (the wisps tables) —
        // the M2 contract beads: a poured convergence wisp root and its
        // gate-typed (speculative) step, with the parent-child edge inline.
        final lines = [
          jsonEncode({
            '_type': 'issue',
            'id': 'tg-wisp-r1',
            'title': 'Convergence wisp iter 1',
            'issue_type': 'epic',
            'status': 'open',
            'ephemeral': true,
            'metadata': {'idempotency_key': 'converge:tg-root:iter:1'},
            'dependencies': [
              {
                'issue_id': 'tg-wisp-r1',
                'depends_on_id': 'tg-root',
                'type': 'parent-child',
              },
            ],
          }),
          jsonEncode({
            '_type': 'issue',
            'id': 'tg-wisp-s1',
            'title': 'iterate on tron',
            'issue_type': 'gate',
            'status': 'closed',
            'ephemeral': true,
            'metadata': {'gc.deferred_type': 'task'},
            'dependencies': [
              {
                'issue_id': 'tg-wisp-s1',
                'depends_on_id': 'tg-wisp-r1',
                'type': 'parent-child',
              },
            ],
          }),
          jsonEncode({'_type': 'issue', 'id': 'tg-root', 'title': 'root'}),
        ].join('\n');

        final runner = FakeBdRunner()
          ..stubCommand('export', BdReply(stdout: lines));
        final service = BdCliService(runner);

        final snapshot = await service.exportAll();

        final root = snapshot.beads.singleWhere((b) => b.id == 'tg-wisp-r1');
        expect(root.ephemeral, isTrue);
        expect(root.metadata['idempotency_key'], 'converge:tg-root:iter:1');
        final step = snapshot.beads.singleWhere((b) => b.id == 'tg-wisp-s1');
        expect(step.ephemeral, isTrue);
        expect(step.issueType, IssueType.gate);
        // A closed wisp remains visible (snapshot = all statuses).
        expect(step.status.wire, 'closed');
        expect(
          snapshot.dependencies.map((d) => '${d.issueId}->${d.dependsOnId}'),
          containsAll(['tg-wisp-r1->tg-root', 'tg-wisp-s1->tg-wisp-r1']),
        );
      },
    );

    test('query() forwards the expression and parses beads', () async {
      final runner = FakeBdRunner()
        ..stubCommand(
          'query',
          BdReply(stdout: fixtureText('hq-ready-sample.json')),
        );
      final service = BdCliService(runner);

      await service.query('status:open priority<=1');

      expect(runner.calls.single, [
        'query',
        'status:open priority<=1',
        '--json',
      ]);
    });

    test('statuses() returns the object envelope (dataMap)', () async {
      final runner = FakeBdRunner()
        ..stubCommand(
          'statuses',
          BdReply(stdout: fixtureText('tg-statuses.json')),
        );
      final service = BdCliService(runner);

      final statuses = await service.statuses();

      expect(statuses.containsKey('built_in_statuses'), isTrue);
    });

    test('types() returns the object envelope (dataMap)', () async {
      final runner = FakeBdRunner()
        ..stubCommand('types', BdReply(stdout: fixtureText('tg-types.json')));
      final service = BdCliService(runner);

      final types = await service.types();

      expect(types.containsKey('core_types'), isTrue);
      expect(types.containsKey('custom_types'), isTrue);
    });

    test('depList() chunks ids at 50 per spawn and de-dupes edges', () async {
      // 120 ids → ceil(120/50) = 3 spawns.
      final ids = [for (var i = 0; i < 120; i++) 'tg-$i'];
      final edge = jsonEncode({
        'schema_version': 1,
        'data': [
          {'issue_id': 'tg-0', 'depends_on_id': 'tg-1', 'type': 'blocks'},
        ],
      });
      final runner = FakeBdRunner()
        ..stubSub('dep', 'list', BdReply(stdout: edge));
      final service = BdCliService(runner);

      final edges = await service.depList(ids);

      expect(runner.calls, hasLength(3));
      // Each spawn is `dep list <ids…> --json`.
      for (final call in runner.calls) {
        expect(call.first, 'dep');
        expect(call[1], 'list');
        expect(call.last, '--json');
      }
      expect(runner.calls[0].where((a) => a.startsWith('tg-')), hasLength(50));
      expect(runner.calls[2].where((a) => a.startsWith('tg-')), hasLength(20));
      // Same edge returned by all chunks ⇒ de-duped by edgeKey to one.
      expect(edges, hasLength(1));
    });

    test('depList([]) short-circuits without a spawn', () async {
      final runner = FakeBdRunner();
      final service = BdCliService(runner);
      expect(await service.depList(const []), isEmpty);
      expect(runner.calls, isEmpty);
    });
  });

  group('BdCliService error path (ADR-0001 D4: error enveloped on stdout)', () {
    test(
      'non-zero exit with the stdout error fixture throws BdCommandFailed',
      () async {
        final runner = FakeBdRunner()
          ..stubSub(
            'dep',
            'list',
            BdReply(
              stdout: fixtureText('tg-error-stdout.json'),
              stderr: '',
              exitCode: 1,
            ),
          );
        final service = BdCliService(runner);

        await expectLater(
          service.depList(['tg-nonexistent']),
          throwsA(
            isA<BdCommandFailed>()
                .having((e) => e.message, 'message', contains('no issue found'))
                .having((e) => e.exitCode, 'exitCode', 1),
          ),
        );
      },
    );
  });

  group('BdCliService mutations carry --actor grid-controller', () {
    late FakeBdRunner runner;
    late BdCliService service;

    setUp(() {
      runner = FakeBdRunner()
        // Created-id envelope for create; empty success envelopes otherwise.
        ..stubCommand(
          'create',
          BdReply(
            stdout: jsonEncode({
              'schema_version': 1,
              'data': {'id': 'tg-new1'},
            }),
          ),
        )
        ..stubCommand('update', _okEnvelope())
        ..stubCommand('close', _okEnvelope())
        ..stubSub('dep', 'add', _okEnvelope())
        ..stubCommand('batch', _okEnvelope());
      service = BdCliService(runner);
    });

    void expectActor(List<String> argv) {
      // The flag and value are adjacent and present.
      final i = argv.indexOf('--actor');
      expect(i, greaterThanOrEqualTo(0), reason: 'no --actor in $argv');
      expect(argv[i + 1], 'grid-controller');
    }

    test(
      'create() stamps actor, type, priority, title and returns the id',
      () async {
        final id = await service.create(
          title: 'Wire the reconciler',
          type: IssueType.feature,
          priority: 1,
          description: 'body',
        );
        expect(id, 'tg-new1');
        final argv = runner.calls.single;
        expect(argv.first, 'create');
        expectActor(argv);
        expect(argv, containsAllInOrder(['--title', 'Wire the reconciler']));
        expect(argv, containsAllInOrder(['--type', 'feature']));
        expect(argv, containsAllInOrder(['--priority', '1']));
        expect(argv, containsAllInOrder(['--description', 'body']));
      },
    );

    test('update() stamps actor and only sends provided fields', () async {
      await service.update('tg-7', status: BeadStatus.inProgress, priority: 0);
      final argv = runner.calls.single;
      expect(argv.first, 'update');
      expect(argv[1], 'tg-7');
      expectActor(argv);
      expect(argv, containsAllInOrder(['--status', 'in_progress']));
      expect(argv, containsAllInOrder(['--priority', '0']));
      expect(argv, isNot(contains('--title')));
      expect(argv, isNot(contains('--description')));
    });

    test('close() stamps actor and forwards the reason', () async {
      await service.close('tg-7', reason: 'done');
      final argv = runner.calls.single;
      expect(argv.first, 'close');
      expect(argv[1], 'tg-7');
      expectActor(argv);
      expect(argv, containsAllInOrder(['--reason', 'done']));
    });

    test('depAdd() stamps actor and forwards the typed edge', () async {
      await service.depAdd('tg-7', 'tg-8', type: DependencyType.tracks);
      final argv = runner.calls.single;
      expect(argv.first, 'dep');
      expect(argv[1], 'add');
      expect(argv[2], 'tg-7');
      expect(argv[3], 'tg-8');
      expectActor(argv);
      expect(argv, containsAllInOrder(['--type', 'tracks']));
    });

    test('batch() stamps actor and pipes the script to stdin', () async {
      await service.batch([
        'close tg-1 done',
        'update tg-2 status=in_progress',
      ]);
      final argv = runner.calls.single;
      expect(argv.first, 'batch');
      expectActor(argv);
      // The line-oriented script reaches the child via stdin (not argv) — one
      // spawn, one Dolt transaction.
      expect(
        runner.stdins.single,
        'close tg-1 done\nupdate tg-2 status=in_progress',
      );
    });

    test('batch([]) is a no-op (no spawn)', () async {
      await service.batch(const []);
      expect(runner.calls, isEmpty);
    });
  });

  group('BdCliService is structurally SQL-free (PDR §6.6 / ADR-0001 D4)', () {
    test('no read or mutation ever emits a SQL string or connects to Dolt', () async {
      // Capture every argv the service would ever spawn and assert none of them
      // resembles SQL or a Dolt connection. BdCliService has no DoltEndpoint /
      // sql-client dependency by construction; this is the behavioural witness.
      final runner = FakeBdRunner()
        ..stubCommand(
          'ready',
          BdReply(stdout: fixtureText('hq-ready-sample.json')),
        )
        ..stubCommand(
          'export',
          BdReply(stdout: fixtureText('hq-export-sample.jsonl')),
        )
        ..stubCommand(
          'query',
          BdReply(stdout: fixtureText('hq-ready-sample.json')),
        )
        ..stubCommand(
          'statuses',
          BdReply(stdout: fixtureText('tg-statuses.json')),
        )
        ..stubCommand('types', BdReply(stdout: fixtureText('tg-types.json')))
        ..stubSub('dep', 'list', BdReply(stdout: _emptyListEnvelope()))
        ..stubCommand(
          'create',
          BdReply(
            stdout: jsonEncode({
              'schema_version': 1,
              'data': {'id': 'x'},
            }),
          ),
        )
        ..stubCommand('update', _okEnvelopeResult())
        ..stubCommand('close', _okEnvelopeResult())
        ..stubSub('dep', 'add', _okEnvelopeResult())
        ..stubCommand('batch', _okEnvelopeResult());
      final service = BdCliService(runner);

      await service.ready();
      await service.exportAll();
      await service.query('x');
      await service.statuses();
      await service.types();
      await service.depList(['tg-1']);
      await service.create(title: 't');
      await service.update('tg-1', priority: 1);
      await service.close('tg-1');
      await service.depAdd('tg-1', 'tg-2');
      await service.batch(['close tg-1 done']);

      final sqlVerb = RegExp(
        r'\b(select|insert|update\s+\w+\s+set|delete|create\s+table|drop|alter)\b',
        caseSensitive: false,
      );
      for (final argv in runner.calls) {
        // Every spawn is a `bd` subcommand, never raw SQL or a mysql:// dsn.
        for (final token in argv) {
          expect(token, isNot(contains('mysql://')));
          expect(token, isNot(contains(':34947')));
          expect(
            token,
            isNot(matches(RegExp(r'^\s*SELECT\s', caseSensitive: false))),
          );
        }
        // The whole argv must not read as a SQL statement.
        expect(
          argv.join(' '),
          isNot(matches(sqlVerb)),
          reason: 'argv looked like SQL: $argv',
        );
      }
      // bd ready / export / query / statuses / types / dep list, plus the five
      // mutations — all spawned, none SQL.
      expect(runner.calls, isNotEmpty);
    });
  });

  group('ProcessBdRunner contract (no real bd spawned)', () {
    test('environment forces BD_JSON_ENVELOPE=1 over the base env', () {
      final runner = ProcessBdRunner(
        workspaceRoot: Directory.systemTemp.path,
        environment: const {'PATH': '/usr/bin', 'BD_JSON_ENVELOPE': '0'},
      );
      // The contract: BD_JSON_ENVELOPE is always '1', inherited keys survive.
      expect(runner.environment['BD_JSON_ENVELOPE'], '1');
      expect(runner.environment['PATH'], '/usr/bin');
    });

    test('a missing executable surfaces as a spawn error (not a hang)', () {
      final runner = ProcessBdRunner(
        workspaceRoot: Directory.systemTemp.path,
        executable: 'bd-does-not-exist-xyz',
        environment: const {'PATH': '/nonexistent'},
      );
      expect(
        () => runner.run(const ['ready', '--json']),
        throwsA(isA<ProcessException>()),
      );
    });
  });

  group('concurrency cap (ADR-0001 D4: max 4 concurrent bd spawns)', () {
    test(
      'the runner semaphore never lets more than 4 actions run at once',
      () async {
        // Exercises ProcessBdRunner's REAL semaphore via `guarded` (no process is
        // spawned): we park each guarded action at a gate and count the live
        // high-water mark while firing 10 against a cap of 4.
        final runner = ProcessBdRunner(
          workspaceRoot: Directory.systemTemp.path,
          maxConcurrency: 4,
          environment: const {},
        );
        final gate = _Gate();

        final futures = [
          for (var i = 0; i < 10; i++) runner.guarded(gate.enter),
        ];

        await _pump();
        expect(gate.live, lessThanOrEqualTo(4));
        expect(gate.maxLive, 4);

        gate.releaseAll();
        await Future.wait(futures);
        expect(gate.maxLive, 4);
      },
    );

    test(
      'FakeBdRunner observes the cap when driven through guarded actions',
      () async {
        // The fake also records a concurrency high-water mark; confirm it never
        // exceeds the cap when each call is held open behind a gate.
        final runner = ProcessBdRunner(
          workspaceRoot: Directory.systemTemp.path,
          maxConcurrency: 4,
          environment: const {},
        );
        final fake = FakeBdRunner()
          ..stubCommand(
            'ready',
            BdReply(delay: const Duration(milliseconds: 20)),
          );

        final futures = [
          for (var i = 0; i < 12; i++)
            runner.guarded(() => fake.run(const ['ready', '--json'])),
        ];
        await Future.wait(futures);

        expect(fake.maxConcurrent, lessThanOrEqualTo(4));
        expect(fake.maxConcurrent, 4);
        expect(fake.calls, hasLength(12));
      },
    );
  });
}

BdReply _okEnvelope() => BdReply(stdout: _emptyObjectEnvelope());
BdReply _okEnvelopeResult() => BdReply(stdout: _emptyObjectEnvelope());

String _emptyObjectEnvelope() =>
    jsonEncode({'schema_version': 1, 'data': <String, dynamic>{}});

String _emptyListEnvelope() =>
    jsonEncode({'schema_version': 1, 'data': <dynamic>[]});

/// Spins the event loop a few turns so queued microtasks/timers run.
Future<void> _pump() async {
  for (var i = 0; i < 8; i++) {
    await Future<void>.delayed(Duration.zero);
  }
}

/// A re-entrant gate: each [enter] parks until [releaseAll], tracking the live
/// high-water mark — the witness for the concurrency cap.
class _Gate {
  final _parked = <Completer<void>>[];
  int live = 0;
  int maxLive = 0;
  bool _released = false;

  Future<void> enter() async {
    live++;
    if (live > maxLive) maxLive = live;
    // Once released, every later entrant (admitted as the semaphore frees
    // permits) passes straight through — otherwise it would park on a fresh
    // completer releaseAll already iterated past, hanging Future.wait.
    if (_released) {
      live--;
      return;
    }
    final completer = Completer<void>();
    _parked.add(completer);
    await completer.future;
    live--;
  }

  void releaseAll() {
    _released = true;
    for (final c in _parked) {
      if (!c.isCompleted) c.complete();
    }
  }
}
