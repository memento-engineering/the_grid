// Acceptance criterion 3 (PDR §6.3) live check, runnable directly:
//   dart --enable-vm-service=0 --disable-service-auth-codes \
//     packages/grid_exploration/tool/criterion3_attach.dart
//
// Registers the exploration host in-process, attaches to this process's own VM
// service, and exercises handshake / stable observation / a grid tool over the
// real protocol. Exits 0 on success, 1 on failure.
// ignore_for_file: avoid_print

import 'dart:developer' as developer;
import 'dart:io';
import 'dart:isolate' as iso;

import 'package:grid_controller/grid_controller.dart';
import 'package:grid_exploration/grid_exploration.dart';
import 'package:vm_service/utils.dart';
import 'package:vm_service/vm_service_io.dart';

class _FakeReader implements SnapshotReader {
  @override
  Future<GraphSnapshot> read() async => GraphSnapshot.fromParts(
    beads: [
      Bead(id: 'tg-1', title: 'tron', issueType: IssueType.molecule),
      const Bead(id: 'tg-2', title: 'ready one'),
    ],
    dependencies: const [],
    readyIds: {'tg-2'},
    capturedAt: DateTime.utc(2026, 6, 11, 12),
  );
}

Future<void> main() async {
  final info = await developer.Service.getInfo();
  final serverUri = info.serverUri;
  if (serverUri == null) {
    print('FAIL: VM service not enabled — run with --enable-vm-service');
    exit(1);
  }

  final runtime = GridControllerRuntime(
    reader: _FakeReader(),
    dirtySources: const [],
  );
  await runtime.start();
  GridExplorationHost(runtime).register();

  final vm = await vmServiceConnectUri(
    convertToWebSocketUrl(serviceProtocolUrl: serverUri).toString(),
  );
  final isolateId = developer.Service.getIsolateId(iso.Isolate.current)!;

  final handshake = await vm.callServiceExtension(
    'ext.exploration.core.handshake',
    isolateId: isolateId,
  );
  final observation = await vm.callServiceExtension(
    'ext.exploration.core.get_stable_observation',
    isolateId: isolateId,
  );
  final ready = await vm.callServiceExtension(
    'ext.exploration.grid.ready',
    isolateId: isolateId,
  );

  final checks = <String, bool>{
    'handshake.protocolVersion == 1': handshake.json!['protocolVersion'] == '1',
    // ADR-0000 A33: the wire key is `extensions`, matching leonard's reader.
    'handshake advertises grid extension':
        ((handshake.json!['extensions']! as List).first as Map)['namespace'] ==
        'grid',
    'observation.type == Observation':
        observation.json!['type'] == 'Observation',
    'observation has grid beadCount 2':
        (((observation.json!['value']! as Map)['extensions']! as Map)['grid']!
            as Map)['beadCount'] ==
        2,
    'grid.ready tool ok + count 1':
        ready.json!['ok'] == true &&
        (ready.json!['value']! as Map)['count'] == 1,
  };

  print('VM service: $serverUri');
  var ok = true;
  checks.forEach((label, passed) {
    print('  ${passed ? "PASS" : "FAIL"}  $label');
    ok = ok && passed;
  });

  await vm.dispose();
  await runtime.dispose();
  print(ok ? 'CRITERION 3: PASS' : 'CRITERION 3: FAIL');
  exit(ok ? 0 : 1);
}
