import 'package:args/command_runner.dart';
import 'package:grid_cli/grid_cli.dart';
import 'package:test/test.dart';

final class _FakeClient extends StationCommandClient {
  _FakeClient(this.result);

  final StationCommandResult result;
  int calls = 0;
  String? gridRoot;
  String? method;
  Map<String, Object?>? params;

  @override
  Future<StationCommandResult> send({
    required String gridRoot,
    required String method,
    required Map<String, Object?> params,
  }) async {
    calls++;
    this.gridRoot = gridRoot;
    this.method = method;
    this.params = params;
    return result;
  }
}

const _rows = [
  {
    'workBeadId': 'tg-1',
    'sessionId': 'tgdog-s1',
    'worktree': '/root/.grid/worktrees/tg/tg-1',
    'branch': 'grid/tg-1',
    'heldReason': 'grid.escalation=human review',
    'status': 'would_collect',
  },
];

void main() {
  test(
    'session ls sends an empty resident payload and renders every field',
    () async {
      final output = <String>[];
      final client = _FakeClient(
        const StationCommandCompleted({'sessions': _rows}),
      );

      expect(
        await runSessionLs(gridRoot: '/grid', client: client, out: output.add),
        0,
      );

      expect(client.gridRoot, '/grid');
      expect(client.method, 'grid/session/ls');
      expect(client.params, isEmpty);
      expect(
        output.join('\n'),
        allOf(
          contains('1 held session'),
          contains('tgdog-s1'),
          contains('tg-1'),
          contains('/root/.grid/worktrees/tg/tg-1'),
          contains('grid/tg-1'),
          contains('grid.escalation=human review'),
        ),
      );
    },
  );

  test(
    'session collect defaults to dry-run and renders WOULD collect',
    () async {
      final output = <String>[];
      final client = _FakeClient(
        const StationCommandCompleted({'sessions': _rows}),
      );

      expect(
        await runSessionCollect(
          gridRoot: '/grid',
          sessionIds: const ['tgdog-s1'],
          client: client,
          out: output.add,
        ),
        0,
      );

      expect(client.method, 'grid/session/collect');
      expect(client.params, {
        'sessionIds': ['tgdog-s1'],
        'act': false,
        'bulk': false,
        'overrideUnsafe': false,
      });
      expect(output.join('\n'), contains('WOULD collect tgdog-s1'));
    },
  );

  test(
    'session collect forwards explicit act, bulk, and override flags',
    () async {
      final client = _FakeClient(
        const StationCommandCompleted({
          'sessions': [
            {
              'workBeadId': 'tg-1',
              'sessionId': 'tgdog-s1',
              'worktree': '/root/.grid/worktrees/tg/tg-1',
              'branch': 'grid/tg-1',
              'heldReason': 'grid.escalation=human review',
              'status': 'collected',
            },
          ],
        }),
      );
      final runner = CommandRunner<int>('grid', 'test')
        ..addCommand(SessionCommand(client: client));

      expect(
        await runner.run(const [
          'session',
          'collect',
          'tgdog-s1',
          'tgdog-s2',
          '--grid-root',
          '/grid',
          '--act',
          '--bulk',
          '--override-unsafe',
        ]),
        0,
      );

      expect(client.params, {
        'sessionIds': ['tgdog-s1', 'tgdog-s2'],
        'act': true,
        'bulk': true,
        'overrideUnsafe': true,
      });
    },
  );

  test(
    'session command guards arity, duplicates, bulk, and absolute root',
    () async {
      for (final arguments in <List<String>>[
        ['session', 'ls', 'extra', '--grid-root', '/grid'],
        ['session', 'ls', '--grid-root', 'relative'],
        ['session', 'collect', '--grid-root', '/grid'],
        [
          'session',
          'collect',
          'tgdog-s1',
          'tgdog-s1',
          '--grid-root',
          '/grid',
          '--bulk',
        ],
        ['session', 'collect', 'tgdog-s1', 'tgdog-s2', '--grid-root', '/grid'],
      ]) {
        final client = _FakeClient(const StationCommandCompleted({}));
        final runner = CommandRunner<int>('grid', 'test')
          ..addCommand(SessionCommand(client: client));
        expect(await runner.run(arguments), 64, reason: arguments.join(' '));
        expect(client.calls, 0, reason: arguments.join(' '));
      }
    },
  );

  test('session noun-domain prints its own usage and exits 64', () async {
    final client = _FakeClient(const StationCommandCompleted({}));
    final command = SessionCommand(client: client);
    CommandRunner<int>('grid', 'test').addCommand(command);

    expect(await command.run(), 64);

    expect(client.calls, 0);
  });

  for (final result in <StationCommandResult>[
    const StationCommandRefused('resident refused'),
    const StationCommandUnavailable('station unavailable'),
  ]) {
    test(
      'session collection renders ${result.runtimeType} to stderr',
      () async {
        final errors = <String>[];
        expect(
          await runSessionCollect(
            gridRoot: '/grid',
            sessionIds: const ['tgdog-s1'],
            client: _FakeClient(result),
            err: errors.add,
          ),
          64,
        );
        expect(errors.single, contains('grid session collect'));
      },
    );
  }

  const voidReceipt = StationCommandCompleted({
    'operation': 'grid/session/void',
    'sessionId': 'tgdog-s1',
    'workBeadId': 'tg-1',
    'retiredKey': 'tg-1#void-tgdog-s1',
    'closedSession': {
      'sessionId': 'tgdog-s1',
      'reason': 'voided',
      'disposition': 'voided',
    },
  });

  test('session void sends the session id and reason and renders the closed, '
      'voided, re-keyed receipt', () async {
    final output = <String>[];
    final client = _FakeClient(voidReceipt);

    expect(
      await runSessionVoid(
        gridRoot: '/grid',
        sessionId: 'tgdog-s1',
        reason: 'never stepped after re-adoption',
        client: client,
        out: output.add,
      ),
      0,
    );

    expect(client.gridRoot, '/grid');
    expect(client.method, 'grid/session/void');
    expect(client.params, {
      'sessionId': 'tgdog-s1',
      'reason': 'never stepped after re-adoption',
    });
    expect(
      output.join('\n'),
      allOf(
        contains('voided session tgdog-s1'),
        contains('disposition voided'),
        contains('re-keyed tg-1 to tg-1#void-tgdog-s1'),
        contains('mountable frontier'),
      ),
    );
  });

  test('session void renders a spec-clear failure loud on stderr while the '
      'void itself stands', () async {
    final output = <String>[];
    final errors = <String>[];
    final client = _FakeClient(
      StationCommandCompleted({
        ...voidReceipt.value,
        'specClearFailure': 'bd update timed out',
      }),
    );

    expect(
      await runSessionVoid(
        gridRoot: '/grid',
        sessionId: 'tgdog-s1',
        reason: 'never stepped',
        client: client,
        out: output.add,
        err: errors.add,
      ),
      0,
    );
    expect(output.join('\n'), contains('voided session tgdog-s1'));
    expect(
      errors.single,
      allOf(contains('spec clear FAILED'), contains('bd update timed out')),
    );
  });

  test('session void is a subcommand of the session noun-domain: it requires '
      '--reason and takes no defer date', () async {
    final client = _FakeClient(voidReceipt);
    final runner = CommandRunner<int>('grid', 'test')
      ..addCommand(SessionCommand(client: client));

    expect(
      await runner.run(const [
        'session',
        'void',
        'tgdog-s1',
        '--reason',
        'never stepped',
        '--grid-root',
        '/grid',
      ]),
      0,
    );
    expect(client.calls, 1);
    expect(client.params, {'sessionId': 'tgdog-s1', 'reason': 'never stepped'});

    // No defer date: `--until` is not an option of this verb.
    expect(
      () => runner.run(const [
        'session',
        'void',
        'tgdog-s1',
        '--reason',
        'never stepped',
        '--until',
        '2026-10-01',
        '--grid-root',
        '/grid',
      ]),
      throwsA(isA<UsageException>()),
    );
    expect(client.calls, 1);
  });

  test('session void guards arity, reason, and absolute root', () async {
    for (final arguments in <List<String>>[
      ['session', 'void', '--reason', 'x', '--grid-root', '/grid'],
      ['session', 'void', 'a', 'b', '--reason', 'x', '--grid-root', '/grid'],
      ['session', 'void', 'a', '--grid-root', '/grid'],
      ['session', 'void', 'a', '--reason', '   ', '--grid-root', '/grid'],
      ['session', 'void', 'a', '--reason', 'x', '--grid-root', 'relative'],
      ['session', 'void', 'a', '--reason', 'x'],
    ]) {
      final client = _FakeClient(voidReceipt);
      final runner = CommandRunner<int>('grid', 'test')
        ..addCommand(SessionCommand(client: client));
      expect(await runner.run(arguments), 64, reason: arguments.join(' '));
      expect(client.calls, 0, reason: arguments.join(' '));
    }
  });

  test('session void surfaces the resident\'s gated refusal, which points the '
      'operator at rework', () async {
    final errors = <String>[];
    expect(
      await runSessionVoid(
        gridRoot: '/grid',
        sessionId: 'tgdog-s1',
        reason: 'never stepped',
        client: _FakeClient(
          const StationCommandRefused(
            'Session "tgdog-s1" is parked at gate tgdog-gate '
            '(tg-1/review/route); `grid session void` voids only an ungated '
            'session — use `grid rework tg-1` to retire a gated round.',
          ),
        ),
        err: errors.add,
      ),
      64,
    );
    expect(
      errors.single,
      allOf(
        startsWith('grid session void: '),
        contains('tgdog-gate'),
        contains('grid rework tg-1'),
      ),
    );
  });

  for (final fixture in <({String name, Map<String, Object?> value})>[
    (name: 'missing closed session', value: const {'workBeadId': 'tg-1'}),
    (
      name: 'unvoided disposition',
      value: const {
        'workBeadId': 'tg-1',
        'retiredKey': 'tg-1#void-tgdog-s1',
        'closedSession': {
          'sessionId': 'tgdog-s1',
          'reason': 'voided',
          'disposition': 'done',
        },
      },
    ),
    (
      name: 'missing re-key',
      value: const {
        'workBeadId': 'tg-1',
        'closedSession': {
          'sessionId': 'tgdog-s1',
          'reason': 'voided',
          'disposition': 'voided',
        },
      },
    ),
  ]) {
    test('session void rejects a ${fixture.name} receipt without partial '
        'stdout', () async {
      final output = <String>[];
      final errors = <String>[];
      expect(
        await runSessionVoid(
          gridRoot: '/grid',
          sessionId: 'tgdog-s1',
          reason: 'never stepped',
          client: _FakeClient(StationCommandCompleted(fixture.value)),
          out: output.add,
          err: errors.add,
        ),
        64,
      );
      expect(output, isEmpty);
      expect(errors.single, contains('complete void receipt'));
    });
  }

  test('session noun-domain help documents the void verb', () {
    final client = _FakeClient(voidReceipt);
    final command = SessionCommand(client: client);
    CommandRunner<int>('grid', 'test').addCommand(command);

    expect(command.usage, contains('void'));
    expect(command.usage, contains('Void an open, ungated session'));
    expect(command.usage, contains('use rework'));
    final voidUsage = command.subcommands['void']!.usage;
    expect(voidUsage, contains('--reason'));
    expect(voidUsage, contains('Required'));
    expect(voidUsage, isNot(contains('--until')));
  });
}
