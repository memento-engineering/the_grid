// StationDriver — the D-B5 hook #1 wiring: `onUnclaimedFrontier` fires once per
// reconciliation phase (the baseline scan at `start()`, then once per
// `afterFlush()` — the rail `runGrid` drives through its `onFlushed` hook) with
// the CURRENT station-wide unclaimed requirement set, computed off the SAME
// `bridge.latest` the driver already holds (no extra subscription). Zero I/O —
// fakes + injected clock.
import 'package:beads_dart/beads_dart.dart';
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
  test(
    'the baseline scan at start() reports EMPTY (no work yet); pushing a '
    'live session surfaces its unclaimed requirement on the NEXT afterFlush',
    () async {
      final work = FakeSnapshotSource(_emptyGraph());
      final state = FakeSnapshotSource(_emptyGraph());
      addTearDown(work.close);
      addTearDown(state.close);
      final bridge = StationJoinBridge(work: work, state: state);
      final registry = RecordingCapabilityRegistry(clock: DateTime(2026));

      final captured = <List<UnclaimedRequirement>>[];
      final driver = StationDriver(
        bridge: bridge,
        registry: registry,
        rootCircuitFor: (_) => _burn,
        stationFacts: _macos,
        onUnclaimedFrontier: captured.add,
      );
      addTearDown(driver.dispose);
      driver.start();

      // The baseline scan (no work pushed yet) reports nothing unclaimed.
      expect(captured, hasLength(1));
      expect(captured.single, isEmpty);

      // A work bead + its (fresh, cursor-empty) owned session land together.
      work.push(
        GraphSnapshot.fromParts(
          beads: [
            Bead(
              id: 'tg-burn',
              issueType: IssueType.task,
              status: BeadStatus.open,
            ),
          ],
          dependencies: const [],
          readyIds: const {'tg-burn'},
          capturedAt: DateTime(2026),
        ),
      );
      await _pump();
      driver.afterFlush();
      state.push(
        GraphSnapshot.fromParts(
          beads: [
            Bead(
              id: 'tgdog-s1',
              issueType: GridIssueTypes.session,
              status: BeadStatus.open,
              metadata: const {'rig': 'tgdog', 'work_bead': 'tg-burn'},
            ),
          ],
          dependencies: const [],
          readyIds: const {},
          capturedAt: DateTime(2026),
        ),
      );
      await _pump();
      driver.afterFlush();

      // The LAST scan sees the linux-requiring follower as unclaimed; the
      // macOS-requiring host is not.
      final last = captured.last;
      expect(last, hasLength(1));
      expect(last.single.sessionId, 'tgdog-s1');
      expect(last.single.workBeadId, 'tg-burn');
      expect(last.single.step.stepId, 'follower');
    },
  );

  test('no rootCircuitFor / no onUnclaimedFrontier wired → the scan is a '
      'true no-op (no crash, nothing computed) — the zero-cost default for a '
      'station composing no federation asset', () async {
    final work = FakeSnapshotSource(_emptyGraph());
    final state = FakeSnapshotSource(_emptyGraph());
    addTearDown(work.close);
    addTearDown(state.close);
    final bridge = StationJoinBridge(work: work, state: state);

    final driver = StationDriver(
      bridge: bridge,
      registry: RecordingCapabilityRegistry(clock: DateTime(2026)),
      // rootCircuitFor + onUnclaimedFrontier both omitted (default null).
    );
    addTearDown(driver.dispose);
    expect(driver.start, returnsNormally);
    await _pump();
    expect(driver.afterFlush, returnsNormally);
  });
}
