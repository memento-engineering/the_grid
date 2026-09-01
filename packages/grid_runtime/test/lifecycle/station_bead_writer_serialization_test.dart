// D-1 — the chokepoint SERIALIZES per target id (ADR-0007 Amended / M4-P1
// Track C foundation, the race gate).
//
// #4732 makes each metadata merge a row-locked server transaction. The
// per-target-id queue remains defense-in-depth and guarantees deterministic
// same-id ordering. These tests pin that writer-level ordering independently
// of the upstream transaction. The sample payload keys are deliberately NEUTRAL
// (`meta.*`, not `grid.cursor.*`) — this suite proves the writer's generic
// per-target-id serialization, independent of any one caller's key schema
// (the flat `grid.cursor.*` model this file's keys once echoed retired with
// tg-eli phase 2). Zero I/O — pure fakes.
import 'dart:async';
import 'dart:io';

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

  /// Explicit replies by call index, returned after that call is released.
  Map<int, BdResult> replies = {};

  int get startedCount => startedIds.length;

  @override
  Future<BdResult> run(
    List<String> args, {
    Duration? timeout,
    String? stdin,
  }) async {
    if (args case ['update', '--help']) {
      return const BdResult(
        exitCode: 0,
        stdout: '--if-assignee --if-status',
        stderr: '',
      );
    }
    final idx = startedIds.length;
    final id = args.length >= 2 ? args[1] : (args.isNotEmpty ? args.first : '');
    startedIds.add(id);
    final gate = Completer<void>();
    _gates.add(gate);
    await gate.future;
    if (failIndexes.contains(idx)) {
      throw StateError('bd failed (call $idx)');
    }
    final reply = replies[idx];
    if (reply != null) return reply;
    return BdResult(
      exitCode: 0,
      stdout: '{"schema_version":1,"data":{"id":"$id"}}',
      stderr: '',
    );
  }

  void release(int i) => _gates[i].complete();
}

final class GatedGraphApplyRunner implements BdRunner {
  final List<List<String>> started = <List<String>>[];
  final List<Completer<void>> _gates = <Completer<void>>[];
  final List<Completer<void>> _starts = <Completer<void>>[];
  final Set<int> failIndexes = <int>{};

  @override
  Future<BdResult> run(
    List<String> args, {
    Duration? timeout,
    String? stdin,
  }) async {
    if (args.length < 3 || args[0] != 'create' || args[1] != '--graph') {
      throw StateError('unexpected non-graph call: $args');
    }
    final index = started.length;
    started.add(List<String>.unmodifiable(args));
    _startSignal(index).complete();
    final gate = Completer<void>();
    _gates.add(gate);
    await gate.future;
    if (failIndexes.contains(index)) {
      throw StateError('graph apply failed (call $index)');
    }
    return const BdResult(
      exitCode: 0,
      stdout: '{"schema_version":1,"data":{"ids":{"root":"tgdog-root"}}}',
      stderr: '',
    );
  }

  Future<void> waitForStarted(int count) => _startSignal(count - 1).future;

  void release(int index) => _gates[index].complete();

  Completer<void> _startSignal(int index) {
    while (_starts.length <= index) {
      _starts.add(Completer<void>());
    }
    return _starts[index];
  }
}

/// A [BdRunner] that simulates bd's row-locked metadata merge transaction.
class MergingBdRunner implements BdRunner {
  final Map<String, Map<String, String>> store = {};
  final Map<String, Future<void>> _tails = {};

