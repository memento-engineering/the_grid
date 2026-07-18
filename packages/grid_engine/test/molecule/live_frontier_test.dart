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
      );
      expect(invalidated, {'tg-1/inner/work', 'tg-1/inner/route'});
      expect(invalidated, isNot(contains('tg-1/inner')));
    });
  });

  group('derivedGeneration — the derived incarnation axis widens '
      'monotonically as independent objections accumulate', () {
    test('1, 2, then 3 independently-F critics widen build\'s generation '
        'monotonically: 1, 2, 3', () {
      expect(
        derivedGeneration(
          _committee,
          _committeeProjected,
          _committeeResults(['critic-correctness']),
          'tg-1',
          path: 'tg-1/build',
          circuitById: _none,
        ),
        1,
      );
      expect(
        derivedGeneration(
          _committee,
          _committeeProjected,
          _committeeResults(['critic-correctness', 'critic-security']),
          'tg-1',
          path: 'tg-1/build',
          circuitById: _none,
        ),
        2,
      );
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
        ),
        3,
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

    // NOT COVERED (ADR-0000 A52, unresolved): a SECOND successive
    // invalidation round from the SAME recurring `route` source. Under the
    // delivered WIDTH semantics `derivedGeneration` would stay `1` on that
    // second round too (still exactly one distinct invalidating source), so
    // the re-key this test proves for round one does NOT repeat — the
    // "increments monotonically on repeated invalidation" acceptance
    // criterion (`DESIGN-tg-pm6.md` §8) is unmet for the common
    // single-recurring-source case. A golden driving two successive rounds
    // and asserting the key changes each time would fail under current
    // semantics; it is deliberately not added here (would red-gate the
    // house build) pending A52's resolution.
  });

  group('effectiveCursor — the collapse: demote to pending under the cap, '
      'GATE at the cap (derivedEscalation surfaces it instead)', () {
    test('below kMaxReworkRounds: build + its whole closure demote to '
        'pending, keyed by the width', () {
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
      );
      for (final path in [
        'tg-1/build',
        'tg-1/critic-correctness',
        'tg-1/critic-security',
        'tg-1/critic-style',
      ]) {
        expect(effective[path]!.state, StepState.pending, reason: path);
        expect(effective[path]!.rewindCount, 2, reason: path);
      }
      expect(
        derivedEscalation(
          _committee,
          _committeeProjected,
          results,
          'tg-1',
          circuitById: _none,
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
        );
        expect(effective['tg-1/build']!.state, StepState.gated);
        expect(effective['tg-1/build']!.rewindCount, kMaxReworkRounds);

        final escalation = derivedEscalation(
          _committee,
          _committeeProjected,
          results,
          'tg-1',
          circuitById: _none,
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
      );
      final b = effectiveCursor(
        _committee,
        _committeeProjected,
        results,
        'tg-1',
        circuitById: _none,
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
        ),
        returnsNormally,
      );
      final effective = effectiveCursor(
        _committee,
        sparseProjected,
        results,
        'tg-1',
        circuitById: _none,
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
