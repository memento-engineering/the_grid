/// Read-only resolution of a station's compiled content/capability assets.
library;

import 'dart:convert';
import 'dart:io';

import 'package:freezed_annotation/freezed_annotation.dart';
import 'package:grid_sdk/grid_sdk.dart';
import 'package:path/path.dart' as p;

part 'asset_catalog_resolver.freezed.dart';

/// One substation root and its explicit asset participation overrides.
@Freezed(copyWith: false)
abstract class AssetCatalogSubstation with _$AssetCatalogSubstation {
  /// Creates one authored catalog-resolution target.
  const factory AssetCatalogSubstation({
    required String substation,
    required String root,
    @Default(<AssetKey, bool>{}) Map<AssetKey, bool> overrides,
  }) = _AssetCatalogSubstation;
}

/// Summary counts for one asset catalog report.
@Freezed(copyWith: false)
abstract class AssetCatalogCounts with _$AssetCatalogCounts {
  /// Creates catalog counts.
  const factory AssetCatalogCounts({
    required int total,
    required int resolved,
    required int excluded,
    required int unknown,
  }) = _AssetCatalogCounts;

  const AssetCatalogCounts._();

  /// Serializes these counts to the stable catalog wire shape.
  Map<String, Object?> toJson() => <String, Object?>{
    'total': total,
    'resolved': resolved,
    'excluded': excluded,
    'unknown': unknown,
  };
}

/// The tri-state participation result for one available asset.
@Freezed(copyWith: false)
sealed class AssetParticipation with _$AssetParticipation {
  /// The selected substation includes the asset.
  const factory AssetParticipation.resolved({
    required String decidedBy,
    required String reason,
  }) = AssetResolved;

  /// The selected substation excludes the asset.
  const factory AssetParticipation.excluded({
    required String decidedBy,
    required String reason,
  }) = AssetExcluded;

  /// No available fact decides whether the substation includes the asset.
  const factory AssetParticipation.unknown({
    required String decidedBy,
    required String reason,
  }) = AssetUnknown;

  const AssetParticipation._();

  /// Serializes this decision without freezed's runtime-type discriminator.
  Map<String, Object?> toJson() => switch (this) {
    AssetResolved(:final decidedBy, :final reason) => <String, Object?>{
      'state': 'RESOLVED',
      'decided_by': decidedBy,
      'reason': reason,
    },
    AssetExcluded(:final decidedBy, :final reason) => <String, Object?>{
      'state': 'EXCLUDED',
      'decided_by': decidedBy,
      'reason': reason,
    },
    AssetUnknown(:final decidedBy, :final reason) => <String, Object?>{
      'state': 'UNKNOWN',
      'decided_by': decidedBy,
      'reason': reason,
    },
  };
}

/// One registry declaration and its participation in the selected substation.
@Freezed(copyWith: false)
abstract class AssetCatalogEntry with _$AssetCatalogEntry {
  /// Creates one ordered catalog entry.
  const factory AssetCatalogEntry({
    required String id,
    required String kind,
    required String pack,
    required String description,
    required String visibility,
    required String audience,
    required Map<String, Object?> selector,
    required AssetParticipation participation,
  }) = _AssetCatalogEntry;

  const AssetCatalogEntry._();

  /// Serializes this entry to the stable catalog wire shape.
  Map<String, Object?> toJson() => <String, Object?>{
    'id': id,
    'kind': kind,
    'pack': pack,
    'description': description,
    'visibility': visibility,
    'audience': audience,
    'selector': selector,
    'participation': participation.toJson(),
  };
}

/// The complete compiled union catalog, optionally resolved for a substation.
@Freezed(copyWith: false)
abstract class AssetCatalogReport with _$AssetCatalogReport {
  /// Creates a catalog report.
  const factory AssetCatalogReport({
    required String? substation,
    required AssetCatalogCounts counts,
    required List<AssetCatalogEntry> assets,
  }) = _AssetCatalogReport;

  const AssetCatalogReport._();

  /// Serializes this report to the shared CLI and station wire shape.
  Map<String, Object?> toJson() => <String, Object?>{
    'substation': substation,
    'counts': counts.toJson(),
    'assets': <Map<String, Object?>>[
      for (final asset in assets) asset.toJson(),
    ],
  };
}

/// A deterministic catalog-resolution refusal safe to expose to a caller.
class AssetCatalogResolutionException implements Exception {
  /// Creates a refusal with an HTTP [statusCode] and safe [message].
  const AssetCatalogResolutionException(this.statusCode, this.message);

