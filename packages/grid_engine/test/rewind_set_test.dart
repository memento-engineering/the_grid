// tg-o90 — the pure rewind set (routing's actuation surface): the named targets
// ∪ their transitive dependents ∪ SELF, each expanded to its whole subtree.
// Zero I/O, zero Seed — a golden test over the predicate the CapabilityHost maps
// to ONE chokepoint write.
import 'package:grid_engine/grid_engine.dart';
import 'package:test/test.dart';

const _deploy = Circuit(
  id: 'deploy',
  terminalStepId: 'launch',
  steps: [
    CapabilityStep(stepId: 'build', capabilityId: 'build'),
    CapabilityStep(
      stepId: 'launch',
      capabilityId: 'launch',
      kind: StepKind.daemon,
      dependsOn: {'build'},
    ),
  ],
);

/// The FOLDED spec circuit: `specify` and `route` are SIBLINGS, so the route can
/// NAME specify in a Rewind (tg-o90 WHAT #2). `rig` is a sub-circuit sibling —
/// it proves a rewound SubCircuitStep expands to its whole subtree.
const _spec = Circuit(
  id: 'spec_review',
  terminalStepId: 'route',
  steps: [
    CapabilityStep(stepId: 'specify', capabilityId: 'specify'),
    CapabilityStep(
      stepId: 'critic',
      capabilityId: 'critic',
      dependsOn: {'specify'},
    ),
    SubCircuitStep(stepId: 'rig', circuitId: 'deploy', dependsOn: {'specify'}),
    CapabilityStep(
      stepId: 'route',
      capabilityId: 'route',
      dependsOn: {'critic', 'rig'},
    ),
  ],
);

Circuit? _byId(String id) => id == 'deploy' ? _deploy : null;

void main() {
  group('tg-o90 — transitiveDependents', () {
    test('is the downstream closure and EXCLUDES the targets themselves', () {
      expect(transitiveDependents(_spec, {'specify'}), {
        'critic',
        'rig',
        'route',
      });
      expect(transitiveDependents(_spec, {'critic'}), {'route'});
      expect(transitiveDependents(_spec, {'route'}), isEmpty);
    });

    test('a cyclic dependsOn saturates rather than looping forever', () {
      const cyclic = Circuit(
        id: 'c',
        terminalStepId: 'b',
        steps: [
          CapabilityStep(stepId: 'a', capabilityId: 'x', dependsOn: {'b'}),
          CapabilityStep(stepId: 'b', capabilityId: 'x', dependsOn: {'a'}),
        ],
      );
      expect(transitiveDependents(cyclic, {'a'}), {'b'});
    });
  });

  group('tg-o90 — subtreeNodePaths', () {
    test('a leaf is its own path; a sub-circuit expands to its WHOLE subtree',
        () {
      expect(
        subtreeNodePaths('tg-1', _spec.stepById('specify')!, circuitById: _byId),
        {'tg-1/specify'},
      );
      expect(
        subtreeNodePaths('tg-1', _spec.stepById('rig')!, circuitById: _byId),
        {'tg-1/rig', 'tg-1/rig/build', 'tg-1/rig/launch'},
      );
    });

    test('the SAME circuitId under two sibling sub-circuits BOTH expand (never '
        'a global visited-set)', () {
      const twoRigs = Circuit(
        id: 'burn',
        terminalStepId: 'central',
        steps: [
          SubCircuitStep(stepId: 'peripheral', circuitId: 'deploy'),
          SubCircuitStep(
            stepId: 'central',
            circuitId: 'deploy',
            dependsOn: {'peripheral'},
          ),
        ],
      );
      final paths = <String>{
        for (final step in twoRigs.steps)
          ...subtreeNodePaths('tg-b', step, circuitById: _byId),
      };
      expect(paths, {
        'tg-b/peripheral',
        'tg-b/peripheral/build',
        'tg-b/peripheral/launch',
        'tg-b/central',
        'tg-b/central/build',
        'tg-b/central/launch',
      });
    });

    test('an unresolvable sub-circuit contributes only its own path, and a '
        'self-referential circuit id terminates', () {
      expect(
        subtreeNodePaths(
          'tg-1',
          _spec.stepById('rig')!,
          circuitById: (_) => null,
        ),
        {'tg-1/rig'},
      );
      const loop = Circuit(
        id: 'loop',
        terminalStepId: 'again',
        steps: [SubCircuitStep(stepId: 'again', circuitId: 'loop')],
      );
      expect(
        subtreeNodePaths('tg-1', loop.steps.single, circuitById: (_) => loop),
        {'tg-1/again', 'tg-1/again/again'},
      );
    });
  });

  group('tg-o90 — rewindNodePaths', () {
    test('names targets + transitive dependents + SELF, expanding sub-circuits',
        () {
      expect(
        rewindNodePaths(
          _spec,
          'tg-1',
          {'specify'},
          selfStepId: 'route',
          circuitById: _byId,
        ),
        {
          'tg-1/specify',
          'tg-1/critic',
          'tg-1/rig',
          'tg-1/rig/build',
          'tg-1/rig/launch',
          'tg-1/route',
        },
      );
    });

    test('a NARROW rewind resets only that branch — SELF is always in the set',
        () {
      expect(
        rewindNodePaths(
          _spec,
          'tg-1',
          {'critic'},
          selfStepId: 'route',
          circuitById: _byId,
        ),
        {'tg-1/critic', 'tg-1/route'},
      );
    });

    test('a dangling target id is SKIPPED here (the host fails LOUD first)', () {
      expect(
        rewindNodePaths(
          _spec,
          'tg-1',
          {'nope'},
          selfStepId: 'route',
          circuitById: _byId,
        ),
        {'tg-1/route'},
      );
    });
  });
}
