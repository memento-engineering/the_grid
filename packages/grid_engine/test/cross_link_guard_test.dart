// The state store's own `type=link` beads as the cross-store edge source for
// the federated frontier guard. Pure-Dart, Fakes only: no bd, no store, no I/O
// beyond reading this package's own sources for the read-only structural gate.
import 'dart:async';
import 'dart:io';

import 'package:beads_dart/beads_dart.dart';
import 'package:grid_engine/grid_engine.dart';
import 'package:test/test.dart';

/// A [SnapshotSource] fake mirroring the real change-gated runtime.
class FakeSource implements SnapshotSource {
  FakeSource([this._current]);

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

GraphSnapshot graphOf(List<Bead> beads, {Set<String>? readyIds, int tick = 0}) =>
    GraphSnapshot.fromParts(
      beads: beads,
      dependencies: const [],
      readyIds: readyIds ?? beads.map((b) => b.id).toSet(),
      capturedAt: DateTime.fromMillisecondsSinceEpoch(tick),
    );

Bead work(String id, {bool closed = false}) => Bead(
  id: id,
  issueType: IssueType.feature,
  status: closed ? BeadStatus.closed : BeadStatus.open,
);

/// A state-store link bead. [to] / [kind] are overridable so the malformed
/// cases are expressible.
Bead linkBead(
  String id, {
  required String from,
  String? to = 'pow-9',
  String? kind = kCrossLinkBlocks,
  bool closed = false,
}) => Bead(
  id: id,
  issueType: IssueType.link,
  status: closed ? BeadStatus.closed : BeadStatus.open,
  metadata: <String, dynamic>{
    CrossLinkKeys.from: from,
    if (to != null) CrossLinkKeys.to: to,
    if (kind != null) CrossLinkKeys.type: kind,
    CrossLinkKeys.reason: 'waits on the upstream port',
    CrossLinkKeys.actor: 'governor',
  },
);

/// Reads the notifier the consumer way (D-H rule 2: no public sync accessor
/// over reactive state) — subscribe (the baseline is delivered immediately),
/// capture, unsubscribe.
JoinedSnapshot read(JoinedSnapshotNotifier notifier) {
  late JoinedSnapshot value;
  final remove = notifier.addListener((s) => value = s);
  remove();
  return value;
}

void main() {
  late FakeSource workSrc;
  late FakeSource stateSrc;
  late List<String> loud;

  setUp(() {
    workSrc = FakeSource();
    stateSrc = FakeSource();
    loud = <String>[];
  });

  tearDown(() async {
    await workSrc.close();
    await stateSrc.close();
  });

  StationJoinBridge bridgeOf() => StationJoinBridge(
    work: workSrc,
    state: stateSrc,
    onUnresolvedCrossLink: loud.add,
  )..start();

  group('the state-store link edge source', () {
    test('an OPEN link blocks its `from` bead in the joined frontier while the '
        '`to` target is open', () {
      workSrc = FakeSource(graphOf([work('tg-1'), work('tg-2'), work('pow-9')]));
      stateSrc = FakeSource(
        graphOf([linkBead('houston-l1', from: 'tg-1')], readyIds: const {}),
      );
      final bridge = bridgeOf();
      addTearDown(bridge.dispose);

      final joined = read(bridge.notifier);
      expect(joined.graph.readyIds, isNot(contains('tg-1')));
      expect(
        joined.graph.readyIds,
        contains('tg-2'),
        reason: 'the sanity control — only the linked bead is held out',
      );
    });

    test('CLOSING the link bead retires the edge and re-admits the bead',
        () async {
      workSrc = FakeSource(graphOf([work('tg-1'), work('pow-9')]));
      stateSrc = FakeSource(
        graphOf([linkBead('houston-l1', from: 'tg-1')], readyIds: const {}),
      );
      final bridge = bridgeOf();
      addTearDown(bridge.dispose);
      expect(read(bridge.notifier).graph.readyIds, isNot(contains('tg-1')));

      stateSrc.emit(
        graphOf(
          [linkBead('houston-l1', from: 'tg-1', closed: true)],
          readyIds: const {},
          tick: 1,
        ),
      );
      await Future<void>.delayed(Duration.zero);

      expect(read(bridge.notifier).graph.readyIds, contains('tg-1'));
    });

    test('CLOSING the `to` target re-admits the bead while the link stays open',
        () async {
      workSrc = FakeSource(graphOf([work('tg-1'), work('pow-9')]));
      stateSrc = FakeSource(
        graphOf([linkBead('houston-l1', from: 'tg-1')], readyIds: const {}),
      );
      final bridge = bridgeOf();
      addTearDown(bridge.dispose);
      expect(read(bridge.notifier).graph.readyIds, isNot(contains('tg-1')));

      workSrc.emit(
        graphOf(
          [work('tg-1'), work('pow-9', closed: true)],
          readyIds: {'tg-1', 'pow-9'},
          tick: 1,
        ),
      );
      await Future<void>.delayed(Duration.zero);

      expect(read(bridge.notifier).graph.readyIds, contains('tg-1'));
    });

    test('a `to` target NO federated member observes blocks fail-closed and is '
        'LOUD about both ids', () {
      workSrc = FakeSource(graphOf([work('tg-1')]));
      stateSrc = FakeSource(
        graphOf([
          linkBead('houston-l1', from: 'tg-1', to: 'space-404'),
        ], readyIds: const {}),
      );
      final bridge = bridgeOf();
      addTearDown(bridge.dispose);

      expect(read(bridge.notifier).graph.readyIds, isNot(contains('tg-1')));
      expect(loud, isNotEmpty);
      expect(loud.last, contains('tg-1'));
      expect(loud.last, contains('space-404'));
      expect(loud.last, contains('fail-closed'));
    });

    test('a MALFORMED link (no `to`, or an unknown `type`) blocks fail-closed '
        'and names the link bead id', () {
      workSrc = FakeSource(graphOf([work('tg-1'), work('tg-2'), work('pow-9')]));
      stateSrc = FakeSource(
        graphOf([
          linkBead('houston-noto', from: 'tg-1', to: null),
          linkBead('houston-kind', from: 'tg-2', kind: 'relates'),
        ], readyIds: const {}),
      );
      final bridge = bridgeOf();
      addTearDown(bridge.dispose);

      final ready = read(bridge.notifier).graph.readyIds;
      expect(ready, isNot(contains('tg-1')));
      expect(ready, isNot(contains('tg-2')));
      expect(loud.any((m) => m.contains('houston-noto')), isTrue);
      expect(loud.any((m) => m.contains('houston-kind')), isTrue);
      expect(
        ready,
        contains('pow-9'),
        reason: 'the sanity control — an unlinked bead is untouched',
      );
    });

    test('a link naming no `from` is reported LOUDLY and blocks nothing', () {
      workSrc = FakeSource(graphOf([work('tg-1')]));
      stateSrc = FakeSource(
        graphOf([
          const Bead(
            id: 'houston-bad',
            issueType: IssueType.link,
            metadata: <String, dynamic>{CrossLinkKeys.to: 'pow-9'},
          ),
        ], readyIds: const {}),
      );
      final bridge = bridgeOf();
      addTearDown(bridge.dispose);

      expect(read(bridge.notifier).graph.readyIds, contains('tg-1'));
      expect(loud.any((m) => m.contains('houston-bad')), isTrue);
    });

    test('a link enforces even when both ids share a store prefix — no store\'s '
        '`is_blocked` knows about an operator-authored edge', () {
      workSrc = FakeSource(graphOf([work('tg-1'), work('tg-9')]));
      stateSrc = FakeSource(
        graphOf([
          linkBead('houston-l1', from: 'tg-1', to: 'tg-9'),
        ], readyIds: const {}),
      );
      final bridge = bridgeOf();
      addTearDown(bridge.dispose);

      expect(read(bridge.notifier).graph.readyIds, isNot(contains('tg-1')));
    });

    test('with nothing excluded the join returns the work snapshot INSTANCE — '
        'no per-join copy', () {
      // pow-9 is CLOSED, so the (well-formed, open) link excludes nothing.
      final snapshot = graphOf([
        work('tg-1'),
        work('pow-9', closed: true),
      ], readyIds: {'tg-1'});
      workSrc = FakeSource(snapshot);
      stateSrc = FakeSource(
        graphOf([
          linkBead('houston-l1', from: 'tg-1', to: 'pow-9'),
        ], readyIds: const {}),
      );
      final bridge = bridgeOf();
      addTearDown(bridge.dispose);

      expect(read(bridge.notifier).graph.readyIds, contains('tg-1'));
      expect(identical(read(bridge.notifier).graph, snapshot), isTrue);
    });

    test('a `type=link` bead never leaks into a session projection', () {
      workSrc = FakeSource(graphOf([work('tg-1')]));
      stateSrc = FakeSource(
        graphOf([linkBead('houston-l1', from: 'tg-1')], readyIds: const {}),
      );
      final bridge = bridgeOf();
      addTearDown(bridge.dispose);

      expect(read(bridge.notifier).sessionsByWorkBead, isEmpty);
    });
  });

  group('the LOUD-not-assume seeded-type refusal', () {
    test('a store WITH the type seeded is accepted (the pinned `bd types` '
        'shape: custom_types is a list of plain strings)', () {
      expect(
        crossLinkTypeRefusal(const <String, dynamic>{
          'custom_types': ['session', 'link'],
        }, store: 'houston'),
        isNull,
      );
    });

    test('a `{name: …}` entry shape is accepted too', () {
      expect(
        crossLinkTypeRefusal(const <String, dynamic>{
          'custom_types': [
            {'name': 'link', 'description': 'a cross-repo edge'},
          ],
        }, store: 'houston'),
        isNull,
      );
    });

    test('a store WITHOUT it is refused, naming the store and types.custom', () {
      final refusal = crossLinkTypeRefusal(const <String, dynamic>{
        'custom_types': ['session'],
      }, store: 'houston');
      expect(refusal, isNotNull);
      expect(refusal!, contains('houston'));
      expect(refusal, contains('types.custom'));
      expect(refusal, contains('link'));
    });
  });

  group('the fold is READ-ONLY (zero writes to any store)', () {
    test('the cross-link source names no writer, bd service, or process', () {
      for (final path in const [
        'lib/src/domain/cross_link.dart',
        'lib/src/bridge/block_guard.dart',
      ]) {
        final src = File(path).readAsStringSync();
        for (final forbidden in const [
          'StationBeadWriter',
          'BdCliService',
          'BdRunner',
          'ServiceBundle',
          'Process',
          'dart:io',
        ]) {
          expect(
            src.contains(forbidden),
            isFalse,
            reason:
                '$path must stay a pure read projection — "$forbidden" would '
                'give the link fold a write path into a store the_grid does '
                'not own.',
          );
        }
      }
    });
  });
}
