@Tags(['integration'])
library;

import 'dart:developer' as developer;
import 'dart:isolate' as iso;

import 'package:beads_dart/beads_dart.dart';
import 'package:grid_exploration/grid_exploration.dart';
import 'package:test/test.dart';
import 'package:vm_service/utils.dart';
import 'package:vm_service/vm_service_io.dart';

/// Hermetic exploration-attach CONFORMANCE test (M3 Track 6 DoD, the
/// in-process analog of the cross-process `leonard_cli --extensions grid` run).
///
/// Constructs a [GridExplorationHost] over a FAKE, in-memory controller
/// snapshot — no bd, no Dolt, no `grid run` — calls [GridExplorationHost.register],
/// then attaches a VM-service client to this very process and reads the three
/// surfaces a stock leonard exercises, **decoding exactly the way leonard's
/// reader does**:
///
///   * the handshake's `extensions` manifest (leonard reads ONLY `extensions`,
///     no `plugins` fallback — `leonard_agent/.../vm_service_client.dart:114`);
///   * the stable observation's `extensions[<ns>]` fragment, peeled into
///     `{namespace, data}` the way leonard's `ExtensionFragment.fromJson` does
///     (`leonard_agent/.../observation/models.dart`);
///   * one grid tool call (`grid.ready`) returning `{ok:true,…}`.
///
/// Run under `dart test --enable-vm-service -t integration`. Self-skips when
/// the VM service is absent (the offline suite stays hermetic and green).
///
/// ADR-0000 A33: the wire key is `extensions`. Asserting the leonard-shaped
/// read here is what proves a stock leonard truly attaches — not just that the
/// host emits *some* map.

const _kExtensionsKey = 'extensions';

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

/// Leonard-faithful manifest entry: derived ONLY from `extensions`.
List<({String namespace, List<String> tools})> readManifest(
  Map<String, Object?> handshake,
) {
  final raw = handshake[_kExtensionsKey];
  final out = <({String namespace, List<String> tools})>[];
  if (raw is List) {
    for (final entry in raw) {
      if (entry is! Map) continue;
      final namespace = entry['namespace'];
      if (namespace is! String) continue;
      final rawTools = entry['tools'];
      final tools = <String>[
        if (rawTools is List)
          for (final t in rawTools)
            if (t is String) t,
      ];
      out.add((namespace: namespace, tools: tools));
    }
  }
  return out;
}

/// Leonard-faithful fragment peel: `extensions[<ns>]` is a bare data map (the
/// grid host emits the bare shape), so `data` is the map itself. Mirrors
/// `ExtensionFragment.fromJson`'s bare-vs-envelope branch.
Map<String, Object?>? readFragmentData(
  Map<String, Object?> observation,
  String namespace,
) {
  final value = observation['value'];
  if (value is! Map) return null;
  final extensions = value[_kExtensionsKey];
  if (extensions is! Map) return null;
  final raw = extensions[namespace];
  if (raw is! Map) return null;
  final envNs = raw['namespace'];
  final envData = raw['data'];
  // Envelope shape — peel; otherwise the bare map IS the data.
  if (envNs is String && envData is Map) {
    return envData.cast<String, Object?>();
  }
  return raw.cast<String, Object?>();
}

void main() {
  test(
    'a leonard-shaped client attaches and reads the grid extension',
    () async {
      final info = await developer.Service.getInfo();
      final serverUri = info.serverUri;
      if (serverUri == null) {
        markTestSkipped('VM service not enabled — run with --enable-vm-service');
        return;
      }

      // Fake, in-memory controller snapshot — no bd / Dolt.
      final runtime = GridControllerRuntime(
        reader: _FakeReader(),
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

      // (a) handshake `extensions` carries namespace `grid` with its 5 tools.
      final handshake = await vm.callServiceExtension(
        'ext.exploration.core.handshake',
        isolateId: isolateId,
      );
      expect(handshake.json!['protocolVersion'], '1');
      final manifest = readManifest(handshake.json!.cast<String, Object?>());
      final grid = manifest.singleWhere((e) => e.namespace == 'grid');
      expect(grid.tools, [
        'requery',
        'snapshot',
        'ready',
        'events',
        'stats',
      ]);

      // (b) pullObservation yields `extensions['grid'].data` with the grid
      //     state fields a leonard prompt renders.
      final observation = await vm.callServiceExtension(
        'ext.exploration.core.get_stable_observation',
        isolateId: isolateId,
      );
      expect(observation.json!['type'], 'Observation');
      final data = readFragmentData(
        observation.json!.cast<String, Object?>(),
        'grid',
      );
      expect(data, isNotNull, reason: 'extensions[grid] fragment must decode');
      expect(data!['beadCount'], 3);
      expect(data['readyCount'], 2);
      expect(data['readyBeads'], isA<List<Object?>>());
      expect((data['readyBeads']! as List), hasLength(2));

      // (c) a `grid.ready` tool call returns ok.
      final ready = await vm.callServiceExtension(
        'ext.exploration.grid.ready',
        isolateId: isolateId,
      );
      expect(ready.json!['ok'], isTrue);
      expect((ready.json!['value']! as Map)['count'], 2);
    },
  );
}
