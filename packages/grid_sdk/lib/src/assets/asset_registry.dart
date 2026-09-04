import 'asset_declaration.dart';
import 'asset_identity.dart';

/// One package's asset collection — the Dart half of a pack that carries a
/// top-level `grid:` block and therefore publishes generated definitions
/// (decision `the_grid#grid-block-packages-publish-dart-asset-definitions`,
/// which updates ADR-0008 Decision 2's clause blessing "AI-only packages with
/// no Dart code").
///
/// Deeply immutable and VALIDATED at construction: a duplicate [AssetKey], a
/// duplicate [AssetArtifactKey] within one asset, or an asset vended by a
/// foreign package refuses LOUD before any field is exposed (guards LOUD or
/// GONE — ADR-0008 Decision 6). A duplicate scan cannot run inside a `const`
/// constructor, so the COLLECTIONS are validated rather than `const`;
/// [GridAssetDefinition] — the value a generated pack emits once and mounts in
/// two places — stays `const`
/// (decision `the_grid#asset-definitions-are-const-collections-are-validated`).
final class GridAssetPackDefinition {
  /// Collects [assets] vended by [package], refusing duplicates LOUD.
  factory GridAssetPackDefinition({
    required String package,
    required List<GridAssetDefinition> assets,
  }) {
    if (package.trim().isEmpty) {
      throw ArgumentError.value(
        package,
        'package',
        'GridAssetPackDefinition: package must be non-empty',
      );
    }
    final seenAssets = <AssetKey>{};
    final taughtCommandPattern = RegExp(r'^[a-z][a-z0-9-]*$');
    for (final asset in assets) {
      if (asset.assetKey.package != package) {
        throw ArgumentError.value(
          asset.assetKey.canonical,
          'assets',
          'GridAssetPackDefinition("$package"): vended by '
              '"${asset.assetKey.package}", not by this pack',
        );
      }
      if (!seenAssets.add(asset.assetKey)) {
        throw ArgumentError.value(
          asset.assetKey.canonical,
          'assets',
          'GridAssetPackDefinition("$package"): duplicate AssetKey',
        );
      }
      if (asset.teaches.isNotEmpty && asset.assetKey.kind != AssetKind.skill) {
        throw ArgumentError.value(
          asset.teaches,
          'assets',
          'GridAssetPackDefinition("$package"): '
              '${asset.assetKey.canonical} declares teaches but is not a skill',
        );
      }
      final seenTaughtCommands = <String>{};
      for (final command in asset.teaches) {
        if (!taughtCommandPattern.hasMatch(command)) {
          throw ArgumentError.value(
            command,
            'assets',
            'GridAssetPackDefinition("$package"): '
                '${asset.assetKey.canonical} has invalid taught command '
                '"$command"',
          );
        }
        if (!seenTaughtCommands.add(command)) {
          throw ArgumentError.value(
            command,
            'assets',
            'GridAssetPackDefinition("$package"): '
                '${asset.assetKey.canonical} has duplicate taught command '
                '"$command"',
          );
        }
      }
      final seenArtifacts = <AssetArtifactKey>{};
      for (final key in asset.artifactKeys) {
        if (!seenArtifacts.add(key)) {
          throw ArgumentError.value(
            key.canonical,
            'assets',
            'GridAssetPackDefinition("$package"): duplicate AssetArtifactKey',
          );
        }
      }
    }
    return GridAssetPackDefinition._(
      package,
      List<GridAssetDefinition>.unmodifiable(assets),
    );
  }

  GridAssetPackDefinition._(this.package, this.assets);

  /// The vending Dart package.
  final String package;

  /// The pack's assets, in declaration order (unmodifiable).
  final List<GridAssetDefinition> assets;
}

/// The station-wide collection of packs — every asset a station's composed
/// packs vend, indexed by identity.
///
/// Construction is the refusal point: a duplicate [AssetKey] or
/// [AssetArtifactKey] ACROSS packs throws before the registry, or any partial
/// index, is exposed. This package neither enumerates package graphs nor reads
/// a pubspec, an MCP config, or a substation root — a caller above it composes
/// the packs and hands them here.
final class GridAssetRegistry {
  /// Indexes [packs], refusing cross-pack duplicates LOUD.
  factory GridAssetRegistry(List<GridAssetPackDefinition> packs) {
    final byAsset = <AssetKey, GridAssetDefinition>{};
    final byArtifact = <AssetArtifactKey, AssetArtifact>{};
    for (final pack in packs) {
      for (final asset in pack.assets) {
        if (byAsset.containsKey(asset.assetKey)) {
          throw ArgumentError.value(
            asset.assetKey.canonical,
            'packs',
            'GridAssetRegistry: duplicate AssetKey across packs',
          );
        }
        byAsset[asset.assetKey] = asset;
        for (final artifact in asset.artifacts) {
          final key = artifact.keyUnder(asset.assetKey);
          if (byArtifact.containsKey(key)) {
            throw ArgumentError.value(
              key.canonical,
              'packs',
              'GridAssetRegistry: duplicate AssetArtifactKey across packs',
            );
          }
          byArtifact[key] = artifact;
        }
      }
    }
    return GridAssetRegistry._(
      List<GridAssetPackDefinition>.unmodifiable(packs),
      List<GridAssetDefinition>.unmodifiable(byAsset.values),
      Map<AssetKey, GridAssetDefinition>.unmodifiable(byAsset),
      Map<AssetArtifactKey, AssetArtifact>.unmodifiable(byArtifact),
    );
  }

  GridAssetRegistry._(this.packs, this.assets, this._byAsset, this._byArtifact);

  /// The composed packs, in composition order (unmodifiable).
  final List<GridAssetPackDefinition> packs;

  /// Every declared asset, in pack-then-declaration order (unmodifiable).
  ///
  /// A definition IS a `Seed`, so this list spreads unchanged into a
  /// `Substation`'s `assets` slot: `Substation('x', root, assets: [
  /// ...registry.assets])`.
  final List<GridAssetDefinition> assets;

  final Map<AssetKey, GridAssetDefinition> _byAsset;
  final Map<AssetArtifactKey, AssetArtifact> _byArtifact;

  /// The definition [key] names, or null when no composed pack vends it.
  GridAssetDefinition? definitionFor(AssetKey key) => _byAsset[key];

  /// The artifact [key] names, or null when no composed pack vends it.
  AssetArtifact? artifactFor(AssetArtifactKey key) => _byArtifact[key];
}
