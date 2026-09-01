/// A structural guard on the SOURCE ITSELF: no Dart file under any package's
/// `lib/` may carry a raw NUL byte (r12; widened to the WORKSPACE in r13).
///
/// This is not style. A literal U+0000 in a source file makes `file` classify
/// the whole file as binary `data`, and it makes plain `grep` return NOTHING
/// for that file — silently. Several guards in this very directory work by
/// reading and grepping sources; a NUL blinds them, and it blinds every
/// review and sweep besides. The escape (backslash-u-0000) has the identical string
/// value and none of the consequences, so the only cost of this rule is
/// remembering it — which is what this test is for.
///
/// THE SCOPE IS THE WORKSPACE, deliberately (r13). The hazard is not
/// package-local — a NUL anywhere blinds the same greps and the same sweeps —
/// and the first cut of this guard scanned only its own `lib/` while a live
/// offender sat in `grid_runtime`. If no workspace root can be located (a
/// vendored or single-package checkout) it falls back to this package's own
/// `lib/` rather than passing vacuously.
library;

import 'dart:io';

import 'package:test/test.dart';

/// The nearest ancestor holding a `packages/` directory — the pub workspace
/// root. Null when there is none.
Directory? _workspaceRoot() {
  var dir = Directory.current.absolute;
  for (var depth = 0; depth < 8; depth += 1) {
    if (Directory('${dir.path}/packages').existsSync()) return dir;
    final parent = dir.parent;
    if (parent.path == dir.path) return null;
    dir = parent;
  }
  return null;
}

List<Directory> _libRoots() {
  final root = _workspaceRoot();
  if (root == null) return [Directory('lib')];
  return [
    for (final entity in Directory('${root.path}/packages').listSync())
      if (entity is Directory && Directory('${entity.path}/lib').existsSync())
        Directory('${entity.path}/lib'),
  ];
}

void main() {
  test('no lib/ source in the WORKSPACE carries a raw NUL byte — the escape, '
      'always', () {
    final roots = _libRoots();
    expect(roots, isNotEmpty, reason: 'the guard must scan something');
    final offenders = <String>[];
    for (final root in roots) {
      for (final entity in root.listSync(recursive: true)) {
        if (entity is! File || !entity.path.endsWith('.dart')) continue;
        if (entity.readAsBytesSync().contains(0)) offenders.add(entity.path);
      }
    }
    expect(
      offenders,
      isEmpty,
      reason:
          'a literal U+0000 makes `grep` silently skip the file and every '
          'source-reading guard in this suite blind to it — write \\u0000',
    );
  });
}
