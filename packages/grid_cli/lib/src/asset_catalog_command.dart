/// The resident-independent `asset-catalog` command.
library;

import 'dart:convert';
import 'dart:io';

import 'package:args/command_runner.dart';

import 'asset_catalog_resolver.dart';

/// Prints the compiled content/capability asset union or resolves one target.
///
/// This command operates directly on its injected [resolver]. It neither
/// attaches to a resident station nor discovers asset manifests at runtime.
class AssetCatalogCommand extends Command<int> {
  /// Creates the offline catalog command over a station-composed resolver.
  AssetCatalogCommand({required this.resolver}) {
    argParser
      ..addOption(
        'substation',
        help: 'Resolve participation for this authored substation.',
        valueHelp: 'name',
      )
      ..addFlag(
        'json',
        help: 'Emit exactly one JSON report object.',
        negatable: false,
      );
  }

  /// The compiled declaration resolver injected by the composing station.
  final AssetCatalogResolver resolver;

  @override
  String get name => 'asset-catalog';

  @override
  String get description =>
      'List compiled content/capability assets and resolve participation.';

  @override
  Future<int> run() => runAssetCatalog(
    resolver: resolver,
    substation: argResults!.option('substation'),
    json: argResults!.flag('json'),
  );
}

/// Runs asset catalog resolution without a resident process or lock file.
Future<int> runAssetCatalog({
  required AssetCatalogResolver resolver,
  String? substation,
  bool json = false,
  void Function(String)? out,
  void Function(String)? err,
}) async {
  final void Function(String) write =
      out ?? (message) => stdout.writeln(message);
  final void Function(String) writeError =
      err ?? (message) => stderr.writeln(message);
  try {
    final report = await resolver.resolve(substation: substation);
    if (json) {
      write(jsonEncode(report.toJson()));
    } else {
      renderAssetCatalog(report, write);
    }
    return 0;
  } on AssetCatalogResolutionException catch (error) {
    writeError('grid asset-catalog: ${error.message}');
    return 64;
  }
}

/// Renders one stable human-readable asset catalog report.
void renderAssetCatalog(
  AssetCatalogReport report,
  void Function(String) write,
) {
  final counts = report.counts;
  write(
    'asset-catalog — substation=${report.substation ?? 'none'} '
    'total=${counts.total} resolved=${counts.resolved} '
    'excluded=${counts.excluded} unknown=${counts.unknown}',
  );
  for (final asset in report.assets) {
    final (state, decidedBy) = switch (asset.participation) {
      AssetResolved(:final decidedBy) => ('RESOLVED', decidedBy),
      AssetExcluded(:final decidedBy) => ('EXCLUDED', decidedBy),
      AssetUnknown(:final decidedBy) => ('UNKNOWN', decidedBy),
    };
    write(
      '$state  ${asset.pack}/${asset.kind}/${asset.id}  '
      'visibility=${asset.visibility} audience=${asset.audience} '
      'selector=${jsonEncode(asset.selector)} decided-by=$decidedBy '
      '— ${asset.description}',
    );
  }
}
