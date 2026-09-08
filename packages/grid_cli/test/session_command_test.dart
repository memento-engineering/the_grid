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
}
