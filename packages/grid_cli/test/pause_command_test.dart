import 'package:args/command_runner.dart';
import 'package:grid_cli/src/pause_command.dart';
import 'package:grid_cli/src/station_command_client.dart';
import 'package:test/test.dart';

final class FakeClient extends StationCommandClient {
  FakeClient(this.result);

  final StationCommandResult result;
  int calls = 0;
  String? method;
  Map<String, Object?>? params;

  @override
  Future<StationCommandResult> send({
    required String gridRoot,
    required String method,
    required Map<String, Object?> params,
  }) async {
    calls++;
    this.method = method;
    this.params = params;
    return result;
  }
}

void main() {
  CommandRunner<int> runner(FakeClient client) =>
      CommandRunner<int>('grid', 'test')
        ..addCommand(PauseCommand(client: client))
        ..addCommand(ResumeCommand(client: client));

  test('pause and resume dispatch through the resident door', () async {
    for (final entry in const [
      ('pause', 'grid/session/pause'),
      ('resume', 'grid/session/resume'),
    ]) {
      final client = FakeClient(
        const StationCommandCompleted({
          'sessionId': 'tgdog-s1',
          'pauseState': 'paused',
          'changed': true,
        }),
      );
      expect(
        await runner(client).run([entry.$1, 'tg-1', '--grid-root', '/grid']),
        0,
      );
      expect(client.method, entry.$2);
      expect(client.params, {'beadId': 'tg-1'});
    }
  });

  test('arity and root guards refuse before dispatch', () async {
    for (final argv in const [
      ['pause', '--grid-root', '/grid'],
      ['pause', 'tg-1', 'tg-2', '--grid-root', '/grid'],
      ['pause', 'tg-1'],
      ['resume', 'tg-1', '--grid-root', 'relative/path'],
    ]) {
      final client = FakeClient(const StationCommandCompleted({}));
      expect(await runner(client).run(argv), 64);
      expect(client.calls, 0);
    }
  });

  test('a resident refusal returns exit 64', () async {
    final client = FakeClient(
      const StationCommandRefused('Session "tgdog-s1" was never paused'),
    );
    expect(
      await runner(client).run(['resume', 'tg-1', '--grid-root', '/grid']),
      64,
    );
  });
}
