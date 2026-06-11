import 'package:grid_controller/grid_controller.dart';
import 'package:riverpod/riverpod.dart';
import 'package:test/test.dart';

import '../support/reactivity_fakes.dart';

void main() {
  group('BeadsRepository.refresh', () {
    test('baseline refresh publishes a snapshot and AsyncData state', () async {
      final reader = FakeSnapshotReader(() => snap([bead('a')], ready: {'a'}));
      final repo = BeadsRepository(reader);
      addTearDown(repo.dispose);

      final snapshots = <GraphSnapshot>[];
      final sub = repo.snapshots.listen(snapshots.add);
      await repo.refresh();
      await Future<void>.delayed(Duration.zero); // let broadcast delivery flush

      expect(snapshots, hasLength(1));
      expect(repo.current, isNotNull);
      expect(repo.state, isA<AsyncData<GraphSnapshot>>());
      expect(repo.recentEvents, [isA<SnapshotInitialized>()]);
      await sub.cancel();
    });

    test('a change emits the snapshot and flattened events', () async {
      var beads = [bead('a')];
      final reader = FakeSnapshotReader(() => snap(beads));
      final repo = BeadsRepository(reader);
      addTearDown(repo.dispose);

      final events = <GraphEvent>[];
      final sub = repo.events.listen(events.add);
      await repo.refresh(); // baseline
      beads = [bead('a'), bead('b')];
      await repo.refresh(); // creates b

      await Future<void>.delayed(Duration.zero);
      expect(events.whereType<BeadCreated>().single.bead.id, 'b');
      await sub.cancel();
    });

    test('an unchanged refresh publishes no snapshot', () async {
      final reader = FakeSnapshotReader(() => snap([bead('a')]));
      final repo = BeadsRepository(reader);
      addTearDown(repo.dispose);

      var snapshotEmissions = 0;
      final sub = repo.snapshots.listen((_) => snapshotEmissions++);
      await repo.refresh(); // baseline emits
      await repo.refresh(); // identical → no emit
      await Future<void>.delayed(Duration.zero);
      expect(snapshotEmissions, 1);
      await sub.cancel();
    });

    test('a failed read becomes AsyncError without throwing', () async {
      final reader = FakeSnapshotReader(() => snap([bead('a')]))
        ..error = StateError('dolt down');
      final repo = BeadsRepository(reader);
      addTearDown(repo.dispose);

      await repo.refresh(); // must not throw
      expect(repo.state, isA<AsyncError<GraphSnapshot>>());
    });

    test('readyBeads maps the ready set to beads', () async {
      final reader = FakeSnapshotReader(
        () => snap([bead('a'), bead('b')], ready: {'b'}),
      );
      final repo = BeadsRepository(reader);
      addTearDown(repo.dispose);
      await repo.refresh();
      expect(repo.readyBeads.map((b) => b.id), ['b']);
    });

    test('event ring buffer is capped', () async {
      var n = 0;
      final reader = FakeSnapshotReader(() {
        // each refresh adds one new bead → one BeadCreated event
        return snap([for (var i = 0; i <= n; i++) bead('b$i')]);
      });
      final repo = BeadsRepository(reader, eventBufferSize: 4);
      addTearDown(repo.dispose);
      for (n = 0; n < 10; n++) {
        await repo.refresh();
      }
      expect(repo.recentEvents.length, lessThanOrEqualTo(4));
    });
  });
}
