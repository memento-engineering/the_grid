import 'dart:async';

import 'package:beads_dart/beads_dart.dart';
import 'package:genesis_tree/genesis_tree.dart';
import 'package:grid_diagnostics_contract/grid_diagnostics_contract.dart';
import 'package:grid_engine/grid_engine.dart';
import 'package:grid_engine/testing.dart';
import 'package:test/test.dart';

final class _DiagnosableRoot extends Seed with Diagnosable {
  const _DiagnosableRoot();

  @override
  Branch createBranch() => _LeafBranch(this);
}

final class _LeafBranch extends Branch {
  _LeafBranch(super.seed);
}

final class _IdleResolver implements SessionResolver {
  const _IdleResolver();

  @override
  Seed sessionFor({required Bead bead, SessionProjection? session}) =>
      const Idle();
}

GraphSnapshot _emptyGraph(DateTime capturedAt) => GraphSnapshot.fromParts(
  beads: const [],
  dependencies: const [],
  readyIds: const [],
  capturedAt: capturedAt,
);

Future<void> _pump() async {
  for (var i = 0; i < 5; i++) {
    await Future<void>.delayed(Duration.zero);
  }
}

StationKernel _kernel({
  required FakeSnapshotSource work,
  required FakeSnapshotSource state,
  TreeProjector? treeProjector,
}) {
  final fakes = buildFakes();
  return StationKernel(
    bridge: StationJoinBridge(work: work, state: state),
    stationServices: fakes.ctx,
    resolver: const _IdleResolver(),
    substations: [
      SubstationScope(
        configNotifier: SubstationConfigNotifier(
          const SubstationConfig(substationId: 'tg', ownedSubstations: {'tg'}),
        ),
        key: const ValueKey('scope.tg'),
      ),
    ],
    treeProjector: treeProjector,
  );
}

void main() {
  test('projects once per flush with injected time and broadcast identity', () {
    final owner = TreeOwner();
    addTearDown(owner.dispose);
    final root = owner.mountRoot(const _DiagnosableRoot());
    var clockCalls = 0;
    final projectedAt = DateTime.utc(2026, 7, 23);
    final projector = TreeProjector(
      clock: () {
        clockCalls++;
        return projectedAt;
      },
    );
    addTearDown(projector.dispose);

    final first = <TreeSnapshot>[];
    final second = <TreeSnapshot>[];
    projector.snapshots.listen(first.add);
    projector.snapshots.listen(second.add);

    projector.afterFlush(root);

    expect(clockCalls, 1);
    expect(first, hasLength(1));
    expect(second, hasLength(1));
    expect(identical(first.single, second.single), isTrue);
    expect(identical(first.single, projector.latest), isTrue);
    expect(projector.latest!.projectedAt, projectedAt);
  });

  test(
    'starts empty, replaces latest in order, and closes idempotently',
    () async {
      final owner = TreeOwner();
      addTearDown(owner.dispose);
      final root = owner.mountRoot(const _DiagnosableRoot());
      final times = [DateTime.utc(2026, 7, 23), DateTime.utc(2026, 7, 24)];
      var clockCalls = 0;
      final projector = TreeProjector(clock: () => times[clockCalls++]);
      final emitted = <TreeSnapshot>[];
      final firstDone = Completer<void>();
      final secondDone = Completer<void>();
      projector.snapshots.listen(emitted.add, onDone: firstDone.complete);
      projector.snapshots.listen(
        (snapshot) => expect(identical(snapshot, projector.latest), isTrue),
        onDone: secondDone.complete,
      );

      expect(projector.latest, isNull);
      projector.afterFlush(root);
      final firstLatest = projector.latest;
      projector.afterFlush(root);

      expect(emitted.map((snapshot) => snapshot.projectedAt), times);
      expect(identical(projector.latest, firstLatest), isFalse);
      expect(identical(projector.latest, emitted.last), isTrue);

      projector.dispose();
      projector.dispose();
      await Future.wait([firstDone.future, secondDone.future]);
      projector.afterFlush(root);

      expect(clockCalls, 2);
      expect(emitted, hasLength(2));
    },
  );

  test('kernel projects retained root once after a coalesced flush', () async {
    final initial = _emptyGraph(DateTime.utc(2026, 7, 22));
    final work = FakeSnapshotSource(initial);
    final state = FakeSnapshotSource(initial);
    addTearDown(work.close);
    addTearDown(state.close);
    final projectedAt = DateTime.utc(2026, 7, 23);
    final projector = TreeProjector(clock: () => projectedAt);
    final emitted = <TreeSnapshot>[];
    projector.snapshots.listen(emitted.add);
    final kernel = _kernel(work: work, state: state, treeProjector: projector);
    addTearDown(kernel.dispose);

    kernel.start();
    expect(projector.latest, isNull);
    work.push(_emptyGraph(DateTime.utc(2026, 7, 23, 1)));
    state.push(_emptyGraph(DateTime.utc(2026, 7, 23, 2)));
    await _pump();

    expect(emitted, hasLength(1));
    expect(emitted.single.root.seedType, 'Station');
    expect(emitted.single.projectedAt, projectedAt);
  });

  test('kernel projector seam is optional and null by default', () async {
    final initial = _emptyGraph(DateTime.utc(2026, 7, 22));
    final work = FakeSnapshotSource(initial);
    final state = FakeSnapshotSource(initial);
    addTearDown(work.close);
    addTearDown(state.close);
    final kernel = _kernel(work: work, state: state);

    expect(kernel.start, returnsNormally);
    work.push(_emptyGraph(DateTime.utc(2026, 7, 23, 1)));
    state.push(_emptyGraph(DateTime.utc(2026, 7, 23, 2)));
    await _pump();
    expect(kernel.dispose, returnsNormally);
  });
}
