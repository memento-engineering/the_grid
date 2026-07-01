/// Pub dev-time linkage — the DART domain's first payload (the
/// `SCRATCH-pub-capability-and-repo-split` design; typed CONFIGURATION, not
/// tools).
///
/// A work bead may declare "the desire to dev-time link" this work's checkout
/// to sibling package sources (e.g. `genesis_tree` → the local genesis
/// checkout). The substation already defines its location and the bead its own
/// worktree — those are projections; this config carries ONLY the linkage
/// intent, as data. Applying it is a PURE function: context → the
/// `pubspec_overrides.yaml` content (pub honors that file from the workspace
/// root at any checkout depth; melos 7 no longer owns it).
///
/// The contexts: [PubLinkContext.dev] (the root checkout — paths apply as
/// declared), [PubLinkContext.worktree] (a deep per-bead worktree at
/// `.grid/worktrees/<sub>/<bead>` — relative `../` paths break there, so
/// declared paths are ABSOLUTIZED against the station's dev root, fail-closed
/// when they can't be), and [PubLinkContext.stable] (no overrides — the
/// pubspec's own hosted/git refs stand).
///
/// Hand-written immutable value types + JSON (the grid_assets payload style —
/// `DispatchCommand`/`LaunchSpec`; dependency-light, no codegen).
library;

import 'package:meta/meta.dart';
import 'package:path/path.dart' as p;

/// Which resolution situation the linkage is being applied for.
enum PubLinkContext {
  /// The root checkout (local dev): declared paths apply as-is.
  dev,

  /// A deep per-bead worktree: declared paths are absolutized against the
  /// station's dev root (relative `../` paths do not resolve from
  /// `.grid/worktrees/<sub>/<bead>`).
  worktree,

  /// Stable: no overrides — the pubspec's hosted/git refs stand.
  stable;

  /// Parses a wire/flag [value]; null for an unknown one (fail-closed — the
  /// caller refuses rather than guessing a context).
  static PubLinkContext? parse(String? value) => switch (value) {
    'dev' => PubLinkContext.dev,
    'worktree' => PubLinkContext.worktree,
    'stable' => PubLinkContext.stable,
    _ => null,
  };
}

/// One package's declared linkage: the dev-time [devPath] source (the override
/// applied in dev/worktree contexts) and the informational stable pins
/// ([hosted] / [gitUrl]+[gitRef]) that stand when no override is applied.
@immutable
class PubLink {
  /// Creates the linkage declaration for [package].
  const PubLink({
    required this.package,
    this.devPath,
    this.hosted,
    this.gitUrl,
    this.gitRef,
  });

  /// The pub package name (e.g. `genesis_tree`).
  final String package;

  /// The dev-time path source — absolute, or relative to the station's dev
  /// root. Null ⇒ this link declares no dev-time override (stable pins stand).
  final String? devPath;

  /// The stable hosted constraint (informational — it lives in the pubspec
  /// proper; recorded here so the intent is complete/auditable).
  final String? hosted;

  /// The stable git url (reserved — a git-ref stable pin; not applied as an
  /// override in this prototype).
  final String? gitUrl;

  /// The stable git ref (reserved, with [gitUrl]).
  final String? gitRef;

  /// JSON form (the envelope payload wire).
  Map<String, Object?> toJson() => {
    'package': package,
    if (devPath != null) 'dev_path': devPath,
    if (hosted != null) 'hosted': hosted,
    if (gitUrl != null) 'git_url': gitUrl,
    if (gitRef != null) 'git_ref': gitRef,
  };

  /// The valid pub package-name shape (identifier chars only). Enforced at
  /// decode so a YAML-dangerous "name" (colons, spaces, hashes) can never reach
  /// the overrides emitter — the envelope is malformed instead (fail-closed).
  static final RegExp _validPackage = RegExp(r'^[A-Za-z_][A-Za-z0-9_]*$');

  /// Parses [json]; throws [FormatException] on a missing/invalid package name
  /// (the envelope decoder maps that to a malformed result — fail-closed).
  static PubLink fromJson(Map<String, Object?> json) {
    final package = json['package'];
    if (package is! String || !_validPackage.hasMatch(package)) {
      throw const FormatException(
        'PubLink requires a valid pub package name '
        '(identifier characters only)',
      );
    }
    return PubLink(
      package: package,
      devPath: json['dev_path'] as String?,
      hosted: json['hosted'] as String?,
      gitUrl: json['git_url'] as String?,
      gitRef: json['git_ref'] as String?,
    );
  }

  @override
  bool operator ==(Object other) =>
      other is PubLink &&
      other.package == package &&
      other.devPath == devPath &&
      other.hosted == hosted &&
      other.gitUrl == gitUrl &&
      other.gitRef == gitRef;

