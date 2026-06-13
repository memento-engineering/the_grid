import 'package:grid_controller/grid_controller.dart';
import 'package:grid_reconciler/grid_reconciler.dart';
import 'package:test/test.dart';

import '../support/fakes.dart';

void main() {
  group('Convergence.project — typed boundary', () {
    test('non-convergence bead is a typed ProjectionError', () {
      final result = Convergence.project(
        const Bead(id: 'gt-t1', issueType: IssueType.task),
      );
      expect(result.isOk, isFalse);
      expect(
        result.errorOrNull!.reason,
        contains('expected issue_type "convergence"'),
      );
    });

    test('metadata decode is total — a convergence bead with garbage '
        'metadata still projects, failures surfaced on the codec', () {
      final result = Convergence.project(
        convergenceBead(
          'gt-c1',
          metadata: const {
            'convergence.state': 'limbo',
            'convergence.iteration': 'NaN',
          },
        ),
      );
      final convergence = result.valueOrNull;
      expect(convergence, isNotNull);
      expect(
        convergence!.state,
        const ConvergenceStateReading.unrecognized('limbo'),
      );
      expect(convergence.metadata.failures, hasLength(2));
    });
  });

  group('child resolution via parent-child edges (A15: hierarchy is an '
      'edge; parent_id column stays null)', () {
    const rootId = 'gt-c1';

    test('children resolve strictly in gc direction (child=issue_id, '
        'parent=depends_on_id); reversed edges are NOT children', () {
      final root = convergenceBead(rootId);
      final w1 = wispBead('gt-w1', key: 'converge:$rootId:iter:1');
      final w2 = wispBead('gt-w2', key: 'converge:$rootId:iter:2');
      final result = Convergence.project(
        root,
        dependencies: [
          parentChild('gt-w1', rootId),
          // Reversed edge: would make the root the child of gt-w2 — must
          // not count (gc's Children() resolves one direction only).
          parentChild(rootId, 'gt-w2'),
        ],
        beadsById: {rootId: root, 'gt-w1': w1, 'gt-w2': w2},
      );
      final convergence = result.valueOrNull!;
      expect(convergence.childIds, ['gt-w1']);
      expect(convergence.wisps.map((w) => w.id), ['gt-w1']);
    });

    test('wisps = children whose key carries OUR prefix; foreign-prefix and '
        'keyless children are excluded from wisps', () {
      final root = convergenceBead(rootId);
      final mine = wispBead('gt-w1', key: 'converge:$rootId:iter:1');
      // A child carrying another convergence's key (e.g. after a re-parent).
      final foreign = wispBead('gt-alien', key: 'converge:gt-OTHER:iter:9');
      const keyless = Bead(id: 'gt-note', issueType: IssueType.task);
      final result = Convergence.project(
        root,
        dependencies: [
          parentChild('gt-w1', rootId),
          parentChild('gt-alien', rootId),
          parentChild('gt-note', rootId),
        ],
        beadsById: {
          rootId: root,
          'gt-w1': mine,
          'gt-alien': foreign,
          'gt-note': keyless,
        },
      );
      final convergence = result.valueOrNull!;
      expect(convergence.childIds, ['gt-alien', 'gt-note', 'gt-w1']);
      expect(convergence.wisps.map((w) => w.id), ['gt-w1']);
      // ...but the foreign key is still scannable (gc's child scan).
      expect(convergence.childIdempotencyKeys, {
        'gt-w1': 'converge:$rootId:iter:1',
        'gt-alien': 'converge:gt-OTHER:iter:9',
      });
    });

    test('a bead-id containing ":iter:" still scopes wisps correctly '
        '(LastIndex parsing + prefix match)', () {
      const trickyId = 'gt:iter:x';
      final root = convergenceBead(trickyId);
      final w1 = wispBead('gt-w1', key: 'converge:$trickyId:iter:1');
      final result = Convergence.project(
        root,
        dependencies: [parentChild('gt-w1', trickyId)],
        beadsById: {trickyId: root, 'gt-w1': w1},
      );
      final convergence = result.valueOrNull!;
      expect(convergence.wisps.single.iteration, 1);
    });

    test('dangling edge (child bead missing from snapshot) is skipped, '
        'never thrown', () {
      final root = convergenceBead(rootId);
      final result = Convergence.project(
        root,
        dependencies: [parentChild('gt-ghost', rootId)],
        beadsById: {rootId: root},
      );
      final convergence = result.valueOrNull!;
      expect(convergence.childIds, ['gt-ghost']);
      expect(convergence.wisps, isEmpty);
    });

    test('wisps sort by iteration, unparseable last', () {
      final root = convergenceBead(rootId);
      final w2 = wispBead('gt-w2', key: 'converge:$rootId:iter:2');
      final w1 = wispBead('gt-w1', key: 'converge:$rootId:iter:1');
      final wx = wispBead('gt-wx', key: 'converge:$rootId:iter:junk');
      final result = Convergence.project(
        root,
        dependencies: [
          parentChild('gt-w2', rootId),
          parentChild('gt-wx', rootId),
          parentChild('gt-w1', rootId),
        ],
        beadsById: {rootId: root, 'gt-w1': w1, 'gt-w2': w2, 'gt-wx': wx},
      );
      expect(result.valueOrNull!.wisps.map((w) => w.id), [
        'gt-w1',
        'gt-w2',
        'gt-wx',
      ]);
    });
  });

  group('closedWispCount — invariant-4 derivation input '
      '(deriveIterationCount, handler.go:812-825)', () {
    const rootId = 'gt-c1';

    Convergence build({required List<Bead> children}) {
      final root = convergenceBead(rootId);
      return Convergence.project(
        root,
        dependencies: [
          for (final child in children) parentChild(child.id, rootId),
        ],
        beadsById: {
          rootId: root,
          for (final child in children) child.id: child,
        },
      ).valueOrNull!;
    }

    test('counts prefix-matched closed children only', () {
      final convergence = build(
        children: [
          wispBead(
            'gt-w1',
            key: 'converge:$rootId:iter:1',
            status: BeadStatus.closed,
          ),
          wispBead(
            'gt-w2',
            key: 'converge:$rootId:iter:2',
            status: BeadStatus.closed,
          ),
          wispBead('gt-w3', key: 'converge:$rootId:iter:3'), // open
          wispBead(
            'gt-alien',
            key: 'converge:other:iter:1',
            status: BeadStatus.closed, // foreign prefix: never counted
          ),
        ],
      );
      expect(convergence.closedWispCount, 2);
    });

    test('counts a closed prefix-wisp with an UNPARSEABLE iteration — gc '
        'counts by prefix + closed, not by parseability', () {
      final convergence = build(
        children: [
          wispBead(
            'gt-w1',
            key: 'converge:$rootId:iter:1',
            status: BeadStatus.closed,
          ),
          wispBead(
            'gt-wx',
            key: 'converge:$rootId:iter:oops',
            status: BeadStatus.closed,
          ),
        ],
      );
      expect(convergence.closedWispCount, 2);
    });

    test('highestClosedWisp skips unparseable iterations '
        '(reconcile.go:640-643)', () {
      final convergence = build(
        children: [
          wispBead(
            'gt-w1',
            key: 'converge:$rootId:iter:1',
            status: BeadStatus.closed,
          ),
          wispBead(
            'gt-wx',
            key: 'converge:$rootId:iter:oops',
            status: BeadStatus.closed,
          ),
          wispBead('gt-w3', key: 'converge:$rootId:iter:3'), // open: skipped
        ],
      );
      expect(convergence.highestClosedWisp!.id, 'gt-w1');
    });

    test('highestClosedWisp is null with no closed parseable wisps', () {
      final convergence = build(
        children: [wispBead('gt-w1', key: 'converge:$rootId:iter:1')],
      );
      expect(convergence.highestClosedWisp, isNull);
    });
  });

  group('activeWisp resolution (metadata active_wisp ∩ actual children)', () {
    const rootId = 'gt-c1';

    Convergence build(Map<String, dynamic> metadata, {List<Bead>? children}) {
      final kids =
          children ??
          [
            wispBead('gt-w1', key: 'converge:$rootId:iter:1'),
            wispBead('gt-w2', key: 'converge:$rootId:iter:2'),
          ];
      final root = convergenceBead(rootId, metadata: metadata);
      return Convergence.project(
        root,
        dependencies: [for (final kid in kids) parentChild(kid.id, rootId)],
        beadsById: {rootId: root, for (final kid in kids) kid.id: kid},
      ).valueOrNull!;
    }

    test('resolves when the metadata id is one of our wisps', () {
      final convergence = build(const {'convergence.active_wisp': 'gt-w2'});
      expect(convergence.activeWisp!.id, 'gt-w2');
      expect(convergence.activeWisp!.iteration, 2);
    });

    test('dangling metadata (id not among children) resolves to null — '
        'never throws', () {
      final convergence = build(const {
        'convergence.active_wisp': 'gt-deleted',
      });
      expect(convergence.activeWisp, isNull);
    });

    test('absent and empty (gc clears by writing "") both resolve null', () {
      expect(build(const {}).activeWisp, isNull);
      expect(build(const {'convergence.active_wisp': ''}).activeWisp, isNull);
    });
  });

  group('findByIdempotencyKey (A15: pure snapshot scan, no bd spawn)', () {
    const rootId = 'gt-c1';
    late Convergence convergence;

    setUp(() {
      final root = convergenceBead(rootId);
      final w1 = wispBead(
        'gt-w1',
        key: 'converge:$rootId:iter:1',
        status: BeadStatus.closed,
      );
      final w2 = wispBead('gt-w2', key: 'converge:$rootId:iter:2');
      final foreign = wispBead('gt-alien', key: 'converge:other:iter:5');
      convergence = Convergence.project(
        root,
        dependencies: [
          parentChild('gt-w1', rootId),
          parentChild('gt-w2', rootId),
          parentChild('gt-alien', rootId),
        ],
        beadsById: {
          rootId: root,
          'gt-w1': w1,
          'gt-w2': w2,
          'gt-alien': foreign,
        },
      ).valueOrNull!;
    });

    test('hit: returns the existing wisp id for a poured iteration', () {
      expect(
        convergence.findByIdempotencyKey('converge:$rootId:iter:2'),
        'gt-w2',
      );
      expect(
        convergence.findByIdempotencyKey(idempotencyKey(rootId, 1)),
        'gt-w1',
      );
    });

    test('miss: an un-poured iteration returns null (pour proceeds)', () {
      expect(
        convergence.findByIdempotencyKey('converge:$rootId:iter:3'),
        isNull,
      );
    });

    test('scans ALL children, not just our-prefix wisps — byte-faithful to '
        'gc child scan (convergence_store.go:264-266)', () {
      expect(
        convergence.findByIdempotencyKey('converge:other:iter:5'),
        'gt-alien',
      );
    });
  });
}
