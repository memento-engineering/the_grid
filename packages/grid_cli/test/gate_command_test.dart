import 'package:grid_cli/src/gate_command.dart';
import 'package:grid_cli/src/station_command_client.dart';
import 'package:test/test.dart';

void main() {
  test('list renders all resident rows sorted', () async {
    final output = <String>[];
    final client = FakeClient(
      StationCommandCompleted({
        'gates': [
          {'id': 'g-2', 'createdAt': '2026-01-01T00:00:00Z'},
          {'id': 'g-1', 'createdAt': '2026-01-01T00:00:00Z'},
        ],
      }),
    );
    expect(
      await runGateLs(
        gridRoot: '/grid',
        client: client,
        out: output.add,
        now: DateTime.utc(2026, 1, 1),
      ),
      0,
    );
    expect(
      output.join('\n').indexOf('g-1'),
      lessThan(output.join('\n').indexOf('g-2')),
    );
    expect(client.method, 'grid/gate/ls');
  });

  test('resolve parses grades and sends typed map', () async {
    final client = FakeClient(const StationCommandCompleted({}));
    expect(
      await runGateResolve(
        gridRoot: '/grid',
        gateId: 'g-1',
        grades: const ['critic=a'],
        rationale: 'reviewed',
        client: client,
        out: (_) {},
      ),
      0,
    );
    expect(client.params!['grades'], {'critic': 'A'});
  });

  test('duplicate grade refuses before dispatch', () async {
    final client = FakeClient(const StationCommandCompleted({}));
    expect(
      await runGateResolve(
        gridRoot: '/grid',
        gateId: 'g-1',
        grades: const ['critic=A', 'critic=B'],
        rationale: 'x',
        client: client,
        err: (_) {},
      ),
      64,
    );
    expect(client.calls, 0);
  });

  test('unavailable station is loud exit 64', () async {
    final errors = <String>[];
    expect(
      await runGateLs(
        gridRoot: '/grid',
        client: FakeClient(
          const StationCommandUnavailable('station.lock is absent'),
        ),
        err: errors.add,
      ),
      64,
    );
    expect(errors.single, contains('station.lock'));
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
