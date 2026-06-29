/// The Packaged-AI-Assets loader (M5 "The Circuit" Track D / D-9).
///
/// Loads the committee's rubric prose + critic prompt template from the on-disk
/// `extension/` assets authored in the Dart/Flutter "Packaged AI Assets" format
/// (per flutter.dev/go/packaged-ai-assets — the `package:extension_discovery`
/// `extension/mcp/config.yaml` shape). The active prompt path is composed in Dart
/// (`CriticCapability.buildCriticPrompt`) using [loadRubric] as its rubric
/// source; [renderCriticPrompt] is the standalone, format-faithful renderer of
/// the `prompts/critic.md` template (the portable mirror).
///
/// Asset resolution walks up from the cwd to the package's own `extension/` dir
/// (works from the repo root or the package dir, like the structural fence's
/// walk). The live-arm `package:` URI resolution is a follow-up — the assets ship
/// inside the package.
library;

import 'dart:io';

import 'package:grid_controller/grid_controller.dart';
import 'package:path/path.dart' as p;

/// Loads grid_assets' bundled rubric/prompt assets from `extension/`.
class PackagedAssetLoader {
  /// Creates a loader. [root] explicitly points at the `extension/` dir (tests
  /// inject it); absent ⇒ the dir is discovered by walking up from the cwd.
  PackagedAssetLoader({String? root}) : _explicitRoot = root;

  final String? _explicitRoot;

  /// The resolved `extension/` directory (discovered once, lazily).
  late final String _root = _explicitRoot ?? _discoverRoot();

  /// The prose bands for [rubricId] (`extension/rubrics/<id>.md`). Throws an
  /// [ArgumentError] for an unknown rubric (fail-loud — a missing rubric is a
  /// packaging bug, never a silent empty prompt).
  String loadRubric(String rubricId) {
    final file = File(p.join(_root, 'rubrics', '$rubricId.md'));
    if (!file.existsSync()) {
      throw ArgumentError('unknown rubric "$rubricId" (no ${file.path})');
    }
    return file.readAsStringSync().trim();
  }

  /// The mustache-templated prompt body for [promptId] (`extension/prompts/<id>.md`).
  String loadPromptTemplate(String promptId) {
    final file = File(p.join(_root, 'prompts', '$promptId.md'));
    if (!file.existsSync()) {
      throw ArgumentError('unknown prompt "$promptId" (no ${file.path})');
    }
    return file.readAsStringSync();
  }

  /// Renders the `critic` prompt template for [rubricId] + [bead] — substitutes
  /// `{{rubric}}`, `{{rubricText}}` (the loaded rubric bands), and `{{bead}}` (the
  /// full work bead). The format-faithful mirror of `buildCriticPrompt`.
  String renderCriticPrompt(String rubricId, Bead bead) => _mustache(
    loadPromptTemplate('critic'),
    {
      'rubric': rubricId,
      'rubricText': loadRubric(rubricId),
      'bead': beadBlock(bead),
    },
  );

  /// A `RubricSource` tear-off bound to this loader (wire into `CriticCapability`).
  String Function(String) get rubricSource => loadRubric;

  /// Substitutes every `{{key}}` in [template] from [vars] (a tiny, dependency-
  /// free mustache for flat string args — the only templating D-9 needs now).
  static String _mustache(String template, Map<String, String> vars) {
    var out = template;
    vars.forEach((key, value) => out = out.replaceAll('{{$key}}', value));
    return out;
  }

  /// Renders the full work [bead] into a prompt block (title/task/design/
  /// acceptance/notes) — the `{{bead}}` substitution.
  static String beadBlock(Bead bead) {
    final title = bead.title.isNotEmpty ? bead.title : 'work bead ${bead.id}';
    final b = StringBuffer()..writeln('`${bead.id}` — $title');
    void section(String heading, String body) {
      if (body.trim().isEmpty) return;
      b
        ..writeln()
        ..writeln('### $heading')
        ..writeln(body.trim());
    }

    section('Task', bead.description);
    section('Design', bead.design);
    section('Acceptance criteria', bead.acceptanceCriteria);
    section('Notes', bead.notes);
    return b.toString().trimRight();
  }

  /// Walks up from the cwd to locate this package's `extension/` dir — robust
  /// whether the suite/process runs from the repo root or the package dir
  /// (mirrors the structural fence's `_libSrc` walk).
  static String _discoverRoot() {
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
    throw StateError(
      'could not locate packages/grid_assets/extension from '
      '${Directory.current.path}',
    );
  }
}
