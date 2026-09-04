import 'package:beads_dart/beads_dart.dart';
import 'package:grid_sdk/grid_sdk.dart';
import 'package:test/test.dart';

void main() {
  final snapshot = GraphSnapshot.fromParts(
    beads: const [
      Bead(
        id: 'tg-b',
        title: 'approved',
        issueType: IssueType.feature,
        status: BeadStatus.inProgress,
        metadata: {
          WorkBeadKeys.approvedBy: 'nico',
          WorkBeadKeys.approvedAt: '2026-09-03T12:00:00Z',
          WorkBeadKeys.approvedRev: 'abc123',
        },
      ),
      Bead(id: 'tg-a', title: 'blocked'),
      Bead(id: 'tg-c', title: 'ready'),
      Bead(id: 'tg-open-blocker', title: 'open blocker'),
      Bead(
        id: 'tg-closed-blocker',
        title: 'closed blocker',
        status: BeadStatus.closed,
      ),
      Bead(id: 'tg-z', title: 'closed', status: BeadStatus.closed),
    ],
    dependencies: const [
      BeadDependency(issueId: 'tg-a', dependsOnId: 'tg-open-blocker'),
      BeadDependency(issueId: 'tg-a', dependsOnId: 'tg-closed-blocker'),
    ],
    readyIds: const ['tg-c'],
    capturedAt: DateTime(2026, 9, 3),
  );

  test('projects open beads in id order with open blockers and approval', () {
    final rows = projectBoard(
      store: 'the_grid',
      root: '/grid',
      snapshot: snapshot,
    ).whereType<BoardBeadRow>().toList();

    expect(rows.map((row) => row.id), [
      'tg-a',
      'tg-b',
      'tg-c',
      'tg-open-blocker',
    ]);
    expect(rows.first.blockedBy, ['tg-open-blocker']);
    expect(rows[1].approvedBy, 'nico');
    expect(rows[1].approvedRev, 'abc123');
    expect(rows[2].ready, isTrue);
  });

  test('ANDs store, status, blocked, and approval filters', () {
    List<String> ids(BoardFilter filter) => projectBoard(
      store: 'the_grid',
      root: '/grid',
      snapshot: snapshot,
      filter: filter,
    ).whereType<BoardBeadRow>().map((row) => row.id).toList();

    expect(ids(const BoardFilter(stores: {'other'})), isEmpty);
    expect(ids(const BoardFilter(statuses: {'in_progress'})), ['tg-b']);
    expect(ids(const BoardFilter(blockedOnly: true)), ['tg-a']);
    expect(ids(const BoardFilter(approved: true)), ['tg-b']);
    expect(ids(const BoardFilter(approved: false)), [
      'tg-a',
      'tg-c',
      'tg-open-blocker',
    ]);
    expect(
      ids(
        const BoardFilter(
          stores: {'the_grid'},
          statuses: {'open'},
          blockedOnly: true,
          approved: false,
        ),
      ),
      ['tg-a'],
    );
  });

  test('active link targets join BLOCKED-BY and the blocked filter', () {
    final rows = projectBoard(
      store: 'the_grid',
      root: '/grid',
      snapshot: snapshot,
      linkBlockersByBeadId: const {
        'tg-c': ['genesis-7ob'],
      },
    ).whereType<BoardBeadRow>().toList();
    expect(rows.singleWhere((row) => row.id == 'tg-c').blockedBy, [
      'genesis-7ob',
    ]);

    final blocked = projectBoard(
      store: 'the_grid',
      root: '/grid',
      snapshot: snapshot,
      filter: const BoardFilter(blockedOnly: true),
      linkBlockersByBeadId: const {
        'tg-c': ['genesis-7ob'],
      },
    ).whereType<BoardBeadRow>().toList();
    expect(blocked.map((row) => row.id), ['tg-a', 'tg-c']);
  });

  test('both row union arms round-trip with their wire kinds', () {
    const rows = <BoardRow>[
      BoardRow.bead(
        id: 'tg-a',
        store: 'the_grid',
        root: '/grid',
        type: 'task',
        status: 'open',
        title: 'work',
      ),
      BoardRow.storeUnreadable(
        store: 'broken',
        root: '/broken',
        reason: 'offline',
      ),
    ];

    expect(rows.map((row) => row.toJson()['kind']), [
      'bead',
      'store_unreadable',
    ]);
    for (final row in rows) {
      expect(BoardRow.fromJson(row.toJson()), row);
    }
  });
}
