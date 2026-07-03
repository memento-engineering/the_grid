// A minimal the_grid VM-service target for the cross-process exploration
// conformance test (M3 Track 6). Registers a [GridExplorationHost] over a
// FAKE, in-memory controller snapshot (no bd / Dolt), prints its own VM
// service ws:// URI as a `GRID_VM_URI=<uri>` line on stdout, then idles until
// killed. Run under `--enable-vm-service`:
//
//   dart --enable-vm-service=0 --disable-service-auth-codes \
//     packages/grid_exploration/tool/attach_target.dart
//
// The fake snapshot mirrors `attach_conformance_test.dart`: 3 beads, 2 ready.
// ignore_for_file: avoid_print

import 'dart:async';
import 'dart:developer' as developer;
import 'dart:io';

import 'package:beads_dart/beads_dart.dart';
import 'package:grid_exploration/grid_exploration.dart';
import 'package:vm_service/utils.dart';

class _FakeReader implements SnapshotReader {
  @override
  Future<GraphSnapshot> read() async => GraphSnapshot.fromParts(
    beads: [
      Bead(id: 'tg-1', title: 'tron', issueType: IssueType.molecule),
      const Bead(id: 'tg-2', title: 'ready one'),
      const Bead(id: 'tg-3', title: 'ready two'),
    ],
    dependencies: const [],
    readyIds: {'tg-2', 'tg-3'},
    capturedAt: DateTime.utc(2026, 6, 15, 12),
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

  final ws = convertToWebSocketUrl(serviceProtocolUrl: serverUri);
  // Sentinel line the cross-process test greps for.
  print('GRID_VM_URI=$ws');

  // Idle until the parent kills us.
  final never = Completer<void>();
  ProcessSignal.sigterm.watch().listen((_) => exit(0));
  await never.future;
}
