import 'package:beads_dart/beads_dart.dart';
import 'package:grid_engine/grid_engine.dart';
import 'package:grid_sdk/src/stores/state_store_pruner.dart';
import 'package:test/test.dart';

void main() {
  final now = DateTime.utc(2026, 9, 14, 12);
  final old = DateTime.utc(2026, 9, 10, 11);
  final cutoff = DateTime.utc(2026, 9, 11, 12);

  test(
    'prunes one strict-cutoff graph and is idempotent on a second run',
    () async {
      final store = _MemoryStateStore(
        state: _snapshot(
          beads: [
            _session('old-session', 'old-work', old),
            _molecule('old-molecule', 'old-session', old),
            _step('old-step', 'old-session', old),
            _session('equal-session', 'equal-work', cutoff),
            _molecule('equal-molecule', 'equal-session', old),
            _step('equal-step', 'equal-session', old),
            _bead('gate', GridIssueTypes.gate, old),
          ],
          dependencies: const [
            BeadDependency(issueId: 'old-step', dependsOnId: 'old-molecule'),
            BeadDependency(issueId: 'old-step', dependsOnId: 'gate'),
            BeadDependency(issueId: 'gate', dependsOnId: 'old-session'),
            BeadDependency(
              issueId: 'equal-step',
              dependsOnId: 'equal-molecule',
            ),
          ],
        ),
        work: _snapshot(
          beads: [
            _bead('old-work', IssueType.task, old),
            _bead('equal-work', IssueType.task, old),
          ],
        ),
      );
      final lines = <String>[];
      final pruner = StateStorePruner(
        age: const Duration(days: 3),
        freshSnapshots: store.freshSnapshots,
        execute: store.execute,
        now: () => now,
        out: lines.add,
      );

      await pruner.run();

      expect(store.snapshotCalls, 1);
      expect(store.executeCalls, 1);
      expect(store.ages, [3]);
      expect(store.protectionSets.single, {
        'equal-molecule',
        'equal-session',
        'equal-step',
        'gate',
      });
      expect(store.state.beadsById.keys, {
        'equal-molecule',
        'equal-session',
        'equal-step',
        'gate',
      });
      expect(store.state.dependencies, hasLength(1));
      expect(
        lines.single,
        'grid: state-store prune complete beads_removed=3 '
        'dependency_rows_removed=3 elapsed_ms=0',
      );

      await pruner.run();

      expect(store.snapshotCalls, 2);
      expect(store.executeCalls, 1, reason: 'an empty plan performs no write');
      expect(
        lines.last,
        'grid: state-store prune complete beads_removed=0 '
        'dependency_rows_removed=0 elapsed_ms=0',
      );
    },
  );

  test('skips unavailable snapshots after exactly one refresh', () async {
    var refreshes = 0;
    var writes = 0;
    final lines = <String>[];
    final pruner = StateStorePruner(
      age: const Duration(days: 3),
      freshSnapshots: () async {
        refreshes++;
        return (state: null, work: _snapshot());
      },
      execute: ({required protectedIds, required olderThanDays}) async {
        writes++;
        return (beadsRemoved: 0, dependencyRowsRemoved: 0);
      },
      now: () => now,
      out: lines.add,
    );

    await pruner.run();

    expect(refreshes, 1);
    expect(writes, 0);
    expect(lines, [
      'grid: state-store prune skipped beads_removed=0 '
          'dependency_rows_removed=0 elapsed_ms=0 '
          'reason=state or work snapshot unavailable',
    ]);
  });

  test(
    'sanitizes snapshot, planning, and writer failures into one line',
    () async {
      Future<void> expectSkipped({
        required Duration age,
        required Future<({GraphSnapshot? state, GraphSnapshot? work})>
        Function()
        snapshots,
        required Future<({int beadsRemoved, int dependencyRowsRemoved})>
        Function({
          required Iterable<String> protectedIds,
          required int olderThanDays,
        })
        execute,
        required String reason,
      }) async {
        final lines = <String>[];
        final pruner = StateStorePruner(
          age: age,
          freshSnapshots: snapshots,
          execute: execute,
          now: () => now,
          out: lines.add,
        );
        await pruner.run();
        expect(lines, [
          'grid: state-store prune skipped beads_removed=0 '
              'dependency_rows_removed=0 elapsed_ms=0 reason=$reason',
        ]);
      }

      await expectSkipped(
        age: const Duration(days: 3),
        snapshots: () async => throw StateError('refresh\r\nfailed'),
        execute: _unreachedExecute,
        reason: 'Bad state: refresh failed',
      );
      await expectSkipped(
        age: Duration.zero,
        snapshots: () async => (state: _snapshot(), work: _snapshot()),
        execute: _unreachedExecute,
        reason:
            'Invalid argument (age): must be positive: Instance of '
            "'Duration'",
      );
      await expectSkipped(
        age: const Duration(days: 3),
        snapshots: () async => (
          state: _snapshot(
            beads: [
              _session('session', 'work', old),
              _step('step', 'session', old),
            ],
          ),
          work: _snapshot(beads: [_bead('work', IssueType.task, old)]),
        ),
        execute: ({required protectedIds, required olderThanDays}) async =>
            throw StateError('writer\nfailed'),
        reason: 'Bad state: writer failed',
      );
    },
  );

  test('does not catch or duplicate a sink failure', () async {
    var sinkCalls = 0;
    final pruner = StateStorePruner(
      age: const Duration(days: 3),
      freshSnapshots: () async => (state: _snapshot(), work: _snapshot()),
      execute: _unreachedExecute,
      now: () => now,
      out: (_) {
        sinkCalls++;
        throw StateError('sink failed');
      },
    );

    await expectLater(pruner.run(), throwsStateError);
    expect(sinkCalls, 1);
  });
}

