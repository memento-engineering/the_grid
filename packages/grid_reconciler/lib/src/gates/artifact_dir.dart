import 'dart:io';

import 'package:path/path.dart' as p;

/// Port of `ArtifactDirFor` (template.go:23-25): the per-iteration artifact dir
/// that becomes `GC_ARTIFACT_DIR` — `<cityPath>/.gc/artifacts/<beadID>/iter-<N>`
/// (handler.go:751, gates-exec.md §1b #21).
///
/// gc only **computes** this path on the live gate path (it may not exist yet —
/// the "sling-time contract", condition.go:66); the runner emits it as an env
/// var without creating it.
String artifactDirFor(String cityPath, String beadId, int iteration) =>
    p.join(cityPath, '.gc', 'artifacts', beadId, 'iter-$iteration');

/// Port of `EnsureArtifactDir` (artifact.go:14-20): `MkdirAll(dir, 0o755)`,
/// returns the path. NOT called from the live convergence gate path (gc only
/// computes the path there); ported because `artifact_test.go` specs it
/// (gates-exec.md §10).
String ensureArtifactDir(String cityPath, String beadId, int iteration) {
  final dir = artifactDirFor(cityPath, beadId, iteration);
  Directory(dir).createSync(recursive: true);
  return dir;
}

/// Thrown by [validateArtifactDir] when the artifact tree contains a symlink
/// escaping the root or a non-regular/non-directory entry (FIFO, device,
/// socket). Mirrors gc's `ValidateArtifactDir` errors (artifact.go:28-69).
class ArtifactDirException implements Exception {
  const ArtifactDirException(this.message);
  final String message;
  @override
  String toString() => 'ArtifactDirException: $message';
}

/// Port of `ValidateArtifactDir` (artifact.go:28-69) — the safety walk before
/// gate execution:
///
/// 1. Canonicalize the root via abs + EvalSymlinks (errors wrapped as
///    `resolving artifact directory`).
/// 2. Walk every entry:
///    * **symlink** → EvalSymlinks (multi-hop); if it resolves outside the root
///      → error `symlink %q points outside artifact directory`.
///    * **regular file / directory** → allowed.
///    * **anything else** (FIFO, device, socket) → error
///      `unsafe file type in artifact directory`.
///
/// NOT wired into the live gate path (gates-exec.md §10) — ported because
/// `artifact_test.go` specs it.
void validateArtifactDir(String dir) {
  final String absDir;
  try {
    absDir = File(p.normalize(p.absolute(dir))).resolveSymbolicLinksSync();
  } on FileSystemException catch (e) {
    throw ArtifactDirException('resolving artifact directory: ${e.message}');
  }

  for (final entity in Directory(absDir).listSync(recursive: true)) {
    final type = FileSystemEntity.typeSync(entity.path, followLinks: false);
    if (type == FileSystemEntityType.link) {
      final String resolved;
      try {
        resolved = entity.resolveSymbolicLinksSync();
      } on FileSystemException catch (e) {
        throw ArtifactDirException(
          'resolving symlink "${entity.path}": ${e.message}',
        );
      }
      final rel = p.relative(resolved, from: absDir);
      if (_isOutsideDir(rel)) {
        throw ArtifactDirException(
          'symlink "${entity.path}" points outside artifact directory: '
          'resolves to "$resolved"',
        );
      }
      continue;
    }
    if (type == FileSystemEntityType.file ||
        type == FileSystemEntityType.directory) {
      continue;
    }
    throw ArtifactDirException(
      'unsafe file type in artifact directory: "${entity.path}" ($type)',
    );
  }
}

/// `pathutil.IsOutsideDir` (pathutil.go:77-79) — duplicated here so artifact
/// validation matches the same containment rule as the condition-path resolver
/// without a cross-import for one predicate.
bool _isOutsideDir(String rel) =>
    rel == '..' || (rel.length > 2 && rel.startsWith('..${p.separator}'));
