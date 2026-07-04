// tg-nsj (`docs/SCRATCH-multi-root-federation.md` §4 + the
// `SCRATCH-grid-alignment.md` §4 rescope to LOCAL stores only): the
// FederatedSnapshotSource union — fan-in BEFORE the join bridge (D-F1),
// per-member freshness (D-F3), absence ≠ deletion (D-Z3), staleness
// fail-closed for NEW mounts (D-Z4), mutable membership (D-Z1/D-Z2), and the
// cross-store external-dep guard (D-F2). Pure-Dart, no I/O.
import 'package:beads_dart/beads_dart.dart';
import 'package:grid_engine/grid_engine.dart';
import 'package:grid_engine/testing.dart';
import 'package:test/test.dart';

GraphSnapshot graphOf(
  List<Bead> beads, {
  List<BeadDependency> dependencies = const [],
  Set<String>? readyIds,
  int tick = 0,
}) => GraphSnapshot.fromParts(
  beads: beads,
  dependencies: dependencies,
  readyIds: readyIds ?? beads.map((b) => b.id).toSet(),
  capturedAt: DateTime.fromMillisecondsSinceEpoch(tick),
);

/// A [FakeSnapshotSource] delivers via a real broadcast stream (like the live
/// runtime), so a listener only observes a push after a microtask turn.
Future<void> settle() => Future<void>.delayed(Duration.zero);