Future<({int beadsRemoved, int dependencyRowsRemoved})> _unreachedExecute({
  required Iterable<String> protectedIds,
  required int olderThanDays,
}) => throw StateError('executor should not run');

final class _MemoryStateStore {
  _MemoryStateStore({required this.state, required this.work});

  GraphSnapshot state;
  final GraphSnapshot work;
  var snapshotCalls = 0;
  var executeCalls = 0;
  final List<int> ages = <int>[];
  final List<Set<String>> protectionSets = <Set<String>>[];

  Future<({GraphSnapshot? state, GraphSnapshot? work})> freshSnapshots() async {
    snapshotCalls++;
    return (state: state, work: work);
  }

  Future<({int beadsRemoved, int dependencyRowsRemoved})> execute({
    required Iterable<String> protectedIds,
    required int olderThanDays,
  }) async {
    executeCalls++;
    ages.add(olderThanDays);
    final protected = protectedIds.toSet();
    protectionSets.add(protected);
    final removed = state.beadsById.keys
        .where((id) => !protected.contains(id))
        .toSet();
    final retainedDependencies = state.dependencies
        .where(
          (edge) =>
              !removed.contains(edge.issueId) &&
              !removed.contains(edge.dependsOnId),
        )
        .toList(growable: false);
    final removedDependencies =
        state.dependencies.length - retainedDependencies.length;
    state = GraphSnapshot.fromParts(
      beads: state.beadsById.values.where(
        (bead) => protected.contains(bead.id),
      ),
      dependencies: retainedDependencies,
      readyIds: const [],
      capturedAt: state.capturedAt,
    );
    return (
      beadsRemoved: removed.length,
      dependencyRowsRemoved: removedDependencies,
    );
  }
}

GraphSnapshot _snapshot({
  List<Bead> beads = const [],
  List<BeadDependency> dependencies = const [],
}) => GraphSnapshot.fromParts(
  beads: beads,
  dependencies: dependencies,
  readyIds: const [],
  capturedAt: DateTime.utc(2026, 9, 14),
);

Bead _session(String id, String workId, DateTime closedAt) => Bead(
  id: id,
  issueType: GridIssueTypes.session,
  status: BeadStatus.closed,
  closedAt: closedAt,
  metadata: {SessionBeadKeys.workBead: workId},
);

Bead _molecule(String id, String sessionId, DateTime closedAt) => Bead(
  id: id,
  issueType: GridIssueTypes.molecule,
  status: BeadStatus.closed,
  closedAt: closedAt,
  metadata: {MoleculeCircuitKeys.session: sessionId},
);

Bead _step(String id, String sessionId, DateTime closedAt) => Bead(
  id: id,
  issueType: GridIssueTypes.step,
  status: BeadStatus.closed,
  closedAt: closedAt,
  metadata: {MoleculeStepKeys.session: sessionId},
);

Bead _bead(String id, IssueType type, DateTime closedAt) => Bead(
  id: id,
  issueType: type,
  status: BeadStatus.closed,
  closedAt: closedAt,
);
