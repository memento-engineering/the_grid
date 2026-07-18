import 'package:grid_engine/src/molecule/bead_path_key.dart';
import 'package:test/test.dart';

void main() {
  group('BeadPathKey', () {
    // A golden literal: the canonical string this exact crumb sequence has
    // always produced. If this test ever needs to change, the durable string
    // format changed — that is a breaking change to every persisted
    // `grid.circuit.crumb` / `grid.step.crumb` value, not a refactor.
    const goldenCrumbs = [
      'tgdog-work-1',
      'tgdog-sess-2',
      'tgdog-mol-3',
      'tgdog-step-4',
    ];
    const goldenCanonical =
        'tgdog-work-1/tgdog-sess-2/tgdog-mol-3/tgdog-step-4';

    test('canonical joins crumbs with the breadcrumb separator', () {
      expect(BeadPathKey(goldenCrumbs).canonical, goldenCanonical);
    });

    test(
      'canonical is stable across independently-built instances (cross-run stability)',
      () {
        // Two keys built from separately-constructed lists (as two process runs
        // would each rebuild from bd's own bead ids) must land on the identical
        // durable string.
        final first = BeadPathKey(List.of(goldenCrumbs));
        final second = BeadPathKey(List.of(goldenCrumbs));
        expect(first.canonical, goldenCanonical);
        expect(second.canonical, goldenCanonical);
      },
    );

    test('separator is dot-free', () {
      expect(kBreadcrumbSeparator, '/');
      expect(kBreadcrumbSeparator, isNot(contains('.')));
    });

    test('separator never collides with a fixture bead id', () {
      // Bead ids are dash-separated alphanumeric tokens (`tgdog-1`,
      // `genesis-done`, `tg-abc123`, ...) across every fixture in this
      // package's tests — never containing `/`.
      const fixtureIds = [
        'tgdog-work-1',
        'tgdog-sess-2',
        'tg-abc123',
        'genesis-done',
        'gc-9',
        'tgdog-own-s',
      ];
      for (final id in fixtureIds) {
        expect(id, isNot(contains(kBreadcrumbSeparator)), reason: id);
      }
    });

    test(
      'canonical decomposes back into exactly the crumbs (no hash mixed in)',
      () {
        final key = BeadPathKey(goldenCrumbs);
        expect(key.canonical.split(kBreadcrumbSeparator), key.crumbs);
      },
    );

    test('hashCode never appears in the canonical string', () {
      final key = BeadPathKey(goldenCrumbs);
      expect(key.canonical, isNot(contains(key.hashCode.toString())));
    });

    test('de-dup preserves first-occurrence order', () {
      final key = BeadPathKey(['a', 'b', 'a', 'c', 'b', 'a']);
      expect(key.crumbs, ['a', 'b', 'c']);
      expect(key.canonical, 'a/b/c');
    });

    test('a single repeated crumb collapses to one', () {
      final key = BeadPathKey(['solo', 'solo', 'solo']);
      expect(key.crumbs, ['solo']);
    });

    test('crumbs is unmodifiable', () {
      final key = BeadPathKey(['a', 'b']);
      expect(() => key.crumbs.add('c'), throwsUnsupportedError);
    });

    group('child', () {
      test('appends a new crumb one level deeper', () {
        final root = BeadPathKey(['tgdog-work-1', 'tgdog-sess-2']);
        final child = root.child('tgdog-mol-3');
        expect(child.crumbs, ['tgdog-work-1', 'tgdog-sess-2', 'tgdog-mol-3']);
        // The parent is untouched (immutable construction).
        expect(root.crumbs, ['tgdog-work-1', 'tgdog-sess-2']);
      });

      test('re-adopting an ancestor crumb still de-dups', () {
        final child = BeadPathKey([
          'tgdog-work-1',
          'tgdog-sess-2',
        ]).child('tgdog-mol-3');
        final reAdopt = child.child('tgdog-sess-2');
        expect(reAdopt.crumbs, ['tgdog-work-1', 'tgdog-sess-2', 'tgdog-mol-3']);
      });
    });

    group('structural equality', () {
      test('equal crumb sequences from distinct lists are ==', () {
        final one = BeadPathKey(['a', 'b', 'c']);
        final two = BeadPathKey(List.of(['a', 'b', 'c']));
        expect(one, two);
        expect(one.hashCode, two.hashCode);
      });

      test('a different order is not ==', () {
        expect(
          BeadPathKey(['a', 'b', 'c']),
          isNot(BeadPathKey(['a', 'c', 'b'])),
        );
      });

      test('a different length is not ==', () {
        expect(BeadPathKey(['a', 'b', 'c']), isNot(BeadPathKey(['a', 'b'])));
      });

      test('a different crumb is not ==', () {
        expect(
          BeadPathKey(['a', 'b', 'c']),
          isNot(BeadPathKey(['a', 'b', 'd'])),
        );
      });

      test(
        'dedup collapses equality: a trailing repeat does not distinguish keys',
        () {
          expect(BeadPathKey(['a', 'b']), BeadPathKey(['a', 'b', 'a']));
        },
      );
    });

    test('toString surfaces the canonical form for debugging', () {
      expect(BeadPathKey(['a', 'b']).toString(), 'BeadPathKey(a/b)');
    });
  });
}
