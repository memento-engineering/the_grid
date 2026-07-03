// Track A2 — the sibling-read projection (D-5).
//
// A read-only view of THIS session's cursor + results is an AMBIENT value
// mounted by SessionScope (config, not a subscription/re-query — A39/invariant
// 1; plumbing moved ambient 2026-07-02). A `route` step reads its sibling
// critics' terminal states + grades by looking the SiblingView up with the
// effect verb. Tests the value-types (SiblingView), the ambient effect-verb
// read, and the `grid.result.*` read projection. Zero I/O.
import 'package:genesis_tree/genesis_tree.dart';
import 'package:grid_controller/grid_controller.dart';
import 'package:grid_engine/grid_engine.dart';
import 'package:test/test.dart';

import 'support/engine_fakes.dart';

/// A ServiceCapability that reads its siblings' states + results from the
/// AMBIENT SiblingView with the effect verb — pull-free, read-only (D-5) — and
/// surfaces what it saw as its Ok payload so the test asserts the read.
class _RouteCap extends ServiceCapability {
  const _RouteCap();

  @override
  Future<StepOutcome> run(TreeContext context, StepArgs args) async {
    final siblings =
        context.getInheritedSeedOfExactType<SiblingView>() ??
        const SiblingView();
    return Ok({
      'nodePath': args.nodePath,
      'critic1.state': siblings.cursorOf('tg-1/review/critic1').state.name,
      'critic1.grade': siblings.resultOf('tg-1/review/critic1')['grade'] ?? '',
    });
  }
}

void main() {
  group('Track A2 — SiblingView reads the ambient cursor + results', () {
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

    test('a ServiceCapability reads the AMBIENT SiblingView (mounted by '
        'SessionScope) with the effect verb — its siblings + its nodePath', () async {
      // The ambient value SessionScope mounts: this session's cursor + results.
      final context = FakeTreeContext(
        values: {
          SiblingView: const SiblingView(
            cursor: {
              'tg-1/review/critic1': NodeCursor(state: StepState.complete),
            },
            results: {
              'tg-1/review/critic1': {'grade': 'A'},
            },
          ),
        },
      );
      final outcome =
          await const _RouteCap().run(context, stepArgs('tg-1/review/route'));
      final payload = (outcome as Ok).payload!;
      expect(payload['nodePath'], 'tg-1/review/route');
      expect(payload['critic1.state'], 'complete');
      expect(payload['critic1.grade'], 'A');
    });

    test('projectCircuitResults parses grid.result.* into per-node maps; a '
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
      final results = projectCircuitResults(sb);
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
