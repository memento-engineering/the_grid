// Track A3 — the gate primitive (D-7).
//
// A gate functionally blocks parked work via a real `type=gate` bead the_grid
// mints in its OWN store (tgdog) — NEVER a mutation of the foreign work bead
// (A37). An open gate parks the subtree; resolving the gate bead re-arms the
// node. Covers the host write+mint, the frontier park, the join projection, and
// the SessionScope re-arm. Zero I/O: fakes + the recording chokepoint.
import 'dart:async';

import 'package:genesis_tree/genesis_tree.dart';
import 'package:grid_controller/grid_controller.dart';
import 'package:grid_engine/grid_engine.dart';
import 'package:test/test.dart';

import 'support/engine_fakes.dart';

/// A ServiceCapability that returns the configured [outcome] (a `Gate` or `Ok`).
class _RouteCap extends ServiceCapability {
  const _RouteCap(this.outcome);
  final StepOutcome outcome;

  @override
  Future<StepOutcome> run(TreeContext context, StepArgs args) async => outcome;
}

const _gateFormula = Formula(
  id: 'f',
  terminalStepId: 'land',
  steps: [
    CapabilityStep(stepId: 'route', capabilityId: 'route'),
    CapabilityStep(stepId: 'land', capabilityId: 'land', dependsOn: {'route'}),
  ],
);

Future<void> _pump() async {
  for (var i = 0; i < 5; i++) {
    await Future<void>.delayed(Duration.zero);
  }
}

GraphSnapshot _graph(List<Bead> beads) => GraphSnapshot.fromParts(
  beads: beads,
  dependencies: const [],
  readyIds: {for (final b in beads) b.id},
  capturedAt: DateTime(2026),
);

Bead _gate({
  required String id,
  required String blocks,
  required String node,
  bool closed = false,
}) => Bead(
  id: id,
  issueType: IssueType.gate,
  status: closed ? BeadStatus.closed : BeadStatus.open,
  metadata: {'rig': stateSubstation, 'blocks': blocks, 'node': node},
);

