import 'package:beads_dart/beads_dart.dart';
import 'package:grid_cli/src/watch_predicate.dart';
import 'package:grid_runtime/grid_runtime.dart' show GridIssueTypes;
import 'package:test/test.dart';

Bead _gate({
  String id = 'tg-gate-1',
  String blocks = 'tgdog-1',
  BeadStatus status = BeadStatus.open,
}) => Bead(
  id: id,
  issueType: GridIssueTypes.gate,
  status: status,
  metadata: <String, dynamic>{'blocks': blocks, 'node': 'tg-1/route'},
);

Bead _bead(
  String id, {
  BeadStatus status = BeadStatus.open,
  IssueType type = IssueType.task,
}) => Bead(id: id, issueType: type, status: status);

void main() {
  group('parseWatchPredicate — the closed set', () {
    test('every literal in the set resolves to its predicate', () {
      expect(parseWatchPredicate('gate-open'), isA<UntilGateOpen>());
      expect(parseWatchPredicate('gate-closed'), isA<UntilGateClosed>());
      expect(
        parseWatchPredicate('session-terminal'),
        isA<UntilSessionTerminal>(),
      );
      expect(parseWatchPredicate('ready-count=0'), isA<UntilReadyCountZero>());
      expect(
        parseWatchPredicate('bead-status=closed'),
        isA<UntilBeadStatus>().having(
          (p) => p.status,
          'status',
          BeadStatus.closed,
        ),
      );
    });

    test('every predicate round-trips through its literal', () {
      for (final literal in const [
        'gate-open',
        'gate-closed',
        'session-terminal',
        'ready-count=0',
        'bead-status=in_progress',
      ]) {
        expect(parseWatchPredicate(literal).literal, literal);
      }
    });

    test('station-down is NOT in the set and is refused', () {
      expect(
        kWatchPredicateLiterals.where((l) => l.startsWith('station-down')),
        isEmpty,
      );
      expect(
        () => parseWatchPredicate('station-down'),
        throwsA(
          isA<WatchUntilRefusal>().having(
            (e) => e.message,
            'message',
            contains('CLOSED'),
          ),
        ),
      );
    });

    test('a typo is refused LOUDLY rather than hanging to the timeout', () {
      expect(
        () => parseWatchPredicate('ready-count=3'),
        throwsA(isA<WatchUntilRefusal>()),
      );
      expect(
        () => parseWatchPredicate('bead-status=closd'),
        throwsA(
          isA<WatchUntilRefusal>().having(
            (e) => e.message,
            'message',
            allOf(contains('in_progress'), contains('deferred')),
          ),
        ),
      );
      expect(
        () => parseWatchPredicate('bead-status='),
        throwsA(isA<WatchUntilRefusal>()),
      );
    });
  });

  group('armWatchUntil', () {
    test('the legacy duration modes arm to null, untouched', () {
      expect(armWatchUntil(), isNull);
      expect(armWatchUntil(forSeconds: '11'), isNull);
    });

    test('--until without --timeout names the missing flag', () {
      expect(
        () => armWatchUntil(until: 'gate-open'),
        throwsA(
          isA<WatchUntilRefusal>().having(
            (e) => e.message,
            'message',
            contains('--timeout'),
          ),
        ),
      );
    });

    test('--until with --for-seconds names both flags', () {
      expect(
        () => armWatchUntil(until: 'gate-open', timeout: '60', forSeconds: '5'),
        throwsA(
          isA<WatchUntilRefusal>().having(
            (e) => e.message,
            'message',
            allOf(contains('--until'), contains('--for-seconds')),
          ),
        ),
      );
    });

    test('--timeout without --until names --until', () {
      expect(
        () => armWatchUntil(timeout: '60'),
        throwsA(
          isA<WatchUntilRefusal>().having(
            (e) => e.message,
            'message',
            contains('--until'),
          ),
        ),
      );
    });

    test('a non-positive or unparseable --timeout is refused', () {
      for (final bad in const ['0', '-3', 'abc']) {
        expect(
          () => armWatchUntil(until: 'gate-open', timeout: bad),
          throwsA(isA<WatchUntilRefusal>()),
        );
      }
    });

    test('the happy arming carries the predicate and the deadline', () {
      final armed = armWatchUntil(until: 'gate-open', timeout: '60')!;
      expect(armed.predicate, isA<UntilGateOpen>());
      expect(armed.timeout, const Duration(seconds: 60));
    });
  });

  group('gate-open keys on the OPEN GATE', () {
    PredicateEvaluator armed() => PredicateEvaluator(const UntilGateOpen());

    test('a minted open gate naming a session satisfies it', () {
      expect(armed().accepts(BeadCreated(_gate())), isTrue);
    });

    test('a gate whose blocks names no session does NOT', () {
      expect(armed().accepts(BeadCreated(_gate(blocks: ''))), isFalse);
    });

    test('a closed gate and a non-gate bead do NOT', () {
      expect(
        armed().accepts(BeadCreated(_gate(status: BeadStatus.closed))),
        isFalse,
      );
      expect(armed().accepts(BeadCreated(_bead('tg-9'))), isFalse);
    });

    test('the follow-up blocks stamp satisfies it (the two-write mint)', () {
      expect(
        armed().accepts(
          BeadUpdated(
            before: _gate(blocks: ''),
            after: _gate(),
            changedFields: const {'metadata'},
          ),
        ),
        isTrue,
      );
    });

    test('a later update on an already-open gate does NOT re-fire', () {
      expect(
        armed().accepts(
          BeadUpdated(
            before: _gate(),
            after: _gate(),
            changedFields: const {'priority'},
          ),
        ),
        isFalse,
      );
    });

    test('a reopened gate satisfies it', () {
      expect(
        armed().accepts(
          BeadReopened(
            before: _gate(status: BeadStatus.closed),
            after: _gate(),
          ),
        ),
        isTrue,
      );
    });
  });

  group('gate-closed is that same gate ceasing to be open', () {
    PredicateEvaluator armed() => PredicateEvaluator(const UntilGateClosed());

    test('closing an open gate satisfies it', () {
      expect(
        armed().accepts(
          BeadClosed(
            before: _gate(),
            after: _gate(status: BeadStatus.closed),
          ),
        ),
        isTrue,
      );
    });

    test('hard-deleting an open gate satisfies it', () {
      expect(armed().accepts(BeadDeleted(_gate())), isTrue);
    });

    test('closing a non-gate bead does NOT', () {
      expect(
        armed().accepts(
          BeadClosed(
            before: _bead('tg-9'),
            after: _bead('tg-9', status: BeadStatus.closed),
          ),
        ),
        isFalse,
      );
    });

    test('minting an open gate does NOT', () {
      expect(armed().accepts(BeadCreated(_gate())), isFalse);
    });
  });

  group('session-terminal', () {
    PredicateEvaluator armed() =>
        PredicateEvaluator(const UntilSessionTerminal());

    test('closing a session bead satisfies it', () {
      expect(
        armed().accepts(
          BeadClosed(
            before: _bead('tgdog-1', type: GridIssueTypes.session),
            after: _bead(
              'tgdog-1',
              type: GridIssueTypes.session,
              status: BeadStatus.closed,
            ),
          ),
        ),
        isTrue,
      );
    });

    test('closing a work bead does NOT', () {
      expect(
        armed().accepts(
          BeadClosed(
            before: _bead('tg-9'),
            after: _bead('tg-9', status: BeadStatus.closed),
          ),
        ),
        isFalse,
      );
    });

    test('creating a session bead does NOT', () {
      expect(
        armed().accepts(
          BeadCreated(_bead('tgdog-2', type: GridIssueTypes.session)),
        ),
        isFalse,
      );
    });
  });

  group('bead-status=<status>', () {
    test('a bead reaching the target status satisfies it', () {
      final armed = PredicateEvaluator(
        const UntilBeadStatus(BeadStatus.blocked),
      );
      expect(
        armed.accepts(
          BeadUpdated(
            before: _bead('tg-9'),
            after: _bead('tg-9', status: BeadStatus.blocked),
            changedFields: const {'status'},
          ),
        ),
        isTrue,
      );
    });

    test('a bead already at the target status does NOT re-fire', () {
      final armed = PredicateEvaluator(
        const UntilBeadStatus(BeadStatus.blocked),
      );
      expect(
        armed.accepts(
          BeadUpdated(
            before: _bead('tg-9', status: BeadStatus.blocked),
            after: _bead('tg-9', status: BeadStatus.blocked),
            changedFields: const {'priority'},
          ),
        ),
        isFalse,
      );
    });

    test('a close satisfies bead-status=closed', () {
      final armed = PredicateEvaluator(
        const UntilBeadStatus(BeadStatus.closed),
      );
      expect(
        armed.accepts(
          BeadClosed(
            before: _bead('tg-9'),
            after: _bead('tg-9', status: BeadStatus.closed),
          ),
        ),
        isTrue,
      );
    });

    test('a bead created AT the target status satisfies it', () {
      final armed = PredicateEvaluator(
        const UntilBeadStatus(BeadStatus.inProgress),
      );
      expect(
        armed.accepts(
          BeadCreated(_bead('tg-9', status: BeadStatus.inProgress)),
        ),
        isTrue,
      );
    });
  });

  group('ready-count=0 folds the baseline plus every delta', () {
    test('a baseline of zero satisfies it immediately', () {
      final armed = PredicateEvaluator(const UntilReadyCountZero());
      expect(
        armed.accepts(const SnapshotInitialized(beadCount: 4, readyCount: 0)),
        isTrue,
      );
    });

    test('a non-empty baseline drains to zero across deltas', () {
      final armed = PredicateEvaluator(const UntilReadyCountZero());
      expect(
        armed.accepts(const SnapshotInitialized(beadCount: 4, readyCount: 2)),
        isFalse,
      );
      expect(
        armed.accepts(const ReadySetChanged(entered: {}, exited: {'tg-1'})),
        isFalse,
      );
      expect(
        armed.accepts(const ReadySetChanged(entered: {}, exited: {'tg-2'})),
        isTrue,
      );
    });

    test('newly ready work keeps the count above zero', () {
      final armed = PredicateEvaluator(const UntilReadyCountZero());
      armed.accepts(const SnapshotInitialized(beadCount: 4, readyCount: 1));
      expect(
        armed.accepts(
          const ReadySetChanged(entered: {'tg-3'}, exited: {'tg-1'}),
        ),
        isFalse,
      );
    });

    test('a delta before the baseline is LOUD, never a silent false', () {
      final armed = PredicateEvaluator(const UntilReadyCountZero());
      expect(
        () =>
            armed.accepts(const ReadySetChanged(entered: {}, exited: {'tg-1'})),
        throwsStateError,
      );
    });
  });
}
