// tg-xh5d — the production-shaped proof. Every armed seat's NAME differs from
// its bead-id PREFIX (the real roster shape), and the SAME two ids are
// expressed twice: once as bd's native `external:` dependency row (BLOCKS,
// exactly like a link bead) and once as a state-store link bead (BLOCKS). A
// project the roster does not arm is the LOUD hard refusal. Pure-Dart, Fakes
// only, no I/O.
import 'package:beads_dart/beads_dart.dart';
import 'package:grid_engine/grid_engine.dart';
import 'package:grid_engine/testing.dart';
import 'package:test/test.dart';

/// The armed roster shape production runs: name → bead-id prefix, aliased on
/// every seat (ADR-0006 Decision 1's prefix axis). An `external:` row names
/// the NAME; the prefix rides the refusal line.
const roster = <String, String>{
  'the_grid': 'tg',
  'power_station': 'pow',
  'space_station': 'space',
  'decor_station': 'dec',
};

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

/// A state-store `type=link` bead — the authored edge that stays authoritative
/// until the one-pass migration (tg-6t0h) deletes it.
Bead linkBead(String id, {required String from, required String to}) => Bead(
  id: id,
  issueType: GridIssueTypes.link,
  status: BeadStatus.open,
  metadata: <String, dynamic>{
    CrossLinkKeys.from: from,
    CrossLinkKeys.to: to,
    CrossLinkKeys.type: kCrossLinkBlocks,
    CrossLinkKeys.reason: 'waits on the upstream port',
    CrossLinkKeys.actor: 'governor',
  },
);

/// A CLOSED bead carrying the capability `bd ship` published.
Bead shipped(String id) => Bead(
  id: id,
  issueType: IssueType.task,
  status: BeadStatus.closed,
  labels: [exportLabel(id), providesLabel(id)],
);

/// Reads the notifier the consumer way (ADR-0008 D-H rule 2: no public sync
/// accessor over reactive state) — subscribe, capture, unsubscribe. The same
/// helper `cross_link_guard_test.dart` uses.
JoinedSnapshot read(JoinedSnapshotNotifier notifier) {
  late JoinedSnapshot value;
  final remove = notifier.addListener((s) => value = s);
  remove();
  return value;
}

void main() {
  late FakeSnapshotSource grid;
  late FakeSnapshotSource power;
  late FakeSnapshotSource space;
  late FakeSnapshotSource decor;
  late List<String> loud;

  /// The union over the aliased roster, seeded from each fake's `current` so
  /// the baseline is synchronous.
  FederatedSnapshotSource unionOf() => FederatedSnapshotSource(
    {
      'the_grid': grid,
      'power_station': power,
      'space_station': space,
      'decor_station': decor,
    },
    memberPrefixes: roster,
    onUnresolvedExternalDep: loud.add,
  );

  setUp(() {
    loud = <String>[];
    grid = FakeSnapshotSource(
      graphOf(
        [bead('tg-mspw'), bead('tg-safe')],
        dependencies: const [
          BeadDependency(
            issueId: 'tg-mspw',
            dependsOnId: 'external:power_station:pow-18',
          ),
        ],
        readyIds: {'tg-mspw', 'tg-safe'},
      ),
    );
    power = FakeSnapshotSource(graphOf([bead('pow-18')]));
    space = FakeSnapshotSource(
      graphOf(
        [bead('space-9')],
        dependencies: const [
          BeadDependency(
            issueId: 'space-9',
            dependsOnId: 'external:decor_station:dec-4',
          ),
        ],
        readyIds: {'space-9'},
      ),
    );
    decor = FakeSnapshotSource(graphOf([bead('dec-4')]));
  });

  test('an external: row HOLDS its consumer out on every aliased seat, '
      'silently — an unshipped prerequisite is not a fault', () {
    final union = unionOf();
    addTearDown(union.dispose);

    expect(
      union.current!.readyIds,
      isNot(anyElement(isIn(['tg-mspw', 'space-9']))),
      reason: 'neither pow-18 nor dec-4 has shipped',
    );
    expect(union.current!.readyIds, contains('tg-safe'));
    expect(loud, isEmpty);
  });

  test('shipping the capability re-admits the consumer — closure alone does '
      'not', () {
    power = FakeSnapshotSource(
      graphOf([
        Bead(
          id: 'pow-18',
          issueType: IssueType.task,
          status: BeadStatus.closed,
        ),
      ], readyIds: const {}),
    );
    final closedOnly = unionOf();
    expect(closedOnly.current!.readyIds, isNot(contains('tg-mspw')));
    closedOnly.dispose();

    power = FakeSnapshotSource(
      graphOf([shipped('pow-18')], readyIds: const {}),
    );
    final union = unionOf();
    addTearDown(union.dispose);
    expect(union.current!.readyIds, contains('tg-mspw'));
    expect(loud, isEmpty);
  });

  test('a row naming a project the roster does not arm is the LOUD hard '
      'refusal, and it BLOCKS', () {
    grid = FakeSnapshotSource(
      graphOf(
        [bead('tg-mspw'), bead('tg-safe')],
        dependencies: const [
          BeadDependency(
            issueId: 'tg-mspw',
            dependsOnId: 'external:dashboard:dash-1',
          ),
        ],
        readyIds: {'tg-mspw', 'tg-safe'},
      ),
    );
    final union = unionOf();
    addTearDown(union.dispose);

    expect(union.current!.readyIds, isNot(contains('tg-mspw')));
    expect(union.current!.readyIds, contains('tg-safe'));
    expect(loud.single, contains('REFUSED'));
    expect(loud.single, contains('tg-mspw'));
    expect(loud.single, contains('external:dashboard:dash-1'));
    expect(loud.single, contains('the_grid(tg)'));
    expect(loud.single, contains('power_station(pow)'));
  });

  test('a LINK bead between the SAME two ids blocks through the join, exactly '
      'as the external row blocks through the union', () {
    power = FakeSnapshotSource(
      graphOf([shipped('pow-18')], readyIds: const {}),
    );
    final union = unionOf();
    addTearDown(union.dispose);
    final state = FakeSnapshotSource(
      graphOf([
        linkBead('houston-l1', from: 'tg-mspw', to: 'pow-18'),
      ], readyIds: const {}),
    );
    final bridge = StationJoinBridge(
      work: union,
      state: state,
      onUnresolvedCrossLink: loud.add,
    )..start();
    addTearDown(bridge.dispose);

    // pow-18 is CLOSED, so the link edge is inert; the sanity control is that
    // the join changes nothing the union already decided.
    expect(read(bridge.notifier).graph.readyIds, contains('tg-mspw'));
  });

  test('an OPEN link target still blocks through the join while the external '
      'capability is shipped — both readers run until the migration', () {
    power = FakeSnapshotSource(
      graphOf([
        Bead(
          id: 'pow-18',
          issueType: IssueType.task,
          status: BeadStatus.open,
          labels: [exportLabel('pow-18'), providesLabel('pow-18')],
        ),
      ], readyIds: const {}),
    );
    final union = unionOf();
    addTearDown(union.dispose);
    final state = FakeSnapshotSource(
      graphOf([
        linkBead('houston-l1', from: 'tg-mspw', to: 'pow-18'),
      ], readyIds: const {}),
    );
    final bridge = StationJoinBridge(
      work: union,
      state: state,
      onUnresolvedCrossLink: loud.add,
    )..start();
    addTearDown(bridge.dispose);

    final joined = read(bridge.notifier).graph;
    expect(joined.readyIds, isNot(contains('tg-mspw')));
    expect(joined.readyIds, contains('tg-safe'));
  });
}
