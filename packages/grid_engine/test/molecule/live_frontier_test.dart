// R4 — live_frontier: invalidation, derived generation, effectiveCursor.
//
// Pure golden tests, mirroring rewind_set_test.dart / rewind_arm_test.dart in
// spirit: zero I/O, zero Seed, zero tree — every function under test is a free
// function over (Circuit, CircuitCursor, CircuitResults, nodePath). The
// committee fixture (`build` + `critic-correctness` / `critic-security` /
// `critic-style`, each validating `build`) mirrors molecule_codec_test.dart's
// own `_codeCircuit` swarm shape exactly, so the two molecule test files stay
// comparable at a glance.
//
// DESIGN-tg-pm6.md §8 / §14. Zero I/O.
import 'package:grid_engine/grid_engine.dart';
import 'package:grid_engine/src/molecule/live_frontier.dart';
import 'package:grid_engine/src/molecule/molecule_schema.dart';
import 'package:test/test.dart';

Circuit? _none(String _) => null;

// --- the committee fixture (mirrors molecule_codec_test.dart's _codeCircuit) -

const _committee = Circuit(
  id: 'code',
  terminalStepId: 'land',
  steps: [
    CapabilityStep(stepId: 'build', capabilityId: 'build'),
    CapabilityStep(
      stepId: 'critic-correctness',
      capabilityId: 'critic',
      dependsOn: {'build'},
      params: {kValidatesParam: 'build'},
    ),
    CapabilityStep(
      stepId: 'critic-security',
      capabilityId: 'critic',
      dependsOn: {'build'},
      params: {kValidatesParam: 'build'},
    ),
    CapabilityStep(
      stepId: 'critic-style',
      capabilityId: 'critic',
      dependsOn: {'build'},
      params: {kValidatesParam: 'build'},
    ),
    CapabilityStep(
      stepId: 'land',
      capabilityId: 'land',
      dependsOn: {'critic-correctness', 'critic-security', 'critic-style'},
    ),
  ],
);

/// build + every critic already ran once and completed (land has never run).
const _committeeProjected = <String, NodeCursor>{
  'tg-1/build': NodeCursor(state: StepState.complete),
  'tg-1/critic-correctness': NodeCursor(state: StepState.complete),
  'tg-1/critic-security': NodeCursor(state: StepState.complete),
  'tg-1/critic-style': NodeCursor(state: StepState.complete),
};

/// The results snapshot with exactly [failing] critics currently stamped F.
CircuitResults _committeeResults(Iterable<String> failing) => {
  for (final critic in failing) 'tg-1/$critic': {ResultKeys.grade: 'F'},
};

DateTime _clock() => DateTime.utc(2026, 7, 17);

Map<String, int> _depths(int depth) => {'tg-1/build': depth};

// --- the daemon fixture (mirrors rewind_arm_test.dart's _daemonSpec) --------

/// `harness` is a dep-free DAEMON validated by `route` — the re-key isolation
/// shape: once `route` stamps an invalidating grade, `harness`'s DERIVED
/// rewindCount must change even though nothing wrote to it, so the UNCHANGED
/// `ValueKey('$path#$restart.$rewind')` (`circuit_scope.dart:100`) re-keys and
/// a still-mounted daemon is torn down and re-run virgin.
const _daemonSpec = Circuit(
  id: 'code',
  terminalStepId: 'route',
  steps: [
    CapabilityStep(
      stepId: 'harness',
      capabilityId: 'harness',
      kind: StepKind.daemon,
    ),
    CapabilityStep(
      stepId: 'route',
      capabilityId: 'route',
      dependsOn: {'harness'},
      params: {kValidatesParam: 'harness'},
    ),
  ],
);

/// The exact reconcile-key material `CircuitScope` computes
/// (`circuit_scope.dart:100`) — reproduced here as a plain string so a pure
/// test can prove a re-key without mounting a tree.
String _keyMaterial(NodeCursor node) =>
    '${node.restartCount}.${node.rewindCount}';

