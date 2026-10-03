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

  test(
    'the trajectory rides between the state store and the work stores',
    () async {
      final harness = await TrajectoryHarness.build(
        config: const TrajectoryConfig(mode: TrajectoryConfigMode.disabled),
        gridHome: '/nonexistent',
        station: 'tranquility',
      );
      final ordered = orderedStoreConnections(
        state: DoltQueryService(_endpoint),
        trajectory: harness,
        work: {
          'mars': DoltQueryService(_endpoint),
          'earth': DoltQueryService(_endpoint),
        },
      );
      expect(ordered.map((c) => c.name), [
        'state',
        'trajectory',
        'earth',
        'mars',
      ]);
      // A harness that never dialled closes nothing and never throws.
      await ordered[1].close();
    },
  );

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

  test('the boot summary names the read deadline and the timed-out reads per '
      'pooled store (tg-6n18)', () {
    final line = describeStoreDeadlines(
      orderedStoreConnections(
        state: DoltQueryService(_endpoint),
        work: {'earth': DoltQueryService(_endpoint), 'mars': null},
      ),
    );

    expect(
      line,
      'store query deadline: '
      '${DoltQueryService.queryTimeout.inMilliseconds}ms '
      '(DoltQueryService.queryTimeout)  ·  timed-out reads: 0 '
      '(state 0, earth 0)',
    );
    expect(
      describeStoreDeadlines(const <StoreConnection>[]),
      endsWith('timed-out reads: n/a (no SQL read path open)'),
      reason: 'the CLI read path has no SQL deadline to count against',
    );
  });
}
