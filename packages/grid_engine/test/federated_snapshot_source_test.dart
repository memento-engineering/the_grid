// tg-nsj (`docs/SCRATCH-multi-root-federation.md` §4 + the
// `SCRATCH-grid-alignment.md` §4 rescope to LOCAL stores only): the
// FederatedSnapshotSource union — fan-in BEFORE the join bridge (D-F1),
// per-member freshness (D-F3), absence ≠ deletion (D-Z3), staleness
// fail-closed for NEW mounts (D-Z4), mutable membership (D-Z1/D-Z2), and the
// LOUD refusal of cross-store dependency rows (tg-mspw, which blocks off
// D-F2's dep-row edge source). Pure-Dart, no I/O.
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

  group('FederatedSnapshotSource — ready-staleness by AGE (tg-zd4v)', () {
    test(
      'a member that stops emitting stops contributing readyIds once its age '
      'exceeds the window — beads stay visible — and recovers on re-capture',
      () async {
        var now = DateTime.fromMillisecondsSinceEpoch(0);
        final tg = FakeSnapshotSource();
        final quiet = FakeSnapshotSource();
        final union = FederatedSnapshotSource(
          {'tg': tg, 'quiet': quiet},
          readyStaleAge: const Duration(seconds: 10),
          now: () => now,
        );
        addTearDown(union.dispose);

        tg.push(graphOf([bead('tg-1')], tick: 1000));
        quiet.push(graphOf([bead('quiet-1')], tick: 1000));
        await settle();
        expect(union.current!.readyIds, {'tg-1', 'quiet-1'});
        expect(union.freshness['quiet']!.stale, isFalse);

        // 'quiet' goes silent; a healthy member's floor tick recomputes the
        // union — the exact event-driven judgement a live resident performs.
        now = DateTime.fromMillisecondsSinceEpoch(15000);
        tg.push(graphOf([bead('tg-1')], tick: 15000));
        await settle();

        expect(
          union.current!.readyIds,
          {'tg-1'},
          reason: 'an aged-out member mints no NEW ready ids (D-Z4 by age)',
        );
        expect(
          union.current!.beadsById.keys,
          containsAll(['tg-1', 'quiet-1']),
          reason: 'absence is not deletion (D-Z3) — beads stay visible',
        );
        expect(union.freshness['quiet']!.stale, isTrue);

        // The member re-captures: fresh again, ready ids restored.
        quiet.push(graphOf([bead('quiet-1')], tick: 16000));
        await settle();
        expect(union.current!.readyIds, {'tg-1', 'quiet-1'});
        expect(union.freshness['quiet']!.stale, isFalse);
      },
    );

    test(
      'stale-by-age and recovery each flare EXACTLY once per edge',
      () async {
        var now = DateTime.fromMillisecondsSinceEpoch(0);
        final flares = <String>[];
        final tg = FakeSnapshotSource();
        final quiet = FakeSnapshotSource();
        final union = FederatedSnapshotSource(
          {'tg': tg, 'quiet': quiet},
          readyStaleAge: const Duration(seconds: 10),
          now: () => now,
          onFlare: (name, data) => flares.add('$name:${data['substation']}'),
        );
        addTearDown(union.dispose);

        tg.push(graphOf([bead('tg-1')], tick: 1000));
        quiet.push(graphOf([bead('quiet-1')], tick: 1000));
        await settle();
        expect(flares, isEmpty);

        now = DateTime.fromMillisecondsSinceEpoch(15000);
        tg.push(graphOf([bead('tg-1')], tick: 15000));
        await settle();
        expect(flares, ['sync.memberStaleByAge:quiet']);

        // More healthy ticks while 'quiet' stays stale: NO flare spam.
        now = DateTime.fromMillisecondsSinceEpoch(20000);
        tg.push(graphOf([bead('tg-1')], tick: 20000));
        now = DateTime.fromMillisecondsSinceEpoch(25000);
        tg.push(graphOf([bead('tg-1')], tick: 25000));
        await settle();
        expect(flares, ['sync.memberStaleByAge:quiet']);

        // Recovery flares once, then healthy silence.
        quiet.push(graphOf([bead('quiet-1')], tick: 26000));
        await settle();
        expect(flares, [
          'sync.memberStaleByAge:quiet',
          'sync.memberRecovered:quiet',
        ]);
        now = DateTime.fromMillisecondsSinceEpoch(27000);
        tg.push(graphOf([bead('tg-1')], tick: 27000));
        await settle();
        expect(flares, hasLength(2));
      },
    );
    test(
      'a QUIETLY-refreshing member (floor ticks, unchanged store) never ages '
      'out — the age judgement reads the live heartbeat, not the last '
      'published snapshot (the ready 16->4 live regression)',
      () async {
        var now = DateTime.fromMillisecondsSinceEpoch(0);
        final flares = <String>[];
        final tg = FakeSnapshotSource();
        final quiet = FakeSnapshotSource();
        final union = FederatedSnapshotSource(
          {'tg': tg, 'quiet': quiet},
          readyStaleAge: const Duration(seconds: 10),
          now: () => now,
          onFlare: (name, data) => flares.add(name),
        );
        addTearDown(union.dispose);

        tg.push(graphOf([bead('tg-1')], tick: 1000));
        quiet.push(graphOf([bead('quiet-1')], tick: 1000));
        await settle();

        // 'quiet' has NO changes to publish, but its runtime floor-refreshes:
        // current.capturedAt advances with zero emissions (change-gated).
        now = DateTime.fromMillisecondsSinceEpoch(15000);
        quiet.refreshQuietly(graphOf([bead('quiet-1')], tick: 15000));
        tg.push(graphOf([bead('tg-1')], tick: 15000));
        await settle();

        expect(
          union.current!.readyIds,
          {'tg-1', 'quiet-1'},
          reason:
              'a healthy quiet member must keep its frontier — aging it out '
              'silently shrank ready 16->4 on the first armed night',
        );
        expect(union.freshness['quiet']!.stale, isFalse);
        expect(flares, isEmpty);
      },
    );
  });

  group('FederatedSnapshotSource — cross-store dep rows are REFUSED, never '
      'blocking (tg-mspw)', () {
    test('a cross-store blocking row is reported LOUDLY and leaves the '
        'candidate READY — a dep row is not an edge', () async {
      final loud = <String>[];
      final tg = FakeSnapshotSource();
      final dash = FakeSnapshotSource();
      final union = FederatedSnapshotSource({
        'tg': tg,
        'dash': dash,
      }, onUnresolvedExternalDep: loud.add);
      addTearDown(union.dispose);

      const dep = BeadDependency(issueId: 'tg-1', dependsOnId: 'dash-1');
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

      expect(
        union.current!.readyIds,
        contains('tg-1'),
        reason: 'link beads are the only cross-store block (tg-hof7 Q1)',
      );
      expect(loud.single, contains('REFUSED'));
      expect(loud.single, contains('tg-1'));
      expect(loud.single, contains('dash-1'));
      expect(loud.single, contains('grid link'));
      expect(loud.single, contains('tg-xh5d'));
    });

    test('a row whose target NO member observes is refused LOUDLY too — never '
        'a silent pass', () async {
      final loud = <String>[];
      final tg = FakeSnapshotSource();
      final union = FederatedSnapshotSource({
        'tg': tg,
      }, onUnresolvedExternalDep: loud.add);
      addTearDown(union.dispose);

      const dep = BeadDependency(issueId: 'tg-1', dependsOnId: 'dash-999');
      tg.push(
        graphOf(
          [bead('tg-1')],
          dependencies: [dep],
          readyIds: {'tg-1'},
          tick: 1,
        ),
      );
      await settle();

      expect(union.current!.readyIds, contains('tg-1'));
      expect(loud.single, contains('tg-1'));
      expect(loud.single, contains('dash-999'));
      expect(loud.single, contains('tg(tg)'));
    });

    test('a SAME-store blocking row is left to the origin store\'s own '
        '`bd ready` — never re-classified, never reported', () async {
      final loud = <String>[];
      final tg = FakeSnapshotSource();
      final union = FederatedSnapshotSource({
        'tg': tg,
      }, onUnresolvedExternalDep: loud.add);
      addTearDown(union.dispose);

      const dep = BeadDependency(issueId: 'tg-1', dependsOnId: 'tg-2');
      tg.push(
        graphOf(
          [bead('tg-1'), bead('tg-2')],
          dependencies: [dep],
          readyIds: {'tg-1', 'tg-2'},
          tick: 1,
        ),
      );
      await settle();

      expect(union.current!.readyIds, {'tg-1', 'tg-2'});
      expect(loud, isEmpty);
    });

    test('an ALIASED member (name != prefix) resolves its own ids: the '
        'same-store row is silent, the cross-store row is refused', () async {
      final loud = <String>[];
      final grid = FakeSnapshotSource();
      final power = FakeSnapshotSource();
      final union = FederatedSnapshotSource(
        {'the_grid': grid, 'power_station': power},
        memberPrefixes: const {'the_grid': 'tg', 'power_station': 'pow'},
        onUnresolvedExternalDep: loud.add,
      );
      addTearDown(union.dispose);

      grid.push(
        graphOf(
          [bead('tg-1'), bead('tg-2')],
          dependencies: const [
            BeadDependency(issueId: 'tg-1', dependsOnId: 'tg-2'),
            BeadDependency(issueId: 'tg-1', dependsOnId: 'pow-9'),
          ],
          readyIds: {'tg-1', 'tg-2'},
          tick: 1,
        ),
      );
      power.push(graphOf([bead('pow-9')], tick: 1));
      await settle();

      expect(union.current!.readyIds, {'tg-1', 'tg-2', 'pow-9'});
      expect(loud, hasLength(1));
      expect(loud.single, contains('pow-9'));
      expect(loud.single, contains('the_grid(tg), power_station(pow)'));
    });

    test(
      'hyphenated prefixes still distinguish same from cross store',
      () async {
        final loud = <String>[];
        final infer = FakeSnapshotSource();
        final train = FakeSnapshotSource();
        final union = FederatedSnapshotSource({
          'swift-infer': infer,
          'swift-train': train,
        }, onUnresolvedExternalDep: loud.add);
        addTearDown(union.dispose);

        infer.push(
          graphOf(
            [bead('swift-infer-001'), bead('swift-infer-002')],
            dependencies: const [
              BeadDependency(
                issueId: 'swift-infer-001',
                dependsOnId: 'swift-infer-002',
              ),
              BeadDependency(
                issueId: 'swift-infer-001',
                dependsOnId: 'swift-train-001',
              ),
            ],
            readyIds: {'swift-infer-001', 'swift-infer-002'},
            tick: 1,
          ),
        );
        train.push(graphOf([bead('swift-train-001')], tick: 1));
        await settle();

        expect(union.current!.readyIds, {
          'swift-infer-001',
          'swift-infer-002',
          'swift-train-001',
        });
        expect(loud, hasLength(1));
        expect(loud.single, contains('swift-train-001'));
      },
    );

    test(
      'a non-blocking dependency type (`related`) is never refused',
      () async {
        final loud = <String>[];
        final tg = FakeSnapshotSource();
        final dash = FakeSnapshotSource();
        final union = FederatedSnapshotSource({
          'tg': tg,
          'dash': dash,
        }, onUnresolvedExternalDep: loud.add);
        addTearDown(union.dispose);

        const dep = BeadDependency(
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
        expect(loud, isEmpty);
      },
    );

    test('one authored row is reported ONCE across recomputes, and again '
        'after it disappears and returns', () async {
      final loud = <String>[];
      final tg = FakeSnapshotSource();
      final union = FederatedSnapshotSource({
        'tg': tg,
      }, onUnresolvedExternalDep: loud.add);
      addTearDown(union.dispose);

      const dep = BeadDependency(issueId: 'tg-1', dependsOnId: 'dash-999');
      tg.push(
        graphOf(
          [bead('tg-1')],
          dependencies: [dep],
          readyIds: {'tg-1'},
          tick: 1,
        ),
      );
      await settle();
      tg.push(
        graphOf(
          [bead('tg-1'), bead('tg-2')],
          dependencies: [dep],
          readyIds: {'tg-1', 'tg-2'},
          tick: 2,
        ),
      );
      await settle();
      expect(loud, hasLength(1), reason: 'rising edge, not per-recompute spam');

      // The operator deletes the row, then re-authors it: reported again.
      tg.push(graphOf([bead('tg-1')], readyIds: {'tg-1'}, tick: 3));
      await settle();
      tg.push(
        graphOf(
          [bead('tg-1')],
          dependencies: [dep],
          readyIds: {'tg-1'},
          tick: 4,
        ),
      );
      await settle();
      expect(loud, hasLength(2));
    });

    test('addMember carries the new member\'s prefix', () async {
      final loud = <String>[];
      final grid = FakeSnapshotSource();
      final power = FakeSnapshotSource();
      final union = FederatedSnapshotSource(
        {'the_grid': grid},
        memberPrefixes: const {'the_grid': 'tg'},
        onUnresolvedExternalDep: loud.add,
      );
      addTearDown(union.dispose);
      union.addMember('power_station', power, prefix: 'pow');

      power.push(
        graphOf(
          [bead('pow-9'), bead('pow-10')],
          dependencies: const [
            BeadDependency(issueId: 'pow-9', dependsOnId: 'pow-10'),
          ],
          readyIds: {'pow-9', 'pow-10'},
          tick: 1,
        ),
      );
      await settle();

      expect(union.members, {'the_grid', 'power_station'});
      expect(loud, isEmpty, reason: 'pow-9 → pow-10 is a SAME-store row');
    });
  });
}
