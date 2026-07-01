// The grid.dart domain config prototype (SCRATCH-pub-capability-and-repo-split)
// — the FIRST "domains serialize their own information" instance, so these
// tests pin the PRECEDENT: the versioned envelope codec (fail-closed), the pure
// context-application (pubspec_overrides.yaml derivation), the UI-drivable
// service layer, and the thin exported Command. Offline: temp dirs only; no
// live bd/pub/network; the_grid only READS work-bead metadata (A37).
import 'dart:convert';
import 'dart:io';

import 'package:args/command_runner.dart';
import 'package:grid_assets/grid_assets.dart';
import 'package:test/test.dart';

/// A work-bead metadata map carrying a grid.dart envelope with [links].
Map<String, dynamic> _metadataWith(
  List<PubLink> links, {
  String version = kDartAssetsVersion,
  String? packsVersion,
}) => {
  'validation_plan': 'dart test', // neighbors survive untouched (merge model)
  kDartDomainKey: {
    'assets_version': version,
    if (packsVersion != null) 'packs_version': packsVersion,
    'payload': {
      'pub': PubLinkConfig(links: links).toJson(),
    },
  },
};

const _genesisLink = PubLink(
  package: 'genesis_tree',
  devPath: '../genesis/packages/tree',
  hosted: '^0.1.3',
);

