// Track J — the Burn (§9): the hardest case end-to-end, offline. A multi-step
// formula with sub-formula harnesses (fan-out + ordering), an await-all barrier
// gating a coordinator, a long-lived daemon, and guaranteed teardown — plus the
// failure path (a half-up rig → escalate + tear down, no leaked daemon).
//
// Driven over the FULL new path (FormulaResolver → SessionScope → FormulaScope →
// nested FormulaScope → CapabilityHosts), with the cursor advanced via the join
// (simulating the bridge re-projecting each chokepoint write). ADR-0008 D4 /
// M4-P1 §9, Track J. Zero I/O.
import 'package:genesis_tree/genesis_tree.dart';
import 'package:grid_controller/grid_controller.dart';
import 'package:grid_engine/grid_engine.dart';
import 'package:test/test.dart';

import 'support/engine_fakes.dart';

// --- the Burn formulas (§9) --------------------------------------------------

const _deploy = Formula(
  id: 'deploy',
  terminalStepId: 'waitWS',
  steps: [
    CapabilityStep(stepId: 'build', capabilityId: 'build'),
    CapabilityStep(stepId: 'install', capabilityId: 'install', dependsOn: {'build'}),
    CapabilityStep(
      stepId: 'launch',
      capabilityId: 'launch',
      kind: StepKind.daemon,
      dependsOn: {'install'},
    ),
    CapabilityStep(stepId: 'waitWS', capabilityId: 'waitWS', dependsOn: {'launch'}),
  ],
);

const _burn = Formula(
  id: 'burn',
  terminalStepId: 'report',
  supervision: SupervisionStrategy.restForOne,
  peak: ResourceRequest(builds: 2, processes: 3),
  steps: [
    SubFormulaStep(stepId: 'harnessPeripheral', formulaId: 'deploy'),
    SubFormulaStep(
      stepId: 'harnessCentral',
      formulaId: 'deploy',
      dependsOn: {'harnessPeripheral'},
    ),
    CapabilityStep(
      stepId: 'coordinator',
      capabilityId: 'coordinator',
      dependsOn: {'harnessPeripheral', 'harnessCentral'},
    ),
    CapabilityStep(stepId: 'report', capabilityId: 'report', dependsOn: {'coordinator'}),
  ],
);

const _tgConfig = SubstationConfig(substationId: 'tg', ownedSubstations: {'tg'});

NodeCursor _done() => const NodeCursor(state: StepState.complete);
NodeCursor _ready() => const NodeCursor(state: StepState.ready);

// --- the full-path harness ---------------------------------------------------

class _Burn {
  _Burn(this.beadId)
    : fakes = buildFakes(),
      reg = RecordingCapabilityRegistry(formulas: const {'deploy': _deploy}),
      joined = JoinedSnapshotNotifier(JoinedSnapshot.empty()),
      owner = TreeOwner();

  final String beadId;
  final Fakes fakes;
  final RecordingCapabilityRegistry reg;
  final JoinedSnapshotNotifier joined;
  final TreeOwner owner;
  late Branch root;

  // The cursor accumulates MONOTONICALLY (a real cursor only advances) — so an
  // advance passes only the DELTA and a daemon's deps never spuriously regress.
  final Map<String, NodeCursor> _cursor = {};

  List<String> get events => reg.events;

  void mount({Map<String, NodeCursor> cursor = const {}, bool terminal = false}) {
    _cursor.addAll(cursor);
    _push(cursor: _cursor, terminal: terminal);
    root = owner.mountRoot(
      InheritedSeed<JoinedSnapshotNotifier>(
        value: joined,
        child: InheritedSeed<EffectContext>(
          value: fakes.ctx,
          child: StableInheritedSeed<CapabilityRegistry>(
            value: reg,
            child: InheritedSeed<ServiceBundle>(
              value: const ServiceBundle(),
              child: InheritedSeed<EffectResolver>(
                value: FormulaResolver((_) => _burn),
                child: Station([
                  SubstationScope(
                    configNotifier: SubstationConfigNotifier(_tgConfig),
                    key: const ValueKey('scope.tg'),
                  ),
                ]),
              ),
            ),
          ),
        ),
      ),
    );
  }