void main() {
  group('Track A3 — host: a ServiceCapability Gate writes gated + mints a gate', () {
    test('writes state=gated AND mints a type=gate bead via the chokepoint, and '
        'does NOT write complete', () async {
      final fakes = buildFakes();
      final owner = TreeOwner();
      addTearDown(() {
        owner.dispose();
        unawaited(fakes.provider.close());
      });
      owner.mountRoot(
        InheritedSeed<StationServices>(
          value: fakes.ctx,
          child: InheritedSeed<CapabilityRegistry>(
            value: RecordingCapabilityRegistry(clock: DateTime(2026)),
            child: InheritedSeed<ServiceBundle>(
              value: const ServiceBundle(),
              child: CapabilityHost(
                capability: const _RouteCap(Gate('x')),
                mount: const StepMount(
                  step: CapabilityStep(stepId: 'route', capabilityId: 'route'),
                  nodePath: 'tg-1/route',
                  session: SessionHandle('tgdog-s'),
                  node: NodeCursor(),
                  key: ValueKey('tg-1/route#0'),
                ),
              ),
            ),
          ),
        ),
      );
      await _pump();

      // 1) the parked cursor write (onto the OWN session, never the work bead).
      // A gate is a terminal transition too → it carries capture-only timing.
      final updates = fakes.runner.callsFor('update');
      expect(fakes.runner.metadataOfUpdate(0), {
        'grid.cursor.tg-1/route.state': 'gated',
        ...expectedTiming('tg-1/route'),
      });

      // 2) a real type=gate bead was minted (create -t gate) + stamped.
      final creates = fakes.runner.callsFor('create');
      expect(creates, hasLength(1));
      expect(creates.single, containsAllInOrder(['--type', 'gate']));
      // The stamp carries the block linkage the join re-arms off.
      final stamp = fakes.runner.metadataOfUpdate(updates.length - 1);
      expect(stamp['blocks'], 'tgdog-s');
      expect(stamp['node'], 'tg-1/route');
      expect(stamp['reason'], 'x');
      expect(stamp['rig'], stateSubstation);

      // No `complete` was ever written (the park is not a positive terminal).
      for (final u in updates) {
        final i = u.indexOf('--metadata');
        expect(i < 0 || !u[i + 1].contains('"complete"'), isTrue);
      }
    });
  });

  group('Track A3 — frontier: a gated node parks itself AND its dependent', () {
    test('a gated route excludes route AND land; positive control: route '
        'complete lets land enter', () {
      final gated = eligibleSteps(
        _gateFormula,
        const {'b/route': NodeCursor(state: StepState.gated)},
        'b',
        formulaById: (_) => null,
        now: DateTime(2026),
      );
      expect(gated, isEmpty, reason: 'route parked + land withheld');

      // Positive control: the SAME tree with route COMPLETE — land enters, so
      // the empty frontier above was the gate, not a structural bug.
      final advanced = eligibleSteps(
        _gateFormula,
        const {'b/route': NodeCursor(state: StepState.complete)},
        'b',
        formulaById: (_) => null,
        now: DateTime(2026),
      );
      expect(advanced.map((s) => s.stepId), ['land']);
    });
  });

  group('Track A3 — join: an OPEN gate bead surfaces in openGateNodes', () {
    test('an open type=gate blocks=<session> adds its node; closing it empties '
        'the set', () {
      final work = FakeSnapshotSource(_graph([bead('tg-1')]));
      final sessionRow = sessionBead(id: 'tgdog-s', workBeadId: 'tg-1');

      // OPEN gate → the node is parked.
      final openState = FakeSnapshotSource(_graph([
        sessionRow,
        _gate(id: 'tgdog-g1', blocks: 'tgdog-s', node: 'tg-1/route'),
      ]));
      final openBridge = StationJoinBridge(work: work, state: openState);
      addTearDown(openBridge.dispose);
      expect(
        openBridge.latest.sessionsByWorkBead['tg-1']!.openGateNodes,
        {'tg-1/route'},
      );

      // CLOSED gate (resolved) → no open gate node (the re-arm signal).
      final closedState = FakeSnapshotSource(_graph([
        sessionRow,
        _gate(id: 'tgdog-g1', blocks: 'tgdog-s', node: 'tg-1/route', closed: true),
      ]));
      final closedBridge = StationJoinBridge(work: work, state: closedState);
      addTearDown(closedBridge.dispose);
      expect(
        closedBridge.latest.sessionsByWorkBead['tg-1']!.openGateNodes,
        isEmpty,
      );

      // Positive control: a gate blocking an UNKNOWN session is ignored.
      final strayState = FakeSnapshotSource(_graph([
        sessionRow,
        _gate(id: 'tgdog-g2', blocks: 'tgdog-other', node: 'tg-1/route'),
      ]));
      final strayBridge = StationJoinBridge(work: work, state: strayState);
      addTearDown(strayBridge.dispose);
      expect(
        strayBridge.latest.sessionsByWorkBead['tg-1']!.openGateNodes,
        isEmpty,
      );
    });
  });

  group('Track A3 — re-arm: a resolved gate flips the parked node to pending', () {
    test('a gated cursor node NOT in openGateNodes schedules a pending re-arm; '
        'a still-open gate schedules nothing', () async {
      // CLOSED gate (node absent from openGateNodes) → re-arm fires.
      final closed = buildFakes();
      final closedOwner = TreeOwner();
      addTearDown(() {
        closedOwner.dispose();
        unawaited(closed.provider.close());
      });
      closedOwner.mountRoot(
        InheritedSeed<StationServices>(
          value: closed.ctx,
          child: InheritedSeed<CapabilityRegistry>(
            value: RecordingCapabilityRegistry(clock: DateTime(2026)),
            child: const SessionScope(
              bead: _bead,
              formula: _gateFormula,
              existingSession: SessionProjection(
                workBeadId: 'tg-1',
                sessionId: 'tgdog-s',
                cursor: {'tg-1/route': NodeCursor(state: StepState.gated)},
              ),
            ),
          ),
        ),
      );
      await _pump();
      final rearm = closed.runner.callsFor('update');
      expect(rearm, hasLength(1));
      expect(closed.runner.metadataOfUpdate(0),
          {'grid.cursor.tg-1/route.state': 'pending'});

      // STILL-OPEN gate (node present in openGateNodes) → NO re-arm.
      final open = buildFakes();
      final openOwner = TreeOwner();
      addTearDown(() {
        openOwner.dispose();
        unawaited(open.provider.close());
      });
      openOwner.mountRoot(
        InheritedSeed<StationServices>(
          value: open.ctx,
          child: InheritedSeed<CapabilityRegistry>(
            value: RecordingCapabilityRegistry(clock: DateTime(2026)),
            child: const SessionScope(
              bead: _bead,
              formula: _gateFormula,
              existingSession: SessionProjection(
                workBeadId: 'tg-1',
                sessionId: 'tgdog-s',
                cursor: {'tg-1/route': NodeCursor(state: StepState.gated)},
                openGateNodes: {'tg-1/route'},
              ),
            ),
          ),
        ),
      );
      await _pump();
      expect(open.runner.callsFor('update'), isEmpty,
          reason: 'a still-open gate must not re-arm');
    });
  });
}

const _bead = Bead(id: 'tg-1', issueType: IssueType.task, status: BeadStatus.open);
