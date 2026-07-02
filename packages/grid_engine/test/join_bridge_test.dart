import 'dart:async';

import 'package:grid_controller/grid_controller.dart';
import 'package:grid_engine/grid_engine.dart';
import 'package:test/test.dart';

/// A [SnapshotSource] fake mirroring the real change-gated runtime: a broadcast
/// controller + a settable [current], emitting **only on a real change**.
///
/// [emit] both updates [current] and pushes — the way `GridControllerRuntime`
/// publishes a snapshot only after a non-empty diff.
class FakeSnapshotSource implements SnapshotSource {
  FakeSnapshotSource([this._current]);

  final _controller = StreamController<GraphSnapshot>.broadcast();
  GraphSnapshot? _current;

  @override
  Stream<GraphSnapshot> get snapshots => _controller.stream;

  @override
  GraphSnapshot? get current => _current;

  /// Publishes [snapshot] as a real change: updates [current] then emits.
  void emit(GraphSnapshot snapshot) {
    _current = snapshot;
    _controller.add(snapshot);
  }

  Future<void> close() => _controller.close();
}

/// Builds a work-graph snapshot from [beads] (every bead ready, for brevity).
GraphSnapshot graphOf(List<Bead> beads, {int tick = 0}) => GraphSnapshot.fromParts(
  beads: beads,
  dependencies: const [],
  readyIds: beads.map((b) => b.id),
  capturedAt: DateTime.fromMillisecondsSinceEpoch(tick),
);

/// A work bead.
Bead work(String id) => Bead(id: id, issueType: IssueType.feature, status: BeadStatus.open);

/// A the_grid session bead linked to [workBeadId], carrying the per-node cursor:
/// each step id in [completed] is marked `complete` at `'$workBeadId/$step'` (the
/// distinguishing payload the JOIN must pair + reflect on a change).
Bead session(
  String id, {
  required String workBeadId,
  Set<String> completed = const {},
  bool closed = false,
}) => Bead(
  id: id,
  issueType: IssueType.session,
  status: closed ? BeadStatus.closed : BeadStatus.open,
  metadata: {
    'rig': 'tgdog',
    'work_bead': workBeadId,
    for (final step in completed)
      ...nodeStateMetadata('$workBeadId/$step', StepState.complete),
  },
);

/// The cursor state of [node] in [s]'s session for [workBead], or null.
StepState? _stateOf(JoinedSnapshot s, String workBead, String node) =>
    s.sessionsByWorkBead[workBead]?.cursor[node]?.state;

/// Reads [notifier]'s value the consumer way (D-H rule 2: no public sync
/// accessor over reactive state): subscribe (`fireImmediately` delivers the
/// baseline), capture, unsubscribe.
JoinedSnapshot _read(JoinedSnapshotNotifier notifier) {
  late JoinedSnapshot value;
  final remove = notifier.addListener((s) => value = s);
  remove();
  return value;
}

