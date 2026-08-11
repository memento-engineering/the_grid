import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:beads_dart/beads_dart.dart';
import 'package:test/test.dart';

import '../support/fake_bd_runner.dart';
import '../support/fixtures.dart';

void main() {
  group('BdCliService reads (FakeBdRunner + pinned fixtures)', () {
    test('ready() returns more than the default page', () async {
      final runner = FakeBdRunner()
        ..stubCommand('ready', BdReply(stdout: beadListEnvelope(120)));
      final service = BdCliService(runner);

      final beads = await service.ready();

      expect(beads, hasLength(120));
      expect(beads.map((bead) => bead.id), containsAll(['tg-0', 'tg-119']));
      expect(runner.calls.single, ['ready', '--json', '--limit', '0']);
    });

    test('ready() restores priority order after the unlimited fetch', () async {
      final runner = FakeBdRunner()
        ..stubCommand(
          'ready',
          BdReply(
            stdout: jsonEncode({
              'schema_version': 1,
              'data': [
                {
                  'id': 'tg-null',
                  'issue_type': 'task',
                  'status': 'open',
                  'priority': 2,
                },
                {
                  'id': 'tg-b',
                  'issue_type': 'task',
                  'status': 'open',
                  'priority': 1,
                  'created_at': '2026-08-07T10:00:00Z',
                },
                {
                  'id': 'tg-a',
                  'issue_type': 'task',
                  'status': 'open',
                  'priority': 1,
                  'created_at': '2026-08-07T10:00:00Z',
                },
                {
                  'id': 'tg-new',
                  'issue_type': 'task',
                  'status': 'open',
                  'priority': 1,
                  'created_at': '2026-08-07T11:00:00Z',
                },
              ],
            }),
          ),
        );
      final beads = await BdCliService(runner).ready();

      expect(beads.map((bead) => bead.id), [
        'tg-new',
        'tg-a',
        'tg-b',
        'tg-null',
      ]);
      expect(runner.calls.single, ['ready', '--json', '--limit', '0']);
    });

    test('listScope returns more than the default page', () async {
      final runner = FakeBdRunner()
        ..stubCommand(
          'list',
          BdReply(stdout: beadListEnvelope(120, type: 'gate')),
        );
      final service = BdCliService(runner);

      final scope = await service.listScope(
        type: const IssueType('gate'),
        status: BeadStatus.open,
      );

      expect(scope.beads, hasLength(120));
      expect(
        scope.beads.map((bead) => bead.id),
        containsAll(['tg-0', 'tg-119']),
      );
      expect(runner.calls.single, [
        'list',
        '-t',
        'gate',
        '--status',
        'open',
        '--json',
        '--limit',
        '0',
      ]);
    });

    test(
      'listScope uses explicit type and status and parses inline edges',
      () async {
        final runner = FakeBdRunner()
          ..stubCommand(
            'list',
            BdReply(
              stdout: jsonEncode({
                'schema_version': 1,
                'data': [
                  {
                    'id': 'tg-gate',
                    'issue_type': 'gate',
                    'status': 'open',
                    'dependencies': [
                      {
                        'issue_id': 'tg-gate',
                        'depends_on_id': 'tg-s',
                        'type': 'blocks',
                      },
                    ],
                  },
                ],
              }),
            ),
          );
        final service = BdCliService(runner);
        final scope = await service.listScope(
          type: const IssueType('gate'),
          status: BeadStatus.open,
        );
        expect(scope.beads.single.id, 'tg-gate');
        expect(scope.dependencies.single.dependsOnId, 'tg-s');
        expect(runner.calls.single, [
          'list',
          '-t',
          'gate',
          '--status',
          'open',
          '--json',
          '--limit',
          '0',
        ]);
      },
    );

    test('listScopeArgs supports all-status and narrowed type scopes', () {
      final service = BdCliService(FakeBdRunner());

      expect(service.listScopeArgs(type: const IssueType('gate')), [
        'list',
        '-t',
        'gate',
        '--json',
        '--limit',
        '0',
      ]);
      expect(
        service.listScopeArgs(type: IssueType.task, status: BeadStatus.closed),
        ['list', '-t', 'task', '--status', 'closed', '--json', '--limit', '0'],
      );
    });

    test('query() returns more than the default page', () async {
      final runner = FakeBdRunner()
        ..stubCommand('query', BdReply(stdout: beadListEnvelope(120)));
      final service = BdCliService(runner);

      final beads = await service.query('status:open priority<=1');

      expect(beads, hasLength(120));
      expect(beads.map((bead) => bead.id), containsAll(['tg-0', 'tg-119']));
      expect(runner.calls.single, [
        'query',
        'status:open priority<=1',
        '--json',
        '--limit',
        '0',
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

    test('non-zero results route through the typed decoder', () async {
      const guardMismatchEnvelope =
          '{"schema_version":1,"data":{"error":"guard mismatch",'
          '"guard_mismatch":true}}';
      final runner = FakeBdRunner()
        ..stubSub(
          'dep',
          'list',
          const BdReply(
            stdout: guardMismatchEnvelope,
            stderr: '',
            exitCode: 13,
          ),
        );

      await expectLater(
        BdCliService(runner).depList(['tg-guarded']),
        throwsA(isA<BdGuardMismatch>()),
      );
    });
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
      expect(argv, isNot(contains('--if-assignee')));
      expect(argv, isNot(contains('--if-status')));
    });

    test('conditional update guards preserve empty assignee', () async {
      await service.update(
        'tg-7',
        ifAssignee: '',
        ifStatus: BeadStatus.open,
        status: BeadStatus.inProgress,
      );
      final argv = runner.calls.single;
      expect(argv, containsAllInOrder(['--if-assignee', '']));
      expect(argv, containsAllInOrder(['--if-status', 'open']));
      expect(argv.indexOf('--if-status'), lessThan(argv.indexOf('--status')));
    });

    test(
      'update() can clear design and acceptance without touching body text',
      () async {
        runner.stubCommand(
          'show',
          BdReply(stdout: _beadEnvelope(acceptanceCriteria: '')),
        );
        await service.update('tg-7', design: '', acceptanceCriteria: '');
        final argv = runner.calls.first;
        expect(argv.first, 'update');
        expect(argv[1], 'tg-7');
        expectActor(argv);
        expect(argv, containsAllInOrder(['--design-file', '-']));
        expect(runner.stdins.first, '');
        expect(argv, containsAllInOrder(['--acceptance', '']));
        expect(argv, isNot(contains('--design')));
        expect(argv, isNot(contains('--description')));
        expect(argv, isNot(contains('--notes')));
        expect(argv, isNot(contains('--append-notes')));
      },
    );

    test(
      'update() carries spec fields, metadata, and metadata unset atomically',
      () async {
        runner.stubCommand(
          'show',
          BdReply(
            stdout: _beadEnvelope(
              acceptanceCriteria: '',
              metadata: const {'other': 'value'},
            ),
          ),
        );
        await service.update(
          'tg-7',
          design: '',
          acceptanceCriteria: '',
          mergeMetadata: const {'other': 'value'},
          unsetMetadata: const ['spec.author'],
        );

        final argv = runner.calls.first;
        expect(argv.first, 'update');
        expectActor(argv);
        expect(argv, containsAllInOrder(['--design-file', '-']));
        expect(argv, containsAllInOrder(['--acceptance', '']));
        expect(argv, containsAllInOrder(['--set-metadata', 'other=value']));
        expect(argv, isNot(contains('--metadata')));
        expect(argv, containsAllInOrder(['--unset-metadata', 'spec.author']));
      },
    );

    test('text transport keeps body and design outside argv', () async {
      const body = 'body\r\n\ufeff\u200b\u00a0\t\n  ';
      const design = 'design\u0000tail';
      String? fileText;
      final inspectingRunner = _InspectingRunner((args, stdin) async {
        final designIndex = args.indexOf('--design-file');
        if (designIndex >= 0 && args[designIndex + 1] != '-') {
          fileText = await File(args[designIndex + 1]).readAsString();
        }
        return BdResult(
          exitCode: 0,
          stdout: _emptyObjectEnvelope(),
          stderr: '',
        );
      });

      await BdCliService(
        inspectingRunner,
      ).update('tg-7', description: body, design: design);

      final argv = inspectingRunner.calls.single;
      expect(argv, containsAllInOrder(['--body-file', '-']));
      expect(argv, contains('--design-file'));
      expect(argv, isNot(contains('--description')));
      expect(argv, isNot(contains('--design')));
      expect(argv, isNot(contains(body)));
      expect(argv, isNot(contains(design)));
      expect(inspectingRunner.stdins.single, body);
      expect(fileText, design);
    });

    test('text transport sends each single field through stdin', () async {
      const design = 'a\u0000b';
      await service.update('tg-7', description: '');
      await service.update('tg-7', design: design);

      expect(runner.calls[0], containsAllInOrder(['--body-file', '-']));
      expect(runner.stdins[0], '');
      expect(runner.calls[1], containsAllInOrder(['--design-file', '-']));
      expect(runner.stdins[1], design);
    });

    test('argv text guard refuses unsafe C0 before any process call', () async {
      for (final update in <Future<void> Function()>[
        () => service.update('tg-7', acceptanceCriteria: 'safe\u0000tail'),
        () => service.update('tg-7', appendNotes: 'safe\u0001tail'),
        () => service.update(
          'tg-7',
          mergeMetadata: const {'key': 'safe\u001ftail'},
        ),
      ]) {
        await expectLater(
          update(),
          throwsA(
            isA<BeadTextRefused>()
                .having((error) => error.offset, 'offset', 4)
                .having((error) => error.context, 'context', contains('tail')),
          ),
        );
      }
      expect(runner.calls, isEmpty);
    });

    test('argv text guard permits tabs and newlines', () async {
      const text = 'tab\tline\nend';
      runner.stubCommand(
        'show',
        BdReply(
          stdout: _beadEnvelope(
            acceptanceCriteria: text,
            metadata: const {'key': text},
          ),
        ),
      );
      await service.update(
        'tg-7',
        acceptanceCriteria: text,
        mergeMetadata: const {'key': text},
      );
      expect(runner.calls.first, contains(text));
    });

    test('argv text round trip reports first divergent offset', () async {
      runner.stubCommand(
        'show',
        BdReply(stdout: _beadEnvelope(acceptanceCriteria: 'abcX')),
      );
      await expectLater(
        service.update('tg-7', acceptanceCriteria: 'abcde'),
        throwsA(
          isA<BeadTextRoundTripFailure>()
              .having((error) => error.field, 'field', 'acceptanceCriteria')
              .having((error) => error.offset, 'offset', 3)
              .having((error) => error.sentLength, 'sent length', 5)
              .having((error) => error.storedLength, 'stored length', 4),
        ),
      );
    });

    test('argv text round trip shares one post-read across fields', () async {
      const text = 'tab\tline\nend';
      final verifyingRunner = FakeBdRunner(
        queuedReplies: [
          BdReply(stdout: _beadEnvelope(notes: 'before')),
          _okEnvelope(),
          BdReply(
            stdout: _beadEnvelope(
              acceptanceCriteria: text,
              notes: 'before\n$text',
              metadata: const {'key': text},
            ),
          ),
        ],
      );

      await BdCliService(verifyingRunner).update(
        'tg-7',
        acceptanceCriteria: text,
        appendNotes: text,
        mergeMetadata: const {'key': text},
      );

      expect(verifyingRunner.calls.map((args) => args.first), [
        'show',
        'update',
        'show',
      ]);
      expect(
        verifyingRunner.calls[1],
        containsAllInOrder(['--append-notes', text]),
      );
    });

    test('stdin-only text update performs no verification read', () async {
      await service.update('tg-7', design: 'design');
      expect(runner.calls, hasLength(1));
      expect(runner.calls.single.first, 'update');
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
          BdReply(stdout: fixtureText('fx-ready-sample.json')),
        )
        ..stubCommand('list', BdReply(stdout: _emptyListEnvelope()))
        ..stubCommand(
          'export',
          BdReply(stdout: fixtureText('fx-export-sample.jsonl')),
        )
        ..stubCommand(
          'query',
          BdReply(stdout: fixtureText('fx-ready-sample.json')),
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
      await service.listScope(type: IssueType.task, status: BeadStatus.open);
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
    test('environment forces service-mode variables over the base env', () {
      final runner = ProcessBdRunner(
        workspaceRoot: Directory.systemTemp.path,
        environment: const {
          'PATH': '/usr/bin',
          'BD_JSON_ENVELOPE': '0',
          'BD_NON_INTERACTIVE': '0',
        },
      );
      expect(runner.environment['BD_JSON_ENVELOPE'], '1');
      expect(runner.environment['BD_NON_INTERACTIVE'], '1');
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

String beadListEnvelope(int count, {String type = 'task'}) => jsonEncode({
  'schema_version': 1,
  'data': [
    for (var i = 0; i < count; i++)
      {'id': 'tg-$i', 'issue_type': type, 'status': 'open'},
  ],
});

BdReply _okEnvelope() => BdReply(stdout: _emptyObjectEnvelope());
BdReply _okEnvelopeResult() => BdReply(stdout: _emptyObjectEnvelope());

String _emptyObjectEnvelope() =>
    jsonEncode({'schema_version': 1, 'data': <String, dynamic>{}});

String _emptyListEnvelope() =>
    jsonEncode({'schema_version': 1, 'data': <dynamic>[]});

String _beadEnvelope({
  String acceptanceCriteria = '',
  String notes = '',
  Map<String, dynamic> metadata = const {},
}) => jsonEncode({
  'schema_version': 1,
  'data': [
    {
      'id': 'tg-7',
      'acceptance_criteria': acceptanceCriteria,
      'notes': notes,
      'metadata': metadata,
    },
  ],
});

class _InspectingRunner implements BdRunner {
  _InspectingRunner(this.reply);

  final Future<BdResult> Function(List<String>, String?) reply;
  final calls = <List<String>>[];
  final stdins = <String?>[];

  @override
  Future<BdResult> run(
    List<String> args, {
    Duration? timeout,
    String? stdin,
  }) async {
    calls.add(args);
    stdins.add(stdin);
    return reply(args, stdin);
  }
}

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
