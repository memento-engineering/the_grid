// Track D — the Packaged-AI-Assets loader (M5 "The Circuit" / D-9).
//
// The committee's rubric prose + critic prompt template ship on disk in the
// Dart/Flutter "Packaged AI Assets" format (`extension/mcp/config.yaml` +
// `extension/rubrics/*.md` + `extension/prompts/critic.md`). This proves the
// [PackagedAssetLoader] reads them faithfully: every committee rubric loads to
// non-empty prose that names itself, an unknown rubric fails loud, the critic
// prompt renders with no leftover mustache holes, and the manifest declares the
// same four rubrics + the critic prompt (parsed as REAL yaml, not string-matched).
//
// Offline only — reads bundled files from a temp-free `extension/` dir resolved
// by walking up from the cwd; no live anything.
import 'dart:io';

import 'package:grid_assets/grid_assets.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';
import 'package:yaml/yaml.dart';

import 'support/asset_fakes.dart';

/// Resolves this package's `extension/` dir by walking up from the cwd (robust
/// whether the suite runs from the repo root or the package dir — the same walk
/// the loader + the structural fence use). Used to pin an explicit loader [root]
/// and to read the manifest from the SAME dir, so both never disagree on cwd.
String _extensionDir() {
  final candidates = <String>[
    'extension',
    p.join('packages', 'grid_assets', 'extension'),
  ];
  var dir = Directory.current;
  for (var i = 0; i < 6; i++) {
    for (final rel in candidates) {
      final probe = Directory(p.join(dir.path, rel));
      if (probe.existsSync() &&
          Directory(p.join(probe.path, 'rubrics')).existsSync()) {
        return probe.path;
      }
    }
    final parent = dir.parent;
    if (parent.path == dir.path) break;
    dir = parent;
  }
  fail('could not locate packages/grid_assets/extension from '
      '${Directory.current.path}');
}

void main() {
  final root = _extensionDir();
  final loader = PackagedAssetLoader(root: root);

  group('PackagedAssetLoader — the committee rubrics', () {
    for (final rubricId in kCommitteeRubrics) {
      test('loadRubric("$rubricId") returns non-empty prose that names itself',
          () {
        final text = loader.loadRubric(rubricId);
        expect(text, isNotEmpty);
        // The rubric's own heading names it — a mis-wired path that loaded the
        // wrong file would not contain the lane's id.
        expect(text, contains(rubricId));
      });
    }

    test('an unknown rubric throws (fail-loud — a packaging bug, never a silent '
        'empty prompt)', () {
      expect(() => loader.loadRubric('does-not-exist'), throwsArgumentError);
    });
  });

  group('PackagedAssetLoader — renderCriticPrompt', () {
    test('substitutes every hole (no `{{` survives) and embeds the bead + the '
        'rubric bands', () {
      final review = bead('tg-1').copyWith(
        title: 'Wire the federation bus',
        description: 'Connect The Studio to The Dashboard.',
      );
      final prompt = loader.renderCriticPrompt('spec-adherence', review);

      // No mustache hole leaked through (a missing var would print `{{...}}`).
      expect(prompt, isNot(contains('{{')));
      // The lane it grades.
      expect(prompt, contains('spec-adherence'));
      // The full work bead under review (the load-bearing review input).
      expect(prompt, contains('tg-1'));
      expect(prompt, contains('Wire the federation bus'));
      expect(prompt, contains('Connect The Studio to The Dashboard.'));
      // The rubric bands themselves — the `{{rubricText}}` substitution carried
      // the loaded prose, not a placeholder.
      expect(prompt, contains('Bands'));
      expect(prompt, contains(loader.loadRubric('spec-adherence')));
    });
  });

  group('extension/mcp/config.yaml — the Packaged-AI-Assets manifest', () {
    final manifest = File(p.join(root, 'mcp', 'config.yaml'));

    test('exists', () {
      expect(manifest.existsSync(), isTrue, reason: 'the manifest must ship');
    });

    test('declares all four rubric resources + the critic prompt, each with a '
        'visibility (parsed as real yaml)', () {
      final doc = loadYaml(manifest.readAsStringSync()) as YamlMap;

      // Resources: one per committee lane, each with id + visibility.
      final resources = (doc['resources'] as YamlList).cast<YamlMap>();
      final resourceIds = {for (final r in resources) r['id'] as String};
      expect(
        resourceIds,
        containsAll(kCommitteeRubrics),
        reason: 'every committee rubric is declared as a resource',
      );
      for (final r in resources) {
        expect(
          r['visibility'],
          isNotNull,
          reason: 'resource ${r['id']} declares a visibility',
        );
      }

      // Prompts: the single `critic` prompt, with a visibility.
      final prompts = (doc['prompts'] as YamlList).cast<YamlMap>();
      final critic = prompts.firstWhere(
        (pr) => pr['id'] == 'critic',
        orElse: () => fail('the `critic` prompt must be declared'),
      );
      expect(critic['visibility'], isNotNull,
          reason: 'the critic prompt declares a visibility');
    });
  });
}