  @override
  int get hashCode => Object.hash(package, devPath, hosted, gitUrl, gitRef);
}

/// The `pub` slice of the DART domain payload: the declared [links].
@immutable
class PubLinkConfig {
  /// Creates the pub linkage config.
  const PubLinkConfig({this.links = const []});

  /// The declared per-package links.
  final List<PubLink> links;

  /// Whether any link declares a dev-time path (i.e. applying in a dev/worktree
  /// context would emit overrides).
  bool get hasDevLinks => links.any((l) => l.devPath != null);

  /// JSON form.
  Map<String, Object?> toJson() => {
    'links': [for (final l in links) l.toJson()],
  };

  /// Parses [json] (a missing/empty `links` is a valid empty config). A
  /// non-list `links` or a non-object entry throws [FormatException] —
  /// explicit, so the fail-closed path never rides an implicit cast error.
  static PubLinkConfig fromJson(Map<String, Object?> json) {
    final raw = json['links'];
    if (raw == null) return const PubLinkConfig();
    if (raw is! List) {
      throw const FormatException('"links" must be a list');
    }
    return PubLinkConfig(
      links: [
        for (final entry in raw)
          if (entry is Map)
            PubLink.fromJson(entry.cast<String, Object?>())
          else
            throw const FormatException('"links" entries must be objects'),
      ],
    );
  }

  @override
  bool operator ==(Object other) =>
      other is PubLinkConfig &&
      other.links.length == links.length &&
      () {
        for (var i = 0; i < links.length; i++) {
          if (other.links[i] != links[i]) return false;
        }
        return true;
      }();

  @override
  int get hashCode => Object.hashAll(links);
}

/// Derives the `pubspec_overrides.yaml` CONTENT for [config] under [context] —
/// the pure heart of the domain (no I/O; deterministic: links sorted by
/// package).
///
/// - [PubLinkContext.stable] → null (no overrides file — the caller removes an
///   existing one; the pubspec's own pins stand).
/// - [PubLinkContext.dev] → path overrides exactly as declared (a relative
///   path resolves naturally from the root checkout).
/// - [PubLinkContext.worktree] → path overrides ABSOLUTIZED: an absolute
///   declaration passes through; a relative one is resolved against [devRoot]
///   (normalized). A relative declaration with NO [devRoot] — or a [devRoot]
///   that is itself relative (which would silently yield a still-relative,
///   broken override) — throws [StateError]: fail-closed, never a silently
///   broken override.
///
/// Paths are emitted as single-quoted YAML scalars (embedded quotes doubled),
/// so a path carrying YAML-hostile characters (`: `, ` #`, leading/trailing
/// spaces) can never corrupt the file. Package names are identifier-validated
/// at decode, so they need no quoting.
///
/// Links with no [PubLink.devPath] contribute nothing. No dev links at all →
/// null (nothing to override).
String? pubspecOverridesFor(
  PubLinkConfig config,
  PubLinkContext context, {
  String? devRoot,
}) {
  if (context == PubLinkContext.stable) return null;
  final dev = config.links.where((l) => l.devPath != null).toList()
    ..sort((a, b) => a.package.compareTo(b.package));
  if (dev.isEmpty) return null;

  final buffer = StringBuffer()
    ..writeln(
      '# Generated by the grid.dart domain (context: ${context.name}). '
      'Do not hand-edit.',
    )
    ..writeln('dependency_overrides:');
  for (final link in dev) {
    final declared = link.devPath!;
    final String path;
    if (context == PubLinkContext.worktree && !p.isAbsolute(declared)) {
      if (devRoot == null) {
        throw StateError(
          'PubLink "${link.package}" declares the relative dev path '
          '"$declared", which cannot resolve from a deep worktree without a '
          'devRoot to absolutize against (fail-closed — a broken override is '
          'worse than none).',
        );
      }
      if (!p.isAbsolute(devRoot)) {
        throw StateError(
          'devRoot "$devRoot" is relative — absolutizing '
          '"${link.package}: $declared" against it would yield a still-'
          'relative (broken) override (fail-closed).',
        );
      }
      path = p.normalize(p.join(devRoot, declared));
    } else {
      path = declared;
    }
    buffer
      ..writeln('  ${link.package}:')
      ..writeln('    path: ${_yamlQuote(path)}');
  }
  return buffer.toString();
}

/// A single-quoted YAML scalar: content survives any YAML-hostile character
/// (embedded single quotes are doubled per the YAML spec).
String _yamlQuote(String value) => "'${value.replaceAll("'", "''")}'";
