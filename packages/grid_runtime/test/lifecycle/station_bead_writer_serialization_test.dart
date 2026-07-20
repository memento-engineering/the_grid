// D-1 — the chokepoint SERIALIZES per target id (ADR-0007 Amended / M4-P1
// Track C foundation, the race gate).
//
// `bd update --metadata` is a client-side read-modify-write with no row lock, so
// two concurrent updates on the SAME bead with DISJOINT keys can last-writer-win
// → a metadata key is lost → the barrier never opens (a silent liveness stall at
// depth). The per-target-id queue closes it. These tests fail on the
// un-serialized writer. The sample payload keys are deliberately NEUTRAL
// (`meta.*`, not `grid.cursor.*`) — this suite proves the writer's generic
// per-target-id serialization, independent of any one caller's key schema
// (the flat `grid.cursor.*` model this file's keys once echoed retired with
// tg-eli phase 2). Zero I/O — pure fakes.
import 'dart:async';
import 'dart:convert';

import 'package:beads_dart/beads_dart.dart';
import 'package:grid_runtime/grid_runtime.dart';
import 'package:test/test.dart';

/// Lets every microtask + zero-delay timer in the chain drain.
Future<void> _settle() async {
  for (var i = 0; i < 3; i++) {
    await Future<void>.delayed(Duration.zero);
  }
}

/// A [BdRunner] whose every call parks on a per-call gate, recording the id of
/// each call AS IT STARTS — so a test can observe whether a second op started
/// before the first was released (overlap = no serialization).
class GatedBdRunner implements BdRunner {
  final List<String> startedIds = [];
  final List<Completer<void>> _gates = [];

  /// Call indexes (0-based, in start order) whose op throws after release.
  Set<int> failIndexes = {};

  int get startedCount => startedIds.length;

  @override
  Future<BdResult> run(List<String> args, {Duration? timeout, String? stdin}) async {
    final idx = startedIds.length;
    final id = args.length >= 2 ? args[1] : (args.isNotEmpty ? args.first : '');
    startedIds.add(id);
    final gate = Completer<void>();
    _gates.add(gate);
    await gate.future;
    if (failIndexes.contains(idx)) {
      throw StateError('bd failed (call $idx)');
    }
    return BdResult(
      exitCode: 0,
      stdout: '{"schema_version":1,"data":{"id":"$id"}}',
      stderr: '',
    );
  }

  void release(int i) => _gates[i].complete();
}

/// A [BdRunner] that simulates bd's client-side read-modify-write metadata merge
/// WITH a race window (a yield between the read and the write), so concurrent
/// un-serialized updates clobber each other (the bug D-1 fixes), and serialized
/// updates apply cumulatively (the fix).
class MergingBdRunner implements BdRunner {
  final Map<String, Map<String, String>> store = {};

  @override
  Future<BdResult> run(List<String> args, {Duration? timeout, String? stdin}) async {
    final sub = args.isNotEmpty ? args.first : '';
    final id = args.length >= 2 ? args[1] : '';
    if (sub == 'update') {
      final i = args.indexOf('--metadata');
      final patch =
          (jsonDecode(args[i + 1]) as Map).cast<String, String>();
      // Read-modify-write with a RACE WINDOW between the read and the write.
      final merged = Map<String, String>.from(store[id] ?? const {});
      await Future<void>.delayed(Duration.zero); // the window
      merged.addAll(patch);
      store[id] = merged;
    }
    return BdResult(
      exitCode: 0,
      stdout: '{"schema_version":1,"data":{"id":"$id"}}',
      stderr: '',
    );
  }
}

StationBeadWriter _writer(BdRunner runner) => StationBeadWriter(
  bd: BdCliService(runner),
  ownership: BeadOwnershipPredicate({'tgdog'}),
);

void main() {
  group('D-1 — per-target-id serialization', () {
    test('two concurrent updates on the SAME id run sequentially, never overlap',
        () async {
      final r = GatedBdRunner();
      final w = _writer(r);

      final f1 = w.update('tgdog-s', metadata: {'meta.a.state': 'complete'});
      final f2 = w.update('tgdog-s', metadata: {'meta.b.state': 'running'});
      await _settle();

      expect(
        r.startedCount,
        1,
        reason: 'the second update must wait for the first (serialized)',
      );
      r.release(0);
      await _settle();
      expect(r.startedCount, 2, reason: 'released → the second now runs');
      r.release(1);
      await Future.wait([f1, f2]);
    });

    test('updates on DISJOINT ids run concurrently (no false serialization)',
        () async {
      final r = GatedBdRunner();
      final w = _writer(r);

      final fx = w.update('tgdog-x', metadata: {'meta.a.state': 'complete'});
      final fy = w.update('tgdog-y', metadata: {'meta.a.state': 'complete'});
      await _settle();

      expect(
        r.startedCount,
        2,
        reason: 'different ids are not serialized against each other',
      );
      r.release(0);
      r.release(1);
      await Future.wait([fx, fy]);
    });

    test('N concurrent disjoint-key updates on one bead LOSE NO KEY (the gate)',
        () async {
      final r = MergingBdRunner();
      final w = _writer(r);

      // Fire 5 concurrent updates, each writing ONE distinct metadata key.
      await Future.wait([
        for (var i = 0; i < 5; i++)
          w.update('tgdog-s', metadata: {'meta.n$i.state': 'complete'}),
      ]);

      // Serialized → all 5 keys present. The un-serialized writer's race window
      // would clobber down to 1 (last-writer-wins).
      expect(r.store['tgdog-s'], hasLength(5));
      for (var i = 0; i < 5; i++) {
        expect(r.store['tgdog-s']!['meta.n$i.state'], 'complete');
      }
    });

    test('a failed op does not poison the chain — the next op still runs',
        () async {
      final r = GatedBdRunner()..failIndexes = {0};
      final w = _writer(r);

      final f1 = w.update('tgdog-s', metadata: {'meta.a.state': 'failed'});
      final f2 = w.update('tgdog-s', metadata: {'meta.b.state': 'running'});

      // Swallow f1's error (it is expected to throw).
      final f1Result = f1.then<Object?>((_) => null, onError: (Object e) => e);
      await _settle();
      r.release(0); // f1 fails here
      await _settle();

      expect(await f1Result, isA<StateError>());
      expect(
        r.startedCount,
        2,
        reason: 'the failed op must not stall the queued one',
      );
      r.release(1);
      await f2;
    });
  });
}
