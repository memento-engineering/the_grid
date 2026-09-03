// tg-mspw — the production-shaped proof. Every armed seat's NAME differs from
// its bead-id PREFIX (the shape that made the old name-keyed classification
// resolve every real id to null), and the SAME two ids are expressed twice:
// once as a bd dependency row (REFUSED, blocks nothing) and once as a state
// store link bead (BLOCKS). Pure-Dart, Fakes only, no I/O.
import 'package:beads_dart/beads_dart.dart';
import 'package:grid_engine/grid_engine.dart';
import 'package:grid_engine/testing.dart';
import 'package:test/test.dart';

/// The armed roster shape production runs: name → bead-id prefix, aliased on
/// every seat (ADR-0006 Decision 1's prefix axis).
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

/// A state-store `type=link` bead — the ONE sanctioned cross-store edge.
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
          BeadDependency(issueId: 'tg-mspw', dependsOnId: 'pow-18'),
        ],
        readyIds: {'tg-mspw', 'tg-safe'},
      ),
    );
    power = FakeSnapshotSource(graphOf([bead('pow-18')]));
    space = FakeSnapshotSource(
      graphOf(
        [bead('space-9')],
        dependencies: const [
          BeadDependency(issueId: 'space-9', dependsOnId: 'dec-4'),
        ],
        readyIds: {'space-9'},
      ),
    );
    decor = FakeSnapshotSource(graphOf([bead('dec-4')]));
  });

  test('a foreign-id dependency row is REFUSED and blocks nothing, on every '
      'aliased seat', () {
    final union = unionOf();
    addTearDown(union.dispose);

    expect(
      union.current!.readyIds,
      containsAll(['tg-mspw', 'space-9']),
      reason: 'a dep row is not a cross-store edge — it may not hold work out',
    );
    expect(loud, hasLength(2));
    final tgLine = loud.firstWhere((m) => m.contains('tg-mspw'));
    expect(tgLine, contains('REFUSED'));
    expect(tgLine, contains('pow-18'));
    expect(tgLine, contains('the_grid(tg)'));
    expect(tgLine, contains('power_station(pow)'));
    expect(tgLine, contains('grid link tg-mspw --blocked-by pow-18'));
    expect(tgLine, contains('tg-xh5d'));
    final spaceLine = loud.firstWhere((m) => m.contains('space-9'));
    expect(spaceLine, contains('dec-4'));
  });

  test('a LINK bead between the SAME two ids DOES block through the join', () {
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
    expect(
      joined.readyIds,
      isNot(contains('tg-mspw')),
      reason: 'the link bead is the sanctioned cross-store edge',
    );
    expect(
      joined.readyIds,
      containsAll(['tg-safe', 'space-9']),
      reason: 'the sanity control — only the LINKED bead is held out',
    );
  });

  test('closing the link target re-admits the bead — the edge is closure-'
      'satisfied, and the dep row still contributes nothing', () {
    power = FakeSnapshotSource(
      graphOf([
        Bead(
          id: 'pow-18',
          issueType: IssueType.task,
          status: BeadStatus.closed,
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

    expect(read(bridge.notifier).graph.readyIds, contains('tg-mspw'));
  });
}
