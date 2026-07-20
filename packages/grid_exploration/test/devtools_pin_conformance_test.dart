import 'dart:io';

import 'package:grid_exploration/grid_exploration.dart';
import 'package:test/test.dart';

/// Cross-pinning conformance for `grid_devtools`' hand-pinned
/// `ext.exploration.*` method strings (ADR-0002 Decision 3, tg-8gv.11(e)).
///
/// `grid_devtools` deliberately does NOT depend on `grid_exploration` (it
/// rides the wire protocol only, per the client's own doc comment), so it
/// re-declares the fully-qualified extension method names as its own
/// constants instead of importing [coreExtension]/[gridExtension]. That is a
/// sanctioned duplication, not an oversight — but nothing stops the two
/// sides drifting apart on a rename. This test lives HERE, in
/// `grid_exploration`'s suite, rather than in `grid_devtools`' own suite,
/// because `grid_devtools`' test suite cannot currently LOAD on this
/// machine (a pre-existing SDK crash unrelated to this change).
///
/// It stays hermetic: a plain file read of `grid_devtools`' pinned-constants
/// source, string-literal extraction, and a value comparison against
/// `grid_exploration`'s own [coreExtension]/[gridExtension] builders — no
/// import of `grid_devtools`.
void main() {
  test(
    'grid_devtools pinned ext.exploration.* strings match grid_exploration',
    () {
      final source = _readDevtoolsProtocolSource();

      final handshake = _pinnedLiteral(source, 'kHandshakeExtension');
      final events = _pinnedLiteral(source, 'kEventsExtension');

      expect(
        handshake,
        coreExtension('handshake'),
        reason:
            "grid_devtools' kHandshakeExtension has drifted from "
            "grid_exploration's coreExtension('handshake') — update the pin "
            'in grid_devtools/lib/src/protocol/grid_exploration_client.dart.',
      );
      expect(
        events,
        gridExtension('events'),
        reason:
            "grid_devtools' kEventsExtension has drifted from "
            "grid_exploration's gridExtension('events') — update the pin in "
            'grid_devtools/lib/src/protocol/grid_exploration_client.dart.',
      );
    },
  );
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

/// Extracts the single-quoted string literal assigned to
/// `const String <name> = '...'` in [source]. Fails loudly (rather than
/// returning null) so a renamed/removed constant breaks this test instead
/// of silently no-op passing.
String _pinnedLiteral(String source, String name) {
  final match = RegExp("const String $name = '([^']*)';").firstMatch(source);
  if (match == null) {
    fail(
      "could not find 'const String $name = ...;' in grid_devtools' pinned "
      'protocol source — has the constant been renamed or removed?',
    );
  }
  return match.group(1)!;
}
