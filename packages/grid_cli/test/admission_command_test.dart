import 'dart:io';

import 'package:args/command_runner.dart';
import 'package:grid_cli/grid_cli.dart';
import 'package:test/test.dart';

final class _FakeClient extends StationCommandClient {
  _FakeClient(this.result);

  final StationCommandResult result;
  final calls =
      <({String gridRoot, String method, Map<String, Object?> params})>[];

  @override
  Future<StationCommandResult> send({
    required String gridRoot,
    required String method,
    required Map<String, Object?> params,
  }) async {
    calls.add((gridRoot: gridRoot, method: method, params: params));
    return result;
  }
}

CommandRunner<int> _runner(
  _FakeClient client, {
  void Function(String)? out,
  void Function(String)? err,
}) =>
    CommandRunner<int>('grid', 'test')
      ..addCommand(AdmissionCommand(client: client, out: out, err: err));

Future<int> _run(CommandRunner<int> runner, List<String> arguments) async {
  try {
    return await runner.run(arguments) ?? 0;
  } on UsageException {
    return 64;
  }
}

void main() {
  test(
    'the noun registers only set and bare admission returns usage',
    () async {
      final client = _FakeClient(const StationCommandCompleted({}));
      final command = AdmissionCommand(client: client);
      expect(command.subcommands.keys, ['set']);
      CommandRunner<int>('grid', 'test').addCommand(command);
      expect(await command.run(), 64);
      expect(await _run(_runner(client), ['admission']), 64);
      expect(client.calls, isEmpty);
    },
  );

  test('valid grammar sends once and renders the resolved pair', () async {
    final output = <String>[];
    final errors = <String>[];
    final client = _FakeClient(
      const StationCommandCompleted({
        'maxAgents': 6,
        'maxAgentsSource': 'control',
      }),
    );

    expect(
      await _run(_runner(client, out: output.add, err: errors.add), [
        'admission',
        'set',
        '6',
        '--grid-root',
        '/absolute/grid/home',
      ]),
      0,
    );
    expect(client.calls, hasLength(1));
    expect(client.calls.single.gridRoot, '/absolute/grid/home');
    expect(client.calls.single.method, 'grid/admission/set');
    expect(client.calls.single.params, {'maxAgents': 6});
    expect(output, ['grid admission set — max agents: 6 (source: control).']);
    expect(errors, isEmpty);
  });

  test(
    'every pre-dispatch guard is loud and makes zero client calls',
    () async {
      final cases = <List<String>>[
        ['admission', 'set', '--grid-root', '/grid'],
        ['admission', 'set', '1', '2', '--grid-root', '/grid'],
        ['admission', 'set', '1.5', '--grid-root', '/grid'],
        [
          'admission',
          'set',
          '999999999999999999999999999999999999999',
          '--grid-root',
          '/grid',
        ],
        ['admission', 'set', '0', '--grid-root', '/grid'],
        ['admission', 'set', '--grid-root', '/grid', '--', '-1'],
        ['admission', 'set', '1'],
        ['admission', 'set', '1', '--grid-root', 'relative/grid'],
      ];
      for (final arguments in cases) {
        final errors = <String>[];
        final client = _FakeClient(const StationCommandCompleted({}));
        expect(
          await _run(_runner(client, err: errors.add), arguments),
          64,
          reason: '$arguments',
        );
        expect(client.calls, isEmpty, reason: '$arguments');
        expect(errors, hasLength(1), reason: '$arguments');
        expect(errors.single, startsWith('grid admission set:'));
      }
    },
  );

  test('resident refusal and unavailability map to loud usage exits', () async {
    for (final result in const <StationCommandResult>[
      StationCommandRefused('resident refused the ceiling'),
      StationCommandUnavailable('resident is down'),
    ]) {
      final errors = <String>[];
      final client = _FakeClient(result);
      expect(
        await _run(_runner(client, err: errors.add), [
          'admission',
          'set',
          '6',
          '--grid-root',
          '/grid',
        ]),
        64,
      );
      expect(client.calls, hasLength(1));
      expect(errors.single, startsWith('grid admission set:'));
    }
  });

  test('the public barrel and reference runner expose the command', () {
    final source = File('bin/grid.dart').readAsStringSync();
    expect(source, contains('AdmissionCommand()'));
    expect(
      File('lib/src/admission_command.dart').readAsStringSync(),
      isNot(contains('print(')),
    );
  });
}
