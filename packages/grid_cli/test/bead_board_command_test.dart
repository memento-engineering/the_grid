import 'dart:convert';

import 'package:args/command_runner.dart';
import 'package:grid_cli/grid_cli.dart';
import 'package:grid_sdk/grid_sdk.dart';
import 'package:test/test.dart';

void main() {
  test('verb sends all board filters through the resident door', () async {
    final client = _FakeClient(
      const StationCommandCompleted({'rows': <Object?>[]}),
    );
    final runner = CommandRunner<int>('grid', 'test')
      ..addCommand(BeadCommand(client: client));

    expect(
      await runner.run(const [
        'bead',
        'board',
        '--grid-root',
        '/grid',
        '--store',
        'alpha',
        '--status',
        'open',
        '--blocked',
        '--unapproved',
      ]),
      0,
    );
    expect(client.method, 'grid/bead/board');
    expect(client.gridRoot, '/grid');
    expect(client.params, {
      'stores': ['alpha'],
      'statuses': ['open'],
      'blocked': true,
      'approved': false,
    });
  });

  test('invalid root and exclusive approval flags never dispatch', () async {
    for (final args in const [
      ['bead', 'board'],
      ['bead', 'board', '--grid-root', 'relative'],
      ['bead', 'board', '--grid-root', '/grid', '--approved', '--unapproved'],
    ]) {
      final client = _FakeClient(const StationCommandCompleted({}));
      final runner = CommandRunner<int>('grid', 'test')
        ..addCommand(BeadCommand(client: client));
      expect(await runner.run(args), 64);
      expect(client.calls, 0);
    }
  });

  test('--json emits a decodable array carrying both union arms', () async {
    const rows = <BoardRow>[
      BoardRow.bead(
        id: 'tg-1',
        store: 'alpha',
        root: '/alpha',
        type: 'task',
        status: 'open',
        title: 'work',
      ),
      BoardRow.storeUnreadable(store: 'beta', root: '/beta', reason: 'offline'),
    ];
    final output = <String>[];
    final code = await runBeadBoard(
      gridRoot: '/grid',
      client: _FakeClient(
        StationCommandCompleted({
          'rows': [for (final row in rows) row.toJson()],
        }),
      ),
      json: true,
      out: output.add,
    );

    expect(code, 0);
    expect(
      (jsonDecode(output.single) as List).map((row) => (row as Map)['kind']),
      ['bead', 'store_unreadable'],
    );
  });

  test('table renders unreadable stores first and aligns columns', () {
    final output = <String>[];
    renderBoard(const [
      BoardRow.bead(
        id: 'tg-1',
        store: 'a',
        root: '/a',
        type: 'task',
        status: 'open',
        title: 'short',
      ),
      BoardRow.storeUnreadable(
        store: 'broken',
        root: '/broken',
        reason: 'offline',
      ),
      BoardRow.bead(
        id: 'tg-long',
        store: 'alpha',
        root: '/a',
        type: 'feature',
        status: 'in_progress',
        title: 'longer',
      ),
    ], output.add);

    expect(output.first, startsWith('!! broken'));
    expect(output[1], startsWith('ID'));
    expect(output[2].indexOf('a'), output[3].indexOf('alpha'));
  });

  test('resident refusal and unavailability return 64 on stderr', () async {
    for (final result in const <StationCommandResult>[
      StationCommandRefused('refused'),
      StationCommandUnavailable('offline'),
    ]) {
      final errors = <String>[];
      expect(
        await runBeadBoard(
          gridRoot: '/grid',
          client: _FakeClient(result),
          err: errors.add,
        ),
        64,
      );
      expect(
        errors.single,
        contains(result is StationCommandRefused ? 'refused' : 'offline'),
      );
    }
  });
}

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
