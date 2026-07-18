import 'package:beads_dart/beads_dart.dart';
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
      // ADR-0000 A33: the wire key is `extensions`, no legacy `plugins`.
      expect(handshake.containsKey('plugins'), isFalse);
      final extensions = handshake[kExtensionsKey]! as List;
      expect((extensions.single as Map)['namespace'], 'grid');
      expect((extensions.single as Map)['tools'], [
        'requery',
        'snapshot',
        'ready',
        'events',
        'stats',
      ]);
    });

    test(
      'observation has empty semantics/routes and grid under extensions',
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
        // ADR-0000 A33: grid state lives under `extensions.grid`, not `plugins`.
        expect(value.containsKey('plugins'), isFalse);
        final grid =
            (value[kExtensionsKey]! as Map)['grid']! as Map<String, Object?>;
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

  group('the dev-mode reload tool', () {
    test(
      'a dev-mode station advertises `reload` as a SIXTH tool — registered by '
      'the host, so a registered tool is a DISCOVERABLE tool',
      () async {
        final runtime = await _startedRuntime(() => _snap([_bead('a')]));
        addTearDown(runtime.dispose);
        final host = GridExplorationHost(
          runtime,
          reassemble: ReassembleTool(
            hotReload: () async => {'mode': 'reload', 'generation': 1},
            hotRestart: () async => {'mode': 'restart', 'generation': 1},
          ),
        );

        final extensions = host.handshakeJson()[kExtensionsKey]! as List;
        expect((extensions.single as Map)['namespace'], 'grid');
        expect((extensions.single as Map)['tools'], [
          'requery',
          'snapshot',
          'ready',
          'events',
          'stats',
          'reload',
        ]);

        // `mode` defaults to reload; the envelope matches the other five tools.
        final result = await host.dispatchTool('reload', const {});
        expect(result['ok'], isTrue);
        expect((result['value']! as Map)['mode'], 'reload');
        expect(
          (await host.dispatchTool('reload', const {
            'mode': 'restart',
          }))['value'],
          containsPair('mode', 'restart'),
        );
      },
    );

    test(
      'a post-swap re-compose refusal rides the reload wire as ok:false',
      () async {
        final runtime = await _startedRuntime(() => _snap([_bead('a')]));
        addTearDown(runtime.dispose);
        final host = GridExplorationHost(
          runtime,
          reassemble: ReassembleTool(
            hotReload: () async => const {
              'mode': 'reload',
              'generation': 1,
              'rebuiltBranches': 0,
              'refused': true,
              'error':
                  'refused: re-compose failed after source swap - bounce the station',
              'reason': 'post_swap_recompose_failed',
              'requiresBounce': true,
              'details': 'StateError: fake post-swap rebuild failure',
            },
            hotRestart: () async => {'mode': 'restart', 'generation': 1},
          ),
        );

        final result = await host.dispatchTool('reload', const {});

        expect(result['ok'], isFalse);
        expect(result['error'], contains('bounce the station'));
        expect(result['reason'], 'post_swap_recompose_failed');
        expect(result['requiresBounce'], isTrue);
        final value = result['value']! as Map<String, Object?>;
        expect(value['refused'], isTrue);
        expect(value['details'], contains('fake post-swap rebuild failure'));
      },
    );

    test('WITHOUT a contributor the host is EXACTLY as-is: the five read-only '
        'tools, no reload', () async {
      final runtime = await _startedRuntime(() => _snap([_bead('a')]));
      addTearDown(runtime.dispose);
      final host = GridExplorationHost(runtime);

      expect(host.toolNames, [
        'requery',
        'snapshot',
        'ready',
        'events',
        'stats',
      ]);
      final extensions = host.handshakeJson()[kExtensionsKey]! as List;
      expect((extensions.single as Map)['tools'], isNot(contains('reload')));
      // The observation plugin owns no such tool — it stays read-only.
      final unknown = await host.dispatchTool('reload', const {});
      expect(unknown['ok'], isFalse);
    });

    test('an unknown reassemble mode is refused LOUDLY (never a silent '
        'reload)', () async {
      final runtime = await _startedRuntime(() => _snap([_bead('a')]));
      addTearDown(runtime.dispose);
      final host = GridExplorationHost(
        runtime,
        reassemble: ReassembleTool(
          hotReload: () async => fail('a bad mode must never reload'),
          hotRestart: () async => fail('a bad mode must never restart'),
        ),
      );

      await expectLater(
        host.dispatchTool('reload', const {'mode': 'bounce'}),
        throwsA(isA<ArgumentError>()),
      );
    });

    test('a colliding dev tool name refuses at CONSTRUCTION', () async {
      final runtime = await _startedRuntime(() => _snap([_bead('a')]));
      addTearDown(runtime.dispose);
      expect(
        () => GridExplorationHost(runtime, reassemble: _CollidingTool()),
        throwsA(isA<ArgumentError>()),
      );
    });
  });
}

/// A contributor that (wrongly) claims an observation tool name — the collision
/// guard's positive control (Fakes, not mocks).
class _CollidingTool implements ReassembleTool {
  @override
  StationReassemble get hotReload =>
      () async => const {};

  @override
  StationReassemble get hotRestart =>
      () async => const {};

  @override
  List<String> get toolNames => const ['stats'];

  @override
  Future<Map<String, Object?>> dispatch(
    String name,
    Map<String, String> params,
  ) async => const {};
}
