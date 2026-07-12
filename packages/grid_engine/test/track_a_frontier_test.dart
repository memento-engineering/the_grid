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
// The two canonical circuits (M4-P1 §6 + §9), and a registry over them.
// ---------------------------------------------------------------------------

/// agent → verify → land — the degenerate linear circuit whose always-1-wide
/// frontier reproduces P0 (§6).
const code = Circuit(
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
const deploy = Circuit(
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

/// The Burn (§9): two deploy sub-circuits (ordered: peripheral before central),
/// a coordinator gated on an await-all barrier over both, then a report.
const burn = Circuit(
  id: 'burn',
  terminalStepId: 'report',
  supervision: SupervisionStrategy.restForOne,
  peak: ResourceRequest(builds: 2, processes: 3),
  steps: [
    SubCircuitStep(stepId: 'harnessPeripheral', circuitId: 'deploy'),
    SubCircuitStep(
      stepId: 'harnessCentral',
      circuitId: 'deploy',
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
Circuit? _byId(String id) => _registry[id];

final _now = DateTime(2026);

/// The eligible step ids of [circuit] under [cursor] at [nodePath], in order.
List<String> _frontier(
  Circuit circuit,
  CircuitCursor cursor,
  String nodePath,
) =>
    eligibleSteps(circuit, cursor, nodePath, circuitById: _byId, now: _now)
        .map((s) => s.stepId)
        .toList();

/// The eligible step ids of [circuit] under [cursor] at [nodePath] AT [now] —
/// the cooldown-sensitive variant (the supervised-restart gate is a clock gate).
List<String> _frontierAt(
  Circuit circuit,
  CircuitCursor cursor,
  String nodePath,
  DateTime now,
) =>
    eligibleSteps(circuit, cursor, nodePath, circuitById: _byId, now: now)
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

    test('all complete → empty frontier, and the circuit is complete', () {
      final cursor = {
        'tg-1/agent': _c(StepState.complete),
        'tg-1/verify': _c(StepState.complete),
        'tg-1/land': _c(StepState.complete),
      };
      expect(_frontier(code, cursor, 'tg-1'), isEmpty);
      expect(
        isCircuitComplete(code, cursor, 'tg-1', circuitById: _byId),
        isTrue,
      );
      expect(isCircuitBroken(code, cursor, 'tg-1'), isFalse);
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
        // The sub-circuit step itself stays mounted (daemons live under it).
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
    test(
      'a REAPED zombie (tg-szb) re-enters the frontier once its cooldown lapses '
      '— the bounce RE-RUNS the step instead of stalling on a corpse',
      () {
        final t = DateTime(2026, 7, 12, 12);
        // What RestartReconciler._reapZombieRunners writes for a dead-pid
        // `running` node: the missed supervised failure (state=failed,
        // restartCount+1, a backoff cooldown).
        final reaped = {
          'tg-1/agent': _c(
            StepState.failed,
            restartCount: 1,
            cooldownUntil: t.add(const Duration(seconds: 1)),
          ),
        };

        // Still cooling down: withheld, but a restart is SCHEDULED — never lost.
        expect(_frontierAt(code, reaped, 'tg-1', t), isEmpty);

        // Past the cooldown and within `maxRestarts` (3): it MOUNTS again. The
        // bumped restartCount re-keys it in CircuitScope, so this is a FRESH
        // incarnation with a fresh token — not a reattach to the corpse.
        expect(
          _frontierAt(code, reaped, 'tg-1', t.add(const Duration(seconds: 2))),
          ['agent'],
        );

        // And the dependents stay withheld until it genuinely completes — the
        // reap restores forward progress, it never fakes it.
        expect(
          _frontierAt(code, reaped, 'tg-1', t.add(const Duration(seconds: 2))),
          isNot(contains('verify')),
        );
      },
    );

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
      expect(isStepBroken(deploy, deploy.steps.first, cursor, 'd'), isTrue);
      expect(isCircuitBroken(deploy, cursor, 'd'), isTrue);
      expect(
        isCircuitComplete(deploy, cursor, 'd', circuitById: _byId),
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
      expect(isStepBroken(deploy, deploy.steps.first, cursor, 'd'), isTrue);
      expect(isCircuitBroken(deploy, cursor, 'd'), isTrue);
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

  group('Track A — isCircuitBrokenDeep descends into sub-circuits (D-5)', () {
    test('a nested deploy step exhausting its breaker is broken-deep, but the '
        'shallow check at the burn level misses it', () {
      final cursor = {
        // The peripheral deploy's build failed AND exhausted (>= maxRestarts 3).
        'b/harnessPeripheral/build': _c(StepState.failed, restartCount: 3),
      };
      expect(isCircuitBrokenDeep(burn, cursor, 'b', circuitById: _byId), isTrue);
      // The shallow check (burn's OWN steps) sees no broken step — they are
      // sub-circuits + withheld leaves.
      expect(isCircuitBroken(burn, cursor, 'b'), isFalse);
    });

    test('a healthy burn is not broken-deep', () {
      expect(
        isCircuitBrokenDeep(burn, const {}, 'b', circuitById: _byId),
        isFalse,
      );
    });
  });

  group('Track A — isCircuitComplete descends into a sub-circuit terminal', () {
    // The regression guard for the asymmetry the adversarial review found: a
    // SubCircuitStep has no host, so its OWN cursor node is never written.
    // isCircuitComplete must resolve a sub-circuit terminal to its terminal-step
    // DESCENDANT, or the session would never close (the indefinite mount D-5
    // forbids).
    const outer = Circuit(
      id: 'outer',
      terminalStepId: 'wrap', // a sub-circuit as the terminal step
      steps: [SubCircuitStep(stepId: 'wrap', circuitId: 'deploy')],
    );

    test('not complete while the sub-circuit terminal descendant is pending',
        () {
      expect(
        isCircuitComplete(outer, const {}, 'n', circuitById: _byId),
        isFalse,
      );
    });

    test('complete once the descendant terminal (waitWS) is a positive terminal',
        () {
      final cursor = {
        'n/wrap/waitWS': _c(StepState.complete),
      };
      expect(
        isCircuitComplete(outer, cursor, 'n', circuitById: _byId),
        isTrue,
      );
    });
  });

  group('Track A — fail-closed dep resolution', () {
    test('a dangling dep id is never satisfiable', () {
      const f = Circuit(
        id: 'x',
        terminalStepId: 'a',
        steps: [
          CapabilityStep(stepId: 'a', capabilityId: 'a', dependsOn: {'ghost'}),
        ],
      );
      expect(_frontier(f, const {}, 'n'), isEmpty);
    });

    test('a sub-circuit dep with an unknown circuitId is never satisfiable', () {
      const f = Circuit(
        id: 'x',
        terminalStepId: 'b',
        steps: [
          SubCircuitStep(stepId: 's', circuitId: 'missing'),
          CapabilityStep(stepId: 'b', capabilityId: 'b', dependsOn: {'s'}),
        ],
      );
      // The sub-circuit step itself is eligible (pending), but 'b' is withheld
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
    test('a multi-step fan-out Circuit round-trips identically', () {
      expect(Circuit.fromJson(_roundTrip(burn.toJson())), burn);
    });

    test('the linear code Circuit round-trips identically', () {
      expect(Circuit.fromJson(_roundTrip(code.toJson())), code);
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
      final back = CircuitStep.fromJson(_roundTrip(step.toJson()));
      expect(back, step);
      expect(back, isA<CapabilityStep>());
    });

    test('a CapabilityStep with a declared requires round-trips (the D-B5 '
        'claim contract)', () {
      const step = CapabilityStep(
        stepId: 'follower',
        capabilityId: 'burn-follower',
        requires: CapabilityFacts(
          sets: {
            kSystemOs: {'linux'},
            kRadio: {'ble'},
          },
        ),
      );
      final back = CircuitStep.fromJson(_roundTrip(step.toJson()));
      expect(back, step);
      expect(back, isA<CapabilityStep>());
      expect((back as CapabilityStep).requires, step.requires);
    });

    test('a CapabilityStep with NO declared requires round-trips requires as '
        'null (never an empty map)', () {
      const step = CapabilityStep(stepId: 'agent', capabilityId: 'agent');
      final json = step.toJson();
      expect(json['requires'], isNull);
      final back = CircuitStep.fromJson(_roundTrip(json));
      expect((back as CapabilityStep).requires, isNull);
    });

    test('a SubCircuitStep round-trips to the right union case', () {
      const step = SubCircuitStep(
        stepId: 's',
        circuitId: 'deploy',
        params: {'selector': 'mdns:pi-a'},
        dependsOn: {'x'},
      );
      final back = CircuitStep.fromJson(_roundTrip(step.toJson()));
      expect(back, step);
      expect(back, isA<SubCircuitStep>());
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
