import 'dart:convert';

import 'package:args/command_runner.dart';
import 'package:grid_cli/grid_cli.dart';
import 'package:test/test.dart';

void main() {
  const fixture =
      "literal `cmd` and \$(cmd) and \$VAR and 'single'\n  trailing  ";

  test('bead set reads stdin exactly and has no inline text flag', () async {
    final client = _FakeClient(const StationCommandCompleted({}));
    final runner = CommandRunner<int>('grid', 'test')
      ..addCommand(
        BeadCommand(client: client, input: Stream.value(utf8.encode(fixture))),
      );
    expect(
      await runner.run(const [
        'bead',
        'set',
        '--bead',
        'tg-a',
        '--field',
        'notes',
        '--file',
        '-',
        '--grid-root',
        '/grid',
      ]),
      0,
    );
    expect(client.params!['content'], fixture);
    expect(
      () => runner.run(const [
        'bead',
        'set',
        '--bead',
        'tg-a',
        '--field',
        'notes',
        '--text',
        'bad',
        '--file',
        '-',
        '--grid-root',
        '/grid',
      ]),
      throwsA(isA<UsageException>()),
    );
  });

  test('append is restricted before reading or dispatch', () async {
    final client = _FakeClient(const StationCommandCompleted({}));
    final runner = CommandRunner<int>('grid', 'test')
      ..addCommand(BeadCommand(client: client));
    expect(
      await runner.run(const [
        'bead',
        'set',
        '--bead',
        'tg-a',
        '--field',
        'design',
        '--append',
        '--file',
        '/missing',
        '--grid-root',
        '/grid',
      ]),
      64,
    );
    expect(client.calls, 0);
  });
}

final class _FakeClient extends StationCommandClient {
  _FakeClient(this.result);
  final StationCommandResult result;
  int calls = 0;
  Map<String, Object?>? params;

  @override
  Future<StationCommandResult> send({
    required String gridRoot,
    required String method,
    required Map<String, Object?> params,
  }) async {
    calls++;
    this.params = params;
    return result;
  }
}
