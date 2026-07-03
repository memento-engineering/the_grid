import 'dart:convert';
import 'dart:io';

import 'package:beads_dart/beads_dart.dart';
import 'package:grid_exploration/grid_exploration.dart';
import 'package:test/test.dart';

/// Offline replay of the pinned exploration-attach conformance fixture
/// (`fixtures/exploration/2026-06-15-leonard-extensions/`), M3 Track 6.
///
/// Two guarantees, both pure (no VM service, no bd/Dolt):
///
///  1. **Leonard-faithful parse.** The pinned host bytes decode through a
///     reader that reads ONLY `extensions` (no `plugins` fallback) — exactly
///     leonard's `vm_service_client.dart` / `observation/models.dart` — and
///     yield the grid namespace, its 5 tools, and the grid data fields a
///     leonard prompt renders. This is what proves a stock leonard attaches.
///
///  2. **Pin freshness.** Re-running the host's builders today reproduces the
///     pinned bytes (modulo the volatile `lastRefreshMs` latency fields,
///     normalized), so any future drift from the `extensions` shape — a
///     reintroduced `plugins` key, a renamed field, a dropped tool — breaks
///     this test. Re-capture via `tool/capture_conformance_fixture.dart`;
///     never hand-edit the fixtures (see the MANIFEST).

const _kExtensionsKey = 'extensions';

/// The fixtures dir, resolved from the test cwd (the package root) with a
/// fallback to the repo-root layout so the test runs from either location.
Directory _fixtureDir() {
  const rel = '../../fixtures/exploration/2026-06-15-leonard-extensions';
  final fromPackage = Directory(rel);
  if (fromPackage.existsSync()) return fromPackage;
  final fromRepo = Directory(
    'fixtures/exploration/2026-06-15-leonard-extensions',
  );
  return fromRepo;
}

Map<String, Object?> _readJson(Directory dir, String name) =>
    jsonDecode(File('${dir.path}/$name').readAsStringSync())
        as Map<String, Object?>;

/// Recursively drop the volatile `lastRefreshMs` keys so the pin compares the
/// load-bearing shape, not wall-clock jitter.
Object? _normalize(Object? node) {
  if (node is Map) {
    return <String, Object?>{
      for (final entry in node.entries)
        if (entry.key != 'lastRefreshMs')
          '${entry.key}': _normalize(entry.value),
    };
  }
  if (node is List) return [for (final e in node) _normalize(e)];
  return node;
}

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

void main() {
  final dir = _fixtureDir();

  group('pinned extensions-shape conformance fixture', () {
    test('fixtures are present (re-capture via the tool, do not hand-edit)', () {
      expect(
        dir.existsSync(),
        isTrue,
        reason: 'missing ${dir.path} — run capture_conformance_fixture.dart',
      );
    });

    test('handshake decodes leonard-faithfully (extensions only)', () {
      final handshake = _readJson(dir, 'handshake.json');
      expect(handshake['protocolVersion'], '1');
      // No legacy keys leaked back in.
      expect(handshake.containsKey('plugins'), isFalse);
      expect(handshake.containsKey('pluginCount'), isFalse);

      final raw = handshake[_kExtensionsKey];
      expect(raw, isA<List<Object?>>());
      final entries = (raw! as List).cast<Map<Object?, Object?>>();
      final grid = entries.singleWhere((e) => e['namespace'] == 'grid');
      expect(grid['tools'], [
        'requery',
        'snapshot',
        'ready',
        'events',
        'stats',
      ]);
    });

    test('observation grid fragment decodes under extensions.grid', () {
      final obs = _readJson(dir, 'observation.json');
      expect(obs['type'], 'Observation');
      final value = obs['value']! as Map<String, Object?>;
      expect(value.containsKey('plugins'), isFalse);
      final extensions = value[_kExtensionsKey]! as Map<Object?, Object?>;
      final grid = extensions['grid']! as Map<Object?, Object?>;
      expect(grid['beadCount'], 3);
      expect(grid['readyCount'], 2);
      expect((grid['readyBeads']! as List), hasLength(2));
    });

    test('grid.ready fixture is an ok envelope with count 2', () {
      final ready = _readJson(dir, 'grid-ready.json');
      expect(ready['ok'], isTrue);
      expect((ready['value']! as Map)['count'], 2);
    });

    test('host builders still reproduce the pinned bytes (no drift)', () async {
      final runtime = GridControllerRuntime(
        reader: _FakeReader(),
        dirtySources: const [],
      );
      await runtime.start();
      addTearDown(runtime.dispose);
      final host = GridExplorationHost(runtime);

      expect(
        _normalize(host.handshakeJson()),
        _normalize(_readJson(dir, 'handshake.json')),
      );
      expect(
        _normalize(host.observationJson()),
        _normalize(_readJson(dir, 'observation.json')),
      );
      expect(
        _normalize(await host.dispatchTool('ready', const {})),
        _normalize(_readJson(dir, 'grid-ready.json')),
      );
    });
  });
}
