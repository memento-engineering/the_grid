import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

/// Locates the version-pinned upstream fixtures
/// (`fixtures/upstream/2026-07-10-bd-1.0.5/`) from the repo root, walking up
/// from the test's working directory so tests pass regardless of whether they
/// run from the package or the workspace root. Fixtures are the single source
/// of truth — never copied into the package (CLAUDE.md: version-pinned,
/// re-captured only via the porting skill).
const fixtureSet = '2026-07-10-bd-1.0.5';

Directory _fixtureDir() {
  var dir = Directory.current;
  for (var i = 0; i < 8; i++) {
    final candidate = Directory(
      p.join(dir.path, 'fixtures', 'upstream', fixtureSet),
    );
    if (candidate.existsSync()) return candidate;
    final parent = dir.parent;
    if (parent.path == dir.path) break;
    dir = parent;
  }
  throw StateError(
    'fixture set $fixtureSet not found walking up from ${Directory.current.path}',
  );
}

/// Raw text of a pinned fixture file.
String fixtureText(String name) =>
    File(p.join(_fixtureDir().path, name)).readAsStringSync();

/// A pinned fixture decoded as JSON.
Object? fixtureJson(String name) => jsonDecode(fixtureText(name));

/// Lines of a `.jsonl` fixture decoded as JSON objects.
List<Map<String, dynamic>> fixtureJsonl(String name) => [
  for (final line in const LineSplitter().convert(fixtureText(name)))
    if (line.trim().isNotEmpty) jsonDecode(line) as Map<String, dynamic>,
];
