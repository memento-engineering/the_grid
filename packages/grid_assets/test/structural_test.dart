// Track B — the meaningfulness half of the opinion-free-engine fence.
//
// grid_engine/test/structural_test.dart asserts the engine names NONE of the
// opinion literals. That assertion would be vacuously true if the opinions
// existed NOWHERE. This test proves they DO live in `grid_assets`: the `code`
// asset's capabilities spawn `claude` (the coding agent + the LLM committee
// critics). Pure-Dart, offline (reads files; no live anything).
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:test/test.dart';

/// Resolves this package's `lib` directory, walking up from the test's working
/// dir to find `packages/grid_assets/lib` (robust whether the suite runs from
/// the repo root or the package dir).
Directory _libDir() {
  final candidates = <String>[
    'lib',
    p.join('packages', 'grid_assets', 'lib'),
  ];
  var dir = Directory.current;
  for (var i = 0; i < 6; i++) {
    for (final rel in candidates) {
      final probe = Directory(p.join(dir.path, rel));
      if (probe.existsSync() &&
          File(p.join(probe.path, 'grid_assets.dart')).existsSync()) {
        return probe;
      }
    }
    final parent = dir.parent;
    if (parent.path == dir.path) break;
    dir = parent;
  }
  fail('could not locate packages/grid_assets/lib from ${Directory.current.path}');
}

void main() {
  group('the opinions DO live in grid_assets (the fence is meaningful)', () {
    final libDir = _libDir();
    final allSource = libDir
        .listSync(recursive: true)
        .whereType<File>()
        .where((f) => f.path.endsWith('.dart'))
        .map((f) => f.readAsStringSync())
        .join('\n');

    test('the `code` asset spawns `claude` (the coding agent + the committee '
        'critics)', () {
      // The compiled `code` asset's capabilities spawn `claude` — both the
      // coding agent and the three LLM committee critics — so the literal exists
      // SOMEWHERE, proving grid_engine's engine-is-clean assertion (the engine
      // names NONE of it) is not vacuously true. (The toy `melos` verify is gone
      // — `verify` is now the committee whose gating lane runs the bead's own
      // Validation Plan, naming no fixed build tool.)
      expect(allSource, contains('claude'));
    });
  });
}
