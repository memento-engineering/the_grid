// Track C3 — the route/aggregate capability + the deterministic matrix.
//
// `route` reads its sibling critics' grades through the threaded-down
// SiblingView (D-5; never a subscription/re-query) and decides:
//   gating-F → Gate · spread ≥ 3 → Gate · any non-gating D/F → Gate ·
//   all A–C → Ok.
// Fail-closed: a missing/forged grade is F, so it can NEVER advance. Zero I/O.
import 'package:grid_assets/grid_assets.dart';
import 'package:grid_engine/grid_engine.dart';
import 'package:test/test.dart';

import 'support/asset_fakes.dart';

const _critics = 'code-validation,spec-adherence,regression-risk,test-coverage';

/// A route [CapabilityContext] whose siblings carry the fabricated [grades]
/// (criticId → letter); an omitted critic has NO recorded grade (the
/// fail-closed-missing case). The node path is realistic: `tg-1/review/route`,
/// so the siblings live at `tg-1/review/<criticId>`.
CapabilityContext _routeCtx(Map<String, String> grades) {
  const parent = 'tg-1/review';
  return CapabilityContext(
    params: const {'critics': _critics, 'gating': 'code-validation'},
    bead: bead('tg-1'),
    workspaceDir: '/w/tg-1',
    branch: 'grid/tg-1',
    baseBranch: 'main',
    services: const ServiceBundle(),
    cancel: CancelToken(),
    nodePath: '$parent/route',
    siblings: SiblingView(
      cursor: {
        for (final id in grades.keys)
          '$parent/$id': const NodeCursor(state: StepState.complete),
      },
      results: {
        for (final entry in grades.entries) '$parent/${entry.key}': {'grade': entry.value},
      },
    ),
  );
}

void main() {
  group('Track C3 — the route matrix', () {
    test('all A–C ⇒ Ok(advance)', () async {
      final out = await const RouteCapability().run(_routeCtx(const {
        'code-validation': 'A',
        'spec-adherence': 'B',
        'regression-risk': 'A',
        'test-coverage': 'C',
      }));
      expect(out, isA<Ok>());
      expect((out as Ok).payload, {'verdict': 'advance'});
    });

    test('the gating critic at F ⇒ Gate (hard block)', () async {
      final out = await const RouteCapability().run(_routeCtx(const {
        'code-validation': 'F',
        'spec-adherence': 'A',
        'regression-risk': 'A',
        'test-coverage': 'A',
      }));
      expect(out, isA<Gate>());
      expect((out as Gate).reason, contains('hard block'));
    });

    test('a grade spread ≥ 3 (A + D) ⇒ Gate', () async {
      final out = await const RouteCapability().run(_routeCtx(const {
        'code-validation': 'A',
        'spec-adherence': 'A',
        'regression-risk': 'A',
        'test-coverage': 'D',
      }));
      expect(out, isA<Gate>());
      // The spread rule (rule 2) fires before the D/F rule — assert the REASON
      // so a gate firing for the WRONG rule is caught (review finding C-1).
      expect((out as Gate).reason, contains('spread'));
    });

    test('a non-gating critic at F (spread < 3) ⇒ Gate (rework rule, the F '
        'branch)', () async {
      // Isolates rule 3's `== F` branch: a synthetic gating=D keeps rule 1 from
      // firing, and all grades sit in D..F so the spread (2) stays < 3 — only the
      // non-gating F can trip the gate (review finding C-2).
      final out = await const RouteCapability().run(_routeCtx(const {
        'code-validation': 'D',
        'spec-adherence': 'F',
        'regression-risk': 'E',
        'test-coverage': 'D',
      }));
      expect(out, isA<Gate>());
      expect((out as Gate).reason, contains('rework'));
    });

    test('a non-gating critic at D (spread < 3) ⇒ Gate (rework, deferred)',
        () async {
      // B..D is a spread of 2 (< 3) so the spread rule does NOT fire — the D/F
      // rework rule does.
      final out = await const RouteCapability().run(_routeCtx(const {
        'code-validation': 'B',
        'spec-adherence': 'C',
        'regression-risk': 'C',
        'test-coverage': 'D',
      }));
      expect(out, isA<Gate>());
      expect((out as Gate).reason, contains('rework'));
    });

    test('a MISSING sibling grade ⇒ Gate (fail-closed — can never advance)',
        () async {
      // test-coverage has no recorded grade ⇒ treated as F ⇒ cannot advance.
      final out = await const RouteCapability().run(_routeCtx(const {
        'code-validation': 'A',
        'spec-adherence': 'A',
        'regression-risk': 'A',
      }));
      expect(out, isA<Gate>(), reason: 'an unread/forged-missing grade is F');
      // A missing non-gating grade is F → the D/F rework rule (review C-1).
      expect((out as Gate).reason, contains('rework'));
    });

    test('the gating critic MISSING ⇒ Gate (fail-closed)', () async {
      final out = await const RouteCapability().run(_routeCtx(const {
        'spec-adherence': 'A',
        'regression-risk': 'A',
        'test-coverage': 'A',
      }));
      expect(out, isA<Gate>());
      // A missing gating grade is F → the hard-block rule, not spread (review C-1).
      expect((out as Gate).reason, contains('hard block'));
    });
  });
}
