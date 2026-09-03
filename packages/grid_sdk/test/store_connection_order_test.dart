import 'package:beads_dart/beads_dart.dart' show DoltEndpoint, DoltQueryService;
import 'package:grid_sdk/grid_sdk.dart';
import 'package:test/test.dart';

const _endpoint = DoltEndpoint(
  host: '127.0.0.1',
  port: 4407,
  database: 'tg',
  user: 'beads_dart',
  password: 'secret',
);

void main() {
  test('the state store closes first, then work stores by name', () {
    final ordered = orderedStoreConnections(
      state: DoltQueryService(_endpoint),
      work: {
        'mars': DoltQueryService(_endpoint),
        'earth': DoltQueryService(_endpoint),
      },
    );
    expect(ordered.map((c) => c.name), ['state', 'earth', 'mars']);
  });

  test('a CLI-path store contributes no connection', () {
    final ordered = orderedStoreConnections(state: null, work: {'earth': null});
    expect(ordered, isEmpty);
  });

  test(
    'close delegates to the pooled service and tolerates a second call',
    () async {
      final connection = orderedStoreConnections(
        state: DoltQueryService(_endpoint),
        work: const {},
      ).single;
      expect(connection.name, 'state');
      await connection.close();
      await connection.close();
    },
  );
}
