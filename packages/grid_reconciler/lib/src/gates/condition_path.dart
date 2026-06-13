import 'dart:io';

import 'package:path/path.dart' as p;

/// Thrown by [resolveConditionPath] when a gate condition path is empty,
/// escapes containment, doesn't exist, or isn't an executable regular file.
///
/// The [message] mirrors gc's wrapped error text (condition.go:191-260) so the
/// reconciler's error surface and any conformance diffing stay legible; callers
/// classify the failure by [kind], not by string-matching.
class ConditionPathException implements Exception {
  const ConditionPathException(this.kind, this.message);

  final ConditionPathError kind;
  final String message;

  @override
  String toString() => 'ConditionPathException: $message';
}

/// The closed set of `ResolveConditionPath` rejection reasons
/// (condition.go:191-260), so the runner can branch without parsing messages.
enum ConditionPathError {
  /// `conditionPath == ''` (condition.go:192-194).
  emptyPath,

  /// `envelope == ''` — an empty envelope would silently disable the traversal
  /// check, so it is rejected (condition.go:195-197).
  emptyEnvelope,

  /// Lexical-join traversal escapes envelope AND base (condition.go:226-230).
  traversal,

  /// Symlink target escapes containment after resolution (condition.go:244-248).
  symlinkEscape,

  /// `EvalSymlinks`/stat failed — typically the file doesn't exist
  /// (condition.go:234-237, 251-253).
  resolveFailure,

  /// Resolved path is not a regular file (condition.go:255-256).
  notRegularFile,

  /// Resolved path has no exec bit (condition.go:258-259).
  notExecutable,
}

/// Resolves and validates a gate condition path with gc's traversal/symlink
/// containment defenses, **in the exact order** of `ResolveConditionPath`
/// (condition.go:191-263). SECURITY-CRITICAL — the steps and the relative-only
/// rule are load-bearing (gates-exec.md §2).
///
/// * [envelope] — the security boundary (the city path). Must be non-empty.
/// * [base] — the join base for relative paths AND a second permitted boundary
///   (sibling rig/city layouts, gascity#2354). Empty ⇒ falls back to
///   [envelope].
/// * [conditionPath] — absolute or relative-to-[base].
///
/// Returns the **symlink-resolved** canonical absolute path. Absolute
/// [conditionPath]s skip BOTH containment checks by design (imported/registry
/// packs live outside the city; callers vouch for absolute paths). A
/// metadata-sourced (ralph-style) caller does NOT blindly vouch — it must wrap
/// this with the trusted-absolute-roots guard via [resolveTrustedConditionPath]
/// (ralph.go:189-203). Throws [ConditionPathException] on any rejection.
String resolveConditionPath(
  String envelope,
  String base,
  String conditionPath,
) {
  if (conditionPath.isEmpty) {
    throw const ConditionPathException(
      ConditionPathError.emptyPath,
      'resolving gate condition path: empty path',
    );
  }
  if (envelope.isEmpty) {
    throw const ConditionPathException(
      ConditionPathError.emptyEnvelope,
      'resolving gate condition path: empty envelope',
    );
  }
  var effectiveBase = base;
  if (effectiveBase.isEmpty) {
    effectiveBase = envelope; // historical single-arg behavior.
  }

  // Canonicalize both roots first so symlinked workspace roots (macOS
  // /tmp → /private/tmp) don't cause false rejections, falling back to a
  // lexical clean when the root doesn't exist yet (condition.go:206-213).
  final canonEnvelope = _evalSymlinksOrClean(envelope);
  final canonBase = _evalSymlinksOrClean(effectiveBase);

  final isAbs = p.isAbsolute(conditionPath);
  final String absPath;
  if (isAbs) {
    absPath = p.normalize(conditionPath);
  } else {
    absPath = p.normalize(p.join(canonBase, conditionPath));
  }

  // Pre-resolution containment (relative paths only): the lexical join must
  // stay under envelope OR base; rejects ../../foo before any FS access.
  // Absolute paths skip — callers vouch for them (condition.go:226-230).
  if (!isAbs) {
    if (!_containedIn(absPath, canonEnvelope) &&
        !_containedIn(absPath, canonBase)) {
      throw ConditionPathException(
        ConditionPathError.traversal,
        'resolving gate condition path: path traversal not allowed: '
        '$conditionPath',
      );
    }
  }

  // Resolve symlinks to the real path (condition.go:234-237).
  final String resolved;
  try {
    resolved = _evalSymlinks(absPath);
  } on FileSystemException catch (e) {
    throw ConditionPathException(
      ConditionPathError.resolveFailure,
      'resolving gate condition path: ${e.message}',
    );
  }

  // Post-resolution containment (relative paths only): a symlink under
  // envelope/base can point outside both trees; re-validate the resolved
  // target (condition.go:244-248). Absolute paths still skip.
  if (!isAbs) {
    if (!_containedIn(resolved, canonEnvelope) &&
        !_containedIn(resolved, canonBase)) {
      throw ConditionPathException(
        ConditionPathError.symlinkEscape,
        'resolving gate condition path: symlink target outside containment: '
        '$conditionPath',
      );
    }
  }

  // Stat: must exist, be a regular file, and carry an exec bit
  // (condition.go:251-260).
  final stat = FileStat.statSync(resolved);
  if (stat.type == FileSystemEntityType.notFound) {
    throw ConditionPathException(
      ConditionPathError.resolveFailure,
      'resolving gate condition path: no such file or directory: $resolved',
    );
  }
  if (stat.type != FileSystemEntityType.file) {
    throw ConditionPathException(
      ConditionPathError.notRegularFile,
      'resolving gate condition path: not a regular file: $resolved',
    );
  }
  if (stat.mode & 0x49 == 0) {
    // 0x49 == 0o111 (owner/group/other exec bits).
    throw ConditionPathException(
      ConditionPathError.notExecutable,
      'resolving gate condition path: file is not executable: $resolved',
    );
  }

  return resolved;
}

