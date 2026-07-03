import 'dart:io';

import 'package:beads_dart/src/services/beads_workspace.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

/// A hermetic beads workspace created by `bd init` in a fresh temp directory
/// (embedded/direct mode — no server, no credentials). Everything the
/// integration suite mutates lives here and is deleted in [dispose].
///
/// **Never points at the live tg server.** `bd init` produces an embedded Dolt
/// store under `<root>/.beads/embeddeddolt/`, so the [BeadsWorkspace] resolves
/// to [DoltMode.direct] with a null endpoint and the controller falls to the
/// CLI read path (ADR-0001 Decision 4).
class HermeticWorkspace {
  HermeticWorkspace._(this.root, this.workspace);

  /// The workspace root (the temp directory containing `.beads/`).
  final Directory root;

  /// The discovered, parsed workspace — direct mode, null endpoint.
  final BeadsWorkspace workspace;

  String get rootPath => root.path;
  String get beadsDir => workspace.beadsDir;
  String get hooksDir => p.join(beadsDir, 'hooks');

  /// `bd init`s a fresh temp workspace and parses it. Asserts the result is the
  /// hermetic embedded mode (a guard against accidentally adopting an inherited
  /// server config from the environment).
  static Future<HermeticWorkspace> create({String? prefix}) async {
    final root = await Directory.systemTemp.createTemp(prefix ?? 'grid_it_');
    // Resolve symlinks so the path the watcher/bd see matches what we compare
    // against (macOS /tmp is a symlink to /private/tmp).
    final resolved = Directory(root.resolveSymbolicLinksSync());

    final init = await Process.run(
      'bd',
      ['init'],
      workingDirectory: resolved.path,
      environment: {...Platform.environment, 'BD_JSON_ENVELOPE': '1'},
      includeParentEnvironment: false,
      runInShell: false,
    );
    if (init.exitCode != 0) {
      await resolved.delete(recursive: true);
      fail('bd init failed (${init.exitCode}): ${init.stderr}\n${init.stdout}');
    }

    final workspace = BeadsWorkspace.discover(start: resolved.path);
    if (workspace == null) {
      await resolved.delete(recursive: true);
      fail(
        'bd init produced no discoverable .beads workspace at '
        '${resolved.path}',
      );
    }
    // Hermetic guard: embedded init must NOT resolve a server endpoint, or we
    // could be writing into the real tg database.
    if (workspace.mode == DoltMode.server || workspace.endpoint != null) {
      await resolved.delete(recursive: true);
      fail(
        'hermetic workspace unexpectedly resolved a server endpoint '
        '(mode=${workspace.mode}, endpoint=${workspace.endpoint}) — refusing '
        'to run against a live server',
      );
    }

    return HermeticWorkspace._(resolved, workspace);
  }

  /// Deletes the temp workspace. Safe to call in `tearDown`.
  Future<void> dispose() async {
    if (root.existsSync()) {
      await root.delete(recursive: true);
    }
  }
}
