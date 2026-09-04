// tg-1w3m: the dependency-neutral asset declaration contract.
//
// Proves the load-bearing properties of the contract:
//   1. const definitions carry stable logical identity and mount INERT;
//   2. delivery-leg identity is authored INDEPENDENTLY of logical identity;
//   3. ONE instance composes in BOTH a GridAssetRegistry and a Substation's
//      `assets` List<Seed> — no inflater, no second representation;
//   4. duplicates refuse LOUD before a partial registry is exposed;
//   5. the package is dependency-neutral (no discovery, filesystem, YAML, or
//      power_station dependency).
//
// The source gates follow dh_state_leak_gate_test's idiom: package-URI
// resolution (CWD-independent), comment stripping (the docs deliberately
// DISCUSS what the negatives ban), and a vacuousness control beside every
// negative so a moved directory cannot make a gate pass silently.
import 'dart:io';
import 'dart:isolate';

import 'package:grid_sdk/grid_sdk.dart';
import 'package:test/test.dart';

const AssetKey _decideKey = AssetKey(
  package: 'demo_grid_assets',
  kind: AssetKind.skill,
  id: 'decide',
);

/// One logical skill with TWO independently authored delivery legs.
const GridAssetDefinition _decide = GridAssetDefinition(
  assetKey: _decideKey,
  description: 'Record a decision in the register.',
  artifacts: <AssetArtifact>[
    AssetArtifact(
      target: AssetDeliveryTarget.claude,
      path: 'assets/claude/skills/decide/SKILL.md',
    ),
    AssetArtifact(
      target: AssetDeliveryTarget.agents,
      path: 'assets/agents/decide.md',
      arguments: <AssetArgument>[
        AssetArgument(
          name: 'slug',
          description: 'the decision slug',
          isRequired: true,
        ),
      ],
    ),
  ],
  teaches: <String>['decide'],
  selector: RequiresPackage('genesis_tree'),
);

GridAssetRegistry _registry() => GridAssetRegistry(<GridAssetPackDefinition>[
  GridAssetPackDefinition(
    package: 'demo_grid_assets',
    assets: const <GridAssetDefinition>[_decide],
  ),
]);

/// A terminal leaf (an empty fan-out) — the track_b_composition_test idiom.
class _Leaf extends MultiChildSeed {
  const _Leaf() : super(children: const <Seed>[]);
}

/// Captures the ambient substation name it mounts under.
class _ScopeProbe extends StatelessSeed {
  const _ScopeProbe(this.seen);

  final List<String> seen;

  @override
  Seed build(TreeContext context) {
    seen.add(SubstationScope.of(context).name);
    return const _Leaf();
  }
}

void _mount(Seed root) {
  final owner = TreeOwner();
  owner.mountRoot(ProviderScope(child: root));
  owner.flush();
}

/// Every authored `.dart` under `lib/src/assets/`, resolved through the
/// package URI so the gate is CWD-independent.
List<File> _assetSources() {
  final libUri = Isolate.resolvePackageUriSync(
    Uri.parse('package:grid_sdk/grid_sdk.dart'),
  );
  return Directory.fromUri(libUri!.resolve('src/assets/'))
      .listSync()
      .whereType<File>()
      .where((f) => f.path.endsWith('.dart'))
      .toList();
}

/// grid_sdk's own pubspec, resolved the same way.
File _pubspec() {
  final libUri = Isolate.resolvePackageUriSync(
    Uri.parse('package:grid_sdk/grid_sdk.dart'),
  );
  return File.fromUri(libUri!.resolve('../pubspec.yaml'));
}

/// The DIRECT dependency names in [_pubspec] — line-scanned, deliberately
/// without a YAML parser (this suite asserts the package has none).
Set<String> _directDependencies() {
  final names = <String>{};
  var inBlock = false;
  for (final line in _pubspec().readAsLinesSync()) {
    if (line.startsWith('dependencies:')) {
      inBlock = true;
      continue;
    }
    if (!inBlock) continue;
    if (line.isNotEmpty && !line.startsWith(' ')) break;
    final match = RegExp(r'^  ([a-z0-9_]+):').firstMatch(line);
    if (match != null) names.add(match.group(1)!);
  }
  return names;
}

/// Strips `//` line comments: the gates reason about CODE, and the doc
/// comments deliberately discuss what the negatives ban.
String _code(String source) => source
    .split('\n')
    .map((line) {
      final i = line.indexOf('//');
      return i == -1 ? line : line.substring(0, i);
    })
    .join('\n');

