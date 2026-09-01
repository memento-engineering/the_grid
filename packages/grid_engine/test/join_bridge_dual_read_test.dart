/// THE JOIN'S THIRD INPUT (cut-wiring C2) — the P1 snapshot threaded into
/// `_join` as a PURE value, the `headChanges` re-join seam, and the wave-1
/// invariant that binds them: under `observe`, NOTHING the comparator sees
/// changes what the join produces.
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

GraphSnapshot _graph(List<Bead> beads, {int tick = 0}) =>
    GraphSnapshot.fromParts(
      beads: beads,
      dependencies: const [],
      readyIds: beads.map((b) => b.id),
      capturedAt: DateTime.fromMillisecondsSinceEpoch(tick),
    );

Bead _work(String id) =>
    Bead(id: id, issueType: IssueType.feature, status: BeadStatus.open);

Bead _sessionBead(
  String id, {
  required String workBeadId,
  bool closed = false,
}) => Bead(
  id: id,
  issueType: GridIssueTypes.session,
  status: closed ? BeadStatus.closed : BeadStatus.open,
  metadata: {
    'rig': 'tgdog',
    'work_bead': workBeadId,
    if (closed) 'grid.outcome': 'complete',
  },
);

final class _Head implements SessionHeadView {
  _Head({
    required this.sessionId,
    required this.workBeadId,
    this.isOpen = true,
    this.outcome,
  });

  @override
  final String sessionId;
  @override
  final String workBeadId;
  @override
  final bool isOpen;
  @override
  final SessionHeadOutcome? outcome;
  @override
  int get round => 0;
  @override
  bool get held => false;
  @override
  String? get heldReason => null;
  @override
  String? get workTerminalReason => null;
  @override
  int? get pgid => null;
  @override
  int? get pid => null;
  @override
  String? get attemptId => null;
  @override
  SessionHeadProvenance? get terminalProvenance => null;
  @override
  String? get unknownReason => null;
  @override
  DateTime get startedAt => DateTime.utc(2026, 8, 31, 10);
  @override
  DateTime? get closedAt => null;
  @override
  int get lastSeq => 1;
}

final class _Snapshot implements TrajectoryHeadSnapshot {
  _Snapshot(this._rows, {this.version = 1});

  final List<SessionHeadView> _rows;

  @override
  final int version;
  @override
  TrajectorySnapshotHealth get health => TrajectorySnapshotHealth.live;
  @override
  DateTime? get seededAt => DateTime.utc(2026, 8, 31, 9);
  @override
  DateTime? get firstEpochClaimedAt => DateTime.utc(2026, 8, 31, 9);

  @override
  SessionHeadView? bySessionId(String sessionId) {
    for (final row in _rows) {
      if (row.sessionId == sessionId) return row;
    }
    return null;
  }

  @override
  SessionHeadWinner byWorkBead(String workBeadId) => sessionHeadWinnerOf([
    for (final row in _rows)
      if (row.workBeadId == workBeadId) row,
  ]);

  @override
  Iterable<SessionHeadView> get rows => _rows;
}

