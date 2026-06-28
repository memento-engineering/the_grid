// Track E/F — the OPINION-FREE KERNEL invariant (ADR-0007 §1).
//
// The engine holds NO landing / VCS / provider opinion: agents, `claude`, the
// PR opener, the subprocess provider, the git service, and the `.land(` call
// live ONLY in the compiled extension (lib/src/extension/). The kernel, the
// effect core, and the core seeds resolve capabilities through the opaque
// EffectResolver / EffectContext seams and never name a concrete opinion.
//
// This is a structural (grep-the-source) guardrail: it reads every lib/src file
// and fails — naming the offending path — if an opinion literal appears outside
// lib/src/extension/. A pure-Dart, offline test (reads files; no live anything).
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:test/test.dart';

/// The literals that encode a landing / VCS / provider OPINION — none may appear
/// in the engine (everything under lib/src EXCEPT lib/src/extension/).
const _opinionLiterals = <String>[
  // The coding agent the implement capability spawns.
  'claude',
  // The real PR opener (the land capability's only concrete VCS dep).
  'GhPrOpener',
  // The real process transport impl.
  'SubprocessProvider',
  // The real git worktree/land service.
  'StationGitService',
  // The land orchestration call site.
  '.land(',
];

/// Resolves this package's `lib/src` directory, walking up from the test's
/// working dir to find `packages/grid_engine/lib/src` (robust whether the suite
/// runs from the repo root or the package dir).
Directory _libSrc() {
  // Candidate roots: cwd, then cwd/packages/grid_engine, then walk up.
  final candidates = <String>[
    p.join('lib', 'src'),
    p.join('packages', 'grid_engine', 'lib', 'src'),
  ];
  var dir = Directory.current;
  for (var i = 0; i < 6; i++) {
    for (final rel in candidates) {
      final probe = Directory(p.join(dir.path, rel));
      if (probe.existsSync() &&
          File(p.join(probe.path, 'kernel', 'station_kernel.dart')).existsSync()) {
        return probe;
      }
    }
    final parent = dir.parent;
    if (parent.path == dir.path) break;
    dir = parent;
  }
  fail('could not locate packages/grid_engine/lib/src from ${Directory.current.path}');
}

void main() {
  group('the engine is opinion-free (ADR-0007 §1)', () {
    final libSrc = _libSrc();
    final extensionDir =
        p.normalize(p.join(libSrc.path, 'extension')) + p.separator;

    final engineFiles = libSrc
        .listSync(recursive: true)
        .whereType<File>()
        .where((f) => f.path.endsWith('.dart'))
        // ONLY lib/src/extension/ may carry the opinion literals.
        .where((f) => !p.normalize(f.path).startsWith(extensionDir))
        .toList();

    test('the kernel, effect core, and core seeds reference NO opinion literal',
        () {
      expect(
        engineFiles,
        isNotEmpty,
        reason: 'sanity: the engine files were found',
      );
      final offences = <String>[];
      for (final file in engineFiles) {
        final source = file.readAsStringSync();
        for (final literal in _opinionLiterals) {
          if (source.contains(literal)) {
            offences.add(
              '${p.relative(file.path, from: libSrc.path)} references "$literal"',
            );
          }
        }
      }
      expect(
        offences,
        isEmpty,
        reason:
            'opinion literals must live ONLY in lib/src/extension/ — the engine '
            'holds no landing/VCS/provider opinion:\n  ${offences.join('\n  ')}',
      );
    });

    test('the extension DOES carry the opinions (the test is meaningful)', () {
      final extensionFiles = Directory(p.join(libSrc.path, 'extension'))
          .listSync(recursive: true)
          .whereType<File>()
          .where((f) => f.path.endsWith('.dart'))
          .toList();
      final allExtensionSource =
          extensionFiles.map((f) => f.readAsStringSync()).join('\n');
      // The compiled `code` extension's capabilities spawn `claude` and drive
      // the land orchestration — proving the literals exist SOMEWHERE, so the
      // engine-is-clean assertion above is not vacuously true.
      expect(allExtensionSource, contains('claude'));
    });
  });
}