void main() {
  group('const definitions carry stable logical identity', () {
    test('re-authoring a const definition yields the SAME instance', () {
      const a = GridAssetDefinition(
        assetKey: AssetKey(package: 'p', kind: AssetKind.prompt, id: 'brief'),
        description: 'the brief',
        artifacts: <AssetArtifact>[
          AssetArtifact(target: AssetDeliveryTarget.mcp, path: 'p/brief.md'),
        ],
      );
      const b = GridAssetDefinition(
        assetKey: AssetKey(package: 'p', kind: AssetKind.prompt, id: 'brief'),
        description: 'the brief',
        artifacts: <AssetArtifact>[
          AssetArtifact(target: AssetDeliveryTarget.mcp, path: 'p/brief.md'),
        ],
      );
      expect(identical(a, b), isTrue);
    });

    test('package / kind / id and the canonical rendering are stable', () {
      expect(_decide.assetKey.package, 'demo_grid_assets');
      expect(_decide.assetKey.kind, AssetKind.skill);
      expect(_decide.assetKey.id, 'decide');
      expect(_decide.assetKey.canonical, 'demo_grid_assets/skill/decide');
      expect(
        _decideKey,
        isNot(
          const AssetKey(
            package: 'demo_grid_assets',
            kind: AssetKind.prompt,
            id: 'decide',
          ),
        ),
      );
    });

    test('the intrinsic Seed key IS the AssetKey and the seed is INERT', () {
      expect(_decide.key, same(_decideKey));
      expect(_decide.children, isEmpty);
      expect(_decide.createBranch(), isA<MultiChildBranch>());
    });

    test('diagnostics record availability, never work', () {
      final deep = _decide.toStringDeep();
      expect(deep, contains('demo_grid_assets/skill/decide'));
      expect(deep, contains('AssetKind.skill'));
      expect(deep, contains('AssetVisibility.public'));
      expect(deep, contains('artifacts: 2'));
    });
  });

  group('delivery-leg identity is authored independently', () {
    test('two legs of ONE logical skill are two distinct artifact keys', () {
      final keys = _decide.artifactKeys;
      expect(keys, hasLength(2));
      expect(keys.first, isNot(keys.last));
      expect(keys.map((k) => k.asset).toSet(), <AssetKey>{_decideKey});
      expect(keys.map((k) => k.canonical), <String>[
        'demo_grid_assets/skill/decide@claude',
        'demo_grid_assets/skill/decide@agents',
      ]);
    });

    test('the legs need not agree on path or arguments', () {
      expect(_decide.artifacts.first.path, isNot(_decide.artifacts.last.path));
      expect(_decide.artifacts.first.arguments, isEmpty);
      expect(_decide.artifacts.last.arguments.single.name, 'slug');
      expect(_decide.artifacts.last.arguments.single.isRequired, isTrue);
    });
  });

  group('ONE instance composes in BOTH surfaces', () {
    test('the registry returns the very instance that was declared', () {
      final registry = _registry();
      expect(identical(registry.definitionFor(_decideKey), _decide), isTrue);
      expect(registry.assets, hasLength(1));
      expect(identical(registry.assets.single, _decide), isTrue);
      expect(registry.packs.single.package, 'demo_grid_assets');
      expect(
        registry.definitionFor(
          const AssetKey(package: 'nope', kind: AssetKind.hook, id: 'x'),
        ),
        isNull,
      );
    });

    test('artifactFor resolves a leg by its independent identity', () {
      final registry = _registry();
      final agents = registry.artifactFor(
        const AssetArtifactKey(
          asset: _decideKey,
          target: AssetDeliveryTarget.agents,
        ),
      );
      expect(agents, isNotNull);
      expect(agents!.path, 'assets/agents/decide.md');
      expect(
        registry.artifactFor(
          const AssetArtifactKey(
            asset: _decideKey,
            target: AssetDeliveryTarget.station,
          ),
        ),
        isNull,
      );
    });

    test('the SAME instance spreads into Substation.assets and mounts', () {
      final registry = _registry();
      final seen = <String>[];
      final assets = <Seed>[...registry.assets, _ScopeProbe(seen)];
      expect(identical(assets.first, _decide), isTrue);
      _mount(Substation('demo', '/tmp/tg-1w3m-spec', assets: assets));
      expect(seen, <String>['demo']);
    });
  });

  group(
    'teaches declarations are preserved and validated at the pack boundary',
    () {
      test('an omitted teaches list remains empty and legal in a pack', () {
        const brief = GridAssetDefinition(
          assetKey: AssetKey(
            package: 'demo_grid_assets',
            kind: AssetKind.prompt,
            id: 'brief',
          ),
          description: 'Summarize the brief.',
          artifacts: <AssetArtifact>[],
        );

        final pack = GridAssetPackDefinition(
          package: 'demo_grid_assets',
          assets: const <GridAssetDefinition>[brief],
        );

        expect(brief.teaches, isEmpty);
        expect(pack.assets.single.teaches, isEmpty);
      });

      test(
        'a skill teaches list round-trips unchanged through pack and registry',
        () {
          final pack = GridAssetPackDefinition(
            package: 'demo_grid_assets',
            assets: const <GridAssetDefinition>[_decide],
          );
          final registry = GridAssetRegistry(<GridAssetPackDefinition>[pack]);

          expect(
            identical(pack.assets.single.teaches, _decide.teaches),
            isTrue,
          );
          expect(
            identical(
              registry.definitionFor(_decideKey)!.teaches,
              _decide.teaches,
            ),
            isTrue,
          );
          expect(_decide.teaches, <String>['decide']);
        },
      );

      test('a non-skill asset cannot teach a command', () {
        const prompt = GridAssetDefinition(
          assetKey: AssetKey(
            package: 'demo_grid_assets',
            kind: AssetKind.prompt,
            id: 'brief',
          ),
          description: 'Summarize the brief.',
          artifacts: <AssetArtifact>[],
          teaches: <String>['decide'],
        );

        expect(
          () => GridAssetPackDefinition(
            package: 'demo_grid_assets',
            assets: const <GridAssetDefinition>[prompt],
          ),
          throwsA(
            isA<ArgumentError>().having(
              (e) => '${e.message}',
              'message',
              contains(prompt.assetKey.canonical),
            ),
          ),
        );
      });

      test('a skill cannot teach a blank command', () {
        const skill = GridAssetDefinition(
          assetKey: AssetKey(
            package: 'demo_grid_assets',
            kind: AssetKind.skill,
            id: 'blank',
          ),
          description: 'Teach nothing valid.',
          artifacts: <AssetArtifact>[],
          teaches: <String>[''],
        );

        expect(
          () => GridAssetPackDefinition(
            package: 'demo_grid_assets',
            assets: const <GridAssetDefinition>[skill],
          ),
          throwsA(
            isA<ArgumentError>().having(
              (e) => '${e.message}',
              'message',
              contains(skill.assetKey.canonical),
            ),
          ),
        );
      });

      test('a skill can teach only lowercase top-level command names', () {
        for (final invalid in <String>[
          'Decide',
          'decide record',
          'decide/run',
          'decide_record',
          '1decide',
        ]) {
          final skill = GridAssetDefinition(
            assetKey: const AssetKey(
              package: 'demo_grid_assets',
              kind: AssetKind.skill,
              id: 'invalid',
            ),
            description: 'Teach an invalid command.',
            artifacts: const <AssetArtifact>[],
            teaches: <String>[invalid],
          );

          expect(
            () => GridAssetPackDefinition(
              package: 'demo_grid_assets',
              assets: <GridAssetDefinition>[skill],
            ),
            throwsA(
              isA<ArgumentError>().having(
                (e) => '${e.message}',
                'message',
                contains(skill.assetKey.canonical),
              ),
            ),
            reason: 'must reject "$invalid"',
          );
        }
      });

      test('a skill cannot teach the same command twice', () {
        const skill = GridAssetDefinition(
          assetKey: AssetKey(
            package: 'demo_grid_assets',
            kind: AssetKind.skill,
            id: 'duplicate',
          ),
          description: 'Teach one command twice.',
          artifacts: <AssetArtifact>[],
          teaches: <String>['decide', 'decide'],
        );

        expect(
          () => GridAssetPackDefinition(
            package: 'demo_grid_assets',
            assets: const <GridAssetDefinition>[skill],
          ),
          throwsA(
            isA<ArgumentError>().having(
              (e) => '${e.message}',
              'message',
              contains(skill.assetKey.canonical),
            ),
          ),
        );
      });
    },
  );

  group('duplicates refuse LOUD before a partial registry is exposed', () {
    test('a duplicate AssetKey across packs throws', () {
      expect(
        () => GridAssetRegistry(<GridAssetPackDefinition>[
          GridAssetPackDefinition(
            package: 'demo_grid_assets',
            assets: const <GridAssetDefinition>[_decide],
          ),
          GridAssetPackDefinition(
            package: 'demo_grid_assets',
            assets: const <GridAssetDefinition>[_decide],
          ),
        ]),
        throwsA(
          isA<ArgumentError>().having(
            (e) => '${e.message}',
            'message',
            contains('duplicate AssetKey'),
          ),
        ),
      );
    });

    test('a duplicate AssetArtifactKey within one asset throws', () {
      const twoClaudeLegs = GridAssetDefinition(
        assetKey: AssetKey(
          package: 'demo_grid_assets',
          kind: AssetKind.rubric,
          id: 'coherence',
        ),
        description: 'the coherence rubric',
        artifacts: <AssetArtifact>[
          AssetArtifact(target: AssetDeliveryTarget.claude, path: 'a.md'),
          AssetArtifact(target: AssetDeliveryTarget.claude, path: 'b.md'),
        ],
      );
      expect(
        () => GridAssetPackDefinition(
          package: 'demo_grid_assets',
          assets: const <GridAssetDefinition>[twoClaudeLegs],
        ),
        throwsA(
          isA<ArgumentError>().having(
            (e) => '${e.message}',
            'message',
            contains('duplicate AssetArtifactKey'),
          ),
        ),
      );
    });

    test('a pack refuses an asset vended by another package', () {
      expect(
        () => GridAssetPackDefinition(
          package: 'other_grid_assets',
          assets: const <GridAssetDefinition>[_decide],
        ),
        throwsA(
          isA<ArgumentError>().having(
            (e) => '${e.message}',
            'message',
            contains('not by this pack'),
          ),
        ),
      );
    });

    test('an empty pack name refuses', () {
      expect(
        () => GridAssetPackDefinition(
          package: '  ',
          assets: const <GridAssetDefinition>[],
        ),
        throwsA(isA<ArgumentError>()),
      );
    });

    test('an empty registry is legal and empty', () {
      final empty = GridAssetRegistry(const <GridAssetPackDefinition>[]);
      expect(empty.assets, isEmpty);
      expect(empty.packs, isEmpty);
      expect(empty.definitionFor(_decideKey), isNull);
    });
  });

  group('the contract is dependency-neutral', () {
    test('positive control: the gates read the real sources and pubspec', () {
      final sources = _assetSources();
      expect(
        sources.map((f) => f.uri.pathSegments.last).toSet(),
        containsAll(<String>[
          'asset_identity.dart',
          'asset_declaration.dart',
          'asset_registry.dart',
        ]),
        reason:
            'the asset contract sources must be found — vacuousness control',
      );
      expect(
        _directDependencies(),
        containsAll(<String>['genesis_tree', 'grid_engine']),
        reason: 'the pubspec scanner must really parse — vacuousness control',
      );
    });

    test('GridAssetDefinition is FINAL — a pack emits instances, never '
        'subclasses (ADR-0008 Decision 2)', () {
      final declaration = _assetSources().singleWhere(
        (f) => f.path.endsWith('asset_declaration.dart'),
      );
      expect(
        _code(declaration.readAsStringSync()),
        contains('final class GridAssetDefinition extends MultiChildSeed'),
      );
    });

    test('the contract sources reference no I/O, YAML, or pack', () {
      for (final file in _assetSources()) {
        final code = _code(file.readAsStringSync());
        for (final banned in const <String>[
          'dart:io',
          'dart:isolate',
          'package:yaml',
          'package:path/',
          '_grid_assets',
          'package:power',
        ]) {
          expect(
            code.contains(banned),
            isFalse,
            reason:
                '${file.path}: must not reference $banned — discovery, root '
                'probing, and materialization live above this contract',
          );
        }
      }
    });

    test(
      'grid_sdk declares no discovery, YAML, or power_station dependency',
      () {
        final deps = _directDependencies();
        for (final banned in const <String>[
          'yaml',
          'yaml_edit',
          'extension_discovery',
          'package_config',
          'glob',
          'io',
        ]) {
          expect(
            deps,
            isNot(contains(banned)),
            reason: '$banned is discovery/parsing, not a contract dependency',
          );
        }
        expect(
          deps.where(
            (d) => d.endsWith('_grid_assets') || d.startsWith('power'),
          ),
          isEmpty,
          reason:
              'no package in the_grid may import power_station to understand an '
              'asset registry',
        );
      },
    );
  });
}
