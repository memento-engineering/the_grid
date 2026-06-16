import 'dart:io';

import 'package:grid_runtime/grid_runtime.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

/// Hermetic tests for the stale-ancestor guard (the gascity#1556 spawn-time
/// guard, `internal/workdir/workdir.go:303-359`). Uses real temp dirs + `.git`
/// pointer files — no `git` binary, no network. Proves the fail-closed cases
/// (stale `gitdir:` target) and the safe cases (real `.git` dir, no marker).
void main() {
  late Directory tmp;

  setUp(() {
    tmp = Directory.systemTemp.createTempSync('grid_stale_');
  });

  tearDown(() {
    if (tmp.existsSync()) tmp.deleteSync(recursive: true);
  });

  test('safe: no .git marker anywhere up the chain', () {
    final target = p.join(tmp.path, 'a', 'b', 'worktree');
    expect(validateAncestorWorktreesNotStale(target), isNull);
  });

  test('safe: ancestor has a real .git DIRECTORY (a main repo root)', () {
    Directory(p.join(tmp.path, 'repo', '.git')).createSync(recursive: true);
    final target = p.join(tmp.path, 'repo', 'sub', 'worktree');
    expect(validateAncestorWorktreesNotStale(target), isNull);
  });

  test('FAIL CLOSED: ancestor .git pointer whose gitdir target is missing', () {
    final repo = Directory(p.join(tmp.path, 'repo'))..createSync();
    File(
      p.join(repo.path, '.git'),
    ).writeAsStringSync('gitdir: /does/not/exist/admin\n');
    final target = p.join(repo.path, 'sub', 'worktree');

    final rejection = validateAncestorWorktreesNotStale(target);
    expect(rejection, isNotNull);
    expect(rejection, contains('stale .git pointer'));
    expect(rejection, contains('does not exist'));
  });

  test('FAIL CLOSED: gitdir target exists but is not a directory', () {
    final repo = Directory(p.join(tmp.path, 'repo'))..createSync();
    // The "admin dir" is actually a regular file → not worktree-capable.
    final adminFile = File(p.join(tmp.path, 'admin-as-file'))
      ..writeAsStringSync('x');
    File(
      p.join(repo.path, '.git'),
    ).writeAsStringSync('gitdir: ${adminFile.path}\n');
    final target = p.join(repo.path, 'sub', 'worktree');

    final rejection = validateAncestorWorktreesNotStale(target);
    expect(rejection, isNotNull);
    expect(rejection, contains('is not a directory'));
  });

  test('safe: gitdir pointer with a VALID directory target', () {
    final repo = Directory(p.join(tmp.path, 'repo'))..createSync();
    final adminDir = Directory(p.join(tmp.path, 'real-admin'))..createSync();
    File(
      p.join(repo.path, '.git'),
    ).writeAsStringSync('gitdir: ${adminDir.path}\n');
    final target = p.join(repo.path, 'sub', 'worktree');

    expect(validateAncestorWorktreesNotStale(target), isNull);
  });

  test('safe (fail OPEN): a .git file with no gitdir: prefix stops the walk', () {
    final repo = Directory(p.join(tmp.path, 'repo'))..createSync();
    File(p.join(repo.path, '.git')).writeAsStringSync('garbage not a pointer');
    final target = p.join(repo.path, 'sub', 'worktree');
    // Unparseable .git file → fail open, stop walking, do not reject.
    expect(validateAncestorWorktreesNotStale(target), isNull);
  });

  test('relative gitdir target resolves against the .git file dir', () {
    final repo = Directory(p.join(tmp.path, 'repo'))..createSync();
    // Relative target ../real-admin, valid dir, resolved against repo/.
    Directory(p.join(tmp.path, 'real-admin')).createSync();
    File(
      p.join(repo.path, '.git'),
    ).writeAsStringSync('gitdir: ../real-admin\n');
    final target = p.join(repo.path, 'sub', 'worktree');
    expect(validateAncestorWorktreesNotStale(target), isNull);

    // And a relative target that does NOT exist fails closed.
    File(
      p.join(repo.path, '.git'),
    ).writeAsStringSync('gitdir: ../missing-admin\n');
    expect(validateAncestorWorktreesNotStale(target), isNotNull);
  });
}