/// Thrown by [resolveTrustedConditionPath] when an **absolute** condition path
/// escapes the trusted-absolute-roots boundary that gc's only production caller
/// (the ralph exec check) enforces around `ResolveConditionPath`
/// (ralph.go:189-203). [resolveConditionPath] itself deliberately skips
/// containment for absolute paths (callers vouch for them); this is the
/// caller-side guard that a less-trusted, metadata-sourced caller MUST apply.
class TrustedRootsException implements Exception {
  const TrustedRootsException(this.message, {required this.resolved});

  /// gc-style error text (ralph.go:191,201). Pre-resolution rejections quote
  /// the raw `gc.check_path`; post-resolution rejections quote the resolved
  /// script path.
  final String message;

  /// `false` for the pre-resolution check (raw absolute checkPath), `true` for
  /// the post-resolution check (the symlink-resolved script path) — the latter
  /// closes the absolute-symlink-escape hole.
  final bool resolved;

  @override
  String toString() => 'TrustedRootsException: $message';
}

/// Resolves a **metadata-sourced** (ralph-style, e.g. `gc.check_path`) gate
/// condition path with gc's full caller-side defense, porting the ralph exec
/// path's sandwich around [resolveConditionPath] (ralph.go:189-203):
///
/// 1. If [conditionPath] is absolute and not within any [trustedAbsRoots],
///    reject BEFORE resolution (ralph.go:190-192).
/// 2. [resolveConditionPath] (handles relative containment + symlink resolution
///    + exec-file checks).
/// 3. If [conditionPath] is absolute and the **resolved** script path is not
///    within any [trustedAbsRoots], reject AFTER resolution
///    (ralph.go:200-202) — this closes the absolute-symlink-escape hole where
///    an in-root absolute symlink points outside every trusted root.
///
/// Relative paths flow straight through [resolveConditionPath]'s envelope/base
/// containment (the absolute-roots checks are no-ops for them, matching gc's
/// `if filepath.IsAbs(...)` guards). Build [trustedAbsRoots] with
/// [ralphCheckTrustedAbsoluteRoots]. Operator-created gate conditions (the
/// convergence handler path) are exec'd verbatim and must NOT route through
/// here (gates-exec.md §2 "Where gc actually applies ResolveConditionPath").
///
/// Throws [TrustedRootsException] on an absolute escape, or
/// [ConditionPathException] for any [resolveConditionPath] rejection.
String resolveTrustedConditionPath(
  String envelope,
  String base,
  String conditionPath,
  List<String> trustedAbsRoots,
) {
  final isAbs = p.isAbsolute(conditionPath);
  if (isAbs && !pathWithinAny(conditionPath, trustedAbsRoots)) {
    throw TrustedRootsException(
      'absolute gc.check_path escapes trusted roots: $conditionPath',
      resolved: false,
    );
  }
  final scriptPath = resolveConditionPath(envelope, base, conditionPath);
  if (isAbs && !pathWithinAny(scriptPath, trustedAbsRoots)) {
    throw TrustedRootsException(
      'resolved gc.check_path escapes trusted roots: $scriptPath',
      resolved: true,
    );
  }
  return scriptPath;
}

