/// THE BEAD-SCOPED ELIGIBILITY BASIS REVISION (cut-wiring §W2.4 W2-B item 3) —
/// the `<snapshotRev>` hole of the ratified `admission.refused` key, and the
/// LEVEL SHAPE the key is ratified for.
library;

import 'dart:async';

import 'package:beads_dart/beads_dart.dart';
import 'package:grid_engine/grid_engine.dart';
import 'package:test/test.dart';

class _Source implements SnapshotSource {
  _Source([this._current]);

  final _controller = StreamController<GraphSnapshot>.broadcast();
  GraphSnapshot? _current;

  @override
  Stream<GraphSnapshot> get snapshots => _controller.stream;

  @override
  GraphSnapshot? get current => _current;

  void emit(GraphSnapshot snapshot) {
    _current = snapshot;
    _controller.add(snapshot);
  }

  Future<void> close() => _controller.close();
}

GraphSnapshot _graph(List<Bead> beads, {int tick = 0, Set<String>? readyIds}) =>
    GraphSnapshot.fromParts(
      beads: beads,
      dependencies: const [],
      readyIds: readyIds ?? beads.map((bead) => bead.id),
      capturedAt: DateTime.fromMillisecondsSinceEpoch(tick),
    );

Bead _work(String id, {Map<String, dynamic> metadata = const {}}) => Bead(
  id: id,
  issueType: IssueType.feature,
  status: BeadStatus.open,
  metadata: metadata,
);

void main() {
  group('EligibilityBasisRevisions — the LEVEL shape', () {
    test('an unchanged candidate keeps ONE value across many passes', () {
      final revisions = EligibilityBasisRevisions();
      final bead = _work('tg-1');
      EligibilityBasis basis() => EligibilityBasis.of(bead: bead, ready: true);

      final first = revisions.revise('tg-1', basis());
      for (var pass = 0; pass < 50; pass++) {
        expect(
          revisions.revise('tg-1', basis()),
          first,
          reason: 'a churning revision would mint a record per pass',
        );
      }
      expect(revisions['tg-1'], first);
    });

    test('changing ONE eligibility input moves it', () {
      final revisions = EligibilityBasisRevisions();
      final bead = _work('tg-1');
      final base = revisions.revise(
        'tg-1',
        EligibilityBasis.of(bead: bead, ready: true),
      );

      final unready = revisions.revise(
        'tg-1',
        EligibilityBasis.of(bead: bead, ready: false),
      );
      expect(unready, isNot(base));

      final excluded = revisions.revise(
        'tg-1',
        EligibilityBasis.of(
          bead: bead,
          ready: false,
          frontierExclusion: 'blocked by tg-9',
        ),
      );
      expect(excluded, isNot(unready));

      final sessioned = revisions.revise(
        'tg-1',
        EligibilityBasis.of(
          bead: bead,
          ready: false,
          frontierExclusion: 'blocked by tg-9',
          linkedSessions: const [
            SessionProjection(workBeadId: 'tg-1', sessionId: 's1'),
          ],
        ),
      );
      expect(sessioned, isNot(excluded));

      final approved = revisions.revise(
        'tg-1',
        EligibilityBasis.of(
          bead: _work(
            'tg-1',
            metadata: const {kEligibilityApprovalKey: '2026-09-12T00:00:00Z'},
          ),
          ready: false,
          frontierExclusion: 'blocked by tg-9',
          linkedSessions: const [
            SessionProjection(workBeadId: 'tg-1', sessionId: 's1'),
          ],
        ),
      );
      expect(approved, isNot(sessioned));
    });

    test('it is MONOTONE — a reverted basis never re-uses an old value', () {
      final revisions = EligibilityBasisRevisions();
      final bead = _work('tg-1');
      final first = revisions.revise(
        'tg-1',
        EligibilityBasis.of(bead: bead, ready: true),
      );
      revisions.revise('tg-1', EligibilityBasis.of(bead: bead, ready: false));
      final reverted = revisions.revise(
        'tg-1',
        EligibilityBasis.of(bead: bead, ready: true),
      );

      expect(reverted, isNot(first));
      expect(
        int.parse(reverted.split('-').first),
        greaterThan(int.parse(first.split('-').first)),
      );
    });

    test('it is bead-SCOPED, and prunes with the graph', () {
      final revisions = EligibilityBasisRevisions();
      final one = revisions.revise(
        'tg-1',
        EligibilityBasis.of(bead: _work('tg-1'), ready: true),
      );
      final two = revisions.revise(
        'tg-2',
        EligibilityBasis.of(bead: _work('tg-2'), ready: true),
      );

      expect(one, isNot(two), reason: 'the digest carries the bead id');
      expect(revisions.length, 2);
      revisions.retain({'tg-1'});
      expect(revisions.length, 1);
      expect(revisions['tg-2'], isNull);
    });
  });

  group('exposed on the joined snapshot', () {
    test(
      'the join publishes a stable revision until an input changes',
      () async {
        final work = _Source(_graph([_work('tg-1')]));
        final state = _Source(_graph(const []));
        final bridge = StationJoinBridge(work: work, state: state);
        addTearDown(bridge.dispose);

        final first = bridge.latest.eligibilityBasisRevisionOf('tg-1');
        expect(first, isNotNull);

        bridge.start();
        work.emit(_graph([_work('tg-1')], tick: 1));
        await pumpEventQueue();
        expect(
          bridge.latest.eligibilityBasisRevisionOf('tg-1'),
          first,
          reason: 'a fresh capture instant is not an eligibility input',
        );

        work.emit(_graph([_work('tg-1')], tick: 2, readyIds: const {}));
        await pumpEventQueue();
        expect(bridge.latest.eligibilityBasisRevisionOf('tg-1'), isNot(first));
      },
    );

    test('a bead that leaves the graph leaves the ledger', () async {
      final work = _Source(_graph([_work('tg-1'), _work('tg-2')]));
      final state = _Source(_graph(const []));
      final bridge = StationJoinBridge(work: work, state: state)..start();
      addTearDown(bridge.dispose);

      expect(bridge.latest.eligibilityBasisRevisionOf('tg-2'), isNotNull);
      work.emit(_graph([_work('tg-1')], tick: 1));
      await pumpEventQueue();
      expect(bridge.latest.eligibilityBasisRevisionsByBeadId.keys, ['tg-1']);
    });

    test('with no P6 mirror the barrier read is disarmed', () {
      final work = _Source(_graph([_work('tg-1')]));
      final state = _Source(_graph(const []));
      final bridge = StationJoinBridge(work: work, state: state);
      addTearDown(bridge.dispose);

      expect(bridge.latest.worktreeOutstanding.armed, isFalse);
    });
  });
}
