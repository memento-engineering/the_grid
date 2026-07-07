// OP-1 (tg-a76 / I-3): the arming-time validation_plan preflight. A plan
// authored from the umbrella-dir view (`cd power_station && …`) cannot run
// inside the per-bead worktree → the gating lane exits non-zero → a FALSE
// gating F indistinguishable from broken code. The preflight turns that class
// into an ARMING refusal (StationRefusal, exit 64) BEFORE any spawn, naming the
// bead + the offending clause. Pure + offline — the directory-existence probe
// is injected, so no real filesystem is touched.
import 'package:grid_cli/src/station_runner.dart';
import 'package:test/test.dart';

/// A fake worktree root whose only existing directories are those in [dirs]
/// (absolute, normalized). Everything else "does not exist".
bool Function(String) _fsWith(Set<String> dirs) => dirs.contains;

void main() {
  const root = '/tmp/worktree/tg-a76';

  group('lintValidationPlan — the deny-list (I-3)', () {
    test('(a) a `cd` into a subdir absent at the worktree root is refused, '
        'naming the clause', () {
      final reason = lintValidationPlan(
        'cd power_station && melos run analyze && melos run test',
        worktreeRoot: root,
        dirExists: _fsWith(const {}), // no subdirs exist
      );
      expect(reason, isNotNull);
      expect(reason, contains('power_station'));
      expect(reason, contains('absent at the worktree root'));
      // The offending clause is named — not the whole plan.
      expect(reason, contains('cd power_station'));
    });

    test('(b) a worktree-relative plan passes — no cd, no absolute path', () {
      final reason = lintValidationPlan(
        'melos run analyze && melos run test',
        worktreeRoot: root,
        dirExists: _fsWith(const {}),
      );
      expect(reason, isNull);
    });

    test('(c) an empty plan is refused', () {
      expect(
        lintValidationPlan('', worktreeRoot: root),
        allOf(isNotNull, contains('empty')),
      );
    });

    test('(c) a whitespace-only plan is refused', () {
      expect(
        lintValidationPlan('   \n  \t ', worktreeRoot: root),
        allOf(isNotNull, contains('empty')),
      );
    });

    test('a null plan is refused (a bead carrying no plan is skipped by the '
        'preflight map, but the lint itself is fail-closed)', () {
      expect(lintValidationPlan(null, worktreeRoot: root), isNotNull);
    });

    test('a `cd` into an EXISTING worktree subdir is allowed (conservative — '
        'we refuse only what will not run)', () {
      final reason = lintValidationPlan(
        'cd packages/grid_cli && melos run test',
        worktreeRoot: root,
        dirExists: _fsWith({'$root/packages/grid_cli'}),
      );
      expect(reason, isNull);
    });

    test('a `cd` into an ABSOLUTE path outside the worktree is refused, naming '
        'the clause', () {
      final reason = lintValidationPlan(
        'cd /Users/nico/power_station && melos run test',
        worktreeRoot: root,
        dirExists: _fsWith(const {}),
      );
      expect(reason, isNotNull);
      expect(reason, contains('/Users/nico/power_station'));
      expect(reason, contains('outside the worktree root'));
    });

    test('a bare `cd` (to \$HOME) is refused', () {
      final reason = lintValidationPlan(
        'cd && melos run test',
        worktreeRoot: root,
      );
      expect(reason, allOf(isNotNull, contains('HOME')));
    });

    test('a `cd ~` / `cd -` / `cd \$VAR` is refused (not worktree-relative)', () {
      for (final plan in ['cd ~', 'cd -', r'cd $REPO']) {
        expect(
          lintValidationPlan(plan, worktreeRoot: root),
          allOf(isNotNull, contains('worktree-relative')),
          reason: 'plan: $plan',
        );
      }
    });

    test('an absolute-path token outside the worktree is refused even without '
        'a cd (shape (c))', () {
      final reason = lintValidationPlan(
        'melos run test --coverage=/Users/nico/out',
        worktreeRoot: root,
        dirExists: _fsWith(const {}),
      );
      expect(reason, allOf(isNotNull, contains('/Users/nico/out')));
    });

    test('an absolute path INSIDE the worktree is allowed (worktree-relative '
        'in spirit — resolves under root)', () {
      final reason = lintValidationPlan(
        'melos run test --coverage=$root/coverage',
        worktreeRoot: root,
        dirExists: _fsWith(const {}),
      );
      expect(reason, isNull);
    });

    test('a non-path token that merely starts with a slash-like regex is not '
        'flagged (no false positive)', () {
      final reason = lintValidationPlan(
        "grep -E '/foo.*bar/' lib && melos run test",
        worktreeRoot: root,
        dirExists: _fsWith(const {}),
      );
      expect(reason, isNull);
    });

    test('clauses are split on ;, |, && and newlines — a bad cd anywhere is '
        'caught', () {
      final reason = lintValidationPlan(
        'melos run analyze ; cd power_station && melos run test',
        worktreeRoot: root,
        dirExists: _fsWith(const {}),
      );
      expect(reason, allOf(isNotNull, contains('power_station')));
    });
  });

  group('preflightValidationPlans — the refusal (OP-1)', () {
    test('names the bead + the offending clause; exit code 64', () {
      Object? caught;
      try {
        preflightValidationPlans(
          {'tg-ucz': 'cd power_station && melos run test'},
          worktreeRoot: root,
          dirExists: _fsWith(const {}),
        );
        fail('expected a StationRefusal');
      } on StationRefusal catch (r) {
        caught = r;
        expect(r.code, 64);
        expect(r.message, contains('tg-ucz'));
        expect(r.message, contains('power_station'));
        expect(r.message, contains('ARMING refusal'));
        expect(r.message, contains('WORKTREE-RELATIVE'));
      }
      expect(caught, isNotNull);
    });

    test('an empty map is a no-op (dry-run / no-read shape)', () {
      expect(
        () => preflightValidationPlans(
          const {},
          worktreeRoot: root,
          dirExists: _fsWith(const {}),
        ),
        returnsNormally,
      );
    });

    test('a bead whose plan is null (carries none) is skipped — not '
        'over-refused', () {
      expect(
        () => preflightValidationPlans(
          {'tg-ok': null},
          worktreeRoot: root,
          dirExists: _fsWith(const {}),
        ),
        returnsNormally,
      );
    });

    test('a bead whose plan is a present-but-blank string IS refused (a real '
        'defect, criterion (c))', () {
      expect(
        () => preflightValidationPlans(
          {'tg-blank': '   '},
          worktreeRoot: root,
          dirExists: _fsWith(const {}),
        ),
        throwsA(
          isA<StationRefusal>().having(
            (r) => r.message,
            'message',
            allOf(contains('tg-blank'), contains('empty')),
          ),
        ),
      );
    });

    test('a worktree-relative plan passes preflight', () {
      expect(
        () => preflightValidationPlans(
          {'tg-ok': 'melos run analyze && melos run test'},
          worktreeRoot: root,
          dirExists: _fsWith(const {}),
        ),
        returnsNormally,
      );
    });
  });

  group('validateArming wires the preflight (OP-1) — refusal at arming, '
      'before any spawn', () {
    StationArgs liveArgs() => const StationArgs(
      substations: {'tgdog'},
      stateSubstation: 'tgdog',
      dryRun: false,
      targetBeads: {'tg-ucz'},
    );

    test('a live arm with a bad plan is refused at validateArming, naming the '
        'clause — never reaching a spawn', () {
      expect(
        () => validateArming(
          liveArgs(),
          rootInjected: true,
          stateInjected: true,
          validationPlans: {'tg-ucz': 'cd power_station && melos run test'},
          worktreeRoot: root,
          dirExists: _fsWith(const {}),
        ),
        throwsA(
          isA<StationRefusal>()
              .having((r) => r.code, 'code', 64)
              .having(
                (r) => r.message,
                'message',
                allOf(contains('tg-ucz'), contains('power_station')),
              ),
        ),
      );
    });

    test('a live arm with a worktree-relative plan passes validateArming', () {
      expect(
        () => validateArming(
          liveArgs(),
          rootInjected: true,
          stateInjected: true,
          validationPlans: {'tg-ucz': 'melos run analyze && melos run test'},
          worktreeRoot: root,
          dirExists: _fsWith(const {}),
        ),
        returnsNormally,
      );
    });

    test('validateArming with NO validationPlans is unchanged — the preflight '
        'is a no-op (back-compat)', () {
      expect(
        () => validateArming(
          liveArgs(),
          rootInjected: true,
          stateInjected: true,
        ),
        returnsNormally,
      );
    });
  });
}