/// Port of gc's `ralphCheckTrustedAbsoluteRoots` (ralph.go:252-282): the
/// ordered, **deduplicated** (by [samePath]) set of roots an absolute
/// `gc.check_path` is permitted to live under — `cityPath`, then `storePath`,
/// then each [formulaSearchPaths] entry, plus the parent of any entry whose
/// basename is `formulas` (pack-authored checks beside a formula layer).
/// Empty/blank entries are skipped. Each root is normalized via
/// [normalizePathForCompare] for stable comparison, mirroring gc's `add`.
List<String> ralphCheckTrustedAbsoluteRoots(
  String cityPath,
  String storePath,
  List<String> formulaSearchPaths,
) {
  final roots = <String>[];
  void add(String root) {
    final trimmed = root.trim();
    if (trimmed.isEmpty) return;
    final normalized = normalizePathForCompare(trimmed);
    for (final existing in roots) {
      if (samePath(existing, normalized)) return;
    }
    roots.add(normalized);
  }

  add(cityPath);
  add(storePath);
  for (final formulaPath in formulaSearchPaths) {
    final trimmed = formulaPath.trim();
    if (trimmed.isEmpty) continue;
    final clean = p.normalize(trimmed);
    add(clean);
    if (p.basename(clean) == 'formulas') {
      add(p.dirname(clean));
    }
  }
  return roots;
}

/// Port of gc's `pathWithinAny` (ralph.go:285-292): true iff [path] is within
/// any of [roots] under [pathWithin].
bool pathWithinAny(String path, List<String> roots) {
  for (final root in roots) {
    if (pathWithin(root, path)) return true;
  }
  return false;
}

/// Port of `pathutil.PathWithin` (pathutil.go:83-97): true iff [candidate] is
/// the same path as [root] or lexically contained beneath it, **after**
/// [normalizePathForCompare] (abs + clean + symlink resolution + macOS alias
/// collapse) on both sides. Empty after normalization → false.
bool pathWithin(String root, String candidate) {
  final normRoot = normalizePathForCompare(root);
  final normCandidate = normalizePathForCompare(candidate);
  if (normRoot.isEmpty || normCandidate.isEmpty) return false;
  if (normRoot == normCandidate) return true;
  final String rel;
  try {
    rel = p.relative(normCandidate, from: normRoot);
  } on Object {
    return false;
  }
  return !_isOutsideDir(rel);
}

/// Port of `pathutil.SamePath` (pathutil.go:70-72): equality after
/// [normalizePathForCompare].
bool samePath(String a, String b) =>
    normalizePathForCompare(a) == normalizePathForCompare(b);

