import 'package:args/command_runner.dart';
import 'package:grid_cli/src/rework_command.dart';
import 'package:grid_cli/src/station_command_client.dart';
import 'package:test/test.dart';

void main() {
  test('sends all authorization fields through resident door', () async {
    final client = FakeClient(const StationCommandCompleted({}));
    final runner = CommandRunner<int>('grid', 'test')
      ..addCommand(ReworkCommand(client: client));
    expect(
      await runner.run([
        'rework',
        'work-1',
        '--grid-root',
        '/grid',
        '--beyond-cap',
        '--actor',
        'Nico',
        '--note',
        'approved',
      ]),
      0,
    );
    expect(client.params, {
      'beadId': 'work-1',
      'note': 'approved',
      'beyondCap': true,
      'actor': 'Nico',
    });
  });

  test('beyond cap syntax guard sends nothing', () async {
    final client = FakeClient(const StationCommandCompleted({}));
    final runner = CommandRunner<int>('grid', 'test')
      ..addCommand(ReworkCommand(client: client));
    expect(
      await runner.run([
        'rework',
        'work-1',
        '--grid-root',
        '/grid',
        '--beyond-cap',
      ]),
      64,
    );
    expect(client.calls, 0);
  });
}

final class FakeClient extends StationCommandClient {
  FakeClient(this.result);

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