  /// The HTTP status code used by the resident read-only route.
  final int statusCode;

  /// The caller-facing refusal detail.
  final String message;

  @override
  String toString() => message;
}

/// Resolves the statically composed [GridAssetRegistry] without discovery.
///
/// Decision `the_grid#adr-0011-federation-and-asset-management` says “Asset is
/// an umbrella with two families.” This catalog serves only family 1,
/// content/capability assets represented by [GridAssetRegistry]. It
/// deliberately excludes family 2's leasable resource/capacity assets
/// (compute, agent slots, and HITL humans).
///
/// A null [registry] is an empty catalog. Resolution reads only an explicitly
/// selected substation's package-config file and declared root-relative paths;
/// it never scans packages or parses asset manifests.
class AssetCatalogResolver {
  /// Creates a resolver over one compiled registry and authored roster.
  const AssetCatalogResolver({
    this.registry,
    this.substations = const <AssetCatalogSubstation>[],
  });

  /// The station-composed, validated content/capability asset registry.
  final GridAssetRegistry? registry;

  /// The authored substation roots and explicit participation overrides.
  final List<AssetCatalogSubstation> substations;

  /// Returns the union catalog, optionally resolved for [substation].
  Future<AssetCatalogReport> resolve({String? substation}) async {
    final selected = _selectSubstation(substation);
    final context = selected == null ? null : _ResolutionContext(selected.root);
    final entries = <AssetCatalogEntry>[];

    for (final definition
        in registry?.assets ?? const <GridAssetDefinition>[]) {
      final key = definition.assetKey;
      final AssetParticipation participation;
      if (selected == null) {
        participation = const AssetParticipation.unknown(
          decidedBy: 'nothing',
          reason: 'no substation was selected',
        );
      } else if (selected.overrides[key] case final include?) {
        participation = include
            ? AssetParticipation.resolved(
                decidedBy: 'roster_override:${key.canonical}=include',
                reason: 'the substation roster includes this asset',
              )
            : AssetParticipation.excluded(
                decidedBy: 'roster_override:${key.canonical}=exclude',
                reason: 'the substation roster excludes this asset',
              );
      } else {
        participation = await _evaluateSelector(
          definition.selector,
          context!,
          key,
        );
      }
      entries.add(
        AssetCatalogEntry(
          id: key.id,
          kind: key.kind.name,
          pack: key.package,
          description: definition.description,
          visibility: definition.visibility.name,
          audience: definition.audience.name,
          selector: _selectorToJson(definition.selector),
          participation: participation,
        ),
      );
    }

    var resolved = 0;
    var excluded = 0;
    var unknown = 0;
    for (final entry in entries) {
      switch (entry.participation) {
        case AssetResolved():
          resolved++;
        case AssetExcluded():
          excluded++;
        case AssetUnknown():
          unknown++;
      }
    }
    return AssetCatalogReport(
      substation: substation,
      counts: AssetCatalogCounts(
        total: entries.length,
        resolved: resolved,
        excluded: excluded,
        unknown: unknown,
      ),
      assets: entries,
    );
  }

  AssetCatalogSubstation? _selectSubstation(String? requested) {
    if (requested == null) return null;
    if (requested.trim().isEmpty) {
      throw const AssetCatalogResolutionException(
        HttpStatus.badRequest,
        'substation must be non-empty',
      );
    }
    final matches = <AssetCatalogSubstation>[
      for (final candidate in substations)
        if (candidate.substation == requested) candidate,
    ];
    if (matches.isEmpty) {
      throw AssetCatalogResolutionException(
        HttpStatus.notFound,
        'unknown substation: $requested',
      );
    }
    if (matches.length != 1) {
      throw AssetCatalogResolutionException(
        HttpStatus.internalServerError,
        'substation is configured more than once: $requested',
      );
    }
    return matches.single;
  }

  Future<AssetParticipation> _evaluateSelector(
    AssetSelector selector,
    _ResolutionContext context,
    AssetKey asset,
  ) async => switch (selector) {
    AlwaysApplies() => const AssetParticipation.resolved(
      decidedBy: 'selector:always_applies',
      reason: 'the selector always applies',
    ),
    RequiresPackage(:final packageName) => _resolvePackage(
      packageName,
      context,
    ),
    RequiresPath(:final relativePath) => _resolvePath(
      relativePath,
      context,
      asset,
    ),
    RequiresAll(:final selectors) => _resolveAll(selectors, context, asset),
  };

