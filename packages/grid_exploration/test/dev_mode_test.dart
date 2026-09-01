import 'package:beads_dart/beads_dart.dart';
import 'package:grid_exploration/grid_exploration.dart';
import 'package:test/test.dart';

GraphSnapshot _snapshot(String id) => GraphSnapshot.fromParts(
  beads: [Bead(id: id, title: 'T-$id')],
  dependencies: const [],
  readyIds: {id},
  capturedAt: DateTime.utc(2026, 7, 25),
);

void main() {
  test('a null VM-service URI arms nothing and performs no work', () async {
    var reads = 0;
    var reloads = 0;
    var restarts = 0;

    final host = await armDevMode(
      vmServiceUri: null,
      latest: () {
        reads++;
        return _snapshot('unread');
      },
      readPath: () => 'unread',
      hotReload: () async {
        reloads++;
        return const {};
      },
      hotRestart: () async {
        restarts++;
        return const {};
      },
    );

    expect(host, isNull);
    expect((reads, reloads, restarts), (0, 0, 0));
  });

  test(
    'a VM-service URI composes the joined graph and reload callbacks',
    () async {
      var latest = _snapshot('first');
      var reloads = 0;
      var restarts = 0;

      final host = await armDevMode(
        vmServiceUri: 'http://127.0.0.1:8181/auth=/',
        latest: () => latest,
        readPath: () => 'joined:primary+state',
        hotReload: () async => {'mode': 'reload', 'generation': ++reloads},
        hotRestart: () async => {'mode': 'restart', 'generation': ++restarts},
      );
      expect(host, isNotNull);
      final armed = host!;
      addTearDown(armed.dispose);

      expect(armed, isA<DevModeHost>());
      // ignore: deprecated_member_use_from_same_package
      final DevModeSeat legacyHost = armed;
      expect(legacyHost, same(armed));

      expect(armed.vmServiceUri, 'http://127.0.0.1:8181/auth=/');
      expect(armed.runtime.current!.bead('first'), isNotNull);
      final observation = armed.host.observationJson();
      final value = observation['value']! as Map<String, Object?>;
      final extensions = value[kExtensionsKey]! as Map<String, Object?>;
      final grid = extensions[kGridNamespace]! as Map<String, Object?>;
      expect(grid['readPath'], 'joined:primary+state');

      expect(
        await armed.host.dispatchTool('reload', const {}),
        containsPair('ok', true),
      );
      expect(
        await armed.host.dispatchTool('reload', const {'mode': 'restart'}),
        containsPair('ok', true),
      );
      expect((reloads, restarts), (1, 1));

      latest = _snapshot('second');
      await armed.runtime.requery();
      expect(armed.runtime.current!.bead('second'), isNotNull);
    },
  );
}
