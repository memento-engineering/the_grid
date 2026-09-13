import 'package:beads_dart/beads_dart.dart';
import 'package:grid_cli/src/station_watch.dart';
import 'package:grid_cli/src/watch_predicate.dart';
import 'package:grid_runtime/grid_runtime.dart'
    show GateSweepSessionDisposition, GridIssueTypes;
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

/// A gate as MINTED — `bd create -t gate` carries no metadata; `blocks`/`node`
/// land on the stamping update a moment later.
Bead _unstampedGate({String id = 'tg-gate-1'}) =>
    Bead(id: id, issueType: GridIssueTypes.gate);

Bead _session(
  String id, {
  BeadStatus status = BeadStatus.open,
  Map<String, dynamic> metadata = const <String, dynamic>{
    'work_bead': 'tg-work-1',
  },
}) => Bead(
  id: id,
  issueType: GridIssueTypes.session,
  status: status,
  metadata: metadata,
);

/// The empty Fake baseline: a station whose state store held no open gate and
/// no live session when the watch attached.
StationBaseline _emptyBaseline() =>
    (openGates: <String>{}, liveSessions: <String>{});

StationFold _foldFrom([StationBaseline? baseline]) =>
    StationFold(baseline: () => baseline ?? _emptyBaseline());

List<StationWatchEvent> _foldAll(StationFold fold, List<GraphEvent> events) =>
    <StationWatchEvent>[for (final event in events) ...fold.fold(event)];

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

  group('parseStationPredicate — the station set', () {
    test('every literal in the set resolves and round-trips', () {
      for (final literal in kStationPredicateLiterals) {
        expect(
          parseStationPredicate(literal).literal,
          literal,
          reason: literal,
        );
      }
      expect(
        parseStationPredicate('resident-down'),
        isA<UntilStationKind>().having(
          (p) => p.kind,
          'kind',
          StationWatchEventKind.residentDown,
        ),
      );
      expect(parseStationPredicate('any'), isA<UntilAnyStationEvent>());
    });

    test('the substation-root work predicates are NOT in the station set', () {
      for (final literal in const ['bead-status=closed', 'ready-count=0']) {
        expect(
          () => parseStationPredicate(literal),
          throwsA(
            isA<WatchUntilRefusal>().having(
              (e) => e.message,
              'message',
              contains('CLOSED'),
            ),
          ),
          reason: literal,
        );
      }
    });

    test('--until any matches every kind but the heartbeat', () {
      const any = UntilAnyStationEvent();
      expect(
        any.accepts(const StationGateOpened(gate: 'g', bead: 'b', node: 'n')),
        isTrue,
      );
      expect(any.accepts(const StationZeroLive()), isTrue);
      expect(
        any.accepts(const StationHeartbeat(gates: 0, sessions: 0, ready: 0)),
        isFalse,
      );
    });

    test('only --until resident-down AWAITS the resident going down', () {
      expect(
        parseStationPredicate(
          'resident-down',
        ).awaits(StationWatchEventKind.residentDown),
        isTrue,
      );
      expect(
        parseStationPredicate('any').awaits(StationWatchEventKind.residentDown),
        isFalse,
      );
      expect(
        parseStationPredicate(
          'zero-live',
        ).awaits(StationWatchEventKind.residentDown),
        isFalse,
      );
    });

    test('armStationWatchUntil shares the substation flag rules', () {
      expect(armStationWatchUntil(), isNull);
      expect(armStationWatchUntil(forSeconds: '11'), isNull);
      expect(
        () => armStationWatchUntil(until: 'zero-live'),
        throwsA(isA<WatchUntilRefusal>()),
      );
      expect(
        () => armStationWatchUntil(
          until: 'zero-live',
          timeout: '60',
          forSeconds: '5',
        ),
        throwsA(isA<WatchUntilRefusal>()),
      );
      expect(
        armStationWatchUntil(until: 'any', timeout: '2700')!.timeout,
        const Duration(seconds: 2700),
      );
    });
  });

  group('StationFold — the station census', () {
    test('the mint + stamp pair announces exactly ONE gate.opened', () {
      final fold = _foldFrom();
      final events = _foldAll(fold, [
        const SnapshotInitialized(beadCount: 1, readyCount: 0),
        BeadCreated(_unstampedGate()),
        BeadUpdated(
          before: _unstampedGate(),
          after: _gate(),
          changedFields: const {'metadata'},
        ),
        // A later unrelated field change on an ALREADY-open gate must not
        // re-announce it.
        BeadUpdated(
          before: _gate(),
          after: _gate(blocks: 'tgdog-1'),
          changedFields: const {'priority'},
        ),
      ]);

      final opened = events.whereType<StationGateOpened>().toList();
      expect(opened, hasLength(1));
      expect(opened.single.gate, 'tg-gate-1');
      expect(opened.single.bead, 'tgdog-1');
      expect(opened.single.node, 'tg-1/route');
      expect(fold.openGateCount, 1);
    });

    test('closing and deleting a gate both end the park', () {
      final closing = _foldFrom();
      final closed = _foldAll(closing, [
        const SnapshotInitialized(beadCount: 1, readyCount: 0),
        BeadCreated(_gate()),
        BeadClosed(
          before: _gate(),
          after: _gate(status: BeadStatus.closed),
        ),
      ]);
      expect(closed.whereType<StationGateClosed>(), hasLength(1));
      expect(closing.openGateCount, 0);

      final deleting = _foldFrom();
      final deleted = _foldAll(deleting, [
        const SnapshotInitialized(beadCount: 1, readyCount: 0),
        BeadCreated(_gate()),
        BeadDeleted(_gate()),
      ]);
      expect(deleted.whereType<StationGateClosed>(), hasLength(1));
      expect(deleting.openGateCount, 0);
    });

    test('two live sessions going terminal emit zero-live exactly once', () {
      final fold = _foldFrom();
      final events = _foldAll(fold, [
        const SnapshotInitialized(beadCount: 0, readyCount: 0),
        BeadCreated(_session('tg-s1')),
        BeadCreated(_session('tg-s2')),
        BeadClosed(
          before: _session('tg-s1'),
          after: _session('tg-s1', status: BeadStatus.closed),
        ),
        BeadClosed(
          before: _session('tg-s2'),
          after: _session('tg-s2', status: BeadStatus.closed),
        ),
      ]);

      expect(events.whereType<StationSessionMinted>(), hasLength(2));
      expect(events.whereType<StationSessionTerminal>(), hasLength(2));
      expect(events.whereType<StationZeroLive>(), hasLength(1));
      expect(events.last, isA<StationZeroLive>());
      expect(fold.liveSessionCount, 0);
    });

    test('a BASELINE live set drains to zero-live too', () {
      // The baseline SnapshotInitialized carries counts only, so sessions that
      // were already live when the watch attached can only come from the
      // census — this is the case a stream-only fold would miss entirely.
      final fold = _foldFrom((
        openGates: <String>{'tg-gate-1'},
        liveSessions: <String>{'tg-s1', 'tg-s2'},
      ));
      final events = _foldAll(fold, [
        const SnapshotInitialized(beadCount: 3, readyCount: 4),
        BeadClosed(
          before: _session('tg-s1'),
          after: _session('tg-s1', status: BeadStatus.closed),
        ),
        BeadClosed(
          before: _session('tg-s2'),
          after: _session('tg-s2', status: BeadStatus.closed),
        ),
      ]);

      expect(events.whereType<StationZeroLive>(), hasLength(1));
      expect(fold.liveSessionCount, 0);
      expect(fold.openGateCount, 1);
    });

    test('an empty station never fires zero-live without having been live', () {
      final fold = _foldFrom();
      final events = _foldAll(fold, [
        const SnapshotInitialized(beadCount: 0, readyCount: 0),
        BeadCreated(_bead('tg-9')),
        const ReadySetChanged(entered: {'tg-9'}, exited: {}),
      ]);
      expect(events.whereType<StationZeroLive>(), isEmpty);
    });

    test('a session close carries its A48 disposition', () {
      final fold = _foldFrom();
      Bead closedWith(Map<String, dynamic> metadata) =>
          _session('tg-s1', status: BeadStatus.closed, metadata: metadata);

      final done = fold.fold(
        BeadClosed(
          before: _session('tg-s1'),
          after: closedWith(const {
            'work_bead': 'tg-work-1',
            'grid.outcome': 'complete',
          }),
        ),
      );
      expect(
        done.whereType<StationSessionTerminal>().single,
        isA<StationSessionTerminal>()
            .having(
              (e) => e.disposition,
              'disposition',
              GateSweepSessionDisposition.done,
            )
            .having((e) => e.workBead, 'workBead', 'tg-work-1'),
      );

      final held = fold.fold(
        BeadClosed(
          before: _session('tg-s2'),
          after: closedWith(const {'grid.escalation': 'breaker'}),
        ),
      );
      expect(
        held.whereType<StationSessionTerminal>().single.disposition,
        GateSweepSessionDisposition.held,
      );

      final voided = fold.fold(
        BeadClosed(
          before: _session('tg-s3'),
          after: closedWith(const <String, dynamic>{}),
        ),
      );
      expect(
        voided.whereType<StationSessionTerminal>().single.disposition,
        GateSweepSessionDisposition.voided,
      );
    });

    test('the heartbeat carries gates, sessions and ready counts', () {
      final fold = _foldFrom((
        openGates: <String>{'tg-gate-1'},
        liveSessions: <String>{'tg-s1'},
      ));
      final baseline = _foldAll(fold, [
        const SnapshotInitialized(beadCount: 6, readyCount: 3),
      ]);

      // The baseline census IS the first heartbeat.
      expect(
        baseline.single,
        isA<StationHeartbeat>()
            .having((e) => e.gates, 'gates', 1)
            .having((e) => e.sessions, 'sessions', 1)
            .having((e) => e.ready, 'ready', 3),
      );

      fold.fold(const ReadySetChanged(entered: {'a', 'b'}, exited: {'c'}));
      fold.fold(BeadCreated(_session('tg-s2')));
      expect(
        fold.heartbeat(),
        isA<StationHeartbeat>()
            .having((e) => e.gates, 'gates', 1)
            .having((e) => e.sessions, 'sessions', 2)
            .having((e) => e.ready, 'ready', 4),
      );
    });

    test('a ready delta before the baseline is LOUD, never a silent count', () {
      expect(
        () => _foldFrom().fold(
          const ReadySetChanged(entered: {}, exited: {'tg-1'}),
        ),
        throwsStateError,
      );
    });
  });
}
