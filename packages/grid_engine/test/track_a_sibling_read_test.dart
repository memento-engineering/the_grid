// Track A2 — the sibling-read projection (D-5).
//
// A read-only view of THIS session's cursor + results is threaded down to each
// capability (config, not a subscription/re-query — A39/invariant 1). A `route`
// step reads its sibling critics' terminal states + grades through it. Tests the
// value-types (SiblingView), the StepMount→CapabilityContext threading, and the
// `grid.result.*` read projection. Zero I/O.
import 'package:genesis_tree/genesis_tree.dart';
import 'package:grid_controller/grid_controller.dart';
import 'package:grid_engine/grid_engine.dart';
import 'package:test/test.dart';

import 'support/engine_fakes.dart';

void main() {
  group('Track A2 — SiblingView reads the threaded cursor + results', () {
    test('cursorOf/resultOf surface a complete sibling with its grade; an '
        'unknown path defaults to pending + empty', () {
      const view = SiblingView(
        cursor: {
          'b/critic1': NodeCursor(state: StepState.complete),
        },
        results: {
          'b/critic1': {'grade': 'A'},
        },
      );
      expect(view.cursorOf('b/critic1').state, StepState.complete);
      expect(view.resultOf('b/critic1'), {'grade': 'A'});
      // Positive control: an unread/unknown path is fail-closed to a default
      // pending cursor + empty result (a route can never read a phantom grade).
      expect(view.cursorOf('b/missing').state, StepState.pending);
      expect(view.resultOf('b/missing'), isEmpty);
    });

    test('a CapabilityContext built from a StepMount exposes its siblings + '
        'nodePath', () {
      const mount = StepMount(
        step: CapabilityStep(stepId: 'route', capabilityId: 'route'),
        bead: _noBead,
        nodePath: 'tg-1/review/route',
        session: SessionHandle('tgdog-s'),
        node: NodeCursor(),
        key: ValueKey('tg-1/review/route#0'),
        cursor: {
          'tg-1/review/critic1': NodeCursor(state: StepState.complete),
        },
        results: {
          'tg-1/review/critic1': {'grade': 'A'},
        },
      );
      final ctx = CapabilityContext(
        params: mount.step.params,
        bead: mount.bead,
        workspaceDir: '/w',
        branch: 'grid/tg-1',
        baseBranch: 'main',
        services: const ServiceBundle(),
        cancel: CancelToken(),
        nodePath: mount.nodePath,
        siblings: SiblingView(cursor: mount.cursor, results: mount.results),
      );
      expect(ctx.nodePath, 'tg-1/review/route');
      expect(ctx.siblings.cursorOf('tg-1/review/critic1').state,
          StepState.complete);
      expect(ctx.siblings.resultOf('tg-1/review/critic1'), {'grade': 'A'});
    });

    test('projectFormulaResults parses grid.result.* into per-node maps; a '
        'malformed key is skipped', () {
      final sb = Bead(
        id: 'tgdog-s',
        issueType: IssueType.session,
        status: BeadStatus.open,
        metadata: const {
          'grid.result.b/critic1.grade': 'A',
          'grid.result.b/critic1.rationale': 'clean',
          'grid.result.b/critic2.grade': 'C',
          // A non-result key is ignored.
          'grid.cursor.b/critic1.state': 'complete',
          // A malformed result key (no field segment) is skipped.
          'grid.result.': 'junk',
        },
      );
      final results = projectFormulaResults(sb);
      expect(results['b/critic1'], {'grade': 'A', 'rationale': 'clean'});
      expect(results['b/critic2'], {'grade': 'C'});
      // The cursor key did NOT leak into results.
      expect(results.containsKey('b'), isFalse);
    });

    test('projectSession threads results onto the projection (read half of '
        'nodeResultMetadata)', () {
      final sb = Bead(
        id: 'tgdog-s',
        issueType: IssueType.session,
        status: BeadStatus.open,
        metadata: {
          'rig': stateSubstation,
          SessionBeadKeys.workBead: 'tg-1',
          ...nodeStateMetadata('tg-1/review/critic1', StepState.complete),
          ...nodeResultMetadata('tg-1/review/critic1', const {'grade': 'A'}),
        },
      );
      final proj = projectSession(sb);
      expect(proj.results['tg-1/review/critic1'], {'grade': 'A'});
      expect(proj.cursor['tg-1/review/critic1']?.state, StepState.complete);
    });
  });
}

const _noBead = Bead(id: 'tg-1', issueType: IssueType.task, status: BeadStatus.open);