  void advance(Map<String, NodeCursor> delta, {bool terminal = false}) {
    events.clear();
    _cursor.addAll(delta);
    _push(cursor: _cursor, terminal: terminal);
    owner.flush();
  }

  void _push({required Map<String, NodeCursor> cursor, required bool terminal}) {
    joined.push(
      JoinedSnapshot(
        graph: GraphSnapshot.fromParts(
          beads: [Bead(id: beadId, issueType: IssueType.task, status: BeadStatus.open)],
          dependencies: const [],
          readyIds: {beadId},
          capturedAt: DateTime(2026),
        ),
        sessionsByWorkBead: {
          beadId: SessionProjection(
            workBeadId: beadId,
            sessionId: 'tgdog-s',
            phase: WorkPhase.implement,
            isTerminal: terminal,
            cursor: cursor,
          ),
        },
      ),
    );
  }

  bool get closed =>
      fakes.runner.callsFor('close').any((c) => c.length > 1 && c[1] == 'tgdog-s');
  bool get escalated => fakes.runner
      .callsFor('update')
      .any((c) => c.join(' ').contains('grid.escalation'));

  void dispose() => owner.dispose();
}

String _b(String step) => 'tg-burn/$step'; // burn root nodePath = the bead id

/// Drains the scheduled microtasks (SessionScope's close/escalate run off build).
Future<void> _drain() async {
  for (var i = 0; i < 5; i++) {
    await Future<void>.delayed(Duration.zero);
  }
}