  Future<AssetParticipation> _resolvePackage(
    String packageName,
    _ResolutionContext context,
  ) async {
    final names = await context.packageNames();
    if (names == null) {
      return AssetParticipation.unknown(
        decidedBy: 'selector:requires_package',
        reason: 'the substation package graph is unavailable',
      );
    }
    if (names.contains(packageName)) {
      return AssetParticipation.resolved(
        decidedBy: 'selector:requires_package',
        reason: 'package "$packageName" is present',
      );
    }
    return AssetParticipation.excluded(
      decidedBy: 'selector:requires_package',
      reason: 'package "$packageName" is absent',
    );
  }

  Future<AssetParticipation> _resolvePath(
    String relativePath,
    _ResolutionContext context,
    AssetKey asset,
  ) async {
    if (relativePath.isEmpty ||
        p.isAbsolute(relativePath) ||
        p.split(relativePath).contains('..')) {
      throw AssetCatalogResolutionException(
        HttpStatus.internalServerError,
        'asset ${asset.canonical} declares a non-contained path: '
        '$relativePath',
      );
    }
    final root = p.canonicalize(p.absolute(context.root));
    final target = p.canonicalize(p.join(root, relativePath));
    if (target != root && !p.isWithin(root, target)) {
      throw AssetCatalogResolutionException(
        HttpStatus.internalServerError,
        'asset ${asset.canonical} declares a non-contained path: '
        '$relativePath',
      );
    }
    final present =
        await FileSystemEntity.type(target, followLinks: false) !=
        FileSystemEntityType.notFound;
    return present
        ? AssetParticipation.resolved(
            decidedBy: 'selector:requires_path',
            reason: 'path "$relativePath" is present',
          )
        : AssetParticipation.excluded(
            decidedBy: 'selector:requires_path',
            reason: 'path "$relativePath" is absent',
          );
  }

  Future<AssetParticipation> _resolveAll(
    List<AssetSelector> selectors,
    _ResolutionContext context,
    AssetKey asset,
  ) async {
    AssetExcluded? excluded;
    AssetUnknown? unknown;
    for (final selector in selectors) {
      final result = await _evaluateSelector(selector, context, asset);
      switch (result) {
        case AssetResolved():
          break;
        case final AssetExcluded value:
          excluded ??= value;
        case final AssetUnknown value:
          unknown ??= value;
      }
    }
    if (excluded case final value?) {
      return AssetParticipation.excluded(
        decidedBy: 'selector:requires_all',
        reason: 'a required selector excluded the asset: ${value.reason}',
      );
    }
    if (unknown case final value?) {
      return AssetParticipation.unknown(
        decidedBy: 'selector:requires_all',
        reason: 'a required selector is unknown: ${value.reason}',
      );
    }
    return const AssetParticipation.resolved(
      decidedBy: 'selector:requires_all',
      reason: 'every required selector resolved',
    );
  }

  Map<String, Object?> _selectorToJson(AssetSelector selector) =>
      switch (selector) {
        AlwaysApplies() => const <String, Object?>{'kind': 'always_applies'},
        RequiresPackage(:final packageName) => <String, Object?>{
          'kind': 'requires_package',
          'package': packageName,
        },
        RequiresPath(:final relativePath) => <String, Object?>{
          'kind': 'requires_path',
          'path': relativePath,
        },
        RequiresAll(:final selectors) => <String, Object?>{
          'kind': 'requires_all',
          'selectors': <Map<String, Object?>>[
            for (final child in selectors) _selectorToJson(child),
          ],
        },
      };
}

final class _ResolutionContext {
  _ResolutionContext(this.root);

  final String root;
  Future<Set<String>?>? _packageNames;

  Future<Set<String>?> packageNames() => _packageNames ??= _readPackageNames();

  Future<Set<String>?> _readPackageNames() async {
    try {
      final source = await File(
        p.join(root, '.dart_tool', 'package_config.json'),
      ).readAsString();
      final decoded = jsonDecode(source);
      if (decoded is! Map<String, dynamic>) return null;
      final packages = decoded['packages'];
      if (packages is! List<dynamic>) return null;
      final names = <String>{};
      for (final package in packages) {
        if (package is! Map<String, dynamic>) return null;
        final name = package['name'];
        if (name is! String || name.trim().isEmpty) return null;
        names.add(name);
      }
      return Set<String>.unmodifiable(names);
    } on Object {
      return null;
    }
  }
}
