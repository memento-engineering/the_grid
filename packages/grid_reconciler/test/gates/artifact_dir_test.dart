import 'dart:io';

import 'package:grid_reconciler/src/gates/artifact_dir.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

import 'support/script_fixtures.dart';

/// Artifact-dir helpers (gates-exec.md §10, artifact.go). `artifactDirFor` is
/// the live `GC_ARTIFACT_DIR` source; ensure/validate are ported because
/// `artifact_test.go` specs them, though gc doesn't wire them into the live
/// gate path.
void main() {
  group('artifactDirFor (template.go:23-25)', () {
    test('format is <cityPath>/.gc/artifacts/<beadID>/iter-<N>', () {
      expect(
        artifactDirFor('/city', 'bead-1', 3),
        p.join('/city', '.gc', 'artifacts', 'bead-1', 'iter-3'),
      );
    });
  });

  group('ensureArtifactDir', () {
    late ScriptFixtures fx;
    setUp(() => fx = ScriptFixtures.create());
    tearDown(() => fx.dispose());

    test('creates the dir tree and returns the path', () {
      final dir = ensureArtifactDir(fx.root.path, 'bead-1', 2);
      expect(Directory(dir).existsSync(), isTrue);
      expect(dir, endsWith(p.join('artifacts', 'bead-1', 'iter-2')));
    });
  });

  group('validateArtifactDir (artifact.go:28-69)', () {
    late ScriptFixtures fx;
    setUp(() => fx = ScriptFixtures.create());
    tearDown(() => fx.dispose());

    test('regular files and dirs are allowed', () {
      final dir = fx.mkdir('artifacts');
      fx.writeFile('artifacts/log.txt', 'hi');
      fx.mkdir('artifacts/sub');
      expect(() => validateArtifactDir(dir), returnsNormally);
    });

    test('a symlink resolving INSIDE the root is allowed', () {
      final dir = fx.mkdir('artifacts');
      final target = fx.writeFile('artifacts/real.txt', 'hi');
      fx.symlink('artifacts/link.txt', target);
      expect(() => validateArtifactDir(dir), returnsNormally);
    });

    test('a symlink escaping the root is rejected', () {
      final dir = fx.mkdir('artifacts');
      final outside = fx.writeFile('outside.txt', 'secret');
      fx.symlink('artifacts/escape.txt', outside);
      expect(
        () => validateArtifactDir(dir),
        throwsA(isA<ArtifactDirException>()),
      );
    });
  });
}