void main() {
  test('the snapshot is a PURE third input: under `observe` the sessions map '
      'is byte-for-byte what pure legacy produced', () {
    final work = _Source(_graph([_work('tg-1')]));
    final state = _Source(
      _graph([_sessionBead('tgdog-s1', workBeadId: 'tg-1')]),
    );
    final legacyOnly = StationJoinBridge(work: work, state: state);
    // A head that DISAGREES loudly — closed and done while legacy says live.
    final observer = DualReadSessionObserver(mode: DualReadMode.observe);
    final dual = StationJoinBridge(
      work: work,
      state: state,
      headSnapshot: () => _Snapshot([
        _Head(
          sessionId: 'tgdog-s1',
          workBeadId: 'tg-1',
          isOpen: false,
          outcome: SessionHeadOutcome.succeeded,
        ),
      ]),
      dualRead: observer,
    );
    addTearDown(legacyOnly.dispose);
    addTearDown(dual.dispose);

    final legacySession = legacyOnly.latest.sessionsByWorkBead['tg-1']!;
    final dualSession = dual.latest.sessionsByWorkBead['tg-1']!;
    expect(dualSession, legacySession);
    expect(sessionDispositionOf(dualSession), isA<LiveSession>());
    // …and the comparator DID see it.
    expect(observer.accounting.divergences, greaterThan(0));
  });

  test('with no snapshot wired the bridge is unchanged and the comparator '
      'never runs', () {
    final work = _Source(_graph([_work('tg-1')]));
    final state = _Source(
      _graph([_sessionBead('tgdog-s1', workBeadId: 'tg-1')]),
    );
    final observer = DualReadSessionObserver(mode: DualReadMode.observe);
    final bridge = StationJoinBridge(
      work: work,
      state: state,
      dualRead: observer,
    );
    addTearDown(bridge.dispose);

    expect(bridge.latest.sessionsByWorkBead, hasLength(1));
    expect(observer.accounting.passes, isZero);
  });

  test('headChanges RE-JOINS: a fold-side fact pushes without waiting for a '
      'work or state emission', () async {
    final work = _Source(_graph([_work('tg-1')]));
    final state = _Source(
      _graph([_sessionBead('tgdog-s1', workBeadId: 'tg-1')]),
    );
    var snapshot = _Snapshot([
      _Head(sessionId: 'tgdog-s1', workBeadId: 'tg-1'),
    ]);
    void Function(TrajectoryHeadSnapshot)? listener;
    final observer = DualReadSessionObserver(mode: DualReadMode.observe);
    final bridge = StationJoinBridge(
      work: work,
      state: state,
      headSnapshot: () => snapshot,
      onHeadChanges: (l) {
        listener = l;
        return () => listener = null;
      },
      dualRead: observer,
    );
    addTearDown(bridge.dispose);

    final pushes = <JoinedSnapshot>[];
    bridge.notifier.addListener(pushes.add, fireImmediately: false);
    bridge.start();
    expect(listener, isNotNull, reason: 'the seam must be subscribed');
    final beforePasses = observer.accounting.passes;
    final beforePushes = pushes.length;

    // The mirror publishes a new version; nothing on work or state moved.
    snapshot = _Snapshot([
      _Head(sessionId: 'tgdog-s1', workBeadId: 'tg-1'),
    ], version: 2);
    listener!(snapshot);

    expect(pushes.length, beforePushes + 1);
    expect(observer.accounting.passes, beforePasses + 1);
  });

  test('THE ROLLBACK POSTURE (r12): under `off` the bridge SUBSCRIBES to '
      'neither mirror, so the push cadence is pre-cut mainline\'s', () {
    // The mirror publishes on EVERY append that yields a delta — including
    // the derived process-lifecycle pair, which carries nothing the legacy
    // join reads — and each publish drives a full re-join plus a
    // `notifier.push`, a mount-frontier evaluation cadence the station did not
    // have before this cut. `off` has to be byte-identical to mainline, so it
    // does not subscribe at all.
    final work = _Source(_graph([_work('tg-1')]));
    final state = _Source(
      _graph([_sessionBead('tgdog-s1', workBeadId: 'tg-1')]),
    );
    var headSubscribed = false;
    var stepSubscribed = false;
    final bridge = StationJoinBridge(
      work: work,
      state: state,
      headSnapshot: () =>
          _Snapshot([_Head(sessionId: 'tgdog-s1', workBeadId: 'tg-1')]),
      onHeadChanges: (_) {
        headSubscribed = true;
        return () {};
      },
      onStepChanges: (_) {
        stepSubscribed = true;
        return () {};
      },
      dualRead: DualReadSessionObserver(mode: DualReadMode.off),
      stepDualRead: DualReadStepObserver(mode: DualReadMode.off),
    );
    addTearDown(bridge.dispose);
    bridge.start();

    expect(headSubscribed, isFalse);
    expect(stepSubscribed, isFalse);
  });

  test('dispose unsubscribes the seam and emits the boot-final summary', () {
    final work = _Source(_graph([_work('tg-1')]));
    final state = _Source(
      _graph([_sessionBead('tgdog-s1', workBeadId: 'tg-1', closed: true)]),
    );
    var removed = false;
    final notes = <(String, String)>[];
    final bridge = StationJoinBridge(
      work: work,
      state: state,
      headSnapshot: () => _Snapshot([
        _Head(
          sessionId: 'tgdog-s1',
          workBeadId: 'tg-1',
          isOpen: false,
          outcome: SessionHeadOutcome.succeeded,
        ),
      ]),
      onHeadChanges: (_) =>
          () => removed = true,
      dualRead: DualReadSessionObserver(
        mode: DualReadMode.observe,
        onRoundSummary: (sessionId, body) => notes.add((sessionId, body)),
      ),
    )..start();

    // The terminal session's own note landed at the join.
    expect(notes.map((n) => n.$1), ['tgdog-s1']);
    bridge.dispose();
    expect(removed, isTrue);
    expect(notes.last.$2, contains('"scope":"boot-final"'));
  });
}
