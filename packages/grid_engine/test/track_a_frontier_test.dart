// Track A — the pure reentrant model: the eligibility predicate computes the
// mount frontier (the barrier IS the predicate withholding a step), and the
// value-types round-trip through one JSON shape.
//
// ADR-0008 D4 / M4-P1 Track A, §3/§4. Zero I/O — pure value-types only.
import 'dart:convert';

import 'package:grid_engine/grid_engine.dart';
import 'package:test/test.dart';

/// A faithful round-trip: serialize to a JSON *string* and back, so nested
/// value-types are genuinely encoded (the "two serializations of one shape"
/// proof — TOML maps to the same shape later).
Map<String, dynamic> _roundTrip(Map<String, dynamic> json) =>
    jsonDecode(jsonEncode(json)) as Map<String, dynamic>;

// ---------------------------------------------------------------------------
// The two canonical formulas (M4-P1 §6 + §9), and a registry over them.
// ---------------------------------------------------------------------------

/// agent → verify → land — the degenerate linear formula whose always-1-wide
/// frontier reproduces P0 (§6).
const code = Formula(
  id: 'code',
  terminalStepId: 'land',
  steps: [
    CapabilityStep(stepId: 'agent', capabilityId: 'agent'),
    CapabilityStep(
      stepId: 'verify',
      capabilityId: 'verify',
      dependsOn: {'agent'},
    ),
    CapabilityStep(stepId: 'land', capabilityId: 'land', dependsOn: {'verify'}),
  ],
);

/// build → install → launch(daemon) → waitWS — the harness deploy (§9), with a
/// long-lived daemon that satisfies on `ready` while staying mounted.
const deploy = Formula(
  id: 'deploy',
  terminalStepId: 'waitWS',
  steps: [
    CapabilityStep(stepId: 'build', capabilityId: 'b'),
    CapabilityStep(stepId: 'install', capabilityId: 'i', dependsOn: {'build'}),
    CapabilityStep(
      stepId: 'launch',
      capabilityId: 'l',
      kind: StepKind.daemon,
      dependsOn: {'install'},
    ),
    CapabilityStep(stepId: 'waitWS', capabilityId: 'w', dependsOn: {'launch'}),
  ],
);

/// The Burn (§9): two deploy sub-formulas (ordered: peripheral before central),
/// a coordinator gated on an await-all barrier over both, then a report.
const burn = Formula(
  id: 'burn',
  terminalStepId: 'report',
  supervision: SupervisionStrategy.restForOne,
  peak: ResourceRequest(builds: 2, processes: 3),
  steps: [
    SubFormulaStep(stepId: 'harnessPeripheral', formulaId: 'deploy'),
    SubFormulaStep(
      stepId: 'harnessCentral',
      formulaId: 'deploy',
      dependsOn: {'harnessPeripheral'}, // ordering barrier
    ),
    CapabilityStep(
      stepId: 'coordinator',
      capabilityId: 'coord',
      dependsOn: {'harnessPeripheral', 'harnessCentral'}, // await-all barrier
    ),
    CapabilityStep(
      stepId: 'report',
      capabilityId: 'report',
      dependsOn: {'coordinator'},
    ),
  ],
);

const _registry = {'deploy': deploy};
Formula? _byId(String id) => _registry[id];

final _now = DateTime(2026);

/// The eligible step ids of [formula] under [cursor] at [nodePath], in order.
List<String> _frontier(
  Formula formula,
  FormulaCursor cursor,
  String nodePath,
) =>
    eligibleSteps(formula, cursor, nodePath, formulaById: _byId, now: _now)
        .map((s) => s.stepId)
        .toList();

NodeCursor _c(
  StepState state, {
  int restartCount = 0,
  DateTime? cooldownUntil,
}) =>
    NodeCursor(
      state: state,
      restartCount: restartCount,
      cooldownUntil: cooldownUntil,
    );

