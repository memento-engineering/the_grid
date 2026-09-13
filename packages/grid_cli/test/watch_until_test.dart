import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:args/command_runner.dart';
import 'package:beads_dart/beads_dart.dart';
import 'package:grid_cli/src/event_renderer.dart';
import 'package:grid_cli/src/station_lock.dart';
import 'package:grid_cli/src/station_watch.dart';
import 'package:grid_cli/src/watch_command.dart';
import 'package:grid_cli/src/watch_predicate.dart';
import 'package:grid_diagnostics_contract/grid_diagnostics_contract.dart'
    show StationLockRecord;
import 'package:grid_runtime/grid_runtime.dart' show GridIssueTypes;
import 'package:test/test.dart';

final _at = DateTime.utc(2026, 9, 3, 22, 45);

Bead _gate() => Bead(
  id: 'tg-gate-1',
  issueType: GridIssueTypes.gate,
  metadata: <String, dynamic>{'blocks': 'tgdog-1', 'node': 'tg-1/route'},
);

Bead _task(String id) => Bead(id: id, title: 'work');

Bead _session(String id, {BeadStatus status = BeadStatus.open}) => Bead(
  id: id,
  issueType: GridIssueTypes.session,
  status: status,
  metadata: const <String, dynamic>{'work_bead': 'tg-work-1'},
);

/// THE Fake state store: the typed event stream a grid state store would emit,
/// plus the baseline census the runtime's snapshot would supply. No store, no
/// Dolt, no bd — the fold and the loop see exactly what they see in production.
final class _FakeStateStore {
  _FakeStateStore({
    Set<String> openGates = const <String>{},
    Set<String> liveSessions = const <String>{},
  }) : _baseline = (
         openGates: openGates.toSet(),
         liveSessions: liveSessions.toSet(),
       );

  final StationBaseline _baseline;
  final StreamController<GraphEvent> _events = StreamController<GraphEvent>();

  Stream<GraphEvent> get events => _events.stream;

  StationFold get fold => StationFold(baseline: () => _baseline);

  void emit(GraphEvent event) => _events.add(event);

  Future<void> close() => _events.close();
}

/// THE Fake lock: a REAL `<home>/.grid/station.lock` under a temp grid home,
/// read by the real probe with a faked pid liveness. `remove()` is the station
/// going away.
final class _FakeResidentLock {
  _FakeResidentLock(this._home);

  final Directory _home;
  bool pidAlive = true;

  static Future<_FakeResidentLock> arm() async {
    final home = await Directory.systemTemp.createTemp('grid-watch-home');
    final lock = _FakeResidentLock(home);
    await File(
      StationLockService.lockPath(home.path),
    ).parent.create(recursive: true);
    await File(StationLockService.lockPath(home.path)).writeAsString(
      jsonEncode(
        StationLockRecord(
          pid: 4242,
          pgid: 4242,
          startedAt: DateTime.utc(2026, 9, 13, 12),
        ).toJson(),
      ),
    );
    return lock;
  }

  String get home => _home.path;

  Future<ResidentState> probe() =>
      probeStationResident(gridHome: home, isPidAlive: (_) => pidAlive);

  Future<void> remove() => File(StationLockService.lockPath(home)).delete();

  Future<void> dispose() => _home.delete(recursive: true);
}

/// A resident that is simply there — the probe for every test whose subject is
/// the event stream rather than liveness.
Future<ResidentState> _residentUp() async => const ResidentLive(4242);

