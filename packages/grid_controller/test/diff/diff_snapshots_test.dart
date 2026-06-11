import 'package:grid_controller/grid_controller.dart';
import 'package:test/test.dart';

final _t0 = DateTime.utc(2026, 6, 11, 12);

Bead _bead(
  String id, {
  BeadStatus status = BeadStatus.open,
  int priority = 0,
  IssueType type = IssueType.task,
  List<String> labels = const [],
  Map<String, dynamic> metadata = const {},
  String title = 'title',
}) => Bead(
  id: id,
  title: title,
  status: status,
  priority: priority,
  issueType: type,
  labels: labels,
  metadata: metadata,
);

GraphSnapshot _snap(
  List<Bead> beads, {
  List<BeadDependency> deps = const [],
  Set<String> ready = const {},
}) => GraphSnapshot.fromParts(
  beads: beads,
  dependencies: deps,
  readyIds: ready,
  capturedAt: _t0,
);

void main() {
  group('diffSnapshots baseline', () {
    test('null before yields exactly one SnapshotInitialized', () {
      final after = _snap([_bead('a'), _bead('b')], ready: {'a'});
      final events = diffSnapshots(null, after);
      expect(events, hasLength(1));
      expect(
        events.single,
        isA<SnapshotInitialized>()
            .having((e) => e.beadCount, 'beadCount', 2)
            .having((e) => e.readyCount, 'readyCount', 1),
      );
    });

    test('diff(s, s) == [] for an identical snapshot', () {
      final s = _snap(
        [_bead('a', priority: 2), _bead('b', status: BeadStatus.closed)],
        deps: [const BeadDependency(issueId: 'a', dependsOnId: 'b')],
        ready: {'a'},
      );
      expect(diffSnapshots(s, s), isEmpty);
    });

    test('diff between two equal-but-distinct snapshots is empty', () {
      final a = _snap([_bead('a'), _bead('b')], ready: {'a'});
      final b = _snap([_bead('a'), _bead('b')], ready: {'a'});
      expect(diffSnapshots(a, b), isEmpty);
    });
  });

  group('bead lifecycle', () {
    test('created', () {
      final before = _snap([_bead('a')]);
      final after = _snap([_bead('a'), _bead('b')]);
      final events = diffSnapshots(before, after);
      expect(events, [isA<BeadCreated>()]);
      expect((events.single as BeadCreated).bead.id, 'b');
    });

    test('deleted (hard removal — A10)', () {
      final before = _snap([_bead('a'), _bead('b')]);
      final after = _snap([_bead('a')]);
      final events = diffSnapshots(before, after);
      expect(events, [isA<BeadDeleted>()]);
      expect((events.single as BeadDeleted).bead.id, 'b');
    });

    test('closed transition emits BeadClosed, not BeadUpdated', () {
      final before = _snap([_bead('a', status: BeadStatus.open)]);
      final after = _snap([_bead('a', status: BeadStatus.closed)]);
      final events = diffSnapshots(before, after);
      expect(events, [isA<BeadClosed>()]);
      final closed = events.single as BeadClosed;
      expect(closed.before.status, BeadStatus.open);
      expect(closed.after.status, BeadStatus.closed);
    });

    test('reopen transition emits BeadReopened', () {
      final before = _snap([_bead('a', status: BeadStatus.closed)]);
      final after = _snap([_bead('a', status: BeadStatus.inProgress)]);
      expect(diffSnapshots(before, after), [isA<BeadReopened>()]);
    });

    test('non-lifecycle change emits BeadUpdated with changed fields', () {
      final before = _snap([_bead('a', priority: 0)]);
      final after = _snap([_bead('a', priority: 3)]);
      final events = diffSnapshots(before, after);
      expect(events, [isA<BeadUpdated>()]);
      expect((events.single as BeadUpdated).changedFields, {'priority'});
    });

    test('status change that is not close/reopen is a BeadUpdated', () {
      final before = _snap([_bead('a', status: BeadStatus.open)]);
      final after = _snap([_bead('a', status: BeadStatus.inProgress)]);
      final events = diffSnapshots(before, after);
      expect(events, [isA<BeadUpdated>()]);
      expect((events.single as BeadUpdated).changedFields, contains('status'));
    });

    test('multiple changed fields are all reported', () {
      final before = _snap([_bead('a', priority: 0, title: 'x')]);
      final after = _snap([_bead('a', priority: 1, title: 'y')]);
      final updated = diffSnapshots(before, after).single as BeadUpdated;
      expect(updated.changedFields, {'priority', 'title'});
    });
  });

  group('change-class coverage', () {
    test('label-only edit is detected (set-insensitive to order)', () {
      final before = _snap([
        _bead('a', labels: ['x']),
      ]);
      final after = _snap([
        _bead('a', labels: ['x', 'y']),
      ]);
      final updated = diffSnapshots(before, after).single as BeadUpdated;
      expect(updated.changedFields, {'labels'});
    });

    test('label reordering only is NOT a change', () {
      final before = _snap([
        _bead('a', labels: ['x', 'y']),
      ]);
      final after = _snap([
        _bead('a', labels: ['y', 'x']),
      ]);
      expect(diffSnapshots(before, after), isEmpty);
    });

    test('metadata edit is detected via deep equality', () {
      final before = _snap([
        _bead('a', metadata: {'k': 'v'}),
      ]);
      final after = _snap([
        _bead('a', metadata: {'k': 'w'}),
      ]);
      final updated = diffSnapshots(before, after).single as BeadUpdated;
      expect(updated.changedFields, {'metadata'});
    });
  });

  group('dependencies', () {
    const edge = BeadDependency(
      issueId: 'a',
      dependsOnId: 'b',
      type: DependencyType.blocks,
    );

    test('added', () {
      final before = _snap([_bead('a'), _bead('b')]);
      final after = _snap([_bead('a'), _bead('b')], deps: [edge]);
      expect(diffSnapshots(before, after), [isA<DependencyAdded>()]);
    });

    test('removed', () {
      final before = _snap([_bead('a'), _bead('b')], deps: [edge]);
      final after = _snap([_bead('a'), _bead('b')]);
      expect(diffSnapshots(before, after), [isA<DependencyRemoved>()]);
    });

    test('same triple is stable across re-fetch', () {
      final before = _snap([_bead('a'), _bead('b')], deps: [edge]);
      final after = _snap([_bead('a'), _bead('b')], deps: [edge]);
      expect(diffSnapshots(before, after), isEmpty);
    });
  });

  group('ready set', () {
    test('entered and exited are reported in one event', () {
      final before = _snap([_bead('a'), _bead('b')], ready: {'a'});
      final after = _snap([_bead('a'), _bead('b')], ready: {'b'});
      final events = diffSnapshots(before, after);
      final ready = events.whereType<ReadySetChanged>().single;
      expect(ready.entered, {'b'});
      expect(ready.exited, {'a'});
    });

    test('no readyset event when membership unchanged', () {
      final before = _snap([_bead('a', priority: 0)], ready: {'a'});
      final after = _snap([_bead('a', priority: 1)], ready: {'a'});
      expect(
        diffSnapshots(before, after).whereType<ReadySetChanged>(),
        isEmpty,
      );
    });
  });

  group('ordering + composite', () {
    test('the canonical M1 demo event order: created then readyset', () {
      final before = _snap([_bead('a')]);
      final after = _snap(
        [_bead('a'), _bead('tron', type: IssueType.molecule)],
        ready: {'tron'},
      );
      final events = diffSnapshots(before, after);
      expect(events[0], isA<BeadCreated>());
      expect(events[1], isA<ReadySetChanged>());
      expect((events[0] as BeadCreated).bead.id, 'tron');
    });

    test('created beads are emitted in id-sorted order', () {
      final before = _snap([_bead('a')]);
      final after = _snap([_bead('a'), _bead('z'), _bead('m'), _bead('b')]);
      final ids = diffSnapshots(
        before,
        after,
      ).whereType<BeadCreated>().map((e) => e.bead.id).toList();
      expect(ids, ['b', 'm', 'z']);
    });

    test('GraphEvent.beadId resolves for bead-scoped events', () {
      final before = _snap([_bead('a', priority: 0)]);
      final after = _snap([_bead('a', priority: 1)]);
      expect(diffSnapshots(before, after).single.beadId, 'a');
    });
  });
}
