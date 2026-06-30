// M6 Track D — the compute-domain structural fence (DoD-4).
//
// The federation CORE (grid_federation/lib) must name NO compute-specific detail
// after the Track D split — the bus/protocol stays kind-agnostic (ADR-0011 D3).
// This grep-style assertion proves it; the meaningfulness half proves the
// compute payloads DO live in grid_assets, so the fence is not vacuous. Reads
// files only — no live anything.
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:test/test.dart';

/// Resolves a sibling package's `lib` dir by walking up to `packages/<pkg>/lib`
/// (robust whether the suite runs from the package dir or the repo root). The
/// `<pkg>.dart` barrel is the marker so a `lib` candidate matches only its own
/// package.
Directory _libDir(String pkg) {
  final candidates = <String>[
    'lib',
    p.join('..', pkg, 'lib'),
    p.join('packages', pkg, 'lib'),
  ];
  var dir = Directory.current;
  for (var i = 0; i < 6; i++) {
    for (final rel in candidates) {
      final probe = Directory(p.join(dir.path, rel));
      if (probe.existsSync() &&
          File(p.join(probe.path, '$pkg.dart')).existsSync()) {
        return probe;
      }
    }
    final parent = dir.parent;
    if (parent.path == dir.path) break;
    dir = parent;
  }
  fail('could not locate packages/$pkg/lib from ${Directory.current.path}');
}

String _allSource(Directory libDir) => libDir
    .listSync(recursive: true)
    .whereType<File>()
    .where((f) => f.path.endsWith('.dart'))
    .map((f) => f.readAsStringSync())
    .join('\n');

void main() {
  group('Track D structural fence — the federation core is kind-agnostic', () {
    final fedSource = _allSource(_libDir('grid_federation'));

    test('grid_federation/lib names NO compute symbol (case-insensitive)', () {
      final lower = fedSource.toLowerCase();
      const forbidden = [
        'compute',
        'dispatchcommand',
        'commandresult',
        'commandexecutor',
      ];
      for (final symbol in forbidden) {
        expect(
          lower.contains(symbol),
          isFalse,
          reason: 'the federation core must not name "$symbol" — the bus stays '
              'kind-agnostic (ADR-0011 D3); the compute concern lives in '
              'grid_assets/src/compute/',
        );
      }
    });

    test('the compute domain DOES live in grid_assets (the fence is meaningful)',
        () {
      final assetSource = _allSource(_libDir('grid_assets'));
      expect(assetSource, contains('class DispatchCommand'));
      expect(assetSource, contains('class CommandResult'));
      expect(assetSource, contains('class LeaseCapability'));
      expect(assetSource, contains("kComputeKind = 'compute'"));
    });
  });
}
