// tg-xh5d / tg-6t0h — the production-shaped proof. Every armed seat's NAME
// differs from its bead-id PREFIX (the real roster shape), and a cross-store
// blocker is expressed ONCE: as bd's native `external:` dependency row on the
// consumer's own bead. A project the roster does not arm is the LOUD hard
// refusal; a state-store `type=link` bead is inert data nothing reads.
// Pure-Dart, Fakes only, no I/O.
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

/// A RETIRED state-store `type=link` bead (tg-6t0h): the one-pass migration
/// converted every authored edge to a bd row and closed the receipt, and the
/// engine deleted the reader. One left OPEN by hand is inert data.
Bead linkBead(String id, {required String from, required String to}) => Bead(
  id: id,
  issueType: GridIssueTypes.link,
  status: BeadStatus.open,
  metadata: <String, dynamic>{
    'grid.link.from': from,
    'grid.link.to': to,
    'grid.link.type': 'blocks',
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
/// accessor over reactive state) — subscribe, capture, unsubscribe.
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

  test('an OPEN link bead in the state store is INERT — the join reads the '
      'frontier the union computed and nothing else (tg-6t0h)', () {
    // The capability IS shipped, so the union admits tg-mspw. An OPEN link
    // bead naming the SAME pair would have held it out before the hard cut;
    // after it, the state axis authors no edges at all.
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
    final bridge = StationJoinBridge(work: union, state: state)..start();
    addTearDown(bridge.dispose);

    final joined = read(bridge.notifier).graph;
    expect(joined.readyIds, contains('tg-mspw'));
    expect(joined.readyIds, contains('tg-safe'));
    expect(loud, isEmpty);
  });

  test('an UNSHIPPED capability keeps holding its consumer out THROUGH the '
      'join — the union is the one edge source', () {
    final union = unionOf();
    addTearDown(union.dispose);
    final state = FakeSnapshotSource(
      graphOf([
        linkBead('houston-l1', from: 'tg-safe', to: 'pow-18'),
      ], readyIds: const {}),
    );
    final bridge = StationJoinBridge(work: union, state: state)..start();
    addTearDown(bridge.dispose);

    final joined = read(bridge.notifier).graph;
    expect(joined.readyIds, isNot(contains('tg-mspw')));
    // tg-safe carries NO external row; the link bead naming it is inert.
    expect(joined.readyIds, contains('tg-safe'));
  });
}
