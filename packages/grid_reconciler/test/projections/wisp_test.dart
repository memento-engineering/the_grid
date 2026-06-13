import 'package:grid_controller/grid_controller.dart';
import 'package:grid_reconciler/grid_reconciler.dart';
import 'package:test/test.dart';

import '../support/fakes.dart';

void main() {
  group('Wisp.project', () {
    test('projects a keyed bead: id, key, iteration parsed from the key', () {
      final result = Wisp.project(
        wispBead('gt-w2', key: 'converge:gt-c1:iter:2'),
      );
      final wisp = result.valueOrNull;
      expect(wisp, isNotNull);
      expect(wisp!.id, 'gt-w2');
      expect(wisp.idempotencyKey, 'converge:gt-c1:iter:2');
      expect(wisp.iteration, 2);
      expect(wisp.isClosed, isFalse);
      expect(wisp.ephemeral, isTrue);
    });

    test('unparseable iteration suffix projects with iteration null '
        '(gc skips it in highestClosedWisp but still counts it)', () {
      final result = Wisp.project(
        wispBead('gt-wx', key: 'converge:gt-c1:iter:abc'),
      );
      expect(result.valueOrNull!.iteration, isNull);
    });

    test('missing idempotency_key is a typed ProjectionError, not a throw', () {
      final result = Wisp.project(
        const Bead(id: 'gt-x', issueType: IssueType.molecule),
      );
      expect(result.isOk, isFalse);
      expect(
        result.errorOrNull!.reason,
        contains('missing metadata.idempotency_key'),
      );
    });

    test('non-String idempotency_key is a typed ProjectionError', () {
      final result = Wisp.project(
        const Bead(
          id: 'gt-x',
          issueType: IssueType.molecule,
          metadata: {'idempotency_key': 7},
        ),
      );
      expect(result.isOk, isFalse);
      expect(result.errorOrNull!.reason, contains('not a String'));
    });

    test('no issue-type or ephemeral requirement — gc identifies wisps by '
        'key prefix only (handler.go:812-825)', () {
      final result = Wisp.project(
        const Bead(
          id: 'gt-task',
          issueType: IssueType.task, // not a molecule
          metadata: {'idempotency_key': 'converge:gt-c1:iter:1'},
        ),
      );
      expect(result.isOk, isTrue);
      expect(result.valueOrNull!.ephemeral, isFalse);
    });

    test('resolves step children via parent-child edges with needs from '
        'sibling blocking edges', () {
      const wispId = 'gt-w1';
      final wisp = wispBead(wispId, key: 'converge:gt-c1:iter:1');
      const s1 = Bead(
        id: 'st1',
        issueType: IssueType.step,
        status: BeadStatus.closed,
      );
      const s2 = Bead(id: 'st2', issueType: IssueType.step);
      const other = Bead(id: 'note', issueType: IssueType.task);
      final deps = [
        parentChild('st1', wispId),
        parentChild('st2', wispId),
        parentChild('note', wispId), // non-step child: not a Step
        const BeadDependency(
          issueId: 'st2',
          dependsOnId: 'st1',
          type: DependencyType.blocks,
        ),
      ];
      final result = Wisp.project(
        wisp,
        dependencies: deps,
        beadsById: {wispId: wisp, 'st1': s1, 'st2': s2, 'note': other},
      );
      final projected = result.valueOrNull!;
      expect(projected.steps.map((s) => s.id), ['st1', 'st2']);
      expect(projected.steps.last.needs, ['st1']);
      expect(projected.stepCount, 2);
      expect(projected.closedStepCount, 1);
      expect(projected.progress, closeTo(0.5, 1e-9));
    });

    test('progress is 1.0 with no steps (mirrors Molecule)', () {
      final result = Wisp.project(
        wispBead('gt-w1', key: 'converge:gt-c1:iter:1'),
      );
      expect(result.valueOrNull!.progress, 1.0);
    });

    group('speculative subtree (A15 deferred pour)', () {
      // A speculative wisp: actionable nodes poured as type `gate` with
      // the real type/assignee/routing under gc.deferred_* (the snapshot a
      // crash-recovery adoption sees — no pour-time id map).
      const wispId = 'gt-w3';
      final wisp = wispBead(wispId, key: 'converge:gt-c1:iter:3');
      const na = Bead(
        id: 'gt-na',
        issueType: IssueType.gate, // speculative step — NOT step-typed
        metadata: {
          'gc.deferred_type': 'step',
          'gc.deferred_assignee': 'polecat-vapor',
          'gc.deferred_routed_to': 'rig-vapor',
        },
      );
      const naChild = Bead(
        id: 'gt-na1',
        issueType: IssueType.gate, // nested actionable node
        metadata: {
          'gc.deferred_type': 'task',
          'gc.deferred_execution_routed_to': 'rig-vapor/exec',
          // Empty reads as not-deferred (activateDeferredAssignees'
          // `!= ""` guards, convergence_store.go:214-226).
          'gc.deferred_assignee': '',
        },
      );
      const nb = Bead(
        id: 'gt-nb',
        issueType: IssueType.gate, // a REAL gate — no deferred keys
      );
      final deps = [
        parentChild('gt-na', wispId),
        parentChild('gt-nb', wispId),
        parentChild('gt-na1', 'gt-na'),
        parentChild('gt-dangling', 'gt-nb'), // edge only, no bead row
      ];
      late final Wisp projected = Wisp.project(
        wisp,
        dependencies: deps,
        beadsById: {wispId: wisp, 'gt-na': na, 'gt-na1': naChild, 'gt-nb': nb},
      ).valueOrNull!;

      test('subtreeIds is POST-ORDER — children before parents, the wisp '
          'LAST: burn order = exactly this list (deleteBeadSubtree, '
          'handler.go:919-933)', () {
        expect(projected.subtreeIds, [
          'gt-na1', // na's child before na
          'gt-na',
          'gt-dangling', // edge-only node still enumerated, before parent
          'gt-nb',
          wispId, // the wisp itself last
        ]);
      });

      test('speculativeNodes is PRE-ORDER (activation recursion, '
          'convergence_store.go:208-246) and exposes every deferred '
          'value; empty values and non-deferred nodes are excluded', () {
        expect(projected.speculativeNodes.map((n) => n.id), [
          'gt-na', // parent before child — activation order
          'gt-na1',
        ]);
        final first = projected.speculativeNodes[0];
        expect(first.deferredType, 'step');
        expect(first.deferredAssignee, 'polecat-vapor');
        expect(first.deferredRoutedTo, 'rig-vapor');
        expect(first.deferredExecutionRoutedTo, isNull);
        final nested = projected.speculativeNodes[1];
        expect(nested.deferredType, 'task');
        expect(nested.deferredExecutionRoutedTo, 'rig-vapor/exec');
        expect(nested.deferredAssignee, isNull); // '' reads not-deferred
        expect(nested.deferredRoutedTo, isNull);
      });

      test('steps stays EMPTY for a speculative wisp — the children are '
          'gate-typed until activation (the ACTIVATED-wisp view)', () {
        expect(projected.steps, isEmpty);
        expect(projected.progress, 1.0); // no visible steps
      });

      test('a directly-poured (activated) wisp has subtreeIds but no '
          'speculativeNodes', () {
        const s1 = Bead(id: 'st1', issueType: IssueType.step);
        final activated = Wisp.project(
          wispBead('gt-w1', key: 'converge:gt-c1:iter:1'),
          dependencies: [parentChild('st1', 'gt-w1')],
          beadsById: {'st1': s1},
        ).valueOrNull!;
        expect(activated.subtreeIds, ['st1', 'gt-w1']);
        expect(activated.speculativeNodes, isEmpty);
        expect(activated.steps.map((s) => s.id), ['st1']);
      });

      test('a childless wisp subtree is just the wisp itself', () {
        final lone = Wisp.project(
          wispBead('gt-w9', key: 'converge:gt-c1:iter:9'),
        ).valueOrNull!;
        expect(lone.subtreeIds, ['gt-w9']);
        expect(lone.speculativeNodes, isEmpty);
      });
    });

    test('effectiveClosedAt falls back to createdAt for a closed wisp '
        'without a close timestamp (convergence_store.go:345-349)', () {
      final created = DateTime.utc(2026, 6, 12, 10);
      final closed = DateTime.utc(2026, 6, 12, 11);

      final withClose = Wisp.project(
        wispBead(
          'gt-w1',
          key: 'converge:gt-c1:iter:1',
          status: BeadStatus.closed,
          createdAt: created,
          closedAt: closed,
        ),
      ).valueOrNull!;
      expect(withClose.effectiveClosedAt, closed);

      final withoutClose = Wisp.project(
        wispBead(
          'gt-w2',
          key: 'converge:gt-c1:iter:2',
          status: BeadStatus.closed,
          createdAt: created,
        ),
      ).valueOrNull!;
      expect(withoutClose.effectiveClosedAt, created); // duration zero

      final open = Wisp.project(
        wispBead('gt-w3', key: 'converge:gt-c1:iter:3', createdAt: created),
      ).valueOrNull!;
      expect(open.effectiveClosedAt, isNull);
    });
  });
}