void main() {
  group('StationJoinBridge', () {
    late FakeSnapshotSource workSrc;
    late FakeSnapshotSource stateSrc;

    setUp(() {
      workSrc = FakeSnapshotSource();
      stateSrc = FakeSnapshotSource();
    });

    tearDown(() async {
      await workSrc.close();
      await stateSrc.close();
    });

    test('a LATE subscriber sees the baseline join, not nothing', () {
      workSrc = FakeSnapshotSource(graphOf([work('w1')]));
      stateSrc = FakeSnapshotSource(
        graphOf([session('s1', workBeadId: 'w1', completed: {'agent'})]),
      );
      final bridge = StationJoinBridge(work: workSrc, state: stateSrc)..start();
      addTearDown(bridge.dispose);

      // Subscribe AFTER construction/start — must still see the seeded baseline.
      JoinedSnapshot? seen;
      final remove = bridge.notifier.addListener((s) => seen = s);
      remove();

      expect(seen, isNotNull);
      expect(seen!.graph.beadsById.keys, contains('w1'));
      expect(_stateOf(seen!, 'w1', 'w1/agent'), StepState.complete);
    });

    test('with no work baseline, the seed is JoinedSnapshot.empty', () {
      final bridge = StationJoinBridge(work: workSrc, state: stateSrc);
      addTearDown(bridge.dispose);
      expect(_read(bridge.notifier).graph.isEmpty, isTrue);
      expect(_read(bridge.notifier).sessionsByWorkBead, isEmpty);
    });

    test('one work change → exactly ONE push, new graph + unchanged sessions', () async {
      stateSrc = FakeSnapshotSource(
        graphOf([session('s1', workBeadId: 'w1', completed: {'agent'})]),
      );
      final bridge = StationJoinBridge(work: workSrc, state: stateSrc)..start();
      addTearDown(bridge.dispose);

      final pushes = <JoinedSnapshot>[];
      bridge.notifier.addListener(pushes.add); // fireImmediately defaults true.
      expect(pushes, hasLength(1), reason: 'baseline only, before any emission');

      workSrc.emit(graphOf([work('w1'), work('w2')], tick: 1));
      await pumpEventQueue(); // a stream event is delivered in a microtask.

      expect(pushes, hasLength(2), reason: 'exactly one push for one work change');
      final joined = pushes.last;
      expect(joined.graph.beadsById.keys, containsAll(<String>['w1', 'w2']));
      // Sessions came from the OTHER source's `.current` — unchanged.
      expect(_stateOf(joined, 'w1', 'w1/agent'), StepState.complete);
    });

    test('one cursor change → exactly ONE push, pairs work bead to its session', () async {
      workSrc = FakeSnapshotSource(graphOf([work('w1')]));
      stateSrc = FakeSnapshotSource(
        graphOf([session('s1', workBeadId: 'w1')]), // empty cursor
      );
      final bridge = StationJoinBridge(work: workSrc, state: stateSrc)..start();
      addTearDown(bridge.dispose);

      final pushes = <JoinedSnapshot>[];
      bridge.notifier.addListener(pushes.add);
      expect(pushes, hasLength(1));
      expect(pushes.last.sessionsByWorkBead['w1']?.cursor, isEmpty);

      // The cursor advances on the work_bead-linked session bead (agent done).
      stateSrc.emit(
        graphOf([session('s1', workBeadId: 'w1', completed: {'agent'})], tick: 1),
      );
      await pumpEventQueue();

      expect(pushes, hasLength(2), reason: 'exactly one push for one cursor change');
      // The JOIN pairs the work bead with its advanced session cursor.
      expect(_stateOf(pushes.last, 'w1', 'w1/agent'), StepState.complete);
      // Graph stayed the work source's `.current`.
      expect(pushes.last.graph.beadsById.keys, contains('w1'));
    });

    test('a no-op (neither source emits) → no push beyond the baseline', () {
      workSrc = FakeSnapshotSource(graphOf([work('w1')]));
      final bridge = StationJoinBridge(work: workSrc, state: stateSrc)..start();
      addTearDown(bridge.dispose);

      final pushes = <JoinedSnapshot>[];
      bridge.notifier.addListener(pushes.add);
      expect(pushes, hasLength(1), reason: 'baseline seed only — nothing emitted');
    });

    test('a session bead with no work_bead linkage is skipped (no crash)', () {
      workSrc = FakeSnapshotSource(graphOf([work('w1')]));
      // A session bead with NO work_bead metadata at all + one valid one.
      final orphan = Bead(
        id: 's-orphan',
        issueType: IssueType.session,
        status: BeadStatus.open,
        metadata: const {'rig': 'tgdog'},
      );
      stateSrc = FakeSnapshotSource(graphOf([orphan, session('s1', workBeadId: 'w1')]));
      final bridge = StationJoinBridge(work: workSrc, state: stateSrc)..start();
      addTearDown(bridge.dispose);

      final joined = _read(bridge.notifier);
      // Orphan dropped; no '' key, no NoSuchMethod, no null-key crash.
      expect(joined.sessionsByWorkBead.keys, <String>['w1']);
      expect(joined.sessionsByWorkBead.containsKey(''), isFalse);
    });

    test('non-session beads in the state store are ignored', () {
      workSrc = FakeSnapshotSource(graphOf([work('w1')]));
      // A non-session bead that happens to carry a work_bead key must NOT join.
      final decoy = Bead(
        id: 'decoy',
        issueType: IssueType.task,
        status: BeadStatus.open,
        metadata: const {'work_bead': 'w1'},
      );
      stateSrc = FakeSnapshotSource(
        graphOf([decoy, session('s1', workBeadId: 'w1', completed: {'agent'})]),
      );
      final bridge = StationJoinBridge(work: workSrc, state: stateSrc)..start();
      addTearDown(bridge.dispose);

      // Only the real session contributes the cursor.
      expect(_stateOf(_read(bridge.notifier), 'w1', 'w1/agent'), StepState.complete);
      expect(_read(bridge.notifier).sessionsByWorkBead, hasLength(1));
    });

    test('terminal retention: a CLOSED session still appears (so WorkList unmounts)', () async {
      workSrc = FakeSnapshotSource(graphOf([work('w1')]));
      stateSrc = FakeSnapshotSource(graphOf([session('s1', workBeadId: 'w1')]));
      final bridge = StationJoinBridge(work: workSrc, state: stateSrc)..start();
      addTearDown(bridge.dispose);

      final pushes = <JoinedSnapshot>[];
      bridge.notifier.addListener(pushes.add);

      // The session closes — the positive terminal signal.
      stateSrc.emit(
        graphOf([session('s1', workBeadId: 'w1', closed: true)], tick: 1),
      );
      await pumpEventQueue();

      final terminal = pushes.last.sessionsByWorkBead['w1'];
      expect(terminal, isNotNull, reason: 'a terminal session must NOT be dropped from the join');
      expect(terminal!.isTerminal, isTrue);
    });

    test('start() re-seeds: a baseline landing in the construct→start gap is recovered', () async {
      // No `.current` at construction — the seed is JoinedSnapshot.empty.
      final bridge = StationJoinBridge(work: workSrc, state: stateSrc);
      addTearDown(bridge.dispose);
      expect(_read(bridge.notifier).graph.isEmpty, isTrue);

      // A first baseline lands in the gap BEFORE start() subscribes. The
      // broadcast stream does not replay, so the event itself is lost — but
      // the source's `.current` carries it, and start()'s re-seed recovers it.
      workSrc.emit(graphOf([work('w1')]));
      await pumpEventQueue();
      expect(_read(bridge.notifier).graph.isEmpty, isTrue, reason: 'gap event not yet recovered');

      bridge.start();
      expect(
        _read(bridge.notifier).graph.beadsById.keys,
        contains('w1'),
        reason: 'start() re-seeds from the sources\' `.current`, recovering the missed baseline',
      );
    });

    test('start() is idempotent — no double subscription, one push per change', () async {
      workSrc = FakeSnapshotSource(graphOf([work('w1')]));
      final bridge = StationJoinBridge(work: workSrc, state: stateSrc)
        ..start()
        ..start();
      addTearDown(bridge.dispose);

      final pushes = <JoinedSnapshot>[];
      bridge.notifier.addListener(pushes.add);
      expect(pushes, hasLength(1));

      workSrc.emit(graphOf([work('w1'), work('w2')], tick: 1));
      await pumpEventQueue();
      expect(pushes, hasLength(2), reason: 'a single subscription — one push, not two');
    });

    test('an injected notifier is driven but not disposed by the bridge', () async {
      workSrc = FakeSnapshotSource(graphOf([work('w1')]));
      final external = JoinedSnapshotNotifier(JoinedSnapshot.empty());
      final bridge = StationJoinBridge(work: workSrc, state: stateSrc, notifier: external)..start();

      final pushes = <JoinedSnapshot>[];
      external.addListener(pushes.add);
      workSrc.emit(graphOf([work('w1'), work('w2')], tick: 1));
      await pumpEventQueue();
      expect(pushes, hasLength(2));

      bridge.dispose();
      // Still usable after dispose — the bridge did not own it.
      expect(() => external.push(JoinedSnapshot.empty()), returnsNormally);
      external.dispose();
    });

    test('dispose() stops pushes and is idempotent', () async {
      workSrc = FakeSnapshotSource(graphOf([work('w1')]));
      final bridge = StationJoinBridge(work: workSrc, state: stateSrc)..start();

      final pushes = <JoinedSnapshot>[];
      bridge.notifier.addListener(pushes.add);
      expect(pushes, hasLength(1));

      bridge
        ..dispose()
        ..dispose(); // idempotent.

      // After dispose, an emission must not reach the (disposed) notifier.
      expect(() => workSrc.emit(graphOf([work('w2')], tick: 1)), returnsNormally);
      await pumpEventQueue();
      expect(pushes, hasLength(1), reason: 'no push after dispose');
    });
  });
}
