import 'dart:io';

import 'package:path/path.dart' as p;

/// Hermetic temp-dir helper for the containment tests (real symlinks/files on
/// disk) and the `integration`-tagged real-subprocess gates. Mirrors gc's
/// `t.TempDir()` + `os.WriteFile(.., 0o755)` fixture pattern
/// (conformance-gate-tests §2 item 2).
///
/// Create with [ScriptFixtures.create]; always [dispose] in `tearDown`.
class ScriptFixtures {
  ScriptFixtures._(this.root);

  /// The temp root (`/tmp/...`); on macOS its canonical form is under
  /// `/private/tmp`, which is exactly why the resolver canonicalizes roots.
  final Directory root;

  static ScriptFixtures create() =>
      ScriptFixtures._(Directory.systemTemp.createTempSync('grid_gates_'));

  /// Absolute path for [relative] under [root].
  String path(String relative) => p.join(root.path, relative);

  /// Writes an executable (`0o755`) script at [relative] with [body], creating
  /// parent dirs. Returns the absolute path.
  String writeScript(String relative, String body) {
    final file = File(path(relative))..parent.createSync(recursive: true);
    file.writeAsStringSync(body);
    _chmod755(file.path);
    return file.path;
  }

  /// Writes a non-executable regular file (`0o644`) at [relative].
  String writeFile(String relative, String body) {
    final file = File(path(relative))..parent.createSync(recursive: true);
    file.writeAsStringSync(body);
    return file.path;
  }

  /// Creates a directory at [relative]. Returns its absolute path.
  String mkdir(String relative) {
    final dir = Directory(path(relative))..createSync(recursive: true);
    return dir.path;
  }

  /// Creates a symlink at [linkRelative] pointing at [target] (absolute or
  /// relative-to-link). Returns the link's absolute path.
  String symlink(String linkRelative, String target) {
    final link = Link(path(linkRelative))..parent.createSync(recursive: true);
    link.createSync(target);
    return link.path;
  }

  void dispose() {
    if (root.existsSync()) root.deleteSync(recursive: true);
  }

  static void _chmod755(String path) {
    // dart:io has no chmod; shell out (POSIX-only — the gate suite is too).
    final r = Process.runSync('chmod', <String>['755', path]);
    if (r.exitCode != 0) {
      throw StateError('chmod 755 failed for $path: ${r.stderr}');
    }
  }
}

/// A `#!/bin/sh` script body, joined from [lines].
String shScript(List<String> lines) => '#!/bin/sh\n${lines.join('\n')}\n';
