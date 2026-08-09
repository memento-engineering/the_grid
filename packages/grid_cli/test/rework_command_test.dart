import 'package:args/command_runner.dart';
import 'package:grid_cli/src/rework_command.dart';
import 'package:grid_cli/src/station_command_client.dart';
import 'package:test/test.dart';

/// Offline proofs for the resident-door `grid rework` client.
///
/// Ported from the pre-door suite: request serialization, completed/refused/
/// unavailable outcomes, bead arity, absolute-root guards, and beyond-cap
/// actor/note syntax guards. Removed with the retired second-process path:
/// direct store export/write, prefix and note-root options, session cursor and
/// round projection; resident semantics live in station_command_handler_test.dart.
void main() {
  CommandRunner<int> runner(FakeClient client) =>
      CommandRunner<int>('grid', 'test')
        ..addCommand(ReworkCommand(client: client));

  test('sends all authorization fields through resident door', () async {
    final client = FakeClient(const StationCommandCompleted({}));
    expect(
      await runner(client).run([
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
    expect(client.method, 'grid/rework');
    expect(client.params, {
      'beadId': 'work-1',
      'note': 'approved',
      'beyondCap': true,
      'actor': 'Nico',
    });
  });

  for (final result in <StationCommandResult>[
    const StationCommandRefused('no session'),
    const StationCommandUnavailable('station.lock is absent'),
  ]) {
    test('resident refusal is exit 64 for ${result.runtimeType}', () async {
      final client = FakeClient(result);
      expect(
        await runner(client).run(['rework', 'work-1', '--grid-root', '/grid']),
        64,
      );
      expect(client.calls, 1);
    });
  }

  test('arity and root guards send nothing', () async {
    for (final args in <List<String>>[
      ['rework', '--grid-root', '/grid'],
      ['rework', 'work-1', 'work-2', '--grid-root', '/grid'],
      ['rework', 'work-1'],
      ['rework', 'work-1', '--grid-root', 'relative'],
    ]) {
      final client = FakeClient(const StationCommandCompleted({}));
      expect(await runner(client).run(args), 64);
      expect(client.calls, 0);
    }
  });

  test('beyond-cap actor and note guards send nothing', () async {
    for (final args in <List<String>>[
      ['rework', 'work-1', '--grid-root', '/grid', '--beyond-cap'],
      [
        'rework',
        'work-1',
        '--grid-root',
        '/grid',
        '--beyond-cap',
        '--actor',
        'Nico',
      ],
    ]) {
      final client = FakeClient(const StationCommandCompleted({}));
      expect(await runner(client).run(args), 64);
      expect(client.calls, 0);
    }
  });
}

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
