import 'package:grid_controller/grid_controller.dart';
import 'package:grid_exploration/grid_exploration.dart';
import 'package:test/test.dart';

/// A minimal in-test [SnapshotReader] returning a scripted snapshot.
class _FakeReader implements SnapshotReader {
  _FakeReader(this.build);
  GraphSnapshot Function() build;
  @override
  Future<GraphSnapshot> read() async => build();
}

GraphSnapshot _snap(List<Bead> beads, {Set<String> ready = const {}}) =>
    GraphSnapshot.fromParts(
      beads: beads,
      dependencies: const [],
      readyIds: ready,
      capturedAt: DateTime.utc(2026, 6, 11, 12),
    );

Bead _bead(String id, {BeadStatus status = BeadStatus.open}) =>
    Bead(id: id, title: 'T-$id', status: status);

Future<GridControllerRuntime> _startedRuntime(
  GraphSnapshot Function() build,
) async {
  final runtime = GridControllerRuntime(
    reader: _FakeReader(build),
    dirtySources: const [],
  );
  await runtime.start();
  return runtime;
}

void main() {
  group('protocol constants + wire shapes', () {
    test('extension prefix is the ratified ext.exploration (ADR-0001 D6)', () {
      expect(kExplorationPrefix, 'ext.exploration');
      expect(coreExtension('handshake'), 'ext.exploration.core.handshake');
      expect(gridExtension('requery'), 'ext.exploration.grid.requery');
    });

    test('graphEventToWire is exhaustive and compact', () {
      final created = graphEventToWire(BeadCreated(_bead('a')));
      expect(created['type'], 'beadCreated');
      expect((created['bead']! as Map)['id'], 'a');

      final ready = graphEventToWire(
        const ReadySetChanged(entered: {'b', 'a'}, exited: {'c'}),
      );
      expect(ready['type'], 'readySetChanged');
      expect(ready['entered'], ['a', 'b']); // sorted
      expect(ready['exited'], ['c']);

      final init = graphEventToWire(
        const SnapshotInitialized(beadCount: 3, readyCount: 1),
      );
      expect(init, {
        'type': 'snapshotInitialized',
        'beadCount': 3,
        'readyCount': 1,
      });
    });
  });

  group('GridExplorationHost JSON builders', () {
    test('handshake advertises the grid plugin and its tools', () async {
      final runtime = await _startedRuntime(() => _snap([_bead('a')]));
      addTearDown(runtime.dispose);
      final host = GridExplorationHost(runtime);

      final handshake = host.handshakeJson();
      expect(handshake['protocolVersion'], '1');
      expect(handshake['pluginCount'], 1);
      final plugins = handshake['plugins']! as List;
      expect((plugins.single as Map)['namespace'], 'grid');
      expect((plugins.single as Map)['tools'], [
        'requery',
        'snapshot',
        'ready',
        'events',
        'stats',
      ]);
    });

    test(
      'observation has empty semantics/routes and grid under plugins',
      () async {
        final runtime = await _startedRuntime(
          () => _snap([_bead('a'), _bead('b')], ready: {'a'}),
        );
        addTearDown(runtime.dispose);
        final host = GridExplorationHost(runtime);

        final obs = host.observationJson();
        expect(obs['type'], 'Observation');
        final value = obs['value']! as Map<String, Object?>;
        expect(value['semantics'], isEmpty);
        expect(value['routes'], isEmpty);
        expect((value['stability']! as Map)['refreshCount'], greaterThan(0));
        final grid =
            (value['plugins']! as Map)['grid']! as Map<String, Object?>;
        expect(grid['beadCount'], 2);
        expect(grid['readyCount'], 1);
      },
    );
  });

  group('grid tool dispatch', () {
    test('snapshot tool returns counts and ready summaries', () async {
      final runtime = await _startedRuntime(
        () => _snap([_bead('a'), _bead('b')], ready: {'b'}),
      );
      addTearDown(runtime.dispose);
      final host = GridExplorationHost(runtime);

      final result = await host.dispatchTool('snapshot', const {});
      expect(result['ok'], isTrue);
      final value = result['value']! as Map<String, Object?>;
      expect(value['beadCount'], 2);
      expect(value['readyCount'], 1);
      expect((value['readyBeads']! as List).single, containsPair('id', 'b'));
    });

    test('requery forces a refresh and reports stats', () async {
      var beads = [_bead('a')];
      final runtime = await _startedRuntime(() => _snap(beads));
      addTearDown(runtime.dispose);
      final host = GridExplorationHost(runtime);

      beads = [_bead('a'), _bead('c')];
      final result = await host.dispatchTool('requery', const {});
      expect(result['ok'], isTrue);
      expect(runtime.current!.beadCount, 2);
    });

    test(
      'events tool honors the limit param and returns wire events',
      () async {
        var beads = [_bead('a')];
        final runtime = await _startedRuntime(() => _snap(beads));
        addTearDown(runtime.dispose);
        final host = GridExplorationHost(runtime);
        beads = [_bead('a'), _bead('b')];
        await runtime.requery();

        final result = await host.dispatchTool('events', const {'limit': '1'});
        final value = result['value']! as Map<String, Object?>;
        expect(value['count'], 1);
        expect((value['events']! as List), hasLength(1));
      },
    );

    test('unknown tool yields ok:false', () async {
      final runtime = await _startedRuntime(() => _snap([_bead('a')]));
      addTearDown(runtime.dispose);
      final host = GridExplorationHost(runtime);
      final result = await host.dispatchTool('nope', const {});
      expect(result['ok'], isFalse);
      expect(result['error'], contains('unknown grid tool'));
    });
  });
}
