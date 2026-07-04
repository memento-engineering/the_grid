// stationUnclaimedFrontier — the STATION-WIDE aggregation of the D-A3/D-B5
// unclaimed-requirement hook (`circuit/unclaimed_frontier.dart`) across every
// live session in a JoinedSnapshot. Zero I/O — fakes only (RecordingCapabilityRegistry).
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

Bead _task(String id) =>
    Bead(id: id, issueType: IssueType.task, status: BeadStatus.open);

GraphSnapshot _graph(List<Bead> beads) => GraphSnapshot.fromParts(
  beads: beads,
  dependencies: const [],
  readyIds: {for (final b in beads) b.id},
  capturedAt: DateTime(2026),
);

void main() {
  group('stationUnclaimedFrontier', () {
    test('aggregates the unclaimed step across ONE live session', () {
      final registry = RecordingCapabilityRegistry(clock: DateTime(2026));
      final snapshot = JoinedSnapshot(
        graph: _graph([_task('tg-burn')]),
        sessionsByWorkBead: const {
          'tg-burn': SessionProjection(
            workBeadId: 'tg-burn',
            sessionId: 'tgdog-s1',
          ),
        },
      );
      final unclaimed = stationUnclaimedFrontier(
        snapshot,
        rootCircuitFor: (_) => _burn,
        registry: registry,
        stationFacts: _macos,
      );
      expect(unclaimed, hasLength(1));
      final only = unclaimed.single;
      expect(only.sessionId, 'tgdog-s1');
      expect(only.workBeadId, 'tg-burn');
      expect(only.step.stepId, 'follower');
      expect(only.step.nodePath, 'tg-burn/follower');
    });

    test('a TERMINAL session contributes nothing', () {
      final registry = RecordingCapabilityRegistry(clock: DateTime(2026));
      final snapshot = JoinedSnapshot(
        graph: _graph([_task('tg-burn')]),
        sessionsByWorkBead: const {
          'tg-burn': SessionProjection(
            workBeadId: 'tg-burn',
            sessionId: 'tgdog-s1',
            isTerminal: true,
          ),
        },
      );
      final unclaimed = stationUnclaimedFrontier(
        snapshot,
        rootCircuitFor: (_) => _burn,
        registry: registry,
        stationFacts: _macos,
      );
      expect(unclaimed, isEmpty);
    });

    test('a session whose work bead is momentarily absent from the joined '
        'graph contributes nothing (fail-closed, never throws)', () {
      final registry = RecordingCapabilityRegistry(clock: DateTime(2026));
      final snapshot = JoinedSnapshot(
        graph: _graph(const []), // the bead is gone from this snapshot
        sessionsByWorkBead: const {
          'tg-burn': SessionProjection(
            workBeadId: 'tg-burn',
            sessionId: 'tgdog-s1',
          ),
        },
      );
      expect(
        () => stationUnclaimedFrontier(
          snapshot,
          rootCircuitFor: (_) => _burn,
          registry: registry,
          stationFacts: _macos,
        ),
        returnsNormally,
      );
      final unclaimed = stationUnclaimedFrontier(
        snapshot,
        rootCircuitFor: (_) => _burn,
        registry: registry,
        stationFacts: _macos,
      );
      expect(unclaimed, isEmpty);
    });

    test('aggregates across MULTIPLE live sessions, tagging each with its '
        'own session/work-bead ids', () {
      final registry = RecordingCapabilityRegistry(clock: DateTime(2026));
      final snapshot = JoinedSnapshot(
        graph: _graph([_task('tg-1'), _task('tg-2')]),
        sessionsByWorkBead: const {
          'tg-1': SessionProjection(workBeadId: 'tg-1', sessionId: 'tgdog-s1'),
          'tg-2': SessionProjection(workBeadId: 'tg-2', sessionId: 'tgdog-s2'),
        },
      );
      final unclaimed = stationUnclaimedFrontier(
        snapshot,
        rootCircuitFor: (_) => _burn,
        registry: registry,
        stationFacts: _macos,
      );
      expect(unclaimed, hasLength(2));
      expect(
        unclaimed.map((u) => u.sessionId).toSet(),
        {'tgdog-s1', 'tgdog-s2'},
      );
      expect(
        unclaimed.map((u) => u.workBeadId).toSet(),
        {'tg-1', 'tg-2'},
      );
    });

    test('a station profile satisfying EVERY requirement → nothing unclaimed',
        () {
      final registry = RecordingCapabilityRegistry(clock: DateTime(2026));
      final snapshot = JoinedSnapshot(
        graph: _graph([_task('tg-burn')]),
        sessionsByWorkBead: const {
          'tg-burn': SessionProjection(
            workBeadId: 'tg-burn',
            sessionId: 'tgdog-s1',
          ),
        },
      );
      const both = CapabilityFacts(
        sets: {
          kSystemOs: {'macos', 'linux'},
          kRadio: {'ble'},
        },
      );
      final unclaimed = stationUnclaimedFrontier(
        snapshot,
        rootCircuitFor: (_) => _burn,
        registry: registry,
        stationFacts: both,
      );
      expect(unclaimed, isEmpty);
    });
  });
}
