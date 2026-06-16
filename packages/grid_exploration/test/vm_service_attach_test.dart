@Tags(['integration'])
library;

import 'dart:developer' as developer;
import 'dart:isolate' as iso;

import 'package:grid_controller/grid_controller.dart';
import 'package:grid_exploration/grid_exploration.dart';
import 'package:test/test.dart';
import 'package:vm_service/utils.dart';
import 'package:vm_service/vm_service_io.dart';

/// Acceptance criterion 3 (PDR §6.3): a tool attaches to the running process
/// over its VM service URI, the exploration handshake succeeds, an observation
/// returns graph state, and at least one grid tool is invocable.
///
/// Run under `dart test --enable-vm-service`. Self-skips otherwise (the unit
/// suite stays offline). This exercises the *real* `dart:developer` extension
/// registration + dispatch over the VM service — not just the pure builders.

class _FakeReader implements SnapshotReader {
  _FakeReader(this.build);
  GraphSnapshot Function() build;
  @override
  Future<GraphSnapshot> read() async => build();
}

void main() {
  test(
    'exploration extensions are callable over the live VM service',
    () async {
      final info = await developer.Service.getInfo();
      final serverUri = info.serverUri;
      if (serverUri == null) {
        markTestSkipped(
          'VM service not enabled — run with --enable-vm-service',
        );
        return;
      }

      final runtime = GridControllerRuntime(
        reader: _FakeReader(
          () => GraphSnapshot.fromParts(
            beads: [
              Bead(id: 'tg-1', title: 'tron', issueType: IssueType.molecule),
              const Bead(id: 'tg-2', title: 'ready one'),
            ],
            dependencies: const [],
            readyIds: {'tg-2'},
            capturedAt: DateTime.utc(2026, 6, 11, 12),
          ),
        ),
        dirtySources: const [],
      );
      await runtime.start();
      final host = GridExplorationHost(runtime);
      host.register();
      addTearDown(() async {
        await host.dispose();
        await runtime.dispose();
      });

      final ws = convertToWebSocketUrl(serviceProtocolUrl: serverUri);
      final vm = await vmServiceConnectUri(ws.toString());
      addTearDown(vm.dispose);
      final isolateId = developer.Service.getIsolateId(iso.Isolate.current)!;

      // Handshake advertises the grid extension + its tools (ADR-0000 A33:
      // the wire key is `extensions`, matching leonard's reader).
      final handshake = await vm.callServiceExtension(
        'ext.exploration.core.handshake',
        isolateId: isolateId,
      );
      expect(handshake.json!['protocolVersion'], '1');
      final extensions = handshake.json!['extensions']! as List;
      expect((extensions.single as Map)['namespace'], 'grid');

      // Stable observation returns graph state under extensions.grid.
      final observation = await vm.callServiceExtension(
        'ext.exploration.core.get_stable_observation',
        isolateId: isolateId,
      );
      expect(observation.json!['type'], 'Observation');
      final value = observation.json!['value']! as Map<String, Object?>;
      final grid =
          (value['extensions']! as Map)['grid']! as Map<String, Object?>;
      expect(grid['beadCount'], 2);
      expect(grid['readyCount'], 1);

      // A grid tool is invocable.
      final ready = await vm.callServiceExtension(
        'ext.exploration.grid.ready',
        isolateId: isolateId,
      );
      expect(ready.json!['ok'], isTrue);
      expect((ready.json!['value']! as Map)['count'], 1);
    },
  );
}
