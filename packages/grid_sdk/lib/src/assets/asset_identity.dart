import 'package:genesis_tree/genesis_tree.dart';
import 'package:meta/meta.dart';

/// What an asset IS — the closed kind vocabulary a pack declares against.
///
/// Closed because every consumer above this package `switch`es exhaustively
/// over it (ADR-0001 Decision 1); a new kind is a deliberate contract change,
/// never an unrecognised string.
enum AssetKind {
  /// Reference material a human or an agent reads (docs, checklists).
  resource,

  /// A parameterised instruction body (the Packaged AI Assets prompt).
  prompt,

  /// A named, invocable procedure (a `SKILL.md` and the directory beside it).
  skill,

  /// An agent definition — a seat's persona, tool surface, and model target.
  agent,

  /// A grading rubric a critic reads.
  rubric,

  /// A harness lifecycle hook declaration.
  hook,

  /// Harness settings a pack contributes (permissions, env allow-lists).
  settings,
}

/// WHERE one leg of an asset is delivered — the closed delivery vocabulary.
///
/// Delivery legs are authored INDEPENDENTLY: the [claude] and [agents] legs of
/// one logical skill are two [AssetArtifactKey]s under one [AssetKey], and
/// neither their paths nor their argument declarations need agree.
enum AssetDeliveryTarget {
  /// Claude Code's on-disk layout (`.claude/…`).
  claude,

  /// The harness-neutral agents layout (`AGENTS.md` / `.agents/…`).
  agents,

  /// The `package:extension_discovery` surface (`extension/mcp/config.yaml`)
  /// — the Packaged AI Assets format ADR-0008 Decision 2 adopts.
  mcp,

  /// The grid's own tree: a station reads it directly, never materialising it
  /// into a repository.
  station,
}

/// One logical asset's identity — the vending [package], its [kind], and the
/// pack-unique [id].
///
/// Extends the tree's [Key] so ONE value is both the logical identity and the
/// reconciliation identity of the `GridAssetDefinition` it names. genesis
/// blesses exactly this ("domains/consumers … define their own `Key` subtypes
/// by extending it and supplying `==`/`hashCode`"), and it is what keeps the
/// definition `const`: a key DERIVED in an initializer could not be.
final class AssetKey extends Key {
  /// Identifies the asset [id] of [kind] vended by [package].
  const AssetKey({required this.package, required this.kind, required this.id})
    : super.empty();

  /// The vending Dart package — the pack carrying the top-level `grid:` block
  /// (decision `the_grid#grid-block-packages-publish-dart-asset-definitions`).
  final String package;

  /// What the asset is.
  final AssetKind kind;

  /// The asset's id, unique within [package] and [kind].
  final String id;

  /// The stable rendering — `<package>/<kind>/<id>`.
  String get canonical => '$package/${kind.name}/$id';

  @override
  bool operator ==(Object other) =>
      other is AssetKey &&
      other.runtimeType == runtimeType &&
      other.package == package &&
      other.kind == kind &&
      other.id == id;

  @override
  int get hashCode => Object.hash(runtimeType, package, kind, id);

  @override
  String toString() => 'AssetKey($canonical)';
}

/// One delivery leg's identity — the logical [asset] plus its [target].
///
/// Held, never inferred (ADR-0013 Decision 2: "the distinguishing identity
/// rides in the type"): the leg is a field, not something reconstructed from a
/// path's shape.
@immutable
final class AssetArtifactKey {
  /// Identifies the [target] leg of [asset].
  const AssetArtifactKey({required this.asset, required this.target});

  /// The logical asset this leg delivers.
  final AssetKey asset;

  /// Which leg this is.
  final AssetDeliveryTarget target;

  /// The stable rendering — `<asset>@<target>`.
  String get canonical => '${asset.canonical}@${target.name}';

  @override
  bool operator ==(Object other) =>
      other is AssetArtifactKey &&
      other.runtimeType == runtimeType &&
      other.asset == asset &&
      other.target == target;

  @override
  int get hashCode => Object.hash(runtimeType, asset, target);

  @override
  String toString() => 'AssetArtifactKey($canonical)';
}