void main() {
  group('Track J — the Burn happy path (fan-out + barrier + daemon + close)', () {
    test('t0: mount → only the peripheral deploy build spawns (central + '
        'coordinator withheld)', () {
      final burn = _Burn('tg-burn')..mount();
      addTearDown(burn.dispose);
      // The peripheral sub-formula inflates {build}; the ordering barrier holds
      // central; the await-all barrier holds the coordinator.
      expect(burn.events, ['START build(tgdog-s/tg-burn/harnessPeripheral/build)']);
    });

    test('the full trace drives to the terminal report and SessionScope closes',
        () async {
      final burn = _Burn('tg-burn')..mount();
      addTearDown(burn.dispose);

      // t1: peripheral build → install → launch(daemon, ready) → waitWS done.
      burn.advance({
        '${_b('harnessPeripheral')}/build': _done(),
        '${_b('harnessPeripheral')}/install': _done(),
        '${_b('harnessPeripheral')}/launch': _ready(),
        '${_b('harnessPeripheral')}/waitWS': _done(),
      });
      // Central's deploy now enters (its build spawns); the peripheral launch
      // daemon STAYS mounted (never STOPped); coordinator still withheld.
      expect(
        burn.events.any((e) => e.contains('START build(tgdog-s/tg-burn/harnessCentral/build)')),
        isTrue,
      );
      expect(
        burn.events.any((e) => e.contains('STOP launch(tgdog-s/tg-burn/harnessPeripheral/launch)')),
        isFalse,
        reason: 'the peripheral daemon stays up across the barrier',
      );

      // t2: central fully done → BOTH harness terminals → coordinator enters.
      burn.advance({
        '${_b('harnessPeripheral')}/waitWS': _done(),
        '${_b('harnessPeripheral')}/launch': _ready(),
        '${_b('harnessCentral')}/waitWS': _done(),
        '${_b('harnessCentral')}/launch': _ready(),
      });
      expect(
        burn.events.any((e) => e.contains('START coordinator(tgdog-s/tg-burn/coordinator)')),
        isTrue,
        reason: 'the await-all barrier opened (both harnesses terminal)',
      );

      // t3: coordinator done → report enters.
      burn.advance({
        '${_b('harnessPeripheral')}/waitWS': _done(),
        '${_b('harnessPeripheral')}/launch': _ready(),
        '${_b('harnessCentral')}/waitWS': _done(),
        '${_b('harnessCentral')}/launch': _ready(),
        'tg-burn/coordinator': _done(),
      });
      expect(
        burn.events.any((e) => e.contains('START report(tgdog-s/tg-burn/report)')),
        isTrue,
      );

      // t4: report (the terminal step) done → SessionScope closes the session.
      burn.advance({
        '${_b('harnessPeripheral')}/waitWS': _done(),
        '${_b('harnessPeripheral')}/launch': _ready(),
        '${_b('harnessCentral')}/waitWS': _done(),
        '${_b('harnessCentral')}/launch': _ready(),
        'tg-burn/coordinator': _done(),
        'tg-burn/report': _done(),
      });
      await _drain(); // let SessionScope's scheduled close fire
      expect(burn.closed, isTrue, reason: 'report is the terminalStepId → close');
      expect(burn.escalated, isFalse);
    });
  });

  group('Track J — the Burn failure path (half-up rig → escalate + teardown)',
      () {
    test('a central harness step exhausting its breaker escalates AND tears the '
        'subtree down (the peripheral daemon is killed — no leak)', () async {
      final burn = _Burn('tg-burn')..mount();
      addTearDown(burn.dispose);

      // Bring the peripheral fully up (its launch daemon mounted) + central
      // building.
      burn.advance({
        '${_b('harnessPeripheral')}/build': _done(),
        '${_b('harnessPeripheral')}/install': _done(),
        '${_b('harnessPeripheral')}/launch': _ready(),
        '${_b('harnessPeripheral')}/waitWS': _done(),
      });
      expect(
        burn.events.any((e) => e.contains('START launch(tgdog-s/tg-burn/harnessPeripheral/launch)')),
        isTrue,
      );

      // Central's build FAILS and exhausts (restartCount 3 == maxRestarts) →
      // circuit-broken → broken-deep → SessionScope escalates + closes.
      burn.advance({
        '${_b('harnessPeripheral')}/launch': _ready(),
        '${_b('harnessPeripheral')}/waitWS': _done(),
        '${_b('harnessCentral')}/build':
            const NodeCursor(state: StepState.failed, restartCount: 3),
      });
      await _drain(); // let SessionScope's scheduled escalate+close fire

      expect(burn.escalated, isTrue, reason: 'breaker exhaustion escalates (D-5)');
      expect(burn.closed, isTrue, reason: 'escalation closes the session');

      // Closing the session is terminal → WorkList unmounts the WorkBead → the
      // whole subtree tears down, killing the peripheral daemon (no leak).
      burn.advance(const {}, terminal: true);
      expect(
        burn.events.any((e) => e.contains('STOP launch(tgdog-s/tg-burn/harnessPeripheral/launch)')),
        isTrue,
        reason: 'teardown reaches the leaked daemon (the §9 failure guarantee)',
      );
    });

    test('a half-up rig NEVER mounts the coordinator (positive-terminal-only)',
        () {
      final burn = _Burn('tg-burn')..mount();
      addTearDown(burn.dispose);
      // Peripheral up, central FAILED (not terminal) — the coordinator's
      // await-all barrier must stay closed.
      burn.advance({
        '${_b('harnessPeripheral')}/waitWS': _done(),
        '${_b('harnessPeripheral')}/launch': _ready(),
        '${_b('harnessCentral')}/build':
            const NodeCursor(state: StepState.failed, restartCount: 1),
      });
      expect(
        burn.events.any((e) => e.contains('coordinator')),
        isFalse,
        reason: 'a failed harness never satisfies the barrier',
      );
    });
  });
}
