import 'dart:io';

import 'package:grid_exploration/grid_exploration.dart'
    show coreExtension, gridExtension;
import 'package:leonard_contract/leonard_contract.dart';
import 'package:test/test.dart';

/// Leonard contract owns the shared prefix. `grid_devtools` imports that pure
/// protocol vocabulary without linking the host; this test inspects its
/// runtime source to prevent a local redeclaration or literal from returning.
void main() {
  test('grid_devtools derives ext.leonard.* methods from leonard_contract', () {
    final source = _readDevtoolsProtocolSource();

    expect(
      source,
      contains("import 'package:leonard_contract/leonard_contract.dart'"),
    );
    expect(source, isNot(contains('const String kExplorationPrefix')));
    expect(source, isNot(contains("'ext.leonard'")));
    expect(
      '$kLeonardExtensionPrefix.core.handshake',
      coreExtension('handshake'),
    );
    expect('$kLeonardExtensionPrefix.grid.events', gridExtension('events'));
  });
}

/// Locates and reads `grid_devtools`' pinned-constants source, resolved
/// relative to the repo root so the test runs from either the package or
/// the workspace cwd (mirrors `conformance_fixture_test.dart`'s
/// `_fixtureDir` pattern).
String _readDevtoolsProtocolSource() {
  const rel = '../grid_devtools/lib/src/protocol/grid_exploration_client.dart';
  final fromPackage = File(rel);
  if (fromPackage.existsSync()) return fromPackage.readAsStringSync();
  const fromRepo =
      'packages/grid_devtools/lib/src/protocol/grid_exploration_client.dart';
  final repoFile = File(fromRepo);
  if (repoFile.existsSync()) return repoFile.readAsStringSync();
  fail(
    'could not locate grid_devtools/lib/src/protocol/grid_exploration_client.dart '
    'from cwd ${Directory.current.path} — checked $rel and $fromRepo',
  );
}