void main() {
  group('the grid.dart envelope codec (versioned, fail-closed)', () {
    test('round-trips through the envelope shape', () {
      const config = DartDomainConfig(
        pub: PubLinkConfig(links: [_genesisLink]),
        packsVersion: 'gc-1',
      );
      final metadata = <String, dynamic>{
        kDartDomainKey: config.toEnvelope(),
      };
      final result = decodeDartEnvelope(metadata);
      expect(result, isA<DartEnvelopeDecoded>());
      expect((result as DartEnvelopeDecoded).config, config);
      // The envelope is stamped with THIS pack's version.
      expect(
        (metadata[kDartDomainKey] as Map<String, Object?>)['assets_version'],
        kDartAssetsVersion,
      );
    });

    test('no grid.dart key → Absent (the common case, not an error)', () {
      expect(
        decodeDartEnvelope({'gc.some_key': 'x'}),
        isA<DartEnvelopeAbsent>(),
      );
    });

    test('an envelope written by an INCOMPATIBLE pack is refused whole '
        '(fail-closed — never a partial parse of a newer shape)', () {
      final result = decodeDartEnvelope(
        _metadataWith([_genesisLink], version: '0.1.0'),
      );
      expect(result, isA<DartEnvelopeIncompatible>());
      expect((result as DartEnvelopeIncompatible).version, '0.1.0');
    });

    test('pre-1.0 minor is BREAKING; 1.x major gates compatibility', () {
      expect(isCompatibleAssetsVersion(kDartAssetsVersion), isTrue);
      expect(isCompatibleAssetsVersion('0.0.9'), isTrue,
          reason: 'same 0.0 minor — patch is compatible (additive-only rule)');
      expect(isCompatibleAssetsVersion('0.1.0'), isFalse,
          reason: 'pre-1.0 minor bump is breaking (pub semantics)');
      expect(isCompatibleAssetsVersion('1.0.0'), isFalse);
      expect(isCompatibleAssetsVersion('garbage'), isFalse,
          reason: 'unparseable → incompatible (fail-closed)');
      expect(isCompatibleAssetsVersion('0.-1.0'), isFalse,
          reason: 'negative components are not semver — fail-closed');
      expect(isCompatibleAssetsVersion('1.-1.0'), isFalse,
          reason: 'a negative component must never slip a major gate');
    });

    test('malformed envelopes are refused with a reason (never applied)', () {
      expect(
        decodeDartEnvelope({kDartDomainKey: 'not-an-object'}),
        isA<DartEnvelopeMalformed>(),
      );
      expect(
        decodeDartEnvelope({
          kDartDomainKey: {'payload': <String, Object?>{}},
        }),
        isA<DartEnvelopeMalformed>(),
        reason: 'missing assets_version',
      );
      expect(
        decodeDartEnvelope({
          kDartDomainKey: {'assets_version': kDartAssetsVersion},
        }),
        isA<DartEnvelopeMalformed>(),
        reason: 'missing payload',
      );
      expect(
        decodeDartEnvelope({
          kDartDomainKey: {
            'assets_version': kDartAssetsVersion,
            'payload': {
              'pub': {
                'links': [
                  {'dev_path': '/x'}, // no package name
                ],
              },
            },
          },
        }),
        isA<DartEnvelopeMalformed>(),
        reason: 'a link without a package is malformed, not skipped',
      );
      expect(
        decodeDartEnvelope({
          kDartDomainKey: {
            'assets_version': kDartAssetsVersion,
            'payload': {
              'pub': {
                'links': [123], // a non-object entry
              },
            },
          },
        }),
        isA<DartEnvelopeMalformed>(),
        reason: 'a non-object link entry is malformed (explicitly, not via an '
            'implicit cast error)',
      );
      expect(
        decodeDartEnvelope({
          kDartDomainKey: {
            'assets_version': kDartAssetsVersion,
            'payload': {
              'pub': {
                'links': [
                  {'package': 'bad: name #!', 'dev_path': '/x'},
                ],
              },
            },
          },
        }),
        isA<DartEnvelopeMalformed>(),
        reason: 'a YAML-hostile "package name" is refused at DECODE, so it can '
            'never reach the overrides emitter',
      );
    });
  });

  group('pubspecOverridesFor — the pure context application', () {
    const config = PubLinkConfig(links: [_genesisLink]);

    test('stable → null (no overrides; the pubspec pins stand)', () {
      expect(pubspecOverridesFor(config, PubLinkContext.stable), isNull);
    });

    test('dev → the declared (relative) path as-is (single-quoted scalar)', () {
      final yaml = pubspecOverridesFor(config, PubLinkContext.dev);
      expect(yaml, contains('genesis_tree:'));
      expect(yaml, contains("path: '../genesis/packages/tree'"));
      expect(yaml, startsWith('# Generated by the grid.dart domain'));
    });

    test('worktree ABSOLUTIZES a relative path against devRoot (normalized) — '
        'the genesis_tree deep-worktree fix', () {
      final yaml = pubspecOverridesFor(
        config,
        PubLinkContext.worktree,
        devRoot: '/Users/nico/development/engineering.memento/the_grid',
      );
      expect(
        yaml,
        contains(
          "path: '/Users/nico/development/engineering.memento/genesis/"
          "packages/tree'",
        ),
        reason: 'the ../ collapses through normalize — an absolute path '
            'resolves from ANY worktree depth',
      );
    });

    test('worktree with an ABSOLUTE declaration passes through untouched', () {
      const abs = PubLinkConfig(links: [
        PubLink(package: 'genesis_tree', devPath: '/abs/genesis/packages/tree'),
      ]);
      final yaml = pubspecOverridesFor(abs, PubLinkContext.worktree);
      expect(yaml, contains("path: '/abs/genesis/packages/tree'"));
    });

    test('worktree + relative + NO devRoot throws (fail-closed — a broken '
        'override is worse than none)', () {
      expect(
        () => pubspecOverridesFor(config, PubLinkContext.worktree),
        throwsA(isA<StateError>()),
      );
    });

    test('worktree + relative + a RELATIVE devRoot throws too (absolutizing '
        'against a relative root yields a still-broken override)', () {
      expect(
        () => pubspecOverridesFor(
          config,
          PubLinkContext.worktree,
          devRoot: 'the_grid', // relative — would emit a relative "override"
        ),
        throwsA(isA<StateError>()),
      );
    });

    test('YAML-hostile paths survive via single-quoting (spaces, colon-space, '
        'hash, embedded quote)', () {
      const hostile = PubLinkConfig(links: [
        PubLink(
          package: 'genesis_tree',
          devPath: "/Users/nico/My Documents: a #dir/it's here",
        ),
      ]);
      final yaml = pubspecOverridesFor(hostile, PubLinkContext.dev)!;
      expect(
        yaml,
        contains("path: '/Users/nico/My Documents: a #dir/it''s here'"),
        reason: 'single-quoted scalar; embedded quote doubled per YAML spec',
      );
    });

    test('no dev links → null in every non-stable context too', () {
      const pinsOnly = PubLinkConfig(links: [
        PubLink(package: 'genesis_tree', hosted: '^0.1.3'),
      ]);
      expect(pubspecOverridesFor(pinsOnly, PubLinkContext.dev), isNull);
      expect(pubspecOverridesFor(const PubLinkConfig(), PubLinkContext.dev),
          isNull);
    });

    test('deterministic: links emit sorted by package', () {
      const two = PubLinkConfig(links: [
        PubLink(package: 'zeta', devPath: '/z'),
        PubLink(package: 'alpha', devPath: '/a'),
      ]);
      final yaml = pubspecOverridesFor(two, PubLinkContext.dev)!;
      expect(yaml.indexOf('alpha:'), lessThan(yaml.indexOf('zeta:')));
    });
  });

  group('DartLinkService — the UI-drivable lib layer (temp dirs)', () {
    late Directory temp;

    setUp(() async {
      temp = await Directory.systemTemp.createTemp('grid-dart-link-');
    });

    tearDown(() async {
      if (temp.existsSync()) await temp.delete(recursive: true);
    });

    File overridesFile() => File('${temp.path}/$kPubspecOverridesFile');

    test('applies a dev link: writes pubspec_overrides.yaml at the workspace '
        'root', () async {
      final outcome = await const DartLinkService().apply(
        metadata: _metadataWith(const [_genesisLink]),
        context: PubLinkContext.dev,
        workspaceDir: temp.path,
      );
      expect(outcome, isA<LinkApplied>());
      expect((outcome as LinkApplied).packages, ['genesis_tree']);
      expect(overridesFile().existsSync(), isTrue);
      expect(
        overridesFile().readAsStringSync(),
        contains("path: '../genesis/packages/tree'"),
      );
    });

    test('stable clears a previously GENERATED overrides file', () async {
      const service = DartLinkService();
      await service.apply(
        metadata: _metadataWith(const [_genesisLink]),
        context: PubLinkContext.dev,
        workspaceDir: temp.path,
      );
      expect(overridesFile().existsSync(), isTrue);

      final outcome = await service.apply(
        metadata: _metadataWith(const [_genesisLink]),
        context: PubLinkContext.stable,
        workspaceDir: temp.path,
      );
      expect(outcome, isA<LinkCleared>());
      expect((outcome as LinkCleared).removed, isTrue);
      expect(overridesFile().existsSync(), isFalse);
    });

    test('NEVER deletes a hand-authored pubspec_overrides.yaml (only the '
        'generated marker is removable)', () async {
      overridesFile().writeAsStringSync(
        'dependency_overrides:\n  mine:\n    path: ../mine\n',
      );
      final outcome = await const DartLinkService().apply(
        metadata: _metadataWith(const [_genesisLink]),
        context: PubLinkContext.stable,
        workspaceDir: temp.path,
      );
      expect((outcome as LinkCleared).removed, isFalse);
      expect(overridesFile().existsSync(), isTrue,
          reason: 'a file this domain did not generate is left alone');
    });

    test('no grid.dart config → touches nothing', () async {
      final outcome = await const DartLinkService().apply(
        metadata: const {'gc.other': 'x'},
        context: PubLinkContext.dev,
        workspaceDir: temp.path,
      );
      expect(outcome, isA<LinkNoConfig>());
      expect(overridesFile().existsSync(), isFalse);
    });

    test('an incompatible envelope is REFUSED and touches nothing '
        '(fail-closed)', () async {
      final outcome = await const DartLinkService().apply(
        metadata: _metadataWith(const [_genesisLink], version: '9.9.9'),
        context: PubLinkContext.dev,
        workspaceDir: temp.path,
      );
      expect(outcome, isA<LinkRefused>());
      expect((outcome as LinkRefused).reason, contains('9.9.9'));
      expect(overridesFile().existsSync(), isFalse);
    });

    test('worktree + relative + no devRoot is REFUSED (not thrown, not '
        'written)', () async {
      final outcome = await const DartLinkService().apply(
        metadata: _metadataWith(const [_genesisLink]),
        context: PubLinkContext.worktree,
        workspaceDir: temp.path,
      );
      expect(outcome, isA<LinkRefused>());
      expect(overridesFile().existsSync(), isFalse);
    });

    test('the genesis_tree scenario end-to-end: a worktree apply yields the '
        'absolute-path override pub needs at any depth', () async {
      // The station's root checkout + a deep per-bead "worktree" under it.
      final devRoot = Directory('${temp.path}/the_grid')..createSync();
      final worktree = Directory(
        '${temp.path}/the_grid/.grid/worktrees/tg/tg-abc',
      )..createSync(recursive: true);

      final outcome = await const DartLinkService().apply(
        metadata: _metadataWith(const [_genesisLink]),
        context: PubLinkContext.worktree,
        workspaceDir: worktree.path,
        devRoot: devRoot.path,
      );
      expect(outcome, isA<LinkApplied>());
      final yaml =
          File('${worktree.path}/$kPubspecOverridesFile').readAsStringSync();
      expect(yaml, contains("path: '${temp.path}/genesis/packages/tree'"),
          reason: 'the ../genesis declaration absolutized against the dev '
              'root — resolvable from the deep worktree');
    });

    test('a RELATIVE devRoot is REFUSED by the service (fail-closed, not a '
        'silently relative override)', () async {
      final outcome = await const DartLinkService().apply(
        metadata: _metadataWith(const [_genesisLink]),
        context: PubLinkContext.worktree,
        workspaceDir: temp.path,
        devRoot: 'the_grid',
      );
      expect(outcome, isA<LinkRefused>());
      expect(overridesFile().existsSync(), isFalse);
    });
  });

  group('DartCommand / dart link — the THIN exported Command', () {
    late Directory temp;

    setUp(() async {
      temp = await Directory.systemTemp.createTemp('grid-dart-cmd-');
    });

    tearDown(() async {
      if (temp.existsSync()) await temp.delete(recursive: true);
    });

    test('link is a subcommand of the dart umbrella (Pub subordinate to '
        'Dart)', () {
      final cmd = DartCommand();
      expect(cmd.name, 'dart');
      expect(cmd.subcommands.keys, contains('link'));
    });

    test('parses flags and delegates to the service end-to-end (offline)',
        () async {
      final metadataFile = File('${temp.path}/bead-metadata.json')
        ..writeAsStringSync(jsonEncode(_metadataWith(const [_genesisLink])));

      final runner = CommandRunnerish();
      final code = await runner.run([
        'dart',
        'link',
        '--metadata',
        metadataFile.path,
        '--context',
        'dev',
        '--dir',
        temp.path,
      ]);
      expect(code, 0);
      expect(
        File('${temp.path}/$kPubspecOverridesFile').existsSync(),
        isTrue,
      );
    });

    test('a refused envelope exits 1 (fail-closed surfaces)', () async {
      final metadataFile = File('${temp.path}/bead-metadata.json')
        ..writeAsStringSync(
          jsonEncode(_metadataWith(const [_genesisLink], version: '9.9.9')),
        );
      final code = await CommandRunnerish().run([
        'dart',
        'link',
        '--metadata',
        metadataFile.path,
        '--context',
        'dev',
        '--dir',
        temp.path,
      ]);
      expect(code, 1);
    });

    test('a missing metadata file exits 64 (usage)', () async {
      final code = await CommandRunnerish().run([
        'dart',
        'link',
        '--metadata',
        '${temp.path}/nope.json',
        '--context',
        'dev',
        '--dir',
        temp.path,
      ]);
      expect(code, 64);
    });
  });
}

/// A minimal runner hosting [DartCommand] exactly the way a station app would
/// (`..addCommand(DartCommand())` — the assembles-the-Commands-it-wants model).
class CommandRunnerish {
  Future<int> run(List<String> args) async {
    final runner = CommandRunner<int>('t', 'test station')
      ..addCommand(DartCommand());
    return await runner.run(args) ?? 0;
  }
}
