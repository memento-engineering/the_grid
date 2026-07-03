import 'dart:async';

import 'package:grid_controller/grid_controller.dart';
import 'package:test/test.dart';

import '../support/reactivity_fakes.dart';

/// A [SnapshotReader] whose read body is a caller-supplied async function —
/// lets a test hold a refresh open mid-flight.
class _BlockingReader implements SnapshotReader {
  _BlockingReader(this._build);
  final Future<GraphSnapshot> Function() _build;
  @override
  Future<GraphSnapshot> read() => _build();
}

void main() {
  group('GridControllerRuntime end-to-end (fakes)', () {
    test(
      'start takes a baseline and a manual signal drives a refresh',
      () async {
        var beads = [bead('a')];
        final reader = FakeSnapshotReader(() => snap(beads, ready: {'a'}));
        final manual = ManualDirtySource();
        final runtime = GridControllerRuntime(
          reader: reader,
          dirtySources: [manual],
          quietPeriod: const Duration(milliseconds: 5),
        );
        addTearDown(runtime.dispose);

        final events = <GraphEvent>[];
        final sub = runtime.events.listen(events.add);

        await runtime.start();
        expect(runtime.current, isNotNull);
        expect(
          runtime.recentEvents.whereType<SnapshotInitialized>(),
          hasLength(1),
        );

        // A real mutation arrives: add bead 'b', ring the manual source.
        beads = [bead('a'), bead('b', status: BeadStatus.open)];
        manual.trigger();
        await Future<void>.delayed(const Duration(milliseconds: 30));

        expect(events.whereType<BeadCreated>().single.bead.id, 'b');
        expect(runtime.stats.totalSignals, greaterThanOrEqualTo(1));
        expect(runtime.stats.refreshCount, greaterThanOrEqualTo(2));
        await sub.cancel();
      },
    );

    test('requery forces an immediate refresh', () async {
      var beads = [bead('a')];
      final reader = FakeSnapshotReader(() => snap(beads));
      final runtime = GridControllerRuntime(
        reader: reader,
        dirtySources: const [],
        quietPeriod: const Duration(seconds: 30),
      );
      addTearDown(runtime.dispose);

      await runtime.start();
      beads = [bead('a'), bead('c')];
      await runtime.requery();
      expect(runtime.current!.beadCount, 2);
    });

    test(
      'dispose drains an in-flight refresh without "add after close"',
      () async {
        // A reader that blocks lets us dispose mid-refresh and prove the
        // repository streams are not closed out from under the running refresh.
        final gate = Completer<void>();
        var built = 0;
        final reader = _BlockingReader(() async {
          built++;
          if (built == 2) await gate.future; // hold the 2nd read open
          return snap([bead('a')]);
        });
        final manual = ManualDirtySource();
        final runtime = GridControllerRuntime(
          reader: reader,
          dirtySources: [manual],
          quietPeriod: const Duration(milliseconds: 1),
        );
        await runtime.start(); // baseline (1st read)
        manual.trigger(); // schedules the 2nd read, which blocks on the gate
        await Future<void>.delayed(const Duration(milliseconds: 10));

        final disposeFuture = runtime.dispose(); // must wait for the gated read
        gate.complete(); // let the in-flight refresh finish
        await expectLater(disposeFuture, completes); // no exception thrown
      },
    );

    test('a closed transition surfaces as BeadClosed', () async {
      var beads = [bead('a', status: BeadStatus.open)];
      final reader = FakeSnapshotReader(() => snap(beads));
      final runtime = GridControllerRuntime(
        reader: reader,
        dirtySources: const [],
      );
      addTearDown(runtime.dispose);
      final events = <GraphEvent>[];
      final sub = runtime.events.listen(events.add);

      await runtime.start();
      beads = [bead('a', status: BeadStatus.closed)];
      await runtime.requery();
      await Future<void>.delayed(Duration.zero);
      expect(events.whereType<BeadClosed>(), hasLength(1));
      await sub.cancel();
    });

    test('errors forwards a failed refresh from the repository', () async {
      final reader = FakeSnapshotReader(() => snap([bead('a')]))
        ..error = StateError('dolt down');
      final runtime = GridControllerRuntime(
        reader: reader,
        dirtySources: const [],
      );
      addTearDown(runtime.dispose);

      final errors = <RefreshError>[];
      final sub = runtime.errors.listen(errors.add);
      await runtime.start(); // baseline read fails
      await Future<void>.delayed(Duration.zero);
      expect(errors, hasLength(1));
      expect(errors.single.error, isA<StateError>());
      await sub.cancel();
    });
  });
}
