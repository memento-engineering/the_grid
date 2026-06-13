import 'dart:io';

import 'package:grid_reconciler/src/gates/condition_path.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

import 'support/script_fixtures.dart';

/// Path resolution + the traversal/symlink containment defenses
/// (gates-exec.md §2, conformance-gate-tests §3.3 `TestResolveConditionPath`).
///
/// These touch the real filesystem (temp dirs, symlinks, stat) but spawn **no**
/// subprocess, so they belong in the offline suite — they are the
/// SECURITY-CRITICAL containment gate. macOS `/tmp → /private/tmp` is exactly
/// why the resolver canonicalizes roots; `expectSameFile` canonicalizes both
/// sides to compare like gc's `AssertSamePath`.
void main() {
  late ScriptFixtures fx;

  setUp(() => fx = ScriptFixtures.create());
  tearDown(() => fx.dispose());

  // Canonicalize both sides for comparison (gc's AssertSamePath / §1.9 step 10).
  void expectSameFile(String actual, String expected) {
    expect(
      File(actual).resolveSymbolicLinksSync(),
      File(expected).resolveSymbolicLinksSync(),
    );
  }

  ConditionPathError errorKindOf(void Function() body) {
    try {
      body();
    } on ConditionPathException catch (e) {
      return e.kind;
    }
    fail('expected ConditionPathException');
  }

  group('accepted paths', () {
    test(
      'absolute path resolves; envelope/base unrelated (containment skipped)',
      () {
        final script = fx.writeScript('check.sh', shScript(<String>['exit 0']));
        final resolved = resolveConditionPath(
          '/some/city',
          '/some/city',
          script,
        );
        expectSameFile(resolved, script);
      },
    );

    test('relative path under base resolves', () {
      final script = fx.writeScript(
        'gates/check.sh',
        shScript(<String>['exit 0']),
      );
      final resolved = resolveConditionPath(
        fx.root.path,
        fx.root.path,
        'gates/check.sh',
      );
      expectSameFile(resolved, script);
    });

    test('symlink under root resolves to its target', () {
      final target = fx.writeScript('real.sh', shScript(<String>['exit 0']));
      fx.symlink('link.sh', target);
      final resolved = resolveConditionPath(
        fx.root.path,
        fx.root.path,
        'link.sh',
      );
      expectSameFile(resolved, target);
    });

    test('empty base falls back to envelope', () {
      final script = fx.writeScript(
        'gates/check.sh',
        shScript(<String>['exit 0']),
      );
      final resolved = resolveConditionPath(fx.root.path, '', 'gates/check.sh');
      expectSameFile(resolved, script);
    });

    test(
      'absolute path OUTSIDE both roots is accepted (callers vouch, §5 gap 6)',
      () {
        // Script in a sibling tree; envelope/base point at an unrelated dir.
        final outside = fx.writeScript(
          'outside/tool.sh',
          shScript(<String>['exit 0']),
        );
        final city = fx.mkdir('city');
        final resolved = resolveConditionPath(city, city, outside);
        expectSameFile(resolved, outside);
      },
    );
  });

  group('rig-scoped envelope/base split (gascity#2320/#2354)', () {
    test('relative path escapes base but stays inside envelope → resolves', () {
      // envelope=city, base=city/frontend; script at city/scripts/check.sh.
      final city = fx.mkdir('city');
      final base = fx.mkdir('city/frontend');
      final script = fx.writeScript(
        'city/scripts/check.sh',
        shScript(<String>['exit 0']),
      );
      final resolved = resolveConditionPath(city, base, '../scripts/check.sh');
      expectSameFile(resolved, script);
    });

    test('traversal outside both envelope and base → rejected', () {
      final city = fx.mkdir('city');
      final base = fx.mkdir('city/frontend');
      fx.writeScript('outside.sh', shScript(<String>['exit 0']));
      expect(
        errorKindOf(() => resolveConditionPath(city, base, '../../outside.sh')),
        ConditionPathError.traversal,
      );
    });

    test(
      'sibling layout: relative path under base (outside envelope) resolves',
      () {
        // envelope=parent/city, base=parent/rig (siblings).
        final envelope = fx.mkdir('parent/city');
        final base = fx.mkdir('parent/rig');
        final script = fx.writeScript(
          'parent/rig/assets/pack/scripts/check.sh',
          shScript(<String>['exit 0']),
        );
        final resolved = resolveConditionPath(
          envelope,
          base,
          'assets/pack/scripts/check.sh',
        );
        expectSameFile(resolved, script);
      },
    );

    test('sibling layout: traversal outside both → rejected', () {
      final envelope = fx.mkdir('parent/city');
      final base = fx.mkdir('parent/rig');
      fx.writeScript('parent/evil.sh', shScript(<String>['exit 0']));
      expect(
        errorKindOf(() => resolveConditionPath(envelope, base, '../evil.sh')),
        ConditionPathError.traversal,
      );
    });
  });

  group('rejections', () {
    test('../outside escape → traversal error', () {
      fx.writeScript('outside.sh', shScript(<String>['exit 0']));
      final dir = fx.mkdir('dir');
      expect(
        errorKindOf(() => resolveConditionPath(dir, dir, '../outside.sh')),
        ConditionPathError.traversal,
      );
    });

    test('empty conditionPath → emptyPath error', () {
      expect(
        errorKindOf(() => resolveConditionPath(fx.root.path, fx.root.path, '')),
        ConditionPathError.emptyPath,
      );
    });

    test('empty envelope → emptyEnvelope error (NOT "no check")', () {
      expect(
        errorKindOf(() => resolveConditionPath('', fx.root.path, 'x.sh')),
        ConditionPathError.emptyEnvelope,
      );
    });

    test(
      'nonexistent relative file → resolveFailure (fails at EvalSymlinks)',
      () {
        final dir = fx.mkdir('dir');
        expect(
          errorKindOf(() => resolveConditionPath(dir, dir, 'nope.sh')),
          ConditionPathError.resolveFailure,
        );
      },
    );

    test('nonexistent absolute file → resolveFailure', () {
      expect(
        errorKindOf(
          () => resolveConditionPath('/city', '/city', '/nonexistent/file.sh'),
        ),
        ConditionPathError.resolveFailure,
      );
    });

    test('symlink under base targeting outside both roots → symlinkEscape', () {
      // rig/scripts/check.sh -> parent/outside.sh; relative path passes the
      // PRE-check (lexically inside base) but the POST-check rejects the
      // resolved target (condition.go:244-248).
      final envelope = fx.mkdir('parent/city');
      final base = fx.mkdir('parent/rig');
      final outside = fx.writeScript(
        'parent/outside.sh',
        shScript(<String>['exit 0']),
      );
      fx.mkdir('parent/rig/scripts');
      fx.symlink('parent/rig/scripts/check.sh', outside);
      expect(
        errorKindOf(
          () => resolveConditionPath(envelope, base, 'scripts/check.sh'),
        ),
        ConditionPathError.symlinkEscape,
      );
    });

    test('resolved path is a directory → notRegularFile (§5 gap 6)', () {
      fx.mkdir('gates/subdir');
      expect(
        errorKindOf(
          () =>
              resolveConditionPath(fx.root.path, fx.root.path, 'gates/subdir'),
        ),
        ConditionPathError.notRegularFile,
      );
    });

    test('mode 0644 (no exec bit) → notExecutable (§5 gap 6)', () {
      fx.writeFile('plain.sh', shScript(<String>['exit 0']));
      expect(
        errorKindOf(
          () => resolveConditionPath(fx.root.path, fx.root.path, 'plain.sh'),
        ),
        ConditionPathError.notExecutable,
      );
    });

    test('absolute symlink escape IS allowed (absolute skips containment)', () {
      // An ABSOLUTE path to a symlink pointing outside is accepted — absolute
      // paths skip both containment checks (callers vouch). Pin the contract.
      final target = fx.writeScript(
        'out/real.sh',
        shScript(<String>['exit 0']),
      );
      final city = fx.mkdir('city');
      final link = fx.symlink('city/link.sh', target);
      // Pass the link by ABSOLUTE path → containment skipped, resolves to target.
      final resolved = resolveConditionPath(city, city, link);
      expectSameFile(resolved, target);
    });
  });

  group('trusted-absolute-roots boundary (ralph.go:189-203)', () {
    TrustedRootsException trustedErrorOf(void Function() body) {
      try {
        body();
      } on TrustedRootsException catch (e) {
        return e;
      }
      fail('expected TrustedRootsException');
    }

    test('absolute path WITHIN a trusted root resolves', () {
      final city = fx.mkdir('city');
      final script = fx.writeScript(
        'city/scripts/check.sh',
        shScript(<String>['exit 0']),
      );
      final roots = ralphCheckTrustedAbsoluteRoots(
        city,
        city,
        const <String>[],
      );
      final resolved = resolveTrustedConditionPath(city, city, script, roots);
      expectSameFile(resolved, script);
    });

    test(
      'absolute path OUTSIDE all trusted roots → pre-resolution rejection',
      () {
        // The bare resolver accepts this (callers vouch); the trusted wrapper
        // does not (ralph.go:190-192). Rejected BEFORE any FS access.
        final outside = fx.writeScript(
          'outside/tool.sh',
          shScript(<String>['exit 0']),
        );
        final city = fx.mkdir('city');
        final roots = ralphCheckTrustedAbsoluteRoots(
          city,
          city,
          const <String>[],
        );
        final e = trustedErrorOf(
          () => resolveTrustedConditionPath(city, city, outside, roots),
        );
        expect(e.resolved, isFalse);
        expect(e.message, contains('escapes trusted roots'));
      },
    );

    test(
      'absolute symlink escape (allowed by the bare resolver) is REJECTED here',
      () {
        // Mirrors the bare-resolver test "absolute symlink escape IS allowed":
        // an ABSOLUTE in-root symlink whose target is outside every trusted
        // root. The bare resolver accepts it (callers vouch); the trusted
        // wrapper rejects it. NOTE: gc's pathWithinAny → NormalizePathForCompare
        // EvalSymlinks-resolves the raw link, so the PRE-resolution check
        // (ralph.go:190-192) already sees the out-of-root target and rejects —
        // the post-resolution check (ralph.go:200-202) is the belt-and-braces
        // re-validation. Either way the escape is closed; we assert rejection,
        // not which of the two checks fires.
        final target = fx.writeScript(
          'out/real.sh',
          shScript(<String>['exit 0']),
        );
        final city = fx.mkdir('city');
        final link = fx.symlink('city/link.sh', target);
        final roots = ralphCheckTrustedAbsoluteRoots(
          city,
          city,
          const <String>[],
        );
        // Sanity: the bare resolver still accepts it (contract unchanged).
        expectSameFile(resolveConditionPath(city, city, link), target);
        // The trusted wrapper rejects the absolute escape.
        final e = trustedErrorOf(
          () => resolveTrustedConditionPath(city, city, link, roots),
        );
        expect(e.message, contains('escapes trusted roots'));
      },
    );

    test('pathWithin resolves symlinks (the absolute-escape defense)', () {
      // A symlink lexically inside a trusted root but pointing outside is NOT
      // within it, because pathWithin → normalizePathForCompare EvalSymlinks-
      // resolves both sides (pathutil.go:18-21). This is why the wrapper closes
      // the absolute-symlink-escape hole that the bare resolver leaves open.
      final target = fx.writeScript(
        'out/real.sh',
        shScript(<String>['exit 0']),
      );
      final city = fx.mkdir('city');
      final link = fx.symlink('city/link.sh', target);
      // Lexically under city...
      expect(p.isWithin(city, link), isTrue);
      // ...but symlink-resolved, the target is outside.
      expect(pathWithin(city, link), isFalse);
    });

    test('a trusted root added via formulaSearchPaths admits its subtree', () {
      final city = fx.mkdir('city');
      final formulas = fx.mkdir('packs/layer/formulas');
      final script = fx.writeScript(
        'packs/layer/formulas/check.sh',
        shScript(<String>['exit 0']),
      );
      final roots = ralphCheckTrustedAbsoluteRoots(city, city, <String>[
        formulas,
      ]);
      final resolved = resolveTrustedConditionPath(
        city,
        formulas,
        script,
        roots,
      );
      expectSameFile(resolved, script);
    });

    test(
      'relative paths skip the absolute-roots checks (envelope/base govern)',
      () {
        // Empty trusted roots: a relative in-base path must still resolve,
        // because the IsAbs guards make the absolute checks no-ops (ralph.go's
        // `if filepath.IsAbs(...)`).
        final city = fx.mkdir('city');
        final script = fx.writeScript(
          'city/gates/check.sh',
          shScript(<String>['exit 0']),
        );
        final resolved = resolveTrustedConditionPath(
          city,
          city,
          'gates/check.sh',
          const <String>[],
        );
        expectSameFile(resolved, script);
      },
    );

    test('relative traversal still rejected via ConditionPathException', () {
      final dir = fx.mkdir('dir');
      fx.writeScript('outside.sh', shScript(<String>['exit 0']));
      expect(
        errorKindOf(
          () => resolveTrustedConditionPath(
            dir,
            dir,
            '../outside.sh',
            const <String>[],
          ),
        ),
        ConditionPathError.traversal,
      );
    });
  });

  group('ralphCheckTrustedAbsoluteRoots (ralph.go:252-282)', () {
    test('cityPath then storePath, deduped by samePath', () {
      final city = fx.mkdir('city');
      final roots = ralphCheckTrustedAbsoluteRoots(
        city,
        city,
        const <String>[],
      );
      // city and store are the same path → one normalized entry.
      expect(roots.length, 1);
      expect(samePath(roots.single, city), isTrue);
    });

    test('distinct store path adds a second root', () {
      final city = fx.mkdir('city');
      final store = fx.mkdir('rig');
      final roots = ralphCheckTrustedAbsoluteRoots(
        city,
        store,
        const <String>[],
      );
      expect(roots.length, 2);
      expect(pathWithin(roots[0], city), isTrue);
      expect(pathWithin(roots[1], store), isTrue);
    });

    test('a formulas/ search path also trusts its parent', () {
      final city = fx.mkdir('city');
      final formulas = fx.mkdir('layer/formulas');
      final parent = p.dirname(formulas);
      final roots = ralphCheckTrustedAbsoluteRoots(city, city, <String>[
        formulas,
      ]);
      expect(roots.any((r) => samePath(r, formulas)), isTrue);
      expect(roots.any((r) => samePath(r, parent)), isTrue);
    });

    test('blank entries are skipped', () {
      final city = fx.mkdir('city');
      final roots = ralphCheckTrustedAbsoluteRoots(city, '  ', <String>[
        '',
        '   ',
      ]);
      expect(roots.length, 1);
    });
  });

  group('pathWithin / samePath semantics (pathutil.go:70-97)', () {
    test('root == candidate is within', () {
      final dir = fx.mkdir('d');
      expect(pathWithin(dir, dir), isTrue);
    });

    test('nested candidate is within; sibling escape is not', () {
      final root = fx.mkdir('root');
      final nested = fx.mkdir('root/a/b');
      final sibling = fx.mkdir('other');
      expect(pathWithin(root, nested), isTrue);
      expect(pathWithin(root, sibling), isFalse);
    });

    test('empty after normalization → not within', () {
      expect(pathWithin('', '/x'), isFalse);
      expect(pathWithin('/x', ''), isFalse);
    });

    test('samePath collapses the macOS /private alias via EvalSymlinks', () {
      // The fixture root is under /tmp (canonical /private/tmp on macOS);
      // samePath of the same dir is reflexively true after normalization.
      final dir = fx.mkdir('z');
      expect(samePath(dir, dir), isTrue);
    });
  });

  group('IsOutsideDir semantics (same-dir is contained)', () {
    test('relative "." (script in base root itself) resolves', () {
      final script = fx.writeScript('check.sh', shScript(<String>['exit 0']));
      final resolved = resolveConditionPath(
        fx.root.path,
        fx.root.path,
        'check.sh',
      );
      expectSameFile(resolved, script);
      // Sanity: the join lands directly in base, rel == 'check.sh' (contained).
      expect(p.dirname(script), fx.root.path);
    });
  });
}
