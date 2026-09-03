import 'dart:async';

import 'package:genesis_tree/genesis_tree.dart';
import 'package:grid_engine/grid_engine.dart';
import 'package:test/test.dart';

final class _DiagnosableRoot extends Seed with GridDiagnosticable {
  const _DiagnosableRoot();

  @override
  Branch createBranch() => _LeafBranch(this);
}

final class _LeafBranch extends Branch {
  _LeafBranch(super.seed);
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
}
