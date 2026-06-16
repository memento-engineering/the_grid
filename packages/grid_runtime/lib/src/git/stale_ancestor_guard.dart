import 'dart:io';

import 'package:path/path.dart' as p;

/// Result of [validateAncestorWorktreesNotStale] — `null` when the spawn is
/// safe, or a human-legible rejection reason when an ancestor has a stale
/// worktree pointer.
typedef StaleAncestorRejection = String?;

/// Walks [path]'s ancestor chain and returns a rejection reason when any
/// ancestor has a regular-file `.git` worktree pointer whose `gitdir:` target
/// is unusable — the VERBATIM port of gc's `ValidateAncestorWorktreesNotStale`
/// (`gascity/internal/workdir/workdir.go:303-359`). Returns `null` when safe.
///
/// This is the spawn-time guard for gascity#1556: a stale worktree pointer on
/// an ancestor lets `git -C <root> worktree add <child>` register a
/// structurally orphaned child. the_grid's worktrees nest under
/// engineering.memento (itself a git repo), so this hazard is real here. Run it
/// before EVERY `git worktree add` (ADR-0006 Decision 3).
///
/// The walk starts at [path]'s PARENT (the spawn target itself typically does
/// not exist yet — we are about to create it) and stops at the first `.git`
/// marker:
///
///  - **Fail closed** (pointer present and parses, target unusable):
///    - the `gitdir:` target does not exist on disk;
///    - the target exists but is not a directory.
///  - **Fail open** (`.git` present but not a recognizable pointer): unreadable
///    file or missing `gitdir:` prefix — stop the walk; anything further up is
///    the surrounding repository's responsibility, and failing closed there
///    would block legitimate spawns on an unrelated permission-restricted
///    ancestor `.git`.
///  - A real `.git` DIRECTORY (a main repo root) stops the walk: safe.
///  - Reaching the filesystem root without a marker: safe.
///
/// A relative `gitdir:` target is resolved against the directory holding the
/// `.git` file (Git's gitfile format), not the process cwd.
StaleAncestorRejection validateAncestorWorktreesNotStale(String path) {
  var cur = p.dirname(p.normalize(path));
  while (true) {
    final gitPath = p.join(cur, '.git');
    final type = FileSystemEntity.typeSync(gitPath, followLinks: false);

    if (type == FileSystemEntityType.file) {
      String? content;
      try {
        content = File(gitPath).readAsStringSync().trim();
      } on FileSystemException {
        content = null; // unreadable → fail open, stop the walk.
      }
      if (content != null && content.startsWith('gitdir:')) {
        var target = content.substring('gitdir:'.length).trim();
        // Git's gitfile format: a relative target resolves against the dir
        // holding the .git file, not the process cwd.
        if (!p.isAbsolute(target)) {
          target = p.join(cur, target);
        }
        target = p.normalize(target);
        final targetType = FileSystemEntity.typeSync(target, followLinks: true);
        if (targetType == FileSystemEntityType.notFound) {
          return 'worktree spawn rejected: ancestor "$cur" has stale .git '
              'pointer (gitdir target "$target" does not exist)';
        }
        if (targetType != FileSystemEntityType.directory) {
          return 'worktree spawn rejected: ancestor "$cur" has stale .git '
              'pointer (gitdir target "$target" is not a directory)';
        }
      }
      // Either a usable pointer, or an unparseable .git file — stop the walk.
      return null;
    }
    if (type == FileSystemEntityType.directory) {
      // Reached a real .git directory (main repo root). Stop: safe.
      return null;
    }

    final parent = p.dirname(cur);
    if (parent == cur) return null; // filesystem root, no marker: safe.
    cur = parent;
  }
}
