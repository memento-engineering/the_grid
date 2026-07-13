@Tags(['integration'])
library;

// The FULL stack over a REAL VM service: a real runGrid tree, a real
// GridExplorationHost with the dev-mode contributor, a real `dart:developer`
// registration, and a real VM-service call that RE-COMPOSES the tree.
//
// Run under `dart test --enable-vm-service -t integration`. Self-skips
// otherwise (the offline suite stays offline), mirroring
// grid_exploration's vm_service_attach_test.
import 'dart:developer' as developer;
import 'dart:isolate' as iso;

import 'package:beads_dart/beads_dart.dart';
import 'package:grid_exploration/grid_exploration.dart';
import 'package:grid_sdk/grid_sdk.dart';
import 'package:test/test.dart';
import 'package:vm_service/utils.dart';
import 'package:vm_service/vm_service_io.dart';

/// A build-counting station: the witness that the tool RE-COMPOSED the tree.
class _ProbeDelegate extends GridDelegate {
  _ProbeDelegate(this.builds);
  final List<int> builds;

  @override
  Seed build(TreeContext context, GridConfiguration configuration) {
    builds.add(1);
    return RawAssetGrid(root: '/grid/home', assets: const []);
  }
}

class _FakeReader implements SnapshotReader {
  @override
  Future<GraphSnapshot> read() async => GraphSnapshot.fromParts(
    beads: const [Bead(id: 'tg-1')],
    dependencies: const [],
    readyIds: const {},
    capturedAt: DateTime.utc(2026),
  );
}

void main() {
  test('the reload extension re-composes the REAL tree over a REAL VM service',
      () async {
    final info = await developer.Service.getInfo();
    final serverUri = info.serverUri;
    if (serverUri == null) {
      markTestSkipped('VM service not enabled — run with --enable-vm-service');
      return;
    }

    final builds = <int>[];
    final grid = runGrid(
      _ProbeDelegate(builds),
      delegateFactory: () => _ProbeDelegate(builds),
    );
    addTearDown(grid.teardown);
    expect(builds, hasLength(1)); // the launch build

    final runtime = GridControllerRuntime(
      reader: _FakeReader(),
      dirtySources: const [],
    );
    await runtime.start();
    final host = GridExplorationHost(
      runtime,
      reassemble: ReassembleTool(
        hotReload: () async => (await grid.hotReload()).toJson(),
        hotRestart: () async => (await grid.hotRestart()).toJson(),
      ),
    );
    host.register();
    addTearDown(() async {
      await host.dispose();
      await runtime.dispose();
    });

    final ws = convertToWebSocketUrl(serviceProtocolUrl: serverUri);
    final vm = await vmServiceConnectUri(ws.toString());
    addTearDown(vm.dispose);
    final isolateId = developer.Service.getIsolateId(iso.Isolate.current)!;

    // The handshake DISCOVERS it (a registered tool is a discoverable tool).
    final handshake = await vm.callServiceExtension(
      'ext.exploration.core.handshake',
      isolateId: isolateId,
    );
    final extensions = handshake.json![kExtensionsKey]! as List;
    expect((extensions.single as Map)['tools'], contains('reload'));

    final response = await vm.callServiceExtension(
      gridExtension(ReassembleTool.toolName),
      isolateId: isolateId,
      args: <String, String>{'mode': 'reload'},
    );

    expect(response.json!['ok'], isTrue);
    final value = response.json!['value']! as Map<String, Object?>;
    expect(value['mode'], 'reload');
    expect(value['generation'], 1);
    // The station's master build RE-RAN, over the wire.
    expect(builds, hasLength(2));
  });
}
