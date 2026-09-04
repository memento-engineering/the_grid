import 'dart:convert';
import 'dart:io';
import 'dart:isolate';

import 'package:grid_cli/grid_cli.dart';
import 'package:grid_sdk/grid_sdk.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

void main() {
  test(
    'union catalog carries every SDK field and counts catalog unknowns',
    () async {
      final registry = GridAssetRegistry([
        GridAssetPackDefinition(
          package: 'alpha_assets',
          assets: [
            _asset(
              package: 'alpha_assets',
              id: 'guide',
              kind: AssetKind.resource,
              description: 'Human guide',
              audience: AssetAudience.human,
              visibility: AssetVisibility.private,
            ),
          ],
        ),
        GridAssetPackDefinition(
          package: 'beta_assets',
          assets: [
            _asset(
              package: 'beta_assets',
              id: 'build',
              kind: AssetKind.skill,
              description: 'Build procedure',
              selector: const RequiresAll([
                RequiresPackage('grid_sdk'),
                RequiresPath('tool/build.dart'),
              ]),
            ),
          ],
        ),
      ]);

      final report = await AssetCatalogResolver(registry: registry).resolve();

      expect(report.substation, isNull);
      expect(
        report.counts,
        const AssetCatalogCounts(
          total: 2,
          resolved: 0,
          excluded: 0,
          unknown: 2,
        ),
      );
      expect(report.toJson(), {
        'substation': null,
        'counts': {'total': 2, 'resolved': 0, 'excluded': 0, 'unknown': 2},
        'assets': [
          {
            'id': 'guide',
            'kind': 'resource',
            'pack': 'alpha_assets',
            'description': 'Human guide',
            'visibility': 'private',
            'audience': 'human',
            'selector': {'kind': 'always_applies'},
            'participation': {
              'state': 'UNKNOWN',
              'decided_by': 'nothing',
              'reason': 'no substation was selected',
            },
          },
          {
            'id': 'build',
            'kind': 'skill',
            'pack': 'beta_assets',
            'description': 'Build procedure',
            'visibility': 'public',
            'audience': 'agent',
            'selector': {
              'kind': 'requires_all',
              'selectors': [
                {'kind': 'requires_package', 'package': 'grid_sdk'},
                {'kind': 'requires_path', 'path': 'tool/build.dart'},
              ],
            },
            'participation': {
              'state': 'UNKNOWN',
              'decided_by': 'nothing',
              'reason': 'no substation was selected',
            },
          },
        ],
      });
    },
  );

  test(
    'selectors and overrides produce resolved excluded and unknown decisions',
    () async {
      final temp = await Directory.systemTemp.createTemp('asset-catalog-');
      addTearDown(() => temp.delete(recursive: true));
      await File(p.join(temp.path, 'present.txt')).writeAsString('present');
      final overrideExcluded = _key('pack', AssetKind.resource, 'override-out');
      final overrideIncluded = _key('pack', AssetKind.resource, 'override-in');
      final registry = GridAssetRegistry([
        GridAssetPackDefinition(
          package: 'pack',
          assets: [
            _asset(key: overrideExcluded, description: 'override exclude'),
            _asset(
              key: overrideIncluded,
              description: 'override include',
              selector: const RequiresPath('/outside'),
            ),
            _asset(
              package: 'pack',
              id: 'package-unknown',
              description: 'unknown package',
              selector: const RequiresPackage('missing'),
            ),
            _asset(
              package: 'pack',
              id: 'all-excluded',
              description: 'all excluded',
              selector: const RequiresAll([
                RequiresPackage('missing'),
                RequiresPath('absent.txt'),
              ]),
            ),
            _asset(
              package: 'pack',
              id: 'all-unknown',
              description: 'all unknown',
              selector: const RequiresAll([
                RequiresPackage('missing'),
                RequiresPath('present.txt'),
              ]),
            ),
            _asset(package: 'pack', id: 'always', description: 'always'),
          ],
        ),
      ]);
      final resolver = AssetCatalogResolver(
        registry: registry,
        substations: [
          AssetCatalogSubstation(
            substation: 'earth',
            root: temp.path,
            overrides: {overrideExcluded: false, overrideIncluded: true},
          ),
        ],
      );

      final report = await resolver.resolve(substation: 'earth');

      expect(
        report.counts,
        const AssetCatalogCounts(
          total: 6,
          resolved: 2,
          excluded: 2,
          unknown: 2,
        ),
      );
      expect(
        [
          for (final entry in report.assets)
            (entry.id, entry.participation.toJson()['state']),
        ],
        [
          ('override-out', 'EXCLUDED'),
          ('override-in', 'RESOLVED'),
          ('package-unknown', 'UNKNOWN'),
          ('all-excluded', 'EXCLUDED'),
          ('all-unknown', 'UNKNOWN'),
          ('always', 'RESOLVED'),
        ],
      );
      expect(
        report.assets[0].participation.toJson()['decided_by'],
        'roster_override:pack/resource/override-out=exclude',
      );
      expect(
        report.assets[1].participation.toJson()['decided_by'],
        'roster_override:pack/resource/override-in=include',
      );
      expect(
        report.assets[3].participation.toJson()['decided_by'],
        'selector:requires_all',
      );
    },
  );

  test('RequiresPackage reads only package_config names', () async {
    final temp = await Directory.systemTemp.createTemp('asset-packages-');
    addTearDown(() => temp.delete(recursive: true));
    final dartTool = await Directory(
      p.join(temp.path, '.dart_tool'),
    ).create(recursive: true);
    await File(p.join(dartTool.path, 'package_config.json')).writeAsString(
      jsonEncode({
        'configVersion': 2,
        'packages': [
          {'name': 'present', 'rootUri': '../present'},
        ],
      }),
    );
    final resolver = AssetCatalogResolver(
      registry: GridAssetRegistry([
        GridAssetPackDefinition(
          package: 'pack',
          assets: [
            _asset(
              package: 'pack',
              id: 'present',
              description: 'present',
              selector: const RequiresPackage('present'),
            ),
            _asset(
              package: 'pack',
              id: 'absent',
              description: 'absent',
              selector: const RequiresPackage('absent'),
            ),
          ],
        ),
      ]),
      substations: [
        AssetCatalogSubstation(substation: 'earth', root: temp.path),
      ],
    );

    final report = await resolver.resolve(substation: 'earth');

    expect(report.assets[0].participation, isA<AssetResolved>());
    expect(report.assets[1].participation, isA<AssetExcluded>());
  });

  test('missing unreadable or malformed package graph is unknown', () async {
    final temp = await Directory.systemTemp.createTemp('asset-packages-');
    addTearDown(() => temp.delete(recursive: true));
    final dartTool = await Directory(
      p.join(temp.path, '.dart_tool'),
    ).create(recursive: true);
    final config = File(p.join(dartTool.path, 'package_config.json'));
    final resolver = _packageResolver(temp.path);

    expect(
      (await resolver.resolve(substation: 'earth')).assets.single.participation,
      isA<AssetUnknown>(),
    );
    await config.writeAsString('{bad');
    expect(
      (await resolver.resolve(substation: 'earth')).assets.single.participation,
      isA<AssetUnknown>(),
    );
    await config.writeAsString(jsonEncode({'packages': 'not-a-list'}));
    expect(
      (await resolver.resolve(substation: 'earth')).assets.single.participation,
      isA<AssetUnknown>(),
    );
  });

  test('absolute and traversing RequiresPath declarations refuse loudly', () {
    final root = Directory.systemTemp.path;
    for (final path in ['/tmp/outside', '../outside']) {
      final resolver = AssetCatalogResolver(
        registry: GridAssetRegistry([
          GridAssetPackDefinition(
            package: 'pack',
            assets: [
              _asset(
                package: 'pack',
                id: 'unsafe',
                description: 'unsafe',
                selector: RequiresPath(path),
              ),
            ],
          ),
        ]),
        substations: [AssetCatalogSubstation(substation: 'earth', root: root)],
      );
      expect(
        resolver.resolve(substation: 'earth'),
        throwsA(
          isA<AssetCatalogResolutionException>()
              .having(
                (error) => error.statusCode,
                'statusCode',
                HttpStatus.internalServerError,
              )
              .having(
                (error) => error.message,
                'message',
                contains('non-contained path'),
              ),
        ),
      );
    }
  });

  test('blank absent and duplicate substations refuse 400 404 and 500', () {
    final root = Directory.systemTemp.path;
    final resolver = AssetCatalogResolver(
      substations: [
        AssetCatalogSubstation(substation: 'duplicate', root: root),
        AssetCatalogSubstation(substation: 'duplicate', root: root),
      ],
    );

    for (final (name, status) in [
      ('  ', HttpStatus.badRequest),
      ('missing', HttpStatus.notFound),
      ('duplicate', HttpStatus.internalServerError),
    ]) {
      expect(
        resolver.resolve(substation: name),
        throwsA(
          isA<AssetCatalogResolutionException>().having(
            (error) => error.statusCode,
            'statusCode',
            status,
          ),
        ),
      );
    }
  });

  test('null registry is empty and never discovers declarations', () async {
    final report = await const AssetCatalogResolver().resolve();
    expect(report.toJson(), {
      'substation': null,
      'counts': {'total': 0, 'resolved': 0, 'excluded': 0, 'unknown': 0},
      'assets': <Object?>[],
    });
  });

  test('grid_cli remains Power-neutral and declaration-offline', () {
    final library = Isolate.resolvePackageUriSync(
      Uri.parse('package:grid_cli/grid_cli.dart'),
    )!;
    final source = File.fromUri(
      library.resolve('src/asset_catalog_resolver.dart'),
    ).readAsStringSync();
    final pubspec = File.fromUri(
      library.resolve('../pubspec.yaml'),
    ).readAsStringSync();

    expect(source, contains("import 'package:grid_sdk/grid_sdk.dart'"));
    expect(source, isNot(contains('power_station')));
    expect(pubspec, isNot(contains('power_station:')));
    expect(source, isNot(contains('package:yaml')));
    expect(source, isNot(contains('loadYaml')));
    expect(source, isNot(contains('dart:mirrors')));
    expect(source, isNot(contains('Directory(')));
    expect(source, isNot(contains('enum AssetSelector')));
    expect(
      source,
      contains('the_grid#adr-0011-federation-and-asset-management'),
    );
    expect(source, contains('an umbrella with two families'));
    expect(source, contains('resource/capacity assets'));
  });
}

AssetCatalogResolver _packageResolver(String root) => AssetCatalogResolver(
  registry: GridAssetRegistry([
    GridAssetPackDefinition(
      package: 'pack',
      assets: [
        _asset(
          package: 'pack',
          id: 'package',
          description: 'package',
          selector: const RequiresPackage('anything'),
        ),
      ],
    ),
  ]),
  substations: [AssetCatalogSubstation(substation: 'earth', root: root)],
);

AssetKey _key(String package, AssetKind kind, String id) =>
    AssetKey(package: package, kind: kind, id: id);

GridAssetDefinition _asset({
  AssetKey? key,
  String? package,
  String? id,
  AssetKind kind = AssetKind.resource,
  required String description,
  AssetAudience audience = AssetAudience.agent,
  AssetVisibility visibility = AssetVisibility.public,
  AssetSelector selector = const AlwaysApplies(),
}) => GridAssetDefinition(
  assetKey: key ?? _key(package!, kind, id!),
  description: description,
  artifacts: const [],
  audience: audience,
  visibility: visibility,
  selector: selector,
);