void main() {
  group('FederatedSnapshotSource — union of LOCAL members', () {
    test('current is null before ANY member has published a baseline', () {
      final tg = FakeSnapshotSource();
      final dash = FakeSnapshotSource();
      final union = FederatedSnapshotSource({'tg': tg, 'dash': dash});
      expect(union.current, isNull);
    });

    test('merges disjoint members\' beads + dependencies directly (ids are '
        'prefix-disjoint — no rewrite needed)', () async {
      final tg = FakeSnapshotSource();
      final dash = FakeSnapshotSource();
      final union = FederatedSnapshotSource({'tg': tg, 'dash': dash});
      addTearDown(union.dispose);

      tg.push(graphOf([bead('tg-1')], tick: 1));
      dash.push(graphOf([bead('dash-1')], tick: 2));
      await settle();

      final current = union.current!;
      expect(current.beadsById.keys, containsAll(['tg-1', 'dash-1']));
      expect(current.readyIds, {'tg-1', 'dash-1'});
      // The union's scalar capturedAt is the MAX of the parts (D-F3).
      expect(current.capturedAt, DateTime.fromMillisecondsSinceEpoch(2));
    });

    test('emits on the snapshots stream ONLY on a non-empty diff (the honest '
        'change gate, D-F3) — re-pushing an unchanged member snapshot emits '
        'nothing new', () async {
      final tg = FakeSnapshotSource();
      final union = FederatedSnapshotSource({'tg': tg});
      addTearDown(union.dispose);

      final events = <GraphSnapshot>[];
      union.snapshots.listen(events.add);

      final snap = graphOf([bead('tg-1')], tick: 1);
      tg.push(snap);
      await settle();
      expect(events, hasLength(1));

      // A member re-publishing the SAME logical snapshot is a no-op diff.
      tg.push(graphOf([bead('tg-1')], tick: 1));
      await settle();
      expect(events, hasLength(1), reason: 'no real change → no emission');
    });

    test(
      'absence ≠ deletion (D-Z3): a member stream error RETAINS its last '
      'known beads in the union but marks it stale in the freshness vector',
      () async {
        final tg = FakeSnapshotSource();
        final dash = FakeSnapshotSource();
        final union = FederatedSnapshotSource({'tg': tg, 'dash': dash});
        addTearDown(union.dispose);

        tg.push(graphOf([bead('tg-1')], tick: 1));
        dash.push(graphOf([bead('dash-1')], tick: 1));
        await settle();
        expect(union.freshness['dash']!.stale, isFalse);

        dash.raiseError('connection dropped');
        await settle();

        // The bead stays visible — NOT synthesized as deleted.
        expect(union.current!.beadsById.keys, contains('dash-1'));
        expect(union.freshness['dash']!.stale, isTrue);
      },
    );

    test('staleness is fail-closed for NEW mounts (D-Z4): once a member goes '
        'stale, its ready ids drop out of the union (its truth can\'t be '
        'refreshed) though its beads remain visible; recovering clears '
        'staleness and re-admits them', () async {
      final tg = FakeSnapshotSource();
      final dash = FakeSnapshotSource();
      final union = FederatedSnapshotSource({'tg': tg, 'dash': dash});
      addTearDown(union.dispose);

      tg.push(graphOf([bead('tg-1')], tick: 1));
      dash.push(graphOf([bead('dash-1')], tick: 1));
      await settle();
      expect(union.current!.readyIds, {'tg-1', 'dash-1'});

      dash.raiseError('connection dropped');
      await settle();
      expect(union.current!.readyIds, {'tg-1'});
      expect(union.current!.beadsById.keys, contains('dash-1'));

      // Recovery: a fresh emission clears staleness and re-admits it.
      dash.push(graphOf([bead('dash-1')], tick: 2));
      await settle();
      expect(union.freshness['dash']!.stale, isFalse);
      expect(union.current!.readyIds, {'tg-1', 'dash-1'});
    });

    test('mutable membership (D-Z1/D-Z2): addMember attaches a NEW store at '
        'runtime and its snapshot folds into the union immediately', () async {
      final tg = FakeSnapshotSource();
      final union = FederatedSnapshotSource({'tg': tg});
      addTearDown(union.dispose);
      tg.push(graphOf([bead('tg-1')], tick: 1));
      await settle();

      final dash = FakeSnapshotSource();
      dash.push(graphOf([bead('dash-1')], tick: 1));
      union.addMember('dash', dash);

      expect(union.members, {'tg', 'dash'});
      expect(union.current!.beadsById.keys, containsAll(['tg-1', 'dash-1']));
    });

    test('removeMember detaches a store — its beads and ready ids drop out of '
        'the union entirely (a deliberate un-registration, distinct from a '
        'stream error)', () async {
      final tg = FakeSnapshotSource();
      final dash = FakeSnapshotSource();
      final union = FederatedSnapshotSource({'tg': tg, 'dash': dash});
      addTearDown(union.dispose);
      tg.push(graphOf([bead('tg-1')], tick: 1));
      dash.push(graphOf([bead('dash-1')], tick: 1));
      await settle();

      union.removeMember('dash');

      expect(union.members, {'tg'});
      expect(union.current!.beadsById.keys, isNot(contains('dash-1')));
      expect(union.freshness.containsKey('dash'), isFalse);
    });

    test(
      'addMember is a no-op when the substation is already a member',
      () async {
        final tg = FakeSnapshotSource();
        final union = FederatedSnapshotSource({'tg': tg});
        addTearDown(union.dispose);
        tg.push(graphOf([bead('tg-1')], tick: 1));
        await settle();

        final other = FakeSnapshotSource();
        union.addMember('tg', other); // ignored — 'tg' already registered.
        expect(union.members, {'tg'});
        expect(union.current!.beadsById.keys, {'tg-1'});
      },
    );
  });

  group('FederatedSnapshotSource — the external-dep guard (D-F2)', () {
    test('a candidate blocked by an OPEN cross-store dependency is excluded '
        'from ready; closing the target re-admits it', () async {
      final tg = FakeSnapshotSource();
      final dash = FakeSnapshotSource();
      final union = FederatedSnapshotSource({'tg': tg, 'dash': dash});
      addTearDown(union.dispose);

      final dep = const BeadDependency(issueId: 'tg-1', dependsOnId: 'dash-1');
      tg.push(
        graphOf(
          [bead('tg-1')],
          dependencies: [dep],
          readyIds: {
            'tg-1',
          }, // tg's OWN `bd ready` doesn't see the foreign dep.
          tick: 1,
        ),
      );
      dash.push(graphOf([bead('dash-1')], tick: 1));
      await settle();

      expect(
        union.current!.readyIds,
        isNot(contains('tg-1')),
        reason: 'dash-1 is open — tg-1 stays blocked across the union',
      );

      // dash-1 closes: the external dependency is now satisfied.
      dash.push(
        graphOf([
          Bead(
            id: 'dash-1',
            issueType: IssueType.task,
            status: BeadStatus.closed,
          ),
        ], tick: 2),
      );
      await settle();

      expect(union.current!.readyIds, contains('tg-1'));
    });

    test(
      'a candidate blocked by a dep target NOT observed by any federated '
      'store is excluded fail-closed + LOUD (never silently satisfied)',
      () async {
        final messages = <String>[];
        final tg = FakeSnapshotSource();
        final union = FederatedSnapshotSource({
          'tg': tg,
        }, onUnresolvedExternalDep: messages.add);
        addTearDown(union.dispose);

        final dep = const BeadDependency(
          issueId: 'tg-1',
          dependsOnId: 'dash-999',
        );
        tg.push(
          graphOf(
            [bead('tg-1')],
            dependencies: [dep],
            readyIds: {'tg-1'},
            tick: 1,
          ),
        );
        await settle();

        expect(union.current!.readyIds, isNot(contains('tg-1')));
        expect(messages, isNotEmpty);
        expect(messages.single, contains('tg-1'));
        expect(messages.single, contains('dash-999'));
      },
    );

    test('a SAME-store blocking dependency is left to the origin store\'s own '
        '`bd ready` — the guard only re-applies CROSS-store edges', () async {
      final tg = FakeSnapshotSource();
      final union = FederatedSnapshotSource({'tg': tg});
      addTearDown(union.dispose);

      final dep = const BeadDependency(issueId: 'tg-1', dependsOnId: 'tg-2');
      tg.push(
        graphOf(
          [bead('tg-1'), bead('tg-2')],
          dependencies: [dep],
          // A contrived candidate set: tg's own ready computation would
          // normally never include a bead genuinely blocked in-store, but
          // the guard must not ALSO apply to a same-store edge — it is
          // scoped to cross-store blocks only.
          readyIds: {'tg-1', 'tg-2'},
          tick: 1,
        ),
      );
      await settle();

      expect(union.current!.readyIds, {'tg-1', 'tg-2'});
    });

    test('a non-blocking dependency type (e.g. `related`) never triggers the '
        'guard, cross-store or not', () async {
      final tg = FakeSnapshotSource();
      final dash = FakeSnapshotSource();
      final union = FederatedSnapshotSource({'tg': tg, 'dash': dash});
      addTearDown(union.dispose);

      final dep = const BeadDependency(
        issueId: 'tg-1',
        dependsOnId: 'dash-1',
        type: DependencyType.related,
      );
      tg.push(
        graphOf(
          [bead('tg-1')],
          dependencies: [dep],
          readyIds: {'tg-1'},
          tick: 1,
        ),
      );
      dash.push(graphOf([bead('dash-1')], tick: 1));
      await settle();

      expect(union.current!.readyIds, contains('tg-1'));
    });
  });
}
