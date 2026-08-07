// tg-60n residual 2 — the wedge alarm samples LAST and ALWAYS.
//
// Live receipt (2026-08-06, lunar arm pid 64281): /status reported the const
// kNotWedged baseline ({wedged:false, reason:"no live session", live:0})
// BESIDE liveSessions:6 — `StationDriver.afterFlush` ran its cooldown and
// unclaimed-frontier scans BEFORE `_wedge.poll()`, so a throwing scan skipped
// the poll and silenced the stall detector forever. Same fail-open shape as
// the #154 flush seam, one level down.
//
// Zero I/O: FakeSnapshotSource + a real StationJoinBridge.
import 'package:beads_dart/beads_dart.dart';
import 'package:grid_engine/grid_engine.dart';
import 'package:grid_engine/testing.dart';
import 'package:test/test.dart';

GraphSnapshot _graph(List<Bead> beads) => GraphSnapshot.fromParts(
  beads: beads,
  dependencies: const [],
  readyIds: {for (final b in beads) b.id},
  capturedAt: DateTime(2026),
);

Bead _stepBead(String id, {required String sessionId, required String path}) =>
    Bead(
      id: id,
      issueType: GridIssueTypes.step,
      status: BeadStatus.open,
      metadata: {
        'rig': stateSubstation,
        MoleculeStepKeys.stepId: path.split('/').last,
        MoleculeStepKeys.capability: 'agent',
        MoleculeStepKeys.kind: StepKind.job.name,
        MoleculeStepKeys.path: path,
        MoleculeStepKeys.state: StepState.running.name,
        MoleculeStepKeys.session: sessionId,
      },
    );

void main() {
  test(
    'afterFlush polls the wedge alarm even when a scan THROWS — a broken '
    'cooldown/frontier scan can never silence the stall detector (tg-60n)',
    () {
      final work = FakeSnapshotSource(_graph([bead('tg-1')]));
      final state = FakeSnapshotSource(
        _graph([
          sessionBead(
            id: 'tgdog-s1',
            workBeadId: 'tg-1',
            metadata: {SessionBeadKeys.model: kSessionModelMolecule},
          ),
          _stepBead('tgdog-step1', sessionId: 'tgdog-s1', path: 'tg-1/agent'),
        ]),
      );
      final bridge = StationJoinBridge(work: work, state: state);
      addTearDown(bridge.dispose);

      final driver = StationDriver(
        bridge: bridge,
        // The frontier scan's all-or-nothing trio, wired so the scan RUNS —
        // and its sink THROWS, the exact shape that silenced the live arm.
        rootCircuitFor: (_) => const Circuit(
          id: 'code',
          terminalStepId: 'land',
          steps: [CapabilityStep(stepId: 'land', capabilityId: 'land')],
        ),
        registry: RecordingCapabilityRegistry(circuits: const {}),
        onUnclaimedFrontier: (_) =>
            throw StateError('frontier consumer broke'),
      );
      addTearDown(driver.dispose);

      expect(
        driver.wedge,
        same(kNotWedged),
        reason: 'sanity: before any flush the state is the const baseline',
      );

      // The scan throw still propagates (LOUD, unchanged) …
      expect(driver.afterFlush, throwsStateError);

      // … but the alarm sampled anyway: the state left the const baseline
      // and reflects the REAL join (one live session, running — flowing).
      final state0 = driver.wedge;
      expect(state0, isNot(same(kNotWedged)));
      expect(state0.sample.live, 1, reason: 'the sample saw the live session');
      expect(state0.isWedged, isFalse, reason: 'a running step is progress');
    },
  );
}