void main() {
  test('gate-open exits 0 and the satisfying event is the LAST line', () async {
    final controller = StreamController<GraphEvent>();
    final renderer = EventRenderer(json: true);
    final lines = <String>[];
    final exit = awaitPredicate(
      events: controller.stream,
      evaluator: PredicateEvaluator(const UntilGateOpen()),
      timeout: const Duration(seconds: 60),
      render: (event) => lines.add(renderer.render(event, at: _at)),
    );

    controller.add(const SnapshotInitialized(beadCount: 3, readyCount: 1));
    controller.add(BeadCreated(_task('tg-9')));
    controller.add(BeadCreated(_gate()));
    controller.add(BeadCreated(_task('tg-10')));

    expect(await exit, kWatchUntilSatisfied);
    expect(lines, hasLength(3));
    final last = jsonDecode(lines.last) as Map<String, dynamic>;
    final event = last['event']! as Map<String, dynamic>;
    expect(event['type'], 'beadCreated');
    expect((event['bead']! as Map<String, dynamic>)['id'], 'tg-gate-1');
    expect((event['bead']! as Map<String, dynamic>)['issueType'], 'gate');
    await controller.close();
  });

  test('an unmet predicate exits 2 and writes no satisfying line', () async {
    final controller = StreamController<GraphEvent>();
    final renderer = EventRenderer(json: true);
    final lines = <String>[];
    final exit = awaitPredicate(
      events: controller.stream,
      evaluator: PredicateEvaluator(const UntilGateOpen()),
      timeout: const Duration(milliseconds: 40),
      render: (event) => lines.add(renderer.render(event, at: _at)),
    );

    controller.add(const SnapshotInitialized(beadCount: 1, readyCount: 1));
    controller.add(BeadCreated(_task('tg-9')));

    expect(await exit, kWatchUntilTimedOut);
    expect(lines, hasLength(2));
    expect(lines.every((l) => !l.contains('tg-gate-1')), isTrue);
    await controller.close();
  });

  test('a broken event stream completes with the LOUD StateError', () async {
    final controller = StreamController<GraphEvent>();
    final exit = awaitPredicate(
      events: controller.stream,
      evaluator: PredicateEvaluator(const UntilReadyCountZero()),
      timeout: const Duration(seconds: 5),
      render: (_) {},
    );
    controller.add(const ReadySetChanged(entered: {}, exited: {'tg-1'}));
    await expectLater(exit, throwsStateError);
    await controller.close();
  });

  test(
    'every illegal --until combination exits 64 before any store is opened',
    () async {
      for (final args in <List<String>>[
        ['watch', '/no-such-substation-root', '--until', 'gate-open'],
        [
          'watch',
          '/no-such-substation-root',
          '--until',
          'gate-open',
          '--timeout',
          '60',
          '--for-seconds',
          '5',
        ],
        ['watch', '/no-such-substation-root', '--timeout', '60'],
        [
          'watch',
          '/no-such-substation-root',
          '--until',
          'station-down',
          '--timeout',
          '60',
        ],
        [
          'watch',
          '/no-such-substation-root',
          '--until',
          'gate-open',
          '--timeout',
          '0',
        ],
        [
          'watch',
          '/no-such-substation-root',
          '--until',
          'gate-open',
          '--timeout',
          'abc',
        ],
      ]) {
        final runner = CommandRunner<int>('grid', 'test')
          ..addCommand(WatchCommand());
        expect(await runner.run(args), 64, reason: args.join(' '));
      }
    },
  );

  group('grid watch --grid-home — the STATION watch', () {
    late StationWatchEventRenderer renderer;
    late List<String> lines;

    void render(StationWatchEvent event) =>
        lines.add(renderer.render(event, at: _at));

    setUp(() {
      renderer = StationWatchEventRenderer(json: false);
      lines = <String>[];
    });

    test('a gate opening emits ONE gate.opened line and exits 0', () async {
      final store = _FakeStateStore();
      final exit = awaitStationWatch(
        events: store.events,
        fold: store.fold,
        probeResident: _residentUp,
        render: render,
        until: armStationWatchUntil(until: 'gate-open', timeout: '60'),
      );

      store
        ..emit(const SnapshotInitialized(beadCount: 2, readyCount: 1))
        // The mint carries no metadata; `blocks`/`node` land on the stamping
        // update — ONE gate.opened across the pair, on the edge into open.
        ..emit(
          BeadCreated(Bead(id: 'tg-gate-1', issueType: GridIssueTypes.gate)),
        )
        ..emit(
          BeadUpdated(
            before: Bead(id: 'tg-gate-1', issueType: GridIssueTypes.gate),
            after: _gate(),
            changedFields: const {'metadata'},
          ),
        );

      expect(await exit, kWatchUntilSatisfied);
      expect(lines.where((l) => l.contains('gate.opened')), hasLength(1));
      expect(lines.last, contains('gate.opened tg-gate-1 tgdog-1 tg-1/route'));
      await store.close();
    });

    test('removing the lock emits resident.down and exits 3', () async {
      final store = _FakeStateStore();
      final lock = await _FakeResidentLock.arm();
      addTearDown(lock.dispose);

      final exit = awaitStationWatch(
        events: store.events,
        fold: store.fold,
        probeResident: lock.probe,
        render: render,
        until: armStationWatchUntil(until: 'zero-live', timeout: '60'),
        residentPoll: const Duration(milliseconds: 10),
      );
      store.emit(const SnapshotInitialized(beadCount: 0, readyCount: 0));
      await lock.remove();

      expect(await exit, kWatchResidentDown);
      expect(lines.last, contains('resident.down lock_missing'));
      await store.close();
    });

    test('a DEAD pid is resident.down too, naming the pid', () async {
      final store = _FakeStateStore();
      final lock = await _FakeResidentLock.arm();
      addTearDown(lock.dispose);

      final exit = awaitStationWatch(
        events: store.events,
        fold: store.fold,
        probeResident: lock.probe,
        render: render,
        until: armStationWatchUntil(until: 'zero-live', timeout: '60'),
        residentPoll: const Duration(milliseconds: 10),
      );
      lock.pidAlive = false;

      expect(await exit, kWatchResidentDown);
      expect(lines.last, contains('resident.down pid_dead pid 4242'));
      await store.close();
    });

    test('--until resident-down makes it the AWAITED event (exit 0)', () async {
      final store = _FakeStateStore();
      final lock = await _FakeResidentLock.arm();
      addTearDown(lock.dispose);

      final exit = awaitStationWatch(
        events: store.events,
        fold: store.fold,
        probeResident: lock.probe,
        render: render,
        until: armStationWatchUntil(until: 'resident-down', timeout: '60'),
        residentPoll: const Duration(milliseconds: 10),
      );
      await lock.remove();

      expect(await exit, kWatchUntilSatisfied);
      expect(lines.last, contains('resident.down lock_missing'));
      await store.close();
    });

    test(
      'two live sessions going terminal emit ONE zero-live, exit 0',
      () async {
        final store = _FakeStateStore();
        final exit = awaitStationWatch(
          events: store.events,
          fold: store.fold,
          probeResident: _residentUp,
          render: render,
          until: armStationWatchUntil(until: 'zero-live', timeout: '60'),
        );

        store
          ..emit(const SnapshotInitialized(beadCount: 0, readyCount: 0))
          ..emit(BeadCreated(_session('tg-s1')))
          ..emit(BeadCreated(_session('tg-s2')))
          ..emit(
            BeadClosed(
              before: _session('tg-s1'),
              after: _session('tg-s1', status: BeadStatus.closed),
            ),
          )
          ..emit(
            BeadClosed(
              before: _session('tg-s2'),
              after: _session('tg-s2', status: BeadStatus.closed),
            ),
          );

        expect(await exit, kWatchUntilSatisfied);
        expect(lines.where((l) => l.contains('zero-live')), hasLength(1));
        expect(lines.last, contains('zero-live'));
        expect(
          lines.where((l) => l.contains('session.terminal')),
          hasLength(2),
        );
        await store.close();
      },
    );

    test(
      '--json emits one parseable object per event, heartbeat included',
      () async {
        renderer = StationWatchEventRenderer(json: true);
        final store = _FakeStateStore(
          openGates: const {'tg-gate-0'},
          liveSessions: const {'tg-s0'},
        );
        final exit = awaitStationWatch(
          events: store.events,
          fold: store.fold,
          probeResident: _residentUp,
          render: render,
          // `any` must NOT be satisfied by the heartbeat, or the governor's
          // standing arming would return every N minutes with nothing to act on.
          until: armStationWatchUntil(until: 'any', timeout: '60'),
        );

        store
          ..emit(const SnapshotInitialized(beadCount: 4, readyCount: 3))
          ..emit(BeadCreated(_session('tg-s1')));

        expect(await exit, kWatchUntilSatisfied);
        final records = lines
            .map((line) => jsonDecode(line) as Map<String, dynamic>)
            .toList();
        expect(records, hasLength(2));
        expect(records.first['event'], 'heartbeat');
        expect(records.first['gates'], 1);
        expect(records.first['sessions'], 1);
        expect(records.first['ready'], 3);
        expect(records.first['ts'], isA<String>());
        expect(records.last['event'], 'session.minted');
        expect(records.last['bead'], 'tg-s1');
        expect(records.last['workBead'], 'tg-work-1');
        await store.close();
      },
    );

    test('--timeout expiry exits 2 with no satisfying line', () async {
      final store = _FakeStateStore();
      final exit = awaitStationWatch(
        events: store.events,
        fold: store.fold,
        probeResident: _residentUp,
        render: render,
        until: StationWatchUntil(
          predicate: parseStationPredicate('zero-live'),
          timeout: const Duration(milliseconds: 40),
        ),
      );
      store.emit(const SnapshotInitialized(beadCount: 0, readyCount: 0));

      expect(await exit, kWatchUntilTimedOut);
      expect(lines.every((l) => !l.contains('zero-live')), isTrue);
      await store.close();
    });

    test('--for-seconds style runFor exits 0 when nothing happened', () async {
      final store = _FakeStateStore();
      final exit = awaitStationWatch(
        events: store.events,
        fold: store.fold,
        probeResident: _residentUp,
        render: render,
        runFor: const Duration(milliseconds: 20),
      );
      expect(await exit, kWatchUntilSatisfied);
      await store.close();
    });

    test(
      'the heartbeat BEATS on its own cadence, carrying the census',
      () async {
        final store = _FakeStateStore(
          openGates: const {'tg-gate-0', 'tg-gate-1'},
          liveSessions: const {'tg-s0'},
        );
        final exit = awaitStationWatch(
          events: store.events,
          fold: store.fold,
          probeResident: _residentUp,
          render: render,
          heartbeatEvery: const Duration(milliseconds: 15),
          runFor: const Duration(milliseconds: 80),
        );
        store.emit(const SnapshotInitialized(beadCount: 5, readyCount: 2));

        expect(await exit, kWatchUntilSatisfied);
        final beats = lines.where((l) => l.contains('heartbeat')).toList();
        // The attach census plus at least one timed beat.
        expect(beats.length, greaterThan(1));
        expect(beats.last, contains('gates 2 sessions 1 ready 2'));
        await store.close();
      },
    );

    test('--heartbeat parses minutes, 0 disables, a typo is LOUD', () {
      expect(
        parseStationHeartbeat(null),
        const Duration(minutes: kDefaultStationHeartbeatMinutes),
      );
      expect(parseStationHeartbeat('0'), isNull);
      expect(parseStationHeartbeat('12'), const Duration(minutes: 12));
      for (final bad in const ['-1', 'soon', '']) {
        expect(
          () => parseStationHeartbeat(bad),
          throwsA(isA<WatchUntilRefusal>()),
          reason: bad,
        );
      }
    });

    test(
      'every illegal --grid-home invocation exits 64 before any store',
      () async {
        for (final args in <List<String>>[
          // The two modes are exclusive.
          ['watch', '/no-such-root', '--grid-home', '/no-such-home'],
          // --heartbeat paces the station watch only.
          ['watch', '/no-such-root', '--heartbeat', '5'],
          // A substation-root predicate is not in the station set.
          [
            'watch',
            '--grid-home',
            '/no-such-home',
            '--until',
            'ready-count=0',
            '--timeout',
            '60',
          ],
          // The shared three-flag mode selector still applies.
          ['watch', '--grid-home', '/no-such-home', '--until', 'zero-live'],
          [
            'watch',
            '--grid-home',
            '/no-such-home',
            '--until',
            'any',
            '--timeout',
            '60',
            '--for-seconds',
            '5',
          ],
          ['watch', '--grid-home', '/no-such-home', '--heartbeat', 'soon'],
        ]) {
          final runner = CommandRunner<int>('grid', 'test')
            ..addCommand(WatchCommand());
          expect(await runner.run(args), 64, reason: args.join(' '));
        }
      },
    );

    test(
      'a legal arming over a missing grid home refuses at the STORE',
      () async {
        final runner = CommandRunner<int>('grid', 'test')
          ..addCommand(WatchCommand());
        expect(
          await runner.run([
            'watch',
            '--grid-home',
            '/no-such-grid-home',
            '--until',
            'any',
            '--timeout',
            '60',
          ]),
          1,
        );
      },
    );
  });
}
