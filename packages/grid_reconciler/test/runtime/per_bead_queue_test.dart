import 'dart:async';

import 'package:grid_reconciler/grid_reconciler.dart';
import 'package:test/test.dart';

void main() {
  group('PerBeadQueue — single-writer-per-bead (invariant 7)', () {
    test('same-bead tasks run strictly in arrival order', () async {
      final queue = PerBeadQueue();
      final order = <String>[];

      // Three tasks for the SAME bead, the first slow. They must complete in
      // arrival order regardless of their individual delays.
      final a = queue.run('bead-1', () async {
        await Future<void>.delayed(const Duration(milliseconds: 30));
        order.add('a');
        return 'a';
      });
      final b = queue.run('bead-1', () async {
        await Future<void>.delayed(const Duration(milliseconds: 1));
        order.add('b');
        return 'b';
      });
      final c = queue.run('bead-1', () async {
        order.add('c');
        return 'c';
      });

      await Future.wait([a, b, c]);
      expect(order, ['a', 'b', 'c']);
    });

    test(
      'different-bead tasks interleave — a slow bead never blocks another',
      () async {
        final queue = PerBeadQueue();
        final completion = <String>[];

        // Bead A is slow; bead B is fast. B must finish before A.
        final slowA = queue.run('A', () async {
          await Future<void>.delayed(const Duration(milliseconds: 40));
          completion.add('A');
        });
        final fastB = queue.run('B', () async {
          await Future<void>.delayed(const Duration(milliseconds: 5));
          completion.add('B');
        });

        await Future.wait([slowA, fastB]);
        expect(completion, ['B', 'A'], reason: 'B is not serialized behind A');
      },
    );

    test(
      'a failed task does not wedge the bead — the next task still runs',
      () async {
        final queue = PerBeadQueue();
        final ran = <String>[];

        final failing = queue.run('bead-1', () async {
          throw StateError('boom');
        });
        final next = queue.run('bead-1', () async {
          ran.add('next');
          return 'ok';
        });

        await expectLater(failing, throwsA(isA<StateError>()));
        expect(await next, 'ok');
        expect(ran, ['next']);
      },
    );

    test('idle() completes when all queued work drains', () async {
      final queue = PerBeadQueue();
      unawaited(
        queue.run('A', () async {
          await Future<void>.delayed(const Duration(milliseconds: 10));
        }),
      );
      unawaited(
        queue.run('B', () async {
          await Future<void>.delayed(const Duration(milliseconds: 10));
        }),
      );
      expect(queue.busyBeads.toSet(), {'A', 'B'});
      await queue.idle();
      expect(queue.busyBeads, isEmpty);
    });
  });
}