// --- the nested sub-circuit fixture (SCOPE: never reaches the parent) ------

const _innerCircuit = Circuit(
  id: 'inner',
  terminalStepId: 'route',
  steps: [
    CapabilityStep(stepId: 'work', capabilityId: 'work'),
    CapabilityStep(
      stepId: 'route',
      capabilityId: 'route',
      dependsOn: {'work'},
      params: {kValidatesParam: 'work'},
    ),
  ],
);

const _outerCircuit = Circuit(
  id: 'outer',
  terminalStepId: 'inner',
  steps: [SubCircuitStep(stepId: 'inner', circuitId: 'inner')],
);

Circuit? _resolveInner(String id) => id == 'inner' ? _innerCircuit : null;

void main() {
  group('liveFrontier — forward AND backward both fall out of it', () {
    test('forward: with nothing invalidated, liveFrontier == eligibleSteps '
        'over the RAW projected cursor (byte-for-byte the flat model\'s '
        'shape)', () {
      final expected = eligibleSteps(
        _committee,
        _committeeProjected,
        'tg-1',
        circuitById: _none,
        now: _clock(),
      );
      final actual = liveFrontier(
        _committee,
        _committeeProjected,
        const {},
        'tg-1',
        circuitById: _none,
        supersedesDepthByPath: const {},
        now: _clock(),
      );
      expect(actual, expected);
      expect(actual.map((s) => s.stepId), ['land']);
    });

    test('backward: a downstream invalidating stamp derives `build` back into '
        'the live frontier, with NO write anywhere — build/critics/land are '
        'ALL still `complete` in the untouched projected cursor', () {
      final results = _committeeResults([
        'critic-correctness',
        'critic-security',
      ]);
      final frontier = liveFrontier(
        _committee,
        _committeeProjected,
        results,
        'tg-1',
        circuitById: _none,
        supersedesDepthByPath: const {},
        now: _clock(),
      );
      // build re-enters the frontier purely from the derivation; its
      // dependents (the critics, gated on build's now-non-terminal state)
      // stay withheld until build completes again — the SAME await-all
      // barrier depsSatisfied has always enforced, untouched.
      expect(frontier.map((s) => s.stepId), ['build']);
      // The projected cursor itself was never touched (no write exists here).
      expect(_committeeProjected['tg-1/build']!.state, StepState.complete);
    });
  });

  group('generation-atomic waves (tg-ev2w) — a predecessor-generation '
      'terminal never satisfies a successor-generation dep', () {
    // The tg-60t interleave, mid-wave: the wave re-keyed the SOURCE
    // (critic-correctness) and the sibling critics to depth 1, so the F stamp
    // no longer invalidates (the fixed-point guard) — but the TARGET (build)
    // has not been re-keyed yet and still projects its PREDECESSOR
    // incarnation's positive terminal. Pre-fix, that stale terminal satisfied
    // the re-keyed critics' deps and they spawned against the OLD build.
    final midWaveProjected = <String, NodeCursor>{
      // build: NOT yet re-keyed — stale generation-0 positive terminal.
      'tg-1/build': const NodeCursor(state: StepState.complete),
      // critics: re-keyed to generation 1, successor beads pending.
      'tg-1/critic-correctness': const NodeCursor(state: StepState.pending),
      'tg-1/critic-security': const NodeCursor(state: StepState.pending),
      'tg-1/critic-style': const NodeCursor(state: StepState.pending),
    };
    const midWaveDepths = <String, int>{
      'tg-1/critic-correctness': 1,
      'tg-1/critic-security': 1,
      'tg-1/critic-style': 1,
    };
    // The evaporated stamp: the source's PRIOR incarnation graded F, but its
    // successor bead is pending — _stampInvalidates correctly refuses it.
    final midWaveResults = _committeeResults(['critic-correctness']);

    test('mid-wave: a successor-generation lane is NOT runnable off a '
        'predecessor-generation dep terminal (the tg-60t early-spawn)', () {
      final frontier = liveFrontier(
        _committee,
        midWaveProjected,
        midWaveResults,
        'tg-1',
        circuitById: _none,
        supersedesDepthByPath: midWaveDepths,
        now: _clock(),
      );
      // The stale build terminal is DEMOTED by generation skew, so the
      // generation-1 critics' deps are unsatisfied — only build (its deps
      // are empty) is runnable: the wave completes instead of interleaving.
      expect(frontier.map((s) => s.stepId), ['build']);
    });

    test('mid-wave: the trailing member re-enters invalidatedNodes even '
        'though the stamp evaporated — the successor-mint machinery can '
        'resume a died-mid-wave re-key after a bounce', () {
      expect(
        invalidatedNodes(
          _committee,
          midWaveProjected,
          midWaveResults,
          'tg-1',
          circuitById: _none,
          supersedesDepthByPath: midWaveDepths,
        ),
        contains('tg-1/build'),
      );
    });

    test('mid-wave: effectiveCursor demotes ONLY the stale terminal — '
        'same-generation members pass through untouched', () {
      final effective = effectiveCursor(
        _committee,
        midWaveProjected,
        midWaveResults,
        'tg-1',
        circuitById: _none,
        supersedesDepthByPath: midWaveDepths,
      );
      expect(effective['tg-1/build']!.state, StepState.pending);
      expect(effective['tg-1/build']!.rewindCount, 1);
      expect(effective['tg-1/critic-security']!.state, StepState.pending);
      expect(effective['tg-1/critic-security']!.rewindCount, 0);
    });

    test('bounce-resume: once the dep re-runs IN the current generation, the '
        'demoted-pending lanes whose deps are satisfied DO spawn (the '
        'pow-dhq stall half)', () {
      final resumedProjected = <String, NodeCursor>{
        // build: re-keyed AND re-run — a fresh generation-1 terminal.
        'tg-1/build': const NodeCursor(state: StepState.complete),
        'tg-1/critic-correctness': const NodeCursor(state: StepState.pending),
        'tg-1/critic-security': const NodeCursor(state: StepState.pending),
        'tg-1/critic-style': const NodeCursor(state: StepState.pending),
      };
      const resumedDepths = <String, int>{
        'tg-1/build': 1,
        'tg-1/critic-correctness': 1,
        'tg-1/critic-security': 1,
        'tg-1/critic-style': 1,
      };
      final frontier = liveFrontier(
        _committee,
        resumedProjected,
        // The prior incarnation's F grade lingers in results — the pending
        // successor source must not re-invalidate on it (unchanged guard).
        midWaveResults,
        'tg-1',
        circuitById: _none,
        supersedesDepthByPath: resumedDepths,
        now: _clock(),
      );
      expect(frontier.map((s) => s.stepId), [
        'critic-correctness',
        'critic-security',
        'critic-style',
      ]);
    });

    test('at rest after a COMPLETED wave (uniform depths, fresh terminals, '
        'no stamp) nothing is demoted — no false re-runs', () {
      const restDepths = <String, int>{
        'tg-1/build': 1,
        'tg-1/critic-correctness': 1,
        'tg-1/critic-security': 1,
        'tg-1/critic-style': 1,
      };
      expect(
        invalidatedNodes(
          _committee,
          _committeeProjected,
          const {},
          'tg-1',
          circuitById: _none,
          supersedesDepthByPath: restDepths,
        ),
        isEmpty,
      );
      final frontier = liveFrontier(
        _committee,
        _committeeProjected,
        const {},
        'tg-1',
        circuitById: _none,
        supersedesDepthByPath: restDepths,
        now: _clock(),
      );
      expect(frontier.map((s) => s.stepId), ['land']);
    });
  });

  group('invalidatedNodes — the validates-source stamp + its target\'s '
      'transitive-dependent closure (mirrors rewindNodePaths exactly)', () {
    test('one invalidating critic demotes build + EVERY transitive dependent '
        '(the other critics AND land), never anything upstream', () {
      final results = _committeeResults(['critic-correctness']);
      expect(
        invalidatedNodes(
          _committee,
          _committeeProjected,
          results,
          'tg-1',
          circuitById: _none,
          supersedesDepthByPath: const {},
        ),
        {
          'tg-1/build',
          'tg-1/critic-correctness',
          'tg-1/critic-security',
          'tg-1/critic-style',
          'tg-1/land',
        },
      );
    });

    test('a PASSING grade never invalidates', () {
      expect(
        invalidatedNodes(
          _committee,
          _committeeProjected,
          {
            'tg-1/critic-correctness': {ResultKeys.grade: 'A'},
          },
          'tg-1',
          circuitById: _none,
          supersedesDepthByPath: const {},
        ),
        isEmpty,
      );
    });

    test('a validates-source stamped F but NOT YET a positive terminal '
        '(freshly demoted, not re-run) does NOT invalidate — the fixed-point '
        'guard against re-reading a STALE prior grade', () {
      final staleProjected = {
        ..._committeeProjected,
        'tg-1/critic-correctness': const NodeCursor(state: StepState.pending),
      };
      final staleResults = _committeeResults(['critic-correctness']);
      expect(
        invalidatedNodes(
          _committee,
          staleProjected,
          staleResults,
          'tg-1',
          circuitById: _none,
          supersedesDepthByPath: const {},
        ),
        isEmpty,
      );
    });

    test('a lowercase grade still invalidates — case-insensitive, matching '
        "grid_cli's gate_command.dart convention", () {
      expect(
        invalidatedNodes(
          _committee,
          _committeeProjected,
          {
            'tg-1/critic-correctness': {ResultKeys.grade: 'f'},
          },
          'tg-1',
          circuitById: _none,
          supersedesDepthByPath: const {},
        ),
        contains('tg-1/build'),
      );
    });

    test('a dangling validates target mints no edge — fail-closed, never '
        'throws', () {
      const dangling = Circuit(
        id: 'x',
        terminalStepId: 'critic',
        steps: [
          CapabilityStep(
            stepId: 'critic',
            capabilityId: 'critic',
            params: {kValidatesParam: 'nope'},
          ),
        ],
      );
      final projected = {
        'tg-1/critic': const NodeCursor(state: StepState.complete),
      };
      final results = {
        'tg-1/critic': {ResultKeys.grade: 'F'},
      };
      expect(
        () => invalidatedNodes(
          dangling,
          projected,
          results,
          'tg-1',
          circuitById: _none,
          supersedesDepthByPath: const {},
        ),
        returnsNormally,
      );
      expect(
        invalidatedNodes(
          dangling,
          projected,
          results,
          'tg-1',
          circuitById: _none,
          supersedesDepthByPath: const {},
        ),
        isEmpty,
      );
    });

    test('a validates edge inside a NESTED sub-circuit only invalidates '
        'within its OWN circuit level — never reaches the parent (mirrors '
        "rewindNodePaths's SCOPE guarantee)", () {
      final projected = {
        'tg-1/inner/work': const NodeCursor(state: StepState.complete),
        'tg-1/inner/route': const NodeCursor(state: StepState.complete),
      };
      final results = {
        'tg-1/inner/route': {ResultKeys.grade: 'F'},
      };
      final invalidated = invalidatedNodes(
        _outerCircuit,
        projected,
        results,
        'tg-1',
        circuitById: _resolveInner,
        supersedesDepthByPath: const {},
      );
      expect(invalidated, {'tg-1/inner/work', 'tg-1/inner/route'});
      expect(invalidated, isNot(contains('tg-1/inner')));
    });
  });

  group(
    'derivedGeneration — the derived incarnation axis is supersedes depth',
    () {
      test('one recurring critic derives generation 1 then 2 across two '
          'successor rounds', () {
        final results = _committeeResults(['critic-correctness']);
        expect(
          derivedGeneration(
            _committee,
            _committeeProjected,
            results,
            'tg-1',
            path: 'tg-1/build',
            circuitById: _none,
            supersedesDepthByPath: _depths(1),
          ),
          1,
        );
        expect(
          derivedGeneration(
            _committee,
            _committeeProjected,
            results,
            'tg-1',
            path: 'tg-1/build',
            circuitById: _none,
            supersedesDepthByPath: _depths(2),
          ),
          2,
        );
      });

      test('three first-round critics still spend only round depth 1', () {
        expect(
          derivedGeneration(
            _committee,
            _committeeProjected,
            _committeeResults([
              'critic-correctness',
              'critic-security',
              'critic-style',
            ]),
            'tg-1',
            path: 'tg-1/build',
            circuitById: _none,
            supersedesDepthByPath: _depths(1),
          ),
          1,
        );
      });

      test('zero for a node nothing currently invalidates', () {
        expect(
          derivedGeneration(
            _committee,
            _committeeProjected,
            const {},
            'tg-1',
            path: 'tg-1/build',
            circuitById: _none,
            supersedesDepthByPath: const {},
          ),
          0,
        );
      });

      test('re-keys a _daemonSpec-style daemon fixture: the derived generation '
          "bump changes CircuitScope's reconcile-key material even though "
          'NOTHING wrote to the daemon\'s node', () {
        const projected = <String, NodeCursor>{
          'tg-1/harness': NodeCursor(state: StepState.ready),
          'tg-1/route': NodeCursor(state: StepState.complete),
        };
        final beforeKey = _keyMaterial(projected['tg-1/harness']!);

        final results = {
          'tg-1/route': {ResultKeys.grade: 'F'},
        };
        final effective = effectiveCursor(
          _daemonSpec,
          projected,
          results,
          'tg-1',
          circuitById: _none,
          supersedesDepthByPath: {'tg-1/harness': 1},
        );
        final afterKey = _keyMaterial(effective['tg-1/harness']!);

        expect(
          afterKey,
          isNot(beforeKey),
          reason:
              'the reconcile key must '
              'change so keyed reconcile tears the still-mounted daemon down and '
              're-mounts it virgin',
        );
        expect(effective['tg-1/harness']!.state, StepState.pending);
        expect(effective['tg-1/harness']!.rewindCount, 1);
        // The still-mounted daemon's TRUE underlying cursor entry is untouched
        // — no write exists on this path at all.
        expect(projected['tg-1/harness']!.state, StepState.ready);
      });
    },
  );

  group('effectiveCursor — the collapse: demote to pending under the cap, '
      'GATE at the cap (derivedEscalation surfaces it instead)', () {
    test('below kMaxReworkRounds: build + its whole closure demote to '
        'pending, keyed by supersedes depth', () {
      final results = _committeeResults([
        'critic-correctness',
        'critic-security',
      ]);
      final effective = effectiveCursor(
        _committee,
        _committeeProjected,
        results,
        'tg-1',
        circuitById: _none,
        supersedesDepthByPath: _depths(1),
      );
      for (final path in [
        'tg-1/build',
        'tg-1/critic-correctness',
        'tg-1/critic-security',
        'tg-1/critic-style',
      ]) {
        expect(effective[path]!.state, StepState.pending, reason: path);
        expect(effective[path]!.rewindCount, 1, reason: path);
      }
      expect(
        derivedEscalation(
          _committee,
          _committeeProjected,
          results,
          'tg-1',
          circuitById: _none,
          supersedesDepthByPath: _depths(1),
        ),
        isNull,
      );
    });

    test('three first-round critics do not gate at depth 1', () {
      final results = _committeeResults([
        'critic-correctness',
        'critic-security',
        'critic-style',
      ]);
      final effective = effectiveCursor(
        _committee,
        _committeeProjected,
        results,
        'tg-1',
        circuitById: _none,
        supersedesDepthByPath: _depths(1),
      );
      expect(effective['tg-1/build']!.state, StepState.pending);
      expect(effective['tg-1/build']!.rewindCount, 1);
      expect(
        derivedEscalation(
          _committee,
          _committeeProjected,
          results,
          'tg-1',
          circuitById: _none,
          supersedesDepthByPath: _depths(1),
        ),
        isNull,
      );
    });

    test(
      'AT kMaxReworkRounds: the node GATES instead of demoting, and '
      'derivedEscalation surfaces the FIRST such node in declaration order',
      () {
        expect(
          kMaxReworkRounds,
          3,
          reason:
              'this fixture is built for the '
              'live cap value; if it moves, this test documents the new one',
        );
        final results = _committeeResults([
          'critic-correctness',
          'critic-security',
          'critic-style',
        ]);
        final effective = effectiveCursor(
          _committee,
          _committeeProjected,
          results,
          'tg-1',
          circuitById: _none,
          supersedesDepthByPath: _depths(kMaxReworkRounds),
        );
        expect(effective['tg-1/build']!.state, StepState.gated);
        expect(effective['tg-1/build']!.rewindCount, kMaxReworkRounds);

        final escalation = derivedEscalation(
          _committee,
          _committeeProjected,
          results,
          'tg-1',
          circuitById: _none,
          supersedesDepthByPath: _depths(kMaxReworkRounds),
        );
        expect(escalation, isNotNull);
        expect(escalation!.path, 'tg-1/build');
        expect(escalation.reason, contains('rework cap reached (3/3)'));

        // A gated node is withheld from the frontier by the UNCHANGED
        // frontier.dart runnable-state gate — no edit, no second check.
        expect(
          liveFrontier(
            _committee,
            _committeeProjected,
            results,
            'tg-1',
            circuitById: _none,
            supersedesDepthByPath: _depths(kMaxReworkRounds),
            now: _clock(),
          ),
          isEmpty,
        );
      },
    );
  });

  group('totality/idempotency on partial or missing stamps (Q4)', () {
    test('empty results: effectiveCursor returns the SAME projected cursor, '
        'unchanged', () {
      expect(
        effectiveCursor(
          _committee,
          _committeeProjected,
          const {},
          'tg-1',
          circuitById: _none,
          supersedesDepthByPath: const {},
        ),
        same(_committeeProjected),
      );
    });

    test('calling effectiveCursor twice on the identical snapshot returns '
        'value-equal cursors — pure, no hidden state', () {
      final results = _committeeResults(['critic-correctness']);
      final a = effectiveCursor(
        _committee,
        _committeeProjected,
        results,
        'tg-1',
        circuitById: _none,
        supersedesDepthByPath: _depths(1),
      );
      final b = effectiveCursor(
        _committee,
        _committeeProjected,
        results,
        'tg-1',
        circuitById: _none,
        supersedesDepthByPath: _depths(1),
      );
      expect(a, b);
    });

    test('a result entry for a node with NO cursor entry at all never '
        'throws, and demotes from the default pending NodeCursor', () {
      final results = {
        'tg-1/critic-correctness': {ResultKeys.grade: 'F'},
      };
      final sparseProjected = {
        'tg-1/critic-correctness': const NodeCursor(state: StepState.complete),
      };
      expect(
        () => effectiveCursor(
          _committee,
          sparseProjected,
          results,
          'tg-1',
          circuitById: _none,
          supersedesDepthByPath: const {},
        ),
        returnsNormally,
      );
      final effective = effectiveCursor(
        _committee,
        sparseProjected,
        results,
        'tg-1',
        circuitById: _none,
        supersedesDepthByPath: const {},
      );
      expect(effective['tg-1/build']!.state, StepState.pending);
    });

    test(
      'no validates edges at all: liveFrontier == eligibleSteps, exactly',
      () {
        const plain = Circuit(
          id: 'plain',
          terminalStepId: 'a',
          steps: [CapabilityStep(stepId: 'a', capabilityId: 'a')],
        );
        const cursor = <String, NodeCursor>{};
        expect(
          liveFrontier(
            plain,
            cursor,
            const {},
            'tg-1',
            circuitById: _none,
            supersedesDepthByPath: const {},
            now: _clock(),
          ),
          eligibleSteps(
            plain,
            cursor,
            'tg-1',
            circuitById: _none,
            now: _clock(),
          ),
        );
      },
    );
  });
}
