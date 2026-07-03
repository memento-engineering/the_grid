// Captures the_grid exploration host's wire output as pinned conformance
// fixtures (M3 Track 6). Writes the handshake, the stable observation, and a
// `grid.ready` tool result — all in the `extensions` shape (ADR-0000 A33) —
// over a FAKE, in-memory controller snapshot (no bd / Dolt).
//
// Re-capture (never hand-edit the fixtures), from the package root:
//   dart run tool/capture_conformance_fixture.dart \
//     ../../fixtures/exploration/2026-06-15-leonard-extensions
//
// The same snapshot (3 beads, 2 ready) is asserted by
// `test/conformance_fixture_test.dart`, which pins the bytes so any future
// drift from leonard's `extensions` read contract is caught offline.
// ignore_for_file: avoid_print

import 'dart:convert';
import 'dart:io';

import 'package:beads_dart/beads_dart.dart';
import 'package:grid_exploration/grid_exploration.dart';

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

Future<void> main(List<String> args) async {
  if (args.isEmpty) {
    print('usage: capture_conformance_fixture.dart <dest-dir>');
    exit(64);
  }
  final dir = Directory(args.first)..createSync(recursive: true);

  final runtime = GridControllerRuntime(
    reader: _FakeReader(),
    dirtySources: const [],
  );
  await runtime.start();
  final host = GridExplorationHost(runtime);

  const enc = JsonEncoder.withIndent('  ');
  File('${dir.path}/handshake.json')
      .writeAsStringSync('${enc.convert(host.handshakeJson())}\n');
  File('${dir.path}/observation.json')
      .writeAsStringSync('${enc.convert(host.observationJson())}\n');
  final ready = await host.dispatchTool('ready', const {});
  File('${dir.path}/grid-ready.json')
      .writeAsStringSync('${enc.convert(ready)}\n');

  await runtime.dispose();
  print('captured handshake/observation/grid-ready to ${dir.path}');
}