void main() {
  group('Track A — linear frontier (1-wide at every cursor; §6 parity)', () {
    test('empty cursor → only the dep-free first step is eligible', () {
      expect(_frontier(code, const {}, 'tg-1'), ['agent']);
    });

    test('agent complete → verify (agent retired, land withheld)', () {
      expect(
        _frontier(code, {'tg-1/agent': _c(StepState.complete)}, 'tg-1'),
        ['verify'],
      );
    });

    test('agent+verify complete → land', () {
      expect(
        _frontier(
          code,
          {
            'tg-1/agent': _c(StepState.complete),
            'tg-1/verify': _c(StepState.complete),
          },
          'tg-1',
        ),
        ['land'],
      );
    });

    test('all complete → empty frontier, and the formula is complete', () {
      final cursor = {
        'tg-1/agent': _c(StepState.complete),
        'tg-1/verify': _c(StepState.complete),
        'tg-1/land': _c(StepState.complete),
      };
      expect(_frontier(code, cursor, 'tg-1'), isEmpty);
      expect(
        isFormulaComplete(code, cursor, 'tg-1', formulaById: _byId),
        isTrue,
      );
      expect(isFormulaBroken(code, cursor, 'tg-1'), isFalse);
    });

    test('a running step stays in the frontier (not unmounted)', () {
      expect(
        _frontier(code, {'tg-1/agent': _c(StepState.running)}, 'tg-1'),
        ['agent'],
      );
    });
  });

  group('Track A — fan-out + ordering + the await-all barrier (§9)', () {
    test('empty cursor → only the peripheral (central ordered after it)', () {
      expect(_frontier(burn, const {}, 'b'), ['harnessPeripheral']);
    });

    test(
      'peripheral terminal-descendant complete → central enters; coordinator '
      'still withheld (only one barrier dep met)',
      () {
        final cursor = {
          'b/harnessPeripheral/waitWS': _c(StepState.complete),
        };
        // The sub-formula step itself stays mounted (daemons live under it).
        expect(
          _frontier(burn, cursor, 'b'),
          ['harnessPeripheral', 'harnessCentral'],
        );
      },
    );

    test('BOTH barrier deps terminal → coordinator enters', () {
      final cursor = {
        'b/harnessPeripheral/waitWS': _c(StepState.complete),
        'b/harnessCentral/waitWS': _c(StepState.complete),
      };
      expect(
        _frontier(burn, cursor, 'b'),
        ['harnessPeripheral', 'harnessCentral', 'coordinator'],
      );
    });

    test('coordinator complete → report enters', () {
      final cursor = {
        'b/harnessPeripheral/waitWS': _c(StepState.complete),
        'b/harnessCentral/waitWS': _c(StepState.complete),
        'b/coordinator': _c(StepState.complete),
      };
      expect(
        _frontier(burn, cursor, 'b'),
        ['harnessPeripheral', 'harnessCentral', 'report'],
      );
    });
  });

  group('Track A — daemon semantics (ready satisfies + stays; death re-closes)',
      () {
    test('a daemon at ready stays mounted AND satisfies its dependent', () {
      final cursor = {
        'd/build': _c(StepState.complete),
        'd/install': _c(StepState.complete),
        'd/launch': _c(StepState.ready),
      };
      // build/install retired (complete jobs); launch (daemon, ready) stays;
      // waitWS enters (its dep launch is a positive terminal).
      expect(_frontier(deploy, cursor, 'd'), ['launch', 'waitWS']);
    });

    test('a daemon death (failed) re-closes the barrier (OQ-5)', () {
      final cursor = {
        'd/build': _c(StepState.complete),
        'd/install': _c(StepState.complete),
        'd/launch': _c(StepState.failed), // was ready; the process died
      };
      // launch routes to supervision (re-key within budget); waitWS withheld
      // again because launch is no longer a positive terminal.
      expect(_frontier(deploy, cursor, 'd'), ['launch']);
    });
  });

  group('Track A — positive-terminal-only + supervision', () {
    test('a failed dep never satisfies (the half-up-rig guard)', () {
      final cursor = {'d/build': _c(StepState.failed)};
      // build re-keys (within budget); install/launch/waitWS all withheld.
      expect(_frontier(deploy, cursor, 'd'), ['build']);
    });

    test('a circuit-broken step (failed AND exhausted) is withheld + escalates',
        () {
      final cursor = {
        'd/build': _c(StepState.failed, restartCount: 3), // == maxRestarts(3)
      };
      expect(_frontier(deploy, cursor, 'd'), isEmpty);
      expect(isCircuitBroken(deploy, deploy.steps.first, cursor, 'd'), isTrue);
      expect(isFormulaBroken(deploy, cursor, 'd'), isTrue);
      expect(
        isFormulaComplete(deploy, cursor, 'd', formulaById: _byId),
        isFalse,
        reason: 'empty-because-broken is NOT empty-because-complete (D-5)',
      );
    });

    test('restartCount BEYOND maxRestarts is still circuit-broken (>=, not ==)',
        () {
      final cursor = {
        'd/build': _c(StepState.failed, restartCount: 4), // > maxRestarts(3)
      };
      expect(_frontier(deploy, cursor, 'd'), isEmpty);
      expect(isCircuitBroken(deploy, deploy.steps.first, cursor, 'd'), isTrue);
      expect(isFormulaBroken(deploy, cursor, 'd'), isTrue);
    });

    test('a failed step within budget but still cooling is withheld', () {
      final cursor = {
        'd/build': _c(
          StepState.failed,
          restartCount: 1,
          cooldownUntil: _now.add(const Duration(seconds: 10)),
        ),
      };
      expect(_frontier(deploy, cursor, 'd'), isEmpty);
    });

    test('a failed step within budget past cooldown re-keys (eligible)', () {
      final cursor = {
        'd/build': _c(
          StepState.failed,
          restartCount: 1,
          cooldownUntil: _now.subtract(const Duration(seconds: 1)),
        ),
      };
      expect(_frontier(deploy, cursor, 'd'), ['build']);
    });

    test('cooldown boundary: now == cooldownUntil is eligible (>= not >)', () {
      final cursor = {
        'd/build': _c(StepState.failed, restartCount: 1, cooldownUntil: _now),
      };
      expect(_frontier(deploy, cursor, 'd'), ['build']);
    });
  });

  group('Track A — isFormulaComplete descends into a sub-formula terminal', () {
    // The regression guard for the asymmetry the adversarial review found: a
    // SubFormulaStep has no host, so its OWN cursor node is never written.
    // isFormulaComplete must resolve a sub-formula terminal to its terminal-step
    // DESCENDANT, or the session would never close (the indefinite mount D-5
    // forbids).
    const outer = Formula(
      id: 'outer',
      terminalStepId: 'wrap', // a sub-formula as the terminal step
      steps: [SubFormulaStep(stepId: 'wrap', formulaId: 'deploy')],
    );

    test('not complete while the sub-formula terminal descendant is pending',
        () {
      expect(
        isFormulaComplete(outer, const {}, 'n', formulaById: _byId),
        isFalse,
      );
    });

    test('complete once the descendant terminal (waitWS) is a positive terminal',
        () {
      final cursor = {
        'n/wrap/waitWS': _c(StepState.complete),
      };
      expect(
        isFormulaComplete(outer, cursor, 'n', formulaById: _byId),
        isTrue,
      );
    });
  });

  group('Track A — fail-closed dep resolution', () {
    test('a dangling dep id is never satisfiable', () {
      const f = Formula(
        id: 'x',
        terminalStepId: 'a',
        steps: [
          CapabilityStep(stepId: 'a', capabilityId: 'a', dependsOn: {'ghost'}),
        ],
      );
      expect(_frontier(f, const {}, 'n'), isEmpty);
    });

    test('a sub-formula dep with an unknown formulaId is never satisfiable', () {
      const f = Formula(
        id: 'x',
        terminalStepId: 'b',
        steps: [
          SubFormulaStep(stepId: 's', formulaId: 'missing'),
          CapabilityStep(stepId: 'b', capabilityId: 'b', dependsOn: {'s'}),
        ],
      );
      // The sub-formula step itself is eligible (pending), but 'b' is withheld
      // because 's' resolves to no terminal path (fail-closed).
      expect(_frontier(f, const {}, 'n'), ['s']);
    });
  });

  group('Track A — Backoff.delayFor', () {
    test('attempt ≤1 yields min; growth doubles and clamps to max', () {
      const b = Backoff(
        min: Duration(seconds: 1),
        max: Duration(seconds: 8),
      );
      expect(b.delayFor(0), const Duration(seconds: 1));
      expect(b.delayFor(1), const Duration(seconds: 1));
      expect(b.delayFor(2), const Duration(seconds: 2));
      expect(b.delayFor(3), const Duration(seconds: 4));
      expect(b.delayFor(4), const Duration(seconds: 8));
      expect(b.delayFor(99), const Duration(seconds: 8)); // clamped
    });
  });

  group('Track A — one shape, two serializations (JSON round-trip)', () {
    test('a multi-step fan-out Formula round-trips identically', () {
      expect(Formula.fromJson(_roundTrip(burn.toJson())), burn);
    });

    test('the linear code Formula round-trips identically', () {
      expect(Formula.fromJson(_roundTrip(code.toJson())), code);
    });

    test('a CapabilityStep with resources + a daemon kind round-trips', () {
      const step = CapabilityStep(
        stepId: 's',
        capabilityId: 'c',
        params: {'role': 'central'},
        dependsOn: {'x', 'y'},
        kind: StepKind.daemon,
        resources: ResourceRequest(builds: 1, processes: 2),
      );
      final back = FormulaStep.fromJson(_roundTrip(step.toJson()));
      expect(back, step);
      expect(back, isA<CapabilityStep>());
    });

    test('a SubFormulaStep round-trips to the right union case', () {
      const step = SubFormulaStep(
        stepId: 's',
        formulaId: 'deploy',
        params: {'selector': 'mdns:pi-a'},
        dependsOn: {'x'},
      );
      final back = FormulaStep.fromJson(_roundTrip(step.toJson()));
      expect(back, step);
      expect(back, isA<SubFormulaStep>());
    });

    test('a NodeCursor round-trips (incl. identity + backoff fields)', () {
      final cursor = NodeCursor(
        state: StepState.running,
        pgid: 4242,
        pid: 4243,
        token: 'tok-abc',
        restartCount: 2,
        cooldownUntil: DateTime(2026, 6, 27, 12),
        logOffset: 1024,
      );
      expect(NodeCursor.fromJson(_roundTrip(cursor.toJson())), cursor);
    });
  });
}
