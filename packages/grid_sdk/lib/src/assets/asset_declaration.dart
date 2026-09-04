import 'package:genesis_tree/genesis_tree.dart';
import 'package:meta/meta.dart';

import 'asset_identity.dart';

/// Who an asset is authored FOR — the closed audience vocabulary.
enum AssetAudience {
  /// A human reader (documentation, operator runbooks).
  human,

  /// An agent seat — instructions a harness feeds a model.
  agent,

  /// Both, verbatim: one body serves the human and the agent.
  both,
}

/// The open/closed split — `visibility: public|private`, adopted from the
/// Packaged AI Assets format by ADR-0008 Decision 2.
enum AssetVisibility {
  /// Vended to any consumer of the pack.
  public,

  /// Vended only inside the owning pack's own station.
  private,
}

/// WHEN an asset applies to a substation — a DECLARED predicate, never an
/// evaluated one.
///
/// Sealed, so the evaluator above this package matches exhaustively (ADR-0001
/// Decision 1). `grid_sdk` performs NO selector I/O: it carries the
/// declaration; resolving one against a real root belongs to the consumer.
/// A disjunction variant is deliberately absent until a real pack requires
/// one — adding a variant is a contract change the exhaustive `switch`
/// surfaces at every call site.
sealed class AssetSelector {
  /// Const-constructible: a selector is a value.
  const AssetSelector();
}

/// The asset applies unconditionally.
final class AlwaysApplies extends AssetSelector {
  /// Applies to every substation.
  const AlwaysApplies();
}

/// Applies where the substation's package graph contains [packageName].
final class RequiresPackage extends AssetSelector {
  /// Requires a dependency on [packageName].
  const RequiresPackage(this.packageName);

  /// The Dart package the substation must depend on.
  final String packageName;
}

/// Applies where [relativePath] exists under the substation root.
final class RequiresPath extends AssetSelector {
  /// Requires [relativePath] (root-relative) to exist.
  const RequiresPath(this.relativePath);

  /// The path, relative to the substation root. Never absolute — this package
  /// resolves nothing.
  final String relativePath;
}

/// Applies where EVERY one of [selectors] applies.
final class RequiresAll extends AssetSelector {
  /// Requires all of [selectors].
  const RequiresAll(this.selectors);

  /// The conjoined selectors.
  final List<AssetSelector> selectors;
}

/// One declared argument of an [AssetArtifact] — the mustache-templated prompt
/// argument of the Packaged AI Assets format (ADR-0008 Decision 2).
@immutable
final class AssetArgument {
  /// Declares [name], documented by [description]; [isRequired] marks it
  /// mandatory.
  const AssetArgument({
    required this.name,
    required this.description,
    this.isRequired = false,
  });

  /// The argument's template name.
  final String name;

  /// What the argument means, for the reader that fills it.
  final String description;

  /// Whether a consumer must supply it.
  final bool isRequired;
}

/// One delivery leg of a logical asset: a package-relative [path] delivered to
/// [target], with the arguments THAT leg declares.
@immutable
final class AssetArtifact {
  /// Declares the [target] leg at [path], with [arguments].
  const AssetArtifact({
    required this.target,
    required this.path,
    this.arguments = const <AssetArgument>[],
  });

  /// Which delivery leg this is.
  final AssetDeliveryTarget target;

  /// The artifact's path, RELATIVE to its vending package root. Resolving it
  /// against a checkout is the consumer's job, never this package's.
  final String path;

  /// The arguments this leg declares. Two legs of one logical asset may
  /// declare different arguments.
  final List<AssetArgument> arguments;

  /// This leg's identity under [asset].
  AssetArtifactKey keyUnder(AssetKey asset) =>
      AssetArtifactKey(asset: asset, target: target);
}

/// ONE logical asset, declared as a `const`, keyed, INERT [Seed].
///
/// One concrete class — `final`, so a pack emits INSTANCES and can never
/// declare a subclass-per-pack or subclass-per-asset (ADR-0008 Decision 2:
/// "consumers compose, never subclass"; the constraint is unrepresentable
/// rather than guarded, ADR-0013 Decision 3).
///
/// Its reconciliation identity IS its [assetKey], so ONE generated
/// `static const` instance is legal both inside a `GridAssetRegistry` and
/// spread unchanged into a `Substation`'s `assets` slot: no inflater and no
/// second runtime representation sits between declaration and composition.
///
/// INERT: it declares zero children and mounts no effect. Mounting one records
/// AVAILABILITY and performs no work; what it contributes is its diagnostics
/// (ADR-0012's typed `DiagnosticsProperty` union).
final class GridAssetDefinition extends MultiChildSeed {
  /// Declares [assetKey], documented by [description], delivered by
  /// [artifacts]; [audience], [visibility], and [selector] default to the
  /// common agent-facing, public, unconditional case.
  const GridAssetDefinition({
    required this.assetKey,
    required this.description,
    required this.artifacts,
    this.audience = AssetAudience.agent,
    this.visibility = AssetVisibility.public,
    this.selector = const AlwaysApplies(),
  }) : super(children: const <Seed>[], key: assetKey);

  /// The logical identity — also this seed's reconciliation [Seed.key].
  final AssetKey assetKey;

  /// What the asset is for, in one line.
  final String description;

  /// The delivery legs, in declaration order.
  final List<AssetArtifact> artifacts;

  /// Who the asset is authored for.
  final AssetAudience audience;

  /// The pack's open/closed posture for this asset.
  final AssetVisibility visibility;

  /// The declared applicability predicate; evaluated above this package.
  final AssetSelector selector;

  /// The identities of this asset's delivery legs, in declaration order.
  List<AssetArtifactKey> get artifactKeys => <AssetArtifactKey>[
    for (final artifact in artifacts) artifact.keyUnder(assetKey),
  ];

  @override
  void debugFillProperties(DiagnosticsBuilder properties) {
    super.debugFillProperties(properties);
    properties
      ..add(
        DiagnosticsProperty.string(
          name: 'asset',
          level: DiagnosticsLevel.info,
          value: assetKey.canonical,
        ),
      )
      ..add(
        DiagnosticsProperty.enumValue(
          name: 'kind',
          level: DiagnosticsLevel.info,
          value: assetKey.kind.name,
          enumType: 'AssetKind',
        ),
      )
      ..add(
        DiagnosticsProperty.enumValue(
          name: 'audience',
          level: DiagnosticsLevel.info,
          value: audience.name,
          enumType: 'AssetAudience',
        ),
      )
      ..add(
        DiagnosticsProperty.enumValue(
          name: 'visibility',
          level: DiagnosticsLevel.info,
          value: visibility.name,
          enumType: 'AssetVisibility',
        ),
      )
      ..add(
        DiagnosticsProperty.int(
          name: 'artifacts',
          level: DiagnosticsLevel.info,
          value: artifacts.length,
        ),
      );
  }
}