/// Port of `pathutil.NormalizePathForCompare` (pathutil.go:12-25): make
/// absolute, lexically clean, resolve symlinks (with a missing-suffix fallback
/// so not-yet-existing paths still normalize), then collapse the macOS
/// `/private/{tmp,var}` host aliases so equality stays stable across APIs
/// (pathutil.go:44-66). Empty in → empty out.
String normalizePathForCompare(String path) {
  if (path.isEmpty) return '';
  final cleaned = p.normalize(p.absolute(path));
  String resolved;
  try {
    resolved = _evalSymlinks(cleaned);
  } on FileSystemException {
    resolved = _normalizeMissingPath(cleaned) ?? cleaned;
  }
  return _canonicalizePlatformPathAlias(resolved);
}

/// Port of `pathutil.normalizeMissingPath` (pathutil.go:27-42): resolve the
/// deepest existing ancestor's symlinks, then re-append the missing tail.
/// Returns null when no ancestor resolves.
String? _normalizeMissingPath(String path) {
  final missing = <String>[];
  var current = path;
  while (true) {
    try {
      var resolved = _evalSymlinks(current);
      for (var i = missing.length - 1; i >= 0; i--) {
        resolved = p.join(resolved, missing[i]);
      }
      return resolved;
    } on FileSystemException {
      // fall through to walk up
    }
    final parent = p.dirname(current);
    if (parent == current) return null;
    missing.add(p.basename(current));
    current = parent;
  }
}

/// Port of `pathutil.canonicalizePlatformPathAlias` (pathutil.go:44-66): on
/// macOS, collapse `/private/tmp` and `/private/var` (and their subtrees) back
/// to `/tmp` and `/var` so EvalSymlinks output compares equal to caller-facing
/// paths. No-op off darwin.
String _canonicalizePlatformPathAlias(String path) {
  final clean = p.normalize(path);
  if (!Platform.isMacOS) return clean;
  if (clean == '/private/tmp') return '/tmp';
  if (clean.startsWith('/private/tmp/')) {
    return '/tmp/${clean.substring('/private/tmp/'.length)}';
  }
  if (clean == '/private/var') return '/var';
  if (clean.startsWith('/private/var/')) {
    return '/var/${clean.substring('/private/var/'.length)}';
  }
  return clean;
}

/// Port of gc's `containedIn` (condition.go:156-162): lexical containment —
/// `rel = Rel(root, absPath)`; on error → false; contained iff
/// `!isOutsideDir(rel)`. Same-dir (`rel == '.'`) counts as contained.
bool _containedIn(String absPath, String root) {
  final String rel;
  try {
    rel = p.relative(absPath, from: root);
  } on Object {
    return false;
  }
  return !_isOutsideDir(rel);
}

/// Port of `pathutil.IsOutsideDir` (pathutil.go:77-79): the relative path
/// escapes its base iff it equals `..` or begins with `../`.
bool _isOutsideDir(String rel) =>
    rel == '..' || (rel.length > 2 && rel.startsWith('..${p.separator}'));

/// Go `filepath.EvalSymlinks` with the gc fallback (condition.go:206-213): on
/// error, return a lexically cleaned absolute path so a not-yet-existing root
/// still produces a stable comparison base.
String _evalSymlinksOrClean(String path) {
  try {
    return _evalSymlinks(path);
  } on FileSystemException {
    return p.normalize(p.absolute(path));
  }
}

/// Go `filepath.EvalSymlinks`: fully resolve every symlink component to a
/// canonical absolute path. Throws [FileSystemException] when a component
/// doesn't exist.
String _evalSymlinks(String path) {
  final absolute = p.normalize(p.absolute(path));
  // resolveSymbolicLinksSync resolves the whole chain and canonicalizes; it
  // throws if any component is missing (matching EvalSymlinks' error contract).
  final resolved = FileSystemEntity.isLinkSync(absolute) || _exists(absolute)
      ? File(absolute).resolveSymbolicLinksSync()
      : Directory(absolute).resolveSymbolicLinksSync();
  return resolved;
}

bool _exists(String path) =>
    FileSystemEntity.typeSync(path, followLinks: false) !=
    FileSystemEntityType.notFound;
