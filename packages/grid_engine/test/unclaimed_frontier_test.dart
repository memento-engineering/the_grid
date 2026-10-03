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

const _projectionBlockerCircuit = Circuit(
  id: 'projection-blockers',
  terminalStepId: 'remote',
  steps: [
    CapabilityStep(stepId: 'declared-blocker', capabilityId: 'declared'),
    CapabilityStep(stepId: 'projected-blocker', capabilityId: 'projected'),
    CapabilityStep(
      stepId: 'remote',
      capabilityId: 'remote',
      dependsOn: {'declared-blocker'},
      requires: _linuxRequirement,
    ),
  ],
);

const _blockerCursor = <String, NodeCursor>{
  'tg-blocked/declared-blocker': NodeCursor(state: StepState.complete),
  'tg-blocked/projected-blocker': NodeCursor(state: StepState.pending),
  'tg-blocked/remote': NodeCursor(state: StepState.pending),
};

ProjectionGraphRead _blockerGraph({required bool authoritative}) =>
    ProjectionGraphRead(
      sessionId: 'tgdog-blocked',
      round: 0,
      steps: const _BlockerSteps([
        _BlockerStep(path: 'tg-blocked/declared-blocker', state: 'complete'),
        _BlockerStep(path: 'tg-blocked/projected-blocker', state: 'pending'),
        _BlockerStep(path: 'tg-blocked/remote', state: 'pending'),
      ]),
      edges: const _BlockerEdges([
        _BlockerEdge(
          from: 'tg-blocked/remote',
          to: 'tg-blocked/projected-blocker',
        ),
      ]),
      processIdentities: const _NoProcesses(),
      isAuthoritative: authoritative,
    );

final class _BlockerStep implements StepCursorView {
  const _BlockerStep({required this.path, required this.state});
  final String path;
  final String state;
  @override
  String get sessionId => 'tgdog-blocked';
  @override
  int get round => 0;
  @override
  String get stepPath => path;
  @override
  int get stepRound => 0;
  @override
  String get stepState => state;
  @override
  int get incarnation => 0;
  @override
  String? get attemptId => null;
  @override
  int? get supersededByStepRound => null;
  @override
  DateTime? get cooldownUntil => null;
  @override
  int? get restartBudget => null;
  @override
  DateTime? get startedAt => null;
  @override
  DateTime? get readyAt => null;
  @override
  DateTime? get completedAt => null;
  @override
  String? get failureClass => null;
  @override
  int get lastSeq => 1;
}

final class _BlockerSteps implements TrajectoryStepSnapshot {
  const _BlockerSteps(this.rows);
  final List<StepCursorView> rows;
  @override
  Iterable<StepCursorView> byP2SessionId(String sessionId) => rows;
  @override
  int get version => 1;
  @override
  TrajectorySnapshotHealth get health => TrajectorySnapshotHealth.live;
  @override
  DateTime? get seededAt => null;
  @override
  DateTime? get firstEpochClaimedAt => null;
}

final class _BlockerEdge implements TrajectoryStepEdgeView {
  const _BlockerEdge({required this.from, required this.to});
  final String from;
  final String to;
  @override
  String get sessionId => 'tgdog-blocked';
  @override
  int get round => 0;
  @override
  String get fromPath => from;
  @override
  String get toPath => to;
  @override
  String get kind => 'blocks';
}

final class _BlockerEdges implements TrajectoryStepEdgeSnapshot {
  const _BlockerEdges(this.rows);
  @override
  final List<TrajectoryStepEdgeView> rows;
  @override
  Iterable<TrajectoryStepEdgeView> bySessionId(String sessionId) => rows;
  @override
  int get version => 1;
  @override
  TrajectorySnapshotHealth get health => TrajectorySnapshotHealth.live;
  @override
  DateTime? get seededAt => null;
}

final class _NoProcesses implements TrajectoryProcessIdentitySnapshot {
  const _NoProcesses();
  @override
  Iterable<ProcessIdentityView> bySessionId(String sessionId) => const [];
  @override
  Iterable<ProcessIdentityView> get rows => const [];
  @override
  int get version => 1;
  @override
  TrajectorySnapshotHealth get health => TrajectorySnapshotHealth.live;
  @override
  DateTime? get seededAt => null;
  @override
  DateTime? get lastTickAt => null;
  @override
  bool get tickStalled => false;
}

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
    test(
      'projection graph blockers use authoritative projected dependencies',
      () {
        final registry = RecordingCapabilityRegistry(clock: DateTime(2026));
        final snapshot = JoinedSnapshot(
          graph: _graph([_task('tg-blocked')]),
          sessionsByWorkBead: {
            'tg-blocked': SessionProjection(
              workBeadId: 'tg-blocked',
              sessionId: 'tgdog-blocked',
              cursor: _blockerCursor,
              trajectoryGraph: _blockerGraph(authoritative: true),
            ),
          },
        );

        final unclaimed = stationUnclaimedFrontier(
          snapshot,
          rootCircuitFor: (_) => _projectionBlockerCircuit,
          registry: registry,
          stationFacts: _macos,
        );

        expect(unclaimed, isEmpty);
      },
    );

    test('projection graph blockers fall back to declared dependencies', () {
      final registry = RecordingCapabilityRegistry(clock: DateTime(2026));
      final snapshot = JoinedSnapshot(
        graph: _graph([_task('tg-blocked')]),
        sessionsByWorkBead: {
          'tg-blocked': SessionProjection(
            workBeadId: 'tg-blocked',
            sessionId: 'tgdog-blocked',
            cursor: _blockerCursor,
            trajectoryGraph: _blockerGraph(authoritative: false),
          ),
        },
      );

      final unclaimed = stationUnclaimedFrontier(
        snapshot,
        rootCircuitFor: (_) => _projectionBlockerCircuit,
        registry: registry,
        stationFacts: _macos,
      );

      expect(unclaimed, hasLength(1));
      expect(unclaimed.single.step.nodePath, 'tg-blocked/remote');
    });

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

    test('cut-held projection graph advertises no unclaimed work', () {
      final registry = RecordingCapabilityRegistry(clock: DateTime(2026));
      final snapshot = JoinedSnapshot(
        graph: _graph([_task('tg-held'), _task('tg-healthy')]),
        sessionsByWorkBead: const {
          'tg-held': SessionProjection(
            workBeadId: 'tg-held',
            sessionId: 'tgdog-held',
            projectionGraphFailurePosture:
                ProjectionGraphFailurePosture.cutHeld,
          ),
          'tg-healthy': SessionProjection(
            workBeadId: 'tg-healthy',
            sessionId: 'tgdog-healthy',
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
      expect(unclaimed.single.sessionId, 'tgdog-healthy');
      expect(unclaimed.single.workBeadId, 'tg-healthy');
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
      expect(unclaimed.map((u) => u.sessionId).toSet(), {
        'tgdog-s1',
        'tgdog-s2',
      });
      expect(unclaimed.map((u) => u.workBeadId).toSet(), {'tg-1', 'tg-2'});
    });

    test(
      'a station profile satisfying EVERY requirement → nothing unclaimed',
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
      },
    );
  });
}
