// StationKernel — the D-B5 hook #1 wiring: `onUnclaimedFrontier` fires once
// per reconciliation phase (the baseline scan at `start()`, then once per
// flush) with the CURRENT station-wide unclaimed requirement set, computed
// off the SAME bridge.latest the kernel already holds (no extra
// subscription). Mirrors track_g_supervision_test.dart's G3 kernel-cooldown
// test harness. Zero I/O — fakes + injected clock.
import 'dart:async';

import 'package:beads_dart/beads_dart.dart';
import 'package:genesis_tree/genesis_tree.dart';
import 'package:grid_engine/grid_engine.dart';
import 'package:grid_engine/testing.dart';
import 'package:test/test.dart';

const _macos = CapabilityFacts(
  sets: {
    kSystemOs: {'macos'},
    kRadio: {'ble'},
  },
);

const _linuxRequirement = CapabilityFacts(
  sets: {
    kSystemOs: {'linux'},
    kRadio: {'ble'},
  },
);

const _burn = Circuit(
  id: 'burn',
  terminalStepId: 'coordinator',
  steps: [
    CapabilityStep(stepId: 'host', capabilityId: 'burn-host', requires: _macos),
    CapabilityStep(
      stepId: 'follower',
      capabilityId: 'burn-follower',
      requires: _linuxRequirement,
    ),
    CapabilityStep(
      stepId: 'coordinator',
      capabilityId: 'coord',
      dependsOn: {'host', 'follower'},
    ),
  ],
);

const _tgConfig = SubstationConfig(substationId: 'tg', ownedSubstations: {'tg'});

/// The G3 harness's Idle resolver — this suite exercises the unclaimed-
/// frontier scan, not the mounted tree, so no real effect ever needs to spawn.
class _IdleResolver implements SessionResolver {
  const _IdleResolver();
  @override
  Seed sessionFor({required Bead bead, SessionProjection? session}) =>
      const Idle();
}

Future<void> _pump() async {
  for (var i = 0; i < 5; i++) {
    await Future<void>.delayed(Duration.zero);
  }
}

GraphSnapshot _emptyGraph() => GraphSnapshot.fromParts(
  beads: const [],
  dependencies: const [],
  readyIds: const [],
  capturedAt: DateTime(2026),
);

void main() {
  test('the baseline scan at start() reports EMPTY (no work yet); pushing a '
      'live session surfaces its unclaimed requirement on the NEXT flush',
      () async {
    final work = FakeSnapshotSource(_emptyGraph());
    final state = FakeSnapshotSource(_emptyGraph());
    addTearDown(work.close);
    addTearDown(state.close);
    final bridge = StationJoinBridge(work: work, state: state);
    final f = buildFakes();
    final registry = RecordingCapabilityRegistry(clock: DateTime(2026));

    final captured = <List<UnclaimedRequirement>>[];
    final kernel = StationKernel(
      bridge: bridge,
      stationServices: f.ctx,
      resolver: const _IdleResolver(),
      substations: [
        SubstationScope(
          configNotifier: SubstationConfigNotifier(_tgConfig),
          key: const ValueKey('scope.tg'),
        ),
      ],
      registry: registry,
      rootCircuitFor: (_) => _burn,
      stationFacts: _macos,
      onUnclaimedFrontier: captured.add,
    );
    addTearDown(kernel.dispose);
    kernel.start();

    // The baseline scan (no work pushed yet) reports nothing unclaimed.
    expect(captured, hasLength(1));
    expect(captured.single, isEmpty);

    // A work bead + its (fresh, cursor-empty) owned session land together.
    work.push(GraphSnapshot.fromParts(
      beads: [Bead(id: 'tg-burn', issueType: IssueType.task, status: BeadStatus.open)],
      dependencies: const [],
      readyIds: const {'tg-burn'},
      capturedAt: DateTime(2026),
    ));
    await _pump();
    state.push(GraphSnapshot.fromParts(
      beads: [
        Bead(
          id: 'tgdog-s1',
          issueType: IssueType.session,
          status: BeadStatus.open,
          metadata: const {'rig': 'tgdog', 'work_bead': 'tg-burn'},
        ),
      ],
      dependencies: const [],
      readyIds: const {},
      capturedAt: DateTime(2026),
    ));
    await _pump();

    // The LAST scan (after the flush the state push triggered) sees the
    // linux-requiring follower as unclaimed; the macOS-requiring host is not.
    final last = captured.last;
    expect(last, hasLength(1));
    expect(last.single.sessionId, 'tgdog-s1');
    expect(last.single.workBeadId, 'tg-burn');
    expect(last.single.step.stepId, 'follower');
  });

  test('no rootCircuitFor / no onUnclaimedFrontier wired → the scan is a '
      'true no-op (no crash, nothing computed) — the zero-cost default for a '
      'station composing no federation asset', () async {
    final work = FakeSnapshotSource(_emptyGraph());
    final state = FakeSnapshotSource(_emptyGraph());
    addTearDown(work.close);
    addTearDown(state.close);
    final bridge = StationJoinBridge(work: work, state: state);
    final f = buildFakes();

    final kernel = StationKernel(
      bridge: bridge,
      stationServices: f.ctx,
      resolver: const _IdleResolver(),
      substations: [
        SubstationScope(
          configNotifier: SubstationConfigNotifier(_tgConfig),
          key: const ValueKey('scope.tg'),
        ),
      ],
      registry: RecordingCapabilityRegistry(clock: DateTime(2026)),
      // rootCircuitFor + onUnclaimedFrontier both omitted (default null).
    );
    addTearDown(kernel.dispose);
    expect(kernel.start, returnsNormally);
    await _pump();
  });
}