  @override
  Future<BdResult> run(
    List<String> args, {
    Duration? timeout,
    String? stdin,
  }) async {
    final sub = args.isNotEmpty ? args.first : '';
    final id = args.length >= 2 ? args[1] : '';
    if (sub == 'update') {
      final patch = <String, String>{};
      for (var i = 0; i < args.length - 1; i++) {
        if (args[i] != '--set-metadata') continue;
        final assignment = args[i + 1];
        final separator = assignment.indexOf('=');
        if (separator < 0) continue;
        patch[assignment.substring(0, separator)] = assignment.substring(
          separator + 1,
        );
      }
      final prior = _tails[id] ?? Future<void>.value();
      final transaction = prior.then((_) async {
        final merged = Map<String, String>.from(store[id] ?? const {});
        await Future<void>.delayed(Duration.zero);
        merged.addAll(patch);
        store[id] = merged;
      });
      _tails[id] = transaction.catchError((_) {});
      await transaction;
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
  reader: _EmptyReader(),
  ownership: BeadOwnershipPredicate({'tgdog'}),
);

const _pourPlan = GraphApplyPlan(
  commitMessage: 'serialization test',
  nodes: <GraphNode>[GraphNode(key: 'root', title: 'Root', type: 'task')],
);

Future<Map<String, String>> _pour(StationBeadWriter writer, String sessionId) =>
    writer.createMolecule(
      _pourPlan,
      substation: 'tgdog',
      sessionId: sessionId,
      rootCrumbs: <String>['tgdog-work', sessionId],
    );

final class _EmptyReader implements BeadProbeReader {
  @override
  Future<Bead?> beadById(String id, {required Set<IssueType> types}) async =>
      null;
  @override
  Future<List<Bead>> openBeads({
    required Set<IssueType> types,
    Map<String, String> metadataAll = const {},
    Map<String, String> metadataAny = const {},
  }) async => const [];
  @override
  Future<List<Bead>> openSuperseding(Set<String> priorIds) async => const [];
}

void main() {
  group('D-1 — per-target-id serialization', () {
    test(
      'two concurrent updates on the SAME id run sequentially, never overlap',
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
      },
    );

    test(
      'updates on DISJOINT ids run concurrently (no false serialization)',
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
      },
    );

    test(
      'N concurrent disjoint-key updates on one bead LOSE NO KEY (the gate)',
      () async {
        final r = MergingBdRunner();
        final w = _writer(r);

        // Fire 5 concurrent updates, each writing ONE distinct metadata key.
        await Future.wait([
          for (var i = 0; i < 5; i++)
            w.update('tgdog-s', metadata: {'meta.n$i.state': 'complete'}),
        ]);

        // The writer orders the calls and the simulated server transaction
        // merges all five keys under its per-id lock.
        expect(r.store['tgdog-s'], hasLength(5));
        for (var i = 0; i < 5; i++) {
          expect(r.store['tgdog-s']!['meta.n$i.state'], 'complete');
        }
      },
    );

    test(
      'a failed op does not poison the chain — the next op still runs',
      () async {
        final r = GatedBdRunner()..failIndexes = {0};
        final w = _writer(r);

        final f1 = w.update('tgdog-s', metadata: {'meta.a.state': 'failed'});
        final f2 = w.update('tgdog-s', metadata: {'meta.b.state': 'running'});

        // Swallow f1's error (it is expected to throw).
        final f1Result = f1.then<Object?>(
          (_) => null,
          onError: (Object e) => e,
        );
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
      },
    );

    test('guard mismatch is not retried and the queue recovers', () async {
      const guardMismatchEnvelope =
          '{"schema_version":1,"data":{"error":"guard mismatch",'
          '"guard_mismatch":true}}';
      final r = GatedBdRunner()
        ..replies = {
          0: const BdResult(
            exitCode: 13,
            stdout: guardMismatchEnvelope,
            stderr: '',
          ),
        };
      final w = _writer(r);

      final first = w.update(
        'tgdog-s',
        metadata: const {'meta.a': 'stale'},
        ifStatus: BeadStatus.open,
      );
      final second = w.update(
        'tgdog-s',
        metadata: const {'meta.b': 'fresh'},
        ifStatus: BeadStatus.open,
      );
      await _settle();
      expect(r.startedCount, 1);
      r.release(0);
      await expectLater(first, throwsA(isA<OwnershipGuardRefused>()));
      await _settle();
      expect(r.startedCount, 2);
      r.release(1);
      await second;
      expect(r.startedCount, 2);
    });

    test(
      'two concurrent pours on one store serialize and finish within 15 seconds',
      () async {
        final runner = GatedGraphApplyRunner();
        final writer = _writer(runner);
        final first = _pour(writer, 'tgdog-session-a');
        final second = _pour(writer, 'tgdog-session-b');
        await runner.waitForStarted(1);

        expect(runner.started, hasLength(1));
        runner.release(0);
        await runner.waitForStarted(2);
        expect(runner.started, hasLength(2));
        runner.release(1);

        await Future.wait(<Future<Map<String, String>>>[
          first,
          second,
        ]).timeout(const Duration(seconds: 15));
      },
    );

    test('a failed pour does not poison the store queue', () async {
      final runner = GatedGraphApplyRunner()..failIndexes.add(0);
      final writer = _writer(runner);
      final first = _pour(
        writer,
        'tgdog-session-a',
      ).then<Object?>((value) => value, onError: (Object error) => error);
      final second = _pour(writer, 'tgdog-session-b');
      await runner.waitForStarted(1);

      runner.release(0);
      await runner.waitForStarted(2);
      expect(await first, isA<StateError>());
      expect(runner.started, hasLength(2));
      runner.release(1);
      await second;
    });

    test(
      'different store writers do not share a durable or process-global queue',
      () async {
        final runnerA = GatedGraphApplyRunner();
        final runnerB = GatedGraphApplyRunner();
        final first = _pour(_writer(runnerA), 'tgdog-session-a');
        final second = _pour(_writer(runnerB), 'tgdog-session-b');
        await Future.wait(<Future<void>>[
          runnerA.waitForStarted(1),
          runnerB.waitForStarted(1),
        ]);

        expect(runnerA.started, hasLength(1));
        expect(runnerB.started, hasLength(1));
        final source = File(
          'lib/src/lifecycle/station_bead_writer.dart',
        ).readAsStringSync();
        expect(source, contains('Future<void>? _storePourTail;'));
        expect(source, isNot(contains("import 'dart:io';")));
        expect(source, isNot(contains('DoltQueryService')));

        runnerA.release(0);
        runnerB.release(0);
        await Future.wait(<Future<Map<String, String>>>[first, second]);
      },
    );
  });
}
